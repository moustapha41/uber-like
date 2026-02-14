const jwt = require('jsonwebtoken');
const usersService = require('../users/users.service');
const logger = require('../../utils/logger');

/**
 * Auth Service
 * Gère l'authentification (register, login, tokens)
 */

class AuthService {
  /**
   * Génère un token JWT pour un utilisateur
   * @param {Object} user - Utilisateur
   * @returns {string} Token JWT
   */
  generateToken(user) {
    const payload = {
      userId: user.id,
      email: user.email,
      role: user.role
    };

    const secret = process.env.JWT_SECRET || 'your-secret-key';
    const expiresIn = process.env.JWT_EXPIRES_IN || '7d';

    return jwt.sign(payload, secret, { expiresIn });
  }

  /**
   * Génère un refresh token
   * @param {Object} user - Utilisateur
   * @returns {string} Refresh token
   */
  generateRefreshToken(user) {
    const payload = {
      userId: user.id,
      type: 'refresh'
    };

    const secret = process.env.JWT_REFRESH_SECRET || process.env.JWT_SECRET || 'your-refresh-secret';
    const expiresIn = process.env.JWT_REFRESH_EXPIRES_IN || '30d';

    return jwt.sign(payload, secret, { expiresIn });
  }

  /**
   * Vérifie un refresh token
   * @param {string} refreshToken - Refresh token
   * @returns {Object} Payload décodé
   */
  verifyRefreshToken(refreshToken) {
    try {
      const secret = process.env.JWT_REFRESH_SECRET || process.env.JWT_SECRET || 'your-refresh-secret';
      return jwt.verify(refreshToken, secret);
    } catch (error) {
      throw new Error('Invalid refresh token');
    }
  }

  /**
   * Enregistre un nouvel utilisateur
   * @param {Object} userData - Données de l'utilisateur
   * @returns {Object} { user, token, refreshToken }
   */
  async register(userData) {
    try {
      const {
        email,
        phone,
        password,
        first_name,
        last_name,
        role = 'client'
      } = userData;

      // Validation basique
      if (!email || !password) {
        throw new Error('Email and password are required');
      }

      if (password.length < 6) {
        throw new Error('Password must be at least 6 characters');
      }

      // Créer l'utilisateur
      const user = await usersService.createUser({
        email,
        phone,
        password,
        first_name,
        last_name,
        role,
        status: 'active' // Ou 'pending_verification' selon votre logique
      });

      // Générer les tokens
      const token = this.generateToken(user);
      const refreshToken = this.generateRefreshToken(user);

      logger.info('User registered', { userId: user.id, email, role });

      return {
        user: {
          id: user.id,
          email: user.email,
          phone: user.phone,
          first_name: user.first_name,
          last_name: user.last_name,
          role: user.role,
          status: user.status
        },
        token,
        refreshToken
      };
    } catch (error) {
      logger.error('Registration failed', { error: error.message, email: userData.email });
      throw error;
    }
  }

  /**
   * Connecte un utilisateur
   * @param {string} email - Email
   * @param {string} password - Mot de passe
   * @returns {Object} { user, token, refreshToken }
   */
  async login(email, password) {
    try {
      if (!email || !password) {
        throw new Error('Email and password are required');
      }

      // Vérifier les credentials
      const user = await usersService.verifyCredentials(email, password);

      // Vérifier que le compte est actif
      if (user.status !== 'active') {
        throw new Error(`Account is ${user.status}. Please contact support.`);
      }

      // Générer les tokens
      const token = this.generateToken(user);
      const refreshToken = this.generateRefreshToken(user);

      logger.info('User logged in', { userId: user.id, email, role: user.role });

      return {
        user: {
          id: user.id,
          email: user.email,
          phone: user.phone,
          first_name: user.first_name,
          last_name: user.last_name,
          role: user.role,
          status: user.status,
          email_verified: user.email_verified,
          phone_verified: user.phone_verified
        },
        token,
        refreshToken
      };
    } catch (error) {
      logger.error('Login failed', { error: error.message, email });
      throw error;
    }
  }

  /**
   * Rafraîchit un token
   * @param {string} refreshToken - Refresh token
   * @returns {Object} { token, refreshToken }
   */
  async refreshToken(refreshToken) {
    try {
      // Vérifier le refresh token
      const decoded = this.verifyRefreshToken(refreshToken);

      // Récupérer l'utilisateur
      const user = await usersService.getUserById(decoded.userId);

      // Vérifier que le compte est actif
      if (user.status !== 'active') {
        throw new Error('Account is not active');
      }

      // Générer de nouveaux tokens
      const newToken = this.generateToken(user);
      const newRefreshToken = this.generateRefreshToken(user);

      logger.info('Token refreshed', { userId: user.id });

      return {
        token: newToken,
        refreshToken: newRefreshToken
      };
    } catch (error) {
      logger.error('Token refresh failed', { error: error.message });
      throw new Error('Invalid refresh token');
    }
  }

  /**
   * Déconnecte un utilisateur (invalide le refresh token côté client)
   * Note: Pour une invalidation côté serveur, il faudrait une table blacklist_tokens
   * @param {number} userId - ID de l'utilisateur
   * @returns {boolean} Success
   */
  async logout(userId) {
    try {
      // Pour l'instant, on fait juste un log
      // Pour une vraie invalidation, il faudrait une table blacklist_tokens
      logger.info('User logged out', { userId });
      return true;
    } catch (error) {
      logger.error('Logout failed', { error: error.message, userId });
      throw error;
    }
  }

  /**
   * Vérifie un token JWT
   * @param {string} token - Token JWT
   * @returns {Object} Payload décodé
   */
  verifyToken(token) {
    try {
      const secret = process.env.JWT_SECRET || 'your-secret-key';
      return jwt.verify(token, secret);
    } catch (error) {
      throw new Error('Invalid or expired token');
    }
  }
}

module.exports = new AuthService();

