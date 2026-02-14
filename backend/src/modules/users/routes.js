const express = require('express');
const router = express.Router();
const { body, validationResult, query } = require('express-validator');
const usersService = require('./users.service');
const { authenticate, authorize } = require('../../middleware/auth');
const { successResponse, errorResponse } = require('../../utils/response');

/**
 * Routes pour le module Users
 */

/**
 * GET /api/v1/users/profile
 * Récupère le profil de l'utilisateur connecté
 */
router.get('/profile', authenticate, async (req, res) => {
  try {
    const user = await usersService.getUserById(req.user.userId);
    
    // Si c'est un driver, inclure le profil driver
    let driverProfile = null;
    if (user.role === 'driver') {
      try {
        driverProfile = await usersService.getDriverProfile(user.id);
      } catch (error) {
        // Profil driver n'existe pas encore
      }
    }

    return successResponse(res, {
      user,
      driver_profile: driverProfile
    });
  } catch (error) {
    return errorResponse(res, error.message, 404);
  }
});

/**
 * GET /api/v1/users/:id
 * Récupère un utilisateur par ID (admin ou propriétaire)
 */
router.get('/:id', authenticate, async (req, res) => {
  try {
    const userId = parseInt(req.params.id);
    
    // Vérifier les permissions
    if (req.user.role !== 'admin' && req.user.userId !== userId) {
      return errorResponse(res, 'Unauthorized', 403);
    }

    const user = await usersService.getUserById(userId);
    return successResponse(res, user);
  } catch (error) {
    return errorResponse(res, error.message, 404);
  }
});

/**
 * PUT /api/v1/users/profile
 * Met à jour le profil de l'utilisateur connecté
 */
router.put('/profile', 
  authenticate,
  [
    body('first_name').optional().isLength({ min: 1, max: 100 }),
    body('last_name').optional().isLength({ min: 1, max: 100 }),
    body('phone').optional().matches(/^\+?[1-9]\d{1,14}$/).withMessage('Invalid phone format'),
    body('avatar_url').optional().isURL(),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return errorResponse(res, 'Validation failed', 400, errors.array());
      }

      // TODO: Implémenter la mise à jour du profil
      return errorResponse(res, 'Not implemented yet', 501);
    } catch (error) {
      return errorResponse(res, error.message, 500);
    }
  }
);

/**
 * GET /api/v1/users/drivers
 * Liste les drivers (admin uniquement)
 */
router.get('/drivers',
  authenticate,
  authorize(['admin']),
  [
    query('status').optional().isIn(['active', 'inactive', 'suspended']),
    query('verified').optional().isBoolean(),
    query('is_online').optional().isBoolean(),
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
        status: req.query.status,
        verified: req.query.verified === 'true' ? true : req.query.verified === 'false' ? false : undefined,
        is_online: req.query.is_online === 'true' ? true : req.query.is_online === 'false' ? false : undefined,
      };

      const limit = parseInt(req.query.limit) || 50;
      const offset = parseInt(req.query.offset) || 0;

      const drivers = await usersService.listDrivers(filters, limit, offset);
      return successResponse(res, drivers);
    } catch (error) {
      return errorResponse(res, error.message, 500);
    }
  }
);

/**
 * GET /api/v1/users/drivers/:id
 * Récupère le profil d'un driver (admin ou driver propriétaire)
 */
router.get('/drivers/:id', authenticate, async (req, res) => {
  try {
    const driverId = parseInt(req.params.id);
    
    // Vérifier les permissions
    if (req.user.role !== 'admin' && req.user.userId !== driverId) {
      return errorResponse(res, 'Unauthorized', 403);
    }

    const driverProfile = await usersService.getDriverProfile(driverId);
    return successResponse(res, driverProfile);
  } catch (error) {
    return errorResponse(res, error.message, 404);
  }
});

/**
 * PUT /api/v1/users/drivers/:id/status
 * Met à jour le statut online/available d'un driver
 */
router.put('/drivers/:id/status',
  authenticate,
  authorize(['driver']),
  [
    body('is_online').isBoolean(),
    body('is_available').isBoolean(),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return errorResponse(res, 'Validation failed', 400, errors.array());
      }

      const driverId = parseInt(req.params.id);
      
      // Vérifier que le driver modifie son propre statut
      if (req.user.userId !== driverId) {
        return errorResponse(res, 'Unauthorized', 403);
      }

      const { is_online, is_available } = req.body;
      const updated = await usersService.updateDriverStatus(driverId, is_online, is_available);
      
      return successResponse(res, updated);
    } catch (error) {
      return errorResponse(res, error.message, 500);
    }
  }
);

/**
 * POST /api/v1/users/drivers/:id/location
 * Met à jour la position GPS d'un driver
 * ⚠️ DÉPRÉCIÉ : Utiliser WebSocket à la place pour le tracking en temps réel
 */
router.post('/drivers/:id/location',
  authenticate,
  authorize(['driver']),
  [
    body('lat').isFloat({ min: -90, max: 90 }),
    body('lng').isFloat({ min: -180, max: 180 }),
    body('heading').optional().isFloat({ min: 0, max: 360 }),
    body('speed').optional().isFloat({ min: 0 }),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return errorResponse(res, 'Validation failed', 400, errors.array());
      }

      const driverId = parseInt(req.params.id);
      
      // Vérifier que le driver met à jour sa propre position
      if (req.user.userId !== driverId) {
        return errorResponse(res, 'Unauthorized', 403);
      }

      const { lat, lng, heading, speed } = req.body;
      const location = await usersService.updateDriverLocation(driverId, lat, lng, heading, speed);
      
      return successResponse(res, location, 'Location updated (consider using WebSocket for real-time tracking)', 200);
    } catch (error) {
      return errorResponse(res, error.message, 500);
    }
  }
);

module.exports = router;
