/**
 * SCÉNARIO 2 : Annulation par le client avant démarrage
 * Objectif : Vérifier la gestion des annulations et libération du driver
 */

const request = require('supertest');
const { app } = require('../../src/app');
const { testPool, createTestUser, createTestDriver, generateTestToken } = require('../setup');

describe('SCÉNARIO 2: Annulation par le client avant démarrage', () => {
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

  test('2.1: Client crée une course', async () => {
    const response = await request(app)
      .post('/api/v1/rides')
      .set('Authorization', `Bearer ${clientToken}`)
      .send({
        pickup_lat: 14.7167,
        pickup_lng: -17.4677,
        dropoff_lat: 14.7200,
        dropoff_lng: -17.4700
      })
      .expect(201);

    rideId = response.body.data.id;
    expect(response.body.data.status).toBe('REQUESTED');
  });

  test('2.2: Driver accepte la course', async () => {
    const response = await request(app)
      .post(`/api/v1/rides/${rideId}/accept`)
      .set('Authorization', `Bearer ${driverToken}`)
      .set('Idempotency-Key', `accept-${Date.now()}`)
      .expect(200);

    expect(response.body.data.status).toBe('DRIVER_ASSIGNED');
    expect(response.body.data.driver_id).toBe(driver.id);
    
    // Vérifier que le driver n'est plus disponible
    const driverProfile = await testPool.query(
      'SELECT is_available FROM driver_profiles WHERE user_id = $1',
      [driver.id]
    );
    expect(driverProfile.rows[0].is_available).toBe(false);
  });

  test('2.3: Client annule la course', async () => {
    const idempotencyKey = `cancel-${Date.now()}`;
    
    const response = await request(app)
      .post(`/api/v1/rides/${rideId}/cancel`)
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .send({ reason: 'Changement de plan' })
      .expect(200);

    expect(response.body.success).toBe(true);
    expect(response.body.data.status).toBe('CANCELLED_BY_CLIENT');
    expect(response.body.data.cancellation_reason).toBe('Changement de plan');
    
    // Vérifier que driver_id reste (pour historique) mais driver est disponible
    const ride = await testPool.query(
      'SELECT driver_id FROM rides WHERE id = $1',
      [rideId]
    );
    expect(ride.rows[0].driver_id).toBe(driver.id); // Reste pour historique
    
    // Vérifier que le driver est libéré
    const driverProfile = await testPool.query(
      'SELECT is_available FROM driver_profiles WHERE user_id = $1',
      [driver.id]
    );
    expect(driverProfile.rows[0].is_available).toBe(true);
  });

  test('2.4: Driver peut accepter d\'autres courses après annulation', async () => {
    // Créer une nouvelle course
    const newRide = await request(app)
      .post('/api/v1/rides')
      .set('Authorization', `Bearer ${clientToken}`)
      .send({
        pickup_lat: 14.7167,
        pickup_lng: -17.4677,
        dropoff_lat: 14.7200,
        dropoff_lng: -17.4700
      })
      .expect(201);

    const newRideId = newRide.body.data.id;
    
    // Driver peut accepter la nouvelle course
    const acceptResponse = await request(app)
      .post(`/api/v1/rides/${newRideId}/accept`)
      .set('Authorization', `Bearer ${driverToken}`)
      .set('Idempotency-Key', `accept-${Date.now()}`)
      .expect(200);

    expect(acceptResponse.body.data.status).toBe('DRIVER_ASSIGNED');
    expect(acceptResponse.body.data.driver_id).toBe(driver.id);
    
    // Nettoyer
    await testPool.query('DELETE FROM rides WHERE id = $1', [newRideId]);
  });

  test('2.5: Idempotency empêche double annulation', async () => {
    const idempotencyKey = `cancel-idempotent-${Date.now()}`;
    
    // Créer une nouvelle course pour tester
    const newRide = await request(app)
      .post('/api/v1/rides')
      .set('Authorization', `Bearer ${clientToken}`)
      .send({
        pickup_lat: 14.7167,
        pickup_lng: -17.4677,
        dropoff_lat: 14.7200,
        dropoff_lng: -17.4700
      });
    
    const newRideId = newRide.body.data.id;
    
    // Première annulation
    await request(app)
      .post(`/api/v1/rides/${newRideId}/cancel`)
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .send({ reason: 'Test' });
    
    // Deuxième annulation avec même clé → doit retourner la même réponse
    const secondCancel = await request(app)
      .post(`/api/v1/rides/${newRideId}/cancel`)
      .set('Authorization', `Bearer ${clientToken}`)
      .set('Idempotency-Key', idempotencyKey)
      .send({ reason: 'Test 2' })
      .expect(200);
    
    // Vérifier que la raison n'a pas changé (idempotence)
    const ride = await testPool.query(
      'SELECT cancellation_reason FROM rides WHERE id = $1',
      [newRideId]
    );
    expect(ride.rows[0].cancellation_reason).toBe('Test'); // Reste "Test", pas "Test 2"
    
    // Nettoyer
    await testPool.query('DELETE FROM rides WHERE id = $1', [newRideId]);
  });
});

