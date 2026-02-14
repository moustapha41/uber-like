const pool = require('../../config/database');
const notificationService = require('../notifications/service');

/**
 * Matching Service
 * Service dédié au matching progressif des drivers
 * Stratégie: T+0s → driver le plus proche, T+10s → +2, T+20s → +5, T+30s → broadcast
 */

class MatchingService {
  /**
   * Trouve les drivers disponibles proches du point de départ
   * @param {number} pickupLat - Latitude point de départ
   * @param {number} pickupLng - Longitude point de départ
   * @param {number} radiusKm - Rayon de recherche en km
   * @param {number} limit - Nombre maximum de drivers à retourner
   * @param {string} entityType - 'ride' ou 'delivery' (défaut: 'ride')
   * @param {Object} deliveryRequirements - Requirements pour livraison (poids, type, etc.)
   * @returns {Array} Liste des drivers triés par distance
   */
  async findNearbyDrivers(pickupLat, pickupLng, radiusKm = 5, limit = 10, entityType = 'ride', deliveryRequirements = null) {
    try {
      let query = `
        SELECT 
          u.id, u.first_name, u.last_name, u.phone,
          dl.lat, dl.lng, dl.updated_at,
          dp.delivery_capabilities,
          (
            6371 * acos(
              cos(radians($1)) * 
              cos(radians(dl.lat)) * 
              cos(radians(dl.lng) - radians($2)) + 
              sin(radians($1)) * 
              sin(radians(dl.lat))
            )
          ) AS distance_km
        FROM users u
        INNER JOIN driver_profiles dp ON u.id = dp.user_id
        INNER JOIN driver_locations dl ON u.id = dl.driver_id
        WHERE u.role = 'driver'
          AND u.status = 'active'
          AND dp.is_online = true
          AND dp.is_available = true
          AND dl.updated_at > NOW() - INTERVAL '5 minutes'
          AND (
            6371 * acos(
              cos(radians($1)) * 
              cos(radians(dl.lat)) * 
              cos(radians(dl.lng) - radians($2)) + 
              sin(radians($1)) * 
              sin(radians(dl.lat))
            )
          ) <= $3
      `;

      const params = [pickupLat, pickupLng, radiusKm];
      let paramCount = 4;

      // Filtrer selon capacités pour les livraisons
      if (entityType === 'delivery' && deliveryRequirements) {
        const conditions = [];
        
        // Vérifier poids max
        if (deliveryRequirements.package_weight_kg) {
          conditions.push(`(dp.delivery_capabilities->>'max_weight_kg')::numeric >= $${paramCount}`);
          params.push(deliveryRequirements.package_weight_kg);
          paramCount++;
        }

        // Vérifier type de colis
        if (deliveryRequirements.package_type === 'fragile') {
          conditions.push(`(dp.delivery_capabilities->>'can_handle_fragile')::boolean = true`);
        } else if (deliveryRequirements.package_type === 'food') {
          conditions.push(`(dp.delivery_capabilities->>'can_handle_food')::boolean = true`);
          conditions.push(`(dp.delivery_capabilities->>'has_thermal_bag')::boolean = true`);
        } else if (deliveryRequirements.package_type === 'electronics') {
          conditions.push(`(dp.delivery_capabilities->>'can_handle_electronics')::boolean = true`);
        } else if (deliveryRequirements.package_type === 'document') {
          conditions.push(`(dp.delivery_capabilities->>'can_handle_documents')::boolean = true`);
        }

        // Vérifier assurance si requise
        if (deliveryRequirements.insurance_required) {
          conditions.push(`(dp.delivery_capabilities->>'has_insurance_coverage')::boolean = true`);
        }

        if (conditions.length > 0) {
          query += ` AND ${conditions.join(' AND ')}`;
        }
      }

      query += ` ORDER BY distance_km LIMIT $${paramCount}`;
      params.push(limit);

      const result = await pool.query(query, params);

      return result.rows;
    } catch (error) {
      console.error('Error finding nearby drivers:', error);
      return [];
    }
  }

