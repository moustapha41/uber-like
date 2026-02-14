-- ============================================
-- SCHÉMA BASE DE DONNÉES - MODULE DELIVERIES
-- ============================================

-- Table: deliveries (Livraisons)
-- ⚠️ FOREIGN KEYS: 
-- client_id → users(id) ON DELETE RESTRICT (celui qui commande)
-- driver_id → users(id) ON DELETE SET NULL (libéré lors d'annulation)
-- sender_id → users(id) ON DELETE SET NULL (expéditeur, peut être différent du client)
-- recipient_id → users(id) ON DELETE SET NULL (destinataire, peut être différent du client)
CREATE TABLE IF NOT EXISTS deliveries (
    id SERIAL PRIMARY KEY,
    delivery_code VARCHAR(20) UNIQUE NOT NULL, -- Code unique (ex: DELIV-2024-001)
    
    -- Relations utilisateurs
    client_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT, -- Celui qui commande
    driver_id INTEGER REFERENCES users(id) ON DELETE SET NULL, -- Driver assigné
    sender_id INTEGER REFERENCES users(id) ON DELETE SET NULL, -- Expéditeur (peut être différent du client)
    recipient_id INTEGER REFERENCES users(id) ON DELETE SET NULL, -- Destinataire
    
    idempotency_key VARCHAR(255), -- Pour protection contre doubles requêtes
    
    -- Localisations
    pickup_lat DECIMAL(10, 8) NOT NULL, -- Point de collecte (marchandise)
    pickup_lng DECIMAL(11, 8) NOT NULL,
    pickup_address TEXT,
    dropoff_lat DECIMAL(10, 8) NOT NULL, -- Point de livraison (destinataire)
    dropoff_lng DECIMAL(11, 8) NOT NULL,
    dropoff_address TEXT,
    
    -- Informations colis
    package_type VARCHAR(50) DEFAULT 'standard', -- 'standard', 'fragile', 'food', 'document', 'electronics', etc.
    package_weight_kg DECIMAL(10, 2), -- Poids en kg
    package_dimensions JSONB, -- {length, width, height} en cm
    package_value DECIMAL(10, 2), -- Valeur déclarée en FCFA
    package_description TEXT, -- Description du colis
    requires_signature BOOLEAN DEFAULT false, -- Signature requise à la livraison
    insurance_required BOOLEAN DEFAULT false, -- Assurance requise
    
    -- Informations destinataire (si différent du client)
    recipient_name VARCHAR(255),
    recipient_phone VARCHAR(20),
    recipient_email VARCHAR(255),
    delivery_instructions TEXT, -- Instructions spéciales (ex: "Laisser devant la porte")
    
    -- Estimations initiales
    estimated_distance_km DECIMAL(10, 2),
    estimated_duration_min INTEGER,
    estimated_fare DECIMAL(10, 2) NOT NULL,
    
    -- Données réelles (remplies après la livraison)
    actual_distance_km DECIMAL(10, 2),
    actual_duration_min INTEGER,
    fare_final DECIMAL(10, 2),
    
    -- Statut et timestamps
    status VARCHAR(50) NOT NULL DEFAULT 'REQUESTED',
    -- Statuts possibles: 
    -- REQUESTED, ASSIGNED, PICKED_UP, IN_TRANSIT, DELIVERED, 
    -- CANCELLED_BY_CLIENT, CANCELLED_BY_DRIVER, CANCELLED_BY_SYSTEM, FAILED
    
    created_at TIMESTAMP DEFAULT NOW(),
    assigned_at TIMESTAMP, -- Quand le driver accepte
    picked_up_at TIMESTAMP, -- Quand le driver récupère le colis
    in_transit_at TIMESTAMP, -- Quand le driver démarre vers le destinataire
    delivered_at TIMESTAMP, -- Quand le colis est livré
    cancelled_at TIMESTAMP,
    cancellation_reason TEXT,
    
    -- Informations complémentaires
    payment_method VARCHAR(50), -- 'wallet' ou 'mobile_money' ou 'cash_on_delivery'
    payment_status VARCHAR(50) DEFAULT 'UNPAID', -- 'UNPAID', 'PAYMENT_PENDING', 'PAID', 'PAYMENT_FAILED', 'REFUNDED'
    transaction_id VARCHAR(100),
    payment_collected_at TIMESTAMP, -- Si paiement à la livraison
    
    -- Notes et avis
    client_rating INTEGER CHECK (client_rating >= 1 AND client_rating <= 5),
    client_review TEXT,
    driver_rating INTEGER CHECK (driver_rating >= 1 AND driver_rating <= 5),
    driver_review TEXT,
    recipient_rating INTEGER CHECK (recipient_rating >= 1 AND recipient_rating <= 5),
    recipient_review TEXT,
    
    -- Preuve de livraison
    delivery_proof JSONB, -- {photo_url, signature_url, recipient_name, delivered_at}
    
    -- Métadonnées
    notes TEXT, -- Notes internes
    metadata JSONB -- Données supplémentaires (ex: route polyline, waypoints)
);

-- Index pour optimiser les requêtes
CREATE INDEX IF NOT EXISTS idx_deliveries_client_id ON deliveries(client_id);
CREATE INDEX IF NOT EXISTS idx_deliveries_driver_id ON deliveries(driver_id);
CREATE INDEX IF NOT EXISTS idx_deliveries_sender_id ON deliveries(sender_id);
CREATE INDEX IF NOT EXISTS idx_deliveries_recipient_id ON deliveries(recipient_id);
CREATE INDEX IF NOT EXISTS idx_deliveries_status ON deliveries(status);
CREATE INDEX IF NOT EXISTS idx_deliveries_created_at ON deliveries(created_at);
CREATE INDEX IF NOT EXISTS idx_deliveries_delivery_code ON deliveries(delivery_code);
CREATE INDEX IF NOT EXISTS idx_deliveries_status_created ON deliveries(status, created_at);
CREATE INDEX IF NOT EXISTS idx_deliveries_payment_status ON deliveries(payment_status);

-- Table: delivery_timeouts (Timeouts pour les livraisons)
CREATE TABLE IF NOT EXISTS delivery_timeouts (
    id SERIAL PRIMARY KEY,
    delivery_id INTEGER NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
    timeout_type VARCHAR(50) NOT NULL, -- 'NO_DRIVER', 'PICKUP_TIMEOUT', 'DELIVERY_TIMEOUT'
    execute_at TIMESTAMP NOT NULL,
    processed BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_delivery_timeouts_delivery_id ON delivery_timeouts(delivery_id);
CREATE INDEX IF NOT EXISTS idx_delivery_timeouts_execute_at ON delivery_timeouts(execute_at);
CREATE INDEX IF NOT EXISTS idx_delivery_timeouts_processed ON delivery_timeouts(processed);

-- Table: delivery_tracking (Historique GPS d'une livraison)
CREATE TABLE IF NOT EXISTS delivery_tracking (
    id SERIAL PRIMARY KEY,
    delivery_id INTEGER NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
    lat DECIMAL(10, 8) NOT NULL,
    lng DECIMAL(11, 8) NOT NULL,
    heading DECIMAL(5, 2), -- Direction en degrés (0-360)
    speed DECIMAL(5, 2), -- Vitesse en km/h
    timestamp TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_delivery_tracking_delivery_id ON delivery_tracking(delivery_id);
CREATE INDEX IF NOT EXISTS idx_delivery_tracking_timestamp ON delivery_tracking(timestamp);
CREATE INDEX IF NOT EXISTS idx_delivery_tracking_delivery_timestamp ON delivery_tracking(delivery_id, timestamp);

