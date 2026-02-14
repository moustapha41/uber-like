const express = require('express');
const { body, validationResult } = require('express-validator');
const router = express.Router();
const paymentService = require('./service');
const { authenticate } = require('../../middleware/auth');
const { successResponse, errorResponse } = require('../../utils/response');

/**
 * POST /api/v1/payment/initiate
 * Initie un paiement Mobile Money (PayTech). Retourne l'URL de redirection checkout.
 * Body: amount, reference_type (ride|delivery|wallet_deposit), reference_id, success_url?, cancel_url?, phone?, target_payment?
 */
router.post('/initiate',
  authenticate,
  [
    body('amount').isFloat({ min: 100 }),
    body('reference_type').isIn(['ride', 'delivery', 'wallet_deposit']),
    body('reference_id').isInt({ min: 1 }),
    body('success_url').optional().isURL(),
    body('cancel_url').optional().isURL(),
    body('phone').optional().trim(),
    body('target_payment').optional().trim()
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return errorResponse(res, errors.array()[0].msg, 400);
      }
      const { amount, reference_type, reference_id, success_url, cancel_url, phone, target_payment } = req.body;
      const result = await paymentService.initiateMobileMoneyPayment({
        userId: req.user.userId,
        amount,
        reference_type,
        reference_id,
        success_url,
        cancel_url,
        phone,
        target_payment
      });
      return successResponse(res, result, 'Paiement initié, redirigez le client vers redirect_url');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/payment/ipn
 * Webhook PayTech (IPN). Pas d'auth - PayTech appelle cette URL.
 * Body: ref_command ou token_payment, success (1/0) ou state (completed/failed)
 */
router.post('/ipn', async (req, res) => {
  try {
    const body = req.body || {};
    const result = await paymentService.handlePayTechIPN(body);
    res.status(200).json({ success: true, ...result });
  } catch (error) {
    console.error('Payment IPN error:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

/**
 * GET /api/v1/payment/status/:ref_command
 * Statut d'une intention de paiement (par ref_command, ex: RIDE-123)
 */
router.get('/status/:ref_command', authenticate, async (req, res) => {
  try {
    const intent = await paymentService.getIntentByRefCommand(req.params.ref_command);
    if (!intent) return errorResponse(res, 'Intention non trouvée', 404);
    if (req.user.role !== 'admin' && intent.user_id !== req.user.userId) {
      return errorResponse(res, 'Non autorisé', 403);
    }
    return successResponse(res, intent, 'Statut récupéré');
  } catch (error) {
    return errorResponse(res, error.message, 500);
  }
});

module.exports = router;
