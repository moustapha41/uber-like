/**
 * Maps Service
 * Handles geocoding, routing, and distance calculations
 * Supports: Google Maps, Mapbox, OpenStreetMap
 * Fallback: Haversine formula for distance calculation
 */

const https = require('https');
const http = require('http');

class MapsService {
  /**
   * Geocode an address to coordinates
   */
  async geocodeAddress(address) {
    // TODO: Implement geocoding (Google Maps/Mapbox/OSM)
    console.log(`Geocoding address: ${address}`);
    return {
      lat: 0,
      lng: 0,
      formattedAddress: address
    };
  }

  /**
   * Reverse geocode coordinates to address
   */
  async reverseGeocode(lat, lng) {
    // TODO: Implement reverse geocoding
    console.log(`Reverse geocoding: ${lat}, ${lng}`);
    return {
      address: 'Address not found',
      city: '',
      country: ''
    };
  }

  /**
   * Calculate distance between two points
   * Utilise la formule Haversine (distance à vol d'oiseau)
   * Pour distance réelle, utiliser getRoute() qui utilise les APIs
   */
  async calculateDistance(origin, destination) {
    if (!origin || !destination || !origin.lat || !origin.lng || !destination.lat || !destination.lng) {
      throw new Error('Invalid origin or destination coordinates');
    }

    const R = 6371; // Earth radius in km
    const dLat = this.toRad(destination.lat - origin.lat);
    const dLon = this.toRad(destination.lng - origin.lng);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(this.toRad(origin.lat)) *
        Math.cos(this.toRad(destination.lat)) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    const distance = R * c; // Distance in km

    return {
      distance: Math.round(distance * 100) / 100, // Arrondir à 2 décimales
      unit: 'km'
    };
  }

  /**
   * Get route between two points
   * Utilise l'API externe si disponible, sinon fallback Haversine
   */
  async getRoute(origin, destination, options = {}) {
    try {
      // Si une API externe est configurée, l'utiliser
      if (process.env.MAPBOX_ACCESS_TOKEN) {
        // Utiliser Mapbox (gratuit jusqu'à 100k requêtes/mois)
        return await this.getRouteFromMapbox(origin, destination, options);
      } else if (process.env.GOOGLE_MAPS_API_KEY) {
        // Utiliser Google Maps
        return await this.getRouteFromGoogleMaps(origin, destination, options);
      } else {
        // Fallback: Calcul Haversine avec estimation de durée
        return await this.getRouteFallback(origin, destination, options);
      }
    } catch (error) {
      console.error('Error getting route, using fallback:', error.message);
      // En cas d'erreur, utiliser le fallback
      return await this.getRouteFallback(origin, destination, options);
    }
  }

  /**
   * Fallback: Calcul route avec Haversine + estimation durée
   */
  async getRouteFallback(origin, destination, options = {}) {
    const distanceResult = await this.calculateDistance(origin, destination);
    const distance = distanceResult.distance;

    // Estimation durée basée sur vitesse moyenne (30 km/h en ville pour moto)
    const averageSpeedKmh = options.mode === 'driving' ? 30 : 20;
    const durationMinutes = Math.round((distance / averageSpeedKmh) * 60);

    return {
      distance: distance,
      duration: durationMinutes,
      distance_km: distance,
      duration_min: durationMinutes,
      polyline: '',
      steps: [],
      fallback: true
    };
  }

  /**
   * Get route from Mapbox API
   */
  async getRouteFromMapbox(origin, destination, options = {}) {
    const accessToken = process.env.MAPBOX_ACCESS_TOKEN;
    const profile = options.mode === 'driving' ? 'driving' : 'driving';

    return new Promise((resolve, reject) => {
      const params = new URLSearchParams({
        access_token: accessToken,
        geometries: 'geojson',
        overview: 'simplified',
        steps: 'false'
      });
      const url = `https://api.mapbox.com/directions/v5/mapbox/${profile}/${origin.lng},${origin.lat};${destination.lng},${destination.lat}?${params}`;
      
      https.get(url, (res) => {
        let data = '';
        res.on('data', (chunk) => { data += chunk; });
        res.on('end', () => {
          try {
            const jsonData = JSON.parse(data);

            if (jsonData && jsonData.routes && jsonData.routes.length > 0) {
              const route = jsonData.routes[0];
              resolve({
                distance: route.distance / 1000, // Convertir mètres en km
                duration: Math.round(route.duration / 60), // Convertir secondes en minutes
                distance_km: route.distance / 1000,
                duration_min: Math.round(route.duration / 60),
                polyline: JSON.stringify(route.geometry),
                steps: [],
                fallback: false
              });
            } else {
              reject(new Error('No route found'));
            }
          } catch (error) {
            reject(error);
          }
        });
      }).on('error', (error) => {
        console.error('Mapbox API error:', error.message);
        reject(error);
      });
    });
  }

  /**
   * Get route from Google Maps API
   */
  async getRouteFromGoogleMaps(origin, destination, options = {}) {
    const apiKey = process.env.GOOGLE_MAPS_API_KEY;

    return new Promise((resolve, reject) => {
      const params = new URLSearchParams({
        origin: `${origin.lat},${origin.lng}`,
        destination: `${destination.lat},${destination.lng}`,
        key: apiKey,
        mode: options.mode || 'driving',
        language: 'fr'
      });
      const url = `https://maps.googleapis.com/maps/api/directions/json?${params}`;
      
      https.get(url, (res) => {
        let data = '';
        res.on('data', (chunk) => { data += chunk; });
        res.on('end', () => {
          try {
            const jsonData = JSON.parse(data);
            
            if (jsonData && jsonData.routes && jsonData.routes.length > 0) {
              const route = jsonData.routes[0];
              const leg = route.legs[0];
              
              resolve({
                distance: leg.distance.value / 1000,
                duration: Math.round(leg.duration.value / 60),
                distance_km: leg.distance.value / 1000,
                duration_min: Math.round(leg.duration.value / 60),
                polyline: route.overview_polyline.points,
                steps: leg.steps.map(step => ({
                  distance: step.distance.value / 1000,
                  duration: Math.round(step.duration.value / 60),
                  instruction: step.html_instructions
                })),
                fallback: false
              });
            } else {
              reject(new Error('No route found'));
            }
          } catch (error) {
            reject(error);
          }
        });
      }).on('error', (error) => {
        console.error('Google Maps API error:', error.message);
        reject(error);
      });
    });
  }

  /**
   * Get estimated time of arrival
   */
  async getETA(origin, destination, mode = 'driving') {
    // TODO: Implement ETA calculation
    const route = await this.getRoute(origin, destination);
    return route.duration;
  }

  /**
   * Convert degrees to radians
   */
  toRad(degrees) {
    return degrees * (Math.PI / 180);
  }

  /**
   * Check if location is in restricted zone
   */
  async isRestrictedZone(lat, lng) {
    // TODO: Implement restricted zone check
    return false;
  }
}

module.exports = new MapsService();

