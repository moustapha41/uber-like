const pool = require('../../config/database');
const pricingService = require('./pricing.service');
const matchingService = require('./matching.service');
const timeoutService = require('./timeout.service');
const mapsService = require('../maps/service');
const notificationService = require('../notifications/service');
const auditService = require('../audit/service');
const walletService = require('../wallet/wallet.service');
const logger = require('../../utils/logger');

/**
 * Rides Service
 * Gère toute la logique métier des courses
 */

class RidesService {
  /**
   * Génère une estimation de prix pour une course
   */
  async estimateRide(pickupLat, pickupLng, dropoffLat, dropoffLng) {
    try {
      // Calculer la distance et durée via le service maps
      const origin = { lat: pickupLat, lng: pickupLng };
      const destination = { lat: dropoffLat, lng: dropoffLng };

      const distance = await mapsService.calculateDistance(origin, destination);
      const route = await mapsService.getRoute(origin, destination);

      const distanceKm = distance.distance;
      const durationMin = Math.ceil(route.duration || distanceKm * 2); // Estimation: 2 min/km si pas de route

      // Vérifier la distance maximale
      const pricingConfig = await pricingService.getActivePricingConfig('ride');
      if (distanceKm > pricingConfig.max_distance_km) {
        throw new Error(`Distance maximale autorisée dépassée (${pricingConfig.max_distance_km} km)`);
      }

      // Calculer le prix
      const fareEstimate = pricingService.calculateFare(
        distanceKm,
        durationMin,
        pricingConfig
      );

      return {
        distance_km: Math.round(distanceKm * 100) / 100,
        duration_min: durationMin,
        fare_estimate: fareEstimate,
        currency: 'XOF',
        pricing_breakdown: {
          base_fare: pricingConfig.base_fare,
          distance_cost: distanceKm * pricingConfig.cost_per_km,
          time_cost: durationMin * pricingConfig.cost_per_minute,
          multiplier: pricingService.getCurrentTimeMultiplier(pricingConfig.time_slots)
        }
      };
    } catch (error) {
      console.error('Error estimating ride:', error);
      throw error;
    }
  }

  /**
   * Crée une nouvelle demande de course
   */
  async createRide(clientId, rideData) {
    const client = await pool.query('SELECT * FROM users WHERE id = $1', [clientId]);
    if (client.rows.length === 0) {
      throw new Error('Client not found');
    }

    // Calculer l'estimation
    const estimate = await this.estimateRide(
      rideData.pickup_lat,
      rideData.pickup_lng,
      rideData.dropoff_lat,
      rideData.dropoff_lng
    );

    // Créer la course en base
    const result = await pool.query(
      `INSERT INTO rides (
        client_id, pickup_lat, pickup_lng, pickup_address,
        dropoff_lat, dropoff_lng, dropoff_address,
        estimated_distance_km, estimated_duration_min, estimated_fare,
        status
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'REQUESTED')
      RETURNING *`,
      [
        clientId,
        rideData.pickup_lat,
        rideData.pickup_lng,
        rideData.pickup_address,
        rideData.dropoff_lat,
        rideData.dropoff_lng,
        rideData.dropoff_address,
        estimate.distance_km,
        estimate.duration_min,
        estimate.fare_estimate
      ]
    );

    const ride = result.rows[0];

    // Logger l'action
    await auditService.logAction(clientId, 'ride_created', 'ride', ride.id, {
      estimated_fare: estimate.fare_estimate
    });

    logger.rideAction('ride_created', { rideId: ride.id, userId: clientId, status: 'REQUESTED' });

    // Déclencher le matching progressif des drivers
    matchingService.progressiveMatching(ride.id, rideData.pickup_lat, rideData.pickup_lng);

    // ⏰ TIMEOUT SYSTÈME - 2 minutes (via service centralisé)
    await timeoutService.scheduleTimeout(ride.id, 'NO_DRIVER', 120000); // 2 minutes

    return ride;
  }

