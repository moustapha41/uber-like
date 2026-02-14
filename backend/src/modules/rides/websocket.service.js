/**
 * WebSocket Service for Real-time GPS Tracking
 * Remplace les POST /location toutes les 5 secondes
 * Utilise Socket.IO pour la communication bidirectionnelle
 */

class WebSocketService {
  constructor(io) {
    this.io = io;
    this.setupEventHandlers();
  }

  /**
   * Configure les gestionnaires d'événements WebSocket
   */
  setupEventHandlers() {
    this.io.on('connection', (socket) => {
      console.log(`Client connected: ${socket.id}`);

      // Driver s'authentifie et rejoint sa room
      socket.on('driver:authenticate', async (data) => {
        try {
          const { driverId, token } = data;
          // TODO: Vérifier le token JWT
          socket.driverId = driverId;
          socket.join(`driver_${driverId}`);
          socket.emit('authenticated', { success: true });
        } catch (error) {
          socket.emit('error', { message: 'Authentication failed' });
        }
      });

      // Client s'authentifie et rejoint sa room
      socket.on('client:authenticate', async (data) => {
        try {
          const { clientId, token } = data;
          // TODO: Vérifier le token JWT
          socket.clientId = clientId;
          socket.join(`client_${clientId}`);
          socket.emit('authenticated', { success: true });
        } catch (error) {
          socket.emit('error', { message: 'Authentication failed' });
        }
      });

      // Driver envoie sa position GPS (remplace POST /location)
      socket.on('driver:location:update', async (data) => {
        try {
          // 🔴 VALIDATION OBLIGATOIRE
          if (!data.rideId || !socket.driverId) {
            return socket.emit('error', { message: 'Invalid data: rideId and authentication required' });
          }

          const { rideId, lat, lng, heading, speed } = data;

          // Validation des coordonnées
          if (typeof lat !== 'number' || typeof lng !== 'number' || 
              lat < -90 || lat > 90 || lng < -180 || lng > 180) {
            return socket.emit('error', { message: 'Invalid coordinates' });
          }

          const pool = require('../../config/database');

          // 🔴 VÉRIFIER QUE LE DRIVER EST BIEN ASSIGNÉ À CETTE COURSE ET EN STATUT IN_PROGRESS
          const rideCheck = await pool.query(
            `SELECT client_id, status FROM rides 
             WHERE id = $1 AND driver_id = $2 AND status = 'IN_PROGRESS'`,
            [rideId, socket.driverId]
          );

          if (rideCheck.rows.length === 0) {
            return socket.emit('error', { 
              message: 'Not authorized to update location for this ride' 
            });
          }

          const ride = rideCheck.rows[0];

          // Mettre à jour la position dans driver_locations (snapshot global)
          await pool.query(
            `INSERT INTO driver_locations (driver_id, lat, lng, heading, speed_kmh, updated_at)
             VALUES ($1, $2, $3, $4, $5, NOW())
             ON CONFLICT (driver_id) 
             DO UPDATE SET lat = $2, lng = $3, heading = $4, speed_kmh = $5, updated_at = NOW()`,
            [socket.driverId, lat, lng, heading || null, speed || null]
          );

          // 📌 SOURCE DE VÉRITÉ : ride_tracking (historique métier pendant IN_PROGRESS)
          await pool.query(
            'INSERT INTO ride_tracking (ride_id, lat, lng) VALUES ($1, $2, $3)',
            [rideId, lat, lng]
          );

          // Broadcast la position au client
          this.io.to(`client_${ride.client_id}`).emit('driver:location:update', {
            ride_id: rideId,
            lat,
            lng,
            heading: heading || null,
            speed: speed || null,
            timestamp: new Date().toISOString()
          });
        } catch (error) {
          console.error('Error updating driver location:', error);
          socket.emit('error', { message: 'Failed to update location' });
        }
      });

      // Client rejoint la room d'une course pour recevoir les updates
      socket.on('ride:subscribe', (data) => {
        const { rideId } = data;
        socket.join(`ride_${rideId}`);
        socket.emit('subscribed', { ride_id: rideId });
      });

      // Notifier les drivers d'une nouvelle demande de course
      socket.on('ride:new_request', (data) => {
        const { driverIds, rideData } = data;
        driverIds.forEach(driverId => {
          this.io.to(`driver_${driverId}`).emit('ride:new_request', rideData);
        });
      });

      // Notifier le client qu'un driver a accepté
      socket.on('ride:driver_assigned', (data) => {
        const { clientId, driverData } = data;
        this.io.to(`client_${clientId}`).emit('ride:driver_assigned', driverData);
      });

      socket.on('disconnect', () => {
        console.log(`Client disconnected: ${socket.id}`);
      });
    });
  }

  /**
   * Émet un événement à un driver spécifique
   */
  emitToDriver(driverId, event, data) {
    this.io.to(`driver_${driverId}`).emit(event, data);
  }

  /**
   * Émet un événement à un client spécifique
   */
  emitToClient(clientId, event, data) {
    this.io.to(`client_${clientId}`).emit(event, data);
  }

  /**
   * Broadcast un événement à tous les clients d'une course
   */
  emitToRide(rideId, event, data) {
    this.io.to(`ride_${rideId}`).emit(event, data);
  }
}

module.exports = WebSocketService;

