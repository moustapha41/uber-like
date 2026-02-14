const pool = require('../../config/database');
const logger = require('../../utils/logger');

/**
 * Wallet Service
 * Gère le portefeuille électronique et les transactions
 */

class WalletService {
  /**
   * Crée un wallet pour un utilisateur
   * @param {number} userId - ID de l'utilisateur
   * @returns {Object} Wallet créé
   */
  async createWallet(userId) {
    try {
      // Vérifier si le wallet existe déjà
      const existing = await pool.query(
        'SELECT id FROM wallets WHERE user_id = $1',
        [userId]
      );

      if (existing.rows.length > 0) {
        return existing.rows[0];
      }

      // Créer le wallet
      const result = await pool.query(
        `INSERT INTO wallets (user_id, balance, currency, is_active)
         VALUES ($1, 0.00, 'XOF', true)
         RETURNING *`,
        [userId]
      );

      logger.info('Wallet created', { userId, walletId: result.rows[0].id });

      return result.rows[0];
    } catch (error) {
      logger.error('Error creating wallet', { error: error.message, userId });
      throw error;
    }
  }

  /**
   * Récupère le wallet d'un utilisateur
   * @param {number} userId - ID de l'utilisateur
   * @returns {Object} Wallet
   */
  async getWallet(userId) {
    try {
      const result = await pool.query(
        'SELECT * FROM wallets WHERE user_id = $1 AND is_active = true',
        [userId]
      );

      if (result.rows.length === 0) {
        // Créer le wallet s'il n'existe pas
        return await this.createWallet(userId);
      }

      return result.rows[0];
    } catch (error) {
      logger.error('Error getting wallet', { error: error.message, userId });
      throw error;
    }
  }

  /**
   * Récupère le solde d'un utilisateur
   * @param {number} userId - ID de l'utilisateur
   * @returns {number} Solde en FCFA
   */
  async getBalance(userId) {
    try {
      const wallet = await this.getWallet(userId);
      return parseFloat(wallet.balance);
    } catch (error) {
      logger.error('Error getting balance', { error: error.message, userId });
      throw error;
    }
  }

