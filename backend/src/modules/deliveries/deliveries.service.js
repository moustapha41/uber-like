const pool = require('../../config/database');
const pricingService = require('../rides/pricing.service');
const matchingService = require('../rides/matching.service');
const timeoutService = require('../rides/timeout.service');
const mapsService = require('../maps/service');
const notificationService = require('../notifications/service');
const auditService = require('../audit/service');
const walletService = require('../wallet/wallet.service');
const logger = require('../../utils/logger');

/**
 * Deliveries Service
 * Gère toute la logique métier des livraisons
 */

class DeliveriesService {
  /**
   * Génère un code unique pour une livraison
   */
  generateDeliveryCode() {
    const year = new Date().getFullYear();
    const random = Math.floor(Math.random() * 10000).toString().padStart(4, '0');
    return `DELIV-${year}-${random}`;
  }

  /**
   * Enregistre l'historique des changements de statut
   */
  async recordStatusChange(deliveryId, oldStatus, newStatus, changedBy, changedByType, reason = null, metadata = null) {
    try {
      await pool.query(
        `INSERT INTO delivery_status_history (delivery_id, old_status, new_status, changed_by, changed_by_type, reason, metadata)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [deliveryId, oldStatus, newStatus, changedBy, changedByType, reason, metadata ? JSON.stringify(metadata) : null]
      );
    } catch (error) {
      logger.error('Error recording status change', { error: error.message, deliveryId });
    }
  }

  /**
   * Gèle le prix au moment ASSIGNED et crée le breakdown
   */
  async freezeDeliveryFare(deliveryId, pricingBreakdown, pricingConfigId) {
    try {
      const delivery = await pool.query('SELECT estimated_fare FROM deliveries WHERE id = $1', [deliveryId]);
      if (delivery.rows.length === 0) return;

      const estimatedFare = parseFloat(delivery.rows[0].estimated_fare);
      const baseFare = pricingBreakdown.base_fare || 0;
      const distanceCost = pricingBreakdown.distance_cost || 0;
      const timeCost = pricingBreakdown.time_cost || 0;
      const weightMultiplier = pricingBreakdown.weight_multiplier || 1.0;
      const typeMultiplier = pricingBreakdown.type_multiplier || 1.0;
      const timeMultiplier = pricingBreakdown.multiplier || 1.0;

      const subtotal = baseFare + distanceCost + timeCost;
      const totalFare = Math.round(subtotal * weightMultiplier * typeMultiplier * timeMultiplier);

      // Créer le breakdown
      await pool.query(
        `INSERT INTO delivery_fees_breakdown (
          delivery_id, base_fare, distance_cost, time_cost,
          weight_multiplier, type_multiplier, time_multiplier,
          subtotal, total_fare, pricing_config_id
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        ON CONFLICT (delivery_id) DO NOTHING`,
        [deliveryId, baseFare, distanceCost, timeCost, weightMultiplier, typeMultiplier, timeMultiplier, subtotal, totalFare, pricingConfigId]
      );

      // Geler le prix dans deliveries
      await pool.query(
        `UPDATE deliveries 
         SET frozen_fare = $1, fare_frozen_at = NOW()
         WHERE id = $2`,
        [totalFare, deliveryId]
      );
    } catch (error) {
      logger.error('Error freezing delivery fare', { error: error.message, deliveryId });
    }
  }

  /**
   * Crée une notification intelligente dans delivery_notifications
   */
  async createDeliveryNotification(deliveryId, userId, notificationType, title, message, metadata = {}) {
    try {
      await pool.query(
        `INSERT INTO delivery_notifications (delivery_id, user_id, notification_type, title, message, metadata)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [deliveryId, userId, notificationType, title, message, JSON.stringify(metadata)]
      );
    } catch (error) {
      logger.error('Error creating delivery notification', { error: error.message, deliveryId });
    }
  }

  /**
   * Génère une estimation de prix pour une livraison
   */
  async estimateDelivery(pickupLat, pickupLng, dropoffLat, dropoffLng, packageWeight = 1, packageType = 'standard') {
    try {
      // Calculer la distance et durée via le service maps
      const origin = { lat: pickupLat, lng: pickupLng };
      const destination = { lat: dropoffLat, lng: dropoffLng };

      const distance = await mapsService.calculateDistance(origin, destination);
      const route = await mapsService.getRoute(origin, destination);

      const distanceKm = distance.distance;
      const durationMin = Math.ceil(route.duration || distanceKm * 2); // Estimation: 2 min/km si pas de route

      // Vérifier la distance maximale
      const pricingConfig = await pricingService.getActivePricingConfig('delivery');
      if (distanceKm > pricingConfig.max_distance_km) {
        throw new Error(`Distance maximale autorisée dépassée (${pricingConfig.max_distance_km} km)`);
      }

      // Calculer le prix de base
      let baseFare = pricingService.calculateFare(
        distanceKm,
        durationMin,
        pricingConfig
      );

      // Ajuster selon le type de colis et poids
      let weightMultiplier = 1.0;
      if (packageWeight > 5) {
        weightMultiplier = 1.2; // +20% pour colis lourd (>5kg)
      } else if (packageWeight > 10) {
        weightMultiplier = 1.5; // +50% pour colis très lourd (>10kg)
      }

      let typeMultiplier = 1.0;
      if (packageType === 'fragile') {
        typeMultiplier = 1.3; // +30% pour fragile
      } else if (packageType === 'food') {
        typeMultiplier = 1.1; // +10% pour nourriture (urgent)
      } else if (packageType === 'electronics') {
        typeMultiplier = 1.2; // +20% pour électronique
      }

      const finalEstimate = Math.round(baseFare * weightMultiplier * typeMultiplier);

      return {
        distance_km: Math.round(distanceKm * 100) / 100,
        duration_min: durationMin,
        fare_estimate: finalEstimate,
        currency: 'XOF',
        pricing_breakdown: {
          base_fare: pricingConfig.base_fare,
          distance_cost: distanceKm * pricingConfig.cost_per_km,
          time_cost: durationMin * pricingConfig.cost_per_minute,
          weight_multiplier: weightMultiplier,
          type_multiplier: typeMultiplier,
          multiplier: pricingService.getCurrentTimeMultiplier(pricingConfig.time_slots)
        }
      };
    } catch (error) {
      logger.error('Error estimating delivery', error);
      throw error;
    }
  }

  /**
   * Crée une nouvelle demande de livraison
   */
  async createDelivery(clientId, deliveryData) {
    const client = await pool.query('SELECT * FROM users WHERE id = $1', [clientId]);
    if (client.rows.length === 0) {
      throw new Error('Client not found');
    }

    // Calculer l'estimation
    const estimate = await this.estimateDelivery(
      deliveryData.pickup_lat,
      deliveryData.pickup_lng,
      deliveryData.dropoff_lat,
      deliveryData.dropoff_lng,
      deliveryData.package_weight_kg || 1,
      deliveryData.package_type || 'standard'
    );

    // Générer un code unique
    let deliveryCode = this.generateDeliveryCode();
    let codeExists = true;
    while (codeExists) {
      const check = await pool.query('SELECT id FROM deliveries WHERE delivery_code = $1', [deliveryCode]);
      if (check.rows.length === 0) {
        codeExists = false;
      } else {
        deliveryCode = this.generateDeliveryCode();
      }
    }

    // Créer la livraison en base
    const result = await pool.query(
      `INSERT INTO deliveries (
        delivery_code, client_id, sender_id, recipient_id,
        pickup_lat, pickup_lng, pickup_address,
        dropoff_lat, dropoff_lng, dropoff_address,
        package_type, package_weight_kg, package_dimensions, package_value,
        package_description, requires_signature, insurance_required,
        recipient_name, recipient_phone, recipient_email, delivery_instructions,
        estimated_distance_km, estimated_duration_min, estimated_fare,
        payment_method, status
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24, $25, 'REQUESTED')
      RETURNING *`,
      [
        deliveryCode,
        clientId,
        deliveryData.sender_id || null,
        deliveryData.recipient_id || null,
        deliveryData.pickup_lat,
        deliveryData.pickup_lng,
        deliveryData.pickup_address,
        deliveryData.dropoff_lat,
        deliveryData.dropoff_lng,
        deliveryData.dropoff_address,
        deliveryData.package_type || 'standard',
        deliveryData.package_weight_kg || null,
        deliveryData.package_dimensions ? JSON.stringify(deliveryData.package_dimensions) : null,
        deliveryData.package_value || null,
        deliveryData.package_description || null,
        deliveryData.requires_signature || false,
        deliveryData.insurance_required || false,
        deliveryData.recipient_name || null,
        deliveryData.recipient_phone || null,
        deliveryData.recipient_email || null,
        deliveryData.delivery_instructions || null,
        estimate.distance_km,
        estimate.duration_min,
        estimate.fare_estimate,
        deliveryData.payment_method || 'wallet'
      ]
    );

    const delivery = result.rows[0];

    // Logger l'action
    await auditService.logAction(clientId, 'delivery_created', 'delivery', delivery.id, {
      estimated_fare: estimate.fare_estimate
    });

    // 📝 Enregistrer changement de statut initial
    await this.recordStatusChange(delivery.id, null, 'REQUESTED', clientId, 'client', 'Delivery created');

    logger.info('Delivery created', { deliveryId: delivery.id, userId: clientId, status: 'REQUESTED' });

    // Déclencher le matching progressif des drivers avec requirements
    const deliveryRequirements = {
      package_weight_kg: delivery.package_weight_kg,
      package_type: delivery.package_type,
      insurance_required: delivery.insurance_required
    };
    matchingService.progressiveMatching(delivery.id, deliveryData.pickup_lat, deliveryData.pickup_lng, 'delivery', deliveryRequirements);

    // ⏰ TIMEOUT SYSTÈME - 2 minutes (via service centralisé)
    await timeoutService.scheduleTimeout(delivery.id, 'NO_DRIVER', 120000, 'delivery'); // 2 minutes

    return delivery;
  }

  /**
   * Accepte une livraison (driver)
   * 🔴 VERROU DB CRITIQUE: FOR UPDATE pour éviter double acceptation
   */
  async acceptDelivery(deliveryId, driverId) {
    await pool.query('BEGIN');

    try {
      // 🔴 VERROU DB: SELECT ... FOR UPDATE (verrou exclusif)
      const deliveryResult = await pool.query(
        'SELECT status FROM deliveries WHERE id = $1 FOR UPDATE',
        [deliveryId]
      );

      if (deliveryResult.rows.length === 0) {
        await pool.query('ROLLBACK');
        throw new Error('Delivery not found');
      }

      const delivery = deliveryResult.rows[0];

      // Vérifier le statut AVANT la mise à jour
      if (delivery.status !== 'REQUESTED') {
        await pool.query('ROLLBACK');
        throw new Error(`Delivery cannot be accepted. Current status: ${delivery.status}`);
      }

      // Vérifier que le driver est disponible
      const driverResult = await pool.query(
        `SELECT dp.is_available, dp.is_online 
         FROM driver_profiles dp 
         WHERE dp.user_id = $1`,
        [driverId]
      );

      if (driverResult.rows.length === 0) {
        await pool.query('ROLLBACK');
        throw new Error('Driver profile not found');
      }

      const driverProfile = driverResult.rows[0];
      if (!driverProfile.is_online || !driverProfile.is_available) {
        await pool.query('ROLLBACK');
        throw new Error('Driver is not available');
      }

      // Récupérer les détails complets de la livraison pour geler le prix
      const fullDelivery = await pool.query(
        'SELECT * FROM deliveries WHERE id = $1',
        [deliveryId]
      );

      // Mettre à jour la livraison
      const updateResult = await pool.query(
        `UPDATE deliveries 
         SET status = 'ASSIGNED', driver_id = $1, assigned_at = NOW()
         WHERE id = $2 AND status = 'REQUESTED'
         RETURNING *`,
        [driverId, deliveryId]
      );

      if (updateResult.rows.length === 0) {
        await pool.query('ROLLBACK');
        throw new Error('Delivery was already accepted or invalid status');
      }

      // Marquer le driver comme non disponible
      await pool.query(
        'UPDATE driver_profiles SET is_available = false WHERE user_id = $1',
        [driverId]
      );

      await pool.query('COMMIT');

      // Retourner la livraison enrichie (client_phone, etc.) pour le chauffeur
      const updatedDelivery = await this.getDeliveryById(deliveryId, driverId);

      // 🔒 GELER LE PRIX au moment ASSIGNED (utiliser les données avant mise à jour pour estimate)
      const pricingConfig = await pricingService.getActivePricingConfig('delivery');
      const estimate = await this.estimateDelivery(
        fullDelivery.rows[0].pickup_lat,
        fullDelivery.rows[0].pickup_lng,
        fullDelivery.rows[0].dropoff_lat,
        fullDelivery.rows[0].dropoff_lng,
        fullDelivery.rows[0].package_weight_kg || 1,
        fullDelivery.rows[0].package_type || 'standard'
      );
      await this.freezeDeliveryFare(deliveryId, estimate.pricing_breakdown, pricingConfig.id);

      // 📝 Enregistrer changement de statut
      await this.recordStatusChange(deliveryId, 'REQUESTED', 'ASSIGNED', driverId, 'driver', 'Driver accepted delivery');

      // 🔔 Notifier le client (notification intelligente)
      await notificationService.sendPushNotification(
        updatedDelivery.client_id,
        'Livraison acceptée',
        'Un driver a accepté votre livraison',
        { type: 'delivery_assigned', delivery_id: deliveryId }
      );
      await this.createDeliveryNotification(
        deliveryId,
        updatedDelivery.client_id,
        'delivery_assigned',
        'Livraison acceptée',
        'Un driver a accepté votre livraison',
        { delivery_id: deliveryId }
      );

      // Logger l'action
      await auditService.logAction(driverId, 'delivery_accepted', 'delivery', deliveryId);

      return updatedDelivery;
    } catch (error) {
      await pool.query('ROLLBACK');
      throw error;
    }
  }

  /**
   * Marque que le driver a récupéré le colis (pickup)
   */
  async markPickedUp(deliveryId, driverId) {
    const delivery = await pool.query(
      'SELECT * FROM deliveries WHERE id = $1 AND driver_id = $2',
      [deliveryId, driverId]
    );

    if (delivery.rows.length === 0) {
      throw new Error('Delivery not found or unauthorized');
    }

    if (delivery.rows[0].status !== 'ASSIGNED') {
      throw new Error(`Invalid status transition. Current: ${delivery.rows[0].status}`);
    }

    const oldDelivery = await pool.query('SELECT status FROM deliveries WHERE id = $1', [deliveryId]);
    const oldStatus = oldDelivery.rows[0]?.status;

    const result = await pool.query(
      `UPDATE deliveries 
       SET status = 'PICKED_UP', picked_up_at = NOW()
       WHERE id = $1
       RETURNING *`,
      [deliveryId]
    );

    const updatedDelivery = result.rows[0];

    // 📝 Enregistrer changement de statut
    await this.recordStatusChange(deliveryId, oldStatus, 'PICKED_UP', driverId, 'driver', 'Package picked up');

    // 🔔 Notifier le client et le destinataire (notifications intelligentes)
    await notificationService.sendPushNotification(
      updatedDelivery.client_id,
      'Colis récupéré',
      'Le driver a récupéré votre colis',
      { type: 'delivery_picked_up', delivery_id: deliveryId }
    );
    await this.createDeliveryNotification(
      deliveryId,
      updatedDelivery.client_id,
      'package_picked',
      'Colis récupéré',
      'Le driver a récupéré votre colis',
      { delivery_id: deliveryId }
    );

    if (updatedDelivery.recipient_id) {
      await notificationService.sendPushNotification(
        updatedDelivery.recipient_id,
        'Colis en route',
        'Votre colis a été récupéré et est en route',
        { type: 'delivery_picked_up', delivery_id: deliveryId }
      );
      await this.createDeliveryNotification(
        deliveryId,
        updatedDelivery.recipient_id,
        'package_picked',
        'Colis en route',
        'Votre colis a été récupéré et est en route',
        { delivery_id: deliveryId }
      );
    }

    logger.info('Delivery picked up', { deliveryId, userId: driverId, status: 'PICKED_UP' });

    return updatedDelivery;
  }

  /**
   * Démarre le trajet vers le destinataire (in transit)
   */
  async startTransit(deliveryId, driverId) {
    const delivery = await pool.query(
      'SELECT * FROM deliveries WHERE id = $1 AND driver_id = $2',
      [deliveryId, driverId]
    );

    if (delivery.rows.length === 0) {
      throw new Error('Delivery not found or unauthorized');
    }

    if (delivery.rows[0].status !== 'PICKED_UP') {
      throw new Error(`Invalid status transition. Current: ${delivery.rows[0].status}`);
    }

    const oldDelivery = await pool.query('SELECT status FROM deliveries WHERE id = $1', [deliveryId]);
    const oldStatus = oldDelivery.rows[0]?.status;

    const result = await pool.query(
      `UPDATE deliveries 
       SET status = 'IN_TRANSIT', in_transit_at = NOW()
       WHERE id = $1 AND status = 'PICKED_UP'
       RETURNING *`,
      [deliveryId]
    );

    if (result.rows.length === 0) {
      throw new Error('Delivery was already in transit or invalid status');
    }

    const updatedDelivery = result.rows[0];

    // 📝 Enregistrer changement de statut
    await this.recordStatusChange(deliveryId, oldStatus, 'IN_TRANSIT', driverId, 'driver', 'Started transit to recipient');

    // 🔔 Notifier le destinataire (notification intelligente)
    const recipientId = updatedDelivery.recipient_id || updatedDelivery.client_id;
    await notificationService.sendPushNotification(
      recipientId,
      'Colis en route',
      'Votre colis est en route vers vous',
      { type: 'delivery_in_transit', delivery_id: deliveryId }
    );
    await this.createDeliveryNotification(
      deliveryId,
      recipientId,
      'in_transit',
      'Colis en route',
      'Votre colis est en route vers vous',
      { delivery_id: deliveryId, estimated_arrival_minutes: updatedDelivery.estimated_duration_min }
    );

    // Logger l'action
    await auditService.logAction(driverId, 'delivery_in_transit', 'delivery', deliveryId);

    return updatedDelivery;
  }

  /**
   * Met à jour la position GPS du driver pendant la livraison
   */
  async updateDriverLocation(deliveryId, driverId, lat, lng, heading, speed, batteryLevel = null, networkType = null, accuracy = null) {
    // Mettre à jour la position dans driver_locations
    await pool.query(
      `INSERT INTO driver_locations (driver_id, lat, lng, heading, speed_kmh, updated_at)
       VALUES ($1, $2, $3, $4, $5, NOW())
       ON CONFLICT (driver_id) 
       DO UPDATE SET lat = $2, lng = $3, heading = $4, speed_kmh = $5, updated_at = NOW()`,
      [driverId, lat, lng, heading, speed]
    );

    // Enregistrer dans l'historique de la livraison avec métriques qualité
    await pool.query(
      `INSERT INTO delivery_tracking (delivery_id, lat, lng, heading, speed, battery_level, network_type, accuracy) 
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [deliveryId, lat, lng, heading, speed, batteryLevel, networkType, accuracy]
    );
  }

  /**
   * Termine la livraison (colis livré)
   */
  async completeDelivery(deliveryId, driverId, actualDistanceKm, actualDurationMin, deliveryProof = null) {
    const delivery = await pool.query(
      'SELECT * FROM deliveries WHERE id = $1 AND driver_id = $2',
      [deliveryId, driverId]
    );

    if (delivery.rows.length === 0) {
      throw new Error('Delivery not found or unauthorized');
    }

    if (delivery.rows[0].status !== 'IN_TRANSIT') {
      throw new Error(`Invalid status transition. Current: ${delivery.rows[0].status}`);
    }

    const deliveryData = delivery.rows[0];
    const oldStatus = deliveryData.status;

    // Utiliser le prix gelé si disponible, sinon calculer
    let finalFare;
    if (deliveryData.frozen_fare) {
      finalFare = parseFloat(deliveryData.frozen_fare);
    } else {
      // Calculer le prix final avec la règle: min(prix_estime × 1.10, prix_calculé_réel)
      const pricingConfig = await pricingService.getActivePricingConfig('delivery');
      const actualFare = pricingService.calculateFare(
        actualDistanceKm,
        actualDurationMin,
        pricingConfig
      );
      finalFare = pricingService.calculateFinalFare(
        parseFloat(deliveryData.estimated_fare),
        actualFare,
        10 // 10% de tolérance
      );
    }

    // Mettre à jour la livraison
    const result = await pool.query(
      `UPDATE deliveries 
       SET status = 'DELIVERED',
           delivered_at = NOW(),
           actual_distance_km = $1,
           actual_duration_min = $2,
           fare_final = $3,
           delivery_proof = $4,
           payment_status = CASE WHEN payment_method = 'cash_on_delivery' THEN 'PAYMENT_PENDING' ELSE 'UNPAID' END
       WHERE id = $5 AND status = 'IN_TRANSIT'
       RETURNING *`,
      [
        actualDistanceKm,
        actualDurationMin,
        finalFare,
        deliveryProof ? JSON.stringify(deliveryProof) : null,
        deliveryId
      ]
    );

    if (result.rows.length === 0) {
      throw new Error('Delivery not found or invalid status for completion');
    }

    // 🔴 Libérer le driver IMMÉDIATEMENT après DELIVERED
    await pool.query(
      'UPDATE driver_profiles SET is_available = true WHERE user_id = $1',
      [driverId]
    );

    const updatedDelivery = result.rows[0];

    // 📝 Enregistrer changement de statut
    await this.recordStatusChange(deliveryId, oldStatus, 'DELIVERED', driverId, 'driver', 'Delivery completed');

    // 📸 Créer preuve de livraison si fournie
    if (deliveryProof) {
      try {
        await pool.query(
          `INSERT INTO delivery_proofs (
            delivery_id, package_photo_url, delivery_photo_url, location_photo_url,
            signature_url, signature_data, recipient_name, recipient_phone,
            gps_lat, gps_lng, delivery_notes
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
          ON CONFLICT (delivery_id) DO UPDATE SET
            package_photo_url = COALESCE($2, delivery_proofs.package_photo_url),
            delivery_photo_url = COALESCE($3, delivery_proofs.delivery_photo_url),
            location_photo_url = COALESCE($4, delivery_proofs.location_photo_url),
            signature_url = COALESCE($5, delivery_proofs.signature_url),
            signature_data = COALESCE($6, delivery_proofs.signature_data),
            recipient_name = COALESCE($7, delivery_proofs.recipient_name),
            recipient_phone = COALESCE($8, delivery_proofs.recipient_phone),
            gps_lat = COALESCE($9, delivery_proofs.gps_lat),
            gps_lng = COALESCE($10, delivery_proofs.gps_lng),
            delivery_notes = COALESCE($11, delivery_proofs.delivery_notes)`,
          [
            deliveryId,
            deliveryProof.package_photo_url || null,
            deliveryProof.delivery_photo_url || null,
            deliveryProof.location_photo_url || null,
            deliveryProof.signature_url || null,
            deliveryProof.signature_data ? JSON.stringify(deliveryProof.signature_data) : null,
            deliveryProof.recipient_name || null,
            deliveryProof.recipient_phone || null,
            deliveryProof.gps_lat || null,
            deliveryProof.gps_lng || null,
            deliveryProof.delivery_notes || null
          ]
        );
      } catch (error) {
        logger.error('Error creating delivery proof', { error: error.message, deliveryId });
      }
    }

    // Traiter le paiement selon la méthode
    if (updatedDelivery.payment_method === 'cash_on_delivery') {
      // Paiement à la livraison - le driver collecte l'argent
      await pool.query(
        `UPDATE deliveries 
         SET payment_status = 'PAID', payment_collected_at = NOW()
         WHERE id = $1`,
        [deliveryId]
      );
    } else {
      // Paiement wallet/mobile_money - traitement automatique
      try {
        const hasBalance = await walletService.hasSufficientBalance(
          updatedDelivery.client_id,
          finalFare
        );

        if (hasBalance) {
          const commissionRate = parseFloat(pricingConfig.commission_rate) || 20;
          await walletService.processRidePayment(
            deliveryId,
            updatedDelivery.client_id,
            finalFare,
            driverId,
            commissionRate
          );

          await pool.query(
            `UPDATE deliveries 
             SET payment_status = 'PAID', paid_at = NOW()
             WHERE id = $1`,
            [deliveryId]
          );
        } else {
          await notificationService.sendPushNotification(
            updatedDelivery.client_id,
            'Paiement requis',
            `Votre livraison de ${finalFare} FCFA est terminée. Veuillez régler.`,
            { deliveryId, amount: finalFare, type: 'payment_request' }
          );
        }
      } catch (error) {
        logger.error('Error processing automatic payment', { error: error.message, deliveryId });
      }
    }

    // 🔔 Notifier le client et le destinataire (notifications intelligentes)
    await notificationService.sendPushNotification(
      updatedDelivery.client_id,
      'Livraison terminée',
      `Votre colis a été livré. Montant: ${finalFare} FCFA`,
      { type: 'delivery_completed', delivery_id: deliveryId, fare: finalFare }
    );
    await this.createDeliveryNotification(
      deliveryId,
      updatedDelivery.client_id,
      'delivered',
      'Livraison terminée',
      `Votre colis a été livré. Montant: ${finalFare} FCFA`,
      { delivery_id: deliveryId, fare: finalFare }
    );

    if (updatedDelivery.recipient_id && updatedDelivery.recipient_id !== updatedDelivery.client_id) {
      await notificationService.sendPushNotification(
        updatedDelivery.recipient_id,
        'Colis livré',
        'Votre colis a été livré avec succès',
        { type: 'delivery_completed', delivery_id: deliveryId }
      );
      await this.createDeliveryNotification(
        deliveryId,
        updatedDelivery.recipient_id,
        'delivered',
        'Colis livré',
        'Votre colis a été livré avec succès',
        { delivery_id: deliveryId }
      );
    }

    // Logger l'action
    await auditService.logAction(driverId, 'delivery_completed', 'delivery', deliveryId, {
      fare_final: finalFare
    });

    return updatedDelivery;
  }

  /**
   * Annule une livraison
   */
  async cancelDelivery(deliveryId, cancelledBy, reason) {
    const delivery = await pool.query('SELECT * FROM deliveries WHERE id = $1', [deliveryId]);

    if (delivery.rows.length === 0) {
      throw new Error('Delivery not found');
    }

    const deliveryData = delivery.rows[0];
    const oldStatus = deliveryData.status;
    const validStatuses = ['REQUESTED', 'ASSIGNED', 'PICKED_UP', 'IN_TRANSIT'];

    if (!validStatuses.includes(deliveryData.status)) {
      throw new Error(`Cannot cancel delivery in status: ${deliveryData.status}`);
    }

    let status;
    let cancellationFee = 0;
    let shouldCreateReturn = false;

    if (cancelledBy === 'client') {
      status = 'CANCELLED_BY_CLIENT';
      // Si colis déjà récupéré, appliquer frais d'annulation
      if (deliveryData.status === 'PICKED_UP' || deliveryData.status === 'IN_TRANSIT') {
        cancellationFee = parseFloat(deliveryData.frozen_fare || deliveryData.estimated_fare) * 0.3; // 30% de frais
        shouldCreateReturn = true;
      }
    } else if (cancelledBy === 'driver') {
      status = 'CANCELLED_BY_DRIVER';
      // Si colis déjà récupéré, créer un retour
      if (deliveryData.status === 'PICKED_UP' || deliveryData.status === 'IN_TRANSIT') {
        shouldCreateReturn = true;
      }
    } else if (cancelledBy === 'system') {
      status = 'CANCELLED_BY_SYSTEM';
    } else {
      throw new Error('Invalid cancelledBy value');
    }

    // Si un driver était assigné, le libérer
    if (deliveryData.driver_id) {
      await pool.query(
        'UPDATE driver_profiles SET is_available = true WHERE user_id = $1',
        [deliveryData.driver_id]
      );

      // Calculer remboursement si nécessaire
      const refundAmount = cancellationFee > 0 
        ? parseFloat(deliveryData.frozen_fare || deliveryData.estimated_fare) - cancellationFee 
        : parseFloat(deliveryData.frozen_fare || deliveryData.estimated_fare);

      // Si annulé par le système ou le driver, mettre driver_id à NULL
      if (cancelledBy !== 'client') {
        await pool.query(
          `UPDATE deliveries 
           SET status = $1, cancelled_at = NOW(), cancellation_reason = $2, driver_id = NULL,
               cancellation_fee = $4, refund_amount = $5, refund_reason = $6
           WHERE id = $3
           RETURNING *`,
          [status, reason, deliveryId, cancellationFee, refundAmount, `Cancelled by ${cancelledBy}`]
        );
      } else {
        // Si annulé par le client, garder driver_id pour historique
        await pool.query(
          `UPDATE deliveries 
           SET status = $1, cancelled_at = NOW(), cancellation_reason = $2,
               cancellation_fee = $4, refund_amount = $5, refund_reason = $6
           WHERE id = $3
           RETURNING *`,
          [status, reason, deliveryId, cancellationFee, refundAmount, reason]
        );
      }
    } else {
      await pool.query(
        `UPDATE deliveries 
         SET status = $1, cancelled_at = NOW(), cancellation_reason = $2, driver_id = NULL,
             cancellation_fee = $4, refund_amount = $5
         WHERE id = $3
         RETURNING *`,
        [status, reason, deliveryId, cancellationFee, parseFloat(deliveryData.estimated_fare)]
      );
    }

    // Créer retour si nécessaire
    if (shouldCreateReturn) {
      try {
        await pool.query(
          `INSERT INTO delivery_returns (
            delivery_id, return_reason, return_initiated_by, return_type, return_notes, status
          ) VALUES ($1, $2, $3, 'permanent', $4, 'pending')`,
          [deliveryId, reason, cancelledBy, `Return initiated due to cancellation`]
        );
      } catch (error) {
        logger.error('Error creating delivery return', { error: error.message, deliveryId });
      }
    }

    // 📝 Enregistrer changement de statut
    await this.recordStatusChange(deliveryId, oldStatus, status, null, cancelledBy, reason, {
      cancellation_fee: cancellationFee,
      refund_amount: cancellationFee > 0 ? parseFloat(deliveryData.frozen_fare || deliveryData.estimated_fare) - cancellationFee : null
    });

    const result = await pool.query('SELECT * FROM deliveries WHERE id = $1', [deliveryId]);

    // Notifier les parties concernées
    await notificationService.sendPushNotification(
      deliveryData.client_id,
      'Livraison annulée',
      reason,
      { type: 'delivery_cancelled', delivery_id: deliveryId }
    );

    if (deliveryData.driver_id) {
      await notificationService.sendPushNotification(
        deliveryData.driver_id,
        'Livraison annulée',
        reason,
        { type: 'delivery_cancelled', delivery_id: deliveryId }
      );
    }

    logger.info('Delivery cancelled', { deliveryId, cancelledBy, reason });

    return result.rows[0];
  }

  /**
   * Récupère une livraison par ID (avec infos chauffeur: avatar, note, position)
   */
  async getDeliveryById(deliveryId, userId) {
    const result = await pool.query(
      `SELECT d.*, 
              u1.email as client_email, u1.first_name as client_first_name, u1.last_name as client_last_name, u1.phone as client_phone,
              u2.email as driver_email, u2.first_name as driver_first_name, u2.last_name as driver_last_name,
              u2.phone as driver_phone, u2.avatar_url as driver_avatar_url,
              u3.email as sender_email, u3.first_name as sender_first_name, u3.last_name as sender_last_name,
              u4.email as recipient_email, u4.first_name as recipient_first_name, u4.last_name as recipient_last_name,
              dp.average_rating as driver_average_rating
       FROM deliveries d
       LEFT JOIN users u1 ON d.client_id = u1.id
       LEFT JOIN users u2 ON d.driver_id = u2.id
       LEFT JOIN driver_profiles dp ON u2.id = dp.user_id
       LEFT JOIN users u3 ON d.sender_id = u3.id
       LEFT JOIN users u4 ON d.recipient_id = u4.id
       WHERE d.id = $1 AND (d.client_id = $2 OR d.driver_id = $2 OR d.sender_id = $2 OR d.recipient_id = $2)`,
      [deliveryId, userId]
    );

    if (result.rows.length === 0) {
      throw new Error('Delivery not found or unauthorized');
    }

    const delivery = result.rows[0];

    // Position du chauffeur (dernière entrée delivery_tracking ou driver_locations)
    if (delivery.driver_id) {
      const tracking = await pool.query(
        `SELECT lat, lng, timestamp FROM delivery_tracking
         WHERE delivery_id = $1 ORDER BY timestamp DESC LIMIT 1`,
        [deliveryId]
      );
      if (tracking.rows.length > 0) {
        delivery.driver_lat = parseFloat(tracking.rows[0].lat);
        delivery.driver_lng = parseFloat(tracking.rows[0].lng);
        delivery.driver_location_updated_at = tracking.rows[0].timestamp;
      } else {
        const loc = await pool.query(
          'SELECT lat, lng, updated_at FROM driver_locations WHERE driver_id = $1',
          [delivery.driver_id]
        );
        if (loc.rows.length > 0) {
          delivery.driver_lat = parseFloat(loc.rows[0].lat);
          delivery.driver_lng = parseFloat(loc.rows[0].lng);
          delivery.driver_location_updated_at = loc.rows[0].updated_at;
        }
      }
    }

    return delivery;
  }

  /**
   * Récupère les livraisons d'un utilisateur
   */
  async getUserDeliveries(userId, role, limit = 50, offset = 0) {
    let query;
    if (role === 'client') {
      query = `SELECT * FROM deliveries 
               WHERE client_id = $1 OR sender_id = $1 OR recipient_id = $1
               ORDER BY created_at DESC 
               LIMIT $2 OFFSET $3`;
    } else if (role === 'driver') {
      query = `SELECT * FROM deliveries 
               WHERE driver_id = $1
               ORDER BY created_at DESC 
               LIMIT $2 OFFSET $3`;
    } else {
      throw new Error('Invalid role');
    }

    const result = await pool.query(query, [userId, limit, offset]);
    return result.rows;
  }

  /**
   * Note une livraison
   */
  async rateDelivery(deliveryId, userId, rating, comment, role) {
    const delivery = await pool.query('SELECT * FROM deliveries WHERE id = $1', [deliveryId]);

    if (delivery.rows.length === 0) {
      throw new Error('Delivery not found');
    }

    const deliveryData = delivery.rows[0];

    // Vérifier que la livraison est terminée
    if (deliveryData.status !== 'DELIVERED') {
      throw new Error('Can only rate completed deliveries');
    }

    // Vérifier les permissions
    if (role === 'client' && deliveryData.client_id !== userId) {
      throw new Error('Unauthorized');
    }
    if (role === 'driver' && deliveryData.driver_id !== userId) {
      throw new Error('Unauthorized');
    }
    if (role === 'recipient' && deliveryData.recipient_id !== userId) {
      throw new Error('Unauthorized');
    }

    // Mettre à jour la note
    let updateQuery;
    if (role === 'client') {
      updateQuery = `UPDATE deliveries 
                     SET client_rating = $1, client_review = $2
                     WHERE id = $3
                     RETURNING *`;
    } else if (role === 'driver') {
      updateQuery = `UPDATE deliveries 
                     SET driver_rating = $1, driver_review = $2
                     WHERE id = $3
                     RETURNING *`;
    } else if (role === 'recipient') {
      updateQuery = `UPDATE deliveries 
                     SET recipient_rating = $1, recipient_review = $2
                     WHERE id = $3
                     RETURNING *`;
    } else {
      throw new Error('Invalid role');
    }

    const result = await pool.query(updateQuery, [rating, comment, deliveryId]);

    return result.rows[0];
  }

  /**
   * Marque NO_SHOW_CLIENT (client/expéditeur ne s'est pas présenté)
   */
  async markNoShowClient(deliveryId, driverId) {
    const delivery = await pool.query('SELECT * FROM deliveries WHERE id = $1 AND driver_id = $2', [deliveryId, driverId]);
    if (delivery.rows.length === 0) {
      throw new Error('Delivery not found or unauthorized');
    }

    const oldStatus = delivery.rows[0].status;
    if (oldStatus !== 'ASSIGNED') {
      throw new Error(`Cannot mark no-show in status: ${oldStatus}`);
    }

    await pool.query(
      `UPDATE deliveries 
       SET status = 'NO_SHOW_CLIENT', cancelled_at = NOW(), cancellation_reason = 'Client/expéditeur ne s\'est pas présenté'
       WHERE id = $1`,
      [deliveryId]
    );

    await this.recordStatusChange(deliveryId, oldStatus, 'NO_SHOW_CLIENT', driverId, 'driver', 'Client no-show');
    await pool.query('UPDATE driver_profiles SET is_available = true WHERE user_id = $1', [driverId]);

    return await pool.query('SELECT * FROM deliveries WHERE id = $1', [deliveryId]).then(r => r.rows[0]);
  }

  /**
   * Marque PACKAGE_REFUSED (colis refusé par destinataire)
   */
  async markPackageRefused(deliveryId, driverId, reason) {
    const delivery = await pool.query('SELECT * FROM deliveries WHERE id = $1 AND driver_id = $2', [deliveryId, driverId]);
    if (delivery.rows.length === 0) {
      throw new Error('Delivery not found or unauthorized');
    }

    const oldStatus = delivery.rows[0].status;
    if (oldStatus !== 'IN_TRANSIT' && oldStatus !== 'DELIVERED') {
      throw new Error(`Cannot mark refused in status: ${oldStatus}`);
    }

    await pool.query(
      `UPDATE deliveries 
       SET status = 'PACKAGE_REFUSED', cancellation_reason = $1
       WHERE id = $2`,
      [reason || 'Colis refusé par le destinataire', deliveryId]
    );

    await this.recordStatusChange(deliveryId, oldStatus, 'PACKAGE_REFUSED', driverId, 'driver', reason || 'Package refused');
    
    // Créer retour
    await pool.query(
      `INSERT INTO delivery_returns (delivery_id, return_reason, return_initiated_by, return_type, status)
       VALUES ($1, $2, 'driver', 'permanent', 'pending')
       ON CONFLICT DO NOTHING`,
      [deliveryId, reason || 'Package refused by recipient']
    );

    await pool.query('UPDATE driver_profiles SET is_available = true WHERE user_id = $1', [driverId]);

    return await pool.query('SELECT * FROM deliveries WHERE id = $1', [deliveryId]).then(r => r.rows[0]);
  }

  /**
   * Marque DELIVERY_FAILED (échec livraison)
   */
  async markDeliveryFailed(deliveryId, driverId, reason) {
    const delivery = await pool.query('SELECT * FROM deliveries WHERE id = $1 AND driver_id = $2', [deliveryId, driverId]);
    if (delivery.rows.length === 0) {
      throw new Error('Delivery not found or unauthorized');
    }

    const oldStatus = delivery.rows[0].status;
    if (oldStatus !== 'IN_TRANSIT') {
      throw new Error(`Cannot mark failed in status: ${oldStatus}`);
    }

    await pool.query(
      `UPDATE deliveries 
       SET status = 'DELIVERY_FAILED', cancellation_reason = $1, cancelled_at = NOW()
       WHERE id = $2`,
      [reason || 'Échec de livraison', deliveryId]
    );

    await this.recordStatusChange(deliveryId, oldStatus, 'DELIVERY_FAILED', driverId, 'driver', reason || 'Delivery failed');
    await pool.query('UPDATE driver_profiles SET is_available = true WHERE user_id = $1', [driverId]);

    return await pool.query('SELECT * FROM deliveries WHERE id = $1', [deliveryId]).then(r => r.rows[0]);
  }
}

module.exports = new DeliveriesService();

