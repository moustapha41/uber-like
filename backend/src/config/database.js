const { Pool } = require('pg');

// Charger .env.test en mode test, .env.production en prod, sinon .env
if (process.env.NODE_ENV === 'test') {
  require('dotenv').config({ path: '.env.test' });
} else if (process.env.NODE_ENV === 'production') {
  require('dotenv').config({ path: '.env.production' });
} else {
  require('dotenv').config();
}

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT) || 5432,
  database: process.env.NODE_ENV === 'test' 
    ? (process.env.DB_NAME_TEST || 'bikeride_pro_test')
    : (process.env.DB_NAME || 'bikeride_pro'),
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || '',
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

pool.on('error', (err) => {
  console.error('Unexpected error on idle client', err);
  process.exit(-1);
});

// Test connection (seulement si pas en mode test pour éviter les logs)
if (process.env.NODE_ENV !== 'test') {
  pool.query('SELECT NOW()', (err, res) => {
    if (err) {
      console.error('❌ Database connection error:', err.message);
    } else {
      console.log('✅ PostgreSQL connected successfully');
    }
  });
}

module.exports = pool;

