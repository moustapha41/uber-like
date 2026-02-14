const cron = require('node-cron');
const timeoutService = require('../modules/rides/timeout.service');
const logger = require('../utils/logger');

/**
 * Job Cron pour traiter les timeouts expirés
 * S'exécute toutes les 30 secondes
 */
const timeoutProcessorJob = cron.schedule('*/30 * * * * *', async () => {
  try {
    const processed = await timeoutService.processExpiredTimeouts();
    if (processed > 0) {
      logger.info(`Processed ${processed} expired timeouts`);
    }
  } catch (error) {
    logger.error('Error in timeout processor cron job', error);
  }
}, {
  scheduled: false // Ne pas démarrer automatiquement
});

/**
 * Démarre le job cron
 */
const startTimeoutProcessor = () => {
  timeoutProcessorJob.start();
  logger.info('Timeout processor cron job started');
};

/**
 * Arrête le job cron
 */
const stopTimeoutProcessor = () => {
  timeoutProcessorJob.stop();
  logger.info('Timeout processor cron job stopped');
};

module.exports = {
  startTimeoutProcessor,
  stopTimeoutProcessor
};

