const pool = require('../../config/database');

/**
 * Audit Service
 * Handles logging and tracking of all system activities
 */

class AuditService {
  /**
   * Log an action/event
   */
  async logAction(userId, action, entityType, entityId, details = {}) {
    try {
      const result = await pool.query(
        `INSERT INTO audit_logs (user_id, action, entity_type, entity_id, details, created_at)
         VALUES ($1, $2, $3, $4, $5, NOW())
         RETURNING *`,
        [userId, action, entityType, entityId, JSON.stringify(details)]
      );
      return result.rows[0];
    } catch (error) {
      console.error('Error logging action:', error);
      // Don't throw - audit logging should not break the main flow
      return null;
    }
  }

  /**
   * Get audit logs for a specific entity
   */
  async getEntityLogs(entityType, entityId, limit = 50) {
    try {
      const result = await pool.query(
        `SELECT * FROM audit_logs
         WHERE entity_type = $1 AND entity_id = $2
         ORDER BY created_at DESC
         LIMIT $3`,
        [entityType, entityId, limit]
      );
      return result.rows;
    } catch (error) {
      console.error('Error fetching audit logs:', error);
      return [];
    }
  }

  /**
   * Get audit logs for a user
   */
  async getUserLogs(userId, limit = 50) {
    try {
      const result = await pool.query(
        `SELECT * FROM audit_logs
         WHERE user_id = $1
         ORDER BY created_at DESC
         LIMIT $2`,
        [userId, limit]
      );
      return result.rows;
    } catch (error) {
      console.error('Error fetching user audit logs:', error);
      return [];
    }
  }

  /**
   * Get audit logs with filters (admin)
   * @param {Object} filters - { entity_type, entity_id, user_id, action, date_from, date_to, limit, offset }
   * @returns {Object} { logs, total }
   */
  async getLogs(filters = {}, limit = 100, offset = 0) {
    try {
      let where = ' WHERE 1=1 ';
      const params = [];
      let paramIndex = 1;

      if (filters.entity_type) {
        where += ` AND entity_type = $${paramIndex}`;
        params.push(filters.entity_type);
        paramIndex++;
      }
      if (filters.entity_id) {
        where += ` AND entity_id = $${paramIndex}`;
        params.push(filters.entity_id);
        paramIndex++;
      }
      if (filters.user_id) {
        where += ` AND user_id = $${paramIndex}`;
        params.push(filters.user_id);
        paramIndex++;
      }
      if (filters.action) {
        where += ` AND action = $${paramIndex}`;
        params.push(filters.action);
        paramIndex++;
      }
      if (filters.date_from) {
        where += ` AND created_at >= $${paramIndex}`;
        params.push(filters.date_from);
        paramIndex++;
      }
      if (filters.date_to) {
        where += ` AND created_at <= $${paramIndex}`;
        params.push(filters.date_to);
        paramIndex++;
      }

      const countResult = await pool.query(
        `SELECT COUNT(*) as total FROM audit_logs ${where}`,
        params
      );
      const total = parseInt(countResult.rows[0].total, 10);

      const result = await pool.query(
        `SELECT * FROM audit_logs ${where}
         ORDER BY created_at DESC
         LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`,
        [...params, limit, offset]
      );

      return { logs: result.rows, total };
    } catch (error) {
      console.error('Error fetching audit logs:', error);
      return { logs: [], total: 0 };
    }
  }
}

module.exports = new AuditService();