  /**
   * Accepte une course (driver)
   * 🔴 VERROU DB CRITIQUE: FOR UPDATE pour éviter double acceptation
   */
  async acceptRide(rideId, driverId) {
    const client = await pool.query('BEGIN');

    try {
      // 🔴 VERROU DB: SELECT ... FOR UPDATE (verrou exclusif)
      // Empêche qu'un autre driver accepte la même course simultanément
      const rideResult = await pool.query(
        'SELECT status FROM rides WHERE id = $1 FOR UPDATE',
        [rideId]
      );

      if (rideResult.rows.length === 0) {
        await pool.query('ROLLBACK');
        throw new Error('Course not found');
      }

      const ride = rideResult.rows[0];

      // Vérifier le statut AVANT la mise à jour
      if (ride.status !== 'REQUESTED') {
        await pool.query('ROLLBACK');
        throw new Error(`Course cannot be accepted. Current status: ${ride.status}`);
      }

      // Vérifier que le driver est disponible
      const driverResult = await pool.query(
        `SELECT u.*, dp.is_online, dp.is_available 
         FROM users u
         INNER JOIN driver_profiles dp ON u.id = dp.user_id
         WHERE u.id = $1 AND u.role = 'driver' AND u.status = 'active'`,
        [driverId]
      );

      if (driverResult.rows.length === 0) {
        throw new Error('Driver not found or not available');
      }

      const driver = driverResult.rows[0];
      if (!driver.is_online || !driver.is_available) {
        throw new Error('Driver is not online or not available');
      }

      // Mettre à jour la course (toujours dans la transaction avec verrou)
      const updateResult = await pool.query(
        `UPDATE rides 
         SET driver_id = $1, status = 'DRIVER_ASSIGNED', accepted_at = NOW()
         WHERE id = $2 AND status = 'REQUESTED'
         RETURNING *`,
        [driverId, rideId]
      );

      // Vérifier que la mise à jour a réussi (protection contre race condition)
      if (updateResult.rows.length === 0) {
        await pool.query('ROLLBACK');
        throw new Error('Course was already accepted by another driver');
      }

      // Marquer le driver comme non disponible
      await pool.query(
        'UPDATE driver_profiles SET is_available = false WHERE user_id = $1',
        [driverId]
      );

      await pool.query('COMMIT');

      // Retourner la course enrichie (client_phone, etc.) pour le chauffeur
      const enrichedRide = await this.getRideById(rideId, driverId);

      // Notifier le client
      await notificationService.sendPushNotification(
        ride.client_id,
        'Chauffeur assigné',
        `Votre chauffeur ${driver.first_name} arrive. Contact: ${driver.phone}`,
        { type: 'driver_assigned', ride_id: rideId, driver: driver }
      );

      // Notifier les autres drivers (course prise)
      // TODO: Implémenter la notification aux autres drivers

      // Logger l'action
      await auditService.logAction(driverId, 'ride_accepted', 'ride', rideId);

      return enrichedRide;
    } catch (error) {
      await pool.query('ROLLBACK');
      throw error;
    }
  }

