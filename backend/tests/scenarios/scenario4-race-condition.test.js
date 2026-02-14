/**
 * SCÉNARIO 4 : Race condition - Double acceptation
 * Objectif : Valider que 2 drivers ne peuvent pas accepter la même course
 */

const { testPool, createTestUser, createTestDriver, generateTestToken } = require('../setup');
const ridesService = require('../../src/modules/rides/rides.service');

describe('SCÉNARIO 4: Race condition - Double acceptation', () => {
  let client, drivers, rideId;

  beforeAll(async () => {
    client = await createTestUser('client');
    
    // Créer 10 drivers
    drivers = [];
    for (let i = 0; i < 10; i++) {
      const driver = await createTestDriver();
      await testPool.query(
        `INSERT INTO driver_locations (driver_id, lat, lng, updated_at)
         VALUES ($1, $2, $3, NOW())
         ON CONFLICT (driver_id) DO UPDATE SET lat = $2, lng = $3`,
        [driver.id, 14.7167, -17.4677]
      );
      drivers.push(driver);
    }
  });

  test('4.1: 10 drivers essayent d\'accepter la même course simultanément', async () => {
    // Créer une course
    const ride = await ridesService.createRide(client.id, {
      pickup_lat: 14.7167,
      pickup_lng: -17.4677,
      dropoff_lat: 14.7200,
      dropoff_lng: -17.4700
    });
    
    rideId = ride.id;
    expect(ride.status).toBe('REQUESTED');
    
    // Simuler 10 drivers qui acceptent en même temps
    const promises = drivers.map((driver, index) => 
      ridesService.acceptRide(rideId, driver.id)
    );
    
    const results = await Promise.allSettled(promises);
    
    // Analyser les résultats
    const successful = results.filter(r => r.status === 'fulfilled').length;
    const failed = results.filter(r => r.status === 'rejected').length;
    
    // UN SEUL DOIT RÉUSSIR
    expect(successful).toBe(1);
    expect(failed).toBe(9);
    
    // Vérifier que le gagnant est bien enregistré
    const updatedRide = await testPool.query(
      'SELECT status, driver_id FROM rides WHERE id = $1',
      [rideId]
    );
    
    expect(updatedRide.rows[0].status).toBe('DRIVER_ASSIGNED');
    expect(drivers.map(d => d.id)).toContain(updatedRide.rows[0].driver_id);
    
    // Vérifier que les échecs sont des erreurs appropriées
    const rejectionReasons = results
      .filter(r => r.status === 'rejected')
      .map(r => r.reason.message);
    
    const hasAlreadyAccepted = rejectionReasons.some(msg => 
      msg.includes('already accepted') || 
      msg.includes('cannot be accepted') ||
      msg.includes('Current status')
    );
    
    expect(hasAlreadyAccepted).toBe(true);
  });

  test('4.2: Vérifier que seul le driver gagnant est assigné', async () => {
    // Créer une nouvelle course
    const ride = await ridesService.createRide(client.id, {
      pickup_lat: 14.7167,
      pickup_lng: -17.4677,
      dropoff_lat: 14.7200,
      dropoff_lng: -17.4700
    });
    
    // S'assurer que tous les drivers sont de nouveau marqués disponibles
    await testPool.query(
      'UPDATE driver_profiles SET is_available = true WHERE user_id = ANY($1::int[])',
      [drivers.map(d => d.id)]
    );
    
    // Simuler acceptation simultanée
    const promises = drivers.slice(0, 5).map(driver =>
      ridesService.acceptRide(ride.id, driver.id)
    );
    
    const results = await Promise.allSettled(promises);
    const successful = results.filter(r => r.status === 'fulfilled');
    
    expect(successful.length).toBe(1);
    
    // Vérifier en base que seul un driver est assigné
    const rideCheck = await testPool.query(
      'SELECT driver_id FROM rides WHERE id = $1',
      [ride.id]
    );
    
    expect(rideCheck.rows[0].driver_id).toBeDefined();
    
    // Vérifier que les autres drivers sont toujours disponibles
    const assignedDriverId = rideCheck.rows[0].driver_id;
    const otherDrivers = drivers.filter(d => d.id !== assignedDriverId).slice(0, 3);
    
    for (const driver of otherDrivers) {
      const driverProfile = await testPool.query(
        'SELECT is_available FROM driver_profiles WHERE user_id = $1',
        [driver.id]
      );
      expect(driverProfile.rows[0].is_available).toBe(true);
    }
    
    // Nettoyer
    await testPool.query('DELETE FROM rides WHERE id = $1', [ride.id]);
  });
});

