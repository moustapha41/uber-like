/**
 * Script de vérification des prérequis pour les tests
 */
const { Pool } = require('pg');
require('dotenv').config();

async function checkPrerequisites() {
  console.log('🔍 Vérification des prérequis pour les tests...\n');
  
  const issues = [];
  
  // Vérifier la connexion à la base de données
  try {
    const pool = new Pool({
      host: process.env.DB_HOST || 'localhost',
      port: process.env.DB_PORT || 5432,
      database: process.env.DB_NAME || 'bikeride_pro',
      user: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD,
    });
    
    await pool.query('SELECT NOW()');
    console.log('✅ Connexion à la base de données OK');
    await pool.end();
  } catch (error) {
    issues.push(`❌ Connexion DB échouée: ${error.message}`);
    console.log(`❌ Connexion DB échouée: ${error.message}`);
  }
  
  // Vérifier que les tables existent
  try {
    const pool = new Pool({
      host: process.env.DB_HOST || 'localhost',
      port: process.env.DB_PORT || 5432,
      database: process.env.DB_NAME || 'bikeride_pro',
      user: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD,
    });
    
    const tables = ['users', 'driver_profiles', 'rides', 'pricing_config'];
    for (const table of tables) {
      try {
        await pool.query(`SELECT 1 FROM ${table} LIMIT 1`);
        console.log(`✅ Table ${table} existe`);
      } catch (error) {
        issues.push(`❌ Table ${table} n'existe pas`);
        console.log(`❌ Table ${table} n'existe pas`);
      }
    }
    await pool.end();
  } catch (error) {
    issues.push(`❌ Vérification tables échouée: ${error.message}`);
  }
  
  // Vérifier les variables d'environnement
  if (!process.env.JWT_SECRET) {
    issues.push('⚠️ JWT_SECRET non défini (utilisera "test-secret" par défaut)');
  }
  
  console.log('\n' + '='.repeat(60));
  if (issues.length === 0) {
    console.log('✅ Tous les prérequis sont satisfaits');
    return true;
  } else {
    console.log(`⚠️ ${issues.length} problème(s) détecté(s):`);
    issues.forEach(issue => console.log(`  ${issue}`));
    console.log('\n💡 Pour créer les tables, exécutez:');
    console.log('   psql -U postgres -d bikeride_pro -f backend/src/modules/rides/models.sql');
    return false;
  }
}

if (require.main === module) {
  checkPrerequisites().then(success => {
    process.exit(success ? 0 : 1);
  });
}

module.exports = { checkPrerequisites };

