-- Script SQL complet pour créer la base de données de test
-- Usage: psql -U postgres -f setup-database-complete.sql

-- Créer la base de données (à exécuter en tant que superuser)
-- CREATE DATABASE bikeride_pro_test;

\c bikeride_pro_test;

-- ============================================
-- TABLES DÉPENDANTES (users, driver_profiles)
-- ============================================

-- Table users
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

-- Table driver_profiles (schéma complet)
CREATE TABLE IF NOT EXISTS driver_profiles (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Permis de conduire
    license_number VARCHAR(50) UNIQUE,
    license_expiry DATE,
    license_photo_url TEXT,
    
    -- Véhicule
    vehicle_type VARCHAR(50) DEFAULT 'motorcycle',
    vehicle_plate VARCHAR(20),
    vehicle_brand VARCHAR(100),
    vehicle_model VARCHAR(100),
    vehicle_year INTEGER,
    vehicle_color VARCHAR(50),
    vehicle_photo_url TEXT,
    
    -- Assurance
    insurance_number VARCHAR(100),
    insurance_expiry DATE,
    insurance_company VARCHAR(100),
    insurance_photo_url TEXT,
    
    -- Documents additionnels
    identity_card_number VARCHAR(50),
    identity_card_photo_url TEXT,
    criminal_record_url TEXT,
    
    -- Statut professionnel
    is_online BOOLEAN DEFAULT false,
    is_available BOOLEAN DEFAULT false,
    is_verified BOOLEAN DEFAULT false,
    verification_status VARCHAR(20) DEFAULT 'pending',
    verification_notes TEXT,
    
    -- Statistiques
    average_rating DECIMAL(3, 2) DEFAULT 0.00,
    total_ratings INTEGER DEFAULT 0,
    total_rides INTEGER DEFAULT 0,
    total_earnings DECIMAL(12, 2) DEFAULT 0.00,
    total_distance_km DECIMAL(10, 2) DEFAULT 0.00,
    
    -- Préférences
    preferred_radius_km INTEGER DEFAULT 10,
    max_distance_km INTEGER DEFAULT 50,
    
    -- Métadonnées
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    verified_at TIMESTAMP,
    last_active_at TIMESTAMP
);

-- Index pour driver_profiles
CREATE INDEX IF NOT EXISTS idx_driver_profiles_user_id ON driver_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_driver_profiles_is_online ON driver_profiles(is_online);
CREATE INDEX IF NOT EXISTS idx_driver_profiles_is_available ON driver_profiles(is_available);
CREATE INDEX IF NOT EXISTS idx_driver_profiles_verification_status ON driver_profiles(verification_status);
CREATE INDEX IF NOT EXISTS idx_driver_profiles_online_available ON driver_profiles(is_online, is_available) WHERE is_online = true AND is_available = true;

-- ============================================
-- TABLES MODULE RIDES
-- ============================================

