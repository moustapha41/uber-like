const pool = require('../../config/database');
const usersService = require('../users/users.service');
const pricingService = require('../rides/pricing.service');
const auditService = require('../audit/service');

/**
 * Admin Service
 * Dashboard, gestion utilisateurs/drivers, tarifs, audit
 */
class AdminService {
  /**
   * Statistiques dashboard (utilisateurs, courses, livraisons, revenus)
   */
  async getDashboardStats() {
    try {
      const [usersByRole, ridesStats, deliveriesResult, pendingDrivers, recentRides] = await Promise.all([
        pool.query(
          `SELECT role, COUNT(*) as count FROM users WHERE deleted_at IS NULL GROUP BY role`
        ),
        pool.query(
          `SELECT COUNT(*) as total_rides, COALESCE(SUM(fare_final), 0)::numeric as total_revenue
           FROM rides WHERE status IN ('COMPLETED', 'PAID', 'CLOSED')`
        ),
        pool.query(
          `SELECT COUNT(*) as total_deliveries, COALESCE(SUM(fare_final), 0)::numeric as total_revenue
           FROM deliveries WHERE status = 'COMPLETED'`
        ).catch(() => ({ rows: [{ total_deliveries: 0, total_revenue: 0 }] })),
        pool.query(
          `SELECT COUNT(*) as count FROM driver_profiles WHERE verification_status = 'pending'`
        ).catch(() => ({ rows: [{ count: 0 }] })),
        pool.query(
          `SELECT id, ride_code, status, fare_final, created_at FROM rides ORDER BY created_at DESC LIMIT 5`
        ).catch(() => ({ rows: [] }))
      ]);

      const roles = { client: 0, driver: 0, admin: 0 };
      usersByRole.rows.forEach(r => { roles[r.role] = parseInt(r.count, 10); });
      const dr = deliveriesResult.rows[0] || { total_deliveries: 0, total_revenue: 0 };
      const pr = pendingDrivers.rows[0] || { count: 0 };

      return {
        users: {
          total: roles.client + roles.driver + roles.admin,
          clients: roles.client,
          drivers: roles.driver,
          admins: roles.admin
        },
        rides: {
          total: parseInt(ridesStats.rows[0].total_rides, 10),
          revenue: parseFloat(ridesStats.rows[0].total_revenue) || 0
        },
        deliveries: {
          total: parseInt(dr.total_deliveries, 10),
          revenue: parseFloat(dr.total_revenue) || 0
        },
        pending_drivers_verification: parseInt(pr.count, 10),
        recent_rides: recentRides.rows
      };
    } catch (error) {
      console.error('Error getDashboardStats:', error);
      throw error;
    }
  }

  /**
   * Liste des utilisateurs (délègue à usersService)
   */
  async listUsers(filters, limit, offset) {
    return usersService.listUsers(filters, limit, offset);
  }

  /**
   * Mise à jour statut utilisateur (délègue à usersService)
   */
  async updateUserStatus(userId, status) {
    return usersService.updateUserStatus(userId, status);
  }

  /**
   * Liste des drivers (délègue à usersService)
   */
  async listDrivers(filters, limit, offset) {
    return usersService.listDrivers(filters, limit, offset);
  }

  /**
   * Mise à jour vérification driver (délègue à usersService)
   */
  async updateDriverVerification(driverId, verificationStatus, verificationNotes) {
    return usersService.updateDriverVerification(driverId, verificationStatus, verificationNotes);
  }

  /**
   * Toutes les configs tarifaires (délègue à pricingService)
   */
  async getAllPricingConfigs() {
    return pricingService.getAllPricingConfigs();
  }

  /**
   * Une config par ID (délègue à pricingService)
   */
  async getPricingConfigById(id) {
    return pricingService.getPricingConfigById(id);
  }

  /**
   * Mise à jour config tarifaire (délègue à pricingService)
   */
  async updatePricingConfig(id, data) {
    return pricingService.updatePricingConfig(id, data);
  }

  /**
   * Logs d'audit avec filtres (délègue à auditService)
   */
  async getAuditLogs(filters, limit, offset) {
    return auditService.getLogs(filters, limit, offset);
  }
}

module.exports = new AdminService();
