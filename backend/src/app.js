const express = require('express');
const http = require('http');
const fs = require('fs');
const { Server } = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');
// En production : charger .env s'il existe (valeurs remplies), sinon .env.production
const envFile = process.env.NODE_ENV === 'production'
  ? (fs.existsSync('.env') ? '.env' : '.env.production')
  : (process.env.NODE_ENV === 'test' ? '.env.test' : '.env');
require('dotenv').config({ path: envFile });

const app = express();
const server = http.createServer(app);

// Socket.IO setup
const io = new Server(server, {
  cors: {
    origin: process.env.CORS_ORIGIN || '*',
    methods: ['GET', 'POST']
  }
});

// Initialize WebSocket service for rides
const WebSocketService = require('./modules/rides/websocket.service');
const wsService = new WebSocketService(io);

// Middlewares
app.use(helmet());
// Configuration CORS
const corsOptions = {
  origin: function (origin, callback) {
    // En production, accepter toutes les origines
    if (process.env.NODE_ENV === 'production') {
      return callback(null, true);
    }
    
    // En développement, vérifier les origines autorisées
    const allowedOrigins = [
      'http://localhost',
      'http://localhost:3000',
      'http://127.0.0.1',
      'http://127.0.0.1:3000',
      'http://10.0.2.2',
      'http://10.0.2.2:3000',
      'http://192.168.1.44',
      'http://192.168.1.44:3000',
      'http://192.168.1.47',
      'http://192.168.1.47:3000',
      'http://104.237.132.106',
      'http://104.237.132.106:3000',
      'https://104.237.132.106',
      'https://104.237.132.106:3000'
    ];
    
    // Autoriser les requêtes sans origine (comme les applications mobiles, Postman, etc.)
    if (!origin || allowedOrigins.some(allowedOrigin => origin.startsWith(allowedOrigin))) {
      return callback(null, true);
    }
    
    callback(new Error(`Origine non autorisée par CORS: ${origin}`));
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key', 'X-Requested-With'],
  credentials: true,
  optionsSuccessStatus: 200 // Pour les navigateurs qui ont des problèmes avec 204
};

// Appliquer la configuration CORS
app.use(cors(corsOptions));

// Gérer les requêtes OPTIONS (pré-vol CORS)
app.options('*', cors(corsOptions));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', message: 'BikeRide Pro API is running' });
});

// API Routes
const API_VERSION = process.env.API_VERSION || 'v1';
app.use(`/api/${API_VERSION}/auth`, require('./modules/auth/routes'));
app.use(`/api/${API_VERSION}/rides`, require('./modules/rides/routes'));
app.use(`/api/${API_VERSION}/deliveries`, require('./modules/deliveries/routes'));
app.use(`/api/${API_VERSION}/carpool`, require('./modules/carpool/routes'));
app.use(`/api/${API_VERSION}/wallet`, require('./modules/wallet/routes'));
app.use(`/api/${API_VERSION}/users`, require('./modules/users/routes'));
app.use(`/api/${API_VERSION}/admin`, require('./modules/admin/routes'));
app.use(`/api/${API_VERSION}/notifications`, require('./modules/notifications/routes'));
app.use(`/api/${API_VERSION}/audit`, require('./modules/audit/routes'));
app.use(`/api/${API_VERSION}/maps`, require('./modules/maps/routes'));
app.use(`/api/${API_VERSION}/payment`, require('./modules/payment/routes'));

// Gestionnaire d'erreurs global
app.use((err, req, res, next) => {
  console.error('Erreur:', err.message);
  
  // Messages d'erreur personnalisés
  const errorMessages = {
    'Cannot cancel ride in status': 'Impossible d\'annuler une course en cours. Veuillez d\'abord terminer la course actuelle.',
    'Ride not found': 'Course introuvable',
    'Invalid ride status': 'Statut de course invalide',
    'Missing required fields': 'Champs obligatoires manquants'
  };

  // Vérifie si le message d'erreur correspond à un message personnalisé
  let userFriendlyMessage = err.message;
  for (const [key, value] of Object.entries(errorMessages)) {
    if (err.message.includes(key)) {
      userFriendlyMessage = value;
      break;
    }
  }

  // Si en production, ne pas renvoyer la pile d'appels
  const errorResponse = {
    success: false,
    message: userFriendlyMessage || 'Une erreur est survenue. Veuillez réessayer plus tard.'
  };

  // En développement, ajouter plus de détails
  if (process.env.NODE_ENV !== 'production') {
    errorResponse.error = err.message;
    errorResponse.stack = err.stack;
  }

  res.status(err.status || 500).json(errorResponse);
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    success: false,
    message: 'Route not found'
  });
});

// Démarrer le processeur de timeouts (cron job) - seulement si pas en mode test
if (process.env.NODE_ENV !== 'test') {
  const { startTimeoutProcessor } = require('./cron/timeoutProcessor');
  startTimeoutProcessor();
}

const PORT = process.env.PORT || 3000;
// Écouter sur 0.0.0.0 pour accepter les connexions depuis le réseau (appareil réel, autre PC)
const HOST = process.env.HOST || '0.0.0.0';

// Ne pas démarrer le serveur en mode test (Jest gère ça)
if (process.env.NODE_ENV !== 'test') {
  server.listen(PORT, HOST, () => {
    console.log(`🚀 BikeRide Pro API server running on http://${HOST}:${PORT}`);
    console.log(`   Depuis ce PC: http://localhost:${PORT}`);
    console.log(`   Depuis le réseau: http://<VOTRE_IP>:${PORT}`);
    console.log(`📋 Environment: ${process.env.NODE_ENV || 'development'}`);
    console.log(`🔌 WebSocket server ready`);
    console.log(`⏰ Timeout processor started`);
  });
}

// Export both app and io for use in other modules
app.io = io;
module.exports = { app, server, io };

