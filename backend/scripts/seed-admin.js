#!/usr/bin/env node
/**
 * Crée un utilisateur admin en base (si pas déjà existant).
 * Usage: node scripts/seed-admin.js
 * Variables optionnelles: ADMIN_EMAIL, ADMIN_PASSWORD, ADMIN_PHONE, ADMIN_FIRST_NAME, ADMIN_LAST_NAME
 */
const path = process.env.NODE_ENV === 'production' ? '.env.production' : '.env';
require('dotenv').config({ path });
const bcrypt = require('bcryptjs');
const pool = require('../src/config/database');

const ADMIN_EMAIL = process.env.ADMIN_EMAIL || 'admin@bikeride.pro';
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || 'Admin123!';
const ADMIN_PHONE = process.env.ADMIN_PHONE || '+221770000000';
const ADMIN_FIRST_NAME = process.env.ADMIN_FIRST_NAME || 'Admin';
const ADMIN_LAST_NAME = process.env.ADMIN_LAST_NAME || 'System';

async function seedAdmin() {
  let client;
  try {
    client = await pool.connect();

    const existing = await client.query(
      'SELECT id, role FROM users WHERE email = $1',
      [ADMIN_EMAIL]
    );

    if (existing.rows.length > 0) {
      const user = existing.rows[0];
      if (user.role === 'admin') {
        console.log('✅ Compte admin déjà existant:', ADMIN_EMAIL);
        return;
      }
      await client.query(
        "UPDATE users SET role = 'admin', status = 'active', updated_at = NOW() WHERE id = $1",
        [user.id]
      );
      console.log('✅ Utilisateur existant promu admin:', ADMIN_EMAIL);
      return;
    }

    const password_hash = await bcrypt.hash(ADMIN_PASSWORD, 10);
    await client.query(
      `INSERT INTO users (email, phone, password_hash, first_name, last_name, role, status)
       VALUES ($1, $2, $3, $4, $5, 'admin', 'active')`,
      [ADMIN_EMAIL, ADMIN_PHONE, password_hash, ADMIN_FIRST_NAME, ADMIN_LAST_NAME]
    );

    console.log('✅ Compte admin créé:', ADMIN_EMAIL);
    console.log('   Connexion: POST /api/v1/auth/login avec email + password');
  } catch (err) {
    console.error('❌ Erreur seed admin:', err.message);
    process.exit(1);
  } finally {
    if (client) client.release();
    await pool.end();
  }
}

seedAdmin();