-- Table: pricing_config
CREATE TABLE IF NOT EXISTS pricing_config (
    id SERIAL PRIMARY KEY,
    service_type VARCHAR(50) NOT NULL DEFAULT 'ride',
    base_fare DECIMAL(10, 2) NOT NULL DEFAULT 500.00,
    cost_per_km DECIMAL(10, 2) NOT NULL DEFAULT 300.00,
    cost_per_minute DECIMAL(10, 2) NOT NULL DEFAULT 50.00,
    commission_rate DECIMAL(5, 2) NOT NULL DEFAULT 20.00,
    max_distance_km DECIMAL(10, 2) DEFAULT 50.00,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Table: pricing_time_slots
CREATE TABLE IF NOT EXISTS pricing_time_slots (
    id SERIAL PRIMARY KEY,
    pricing_config_id INTEGER REFERENCES pricing_config(id) ON DELETE CASCADE,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    multiplier DECIMAL(5, 2) NOT NULL DEFAULT 1.0,
    description VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Table: rides
CREATE TABLE IF NOT EXISTS rides (
    id SERIAL PRIMARY KEY,
    ride_code VARCHAR(20) UNIQUE NOT NULL,
    client_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    driver_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    idempotency_key VARCHAR(255),
    pickup_lat DECIMAL(10, 8) NOT NULL,
    pickup_lng DECIMAL(11, 8) NOT NULL,
    pickup_address TEXT,
    dropoff_lat DECIMAL(10, 8) NOT NULL,
    dropoff_lng DECIMAL(11, 8) NOT NULL,
    dropoff_address TEXT,
    estimated_distance_km DECIMAL(10, 2),
    estimated_duration_min INTEGER,
    estimated_fare DECIMAL(10, 2) NOT NULL,
    actual_distance_km DECIMAL(10, 2),
    actual_duration_min INTEGER,
    fare_final DECIMAL(10, 2),
    status VARCHAR(50) NOT NULL DEFAULT 'REQUESTED',
    created_at TIMESTAMP DEFAULT NOW(),
    accepted_at TIMESTAMP,
    driver_arrived_at TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    paid_at TIMESTAMP,
    cancelled_at TIMESTAMP,
    cancellation_reason TEXT,
    payment_method VARCHAR(50),
    payment_status VARCHAR(50) DEFAULT 'UNPAID',
    transaction_id VARCHAR(100),
    client_rating INTEGER CHECK (client_rating >= 1 AND client_rating <= 5),
    client_review TEXT,
    driver_rating INTEGER CHECK (driver_rating >= 1 AND driver_rating <= 5),
    driver_review TEXT,
    notes TEXT,
    metadata JSONB
);

-- Table: ride_reviews
CREATE TABLE IF NOT EXISTS ride_reviews (
    id SERIAL PRIMARY KEY,
    ride_id INTEGER NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    reviewer_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    reviewed_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    role VARCHAR(20) NOT NULL,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Table: driver_locations
CREATE TABLE IF NOT EXISTS driver_locations (
    id SERIAL PRIMARY KEY,
    driver_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    lat DECIMAL(10, 8) NOT NULL,
    lng DECIMAL(11, 8) NOT NULL,
    heading DECIMAL(5, 2),
    speed_kmh DECIMAL(5, 2),
    accuracy_m DECIMAL(5, 2),
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(driver_id)
);

-- Table: ride_tracking
CREATE TABLE IF NOT EXISTS ride_tracking (
    id SERIAL PRIMARY KEY,
    ride_id INTEGER NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    lat DECIMAL(10, 8) NOT NULL,
    lng DECIMAL(11, 8) NOT NULL,
    timestamp TIMESTAMP DEFAULT NOW()
);

-- Table: ride_timeouts
CREATE TABLE IF NOT EXISTS ride_timeouts (
    id SERIAL PRIMARY KEY,
    ride_id INTEGER NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    timeout_type VARCHAR(50) NOT NULL,
    execute_at TIMESTAMP NOT NULL,
    processed BOOLEAN DEFAULT false,
    processed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(ride_id, timeout_type)
);

-- Table: idempotent_requests
CREATE TABLE IF NOT EXISTS idempotent_requests (
    id SERIAL PRIMARY KEY,
    idempotency_key VARCHAR(255) UNIQUE NOT NULL,
    user_id INTEGER REFERENCES users(id),
    endpoint VARCHAR(255) NOT NULL,
    request_hash TEXT,
    response_data JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    expires_at TIMESTAMP NOT NULL
);

-- ============================================
-- INDEX
-- ============================================

CREATE INDEX IF NOT EXISTS idx_rides_client_id ON rides(client_id);
CREATE INDEX IF NOT EXISTS idx_rides_driver_id ON rides(driver_id);
CREATE INDEX IF NOT EXISTS idx_rides_status ON rides(status);
CREATE INDEX IF NOT EXISTS idx_rides_created_at ON rides(created_at);
CREATE INDEX IF NOT EXISTS idx_rides_ride_code ON rides(ride_code);
CREATE INDEX IF NOT EXISTS idx_rides_status_created ON rides(status, created_at);
CREATE INDEX IF NOT EXISTS idx_rides_payment_status ON rides(payment_status);
CREATE INDEX IF NOT EXISTS idx_ride_reviews_ride_id ON ride_reviews(ride_id);
CREATE INDEX IF NOT EXISTS idx_ride_reviews_reviewed_id ON ride_reviews(reviewed_id);
CREATE INDEX IF NOT EXISTS idx_driver_locations_updated_at ON driver_locations(updated_at);
CREATE INDEX IF NOT EXISTS idx_driver_locations_updated_desc ON driver_locations(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_ride_tracking_ride_id ON ride_tracking(ride_id);
CREATE INDEX IF NOT EXISTS idx_ride_tracking_timestamp ON ride_tracking(timestamp);
CREATE INDEX IF NOT EXISTS idx_ride_tracking_ride_created ON ride_tracking(ride_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_ride_timeouts_execute_at ON ride_timeouts(execute_at) WHERE processed = false;
CREATE INDEX IF NOT EXISTS idx_ride_timeouts_ride_id ON ride_timeouts(ride_id);
CREATE INDEX IF NOT EXISTS idx_idempotent_requests_key ON idempotent_requests(idempotency_key);
CREATE INDEX IF NOT EXISTS idx_idempotent_requests_expires ON idempotent_requests(expires_at);

-- Index géospatiaux
CREATE INDEX IF NOT EXISTS idx_rides_pickup_location ON rides USING GIST (point(pickup_lng, pickup_lat));
CREATE INDEX IF NOT EXISTS idx_driver_locations_location ON driver_locations USING GIST (point(lng, lat));

-- ============================================
-- TRIGGERS ET FONCTIONS
-- ============================================

-- Fonction pour générer un code de course unique
CREATE OR REPLACE FUNCTION generate_ride_code() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.ride_code IS NULL THEN
        NEW.ride_code := 'RIDE-' || TO_CHAR(NOW(), 'YYYY') || '-' || 
                        LPAD(NEXTVAL('rides_id_seq')::TEXT, 6, '0');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_generate_ride_code
    BEFORE INSERT ON rides
    FOR EACH ROW
    EXECUTE FUNCTION generate_ride_code();

-- Fonction pour mettre à jour updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_pricing_config_updated_at
    BEFORE UPDATE ON pricing_config
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Fonction pour nettoyer les clés d'idempotence expirées
CREATE OR REPLACE FUNCTION cleanup_expired_idempotency_keys()
RETURNS void AS $$
BEGIN
    DELETE FROM idempotent_requests WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- DONNÉES DE TEST
-- ============================================

-- Configuration de prix par défaut
INSERT INTO pricing_config (service_type, base_fare, cost_per_km, cost_per_minute, commission_rate, max_distance_km, is_active)
VALUES ('ride', 500, 300, 50, 20, 50, true)
ON CONFLICT DO NOTHING;

-- Plages horaires par défaut
DO \$\$
DECLARE
    config_id INTEGER;
BEGIN
    SELECT id INTO config_id FROM pricing_config WHERE service_type = 'ride' AND is_active = true LIMIT 1;
    
    IF config_id IS NOT NULL THEN
        INSERT INTO pricing_time_slots (pricing_config_id, start_time, end_time, multiplier, description)
        VALUES 
            (config_id, '06:00', '22:00', 1.0, 'Jour'),
            (config_id, '22:00', '06:00', 1.3, 'Nuit')
        ON CONFLICT DO NOTHING;
    END IF;
END \$\$;

-- ============================================
-- TABLE AUDIT (optionnel mais utilisé par rides.service.js)
-- ============================================

CREATE TABLE IF NOT EXISTS audit_logs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50),
    entity_id INTEGER,
    details JSONB,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at);

-- ============================================
-- TABLE WALLETS (pour tests de paiement)
-- ============================================

CREATE TABLE IF NOT EXISTS wallets (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    balance DECIMAL(10, 2) DEFAULT 0.00,
    currency VARCHAR(3) DEFAULT 'XOF',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(20) NOT NULL, -- 'credit', 'debit', 'refund', 'commission', 'withdrawal', 'deposit'
    amount DECIMAL(10, 2) NOT NULL,
    balance_before DECIMAL(10, 2) NOT NULL,
    balance_after DECIMAL(10, 2) NOT NULL,
    reference_type VARCHAR(50), -- 'ride', 'delivery', 'carpool', 'manual', 'mobile_money'
    reference_id INTEGER,
    description TEXT,
    metadata JSONB,
    status VARCHAR(20) DEFAULT 'completed', -- 'pending', 'completed', 'failed', 'cancelled'
    processed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_reference ON transactions(reference_type, reference_id);

-- Table payment_intents (PayTech / Mobile Money)
CREATE TABLE IF NOT EXISTS payment_intents (
    id SERIAL PRIMARY KEY,
    ref_command VARCHAR(100) UNIQUE NOT NULL,
    token VARCHAR(255),
    reference_type VARCHAR(50) NOT NULL,
    reference_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    amount DECIMAL(12, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'XOF',
    status VARCHAR(50) DEFAULT 'pending',
    provider VARCHAR(50) DEFAULT 'paytech',
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    completed_at TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_payment_intents_ref_command ON payment_intents(ref_command);
CREATE INDEX IF NOT EXISTS idx_payment_intents_reference ON payment_intents(reference_type, reference_id);

-- Vérification
SELECT 'Base de données de test configurée avec succès!' as status;
SELECT COUNT(*) as tables_created FROM information_schema.tables 
WHERE table_schema = 'public' AND table_name IN ('users', 'driver_profiles', 'rides', 'pricing_config', 'audit_logs', 'wallets');

