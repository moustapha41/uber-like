const pool = require('../../config/database');
const bcrypt = require('bcryptjs');
const logger = require('../../utils/logger');

/**
 * Users Service
 * Gère toute la logique métier des utilisateurs et drivers
 */

class UsersService {
  /**
   * Crée un nouvel utilisateur
   * @param {Object} userData - Données de l'utilisateur
   * @returns {Object} Utilisateur créé
   */
  async createUser(userData) {
    const {
      email,
      phone,
      password,
      first_name,
      last_name,
      role = 'client',
      status = 'active'
    } = userData;

    try {
      // Vérifier que l'email n'existe pas déjà
      const existingUser = await pool.query(
        'SELECT id FROM users WHERE email = $1 OR phone = $2',
        [email, phone]
      );

      if (existingUser.rows.length > 0) {
        throw new Error('Email or phone already exists');
      }

      // Hasher le mot de passe
      const saltRounds = 10;
      const password_hash = await bcrypt.hash(password, saltRounds);

      // Créer l'utilisateur
      const result = await pool.query(
        `INSERT INTO users (email, phone, password_hash, first_name, last_name, role, status)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING id, email, phone, first_name, last_name, role, status, created_at`,
        [email, phone, password_hash, first_name, last_name, role, status]
      );

      const user = result.rows[0];

      // Si c'est un driver, créer le profil driver
      if (role === 'driver') {
        await this.createDriverProfile(user.id);
      }

      logger.info('User created', { userId: user.id, email, role });

      return user;
    } catch (error) {
      logger.error('Error creating user', { error: error.message, email });
      throw error;
    }
  }

  /**
   * Crée un profil driver pour un utilisateur
   * @param {number} userId - ID de l'utilisateur
   * @param {Object} driverData - Données du driver (optionnel)
   * @returns {Object} Profil driver créé
   */
  async createDriverProfile(userId, driverData = {}) {
    try {
      // Vérifier que l'utilisateur existe et est un driver
      const user = await pool.query(
        'SELECT id, role FROM users WHERE id = $1',
        [userId]
      );

      if (user.rows.length === 0) {
        throw new Error('User not found');
      }

      if (user.rows[0].role !== 'driver') {
        throw new Error('User is not a driver');
      }

      // Vérifier que le profil n'existe pas déjà
      const existingProfile = await pool.query(
        'SELECT id FROM driver_profiles WHERE user_id = $1',
        [userId]
      );

      if (existingProfile.rows.length > 0) {
        throw new Error('Driver profile already exists');
      }

      // Créer le profil driver
      const result = await pool.query(
        `INSERT INTO driver_profiles (
          user_id, license_number, license_expiry, vehicle_type, vehicle_plate,
          insurance_number, insurance_expiry, verification_status
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING *`,
        [
          userId,
          driverData.license_number || null,
          driverData.license_expiry || null,
          driverData.vehicle_type || 'motorcycle',
          driverData.vehicle_plate || null,
          driverData.insurance_number || null,
          driverData.insurance_expiry || null,
          'pending' // En attente de vérification
        ]
      );

      logger.info('Driver profile created', { userId, profileId: result.rows[0].id });

      return result.rows[0];
    } catch (error) {
      logger.error('Error creating driver profile', { error: error.message, userId });
      throw error;
    }
  }

  /**
   * Récupère un utilisateur par ID
   * @param {number} userId - ID de l'utilisateur
   * @returns {Object} Utilisateur
   */
  async getUserById(userId) {
    try {
      const result = await pool.query(
        `SELECT id, email, phone, first_name, last_name, role, status, 
                avatar_url, created_at, updated_at, email_verified, phone_verified
         FROM users 
         WHERE id = $1 AND deleted_at IS NULL`,
        [userId]
      );

      if (result.rows.length === 0) {
        throw new Error('User not found');
      }

      return result.rows[0];
    } catch (error) {
      logger.error('Error getting user by id', { error: error.message, userId });
      throw error;
    }
  }

