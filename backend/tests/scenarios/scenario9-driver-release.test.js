/**
 * SCÉNARIO 9 : Libération du driver
 * Objectif : Valider que le driver est libéré correctement dans tous les cas
 */

const { testPool, createTestUser, createTestDriver } = require('../setup');
const ridesService = require('../../src/modules/rides/rides.service');

describe('SCÉNARIO 9: Libération du driver', () => {
  let client, driver;

  beforeAll(async () => {
    client = await createTestUser('client');
    driver = await createTestDriver();
    
    await testPool.query(
      `INSERT INTO driver_locations (driver_id, lat, lng, updated_at)
       VALUES ($1, $2, $3, NOW())
       ON CONFLICT (driver_id) DO UPDATE SET lat = $2, lng = $3`,
      [driver.id, 14.7167, -17.4677]
    );
  });

  test('9.1: Driver libéré immédiatement après COMPLETED', async () => {
    // Créer et compléter une course
    const ride = await ridesService.createRide(client.id, {
      pickup_lat: 14.7167,
      pickup_lng: -17.4677,
      dropoff_lat: 14.7200,
      dropoff_lng: -17.4700
    });
    
    await ridesService.acceptRide(ride.id, driver.id);
    await ridesService.markDriverArrived(ride.id, driver.id);
    await ridesService.startRide(ride.id, driver.id);
    
    // Vérifier que le driver n'est pas disponible avant completion
    let driverProfile = await testPool.query(
      'SELECT is_available FROM driver_profiles WHERE user_id = $1',
      [driver.id]
    );
    expect(driverProfile.rows[0].is_available).toBe(false);
    
    // Compléter la course
    await ridesService.completeRide(ride.id, driver.id, 3.5, 15);
    
    // Vérifier que le driver est libéré IMMÉDIATEMENT
    driverProfile = await testPool.query(
      'SELECT is_available FROM driver_profiles WHERE user_id = $1',
      [driver.id]
    );
    expect(driverProfile.rows[0].is_available).toBe(true);
    
    // Vérifier que payment_status est PAYMENT_PENDING (pas encore payé)
    const rideAfterComplete = await testPool.query(
      'SELECT payment_status FROM rides WHERE id = $1',
      [ride.id]
    );
    expect(rideAfterComplete.rows[0].payment_status).toBe('PAYMENT_PENDING');
  });

  test('9.2: Driver libéré après annulation CANCELLED_BY_DRIVER', async () => {
    const ride = await ridesService.createRide(client.id, {
      pickup_lat: 14.7167,
      pickup_lng: -17.4677,
      dropoff_lat: 14.7200,
      dropoff_lng: -17.4700
    });
    
    await ridesService.acceptRide(ride.id, driver.id);
    
    // Driver annule
    await ridesService.cancelRide(ride.id, 'driver', 'Problème véhicule');
    
    // Vérifier que driver_id = NULL
    const rideAfterCancel = await testPool.query(
      'SELECT driver_id FROM rides WHERE id = $1',
      [ride.id]
    );
    expect(rideAfterCancel.rows[0].driver_id).toBeNull();
    
    // Vérifier que le driver est disponible
    const driverProfile = await testPool.query(
      'SELECT is_available FROM driver_profiles WHERE user_id = $1',
      [driver.id]
    );
    expect(driverProfile.rows[0].is_available).toBe(true);
  });

  test('9.3: Driver libéré après annulation CANCELLED_BY_SYSTEM', async () => {
    const ride = await ridesService.createRide(client.id, {
      pickup_lat: 14.7167,
      pickup_lng: -17.4677,
      dropoff_lat: 14.7200,
      dropoff_lng: -17.4700
    });
    
    await ridesService.acceptRide(ride.id, driver.id);
    
    // Système annule (timeout)
    await ridesService.cancelRide(ride.id, 'system', 'Timeout');
    
    // Vérifier que driver_id = NULL
    const rideAfterCancel = await testPool.query(
      'SELECT driver_id FROM rides WHERE id = $1',
      [ride.id]
    );
    expect(rideAfterCancel.rows[0].driver_id).toBeNull();
    
    // Vérifier que le driver est disponible
    const driverProfile = await testPool.query(
      'SELECT is_available FROM driver_profiles WHERE user_id = $1',
      [driver.id]
    );
    expect(driverProfile.rows[0].is_available).toBe(true);
  });

  test('9.4: Driver_id reste après CANCELLED_BY_CLIENT (historique)', async () => {
    const ride = await ridesService.createRide(client.id, {
      pickup_lat: 14.7167,
      pickup_lng: -17.4677,
      dropoff_lat: 14.7200,
      dropoff_lng: -17.4700
    });
    
    await ridesService.acceptRide(ride.id, driver.id);
    
    // Client annule
    await ridesService.cancelRide(ride.id, 'client', 'Changement de plan');
    
    // Vérifier que driver_id reste (pour historique)
    const rideAfterCancel = await testPool.query(
      'SELECT driver_id FROM rides WHERE id = $1',
      [ride.id]
    );
    expect(rideAfterCancel.rows[0].driver_id).toBe(driver.id);
    
    // Mais le driver est disponible
    const driverProfile = await testPool.query(
      'SELECT is_available FROM driver_profiles WHERE user_id = $1',
      [driver.id]
    );
    expect(driverProfile.rows[0].is_available).toBe(true);
  });

  test('9.5: Driver peut accepter nouvelle course immédiatement après COMPLETED', async () => {
    // Première course
    const ride1 = await ridesService.createRide(client.id, {
      pickup_lat: 14.7167,
      pickup_lng: -17.4677,
      dropoff_lat: 14.7200,
      dropoff_lng: -17.4700
    });
    
    await ridesService.acceptRide(ride1.id, driver.id);
    await ridesService.markDriverArrived(ride1.id, driver.id);
    await ridesService.startRide(ride1.id, driver.id);
    await ridesService.completeRide(ride1.id, driver.id, 3.5, 15);
    
    // Vérifier que le driver est disponible
    let driverProfile = await testPool.query(
      'SELECT is_available FROM driver_profiles WHERE user_id = $1',
      [driver.id]
    );
    expect(driverProfile.rows[0].is_available).toBe(true);
    
    // Créer une deuxième course
    const ride2 = await ridesService.createRide(client.id, {
      pickup_lat: 14.7167,
      pickup_lng: -17.4677,
      dropoff_lat: 14.7200,
      dropoff_lng: -17.4700
    });
    
    // Driver peut accepter immédiatement
    await ridesService.acceptRide(ride2.id, driver.id);
    
    const ride2Check = await testPool.query(
      'SELECT status FROM rides WHERE id = $1',
      [ride2.id]
    );
    expect(ride2Check.rows[0].status).toBe('DRIVER_ASSIGNED');
    
    // Nettoyer
    await testPool.query('DELETE FROM rides WHERE id IN ($1, $2)', [ride1.id, ride2.id]);
  });
});

