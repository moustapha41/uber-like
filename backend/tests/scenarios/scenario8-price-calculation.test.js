/**
 * SCÉNARIO 8 : Calcul de prix et tolérance
 * Objectif : Valider que la formule de prix et la tolérance fonctionnent correctement
 */

const { testPool, createTestUser, createTestDriver } = require('../setup');
const ridesService = require('../../src/modules/rides/rides.service');
const pricingService = require('../../src/modules/rides/pricing.service');

describe('SCÉNARIO 8: Calcul de prix et tolérance', () => {
  let client, driver;

  beforeAll(async () => {
    client = await createTestUser('client');
    driver = await createTestDriver();
  });

  test('8.1: Estimation de prix initiale', async () => {
    const estimate = await ridesService.estimateRide(
      14.7167, -17.4677, // Pickup
      14.7200, -17.4700  // Dropoff
    );
    
    expect(estimate.fare_estimate).toBeGreaterThan(0);
    expect(estimate.distance_km).toBeGreaterThan(0);
    expect(estimate.duration_min).toBeGreaterThan(0);
    expect(estimate.currency).toBe('XOF');
    expect(estimate.pricing_breakdown).toBeDefined();
  });

  test('8.2: Règle de tolérance - Prix réel < Estimation', async () => {
    const estimatedFare = 2000;
    const actualFare = 1800; // Moins cher que l'estimation
    
    const finalFare = pricingService.calculateFinalFare(
      estimatedFare,
      actualFare,
      10 // 10% tolérance
    );
    
    // Le prix final devrait être le prix réel (moins cher)
    expect(finalFare).toBe(1800);
  });

  test('8.3: Règle de tolérance - Prix réel > Estimation + 10%', async () => {
    const estimatedFare = 2000;
    const actualFare = 2500; // Plus cher que estimation + 10% (2200)
    
    const finalFare = pricingService.calculateFinalFare(
      estimatedFare,
      actualFare,
      10
    );
    
    // Le prix final devrait être plafonné à estimation × 1.10
    const maxAllowed = Math.round(estimatedFare * 1.10);
    expect(finalFare).toBe(maxAllowed);
    expect(finalFare).toBeLessThanOrEqual(2200);
  });

  test('8.4: Règle de tolérance - Prix réel dans la tolérance', async () => {
    const estimatedFare = 2000;
    const actualFare = 2100; // Dans la tolérance (max 2200)
    
    const finalFare = pricingService.calculateFinalFare(
      estimatedFare,
      actualFare,
      10
    );
    
    // Le prix final devrait être le prix réel
    expect(finalFare).toBe(2100);
  });

  test('8.5: Application de la formule complète', async () => {
    // Créer une course complète
    const ride = await ridesService.createRide(client.id, {
      pickup_lat: 14.7167,
      pickup_lng: -17.4677,
      dropoff_lat: 14.7200,
      dropoff_lng: -17.4700
    });
    
    await ridesService.acceptRide(ride.id, driver.id);
    await ridesService.markDriverArrived(ride.id, driver.id);
    await ridesService.startRide(ride.id, driver.id);
    
    // Récupérer l'estimation
    const rideBeforeComplete = await testPool.query(
      'SELECT estimated_fare FROM rides WHERE id = $1',
      [ride.id]
    );
    const estimatedFare = parseFloat(rideBeforeComplete.rows[0].estimated_fare);
    
    // Terminer avec distance/durée différentes
    const completedRide = await ridesService.completeRide(
      ride.id,
      driver.id,
      5.0,  // Distance réelle (peut différer)
      20    // Durée réelle
    );
    
    const finalFare = parseFloat(completedRide.fare_final);
    const maxAllowed = Math.round(estimatedFare * 1.10);
    
    // Vérifier la règle
    expect(finalFare).toBeLessThanOrEqual(maxAllowed);
    expect(finalFare).toBeGreaterThan(0);
    
    // Nettoyer
    await testPool.query('DELETE FROM rides WHERE id = $1', [ride.id]);
  });

  test('8.6: Multiplicateur selon plage horaire', async () => {
    // Créer une configuration avec plage horaire nuit (1.3x)
    await testPool.query(
      `INSERT INTO pricing_config (service_type, base_fare, cost_per_km, cost_per_minute, is_active)
       VALUES ('ride', 500, 300, 50, true)
       RETURNING id`
    );
    
    const config = await testPool.query(
      `SELECT id FROM pricing_config WHERE service_type = 'ride' AND is_active = true ORDER BY created_at DESC LIMIT 1`
    );
    
    await testPool.query(
      `INSERT INTO pricing_time_slots (pricing_config_id, start_time, end_time, multiplier)
       VALUES ($1, '22:00', '06:00', 1.3)`,
      [config.rows[0].id]
    );
    
    // Tester le calcul avec multiplicateur
    const pricingConfig = await pricingService.getActivePricingConfig('ride');
    const multiplier = pricingService.getCurrentTimeMultiplier(pricingConfig.time_slots);
    
    // Si on est dans la plage 22h-06h, multiplier devrait être 1.3
    const now = new Date();
    const currentHour = now.getHours();
    
    if (currentHour >= 22 || currentHour < 6) {
      expect(multiplier).toBe(1.3);
    } else {
      expect(multiplier).toBe(1.0);
    }
  });
});

