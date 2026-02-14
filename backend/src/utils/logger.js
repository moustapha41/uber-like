const winston = require('winston');
const path = require('path');

/**
 * Logger structuré pour l'application
 */
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  defaultMeta: { service: 'bikeride-pro-backend' },
  transports: [
    // Erreurs dans un fichier séparé
    new winston.transports.File({ 
      filename: path.join(__dirname, '../../logs/error.log'), 
      level: 'error',
      maxsize: 5242880, // 5MB
      maxFiles: 5
    }),
    // Tous les logs dans un fichier combiné
    new winston.transports.File({ 
      filename: path.join(__dirname, '../../logs/combined.log'),
      maxsize: 5242880, // 5MB
      maxFiles: 5
    }),
  ],
});

// En développement, aussi logger dans la console
if (process.env.NODE_ENV !== 'production') {
  logger.add(new winston.transports.Console({
    format: winston.format.combine(
      winston.format.colorize(),
      winston.format.simple()
    )
  }));
}

/**
 * Helper pour logger les actions de course
 */
logger.rideAction = (action, data) => {
  logger.info('Ride action', {
    action,
    rideId: data.rideId,
    userId: data.userId,
    status: data.status,
    ...data
  });
};

/**
 * Helper pour logger les erreurs de course
 */
logger.rideError = (action, error, data) => {
  logger.error('Ride error', {
    action,
    error: error.message,
    stack: error.stack,
    rideId: data.rideId,
    userId: data.userId,
    ...data
  });
};

module.exports = logger;

