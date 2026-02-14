const jwt = require('jsonwebtoken');
const pool = require('../config/database');

/**
 * Middleware to verify JWT token
 */
const authenticate = async (req, res, next) => {
  try {
    const token = req.headers.authorization?.split(' ')[1];

    if (!token) {
      return res.status(401).json({
        success: false,
        message: 'Authentication token required'
      });
    }

    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    
    // Verify user still exists and is active
    const userResult = await pool.query(
      'SELECT id, email, role, status FROM users WHERE id = $1',
      [decoded.userId]
    );

    if (userResult.rows.length === 0) {
      return res.status(401).json({
        success: false,
        message: 'User not found'
      });
    }

    if (userResult.rows[0].status !== 'active') {
      return res.status(401).json({
        success: false,
        message: 'User account is not active'
      });
    }

    // Utiliser le rôle de la DB plutôt que celui du token (plus sûr)
    const dbUser = userResult.rows[0];
    // Normaliser le rôle (trim + lowercase pour éviter les problèmes de casse/espaces)
    const normalizedRole = (dbUser.role || '').trim().toLowerCase();
    req.user = {
      userId: decoded.userId,
      id: decoded.userId, // Alias pour compatibilité
      email: decoded.email,
      role: normalizedRole // Utiliser le rôle de la DB normalisé
    };

    next();
  } catch (error) {
    return res.status(401).json({
      success: false,
      message: 'Invalid or expired token'
    });
  }
};

/**
 * Middleware to check user role
 */
const authorize = (...roles) => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({
        success: false,
        message: 'Authentication required'
      });
    }

    // Normaliser les rôles requis et le rôle de l'utilisateur pour comparaison
    const normalizedUserRole = String(req.user.role || '').trim().toLowerCase();
    
    // Flatten le tableau de rôles (authorize(['driver']) donne roles = [['driver']])
    let rolesArray = roles;
    if (roles.length === 1 && Array.isArray(roles[0])) {
      rolesArray = roles[0];
    }
    // Convertir tous les rôles en strings et normaliser
    const normalizedRequiredRoles = rolesArray
      .filter(r => r != null) // Filtrer les valeurs null/undefined
      .map(r => String(r).trim().toLowerCase());

    if (!normalizedRequiredRoles.includes(normalizedUserRole)) {
      return res.status(403).json({
        success: false,
        message: 'Insufficient permissions',
        debug: {
          userRole: req.user.role,
          normalizedUserRole: normalizedUserRole,
          requiredRoles: roles,
          normalizedRequiredRoles: normalizedRequiredRoles
        }
      });
    }

    next();
  };
};

module.exports = {
  authenticate,
  authorize
};

