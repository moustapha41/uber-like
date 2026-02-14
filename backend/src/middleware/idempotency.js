const pool = require('../config/database');
const crypto = require('crypto');

/**
 * Middleware d'idempotence
 * Protège contre les doubles requêtes (double accept, double paiement, etc.)
 */
const idempotencyMiddleware = async (req, res, next) => {
  // Vérifier si l'endpoint nécessite l'idempotence
  const idempotentEndpoints = [
    '/accept',
    '/complete',
    '/rate',
    '/cancel',
    '/cancel-driver'
  ];

  const isIdempotentEndpoint = idempotentEndpoints.some(endpoint => 
    req.path.includes(endpoint)
  );

  if (!isIdempotentEndpoint) {
    return next();
  }

  // Récupérer la clé d'idempotence depuis le header
  const idempotencyKey = req.headers['idempotency-key'];

  if (!idempotencyKey) {
    // Générer une clé basée sur user + endpoint + timestamp (fallback)
    const fallbackKey = `${req.user?.id || 'anonymous'}-${req.path}-${Date.now()}`;
    req.idempotencyKey = crypto.createHash('sha256').update(fallbackKey).digest('hex');
    return next();
  }

  // Vérifier si cette requête a déjà été traitée
  const existingRequest = await pool.query(
    `SELECT response_data, expires_at 
     FROM idempotent_requests 
     WHERE idempotency_key = $1`,
    [idempotencyKey]
  );

  if (existingRequest.rows.length > 0) {
    const cached = existingRequest.rows[0];
    
    // Si la clé a expiré, permettre la nouvelle requête
    if (new Date(cached.expires_at) < new Date()) {
      await pool.query(
        'DELETE FROM idempotent_requests WHERE idempotency_key = $1',
        [idempotencyKey]
      );
      req.idempotencyKey = idempotencyKey;
      return next();
    }

    // Retourner la réponse en cache
    return res.status(200).json(cached.response_data);
  }

  // Stocker la clé pour vérification après traitement
  req.idempotencyKey = idempotencyKey;
  next();
};

/**
 * Enregistre la réponse d'une requête idempotente
 */
const saveIdempotentResponse = async (idempotencyKey, userId, endpoint, responseData) => {
  try {
    await pool.query(
      `INSERT INTO idempotent_requests 
       (idempotency_key, user_id, endpoint, response_data, expires_at)
       VALUES ($1, $2, $3, $4, NOW() + INTERVAL '24 hours')
       ON CONFLICT (idempotency_key) DO NOTHING`,
      [idempotencyKey, userId, endpoint, JSON.stringify(responseData)]
    );
  } catch (error) {
    console.error('Error saving idempotent response:', error);
    // Ne pas bloquer la requête si l'enregistrement échoue
  }
};

module.exports = {
  idempotencyMiddleware,
  saveIdempotentResponse
};

