const express = require('express');
const router = express.Router();
const { body, validationResult } = require('express-validator');
const authService = require('./auth.service');
const { authenticate } = require('../../middleware/auth');
const { successResponse, errorResponse } = require('../../utils/response');
const { apiLimiter } = require('../../middleware/rateLimit');

/**
 * Routes d'authentification
 */

/**
 * POST /api/v1/auth/register
 * Enregistre un nouvel utilisateur
 */
router.post('/register',
  apiLimiter,
  [
    body('email').isEmail().normalizeEmail(),
    body('password').isLength({ min: 6 }).withMessage('Password must be at least 6 characters'),
    body('phone').optional().matches(/^\+?[1-9]\d{1,14}$/).withMessage('Invalid phone format (use international format: +221770000001)'),
    body('first_name').optional().isLength({ min: 1, max: 100 }),
    body('last_name').optional().isLength({ min: 1, max: 100 }),
    body('role').optional().isIn(['client', 'driver']).withMessage('Role must be client or driver'),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return res.status(400).json({
          success: false,
          message: 'Validation failed',
          errors: errors.array()
        });
      }

      const { email, password, phone, first_name, last_name, role } = req.body;

      const result = await authService.register({
        email,
        password,
        phone,
        first_name,
        last_name,
        role: role || 'client'
      });

      return successResponse(res, result, 'User registered successfully', 201);
    } catch (error) {
      if (error.message === 'Email or phone already exists') {
        return errorResponse(res, error.message, 409);
      }
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/auth/login
 * Connecte un utilisateur
 */
router.post('/login',
  apiLimiter,
  [
    body('email').isEmail().normalizeEmail(),
    body('password').notEmpty().withMessage('Password is required'),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return errorResponse(res, 'Validation failed', 400, errors.array());
      }

      const { email, password } = req.body;

      const result = await authService.login(email, password);

      return successResponse(res, result, 'Login successful', 200);
    } catch (error) {
      if (error.message === 'Invalid credentials') {
        return errorResponse(res, 'Invalid email or password', 401);
      }
      if (error.message.includes('Account is')) {
        return errorResponse(res, error.message, 403);
      }
      return errorResponse(res, error.message, 400);
    }
  }
);

/**
 * POST /api/v1/auth/refresh
 * Rafraîchit un token
 */
router.post('/refresh',
  [
    body('refreshToken').notEmpty().withMessage('Refresh token is required'),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return errorResponse(res, 'Validation failed', 400, errors.array());
      }

      const { refreshToken } = req.body;

      const result = await authService.refreshToken(refreshToken);

      return successResponse(res, result, 'Token refreshed successfully', 200);
    } catch (error) {
      return errorResponse(res, 'Invalid refresh token', 401);
    }
  }
);

/**
 * POST /api/v1/auth/logout
 * Déconnecte un utilisateur
 */
router.post('/logout',
  authenticate,
  async (req, res) => {
    try {
      await authService.logout(req.user.id);

      return successResponse(res, null, 'Logout successful', 200);
    } catch (error) {
      return errorResponse(res, error.message, 500);
    }
  }
);

/**
 * GET /api/v1/auth/me
 * Récupère les informations de l'utilisateur connecté
 */
router.get('/me',
  authenticate,
  async (req, res) => {
    try {
      const usersService = require('../users/users.service');
      const user = await usersService.getUserById(req.user.id);
      
      // Si c'est un driver, inclure le profil driver
      let driverProfile = null;
      if (user.role === 'driver') {
        try {
          driverProfile = await usersService.getDriverProfile(user.id);
        } catch (error) {
          // Profil driver n'existe pas encore
        }
      }

      return successResponse(res, {
        user,
        driver_profile: driverProfile
      });
    } catch (error) {
      return errorResponse(res, error.message, 404);
    }
  }
);

/**
 * POST /api/v1/auth/verify-email
 * Vérifie l'email d'un utilisateur (avec token)
 */
router.post('/verify-email',
  [
    body('token').notEmpty().withMessage('Verification token is required'),
  ],
  async (req, res) => {
    try {
      const errors = validationResult(req);
      if (!errors.isEmpty()) {
        return errorResponse(res, 'Validation failed', 400, errors.array());
      }

      // TODO: Implémenter la vérification d'email
      return errorResponse(res, 'Email verification not implemented yet', 501);
    } catch (error) {
      return errorResponse(res, error.message, 500);
    }
  }
);

module.exports = router;
