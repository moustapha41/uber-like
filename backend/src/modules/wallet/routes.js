const express = require('express');
const router = express.Router();
const { body, query, validationResult } = require('express-validator');
const walletService = require('./wallet.service');
const { authenticate, authorize } = require('../../middleware/auth');
const { successResponse, errorResponse } = require('../../utils/response');

/**
 * Routes pour le module Wallet
 */

/**
 * GET /api/v1/wallet/balance
 * Récupère le solde de l'utilisateur connecté
 */
router.get('/balance', authenticate, async (req, res) => {
  try {
    const balance = await walletService.getBalance(req.user.userId);
    const wallet = await walletService.getWallet(req.user.userId);

    return successResponse(res, {
      balance,
      currency: wallet.currency,
      wallet_id: wallet.id
    });
  } catch (error) {
    return errorResponse(res, error.message, 500);
  }
});

/**
 * GET /api/v1/wallet/transactions
 * Récupère l'historique des transactions
 */
router.get('/transactions',
  authenticate,
  [
    query('type').optional().isIn(['credit', 'debit', 'refund', 'commission', 'withdrawal', 'deposit']),
    query('status').optional().isIn(['pending', 'completed', 'failed', 'cancelled']),
    query('reference_type').optional().isIn(['ride', 'delivery', 'carpool', 'manual', 'mobile_money']),
    query('limit').optional().isInt({ min: 1, max: 100 }),
    query('offset').optional().isInt({ min: 0 }),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return errorResponse(res, 'Validation failed', 400, errors.array());
      }

      const filters = {
        type: req.query.type,
        status: req.query.status,
        reference_type: req.query.reference_type,
        limit: parseInt(req.query.limit) || 50,
        offset: parseInt(req.query.offset) || 0
      };

      const transactions = await walletService.getTransactions(req.user.userId, filters);

      return successResponse(res, transactions);
    } catch (error) {
      return errorResponse(res, error.message, 500);
    }
  }
);

/**
 * POST /api/v1/wallet/deposit
 * Dépôt manuel (admin uniquement)
 */
router.post('/deposit',
  authenticate,
  authorize(['admin']),
  [
    body('user_id').isInt().withMessage('User ID is required'),
    body('amount').isFloat({ min: 1 }).withMessage('Amount must be greater than 0'),
    body('description').optional().isLength({ max: 500 }),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return errorResponse(res, 'Validation failed', 400, errors.array());
      }

      const { user_id, amount, description } = req.body;

      const transaction = await walletService.credit(user_id, amount, {
        reference_type: 'manual',
        description: description || `Dépôt manuel de ${amount} FCFA`,
        metadata: { admin_id: req.user.userId }
      });

      return successResponse(res, transaction, 'Deposit successful', 201);
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/wallet/withdraw
 * Retrait (utilisateur)
 */
router.post('/withdraw',
  authenticate,
  [
    body('amount').isFloat({ min: 1 }).withMessage('Amount must be greater than 0'),
    body('description').optional().isLength({ max: 500 }),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return errorResponse(res, 'Validation failed', 400, errors.array());
      }

      const { amount, description } = req.body;

      // Vérifier le solde
      const hasBalance = await walletService.hasSufficientBalance(req.user.userId, amount);
      if (!hasBalance) {
        return errorResponse(res, 'Insufficient balance', 400);
      }

      const transaction = await walletService.debit(req.user.userId, amount, {
        type: 'withdrawal',
        reference_type: 'manual',
        description: description || `Retrait de ${amount} FCFA`,
        metadata: { withdrawal: true }
      });

      return successResponse(res, transaction, 'Withdrawal successful', 201);
    } catch (error) {
      if (error.message === 'Insufficient balance') {
        return errorResponse(res, error.message, 400);
      }
      return errorResponse(res, error.message, 500);
    }
  }
);

module.exports = router;
