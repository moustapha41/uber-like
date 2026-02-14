const rateLimit = require('express-rate-limit');

/**
 * Rate Limiting pour endpoints critiques
 */

// Limite pour création de courses (10 requêtes / 15 min)
const rideCreationLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10, // 10 requêtes max
  message: {
    success: false,
    message: 'Trop de demandes de course, veuillez réessayer plus tard'
  },
  standardHeaders: true,
  legacyHeaders: false,
});

// Limite pour updates GPS (60 requêtes / minute)
const driverLocationLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 60, // 60 updates max (1 par seconde)
  message: {
    success: false,
    message: 'Trop de mises à jour de position, veuillez ralentir'
  },
  keyGenerator: (req) => req.user?.id || req.ip, // Limite par utilisateur
  standardHeaders: true,
  legacyHeaders: false,
});

// Limite pour acceptation de courses (20 requêtes / 5 min)
const rideAcceptLimiter = rateLimit({
  windowMs: 5 * 60 * 1000, // 5 minutes
  max: 20, // 20 acceptations max
  message: {
    success: false,
    message: 'Trop de tentatives d\'acceptation, veuillez réessayer plus tard'
  },
  keyGenerator: (req) => req.user?.id || req.ip,
  standardHeaders: true,
  legacyHeaders: false,
});

// Limite générale pour API (100 requêtes / 15 min)
const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: {
    success: false,
    message: 'Trop de requêtes, veuillez réessayer plus tard'
  },
  standardHeaders: true,
  legacyHeaders: false,
});

module.exports = {
  rideCreationLimiter,
  driverLocationLimiter,
  rideAcceptLimiter,
  apiLimiter
};

