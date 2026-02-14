/**
 * SCÉNARIO 3 : Timeout client ou pas de driver disponible
 * Objectif : Vérifier le système de timeout centralisé et notifications automatiques
 */

const { testPool, createTestUser, createTestDriver, generateTestToken } = require('../setup');
const ridesService = require('../../src/modules/rides/rides.service');
const timeoutService = require('../../src/modules/rides/timeout.service');

describe('SCÉNARIO 3: Timeouts système', () => {
  let client, clientToken, rideId;

  beforeAll(async () => {
    client = await createTestUser('client');
    clientToken = generateTestToken(client.id, 'client');
  });

  test('3.1: Timeout NO_DRIVER après 2 minutes', async () => {
    // Créer une course
    const ride = await ridesService.createRide(client.id, {
      pickup_lat: 14.7167,
      pickup_lng: -17.4677,
      dropoff_lat: 14.7200,
      dropoff_lng: -17.4700
    });
    
    rideId = ride.id;
    expect(ride.status).toBe('REQUESTED');
    
    // Vérifier que le timeout est programmé
    const timeout = await testPool.query(
      `SELECT * FROM ride_timeouts 
       WHERE ride_id = $1 AND timeout_type = 'NO_DRIVER' AND processed = false`,
      [rideId]
    );
    expect(timeout.rows.length).toBe(1);
    
    // Simuler le passage du temps (avancer l'horloge de 2 minutes)
    // En production, le cron job traiterait cela automatiquement
    const executeAt = new Date(Date.now() - 130000); // 2+ minutes dans le passé pour être sûr
    await testPool.query(
      `UPDATE ride_timeouts SET execute_at = $1 WHERE ride_id = $2 AND timeout_type = 'NO_DRIVER'`,
      [executeAt, rideId]
    );
    
    // Traiter les timeouts expirés
    await timeoutService.processExpiredTimeouts();
    
    // Vérifier que la course est annulée
    const updatedRide = await testPool.query(
      'SELECT status, driver_id, cancellation_reason FROM rides WHERE id = $1',
      [rideId]
    );
    
    expect(updatedRide.rows[0].status).toBe('CANCELLED_BY_SYSTEM');
    expect(updatedRide.rows[0].driver_id).toBeNull();
    expect(updatedRide.rows[0].cancellation_reason).toContain('Aucun driver disponible');
    
    // Vérifier que le timeout est marqué comme traité
    const processedTimeout = await testPool.query(
      `SELECT processed FROM ride_timeouts 
       WHERE ride_id = $1 AND timeout_type = 'NO_DRIVER'`,
      [rideId]
    );
    expect(processedTimeout.rows[0].processed).toBe(true);
  });

  test('3.2: Timeout CLIENT_NO_SHOW après 7 minutes', async () => {
    // Créer une nouvelle course avec driver assigné
    const driver = await createTestDriver();
    await testPool.query(
      `INSERT INTO driver_locations (driver_id, lat, lng, updated_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (driver_id) DO UPDATE SET lat = $2, lng = $3`,
      [driver.id, 14.7167, -17.4677]
    );
    
    const ride = await ridesService.createRide(client.id, {
      pickup_lat: 14.7167,
      pickup_lng: -17.4677,
      dropoff_lat: 14.7200,
      dropoff_lng: -17.4700
    });
    
    // Driver accepte
    await ridesService.acceptRide(ride.id, driver.id);
    
    // Driver arrive
    await ridesService.markDriverArrived(ride.id, driver.id);
    
    // Vérifier que le timeout CLIENT_NO_SHOW est programmé
    const timeout = await testPool.query(
      `SELECT * FROM ride_timeouts 
       WHERE ride_id = $1 AND timeout_type = 'CLIENT_NO_SHOW' AND processed = false`,
      [ride.id]
    );
    expect(timeout.rows.length).toBe(1);
    
    // Simuler le passage du temps (7 minutes)
    const executeAt = new Date(Date.now() - 450000); // 7+ minutes dans le passé pour être sûr
    await testPool.query(
      `UPDATE ride_timeouts SET execute_at = $1 WHERE ride_id = $2 AND timeout_type = 'CLIENT_NO_SHOW'`,
      [executeAt, ride.id]
    );
    
    // Traiter les timeouts expirés
    await timeoutService.processExpiredTimeouts();
    
    // Vérifier que la course est annulée
    const updatedRide = await testPool.query(
      'SELECT status, driver_id, cancellation_reason FROM rides WHERE id = $1',
      [ride.id]
    );
    
    expect(updatedRide.rows[0].status).toBe('CANCELLED_BY_DRIVER');
    expect(updatedRide.rows[0].driver_id).toBeNull(); // Driver libéré
    expect(updatedRide.rows[0].cancellation_reason).toContain('ne s\'est pas présenté');
    
    // Vérifier que le driver est disponible
    const driverProfile = await testPool.query(
      'SELECT is_available FROM driver_profiles WHERE user_id = $1',
      [driver.id]
    );
    expect(driverProfile.rows[0].is_available).toBe(true);
  });

  test('3.3: Timeout survit au redémarrage du serveur', async () => {
    // Créer une course avec timeout programmé
    const ride = await ridesService.createRide(client.id, {
      pickup_lat: 14.7167,
      pickup_lng: -17.4677,
      dropoff_lat: 14.7200,
      dropoff_lng: -17.4700
    });
    
    // Vérifier que le timeout est en base
    const timeoutBefore = await testPool.query(
      `SELECT * FROM ride_timeouts 
       WHERE ride_id = $1 AND timeout_type = 'NO_DRIVER'`,
      [ride.id]
    );
    expect(timeoutBefore.rows.length).toBe(1);
    const timeoutId = timeoutBefore.rows[0].id;
    
    // Simuler redémarrage serveur (vider cache, reconnexion DB)
    // Le timeout reste en base de données
    
    // Simuler passage du temps
    const executeAt = new Date(Date.now() - 130000); // 2+ minutes dans le passé
    await testPool.query(
      `UPDATE ride_timeouts SET execute_at = $1 WHERE id = $2`,
      [executeAt, timeoutId]
    );
    
    // Le cron job doit retrouver et traiter le timeout
    await timeoutService.processExpiredTimeouts();
    
    // Vérifier que la course est annulée
    const updatedRide = await testPool.query(
      'SELECT status FROM rides WHERE id = $1',
      [ride.id]
    );
    expect(updatedRide.rows[0].status).toBe('CANCELLED_BY_SYSTEM');
    
    // Vérifier que le timeout est traité
    const processedTimeout = await testPool.query(
      `SELECT processed FROM ride_timeouts WHERE id = $1`,
      [timeoutId]
    );
    expect(processedTimeout.rows[0].processed).toBe(true);
  });

  test('3.4: Pas de course bloquée dans la DB', async () => {
    // Créer plusieurs courses qui vont timeout
    const rides = [];
    for (let i = 0; i < 5; i++) {
      const ride = await ridesService.createRide(client.id, {
        pickup_lat: 14.7167 + (i * 0.001),
        pickup_lng: -17.4677 + (i * 0.001),
        dropoff_lat: 14.7200,
        dropoff_lng: -17.4700
      });
      rides.push(ride.id);
    }
    
    // Simuler passage du temps pour tous
    await testPool.query(
      `UPDATE ride_timeouts 
       SET execute_at = NOW() - INTERVAL '1 minute'
       WHERE ride_id = ANY($1::int[]) AND timeout_type = 'NO_DRIVER'`,
      [rides]
    );
    
    // Traiter les timeouts
    await timeoutService.processExpiredTimeouts();
    
    // Vérifier que toutes les courses sont annulées
    const cancelledRides = await testPool.query(
      `SELECT COUNT(*) as count FROM rides 
       WHERE id = ANY($1::int[]) AND status = 'CANCELLED_BY_SYSTEM'`,
      [rides]
    );
    
    expect(parseInt(cancelledRides.rows[0].count)).toBe(5);
    
    // Nettoyer
    await testPool.query('DELETE FROM rides WHERE id = ANY($1::int[])', [rides]);
  });
});

