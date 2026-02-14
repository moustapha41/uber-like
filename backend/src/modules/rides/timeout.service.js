const pool = require('../../config/database');
const notificationService = require('../notifications/service');
const logger = require('../../utils/logger');

/**
 * Timeout Service - Gestion centralisée des timeouts
 * Remplace les setTimeout() dans l'API pour robustesse
 */

class TimeoutService {
  /**
   * Crée un timeout pour une course ou une livraison
   * @param {number} entityId - ID de la course ou livraison
   * @param {string} timeoutType - Type de timeout (NO_DRIVER, CLIENT_NO_SHOW, etc.)
   * @param {number} delayMs - Délai en millisecondes
   * @param {string} entityType - 'ride' ou 'delivery' (défaut: 'ride')
   */
  async scheduleTimeout(entityId, timeoutType, delayMs, entityType = 'ride') {
    try {
      const executeAt = new Date(Date.now() + delayMs);
      const tableName = entityType === 'delivery' ? 'delivery_timeouts' : 'ride_timeouts';
      const idColumn = entityType === 'delivery' ? 'delivery_id' : 'ride_id';

      await pool.query(
        `INSERT INTO ${tableName} (${idColumn}, timeout_type, execute_at)
         VALUES ($1, $2, $3)
         ON CONFLICT (${idColumn}, timeout_type) 
         DO UPDATE SET execute_at = $3, processed = false`,
        [entityId, timeoutType, executeAt]
      );

      logger.info('Timeout scheduled', { entityId, timeoutType, executeAt, entityType });
    } catch (error) {
      logger.error('Error scheduling timeout', error, { entityId, timeoutType, entityType });
    }
  }

  /**
   * Traite les timeouts expirés (à appeler périodiquement via cron)
   */
  async processExpiredTimeouts() {
    try {
      // Traiter les timeouts de courses
      const expiredRideTimeouts = await pool.query(
        `SELECT *, 'ride' as entity_type FROM ride_timeouts 
         WHERE processed = false AND execute_at <= NOW()
         ORDER BY execute_at ASC
         LIMIT 100`
      );

      for (const timeout of expiredRideTimeouts.rows) {
        await this.handleTimeout(timeout, 'ride');
      }

      // Traiter les timeouts de livraisons
      const expiredDeliveryTimeouts = await pool.query(
        `SELECT *, 'delivery' as entity_type FROM delivery_timeouts 
         WHERE processed = false AND execute_at <= NOW()
         ORDER BY execute_at ASC
         LIMIT 100`
      );

      for (const timeout of expiredDeliveryTimeouts.rows) {
        await this.handleTimeout(timeout, 'delivery');
      }

      return expiredRideTimeouts.rows.length + expiredDeliveryTimeouts.rows.length;
    } catch (error) {
      logger.error('Error processing expired timeouts', error);
      return 0;
    }
  }

  /**
   * Gère un timeout spécifique
   * @param {object} timeout - Objet timeout avec ride_id/delivery_id et timeout_type
   * @param {string} entityType - 'ride' ou 'delivery'
   */
  async handleTimeout(timeout, entityType = 'ride') {
    const entityId = entityType === 'delivery' ? timeout.delivery_id : timeout.ride_id;
    const timeoutType = timeout.timeout_type;
    const tableName = entityType === 'delivery' ? 'deliveries' : 'rides';
    const idColumn = entityType === 'delivery' ? 'delivery_id' : 'ride_id';

    try {
      // Charger le service approprié
      const service = entityType === 'delivery' 
        ? require('../deliveries/deliveries.service')
        : require('./rides.service');

      // Vérifier que l'entité existe toujours et est dans le bon statut
      const entity = await pool.query(
        `SELECT * FROM ${tableName} WHERE id = $1`,
        [entityId]
      );

      if (entity.rows.length === 0) {
        // Entité supprimée, marquer le timeout comme traité
        await this.markTimeoutProcessed(timeout.id, entityType);
        return;
      }

      const entityData = entity.rows[0];

      switch (timeoutType) {
        case 'NO_DRIVER':
          // Aucun driver n'a accepté dans les délais
          if (entityData.status === 'REQUESTED') {
            const cancelMethod = entityType === 'delivery' ? 'cancelDelivery' : 'cancelRide';
            await service[cancelMethod](
              entityId,
              'system',
              'Aucun driver disponible dans les délais'
            );
            await notificationService.sendPushNotification(
              entityData.client_id,
              entityType === 'delivery' ? 'Livraison annulée' : 'Course annulée',
              'Aucun chauffeur disponible. Veuillez réessayer.',
              { 
                type: entityType === 'delivery' ? 'delivery_cancelled' : 'ride_cancelled',
                [entityType === 'delivery' ? 'delivery_id' : 'ride_id']: entityId
              }
            );
          }
          break;

        case 'CLIENT_NO_SHOW':
        case 'PICKUP_TIMEOUT':
          // Client/expéditeur ne s'est pas présenté après l'arrivée du driver
          const arrivedStatus = entityType === 'delivery' ? 'ASSIGNED' : 'DRIVER_ARRIVED';
          if (entityData.status === arrivedStatus) {
            const cancelMethod = entityType === 'delivery' ? 'cancelDelivery' : 'cancelRide';
            await service[cancelMethod](
              entityId,
              'driver',
              entityType === 'delivery' 
                ? 'Expéditeur ne s\'est pas présenté dans les délais'
                : 'Client ne s\'est pas présenté dans les délais'
            );
            // TODO: Facturer pénalité au client si nécessaire
          }
          break;

        case 'PAYMENT_TIMEOUT':
          // Paiement non effectué après X temps
          const completedStatus = entityType === 'delivery' ? 'DELIVERED' : 'COMPLETED';
          if (entityData.status === completedStatus && entityData.payment_status === 'PAYMENT_PENDING') {
            // Marquer comme échec de paiement
            await pool.query(
              `UPDATE ${tableName} 
               SET payment_status = 'PAYMENT_FAILED'
               WHERE id = $1`,
              [entityId]
            );
            // TODO: Notifier le support pour intervention manuelle
          }
          break;

        default:
          logger.warn('Unknown timeout type', { timeoutType, entityId, entityType });
      }

      // Marquer le timeout comme traité
      await this.markTimeoutProcessed(timeout.id, entityType);
    } catch (error) {
      logger.error('Error handling timeout', error, { entityId, timeoutType, entityType });
    }
  }

  /**
   * Marque un timeout comme traité
   */
  async markTimeoutProcessed(timeoutId, entityType = 'ride') {
    const tableName = entityType === 'delivery' ? 'delivery_timeouts' : 'ride_timeouts';
    await pool.query(
      `UPDATE ${tableName} 
       SET processed = true
       WHERE id = $1`,
      [timeoutId]
    );
  }

  /**
   * Annule un timeout programmé (si l'entité est traitée avant)
   */
  async cancelTimeout(entityId, timeoutType, entityType = 'ride') {
    const tableName = entityType === 'delivery' ? 'delivery_timeouts' : 'ride_timeouts';
    const idColumn = entityType === 'delivery' ? 'delivery_id' : 'ride_id';
    await pool.query(
      `UPDATE ${tableName} 
       SET processed = true
       WHERE ${idColumn} = $1 AND timeout_type = $2 AND processed = false`,
      [entityId, timeoutType]
    );
  }
}

module.exports = new TimeoutService();

