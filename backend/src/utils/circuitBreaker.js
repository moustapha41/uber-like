const CircuitBreaker = require('opossum');

/**
 * Circuit Breaker pour APIs externes
 * Protège contre les pannes d'APIs tierces (Maps, SMS, etc.)
 */

class CircuitBreakerService {
  constructor() {
    this.breakers = {};
  }

  /**
   * Crée ou récupère un circuit breaker pour un service
   */
  getBreaker(serviceName, asyncFunction, options = {}) {
    if (!this.breakers[serviceName]) {
      const defaultOptions = {
        timeout: 5000, // 5 secondes timeout
        errorThresholdPercentage: 50, // 50% d'erreurs = ouvert
        resetTimeout: 30000, // 30 secondes pour reset
        ...options
      };

      this.breakers[serviceName] = new CircuitBreaker(asyncFunction, defaultOptions);

      // Écouter les événements
      this.breakers[serviceName].on('open', () => {
        console.warn(`Circuit breaker ${serviceName} opened - service unavailable`);
      });

      this.breakers[serviceName].on('halfOpen', () => {
        console.info(`Circuit breaker ${serviceName} half-open - testing service`);
      });

      this.breakers[serviceName].on('close', () => {
        console.info(`Circuit breaker ${serviceName} closed - service recovered`);
      });
    }

    return this.breakers[serviceName];
  }

  /**
   * Circuit breaker pour l'API Maps
   */
  getMapsBreaker(mapsService) {
    return this.getBreaker('maps', async (origin, destination) => {
      return await mapsService.getRoute(origin, destination);
    }, {
      fallback: () => ({
        distance: this.estimateDistance(origin, destination),
        duration: this.estimateDuration(origin, destination),
        fallback: true,
        error: 'Maps API unavailable, using fallback calculation'
      })
    });
  }

  /**
   * Estimation de distance en fallback (formule Haversine)
   */
  estimateDistance(origin, destination) {
    const R = 6371; // Rayon de la Terre en km
    const dLat = this.toRad(destination.lat - origin.lat);
    const dLon = this.toRad(destination.lng - origin.lng);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(this.toRad(origin.lat)) *
        Math.cos(this.toRad(destination.lat)) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }

  /**
   * Estimation de durée en fallback (2 min/km)
   */
  estimateDuration(origin, destination) {
    const distance = this.estimateDistance(origin, destination);
    return Math.ceil(distance * 2); // 2 minutes par km
  }

  toRad(degrees) {
    return degrees * (Math.PI / 180);
  }
}

module.exports = new CircuitBreakerService();