  /**
   * Récupère un utilisateur par email
   * @param {string} email - Email de l'utilisateur
   * @returns {Object} Utilisateur
   */
  async getUserByEmail(email) {
    try {
      const result = await pool.query(
        `SELECT * FROM users WHERE email = $1 AND deleted_at IS NULL`,
        [email]
      );

      if (result.rows.length === 0) {
        throw new Error('User not found');
      }

      return result.rows[0];
    } catch (error) {
      logger.error('Error getting user by email', { error: error.message, email });
      throw error;
    }
  }

  /**
   * Récupère le profil driver d'un utilisateur
   * @param {number} userId - ID de l'utilisateur
   * @returns {Object} Profil driver
   */
  async getDriverProfile(userId) {
    try {
      const result = await pool.query(
        `SELECT dp.*, u.email, u.phone, u.first_name, u.last_name
         FROM driver_profiles dp
         INNER JOIN users u ON dp.user_id = u.id
         WHERE dp.user_id = $1`,
        [userId]
      );

      if (result.rows.length === 0) {
        throw new Error('Driver profile not found');
      }

      return result.rows[0];
    } catch (error) {
      logger.error('Error getting driver profile', { error: error.message, userId });
      throw error;
    }
  }

  /**
   * Met à jour le statut online/available d'un driver
   * @param {number} driverId - ID du driver
   * @param {boolean} isOnline - Statut online
   * @param {boolean} isAvailable - Statut available
   * @returns {Object} Profil driver mis à jour
   */
  async updateDriverStatus(driverId, isOnline, isAvailable) {
    try {
      const result = await pool.query(
        `UPDATE driver_profiles 
         SET is_online = $1, is_available = $2, last_active_at = NOW()
         WHERE user_id = $3
         RETURNING *`,
        [isOnline, isAvailable, driverId]
      );

      if (result.rows.length === 0) {
        throw new Error('Driver profile not found');
      }

      logger.info('Driver status updated', { driverId, isOnline, isAvailable });

      return result.rows[0];
    } catch (error) {
      logger.error('Error updating driver status', { error: error.message, driverId });
      throw error;
    }
  }

  /**
   * Met à jour la position GPS d'un driver
   * @param {number} driverId - ID du driver
   * @param {number} lat - Latitude
   * @param {number} lng - Longitude
   * @param {number} heading - Direction (0-360)
   * @param {number} speed - Vitesse en km/h
   * @returns {Object} Position mise à jour
   */
  async updateDriverLocation(driverId, lat, lng, heading = null, speed = null) {
    try {
      // Vérifier que le driver existe
      const driver = await pool.query(
        'SELECT id FROM driver_profiles WHERE user_id = $1',
        [driverId]
      );

      if (driver.rows.length === 0) {
        throw new Error('Driver not found');
      }

      // Mettre à jour ou créer la position
      const result = await pool.query(
        `INSERT INTO driver_locations (driver_id, lat, lng, heading, speed_kmh, updated_at)
         VALUES ($1, $2, $3, $4, $5, NOW())
         ON CONFLICT (driver_id) 
         DO UPDATE SET lat = $2, lng = $3, heading = $4, speed_kmh = $5, updated_at = NOW()
         RETURNING *`,
        [driverId, lat, lng, heading, speed]
      );

      return result.rows[0];
    } catch (error) {
      logger.error('Error updating driver location', { error: error.message, driverId });
      throw error;
    }
  }

