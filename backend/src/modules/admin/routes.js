const express = require('express');
const { param, query, body, validationResult } = require('express-validator');
const router = express.Router();
const adminService = require('./admin.service');
const { authenticate, authorize } = require('../../middleware/auth');
const { successResponse, errorResponse } = require('../../utils/response');

const runValidation = (req, res) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    errorResponse(res, errors.array()[0].msg, 400);
    return true;
  }
  return false;
};

// Toutes les routes admin nécessitent authentification + rôle admin
router.use(authenticate);
router.use(authorize('admin'));

/**
 * GET /api/v1/admin
 * Dashboard : statistiques globales
 */
router.get('/', async (req, res) => {
  try {
    const stats = await adminService.getDashboardStats();
    return successResponse(res, stats, 'Statistiques récupérées');
  } catch (error) {
    return errorResponse(res, error.message, 500);
  }
});

/**
 * GET /api/v1/admin/users
 * Liste des utilisateurs (filtres: role, status, limit, offset)
 */
router.get('/users',
  query('role').optional().isIn(['client', 'driver', 'admin']),
  query('status').optional().isIn(['active', 'inactive', 'suspended', 'pending_verification']),
  query('limit').optional().isInt({ min: 1, max: 200 }).toInt(),
  query('offset').optional().isInt({ min: 0 }).toInt(),
  async (req, res) => {
    if (runValidation(req, res)) return; // validation failed, response already sent
    try {
      const limit = req.query.limit || 50;
      const offset = req.query.offset || 0;
      const filters = {};
      if (req.query.role) filters.role = req.query.role;
      if (req.query.status) filters.status = req.query.status;
      const result = await adminService.listUsers(filters, limit, offset);
      return successResponse(res, { users: result.users, total: result.total }, 'Utilisateurs récupérés');
    } catch (error) {
      return errorResponse(res, error.message, 500);
    }
  }
);

/**
 * PUT /api/v1/admin/users/:id/status
 * Modifier le statut d'un utilisateur (active, inactive, suspended, pending_verification)
 */