  /**
   * Matching progressif: envoie la demande aux drivers par vagues
   * T+0s → 1 driver le plus proche
   * T+10s → +2 drivers
   * T+20s → +5 drivers
   * T+30s → broadcast large (tous dans le rayon)
   * 
   * @param {number} entityId - ID de la course ou livraison
   * @param {number} pickupLat - Latitude point de départ
   * @param {number} pickupLng - Longitude point de départ
   * @param {string} entityType - 'ride' ou 'delivery' (défaut: 'ride')
   * @param {Object} deliveryRequirements - Requirements pour livraison (optionnel)
   */
  async progressiveMatching(entityId, pickupLat, pickupLng, entityType = 'ride', deliveryRequirements = null) {
    try {
      const tableName = entityType === 'delivery' ? 'deliveries' : 'rides';
      // Vérifier que l'entité existe toujours et est en statut REQUESTED
      const entityCheck = await pool.query(
        `SELECT status FROM ${tableName} WHERE id = $1`,
        [entityId]
      );

      if (entityCheck.rows.length === 0 || entityCheck.rows[0].status !== 'REQUESTED') {
        console.log(`${entityType === 'delivery' ? 'Delivery' : 'Ride'} ${entityId} no longer available for matching`);
        return;
      }

      // Récupérer requirements pour livraison si nécessaire
      let deliveryRequirements = null;
      if (entityType === 'delivery') {
        const entityData = await pool.query(`SELECT package_weight_kg, package_type, insurance_required FROM ${tableName} WHERE id = $1`, [entityId]);
        if (entityData.rows.length > 0) {
          deliveryRequirements = entityData.rows[0];
        }
      }

      // Vague 1: T+0s → 1 driver le plus proche
      const wave1 = await this.findNearbyDrivers(pickupLat, pickupLng, 5, 1, entityType, deliveryRequirements);
      if (wave1.length > 0) {
        await this.notifyDrivers(wave1, entityId, pickupLat, pickupLng, entityType);
      }

      // Préparer les vagues suivantes dans un scope partagé
      let wave2 = [];
      let wave3 = [];

      // Vague 2: T+10s → +2 drivers (total 3)
      setTimeout(async () => {
        const entityCheck2 = await pool.query(
          `SELECT status FROM ${tableName} WHERE id = $1`,
          [entityId]
        );
        if (entityCheck2.rows.length > 0 && entityCheck2.rows[0].status === 'REQUESTED') {
          wave2 = await this.findNearbyDrivers(pickupLat, pickupLng, 5, 3, entityType, deliveryRequirements);
          // Exclure ceux déjà notifiés
          const newDrivers = wave2.filter(
            d => !wave1.some(w1 => w1.id === d.id)
          );
          if (newDrivers.length > 0) {
            await this.notifyDrivers(newDrivers, entityId, pickupLat, pickupLng, entityType);
          }
        }
      }, 10000); // 10 secondes

      // Vague 3: T+20s → +5 drivers (total 8)
      setTimeout(async () => {
        const entityCheck3 = await pool.query(
          `SELECT status FROM ${tableName} WHERE id = $1`,
          [entityId]
        );
        if (entityCheck3.rows.length > 0 && entityCheck3.rows[0].status === 'REQUESTED') {
          wave3 = await this.findNearbyDrivers(pickupLat, pickupLng, 5, 8, entityType, deliveryRequirements);
          const alreadyNotified = [...wave1, ...(wave2 || [])];
          const newDrivers = wave3.filter(
            d => !alreadyNotified.some(an => an.id === d.id)
          );
          if (newDrivers.length > 0) {
            await this.notifyDrivers(newDrivers, entityId, pickupLat, pickupLng, entityType);
          }
        }
      }, 20000); // 20 secondes

      // Vague 4: T+30s → broadcast large (rayon étendu à 10km)
      setTimeout(async () => {
        const entityCheck4 = await pool.query(
          `SELECT status FROM ${tableName} WHERE id = $1`,
          [entityId]
        );
        if (entityCheck4.rows.length > 0 && entityCheck4.rows[0].status === 'REQUESTED') {
          const wave4 = await this.findNearbyDrivers(pickupLat, pickupLng, 10, 20, entityType, deliveryRequirements);
          const alreadyNotified = [...wave1, ...(wave2 || []), ...wave3];
          const newDrivers = wave4.filter(
            d => !alreadyNotified.some(an => an.id === d.id)
          );
          if (newDrivers.length > 0) {
            await this.notifyDrivers(newDrivers, entityId, pickupLat, pickupLng, entityType);
          }

          // Si toujours pas de driver après 30s, programmer l'annulation
          setTimeout(async () => {
            const finalCheck = await pool.query(
              `SELECT status FROM ${tableName} WHERE id = $1`,
              [entityId]
            );
            if (finalCheck.rows.length > 0 && finalCheck.rows[0].status === 'REQUESTED') {
              // Annuler automatiquement après 2-3 minutes total
              if (entityType === 'delivery') {
                const deliveriesService = require('../deliveries/deliveries.service');
                await deliveriesService.cancelDelivery(
                  entityId,
                  'system',
                  'Aucun driver disponible dans les délais'
                );
              } else {
                const ridesService = require('./rides.service');
                await ridesService.cancelRide(
                  entityId,
                  'system',
                  'Aucun driver disponible dans les délais'
                );
              }
            }
          }, 90000); // +90s = 2 minutes total
        }
      }, 30000); // 30 secondes
    } catch (error) {
      console.error('Error in progressive matching:', error);
    }
  }

  /**
   * Envoie une notification aux drivers
   */
  async notifyDrivers(drivers, entityId, pickupLat, pickupLng, entityType = 'ride') {
    const entityName = entityType === 'delivery' ? 'livraison' : 'course';
    const notificationType = entityType === 'delivery' ? 'new_delivery_request' : 'new_ride_request';
    const entityIdKey = entityType === 'delivery' ? 'delivery_id' : 'ride_id';

    for (const driver of drivers) {
      try {
        await notificationService.sendPushNotification(
          driver.id,
          `Nouvelle demande de ${entityName}`,
          `Une ${entityName} est disponible à ${Math.round(driver.distance_km * 1000)}m de vous`,
          {
            type: notificationType,
            [entityIdKey]: entityId,
            pickup_lat: pickupLat,
            pickup_lng: pickupLng,
            distance_km: driver.distance_km
          }
        );

        // TODO: Émettre événement WebSocket
        // socketIO.to(`driver_${driver.id}`).emit(`new-${entityType}-request`, { [entityIdKey]: entityId, ... });
      } catch (error) {
        console.error(`Error notifying driver ${driver.id}:`, error);
      }
    }
  }
}

module.exports = new MatchingService();

