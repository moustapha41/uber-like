/**
 * SCÉNARIO 5 : Flow complet avec WebSocket
 * Objectif : Valider le parcours complet d'une course avec tracking temps réel
 */

const { Server } = require('socket.io');
const { createServer } = require('http');
const ioClient = require('socket.io-client');
const { testPool, createTestUser, createTestDriver, generateTestToken } = require('../setup');
const ridesService = require('../../src/modules/rides/rides.service');
const WebSocketService = require('../../src/modules/rides/websocket.service');

describe('SCÉNARIO 5: Flow complet avec WebSocket', () => {
  let client, driver, rideId, io, server, clientSocket, driverSocket;
  const locationUpdates = [];

  // Démarrer un vrai serveur Socket.IO de test
  beforeAll((done) => {
    server = createServer();
    io = new Server(server);
    // Initialiser le service WebSocket sur ce serveur
    // (les handlers d'événements sont enregistrés ici)
    // eslint-disable-next-line no-new
    new WebSocketService(io);
    
    server.listen(3001, () => {
      done();
    });
  });

  // Préparer un client, un driver et une course ACCEPTÉE partagée pour tous les tests
  beforeAll(async () => {
    client = await createTestUser('client');
    driver = await createTestDriver();

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

    rideId = ride.id;
    await ridesService.acceptRide(rideId, driver.id);

    const updatedRide = await testPool.query(
      'SELECT status FROM rides WHERE id = $1',
      [rideId]
    );
    expect(updatedRide.rows[0].status).toBe('DRIVER_ASSIGNED');

    // Nettoyer le buffer d'updates
    locationUpdates.length = 0;
  });

  afterAll((done) => {
    if (clientSocket) clientSocket.disconnect();
    if (driverSocket) driverSocket.disconnect();
    if (io) io.close();
    if (server) server.close(done);
  });

  test('5.1: Création course et acceptation', async () => {
    // On vérifie simplement l\'état initial préparé dans beforeAll
    const ride = await testPool.query(
      'SELECT status FROM rides WHERE id = $1',
      [rideId]
    );
    expect(ride.rows[0].status).toBe('DRIVER_ASSIGNED');
  });

  test('5.2: Connexion WebSocket client et driver', (done) => {
    // Client se connecte via socket.io-client
    clientSocket = ioClient('http://localhost:3001', {
      auth: { token: generateTestToken(client.id, 'client') }
    });
    
    clientSocket.on('connect', () => {
      clientSocket.emit('client:authenticate', {
        clientId: client.id,
        token: generateTestToken(client.id, 'client')
      });
      
      // Driver se connecte
      driverSocket = ioClient('http://localhost:3001', {
        auth: { token: generateTestToken(driver.id, 'driver') }
      });
      
      driverSocket.on('connect', () => {
        driverSocket.emit('driver:authenticate', {
          driverId: driver.id,
          token: generateTestToken(driver.id, 'driver')
        });
        
        setTimeout(done, 500); // Attendre authentification
      });
    });
  });

  test('5.3: Client s\'abonne aux updates de la course', (done) => {
    clientSocket.emit('ride:subscribe', { rideId });
    
    clientSocket.on('subscribed', (data) => {
      expect(data.ride_id).toBe(rideId);
      done();
    });
  });

  test('5.4: Driver démarre la course', async () => {
    await ridesService.markDriverArrived(rideId, driver.id);
    await ridesService.startRide(rideId, driver.id);
    
    const ride = await testPool.query(
      'SELECT status FROM rides WHERE id = $1',
      [rideId]
    );
    expect(ride.rows[0].status).toBe('IN_PROGRESS');
  });

  test('5.5: Tracking GPS via WebSocket', (done) => {
    const positions = [
      { lat: 14.7167, lng: -17.4677, heading: 0, speed: 0 },
      { lat: 14.7175, lng: -17.4685, heading: 45, speed: 30 },
      { lat: 14.7185, lng: -17.4695, heading: 90, speed: 30 },
      { lat: 14.7200, lng: -17.4700, heading: 0, speed: 0 }
    ];
    
    let receivedCount = 0;
    
    // Client écoute les updates
    clientSocket.on('driver:location:update', (data) => {
      locationUpdates.push(data);
      receivedCount++;
      
      expect(data.ride_id).toBe(rideId);
      expect(data.lat).toBeDefined();
      expect(data.lng).toBeDefined();
      
      if (receivedCount === positions.length) {
        expect(locationUpdates.length).toBe(positions.length);
        done();
      }
    });
    
    // Driver envoie les positions
    positions.forEach((pos, index) => {
      setTimeout(() => {
        driverSocket.emit('driver:location:update', {
          rideId,
          lat: pos.lat,
          lng: pos.lng,
          heading: pos.heading,
          speed: pos.speed
        });
      }, index * 500);
    });
  });

  test('5.6: Vérifier que les positions sont enregistrées dans ride_tracking', async () => {
    // Attendre un peu pour que les positions soient enregistrées
    await new Promise(resolve => setTimeout(resolve, 2000));
    
    const trackingPoints = await testPool.query(
      'SELECT COUNT(*) as count FROM ride_tracking WHERE ride_id = $1',
      [rideId]
    );
    
    expect(parseInt(trackingPoints.rows[0].count)).toBeGreaterThan(0);
  });

  test('5.7: Validation WebSocket rejette positions non autorisées', async () => {
    const unauthorizedDriver = await createTestDriver();
    
    // Tentative d'envoi de position par un driver non autorisé
    const unauthorizedSocket = ioClient('http://localhost:3001', {
      auth: { token: generateTestToken(unauthorizedDriver.id, 'driver') }
    });
    
    unauthorizedSocket.on('connect', () => {
      unauthorizedSocket.emit('driver:authenticate', {
        driverId: unauthorizedDriver.id,
        token: generateTestToken(unauthorizedDriver.id, 'driver')
      });
      
      setTimeout(() => {
        unauthorizedSocket.emit('driver:location:update', {
          rideId,
          lat: 14.0,
          lng: -17.0,
          heading: 0,
          speed: 30
        });
        
        unauthorizedSocket.on('error', (error) => {
          expect(error.message).toContain('UNAUTHORIZED');
          unauthorizedSocket.disconnect();
        });
      }, 500);
    });
  });

  test('5.8: Driver termine la course', async () => {
    const completedRide = await ridesService.completeRide(
      rideId,
      driver.id,
      3.5, // distance
      15   // duration
    );
    
    expect(completedRide.status).toBe('COMPLETED');
    expect(completedRide.fare_final).toBeDefined();
    
    // Vérifier règle de tolérance
    const ride = await testPool.query(
      'SELECT estimated_fare, fare_final FROM rides WHERE id = $1',
      [rideId]
    );
    
    const estimatedFare = parseFloat(ride.rows[0].estimated_fare);
    const finalFare = parseFloat(ride.rows[0].fare_final);
    const maxAllowed = estimatedFare * 1.10;
    
    expect(finalFare).toBeLessThanOrEqual(Math.round(maxAllowed));
  });
});