  /**
   * Met à jour les statistiques d'un driver après une course
   * @param {number} driverId - ID du driver
   * @param {number} rating - Note reçue (1-5)
   * @param {number} distanceKm - Distance parcourue
   * @param {number} earnings - Gains de la course
   */
  async updateDriverStats(driverId, rating = null, distanceKm = 0, earnings = 0) {
    try {
      // Récupérer les stats actuelles
      const current = await pool.query(
        'SELECT total_rides, total_ratings, average_rating, total_earnings, total_distance_km FROM driver_profiles WHERE user_id = $1',
        [driverId]
      );

      if (current.rows.length === 0) {
        throw new Error('Driver profile not found');
      }

      const stats = current.rows[0];
      const newTotalRides = stats.total_rides + 1;
      const newTotalDistance = parseFloat(stats.total_distance_km) + distanceKm;
      const newTotalEarnings = parseFloat(stats.total_earnings) + earnings;

      // Calculer la nouvelle note moyenne
      let newAverageRating = stats.average_rating;
      if (rating) {
        const newTotalRatings = stats.total_ratings + 1;
        const currentTotal = parseFloat(stats.average_rating) * stats.total_ratings;
        newAverageRating = ((currentTotal + rating) / newTotalRatings).toFixed(2);
        
        await pool.query(
          `UPDATE driver_profiles 
           SET total_rides = $1, total_ratings = $2, average_rating = $3,
               total_distance_km = $4, total_earnings = $5
           WHERE user_id = $6`,
          [newTotalRides, newTotalRatings, newAverageRating, newTotalDistance, newTotalEarnings, driverId]
        );
      } else {
        await pool.query(
          `UPDATE driver_profiles 
           SET total_rides = $1, total_distance_km = $2, total_earnings = $3
           WHERE user_id = $4`,
          [newTotalRides, newTotalDistance, newTotalEarnings, driverId]
        );
      }

      logger.info('Driver stats updated', { driverId, newTotalRides, newAverageRating });
    } catch (error) {
      logger.error('Error updating driver stats', { error: error.message, driverId });
      throw error;
    }
  }

  /**
   * Vérifie les credentials d'un utilisateur
   * @param {string} email - Email
   * @param {string} password - Mot de passe
   * @returns {Object} Utilisateur si credentials valides
   */
  async verifyCredentials(email, password) {
    try {
      const user = await this.getUserByEmail(email);

      // Vérifier le mot de passe
      const isValid = await bcrypt.compare(password, user.password_hash);

      if (!isValid) {
        throw new Error('Invalid credentials');
      }

      // Mettre à jour last_login_at
      await pool.query(
        'UPDATE users SET last_login_at = NOW(), failed_login_attempts = 0 WHERE id = $1',
        [user.id]
      );

      // Retourner l'utilisateur sans le password_hash
      delete user.password_hash;
      return user;
    } catch (error) {
      // Incrémenter failed_login_attempts
      try {
        await pool.query(
          'UPDATE users SET failed_login_attempts = failed_login_attempts + 1 WHERE email = $1',
          [email]
        );
      } catch (updateError) {
        // Ignorer si l'utilisateur n'existe pas
      }

      logger.error('Invalid login attempt', { email });
      throw new Error('Invalid credentials');
    }
  }

  /**
   * Liste les drivers disponibles
   * @param {Object} filters - Filtres (status, verified, etc.)
   * @param {number} limit - Limite
   * @param {number} offset - Offset
   * @returns {Array} Liste des drivers
   */
  async listDrivers(filters = {}, limit = 50, offset = 0) {
    try {
      let query = `
        SELECT u.id, u.email, u.phone, u.first_name, u.last_name, u.status,
               dp.*, dl.lat, dl.lng, dl.updated_at as last_location_update
        FROM users u
        INNER JOIN driver_profiles dp ON u.id = dp.user_id
        LEFT JOIN driver_locations dl ON u.id = dl.driver_id
        WHERE u.role = 'driver' AND u.deleted_at IS NULL
      `;

      const params = [];
      let paramIndex = 1;

      if (filters.status) {
        query += ` AND u.status = $${paramIndex}`;
        params.push(filters.status);
        paramIndex++;
      }

      if (filters.verified !== undefined) {
        query += ` AND dp.is_verified = $${paramIndex}`;
        params.push(filters.verified);
        paramIndex++;
      }

      if (filters.is_online !== undefined) {
        query += ` AND dp.is_online = $${paramIndex}`;
        params.push(filters.is_online);
        paramIndex++;
      }

      query += ` ORDER BY u.created_at DESC LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`;
      params.push(limit, offset);

      const result = await pool.query(query, params);
      return result.rows;
    } catch (error) {
      logger.error('Error listing drivers', { error: error.message });
      throw error;
    }
  }

