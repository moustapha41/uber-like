-- Script SQL pour créer la base de données de test et les tables nécessaires
-- Usage: psql -U postgres -f tests/create-test-db.sql

-- Créer la base de données de test (à exécuter manuellement avant)
-- CREATE DATABASE bikeride_pro_test;

\c bikeride_pro_test;

-- Table users (dépendance requise)
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    role VARCHAR(20) NOT NULL DEFAULT 'client',
    status VARCHAR(20) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Table driver_profiles (dépendance requise)
CREATE TABLE IF NOT EXISTS driver_profiles (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    license_number VARCHAR(50) UNIQUE,
    license_expiry DATE,
    vehicle_type VARCHAR(50) DEFAULT 'motorcycle',
    vehicle_plate VARCHAR(20),
    insurance_number VARCHAR(100),
    insurance_expiry DATE,
    is_online BOOLEAN DEFAULT false,
    is_available BOOLEAN DEFAULT false,
    average_rating DECIMAL(3, 2) DEFAULT 0.00,
    total_ratings INTEGER DEFAULT 0,
    total_rides INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Exécuter le script du module rides pour créer les tables rides
\i src/modules/rides/models.sql

-- Insérer des données de test de base (optionnel)
-- INSERT INTO pricing_config (service_type, base_fare, cost_per_km, cost_per_minute, is_active)
-- VALUES ('ride', 500, 300, 50, true);