router.put('/users/:id/status',
  param('id').isInt({ min: 1 }).toInt(),
  body('status').isIn(['active', 'inactive', 'suspended', 'pending_verification']),
  async (req, res) => {
    if (runValidation(req, res)) return; // validation failed, response already sent
    try {
      const user = await adminService.updateUserStatus(req.params.id, req.body.status);
      return successResponse(res, user, 'Statut mis à jour');
    } catch (error) {
      if (error.message === 'User not found') return errorResponse(res, error.message, 404);
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * GET /api/v1/admin/drivers
 * Liste des drivers (filtres: status, verified, is_online, limit, offset)
 */
router.get('/drivers',
  query('status').optional().isIn(['active', 'inactive', 'suspended']),
  query('verified').optional().isBoolean(),
  query('is_online').optional().isBoolean(),
  query('limit').optional().isInt({ min: 1, max: 200 }).toInt(),
  query('offset').optional().isInt({ min: 0 }).toInt(),
  async (req, res) => {
    if (runValidation(req, res)) return; // validation failed, response already sent
    try {
      const limit = req.query.limit || 50;
      const offset = req.query.offset || 0;
      const filters = {};
      if (req.query.status) filters.status = req.query.status;
      if (req.query.verified !== undefined) filters.verified = req.query.verified === 'true';
      if (req.query.is_online !== undefined) filters.is_online = req.query.is_online === 'true';
      const drivers = await adminService.listDrivers(filters, limit, offset);
      return successResponse(res, drivers, 'Drivers récupérés');
    } catch (error) {
      return errorResponse(res, error.message, 500);
    }
  }
);

/**
 * PUT /api/v1/admin/drivers/:id/verify
 * Vérifier / rejeter / suspendre un driver (verification_status + notes)
 */
router.put('/drivers/:id/verify',
  param('id').isInt({ min: 1 }).toInt(),
  body('verification_status').isIn(['pending', 'approved', 'rejected', 'suspended']),
  body('verification_notes').optional().trim().isLength({ max: 2000 }),
  async (req, res) => {
    if (runValidation(req, res)) return; // validation failed, response already sent
    try {
      const profile = await adminService.updateDriverVerification(
        req.params.id,
        req.body.verification_status,
        req.body.verification_notes || null
      );
      return successResponse(res, profile, 'Vérification mise à jour');
    } catch (error) {
      if (error.message === 'Driver profile not found') return errorResponse(res, error.message, 404);
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * GET /api/v1/admin/pricing
 * Toutes les configurations tarifaires (ride + delivery)
 */
router.get('/pricing', async (req, res) => {
  try {
    const configs = await adminService.getAllPricingConfigs();
    return successResponse(res, configs, 'Configurations tarifaires récupérées');
  } catch (error) {
    return errorResponse(res, error.message, 500);
  }
});

/**
 * GET /api/v1/admin/pricing/:id
 * Une configuration tarifaire par ID
 */
router.get('/pricing/:id',
  param('id').isInt({ min: 1 }).toInt(),
  async (req, res) => {
    if (runValidation(req, res)) return; // validation failed, response already sent
    try {
      const config = await adminService.getPricingConfigById(req.params.id);
      if (!config) return errorResponse(res, 'Configuration non trouvée', 404);
      return successResponse(res, config, 'Configuration récupérée');
    } catch (error) {
      return errorResponse(res, error.message, 500);
    }
  }
);

/**
 * PUT /api/v1/admin/pricing/:id
 * Mettre à jour une configuration tarifaire (base_fare, cost_per_km, cost_per_minute, commission_rate, max_distance_km, is_active)
 */
router.put('/pricing/:id',
  param('id').isInt({ min: 1 }).toInt(),
  body('base_fare').optional().isFloat({ min: 0 }),
  body('cost_per_km').optional().isFloat({ min: 0 }),
  body('cost_per_minute').optional().isFloat({ min: 0 }),
  body('commission_rate').optional().isFloat({ min: 0, max: 100 }),
  body('max_distance_km').optional().isFloat({ min: 0 }),
  body('is_active').optional().isBoolean(),
  async (req, res) => {
    if (runValidation(req, res)) return; // validation failed, response already sent
    try {
      const config = await adminService.updatePricingConfig(req.params.id, req.body);
      return successResponse(res, config, 'Configuration mise à jour');
    } catch (error) {
      if (error.message === 'Pricing config not found') return errorResponse(res, error.message, 404);
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * GET /api/v1/admin/audit
 * Logs d'audit (filtres: entity_type, entity_id, user_id, action, date_from, date_to, limit, offset)
 */
router.get('/audit',
  query('entity_type').optional().trim().isLength({ max: 50 }),
  query('entity_id').optional(),
  query('user_id').optional().isInt({ min: 1 }).toInt(),
  query('action').optional().trim().isLength({ max: 100 }),
  query('date_from').optional().isISO8601(),
  query('date_to').optional().isISO8601(),
  query('limit').optional().isInt({ min: 1, max: 500 }).toInt(),
  query('offset').optional().isInt({ min: 0 }).toInt(),
  async (req, res) => {
    if (runValidation(req, res)) return; // validation failed, response already sent
    try {
      const limit = req.query.limit || 100;
      const offset = req.query.offset || 0;
      const filters = {};
      if (req.query.entity_type) filters.entity_type = req.query.entity_type;
      if (req.query.entity_id) filters.entity_id = req.query.entity_id;
      if (req.query.user_id) filters.user_id = req.query.user_id;
      if (req.query.action) filters.action = req.query.action;
      if (req.query.date_from) filters.date_from = req.query.date_from;
      if (req.query.date_to) filters.date_to = req.query.date_to;
      const result = await adminService.getAuditLogs(filters, limit, offset);
      return successResponse(res, { logs: result.logs, total: result.total }, 'Logs récupérés');
    } catch (error) {
      return errorResponse(res, error.message, 500);
    }
  }
);

module.exports = router;
