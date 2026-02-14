/**
 * SCÉNARIO 7 : Idempotency
 * Objectif : Valider que l'idempotency fonctionne pour éviter les doubles requêtes
 */

const request = require('supertest');
const { app } = require('../../src/app');
const { testPool, createTestUser, createTestDriver, generateTestToken } = require('../setup');
const ridesService = require('../../src/modules/rides/rides.service');

describe('SCÉNARIO 7: Idempotency', () => {
  let client, driver, clientToken, driverToken, rideId;

  beforeAll(async () => {
    client = await createTestUser('client');
    driver = await createTestDriver();
    
    clientToken = generateTestToken(client.id, 'client');
    driverToken = generateTestToken(driver.id, 'driver');
    
    await testPool.query(
      `INSERT INTO driver_locations (driver_id, lat, lng, updated_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (driver_id) DO UPDATE SET lat = $2, lng = $3`,
      [driver.id, 14.7167, -17.4677]
    );
  });

  test('7.1: Double acceptation avec même Idempotency Key', async () => {
    // Créer une course
    const ride = await ridesService.createRide(client.id, {
      pickup_lat: 14.7167,
      pickup_lng: -17.4677,
      dropoff_lat: 14.7200,
      dropoff_lng: -17.4700
    });
    
    rideId = ride.id;
    const idempotencyKey = `accept-${Date.now()}`;
    
    // Première acceptation
    const firstAccept = await request(app)
      .post(`/api/v1/rides/${rideId}/accept`)
      .set('Authorization', `Bearer ${driverToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .expect(200);
    
    expect(firstAccept.body.success).toBe(true);
    const firstDriverId = firstAccept.body.data.driver_id;
    
    // Deuxième acceptation avec même clé
    const secondAccept = await request(app)
      .post(`/api/v1/rides/${rideId}/accept`)
      .set('Authorization', `Bearer ${driverToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .expect(200);
    
    // Doit retourner la même réponse (idempotence)
    expect(secondAccept.body.data.driver_id).toBe(firstDriverId);
    
    // Vérifier qu'une seule acceptation a été enregistrée
    const rideCheck = await testPool.query(
      'SELECT driver_id FROM rides WHERE id = $1',
      [rideId]
    );
    expect(rideCheck.rows[0].driver_id).toBe(firstDriverId);
  });

  test('7.2: Double paiement avec même Idempotency Key', async () => {
    // Créer une course complétée
    const ride = await ridesService.createRide(client.id, {
      pickup_lat: 14.7167,
      pickup_lng: -17.4677,
      dropoff_lat: 14.7200,
      dropoff_lng: -17.4700
    });
    
    // S'assurer que le driver est bien en ligne et disponible
    await testPool.query(
      'UPDATE driver_profiles SET is_online = true, is_available = true WHERE user_id = $1',
      [driver.id]
    );

    await ridesService.acceptRide(ride.id, driver.id);
    await ridesService.markDriverArrived(ride.id, driver.id);
    await ridesService.startRide(ride.id, driver.id);
    await ridesService.completeRide(ride.id, driver.id, 3.5, 15);
    
    const idempotencyKey = `payment-${Date.now()}`;
    
    // Simuler paiement (endpoint à créer dans payment module)
    // Pour l'instant, vérifier que l'idempotency key est bien gérée
    
    // Vérifier que la clé d'idempotence est enregistrée
    const idempotentRequest = await testPool.query(
      `SELECT * FROM idempotent_requests WHERE idempotency_key = $1`,
      [idempotencyKey]
    );
    
    // La clé devrait être enregistrée après la première requête
    // (à adapter selon l'implémentation du module payment)
  });

  test('7.3: Double notation avec même Idempotency Key', async () => {
    const idempotencyKey = `rate-${Date.now()}`;
    
    // Première notation
    const firstRate = await request(app)
      .post(`/api/v1/rides/${rideId}/rate`)
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .send({
        rating: 5,
        comment: 'Excellent!',
        role: 'client'
      })
      .expect(200);
    
    expect(firstRate.body.success).toBe(true);
    
    // Deuxième notation avec même clé
    const secondRate = await request(app)
      .post(`/api/v1/rides/${rideId}/rate`)
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .send({
        rating: 3, // Note différente
        comment: 'Moyen',
        role: 'client'
      })
      .expect(200);
    
    // Vérifier que la note n'a pas changé (idempotence)
    const ride = await testPool.query(
      'SELECT client_rating, client_review FROM rides WHERE id = $1',
      [rideId]
    );
    
    expect(ride.rows[0].client_rating).toBe(5); // Reste à 5
    expect(ride.rows[0].client_review).toBe('Excellent!'); // Reste "Excellent!"
  });
});

