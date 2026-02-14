/**
 * Configuration globale pour les tests
 */
const { Pool } = require('pg');
require('dotenv').config({ path: '.env.test' });

// Configuration de la base de données de test
const testPool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT) || 5432,
  database: process.env.DB_NAME_TEST || 'bikeride_pro_test',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || '',
});

// Nettoyer la base avant chaque suite de tests
beforeAll(async () => {
  // Créer les tables si elles n'existent pas
  // (à adapter selon votre structure)
});

afterAll(async () => {
  await testPool.end();
});

// Helper pour créer un utilisateur de test
async function createTestUser(role = 'client') {
  const bcrypt = require('bcryptjs');
  const passwordHash = await bcrypt.hash('testpassword123', 10);
  const timestamp = Date.now();
  const result = await testPool.query(
    `INSERT INTO users (email, phone, password_hash, role, status, first_name, last_name)
     VALUES ($1, $2, $3, $4, 'active', $5, $6)
     RETURNING *`,
    [`test-${role}-${timestamp}@test.com`, `+22177${timestamp.toString().slice(-6)}`, passwordHash, role, 'Test', 'User']
  );
  return result.rows[0];
}

// Helper pour créer un driver de test
async function createTestDriver() {
  const user = await createTestUser('driver');
  const result = await testPool.query(
    `INSERT INTO driver_profiles (user_id, is_online, is_available, license_number, verification_status)
     VALUES ($1, true, true, $2, 'pending')
     RETURNING *`,
    [user.id, `LIC-${Date.now()}`]
  );
  return { ...user, driverProfile: result.rows[0] };
}

// Helper pour générer un token JWT de test
function generateTestToken(userId, role) {
  const jwt = require('jsonwebtoken');
  return jwt.sign(
    { userId, email: 'test@test.com', role },
    process.env.JWT_SECRET || 'test-secret',
    { expiresIn: '1h' }
  );
}

module.exports = {
  testPool,
  createTestUser,
  createTestDriver,
  generateTestToken
};

