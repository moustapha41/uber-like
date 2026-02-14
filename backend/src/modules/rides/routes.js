const express = require('express');
const { body, param, query, validationResult } = require('express-validator');
const router = express.Router();
const { authenticate, authorize } = require('../../middleware/auth');
const { successResponse, errorResponse } = require('../../utils/response');
const { idempotencyMiddleware, saveIdempotentResponse } = require('../../middleware/idempotency');
const { rideCreationLimiter, rideAcceptLimiter, driverLocationLimiter } = require('../../middleware/rateLimit');
const ridesService = require('./rides.service');
const pricingService = require('./pricing.service');
const matchingService = require('./matching.service');

/**
 * Validation middleware
 */
const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return errorResponse(res, errors.array()[0].msg, 400);
  }
  next();
};

// ============================================
// ROUTES PUBLIQUES / ESTIMATION
// ============================================

/**
 * POST /api/v1/rides/estimate
 * Estime le prix d'une course
 */
router.post(
  '/estimate',
  [
    body('pickup_lat').isFloat({ min: -90, max: 90 }).withMessage('Latitude de départ invalide'),
    body('pickup_lng').isFloat({ min: -180, max: 180 }).withMessage('Longitude de départ invalide'),
    body('dropoff_lat').isFloat({ min: -90, max: 90 }).withMessage('Latitude d\'arrivée invalide'),
    body('dropoff_lng').isFloat({ min: -180, max: 180 }).withMessage('Longitude d\'arrivée invalide')
  ],
  validate,
  async (req, res) => {
    try {
      const { pickup_lat, pickup_lng, dropoff_lat, dropoff_lng } = req.body;
      const estimate = await ridesService.estimateRide(
        pickup_lat,
        pickup_lng,
        dropoff_lat,
        dropoff_lng
      );
      return successResponse(res, estimate, 'Estimation calculée avec succès');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

// ============================================
// ROUTES CLIENT (Authentification requise)
// ============================================

/**
 * POST /api/v1/rides
 * Crée une nouvelle demande de course
 */
router.post(
  '/',
  authenticate,
  rideCreationLimiter, // Rate limiting
  [
    body('pickup_lat').isFloat({ min: -90, max: 90 }).withMessage('Latitude de départ invalide'),
    body('pickup_lng').isFloat({ min: -180, max: 180 }).withMessage('Longitude de départ invalide'),
    body('dropoff_lat').isFloat({ min: -90, max: 90 }).withMessage('Latitude d\'arrivée invalide'),
    body('dropoff_lng').isFloat({ min: -180, max: 180 }).withMessage('Longitude d\'arrivée invalide'),
    body('pickup_address').optional().isString(),
    body('dropoff_address').optional().isString()
  ],
  validate,
  async (req, res) => {
    try {
      const ride = await ridesService.createRide(req.user.id, req.body);
      return successResponse(res, ride, 'Course créée avec succès', 201);
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * GET /api/v1/rides
 * Récupère l'historique des courses du client
 */
router.get(
  '/',
  authenticate,
  [
    query('limit').optional().isInt({ min: 1, max: 100 }).withMessage('Limit invalide'),
    query('offset').optional().isInt({ min: 0 }).withMessage('Offset invalide')
  ],
  validate,
  async (req, res) => {
    try {
      const limit = parseInt(req.query.limit) || 50;
      const offset = parseInt(req.query.offset) || 0;
      const rides = await ridesService.getUserRides(req.user.id, 'client', limit, offset);
      return successResponse(res, rides, 'Historique récupéré avec succès');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * GET /api/v1/rides/:id/nearby-drivers
 * Chauffeurs à proximité du point de départ (pour affichage carte client, course en attente)
 */
router.get(
  '/:id/nearby-drivers',
  authenticate,
  [param('id').isInt().withMessage('ID invalide')],
  validate,
  async (req, res) => {
    try {
      const rideId = parseInt(req.params.id);
      const ride = await ridesService.getRideById(rideId, req.user.id);
      if (ride.client_id !== req.user.id) {
        return errorResponse(res, 'Unauthorized', 403);
      }
      if (ride.status !== 'REQUESTED') {
        return successResponse(res, [], 'Course déjà assignée ou terminée');
      }
      const pickupLat = parseFloat(ride.pickup_lat);
      const pickupLng = parseFloat(ride.pickup_lng);
      const drivers = await matchingService.findNearbyDrivers(pickupLat, pickupLng, 5, 20, 'ride');
      const list = drivers.map(d => ({
        driver_id: d.id,
        lat: parseFloat(d.lat),
        lng: parseFloat(d.lng),
        distance_km: d.distance_km != null ? parseFloat(d.distance_km) : null
      }));
      return successResponse(res, list, 'Chauffeurs à proximité');
    } catch (error) {
      return errorResponse(res, error.message, 404);
    }
  }
);

/**
 * GET /api/v1/rides/:id
 * Récupère les détails d'une course
 */
router.get(
  '/:id',
  authenticate,
  [param('id').isInt().withMessage('ID invalide')],
  validate,
  async (req, res) => {
    try {
      const ride = await ridesService.getRideById(req.params.id, req.user.id);
      return successResponse(res, ride, 'Course récupérée avec succès');
    } catch (error) {
      return errorResponse(res, error.message, 404);
    }
  }
);

/**
 * POST /api/v1/rides/:id/cancel
 * Annule une course (client)
 */
router.post(
  '/:id/cancel',
  authenticate,
  idempotencyMiddleware,
  [
    param('id').isInt().withMessage('ID invalide'),
    body('reason').optional().isString()
  ],
  validate,
  async (req, res) => {
    try {
      const ride = await ridesService.cancelRide(
        req.params.id,
        'client',
        req.body.reason || 'Annulé par le client'
      );
      const response = successResponse(res, ride, 'Course annulée avec succès');

      // Enregistrer la réponse pour idempotence
      if (req.idempotencyKey) {
        await saveIdempotentResponse(
          req.idempotencyKey,
          req.user.id,
          `/rides/${req.params.id}/cancel`,
          { success: true, data: ride }
        );
      }

      return response;
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/rides/:id/rate
 * Note une course (client ou driver)
 */
router.post(
  '/:id/rate',
  authenticate,
  idempotencyMiddleware,
  [
    param('id').isInt().withMessage('ID invalide'),
    body('rating').isInt({ min: 1, max: 5 }).withMessage('Note invalide (1-5)'),
    body('comment').optional().isString(),
    body('role').isIn(['client', 'driver']).withMessage('Role invalide')
  ],
  validate,
  async (req, res) => {
    try {
      const result = await ridesService.rateRide(
        req.params.id,
        req.user.id,
        req.body.rating,
        req.body.comment,
        req.body.role
      );
      const response = successResponse(res, result, 'Avis enregistré avec succès');

      // Enregistrer la réponse pour idempotence
      if (req.idempotencyKey) {
        await saveIdempotentResponse(
          req.idempotencyKey,
          req.user.id,
          `/rides/${req.params.id}/rate`,
          { success: true, data: result }
        );
      }

      return response;
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

// ============================================
// ROUTES DRIVER (Authentification + Role driver requis)
// ============================================

/**
 * GET /api/v1/rides/driver/available
 * Récupère les courses disponibles pour le driver
 */
router.get(
  '/driver/available',
  authenticate,
  authorize('driver'),
  async (req, res) => {
    try {
      // TODO: Implémenter la récupération des courses disponibles
      // Pour l'instant, retourner les courses en pending
      const result = await require('../../config/database').query(
        `SELECT * FROM rides 
         WHERE status = 'REQUESTED' 
         ORDER BY created_at DESC 
         LIMIT 20`
      );
      return successResponse(res, result.rows, 'Courses disponibles récupérées');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * GET /api/v1/rides/driver/my-rides
 * Récupère l'historique des courses du driver
 */
router.get(
  '/driver/my-rides',
  authenticate,
  authorize('driver'),
  [
    query('limit').optional().isInt({ min: 1, max: 100 }),
    query('offset').optional().isInt({ min: 0 })
  ],
  validate,
  async (req, res) => {
    try {
      const limit = parseInt(req.query.limit) || 50;
      const offset = parseInt(req.query.offset) || 0;
      const rides = await ridesService.getUserRides(req.user.id, 'driver', limit, offset);
      return successResponse(res, rides, 'Historique récupéré avec succès');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/rides/:id/accept
 * Accepte une course (driver)
 * Header requis: Idempotency-Key (protection contre double acceptation)
 */
router.post(
  '/:id/accept',
  authenticate,
  authorize('driver'),
  idempotencyMiddleware, // Protection idempotence
  rideAcceptLimiter, // Rate limiting
  [param('id').isInt().withMessage('ID invalide')],
  validate,
  async (req, res) => {
    try {
      const ride = await ridesService.acceptRide(req.params.id, req.user.id);
      const response = successResponse(res, ride, 'Course acceptée avec succès');
      
      // Enregistrer la réponse pour idempotence
      if (req.idempotencyKey) {
        await saveIdempotentResponse(
          req.idempotencyKey,
          req.user.id,
          `/rides/${req.params.id}/accept`,
          { success: true, data: ride }
        );
      }
      
      return response;
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/rides/:id/arrived
 * Marque l'arrivée du driver au point de prise en charge
 */
router.post(
  '/:id/arrived',
  authenticate,
  authorize('driver'),
  [param('id').isInt().withMessage('ID invalide')],
  validate,
  async (req, res) => {
    try {
      const ride = await ridesService.markDriverArrived(req.params.id, req.user.id);
      return successResponse(res, ride, 'Arrivée enregistrée avec succès');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/rides/:id/start
 * Démarre la course (début du trajet)
 */
router.post(
  '/:id/start',
  authenticate,
  authorize('driver'),
  [param('id').isInt().withMessage('ID invalide')],
  validate,
  async (req, res) => {
    try {
      const ride = await ridesService.startRide(req.params.id, req.user.id);
      return successResponse(res, ride, 'Course démarrée avec succès');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/rides/:id/location
 * ⚠️ DÉPRÉCIÉ: Utiliser WebSocket 'driver:location:update' à la place
 * Conservé pour compatibilité, mais ne devrait plus être utilisé en production
 */
router.post(
  '/:id/location',
  authenticate,
  authorize('driver'),
  driverLocationLimiter, // Rate limiting (60 req/min)
  [
    param('id').isInt().withMessage('ID invalide'),
    body('lat').isFloat({ min: -90, max: 90 }).withMessage('Latitude invalide'),
    body('lng').isFloat({ min: -180, max: 180 }).withMessage('Longitude invalide'),
    body('heading').optional().isFloat({ min: 0, max: 360 }),
    body('speed').optional().isFloat({ min: 0 })
  ],
  validate,
  async (req, res) => {
    try {
      // Log warning en production
      if (process.env.NODE_ENV === 'production') {
        console.warn(`⚠️ POST /location used for ride ${req.params.id}. Use WebSocket instead.`);
      }
      
      await ridesService.updateDriverLocation(
        req.params.id,
        req.user.id,
        req.body.lat,
        req.body.lng,
        req.body.heading,
        req.body.speed
      );
      return successResponse(res, {}, 'Position mise à jour avec succès (déprécié: utiliser WebSocket)');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/rides/:id/complete
 * Termine la course (arrivée à destination)
 */
router.post(
  '/:id/complete',
  authenticate,
  authorize('driver'),
  [
    param('id').isInt().withMessage('ID invalide'),
    body('actual_distance_km').isFloat({ min: 0 }).withMessage('Distance invalide'),
    body('actual_duration_min').isInt({ min: 0 }).withMessage('Durée invalide')
  ],
  validate,
  async (req, res) => {
    try {
      const ride = await ridesService.completeRide(
        req.params.id,
        req.user.id,
        req.body.actual_distance_km,
        req.body.actual_duration_min
      );
      return successResponse(res, ride, 'Course terminée avec succès');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/rides/:id/cancel-driver
 * Annule une course (driver)
 */
router.post(
  '/:id/cancel-driver',
  authenticate,
  authorize('driver'),
  idempotencyMiddleware,
  [
    param('id').isInt().withMessage('ID invalide'),
    body('reason').optional().isString()
  ],
  validate,
  async (req, res) => {
    try {
      const ride = await ridesService.cancelRide(
        req.params.id,
        'driver',
        req.body.reason || 'Annulé par le chauffeur'
      );
      const response = successResponse(res, ride, 'Course annulée avec succès');

      // Enregistrer la réponse pour idempotence
      if (req.idempotencyKey) {
        await saveIdempotentResponse(
          req.idempotencyKey,
          req.user.id,
          `/rides/${req.params.id}/cancel-driver`,
          { success: true, data: ride }
        );
      }

      return response;
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

// ============================================
// ROUTES ADMIN (Authentification + Role admin requis)
// ============================================

/**
 * GET /api/v1/rides/admin/all
 * Récupère toutes les courses (admin)
 */
router.get(
  '/admin/all',
  authenticate,
  authorize('admin'),
  [
    query('status').optional().isString(),
    query('limit').optional().isInt({ min: 1, max: 100 }),
    query('offset').optional().isInt({ min: 0 })
  ],
  validate,
  async (req, res) => {
    try {
      const pool = require('../../config/database');
      let query = 'SELECT * FROM rides WHERE 1=1';
      const params = [];
      let paramCount = 1;

      if (req.query.status) {
        query += ` AND status = $${paramCount}`;
        params.push(req.query.status);
        paramCount++;
      }

      query += ' ORDER BY created_at DESC';
      query += ` LIMIT $${paramCount} OFFSET $${paramCount + 1}`;
      params.push(parseInt(req.query.limit) || 50);
      params.push(parseInt(req.query.offset) || 0);

      const result = await pool.query(query, params);
      return successResponse(res, result.rows, 'Courses récupérées avec succès');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

module.exports = router;
