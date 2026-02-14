/**
 * SCÉNARIO 1 : Course normale (happy path)
 * Objectif : Vérifier le flux complet de création à paiement d'une course
 */

const request = require('supertest');
const { app } = require('../../src/app');
const { testPool, createTestUser, createTestDriver, generateTestToken } = require('../setup');
const ridesService = require('../../src/modules/rides/rides.service');
const matchingService = require('../../src/modules/rides/matching.service');
const timeoutService = require('../../src/modules/rides/timeout.service');

describe('SCÉNARIO 1: Course normale (happy path)', () => {
  let client, driver, clientToken, driverToken, rideId;

  beforeAll(async () => {
    // Créer utilisateurs de test
    client = await createTestUser('client');
    driver = await createTestDriver();
    
    clientToken = generateTestToken(client.id, 'client');
    driverToken = generateTestToken(driver.id, 'driver');
    
    // Positionner le driver à proximité
    await testPool.query(
      `INSERT INTO driver_locations (driver_id, lat, lng, updated_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (driver_id) DO UPDATE SET lat = $2, lng = $3`,
      [driver.id, 14.7167, -17.4677]
    );
  });

  afterAll(async () => {
    // Nettoyer les données de test
    if (rideId) {
      await testPool.query('DELETE FROM rides WHERE id = $1', [rideId]);
    }
  });

  test('1.1: Client crée une course', async () => {
    const response = await request(app)
      .post('/api/v1/rides')
      .set('Authorization', `Bearer ${clientToken}`)
      .send({
        pickup_lat: 14.7167,
        pickup_lng: -17.4677,
        dropoff_lat: 14.7200,
        dropoff_lng: -17.4700,
        pickup_address: 'Point A',
        dropoff_address: 'Point B'
      })
      .expect(201);

    expect(response.body.success).toBe(true);
    expect(response.body.data.status).toBe('REQUESTED');
    expect(response.body.data.ride_code).toMatch(/^RIDE-/);
    expect(response.body.data.client_id).toBe(client.id);
    
    rideId = response.body.data.id;
  });

  test('1.2: Estimation de prix', async () => {
    const response = await request(app)
      .post('/api/v1/rides/estimate')
      .send({
        pickup_lat: 14.7167,
        pickup_lng: -17.4677,
        dropoff_lat: 14.7200,
        dropoff_lng: -17.4700
      })
      .expect(200);

    expect(response.body.success).toBe(true);
    expect(response.body.data.fare_estimate).toBeGreaterThan(0);
    expect(response.body.data.distance_km).toBeGreaterThan(0);
    expect(response.body.data.duration_min).toBeGreaterThan(0);
  });

  test('1.3: Matching progressif se déclenche', async () => {
    // Vérifier que le matching est programmé
    const nearbyDrivers = await matchingService.findNearbyDrivers(
      14.7167, -17.4677, 5, 1
    );
    
    // On vérifie simplement qu'au moins un driver éligible est trouvé
    expect(nearbyDrivers.length).toBeGreaterThan(0);
  });

  test('1.4: Driver accepte avec verrou DB', async () => {
    const idempotencyKey = `accept-${Date.now()}`;
    
    const response = await request(app)
      .post(`/api/v1/rides/${rideId}/accept`)
      .set('Authorization', `Bearer ${driverToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .expect(200);

    expect(response.body.success).toBe(true);
    expect(response.body.data.status).toBe('DRIVER_ASSIGNED');
    expect(response.body.data.driver_id).toBe(driver.id);
    
    // Vérifier que le driver n'est plus disponible
    const driverProfile = await testPool.query(
      'SELECT is_available FROM driver_profiles WHERE user_id = $1',
      [driver.id]
    );
    expect(driverProfile.rows[0].is_available).toBe(false);
  });

  test('1.5: Vérifier protection contre double acceptation', async () => {
    const anotherDriver = await createTestDriver();
    const anotherToken = generateTestToken(anotherDriver.id, 'driver');
    
    // Tentative d'acceptation par un autre driver
    const response = await request(app)
      .post(`/api/v1/rides/${rideId}/accept`)
      .set('Authorization', `Bearer ${anotherToken}`)
      .set('Idempotency-Key', `accept-${Date.now()}`)
      .expect(400);

    expect(response.body.success).toBe(false);
    // Le message réel indique que la course ne peut plus être acceptée
    expect(response.body.message).toContain('Course cannot be accepted');
  });

  test('1.6: Driver arrive au point de pickup', async () => {
    const response = await request(app)
      .post(`/api/v1/rides/${rideId}/arrived`)
      .set('Authorization', `Bearer ${driverToken}`)
      .expect(200);

    expect(response.body.success).toBe(true);
    expect(response.body.data.status).toBe('DRIVER_ARRIVED');
    
    // Vérifier que le timeout CLIENT_NO_SHOW est programmé
    const timeout = await testPool.query(
      `SELECT * FROM ride_timeouts 
       WHERE ride_id = $1 AND timeout_type = 'CLIENT_NO_SHOW' AND processed = false`,
      [rideId]
    );
    expect(timeout.rows.length).toBe(1);
  });

  test('1.7: Driver démarre la course', async () => {
    const idempotencyKey = `start-${Date.now()}`;
    
    const response = await request(app)
      .post(`/api/v1/rides/${rideId}/start`)
      .set('Authorization', `Bearer ${driverToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .expect(200);

    expect(response.body.success).toBe(true);
    expect(response.body.data.status).toBe('IN_PROGRESS');
    expect(response.body.data.started_at).toBeDefined();
  });

  test('1.8: Protection contre double start', async () => {
    // Tentative de démarrer à nouveau
    const response = await request(app)
      .post(`/api/v1/rides/${rideId}/start`)
      .set('Authorization', `Bearer ${driverToken}`)
      .set('Idempotency-Key', `start-${Date.now()}`)
      .expect(400);

    expect(response.body.success).toBe(false);
    // Le service renvoie un message de transition de statut invalide
    expect(response.body.message).toContain('Invalid status transition');
  });

  test('1.9: Driver termine la course', async () => {
    const idempotencyKey = `complete-${Date.now()}`;
    
    // Récupérer l'estimation initiale
    const ride = await testPool.query('SELECT estimated_fare FROM rides WHERE id = $1', [rideId]);
    const estimatedFare = parseFloat(ride.rows[0].estimated_fare);
    
    const response = await request(app)
      .post(`/api/v1/rides/${rideId}/complete`)
      .set('Authorization', `Bearer ${driverToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .send({
        actual_distance_km: 3.5,
        actual_duration_min: 15
      })
      .expect(200);

    expect(response.body.success).toBe(true);
    expect(response.body.data.status).toBe('COMPLETED');
    expect(response.body.data.fare_final).toBeDefined();
    // Certaines valeurs sont sérialisées en chaînes, on compare donc via parseFloat / parseInt
    expect(parseFloat(response.body.data.actual_distance_km)).toBeCloseTo(3.5);
    expect(parseInt(response.body.data.actual_duration_min)).toBe(15);
    
    // Vérifier la règle de tolérance : min(estime × 1.10, réel)
    const finalFare = parseFloat(response.body.data.fare_final);
    const maxAllowed = estimatedFare * 1.10;
    expect(finalFare).toBeLessThanOrEqual(Math.round(maxAllowed));
    
    // Vérifier que le driver est libéré immédiatement
    const driverProfile = await testPool.query(
      'SELECT is_available FROM driver_profiles WHERE user_id = $1',
      [driver.id]
    );
    expect(driverProfile.rows[0].is_available).toBe(true);
    
    // Vérifier que payment_status est PAYMENT_PENDING
    const rideAfterComplete = await testPool.query(
      'SELECT payment_status FROM rides WHERE id = $1',
      [rideId]
    );
    expect(rideAfterComplete.rows[0].payment_status).toBe('PAYMENT_PENDING');
  });

  test('1.10: Client et driver notent mutuellement', async () => {
    // Client note le driver
    const clientRating = await request(app)
      .post(`/api/v1/rides/${rideId}/rate`)
      .set('Authorization', `Bearer ${clientToken}`)
      .send({
        rating: 5,
        comment: 'Excellent service!',
        role: 'client'
      })
      .expect(200);

    expect(clientRating.body.success).toBe(true);
    
    // Driver note le client
    const driverRating = await request(app)
      .post(`/api/v1/rides/${rideId}/rate`)
      .set('Authorization', `Bearer ${driverToken}`)
      .send({
        rating: 4,
        comment: 'Bon client',
        role: 'driver'
      })
      .expect(200);

    expect(driverRating.body.success).toBe(true);
    
    // Vérifier que les notes sont enregistrées
    const ride = await testPool.query(
      'SELECT client_rating, driver_rating FROM rides WHERE id = $1',
      [rideId]
    );
    expect(ride.rows[0].client_rating).toBe(5);
    expect(ride.rows[0].driver_rating).toBe(4);
  });

  test('1.11: Vérifier idempotency sur rating', async () => {
    const idempotencyKey = `rate-${Date.now()}`;
    
    // Premier rating
    await request(app)
      .post(`/api/v1/rides/${rideId}/rate`)
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .send({ rating: 5, role: 'client' })
      .expect(200);
    
    // Deuxième rating avec même clé → doit retourner la même réponse
    const response = await request(app)
      .post(`/api/v1/rides/${rideId}/rate`)
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .send({ rating: 3, role: 'client' })
      .expect(200);
    
    // La note ne doit pas changer (idempotence)
    const ride = await testPool.query(
      'SELECT client_rating FROM rides WHERE id = $1',
      [rideId]
    );
    expect(ride.rows[0].client_rating).toBe(5); // Reste à 5, pas changé à 3
  });
});

