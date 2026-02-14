/**
 * Tests simplifiés sans base de données
 * Valide la logique métier et la structure des tests
 */

const ridesService = require('../src/modules/rides/rides.service');
const pricingService = require('../src/modules/rides/pricing.service');
const matchingService = require('../src/modules/rides/matching.service');

console.log('🧪 Tests de validation (sans base de données)');
console.log('='.repeat(60));
console.log('');

let testsPassed = 0;
let testsFailed = 0;

function test(name, fn) {
  try {
    const result = fn();
    if (result instanceof Promise) {
      result
        .then(() => {
          console.log(`✅ ${name}`);
          testsPassed++;
        })
        .catch(error => {
          console.log(`❌ ${name}`);
          console.log(`   Erreur: ${error.message}`);
          testsFailed++;
        });
    } else {
      console.log(`✅ ${name}`);
      testsPassed++;
    }
  } catch (error) {
    console.log(`❌ ${name}`);
    console.log(`   Erreur: ${error.message}`);
    testsFailed++;
  }
}

// Test 1 : Service Pricing
console.log('📊 Test 1 : Service de Pricing');
test('calculateFare - Calcul de base', () => {
  const config = {
    base_fare: 500,
    cost_per_km: 300,
    cost_per_minute: 50,
    time_slots: []
  };
  
  const fare = pricingService.calculateFare(5, 10, config);
  // 500 + (5 * 300) + (10 * 50) = 500 + 1500 + 500 = 2500
  if (fare !== 2500) {
    throw new Error(`Prix attendu: 2500, obtenu: ${fare}`);
  }
});

test('calculateFinalFare - Règle min(estime × 1.10, réel)', () => {
  const estimatedFare = 2000;
  const actualFare = 2500; // Plus cher que 2200 (2000 * 1.10)
  
  const finalFare = pricingService.calculateFinalFare(estimatedFare, actualFare, 10);
  const maxAllowed = Math.round(estimatedFare * 1.10);
  
  if (finalFare !== maxAllowed) {
    throw new Error(`Prix final devrait être plafonné à ${maxAllowed}, obtenu: ${finalFare}`);
  }
});

test('calculateFinalFare - Prix réel dans tolérance', () => {
  const estimatedFare = 2000;
  const actualFare = 2100; // Dans la tolérance
  
  const finalFare = pricingService.calculateFinalFare(estimatedFare, actualFare, 10);
  
  if (finalFare !== 2100) {
    throw new Error(`Prix final devrait être ${actualFare}, obtenu: ${finalFare}`);
  }
});

// Test 2 : Multiplicateurs horaires
console.log('');
console.log('⏰ Test 2 : Multiplicateurs horaires');
test('getCurrentTimeMultiplier - Plage normale', () => {
  const timeSlots = [
    { start_time: '06:00', end_time: '22:00', multiplier: 1.0 },
    { start_time: '22:00', end_time: '06:00', multiplier: 1.3 }
  ];
  
  const multiplier = pricingService.getCurrentTimeMultiplier(timeSlots);
  // Devrait retourner 1.0 ou 1.3 selon l'heure actuelle
  if (multiplier !== 1.0 && multiplier !== 1.3) {
    throw new Error(`Multiplicateur invalide: ${multiplier}`);
  }
});

// Test 3 : Structure des services
console.log('');
console.log('🏗️ Test 3 : Structure des services');
test('ridesService existe et a les méthodes nécessaires', () => {
  const requiredMethods = [
    'estimateRide',
    'createRide',
    'acceptRide',
    'markDriverArrived',
    'startRide',
    'completeRide',
    'cancelRide',
    'rateRide'
  ];
  
  for (const method of requiredMethods) {
    if (typeof ridesService[method] !== 'function') {
      throw new Error(`Méthode ${method} manquante dans ridesService`);
    }
  }
});

test('pricingService existe et a les méthodes nécessaires', () => {
  const requiredMethods = [
    'getActivePricingConfig',
    'getCurrentTimeMultiplier',
    'calculateFare',
    'calculateFinalFare',
    'calculateCommission'
  ];
  
  for (const method of requiredMethods) {
    if (typeof pricingService[method] !== 'function') {
      throw new Error(`Méthode ${method} manquante dans pricingService`);
    }
  }
});

test('matchingService existe et a les méthodes nécessaires', () => {
  const requiredMethods = [
    'findNearbyDrivers',
    'progressiveMatching',
    'notifyDrivers'
  ];
  
  for (const method of requiredMethods) {
    if (typeof matchingService[method] !== 'function') {
      throw new Error(`Méthode ${method} manquante dans matchingService`);
    }
  }
});

// Résumé
setTimeout(() => {
  console.log('');
  console.log('='.repeat(60));
  console.log('📊 RÉSUMÉ');
  console.log('='.repeat(60));
  console.log(`✅ Tests passés: ${testsPassed}`);
  console.log(`❌ Tests échoués: ${testsFailed}`);
  console.log(`📈 Total: ${testsPassed + testsFailed}`);
  console.log('');
  
  if (testsFailed === 0) {
    console.log('🎉 Tous les tests de validation sont passés !');
    console.log('');
    console.log('💡 Pour exécuter les tests complets avec base de données :');
    console.log('   1. Configurer PostgreSQL (voir tests/QUICK_SETUP.md)');
    console.log('   2. Exécuter : npm test');
    process.exit(0);
  } else {
    console.log(`⚠️ ${testsFailed} test(s) ont échoué`);
    process.exit(1);
  }
}, 2000);

