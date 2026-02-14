/**
 * Client PayTech (paytech.sn) - Mobile Money, Orange Money, Wave, etc.
 * Doc: https://doc.paytech.sn/
 * Mode test: env=test (montant débité 100-150 FCFA en test)
 */
const https = require('https');

const BASE_URL = 'https://paytech.sn';
const API_PATH = '/api';

function request(options, body = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(API_PATH + options.path, BASE_URL);
    const reqOpts = {
      hostname: url.hostname,
      port: 443,
      path: url.pathname + url.search,
      method: options.method || 'GET',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'API_KEY': options.apiKey || process.env.PAYTECH_API_KEY || '',
        'API_SECRET': options.apiSecret || process.env.PAYTECH_API_SECRET || ''
      }
    };
    if (body && (reqOpts.method === 'POST' || reqOpts.method === 'PATCH')) {
      reqOpts.headers['Content-Type'] = 'application/json';
    }
    const req = https.request(reqOpts, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          const json = data ? JSON.parse(data) : {};
          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve(json);
          } else {
            reject(new Error(json.message || json.error || `HTTP ${res.statusCode}`));
          }
        } catch (e) {
          reject(new Error(data || 'Invalid response'));
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(typeof body === 'string' ? body : JSON.stringify(body));
    req.end();
  });
}

/**
 * Créer une demande de paiement (redirection vers checkout PayTech)
 * @param {Object} params - item_name, item_price, ref_command, command_name, currency, env, ipn_url, success_url, cancel_url, custom_field, target_payment
 * @returns {Promise<{success: number, token: string, redirect_url: string}>}
 */
async function requestPayment(params) {
  const body = {
    item_name: params.item_name,
    item_price: params.item_price,
    ref_command: params.ref_command,
    command_name: params.command_name,
    currency: params.currency || 'XOF',
    env: params.env || process.env.PAYTECH_ENV || 'test',
    ipn_url: params.ipn_url,
    success_url: params.success_url,
    cancel_url: params.cancel_url,
    custom_field: params.custom_field,
    target_payment: params.target_payment || '' // "Orange Money", "Wave", "Orange Money, Wave", etc.
  };
  const res = await request({ method: 'POST', path: '/payment/request-payment' }, body);
  return {
    success: res.success,
    token: res.token,
    redirect_url: res.redirect_url || res.redirectUrl,
    message: res.message
  };
}

/**
 * Vérifier le statut d'un paiement
 * @param {string} tokenPayment - token retourné par request-payment
 * @returns {Promise<Object>}
 */
async function getPaymentStatus(tokenPayment) {
  const path = `/payment/get-status?token_payment=${encodeURIComponent(tokenPayment)}`;
  return request({ method: 'GET', path });
}

module.exports = {
  request,
  requestPayment,
  getPaymentStatus
};
