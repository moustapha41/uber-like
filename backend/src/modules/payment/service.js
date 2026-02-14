/**
 * Payment Service - PayTech Mobile Money + payment intents
 */
const pool = require('../../config/database');
const paytech = require('./paytech.client');
const walletService = require('../wallet/wallet.service');
const pricingService = require('../rides/pricing.service');
const logger = require('../../utils/logger');

const BASE_URL_APP = process.env.APP_BASE_URL || process.env.BASE_URL || 'http://localhost:3000';

function makeRefCommand(referenceType, referenceId) {
  const prefix = { ride: 'RIDE', delivery: 'DEL', wallet_deposit: 'DEP' }[referenceType] || 'PAY';
  return `${prefix}-${referenceId}`;
}

/**
 * Initier un paiement Mobile Money (PayTech) pour une course, livraison ou dépôt wallet
 * @param {Object} params - userId, amount, reference_type, reference_id, success_url, cancel_url, phone (optionnel), target_payment (optionnel)
 * @returns {Promise<{redirect_url, token, ref_command, payment_intent_id}>}
 */
async function initiateMobileMoneyPayment(params) {
  const { userId, amount, reference_type, reference_id, success_url, cancel_url, phone, target_payment } = params;
  const ref_command = makeRefCommand(reference_type, reference_id);

  const existing = await pool.query(
    'SELECT id, token, status FROM payment_intents WHERE ref_command = $1 AND status = $2',
    [ref_command, 'pending']
  );
  if (existing.rows.length > 0) {
    const row = existing.rows[0];
    const redirect_url = row.token ? `https://paytech.sn/payment/checkout/${row.token}` : null;
    return {
      redirect_url,
      token: row.token,
      ref_command,
      payment_intent_id: row.id
    };
  }

  const itemName = reference_type === 'ride' ? `Course #${reference_id}` : reference_type === 'delivery' ? `Livraison #${reference_id}` : `Dépôt wallet`;
  const ipnUrl = `${BASE_URL_APP}/api/v1/payment/ipn`;
  const paytechParams = {
    item_name: itemName,
    item_price: Math.round(amount),
    ref_command,
    command_name: itemName,
    currency: 'XOF',
    env: process.env.PAYTECH_ENV || 'test',
    ipn_url: ipnUrl,
    success_url: success_url || `${BASE_URL_APP}/payment/success?ref=${ref_command}`,
    cancel_url: cancel_url || `${BASE_URL_APP}/payment/cancel?ref=${ref_command}`,
    custom_field: JSON.stringify({ reference_type, reference_id, user_id: userId }),
    target_payment: target_payment || 'Orange Money, Wave'
  };

  const res = await paytech.requestPayment(paytechParams);
  if (!res.success || !res.redirect_url) {
    throw new Error(res.message || 'PayTech request failed');
  }

  const insert = await pool.query(
    `INSERT INTO payment_intents (ref_command, token, reference_type, reference_id, user_id, amount, currency, status, provider)
     VALUES ($1, $2, $3, $4, $5, $6, 'XOF', 'pending', 'paytech')
     RETURNING id`,
    [ref_command, res.token, reference_type, reference_id, userId, amount]
  );

  return {
    redirect_url: res.redirect_url,
    token: res.token,
    ref_command,
    payment_intent_id: insert.rows[0].id
  };
}

/**
 * Traiter la notification IPN (webhook) PayTech
 * PayTech envoie ref_command (ou token) et un indicateur de succès (format à confirmer dans la doc PayTech).
 * @param {Object} body - Corps de la requête IPN (JSON ou form)
 */