  /**
   * Marque l'arrivée du driver au point de prise en charge
   */
  async markDriverArrived(rideId, driverId) {
    const ride = await pool.query(
      'SELECT * FROM rides WHERE id = $1 AND driver_id = $2',
      [rideId, driverId]
    );

    if (ride.rows.length === 0) {
      throw new Error('Ride not found or unauthorized');
    }

    if (ride.rows[0].status !== 'DRIVER_ASSIGNED') {
      throw new Error(`Invalid status transition. Current: ${ride.rows[0].status}`);
    }

    const result = await pool.query(
      `UPDATE rides 
       SET status = 'DRIVER_ARRIVED', driver_arrived_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [rideId]
    );

    const updatedRide = result.rows[0];

    // Notifier le client
    await notificationService.sendPushNotification(
      updatedRide.client_id,
      'Chauffeur arrivé',
      'Votre chauffeur est arrivé au point de prise en charge',
      { type: 'driver_arrived', ride_id: rideId }
    );

    // ⏰ TIMEOUT CLIENT - 7 minutes (via service centralisé)
    await timeoutService.scheduleTimeout(rideId, 'CLIENT_NO_SHOW', 420000); // 7 minutes

    logger.rideAction('driver_arrived', { rideId, userId: driverId, status: 'DRIVER_ARRIVED' });

    return updatedRide;
  }

  /**
   * Gère le cas où le client ne se présente pas
   */
  async handleClientNoShow(rideId) {
    const ride = await pool.query('SELECT * FROM rides WHERE id = $1', [rideId]);
    if (ride.rows.length === 0 || ride.rows[0].status !== 'DRIVER_ARRIVED') {
      return;
    }

    // Annuler la course et libérer le driver
    await this.cancelRide(rideId, 'driver', 'Client ne s\'est pas présenté dans les délais');
  }

  /**
   * Démarre la course (début du trajet)
   */
  async startRide(rideId, driverId) {
    const ride = await pool.query(
      'SELECT * FROM rides WHERE id = $1 AND driver_id = $2',
      [rideId, driverId]
    );

    if (ride.rows.length === 0) {
      throw new Error('Ride not found or unauthorized');
    }

    if (ride.rows[0].status !== 'DRIVER_ARRIVED') {
      throw new Error(`Invalid status transition. Current: ${ride.rows[0].status}`);
    }

    // 🔴 AJUSTEMENT CRITIQUE : Protection contre "double start"
    const result = await pool.query(
      `UPDATE rides 
       SET status = 'IN_PROGRESS', started_at = NOW()
       WHERE id = $1 AND status = 'DRIVER_ARRIVED'
       RETURNING *`,
      [rideId]
    );

    // Vérifier que la mise à jour a réussi (protection contre race condition)
    if (result.rows.length === 0) {
      throw new Error('Ride was already started or invalid status');
    }

    const updatedRide = result.rows[0];

    // Notifier le client
    await notificationService.sendPushNotification(
      updatedRide.client_id,
      'Course démarrée',
      'La course a débuté. Suivi en direct activé.',
      { type: 'ride_started', ride_id: rideId }
    );

    // Logger l'action
    await auditService.logAction(driverId, 'ride_started', 'ride', rideId);

    return updatedRide;
  }

  /**
   * Met à jour la position GPS du driver pendant la course
   * ⚠️ DÉPRÉCIÉ: Cette méthode est appelée via WebSocket maintenant
   * Conservée pour compatibilité avec l'ancien endpoint POST
   */
  async updateDriverLocation(rideId, driverId, lat, lng, heading, speed) {
    // Mettre à jour la position dans driver_locations
    await pool.query(
      `INSERT INTO driver_locations (driver_id, lat, lng, heading, speed_kmh, updated_at)
       VALUES ($1, $2, $3, $4, $5, NOW())
       ON CONFLICT (driver_id) 
       DO UPDATE SET lat = $2, lng = $3, heading = $4, speed_kmh = $5, updated_at = NOW()`,
      [driverId, lat, lng, heading, speed]
    );

    // Enregistrer dans l'historique de la course
    await pool.query(
      'INSERT INTO ride_tracking (ride_id, lat, lng) VALUES ($1, $2, $3)',
      [rideId, lat, lng]
    );

    // Note: Le broadcast WebSocket est géré par websocket.service.js
  }

  /**
   * Termine la course (arrivée à destination)
   */
  async completeRide(rideId, driverId, actualDistanceKm, actualDurationMin) {
    const ride = await pool.query(
      'SELECT * FROM rides WHERE id = $1 AND driver_id = $2',
      [rideId, driverId]
    );

    if (ride.rows.length === 0) {
      throw new Error('Ride not found or unauthorized');
    }

    if (ride.rows[0].status !== 'IN_PROGRESS') {
      throw new Error(`Invalid status transition. Current: ${ride.rows[0].status}`);
    }

    const rideData = ride.rows[0];

    // Calculer le prix final avec la règle: min(prix_estime × 1.10, prix_calculé_reel)
    const pricingConfig = await pricingService.getActivePricingConfig('ride');
    const actualFare = pricingService.calculateFare(
      actualDistanceKm,
      actualDurationMin,
      pricingConfig
    );

    const finalFare = pricingService.calculateFinalFare(
      parseFloat(rideData.estimated_fare),
      actualFare,
      10 // 10% de tolérance
    );

    // Mettre à jour la course
    const result = await pool.query(
      `UPDATE rides 
       SET status = 'COMPLETED',
           completed_at = NOW(),
           actual_distance_km = $1,
           actual_duration_min = $2,
           fare_final = $3,
           payment_status = 'PAYMENT_PENDING'
       WHERE id = $4 AND status = 'IN_PROGRESS'
       RETURNING *`,
      [actualDistanceKm, actualDurationMin, finalFare, rideId]
    );

    if (result.rows.length === 0) {
      throw new Error('Ride not found or invalid status for completion');
    }

    // 🔴 AJUSTEMENT CRITIQUE : Libérer le driver IMMÉDIATEMENT après COMPLETED
    await pool.query(
      'UPDATE driver_profiles SET is_available = true WHERE user_id = $1',
      [driverId]
    );

    const updatedRide = result.rows[0];

    // 🔴 LANCER LE PROCESSUS DE PAIEMENT
    // Si mobile_money : laisser PAYMENT_PENDING, le client paie via PayTech (POST /payment/initiate puis redirection)
    try {
      if (updatedRide.payment_method === 'mobile_money') {
        await notificationService.sendPushNotification(
          updatedRide.client_id,
          'Paiement Mobile Money',
          `Votre course de ${finalFare} FCFA est terminée. Payez par Orange Money / Wave.`,
          { rideId, amount: finalFare, type: 'payment_request', payment_method: 'mobile_money' }
        );
      } else {
        const hasBalance = await walletService.hasSufficientBalance(
          updatedRide.client_id,
          finalFare
        );

        if (hasBalance) {
        // Récupérer la configuration de pricing pour la commission
        const pricingConfig = await pricingService.getActivePricingConfig('ride');
        const commissionRate = parseFloat(pricingConfig.commission_rate) || 20;

        // Traiter le paiement
        await walletService.processRidePayment(
          rideId,
          updatedRide.client_id,
          finalFare,
          driverId,
          commissionRate
        );

        // Mettre à jour le statut de paiement
        await pool.query(
          `UPDATE rides 
           SET payment_status = 'PAID', status = 'PAID', paid_at = NOW()
           WHERE id = $1`,
          [rideId]
        );

        logger.info('Ride payment processed from wallet', { 
          rideId, 
          clientId: updatedRide.client_id, 
          driverId, 
          amount: finalFare 
        });
      } else {
        // Solde insuffisant, envoyer une demande de paiement
        await notificationService.sendPushNotification(
          updatedRide.client_id,
          'Paiement requis',
          `Votre course de ${finalFare} FCFA est terminée. Veuillez régler.`,
          { rideId, amount: finalFare, type: 'payment_request' }
        );

        logger.info('Payment request sent to client', { 
          rideId, 
          clientId: updatedRide.client_id, 
          amount: finalFare 
        });
        }
      }
    } catch (error) {
      // En cas d'erreur, laisser le statut PAYMENT_PENDING
      logger.error('Error processing automatic payment', { 
        error: error.message, 
        rideId 
      });
      
      // Notifier le client quand même
      await notificationService.sendPushNotification(
        updatedRide.client_id,
        'Paiement requis',
        `Votre course de ${finalFare} FCFA est terminée. Veuillez régler.`,
        { rideId, amount: finalFare, type: 'payment_request' }
      );
    }

    // Notifier le client
    await notificationService.sendPushNotification(
      updatedRide.client_id,
      'Course terminée',
      `Vous êtes arrivé. Montant à régler: ${finalFare} FCFA`,
      { type: 'ride_completed', ride_id: rideId, fare: finalFare }
    );

    // Logger l'action
    await auditService.logAction(driverId, 'ride_completed', 'ride', rideId, {
      fare_final: finalFare
    });

    return updatedRide;
  }

  /**
   * Annule une course
   */
  async cancelRide(rideId, cancelledBy, reason) {
    const ride = await pool.query('SELECT * FROM rides WHERE id = $1', [rideId]);

    if (ride.rows.length === 0) {
      throw new Error('Ride not found');
    }

    const rideData = ride.rows[0];
    const validStatuses = ['REQUESTED', 'DRIVER_ASSIGNED', 'DRIVER_ARRIVED'];

    if (!validStatuses.includes(rideData.status)) {
      throw new Error(`Cannot cancel ride in status: ${rideData.status}`);
    }

    let status;
    let shouldReleaseDriver = false;
    
    if (cancelledBy === 'client') {
      status = 'CANCELLED_BY_CLIENT';
      // Client annule : driver_id reste pour historique, mais driver marqué disponible
      shouldReleaseDriver = true;
    } else if (cancelledBy === 'driver') {
      status = 'CANCELLED_BY_DRIVER';
      // Driver annule : driver_id = NULL (libérer complètement)
      shouldReleaseDriver = true;
    } else {
      status = 'CANCELLED_BY_SYSTEM';
      // Système annule (timeout) : driver_id = NULL
      shouldReleaseDriver = true;
    }

    // 🔴 AJUSTEMENT CRITIQUE : Libérer driver_id pour CANCELLED_BY_DRIVER et CANCELLED_BY_SYSTEM
    const driverIdToRelease = rideData.driver_id;
    const shouldNullifyDriverId = (cancelledBy === 'driver' || cancelledBy === 'system');

    const result = await pool.query(
      `UPDATE rides 
       SET status = $1, 
           cancelled_at = NOW(), 
           cancellation_reason = $2,
           driver_id = CASE WHEN $4 THEN NULL ELSE driver_id END
       WHERE id = $3
       RETURNING *`,
      [status, reason, rideId, shouldNullifyDriverId]
    );

    // Libérer le driver (marquer disponible)
    if (shouldReleaseDriver && driverIdToRelease) {
      await pool.query(
        'UPDATE driver_profiles SET is_available = true WHERE user_id = $1',
        [driverIdToRelease]
      );
    }

    const updatedRide = result.rows[0];

    // Notifier les parties concernées
    if (cancelledBy === 'client' && rideData.driver_id) {
      await notificationService.sendPushNotification(
        rideData.driver_id,
        'Course annulée',
        'Le client a annulé la course',
        { type: 'ride_cancelled', ride_id: rideId }
      );
    } else if (cancelledBy === 'driver' && rideData.client_id) {
      await notificationService.sendPushNotification(
        rideData.client_id,
        'Course annulée',
        'Le chauffeur a annulé la course. Recherche d\'un nouveau chauffeur...',
        { type: 'ride_cancelled', ride_id: rideId }
      );
    }

    // Logger l'action
    await auditService.logAction(
      cancelledBy === 'client' ? rideData.client_id : rideData.driver_id,
      'ride_cancelled',
      'ride',
      rideId,
      { reason, cancelled_by: cancelledBy }
    );

    return updatedRide;
  }

  /**
   * Enregistre une notation/avis
   */
  async rateRide(rideId, userId, rating, comment, role) {
    const ride = await pool.query('SELECT * FROM rides WHERE id = $1', [rideId]);

    if (ride.rows.length === 0) {
      throw new Error('Ride not found');
    }

    const rideData = ride.rows[0];

    // Déterminer qui est noté
    const reviewedId = role === 'client' ? rideData.driver_id : rideData.client_id;

    if (!reviewedId) {
      throw new Error('Cannot rate: no driver/client assigned');
    }

    // Vérifier que l'utilisateur peut noter
    if (role === 'client' && rideData.client_id !== userId) {
      throw new Error('Unauthorized');
    }
    if (role === 'driver' && rideData.driver_id !== userId) {
      throw new Error('Unauthorized');
    }

    // Enregistrer l'avis
    await pool.query(
      `INSERT INTO ride_reviews (ride_id, reviewer_id, reviewed_id, role, rating, comment)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [rideId, userId, reviewedId, role, rating, comment]
    );

    // Mettre à jour la note dans la table rides
    if (role === 'client') {
      await pool.query(
        'UPDATE rides SET client_rating = $1, client_review = $2 WHERE id = $3',
        [rating, comment, rideId]
      );
    } else {
      await pool.query(
        'UPDATE rides SET driver_rating = $1, driver_review = $2 WHERE id = $3',
        [rating, comment, rideId]
      );
    }

    // Recalculer la note moyenne du driver/client
    if (role === 'client') {
      // Recalculer la note moyenne du driver
      const avgResult = await pool.query(
        `SELECT AVG(rating) as avg_rating, COUNT(*) as total_ratings
         FROM ride_reviews WHERE reviewed_id = $1`,
        [reviewedId]
      );

      if (avgResult.rows[0].avg_rating) {
        await pool.query(
          'UPDATE driver_profiles SET average_rating = $1, total_ratings = $2 WHERE user_id = $3',
          [
            parseFloat(avgResult.rows[0].avg_rating).toFixed(2),
            avgResult.rows[0].total_ratings,
            reviewedId
          ]
        );
      }
    }

    return { success: true };
  }

