-- ============================================
-- SCHÉMA BASE DE DONNÉES - MODULE RIDES
-- ============================================

-- Table: pricing_config (Configuration des tarifs par l'admin)
CREATE TABLE IF NOT EXISTS pricing_config (
    id SERIAL PRIMARY KEY,
    service_type VARCHAR(50) NOT NULL DEFAULT 'ride', -- 'ride' ou 'delivery'
    base_fare DECIMAL(10, 2) NOT NULL DEFAULT 500.00, -- Frais de base en FCFA
    cost_per_km DECIMAL(10, 2) NOT NULL DEFAULT 300.00, -- Prix par km
    cost_per_minute DECIMAL(10, 2) NOT NULL DEFAULT 50.00, -- Prix par minute
    commission_rate DECIMAL(5, 2) NOT NULL DEFAULT 20.00, -- Commission plateforme (%)
    max_distance_km DECIMAL(10, 2) DEFAULT 50.00, -- Distance maximale autorisée
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Table: pricing_time_slots (Plages horaires avec multiplicateurs)
CREATE TABLE IF NOT EXISTS pricing_time_slots (
    id SERIAL PRIMARY KEY,
    pricing_config_id INTEGER REFERENCES pricing_config(id) ON DELETE CASCADE,
    start_time TIME NOT NULL, -- Format HH:MM
    end_time TIME NOT NULL,
    multiplier DECIMAL(5, 2) NOT NULL DEFAULT 1.0, -- Multiplicateur de prix
    description VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Table: rides (Courses)
-- ⚠️ FOREIGN KEYS: Déjà présentes mais documentées ici pour clarté
-- client_id → users(id) ON DELETE RESTRICT
-- driver_id → users(id) ON DELETE SET NULL (libéré lors d'annulation)
CREATE TABLE IF NOT EXISTS rides (
    id SERIAL PRIMARY KEY,
    ride_code VARCHAR(20) UNIQUE NOT NULL, -- Code unique (ex: RIDE-2024-001)
    client_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    driver_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    idempotency_key VARCHAR(255), -- Pour protection contre doubles requêtes
    
    -- Localisations (format JSONB ou coordonnées séparées)
    pickup_lat DECIMAL(10, 8) NOT NULL,
    pickup_lng DECIMAL(11, 8) NOT NULL,
    pickup_address TEXT,
    dropoff_lat DECIMAL(10, 8) NOT NULL,
    dropoff_lng DECIMAL(11, 8) NOT NULL,
    dropoff_address TEXT,
    
    -- Estimations initiales
    estimated_distance_km DECIMAL(10, 2),
    estimated_duration_min INTEGER,
    estimated_fare DECIMAL(10, 2) NOT NULL,
    
    -- Données réelles (remplies après le trajet)
    actual_distance_km DECIMAL(10, 2),
    actual_duration_min INTEGER,
    fare_final DECIMAL(10, 2),
    
    -- Statut et timestamps
    status VARCHAR(50) NOT NULL DEFAULT 'REQUESTED',
    -- Statuts possibles: REQUESTED, DRIVER_ASSIGNED, DRIVER_ARRIVED, IN_PROGRESS, 
    -- COMPLETED, PAID, CLOSED, CANCELLED_BY_CLIENT, CANCELLED_BY_DRIVER, CANCELLED_BY_SYSTEM
    
    created_at TIMESTAMP DEFAULT NOW(),
    accepted_at TIMESTAMP,
    driver_arrived_at TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    paid_at TIMESTAMP,
    cancelled_at TIMESTAMP,
    cancellation_reason TEXT,
    
    -- Informations complémentaires
    payment_method VARCHAR(50), -- 'wallet' ou 'mobile_money'
    payment_status VARCHAR(50) DEFAULT 'UNPAID', -- 'UNPAID', 'PAYMENT_PENDING', 'PAID', 'PAYMENT_FAILED', 'REFUNDED'
    transaction_id VARCHAR(100),
    
    -- Notes et avis
    client_rating INTEGER CHECK (client_rating >= 1 AND client_rating <= 5),
    client_review TEXT,
    driver_rating INTEGER CHECK (driver_rating >= 1 AND driver_rating <= 5),
    driver_review TEXT,
    
    -- Métadonnées
    notes TEXT, -- Notes internes
    metadata JSONB -- Données supplémentaires (ex: route polyline, waypoints)
);

-- Index pour optimiser les requêtes
CREATE INDEX IF NOT EXISTS idx_rides_client_id ON rides(client_id);
CREATE INDEX IF NOT EXISTS idx_rides_driver_id ON rides(driver_id);
CREATE INDEX IF NOT EXISTS idx_rides_status ON rides(status);
CREATE INDEX IF NOT EXISTS idx_rides_created_at ON rides(created_at);
CREATE INDEX IF NOT EXISTS idx_rides_ride_code ON rides(ride_code);

-- Index critiques manquants (performance)
CREATE INDEX IF NOT EXISTS idx_rides_status_created ON rides(status, created_at);
CREATE INDEX IF NOT EXISTS idx_rides_payment_status ON rides(payment_status);
CREATE INDEX IF NOT EXISTS idx_driver_locations_updated_desc ON driver_locations(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_ride_tracking_ride_created ON ride_tracking(ride_id, timestamp);

-- Index géospatial pour recherche de drivers proches
CREATE INDEX IF NOT EXISTS idx_rides_pickup_location ON rides USING GIST (
    point(pickup_lng, pickup_lat)
);

-- Table: ride_reviews (Avis détaillés sur les courses)
CREATE TABLE IF NOT EXISTS ride_reviews (
    id SERIAL PRIMARY KEY,
    ride_id INTEGER NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    reviewer_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    reviewed_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    role VARCHAR(20) NOT NULL, -- 'client' ou 'driver'
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ride_reviews_ride_id ON ride_reviews(ride_id);
CREATE INDEX IF NOT EXISTS idx_ride_reviews_reviewed_id ON ride_reviews(reviewed_id);

-- Table: driver_locations (Positions GPS des drivers en temps réel)
CREATE TABLE IF NOT EXISTS driver_locations (
    id SERIAL PRIMARY KEY,
    driver_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    lat DECIMAL(10, 8) NOT NULL,
    lng DECIMAL(11, 8) NOT NULL,
    heading DECIMAL(5, 2), -- Direction en degrés (0-360)
    speed_kmh DECIMAL(5, 2), -- Vitesse en km/h
    accuracy_m DECIMAL(5, 2), -- Précision GPS en mètres
    updated_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(driver_id)
);

CREATE INDEX IF NOT EXISTS idx_driver_locations_updated_at ON driver_locations(updated_at);
CREATE INDEX IF NOT EXISTS idx_driver_locations_location ON driver_locations USING GIST (
    point(lng, lat)
);

-- Table: ride_tracking (Historique GPS d'une course en cours)
CREATE TABLE IF NOT EXISTS ride_tracking (
    id SERIAL PRIMARY KEY,
    ride_id INTEGER NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    lat DECIMAL(10, 8) NOT NULL,
    lng DECIMAL(11, 8) NOT NULL,
    timestamp TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ride_tracking_ride_id ON ride_tracking(ride_id);
CREATE INDEX IF NOT EXISTS idx_ride_tracking_timestamp ON ride_tracking(timestamp);

-- Table: ride_timeouts (Timeouts centralisés pour gestion robuste)
CREATE TABLE IF NOT EXISTS ride_timeouts (
    id SERIAL PRIMARY KEY,
    ride_id INTEGER NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
    timeout_type VARCHAR(50) NOT NULL, -- 'NO_DRIVER', 'CLIENT_NO_SHOW', 'PAYMENT_TIMEOUT'
    execute_at TIMESTAMP NOT NULL,
    processed BOOLEAN DEFAULT false,
    processed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(ride_id, timeout_type)
);

CREATE INDEX IF NOT EXISTS idx_ride_timeouts_execute_at ON ride_timeouts(execute_at) WHERE processed = false;
CREATE INDEX IF NOT EXISTS idx_ride_timeouts_ride_id ON ride_timeouts(ride_id);

-- Table: idempotent_requests (Protection contre doubles requêtes)
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

CREATE INDEX IF NOT EXISTS idx_idempotent_requests_key ON idempotent_requests(idempotency_key);
CREATE INDEX IF NOT EXISTS idx_idempotent_requests_expires ON idempotent_requests(expires_at);

-- Nettoyer les clés expirées (à exécuter périodiquement)
CREATE OR REPLACE FUNCTION cleanup_expired_idempotency_keys()
RETURNS void AS $$
BEGIN
    DELETE FROM idempotent_requests WHERE expires_at < NOW();
END;
$$ LANGUAGE plpgsql;

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

-- Trigger pour générer automatiquement le code de course
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

-- Trigger pour pricing_config
CREATE TRIGGER trigger_update_pricing_config_updated_at
    BEFORE UPDATE ON pricing_config
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