  /**
   * Crédite un wallet
   * @param {number} userId - ID de l'utilisateur
   * @param {number} amount - Montant à créditer
   * @param {Object} options - Options (description, reference_type, reference_id, metadata)
   * @returns {Object} Transaction créée
   */
  async credit(userId, amount, options = {}) {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // Récupérer le wallet avec verrou
      const walletResult = await client.query(
        'SELECT * FROM wallets WHERE user_id = $1 FOR UPDATE',
        [userId]
      );

      if (walletResult.rows.length === 0) {
        await client.query('ROLLBACK');
        throw new Error('Wallet not found');
      }

      const wallet = walletResult.rows[0];
      const balanceBefore = parseFloat(wallet.balance);
      const balanceAfter = balanceBefore + amount;

      // Mettre à jour le solde
      await client.query(
        'UPDATE wallets SET balance = $1, updated_at = NOW() WHERE id = $2',
        [balanceAfter, wallet.id]
      );

      // Créer la transaction
      const transactionResult = await client.query(
        `INSERT INTO transactions (
          wallet_id, user_id, type, amount, balance_before, balance_after,
          reference_type, reference_id, description, metadata, status, processed_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW())
        RETURNING *`,
        [
          wallet.id,
          userId,
          'credit',
          amount,
          balanceBefore,
          balanceAfter,
          options.reference_type || null,
          options.reference_id || null,
          options.description || `Crédit de ${amount} FCFA`,
          options.metadata ? JSON.stringify(options.metadata) : null,
          'completed'
        ]
      );

      await client.query('COMMIT');

      logger.info('Wallet credited', { userId, amount, balanceAfter });

      return transactionResult.rows[0];
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Error crediting wallet', { error: error.message, userId, amount });
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Débite un wallet
   * @param {number} userId - ID de l'utilisateur
   * @param {number} amount - Montant à débiter
   * @param {Object} options - Options (description, reference_type, reference_id, metadata)
   * @returns {Object} Transaction créée
   */
  async debit(userId, amount, options = {}) {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // Récupérer le wallet avec verrou
      const walletResult = await client.query(
        'SELECT * FROM wallets WHERE user_id = $1 FOR UPDATE',
        [userId]
      );

      if (walletResult.rows.length === 0) {
        await client.query('ROLLBACK');
        throw new Error('Wallet not found');
      }

      const wallet = walletResult.rows[0];
      const balanceBefore = parseFloat(wallet.balance);

      // Vérifier que le solde est suffisant
      if (balanceBefore < amount) {
        await client.query('ROLLBACK');
        throw new Error('Insufficient balance');
      }

      const balanceAfter = balanceBefore - amount;

      // Mettre à jour le solde
      await client.query(
        'UPDATE wallets SET balance = $1, updated_at = NOW() WHERE id = $2',
        [balanceAfter, wallet.id]
      );

      // Créer la transaction
      const transactionResult = await client.query(
        `INSERT INTO transactions (
          wallet_id, user_id, type, amount, balance_before, balance_after,
          reference_type, reference_id, description, metadata, status, processed_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, NOW())
        RETURNING *`,
        [
          wallet.id,
          userId,
          'debit',
          amount,
          balanceBefore,
          balanceAfter,
          options.reference_type || null,
          options.reference_id || null,
          options.description || `Débit de ${amount} FCFA`,
          options.metadata ? JSON.stringify(options.metadata) : null,
          'completed'
        ]
      );

      await client.query('COMMIT');

      logger.info('Wallet debited', { userId, amount, balanceAfter });

      return transactionResult.rows[0];
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Error debiting wallet', { error: error.message, userId, amount });
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Traite le paiement d'une course depuis le wallet
   * @param {number} rideId - ID de la course
   * @param {number} clientId - ID du client
   * @param {number} amount - Montant à payer
   * @param {number} driverId - ID du driver (pour crédit)
   * @param {number} commissionRate - Taux de commission (défaut: 20%)
   * @returns {Object} { success, clientTransaction, driverTransaction, commission }
   */
  async processRidePayment(rideId, clientId, amount, driverId, commissionRate = 20) {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');

      // Calculer la commission et le revenu driver
      const commission = Math.round(amount * (commissionRate / 100));
      const driverEarnings = amount - commission;

      // Débiter le client
      const clientTransaction = await this.debit(clientId, amount, {
        reference_type: 'ride',
        reference_id: rideId,
        description: `Paiement course #${rideId}`,
        metadata: { rideId, amount, commissionRate }
      });

      // Créditer le driver
      const driverTransaction = await this.credit(driverId, driverEarnings, {
        reference_type: 'ride',
        reference_id: rideId,
        description: `Revenus course #${rideId} (commission: ${commission} FCFA)`,
        metadata: { rideId, amount, driverEarnings, commission, commissionRate }
      });

      // Créer une transaction commission (pour tracking)
      const commissionTransaction = await client.query(
        `INSERT INTO transactions (
          wallet_id, user_id, type, amount, balance_before, balance_after,
          reference_type, reference_id, description, metadata, status, processed_at
        )
        SELECT wallet_id, $1, 'commission', $2, balance, balance, 'ride', $3, 
               'Commission plateforme course #' || $3, 
               '{"rideId": ' || $3 || ', "commissionRate": ' || $4 || '}'::jsonb,
               'completed', NOW()
        FROM wallets WHERE user_id = $1
        RETURNING *`,
        [clientId, commission, rideId, commissionRate]
      );

      await client.query('COMMIT');

      logger.info('Ride payment processed', { 
        rideId, 
        clientId, 
        driverId, 
        amount, 
        commission, 
        driverEarnings 
      });

      return {
        success: true,
        clientTransaction,
        driverTransaction,
        commissionTransaction: commissionTransaction.rows[0],
        commission,
        driverEarnings
      };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Error processing ride payment', {
        error: error.message,
        rideId,
        clientId
      });
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Crédite le driver après un paiement externe (Mobile Money / PayTech)
   * Pas de débit client (l'argent est reçu via PayTech).
   * @param {number} rideId - ID de la course
   * @param {number} clientId - ID du client (pour référence)
   * @param {number} driverId - ID du driver à créditer
   * @param {number} amount - Montant total payé
   * @param {number} commissionRate - Taux de commission (%)
   */
  async creditDriverForExternalPayment(rideId, clientId, driverId, amount, commissionRate = 20) {
    const commission = Math.round(amount * (commissionRate / 100));
    const driverEarnings = amount - commission;
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const driverTransaction = await this.credit(driverId, driverEarnings, {
        reference_type: 'ride',
        reference_id: rideId,
        description: `Revenus course #${rideId} (paiement Mobile Money, commission: ${commission} FCFA)`,
        metadata: { rideId, amount, driverEarnings, commission, commissionRate, source: 'mobile_money' }
      });
      await client.query(
        `INSERT INTO transactions (
          wallet_id, user_id, type, amount, balance_before, balance_after,
          reference_type, reference_id, description, metadata, status, processed_at
        )
        SELECT wallet_id, $1, 'commission', $2, balance, balance, 'ride', $3,
               'Commission plateforme course #' || $3, '{"rideId": ' || $3 || ', "commissionRate": ' || $4 || ', "source": "mobile_money"}'::jsonb,
               'completed', NOW()
        FROM wallets WHERE user_id = $1
        RETURNING *`,
        [clientId, commission, rideId, commissionRate]
      );
      await client.query('COMMIT');
      logger.info('Driver credited for external payment', { rideId, driverId, amount, driverEarnings });
      return { success: true, driverEarnings, commission };
    } catch (error) {
      await client.query('ROLLBACK');
      logger.error('Error crediting driver for external payment', { error: error.message, rideId });
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Crédite le driver après paiement externe pour une livraison (Mobile Money)
   */
  async creditDriverForDeliveryExternalPayment(deliveryId, clientId, driverId, amount, commissionRate = 20) {
    const commission = Math.round(amount * (commissionRate / 100));
    const driverEarnings = amount - commission;
    await this.credit(driverId, driverEarnings, {
      reference_type: 'delivery',
      reference_id: deliveryId,
      description: `Revenus livraison #${deliveryId} (paiement Mobile Money)`,
      metadata: { deliveryId, amount, driverEarnings, commission, commissionRate, source: 'mobile_money' }
    });
    logger.info('Driver credited for delivery external payment', { deliveryId, driverId, amount });
    return { success: true, driverEarnings, commission };
  }

  /**
   * Récupère l'historique des transactions d'un utilisateur
   * @param {number} userId - ID de l'utilisateur
   * @param {Object} filters - Filtres (type, status, limit, offset)
   * @returns {Array} Liste des transactions
   */
  async getTransactions(userId, filters = {}) {
    try {
      let query = `
        SELECT t.*, w.balance as current_balance
        FROM transactions t
        INNER JOIN wallets w ON t.wallet_id = w.id
        WHERE t.user_id = $1
      `;

      const params = [userId];
      let paramIndex = 2;

      if (filters.type) {
        query += ` AND t.type = $${paramIndex}`;
        params.push(filters.type);
        paramIndex++;
      }

      if (filters.status) {
        query += ` AND t.status = $${paramIndex}`;
        params.push(filters.status);
        paramIndex++;
      }

      if (filters.reference_type) {
        query += ` AND t.reference_type = $${paramIndex}`;
        params.push(filters.reference_type);
        paramIndex++;
      }

      query += ` ORDER BY t.created_at DESC`;

      const limit = filters.limit || 50;
      const offset = filters.offset || 0;
      query += ` LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
      params.push(limit, offset);

      const result = await pool.query(query, params);
      return result.rows;
    } catch (error) {
      logger.error('Error getting transactions', { error: error.message, userId });
      throw error;
    }
  }

  /**
   * Vérifie si un utilisateur a un solde suffisant
   * @param {number} userId - ID de l'utilisateur
   * @param {number} amount - Montant requis
   * @returns {boolean} True si solde suffisant
   */
  async hasSufficientBalance(userId, amount) {
    try {
      const balance = await this.getBalance(userId);
      return balance >= amount;
    } catch (error) {
      logger.error('Error checking balance', { error: error.message, userId });
      return false;
    }
  }
}

module.exports = new WalletService();