async function handlePayTechIPN(body) {
  let ref = body.ref_command;
  if (!ref && body.custom_field) {
    try {
      const cf = typeof body.custom_field === 'string' ? JSON.parse(body.custom_field) : body.custom_field;
      if (cf.reference_type && cf.reference_id) {
        ref = makeRefCommand(cf.reference_type, cf.reference_id);
      }
    } catch (_) {}
  }
  const token = body.token_payment || body.token;
  const success = body.success === 1 || body.success === true || body.success === '1' || (body.state && String(body.state).toLowerCase() === 'completed');

  let intent;
  if (ref) {
    intent = (await pool.query('SELECT * FROM payment_intents WHERE ref_command = $1', [ref])).rows[0];
  }
  if (!intent && token) {
    intent = (await pool.query('SELECT * FROM payment_intents WHERE token = $1', [token])).rows[0];
  }
  if (!intent) {
    logger.warn('PayTech IPN: no payment_intent found', { body: Object.keys(body) });
    return { processed: false, reason: 'intent_not_found' };
  }

  if (intent.status !== 'pending') {
    return { processed: true, already: intent.status };
  }

  if (success) {
    await pool.query(
      `UPDATE payment_intents SET status = 'completed', updated_at = NOW(), completed_at = NOW() WHERE id = $1`,
      [intent.id]
    );
    const { reference_type, reference_id } = intent;
    const amount = parseFloat(intent.amount);
    const pricingConfig = await pricingService.getActivePricingConfig(reference_type === 'ride' ? 'ride' : 'delivery');
    const commissionRate = parseFloat(pricingConfig.commission_rate) || 20;

    if (reference_type === 'ride') {
      const ride = (await pool.query('SELECT * FROM rides WHERE id = $1', [reference_id])).rows[0];
      if (ride && ride.payment_status === 'PAYMENT_PENDING') {
        await pool.query(
          `UPDATE rides SET payment_status = 'PAID', status = 'PAID', paid_at = NOW() WHERE id = $1`,
          [reference_id]
        );
        if (ride.driver_id) {
          await walletService.creditDriverForExternalPayment(reference_id, ride.client_id, ride.driver_id, amount, commissionRate);
        }
      }
    } else if (reference_type === 'delivery') {
      const deliv = (await pool.query('SELECT * FROM deliveries WHERE id = $1', [reference_id])).rows[0];
      if (deliv && deliv.payment_status === 'PAYMENT_PENDING') {
        await pool.query(
          `UPDATE deliveries SET payment_status = 'PAID', paid_at = NOW() WHERE id = $1`,
          [reference_id]
        );
        if (deliv.driver_id) {
          await walletService.creditDriverForDeliveryExternalPayment(reference_id, deliv.client_id, deliv.driver_id, amount, commissionRate);
        }
      }
    } else if (reference_type === 'wallet_deposit') {
      await walletService.credit(intent.user_id, amount, {
        reference_type: 'mobile_money',
        reference_id: intent.id,
        description: `Dépôt Mobile Money #${reference_id}`
      });
    }
    logger.info('PayTech IPN: payment completed', { ref_command: intent.ref_command, reference_type, reference_id });
    return { processed: true, status: 'completed' };
  }

  await pool.query(
    `UPDATE payment_intents SET status = 'failed', updated_at = NOW() WHERE id = $1`,
    [intent.id]
  );
  const { reference_type, reference_id } = intent;
  if (reference_type === 'ride') {
    await pool.query(`UPDATE rides SET payment_status = 'PAYMENT_FAILED' WHERE id = $1 AND payment_status = 'PAYMENT_PENDING'`, [reference_id]);
  } else if (reference_type === 'delivery') {
    await pool.query(`UPDATE deliveries SET payment_status = 'PAYMENT_FAILED' WHERE id = $1 AND payment_status = 'PAYMENT_PENDING'`, [reference_id]);
  }
  logger.info('PayTech IPN: payment failed', { ref_command: intent.ref_command });
  return { processed: true, status: 'failed' };
}

/**
 * Vérifier le statut d'un paiement côté PayTech
 */
async function getPaymentStatus(tokenPayment) {
  return paytech.getPaymentStatus(tokenPayment);
}

/**
 * Récupérer une intention par ref_command
 */
async function getIntentByRefCommand(refCommand) {
  const r = await pool.query('SELECT * FROM payment_intents WHERE ref_command = $1', [refCommand]);
  return r.rows[0] || null;
}

module.exports = {
  makeRefCommand,
  initiateMobileMoneyPayment,
  handlePayTechIPN,
  getPaymentStatus,
  getIntentByRefCommand
};
