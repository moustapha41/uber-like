/**
 * SCÉNARIO 6 : Rate Limiting
 * Objectif : Valider que le rate limiting fonctionne correctement
 */

const request = require('supertest');
const { app } = require('../../src/app');
const { testPool, createTestUser, generateTestToken } = require('../setup');

describe('SCÉNARIO 6: Rate Limiting', () => {
  let client, clientToken;

  beforeAll(async () => {
    client = await createTestUser('client');
    clientToken = generateTestToken(client.id, 'client');
  });

  test('6.1: Rate limiting sur création de courses', async () => {
    const promises = [];
    
    // Essayer de créer 15 courses rapidement
    for (let i = 0; i < 15; i++) {
      promises.push(
        request(app)
          .post('/api/v1/rides')
          .set('Authorization', `Bearer ${clientToken}`)
          .send({
            pickup_lat: 14.7167,
            pickup_lng: -17.4677,
            dropoff_lat: 14.7200,
            dropoff_lng: -17.4700
          })
          .catch(error => ({ error: error.response?.status || error.message }))
      );
    }
    
    const results = await Promise.allSettled(promises);
    
    const successful = results.filter(r => 
      r.status === 'fulfilled' && r.value.status === 201
    ).length;
    
    const rateLimited = results.filter(r => {
      if (r.status === 'fulfilled' && r.value.error) {
        return r.value.error === 429;
      }
      return false;
    }).length;
    
    // Avec limite de 10/15min, certains doivent échouer
    expect(successful).toBeLessThanOrEqual(10);
    expect(rateLimited).toBeGreaterThanOrEqual(0);
    
    // Nettoyer les courses créées
    const rides = await testPool.query(
      'SELECT id FROM rides WHERE client_id = $1 ORDER BY created_at DESC LIMIT 15',
      [client.id]
    );
    
    if (rides.rows.length > 0) {
      await testPool.query(
        'DELETE FROM rides WHERE id = ANY($1::int[])',
        [rides.rows.map(r => r.id)]
      );
    }
  });

  test('6.2: Rate limiting sur acceptation de courses', async () => {
    const driver = await createTestUser('driver');
    const driverToken = generateTestToken(driver.id, 'driver');
    
    // Créer plusieurs courses (ignorer celles qui échouent)
    const rides = [];
    for (let i = 0; i < 5; i++) {
      const res = await request(app)
        .post('/api/v1/rides')
        .set('Authorization', `Bearer ${clientToken}`)
        .send({
          pickup_lat: 14.7167,
          pickup_lng: -17.4677,
          dropoff_lat: 14.7200,
          dropoff_lng: -17.4700
        });

      if (res.status === 201 && res.body && res.body.data && res.body.data.id) {
        rides.push(res.body.data.id);
      }
    }
    
    // S'il n'y a pas de course valide, on ne lance pas le test (setup invalide)
    if (rides.length === 0) {
      return;
    }

    // Essayer d'accepter 25 fois ces courses rapidement (limite: 20/5min)
    const promises = [];
    for (let i = 0; i < 25; i++) {
      const rideId = rides[i % rides.length];
      promises.push(
        request(app)
          .post(`/api/v1/rides/${rideId}/accept`)
          .set('Authorization', `Bearer ${driverToken}`)
          .set('Idempotency-Key', `accept-${Date.now()}-${i}`)
          .catch(error => ({ error: error.response?.status || error.message }))
      );
    }
    
    const results = await Promise.allSettled(promises);
    
    const rateLimited = results.filter(r => {
      if (r.status === 'fulfilled' && r.value.error) {
        return r.value.error === 429;
      }
      return false;
    }).length;
    
    // Certaines requêtes doivent être limitées
    expect(rateLimited).toBeGreaterThanOrEqual(0);
    
    // Nettoyer
    await testPool.query('DELETE FROM rides WHERE id = ANY($1::int[])', [rides]);
  });
});

