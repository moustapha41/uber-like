const pool = require('../../config/database');
const logger = require('../../utils/logger');

/**
 * Notifications Service
 * Handles Push Notifications (Firebase) and SMS (Twilio/Africas Talking)
 */

class NotificationService {
  /**
   * Send push notification via Firebase
   * @param {number} userId - ID de l'utilisateur
   * @param {string} title - Titre de la notification
   * @param {string} body - Corps de la notification
   * @param {Object} data - Données supplémentaires
   * @returns {Object} Résultat de l'envoi
   */
  async sendPushNotification(userId, title, body, data = {}) {
    try {
      // TODO: Implémenter Firebase Cloud Messaging
      // Pour l'instant, on log et on enregistre dans la DB
      
      // Enregistrer la notification dans la DB (si table notifications existe)
      try {
        await pool.query(
          `INSERT INTO notifications (user_id, type, title, body, data, created_at)
           VALUES ($1, 'push', $2, $3, $4, NOW())
           ON CONFLICT DO NOTHING`,
          [userId, title, body, JSON.stringify(data)]
        );
      } catch (error) {
        // Table notifications n'existe pas encore, ignorer
      }

      logger.info('Push notification sent', { userId, title, body });
      
      // TODO: Intégrer Firebase Cloud Messaging
      // const fcmToken = await this.getFCMToken(userId);
      // if (fcmToken) {
      //   await admin.messaging().send({
      //     token: fcmToken,
      //     notification: { title, body },
      //     data: data
      //   });
      // }

      return { success: true, method: 'push', userId, title, body };
    } catch (error) {
      logger.error('Error sending push notification', { error: error.message, userId });
      return { success: false, error: error.message };
    }
  }

  /**
   * Send SMS via Twilio or Africas Talking
   * @param {string} phoneNumber - Numéro de téléphone
   * @param {string} message - Message SMS
   * @returns {Object} Résultat de l'envoi
   */
  async sendSMS(phoneNumber, message) {
    try {
      // TODO: Implémenter SMS service (Twilio/Africas Talking)
      
      logger.info('SMS sent', { phoneNumber, messageLength: message.length });
      
      // TODO: Intégrer Twilio ou Africas Talking
      // if (process.env.TWILIO_ACCOUNT_SID) {
      //   await twilioClient.messages.create({
      //     body: message,
      //     from: process.env.TWILIO_PHONE_NUMBER,
      //     to: phoneNumber
      //   });
      // }

      return { success: true, method: 'sms', phoneNumber };
    } catch (error) {
      logger.error('Error sending SMS', { error: error.message, phoneNumber });
      return { success: false, error: error.message };
    }
  }

  /**
   * Send notification for ride status update
   * @param {number} userId - ID de l'utilisateur
   * @param {number} rideId - ID de la course
   * @param {string} status - Nouveau statut
   * @returns {Object} Résultat
   */
  async notifyRideStatus(userId, rideId, status) {
    try {
      const statusMessages = {
        'DRIVER_ASSIGNED': {
          title: 'Chauffeur assigné',
          body: 'Votre chauffeur arrive bientôt'
        },
        'DRIVER_ARRIVED': {
          title: 'Chauffeur arrivé',
          body: 'Votre chauffeur est arrivé au point de prise en charge'
        },
        'IN_PROGRESS': {
          title: 'Course en cours',
          body: 'Votre course a démarré'
        },
        'COMPLETED': {
          title: 'Course terminée',
          body: 'Votre course est terminée. Veuillez régler.'
        },
        'CANCELLED_BY_DRIVER': {
          title: 'Course annulée',
          body: 'Le chauffeur a annulé la course'
        },
        'CANCELLED_BY_SYSTEM': {
          title: 'Course annulée',
          body: 'Aucun chauffeur disponible'
        }
      };

      const message = statusMessages[status] || {
        title: 'Mise à jour course',
        body: `Statut de la course: ${status}`
      };

      await this.sendPushNotification(userId, message.title, message.body, {
        rideId,
        status,
        type: 'ride_status_update'
      });

      return { success: true };
    } catch (error) {
      logger.error('Error notifying ride status', { error: error.message, userId, rideId });
      return { success: false, error: error.message };
    }
  }

  /**
   * Send payment request notification
   * @param {number} userId - ID du client
   * @param {number} rideId - ID de la course
   * @param {number} amount - Montant à payer
   * @returns {Object} Résultat
   */
  async sendPaymentRequest(userId, rideId, amount) {
    try {
      await this.sendPushNotification(
        userId,
        'Paiement requis',
        `Veuillez régler votre course de ${amount} FCFA`,
        {
          rideId,
          amount,
          type: 'payment_request'
        }
      );

      return { success: true };
    } catch (error) {
      logger.error('Error sending payment request', { error: error.message, userId, rideId });
      return { success: false, error: error.message };
    }
  }

  /**
   * Send notification for delivery status update
   * @param {number} userId - ID de l'utilisateur
   * @param {number} deliveryId - ID de la livraison
   * @param {string} status - Nouveau statut
   * @returns {Object} Résultat
   */
  async notifyDeliveryStatus(userId, deliveryId, status) {
    try {
      // TODO: Implémenter notifications livraison
      logger.info('Delivery status notification', { userId, deliveryId, status });
      return { success: true };
    } catch (error) {
      logger.error('Error notifying delivery status', { error: error.message, userId, deliveryId });
      return { success: false, error: error.message };
    }
  }
}

module.exports = new NotificationService();