  /**
   * Met à jour le statut d'un utilisateur (admin)
   * @param {number} userId - ID de l'utilisateur
   * @param {string} status - 'active' | 'inactive' | 'suspended' | 'pending_verification'
   * @returns {Object} Utilisateur mis à jour
   */
  async updateUserStatus(userId, status) {
    const validStatuses = ['active', 'inactive', 'suspended', 'pending_verification'];
    if (!validStatuses.includes(status)) {
      throw new Error('Invalid status');
    }
    try {
      const result = await pool.query(
        `UPDATE users SET status = $1, updated_at = NOW()
         WHERE id = $2 AND deleted_at IS NULL
         RETURNING id, email, phone, first_name, last_name, role, status, created_at, updated_at`,
        [status, userId]
      );
      if (result.rows.length === 0) {
        throw new Error('User not found');
      }
      logger.info('User status updated', { userId, status });
      return result.rows[0];
    } catch (error) {
      logger.error('Error updating user status', { error: error.message, userId });
      throw error;
    }
  }

  /**
   * Met à jour la vérification d'un driver (admin)
   * @param {number} driverId - user_id du driver
   * @param {string} verificationStatus - 'pending' | 'approved' | 'rejected' | 'suspended'
   * @param {string} verificationNotes - Notes optionnelles
   * @returns {Object} Profil driver mis à jour
   */
  async updateDriverVerification(driverId, verificationStatus, verificationNotes = null) {
    const valid = ['pending', 'approved', 'rejected', 'suspended'];
    if (!valid.includes(verificationStatus)) {
      throw new Error('Invalid verification_status');
    }
    try {
      const isVerified = verificationStatus === 'approved';
      const result = await pool.query(
        `UPDATE driver_profiles
         SET verification_status = $1, verification_notes = $2, is_verified = $3, verified_at = NOW()
         WHERE user_id = $4
         RETURNING *`,
        [verificationStatus, verificationNotes, isVerified, driverId]
      );
      if (result.rows.length === 0) {
        throw new Error('Driver profile not found');
      }
      logger.info('Driver verification updated', { driverId, verificationStatus });
      return result.rows[0];
    } catch (error) {
      logger.error('Error updating driver verification', { error: error.message, driverId });
      throw error;
    }
  }

  /**
   * Liste les utilisateurs avec filtres (admin)
   * @param {Object} filters - { role, status, limit, offset }
   * @returns {Object} { users, total }
   */
  async listUsers(filters = {}, limit = 50, offset = 0) {
    try {
      let where = ' WHERE deleted_at IS NULL ';
      const params = [];
      let paramIndex = 1;

      if (filters.role) {
        where += ` AND role = $${paramIndex}`;
        params.push(filters.role);
        paramIndex++;
      }
      if (filters.status) {
        where += ` AND status = $${paramIndex}`;
        params.push(filters.status);
        paramIndex++;
      }

      const countResult = await pool.query(
        `SELECT COUNT(*) as total FROM users ${where}`,
        params
      );
      const total = parseInt(countResult.rows[0].total, 10);

      const result = await pool.query(
        `SELECT id, email, phone, first_name, last_name, role, status, created_at, updated_at
         FROM users ${where}
         ORDER BY created_at DESC
         LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`,
        [...params, limit, offset]
      );

      return { users: result.rows, total };
    } catch (error) {
      logger.error('Error listing users', { error: error.message });
      throw error;
    }
  }
}

module.exports = new UsersService();

