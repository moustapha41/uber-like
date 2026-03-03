#!/usr/bin/env node
/**
 * Migration du schéma de la base de données (production ou dev).
 * Crée toutes les tables dans le bon ordre.
 * Usage: NODE_ENV=production node src/config/migrate.js
 *    ou: node src/config/migrate.js (utilise .env)
 */
const fs = require('fs');
const path = require('path');

// Charger .env (même logique que app.js)
const envFile = process.env.NODE_ENV === 'production'
  ? (fs.existsSync(path.join(process.cwd(), '.env')) ? '.env' : '.env.production')
  : (process.env.NODE_ENV === 'test' ? '.env.test' : '.env');
require('dotenv').config({ path: path.join(process.cwd(), envFile) });

const pool = require('./database');

const SQL_FILES = [
  'src/modules/users/models.sql',
  'src/modules/rides/models.sql',
  'src/modules/wallet/models.sql',
  'src/modules/payment/models.sql',
  'src/modules/audit/models.sql',
  'src/modules/deliveries/models.sql',
  'src/modules/deliveries/migrations/001_add_production_features.sql',
  'src/modules/rides/setup-pricing.sql',
  'src/modules/deliveries/setup-pricing.sql',
];

async function runMigration() {
  const client = await pool.connect();
  try {
    console.log('🔄 Migration de la base de données...');
    for (const file of SQL_FILES) {
      const filePath = path.join(process.cwd(), file);
      if (!fs.existsSync(filePath)) {
        console.warn(`⚠️  Fichier non trouvé (ignoré): ${file}`);
        continue;
      }
      const sql = fs.readFileSync(filePath, 'utf8');
      console.log(`   → ${file}`);
      await client.query(sql);
    }
    console.log('✅ Migration terminée avec succès.');
  } catch (err) {
    console.error('❌ Erreur migration:', err.message);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

runMigration();
