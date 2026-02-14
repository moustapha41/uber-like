const express = require('express');
const { body, param, query, validationResult } = require('express-validator');
const router = express.Router();
const { authenticate, authorize } = require('../../middleware/auth');
const { successResponse, errorResponse } = require('../../utils/response');
const { idempotencyMiddleware, saveIdempotentResponse } = require('../../middleware/idempotency');
const { rideCreationLimiter, rideAcceptLimiter, driverLocationLimiter } = require('../../middleware/rateLimit');
const deliveriesService = require('./deliveries.service');
const matchingService = require('../rides/matching.service');

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
 * POST /api/v1/deliveries/estimate
 * Estime le prix d'une livraison
 */
router.post(
  '/estimate',
  [
    body('pickup_lat').isFloat({ min: -90, max: 90 }).withMessage('Latitude de départ invalide'),
    body('pickup_lng').isFloat({ min: -180, max: 180 }).withMessage('Longitude de départ invalide'),
    body('dropoff_lat').isFloat({ min: -90, max: 90 }).withMessage('Latitude d\'arrivée invalide'),
    body('dropoff_lng').isFloat({ min: -180, max: 180 }).withMessage('Longitude d\'arrivée invalide'),
    body('package_weight_kg').optional().isFloat({ min: 0 }).withMessage('Poids invalide'),
    body('package_type').optional().isIn(['standard', 'fragile', 'food', 'document', 'electronics']).withMessage('Type de colis invalide')
  ],
  validate,
  async (req, res) => {
    try {
      const { pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, package_weight_kg, package_type } = req.body;
      const estimate = await deliveriesService.estimateDelivery(
        pickup_lat,
        pickup_lng,
        dropoff_lat,
        dropoff_lng,
        package_weight_kg,
        package_type
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
 * POST /api/v1/deliveries
 * Crée une nouvelle demande de livraison
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
    body('dropoff_address').optional().isString(),
    body('package_type').optional().isIn(['standard', 'fragile', 'food', 'document', 'electronics']),
    body('package_weight_kg').optional().isFloat({ min: 0 }),
    body('package_dimensions').optional().isObject(),
    body('package_value').optional().isFloat({ min: 0 }),
    body('package_description').optional().isString(),
    body('requires_signature').optional().isBoolean(),
    body('insurance_required').optional().isBoolean(),
    body('recipient_name').optional().isString(),
    body('recipient_phone').optional().isString(),
    body('recipient_email').optional().isEmail(),
    body('delivery_instructions').optional().isString(),
    body('payment_method').optional().isIn(['wallet', 'mobile_money', 'cash_on_delivery']),
    body('sender_id').optional().isInt(),
    body('recipient_id').optional().isInt()
  ],
  validate,
  async (req, res) => {
    try {
      const delivery = await deliveriesService.createDelivery(req.user.id, req.body);
      return successResponse(res, delivery, 'Livraison créée avec succès', 201);
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * GET /api/v1/deliveries
 * Récupère l'historique des livraisons du client
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
      const deliveries = await deliveriesService.getUserDeliveries(req.user.id, 'client', limit, offset);
      return successResponse(res, deliveries, 'Historique récupéré avec succès');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * GET /api/v1/deliveries/:id/nearby-drivers
 * Chauffeurs à proximité du point de prise en charge (pour affichage carte client)
 */
router.get(
  '/:id/nearby-drivers',
  authenticate,
  [param('id').isInt().withMessage('ID invalide')],
  validate,
  async (req, res) => {
    try {
      const deliveryId = parseInt(req.params.id);
      const delivery = await deliveriesService.getDeliveryById(deliveryId, req.user.id);
      if (delivery.client_id !== req.user.id) {
        return errorResponse(res, 'Unauthorized', 403);
      }
      if (delivery.status !== 'REQUESTED') {
        return successResponse(res, [], 'Livraison déjà assignée ou terminée');
      }
      const pickupLat = parseFloat(delivery.pickup_lat);
      const pickupLng = parseFloat(delivery.pickup_lng);
      const drivers = await matchingService.findNearbyDrivers(pickupLat, pickupLng, 5, 20, 'delivery');
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
 * GET /api/v1/deliveries/:id
 * Récupère les détails d'une livraison
 */
router.get(
  '/:id',
  authenticate,
  [param('id').isInt().withMessage('ID invalide')],
  validate,
  async (req, res) => {
    try {
      const delivery = await deliveriesService.getDeliveryById(req.params.id, req.user.id);
      return successResponse(res, delivery, 'Livraison récupérée avec succès');
    } catch (error) {
      return errorResponse(res, error.message, 404);
    }
  }
);

/**
 * POST /api/v1/deliveries/:id/cancel
 * Annule une livraison (client)
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
      const delivery = await deliveriesService.cancelDelivery(
        req.params.id,
        'client',
        req.body.reason || 'Annulé par le client'
      );
      const response = successResponse(res, delivery, 'Livraison annulée avec succès');

      // Enregistrer la réponse pour idempotence
      if (req.idempotencyKey) {
        await saveIdempotentResponse(
          req.idempotencyKey,
          req.user.id,
          `/deliveries/${req.params.id}/cancel`,
          { success: true, data: delivery }
        );
      }

      return response;
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/deliveries/:id/rate
 * Note une livraison (client, driver ou destinataire)
 */
router.post(
  '/:id/rate',
  authenticate,
  idempotencyMiddleware,
  [
    param('id').isInt().withMessage('ID invalide'),
    body('rating').isInt({ min: 1, max: 5 }).withMessage('Note invalide (1-5)'),
    body('comment').optional().isString(),
    body('role').isIn(['client', 'driver', 'recipient']).withMessage('Role invalide')
  ],
  validate,
  async (req, res) => {
    try {
      const result = await deliveriesService.rateDelivery(
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
          `/deliveries/${req.params.id}/rate`,
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
 * GET /api/v1/deliveries/driver/available
 * Récupère les livraisons disponibles pour le driver
 */
router.get(
  '/driver/available',
  authenticate,
  authorize('driver'),
  async (req, res) => {
    try {
      const pool = require('../../config/database');
      const result = await pool.query(
        `SELECT * FROM deliveries 
         WHERE status = 'REQUESTED' 
         ORDER BY created_at DESC 
         LIMIT 20`
      );
      return successResponse(res, result.rows, 'Livraisons disponibles récupérées');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * GET /api/v1/deliveries/driver/my-deliveries
 * Récupère l'historique des livraisons du driver
 */
router.get(
  '/driver/my-deliveries',
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
      const deliveries = await deliveriesService.getUserDeliveries(req.user.id, 'driver', limit, offset);
      return successResponse(res, deliveries, 'Historique récupéré avec succès');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/deliveries/:id/accept
 * Accepte une livraison (driver)
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
      const delivery = await deliveriesService.acceptDelivery(req.params.id, req.user.id);
      const response = successResponse(res, delivery, 'Livraison acceptée avec succès');
      
      // Enregistrer la réponse pour idempotence
      if (req.idempotencyKey) {
        await saveIdempotentResponse(
          req.idempotencyKey,
          req.user.id,
          `/deliveries/${req.params.id}/accept`,
          { success: true, data: delivery }
        );
      }
      
      return response;
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/deliveries/:id/picked-up
 * Marque que le driver a récupéré le colis
 */
router.post(
  '/:id/picked-up',
  authenticate,
  authorize('driver'),
  [param('id').isInt().withMessage('ID invalide')],
  validate,
  async (req, res) => {
    try {
      const delivery = await deliveriesService.markPickedUp(req.params.id, req.user.id);
      return successResponse(res, delivery, 'Colis récupéré avec succès');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/deliveries/:id/start-transit
 * Démarre le trajet vers le destinataire
 */
router.post(
  '/:id/start-transit',
  authenticate,
  authorize('driver'),
  [param('id').isInt().withMessage('ID invalide')],
  validate,
  async (req, res) => {
    try {
      const delivery = await deliveriesService.startTransit(req.params.id, req.user.id);
      return successResponse(res, delivery, 'Trajet démarré avec succès');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/deliveries/:id/location
 * ⚠️ DÉPRÉCIÉ: Utiliser WebSocket 'driver:location:update' à la place
 * Met à jour la position GPS du driver pendant la livraison
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
      if (process.env.NODE_ENV === 'production') {
        console.warn(`⚠️ POST /location used for delivery ${req.params.id}. Use WebSocket instead.`);
      }
      
      await deliveriesService.updateDriverLocation(
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
 * POST /api/v1/deliveries/:id/complete
 * Termine la livraison (colis livré)
 */
router.post(
  '/:id/complete',
  authenticate,
  authorize('driver'),
  [
    param('id').isInt().withMessage('ID invalide'),
    body('actual_distance_km').isFloat({ min: 0 }).withMessage('Distance invalide'),
    body('actual_duration_min').isInt({ min: 0 }).withMessage('Durée invalide'),
    body('delivery_proof').optional().isObject().withMessage('Preuve de livraison invalide')
  ],
  validate,
  async (req, res) => {
    try {
      const delivery = await deliveriesService.completeDelivery(
        req.params.id,
        req.user.id,
        req.body.actual_distance_km,
        req.body.actual_duration_min,
        req.body.delivery_proof
      );
      return successResponse(res, delivery, 'Livraison terminée avec succès');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/deliveries/:id/cancel-driver
 * Annule une livraison (driver)
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
      const delivery = await deliveriesService.cancelDelivery(
        req.params.id,
        'driver',
        req.body.reason || 'Annulé par le chauffeur'
      );
      const response = successResponse(res, delivery, 'Livraison annulée avec succès');

      // Enregistrer la réponse pour idempotence
      if (req.idempotencyKey) {
        await saveIdempotentResponse(
          req.idempotencyKey,
          req.user.id,
          `/deliveries/${req.params.id}/cancel-driver`,
          { success: true, data: delivery }
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
 * GET /api/v1/deliveries/admin/all
 * Récupère toutes les livraisons (admin)
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
      let query = 'SELECT * FROM deliveries WHERE 1=1';
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
      return successResponse(res, result.rows, 'Livraisons récupérées avec succès');
    } catch (error) {
      return errorResponse(res, error.message, 400);
    }
  }
);

module.exports = router;
