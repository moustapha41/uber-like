#!/usr/bin/env node

/**
 * Script pour exécuter tous les scénarios de test
 * Usage: node tests/run-all-scenarios.js
 */

const { execSync } = require('child_process');
const path = require('path');

const scenarios = [
  'scenario1-happy-path.test.js',
  'scenario2-cancellation.test.js',
  'scenario3-timeouts.test.js',
  'scenario4-race-condition.test.js',
  'scenario5-websocket.test.js',
  'scenario6-rate-limiting.test.js',
  'scenario7-idempotency.test.js',
  'scenario8-price-calculation.test.js',
  'scenario9-driver-release.test.js'
];

console.log('🧪 Exécution de tous les scénarios de test\n');
console.log('='.repeat(60));

let passed = 0;
let failed = 0;

scenarios.forEach((scenario, index) => {
  console.log(`\n📋 Scénario ${index + 1}/9: ${scenario}`);
  console.log('-'.repeat(60));
  
  try {
    execSync(
      `NODE_ENV=test jest ${path.join(__dirname, 'scenarios', scenario)} --verbose`,
      { stdio: 'inherit', cwd: path.join(__dirname, '..') }
    );
    console.log(`✅ ${scenario} - PASSÉ`);
    passed++;
  } catch (error) {
    console.log(`❌ ${scenario} - ÉCHOUÉ`);
    failed++;
  }
});

console.log('\n' + '='.repeat(60));
console.log('📊 RÉSUMÉ');
console.log('='.repeat(60));
console.log(`✅ Passés: ${passed}/${scenarios.length}`);
console.log(`❌ Échoués: ${failed}/${scenarios.length}`);

if (failed === 0) {
  console.log('\n🎉 Tous les scénarios sont passés !');
  process.exit(0);
} else {
  console.log(`\n⚠️ ${failed} scénario(s) ont échoué`);
  process.exit(1);
}