  /**
   * Récupère les détails d'une course (avec infos chauffeur: avatar, note, position)
   */
  async getRideById(rideId, userId = null) {
    const result = await pool.query(
      `SELECT r.*, 
              c.first_name as client_first_name, c.last_name as client_last_name, c.phone as client_phone,
              d.first_name as driver_first_name, d.last_name as driver_last_name, d.phone as driver_phone,
              d.avatar_url as driver_avatar_url,
              dp.average_rating as driver_average_rating
       FROM rides r
       LEFT JOIN users c ON r.client_id = c.id
       LEFT JOIN users d ON r.driver_id = d.id
       LEFT JOIN driver_profiles dp ON d.id = dp.user_id
       WHERE r.id = $1`,
      [rideId]
    );

    if (result.rows.length === 0) {
      throw new Error('Ride not found');
    }

    const ride = result.rows[0];

    // Vérifier les permissions si userId fourni
    if (userId && ride.client_id !== userId && ride.driver_id !== userId) {
      const user = await pool.query('SELECT role FROM users WHERE id = $1', [userId]);
      if (user.rows[0]?.role !== 'admin') {
        throw new Error('Unauthorized');
      }
    }

    // Position du chauffeur (driver_locations) pour suivi en temps réel
    if (ride.driver_id) {
      const loc = await pool.query(
        'SELECT lat, lng, updated_at FROM driver_locations WHERE driver_id = $1',
        [ride.driver_id]
      );
      if (loc.rows.length > 0) {
        ride.driver_lat = parseFloat(loc.rows[0].lat);
        ride.driver_lng = parseFloat(loc.rows[0].lng);
        ride.driver_location_updated_at = loc.rows[0].updated_at;
      }
    }

    return ride;
  }

  /**
   * Récupère l'historique des courses d'un utilisateur
   */
  async getUserRides(userId, role, limit = 50, offset = 0) {
    const column = role === 'client' ? 'client_id' : 'driver_id';

    const result = await pool.query(
      `SELECT r.*, 
              c.first_name as client_first_name, c.last_name as client_last_name,
              d.first_name as driver_first_name, d.last_name as driver_last_name
       FROM rides r
       LEFT JOIN users c ON r.client_id = c.id
       LEFT JOIN users d ON r.driver_id = d.id
       WHERE r.${column} = $1
       ORDER BY r.created_at DESC
       LIMIT $2 OFFSET $3`,
      [userId, limit, offset]
    );

    return result.rows;
  }
}

module.exports = new RidesService();

