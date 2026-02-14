const pool = require('../../config/database');

/**
 * Pricing Service
 * Gère le calcul des prix des courses selon la configuration admin
 */

class PricingService {
  /**
   * Récupère la configuration de tarification active
   */
  async getActivePricingConfig(serviceType = 'ride') {
    try {
      const result = await pool.query(
        `SELECT * FROM pricing_config 
         WHERE service_type = $1 AND is_active = true 
         ORDER BY created_at DESC LIMIT 1`,
        [serviceType]
      );

      if (result.rows.length === 0) {
        // Configuration par défaut si aucune config trouvée
        return {
          base_fare: 500,
          cost_per_km: 300,
          cost_per_minute: 50,
          commission_rate: 20,
          max_distance_km: 50
        };
      }

      const config = result.rows[0];

      // Récupérer les plages horaires
      const timeSlotsResult = await pool.query(
        `SELECT * FROM pricing_time_slots 
         WHERE pricing_config_id = $1 
         ORDER BY start_time`,
        [config.id]
      );

      config.time_slots = timeSlotsResult.rows;

      return config;
    } catch (error) {
      console.error('Error fetching pricing config:', error);
      throw error;
    }
  }

  /**
   * Récupère le multiplicateur selon l'heure actuelle
   */
  getCurrentTimeMultiplier(timeSlots) {
    if (!timeSlots || timeSlots.length === 0) {
      return 1.0;
    }

    const now = new Date();
    const currentTime = now.toTimeString().slice(0, 5); // Format HH:MM

    for (const slot of timeSlots) {
      const start = slot.start_time;
      const end = slot.end_time;

      // Gérer le cas où la plage horaire traverse minuit (ex: 22:00 - 06:00)
      if (start > end) {
        // Plage qui traverse minuit
        if (currentTime >= start || currentTime < end) {
          return parseFloat(slot.multiplier);
        }
      } else {
        // Plage normale
        if (currentTime >= start && currentTime < end) {
          return parseFloat(slot.multiplier);
        }
      }
    }

    // Par défaut, multiplier = 1.0
    return 1.0;
  }

  /**
   * Calcule le prix d'une course
   * @param {number} distanceKm - Distance en kilomètres
   * @param {number} durationMin - Durée en minutes
   * @param {object} pricingConfig - Configuration de tarification
   * @returns {number} Prix calculé en FCFA (arrondi)
   */
  calculateFare(distanceKm, durationMin, pricingConfig) {
    const base = parseFloat(pricingConfig.base_fare) || 500;
    const costPerKm = parseFloat(pricingConfig.cost_per_km) || 300;
    const costPerMinute = parseFloat(pricingConfig.cost_per_minute) || 50;

    // Calcul du prix de base
    const distanceCost = distanceKm * costPerKm;
    const timeCost = durationMin * costPerMinute;
    const subtotal = base + distanceCost + timeCost;

    // Application du multiplicateur selon la plage horaire
    const multiplier = this.getCurrentTimeMultiplier(pricingConfig.time_slots);
    const fare = subtotal * multiplier;

    // Arrondi à l'entier le plus proche
    return Math.round(fare);
  }

  /**
   * Calcule le prix final avec tolérance (après le trajet)
   * Règle officielle: prix_final = min(prix_estime × 1.10, prix_calculé_reel)
   * Protection client + évite litiges & fraude driver
   * 
   * @param {number} estimatedFare - Prix estimé initial
   * @param {number} actualFare - Prix calculé avec données réelles
   * @param {number} tolerancePercent - Tolérance en % (défaut: 10%)
   * @returns {number} Prix final à facturer
   */
  calculateFinalFare(estimatedFare, actualFare, tolerancePercent = 10) {
    const maxFare = estimatedFare * (1 + tolerancePercent / 100);
    
    // Règle: prix_final = min(prix_estime × 1.10, prix_calculé_reel)
    const finalFare = Math.min(maxFare, actualFare);
    
    return Math.round(finalFare);
  }

  /**
   * Calcule la commission de la plateforme
   * @param {number} fare - Prix de la course
   * @param {number} commissionRate - Taux de commission en %
   * @returns {object} { commission, driverEarning }
   */
  calculateCommission(fare, commissionRate = 20) {
    const commission = Math.round((fare * commissionRate) / 100);
    const driverEarning = fare - commission;

    return {
      commission,
      driverEarning,
      total: fare
    };
  }

  /**
   * Récupère une config par ID (admin)
   */
  async getPricingConfigById(id) {
    const result = await pool.query(
      'SELECT * FROM pricing_config WHERE id = $1',
      [id]
    );
    if (result.rows.length === 0) return null;
    const config = result.rows[0];
    const slots = await pool.query(
      'SELECT * FROM pricing_time_slots WHERE pricing_config_id = $1 ORDER BY start_time',
      [id]
    );
    config.time_slots = slots.rows;
    return config;
  }

  /**
   * Récupère toutes les configs (actives et inactives) pour admin
   */
  async getAllPricingConfigs() {
    const result = await pool.query(
      'SELECT * FROM pricing_config ORDER BY service_type, created_at DESC'
    );
    const configs = result.rows;
    for (const c of configs) {
      const slots = await pool.query(
        'SELECT * FROM pricing_time_slots WHERE pricing_config_id = $1 ORDER BY start_time',
        [c.id]
      );
      c.time_slots = slots.rows;
    }
    return configs;
  }

  /**
   * Met à jour une config de tarification (admin)
   */
  async updatePricingConfig(id, data) {
    const fields = [];
    const values = [];
    let i = 1;
    const allowed = ['base_fare', 'cost_per_km', 'cost_per_minute', 'commission_rate', 'max_distance_km', 'is_active'];
    for (const key of allowed) {
      if (data[key] !== undefined) {
        fields.push(`${key} = $${i}`);
        values.push(data[key]);
        i++;
      }
    }
    if (fields.length === 0) throw new Error('No fields to update');
    fields.push('updated_at = NOW()');
    values.push(id);
    const result = await pool.query(
      `UPDATE pricing_config SET ${fields.join(', ')} WHERE id = $${i} RETURNING *`,
      values
    );
    if (result.rows.length === 0) throw new Error('Pricing config not found');
    return result.rows[0];
  }
}

module.exports = new PricingService();

