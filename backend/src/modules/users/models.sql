-- ============================================
-- SCHÉMA BASE DE DONNÉES - MODULE USERS
-- ============================================
-- Ce module gère les utilisateurs (clients, drivers, admins) et les profils drivers
-- ⚠️ IMPORTANT : Ces tables doivent être créées AVANT le module rides

-- ============================================
-- TABLE: users
-- ============================================
-- Table principale des utilisateurs (clients, drivers, admins)

CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    role VARCHAR(20) NOT NULL DEFAULT 'client', -- 'client', 'driver', 'admin'
    status VARCHAR(20) DEFAULT 'active', -- 'active', 'inactive', 'suspended', 'pending_verification'
    avatar_url TEXT, -- URL de l'image de profil
    date_of_birth DATE,
    gender VARCHAR(10), -- 'male', 'female', 'other'
    language VARCHAR(10) DEFAULT 'fr', -- 'fr', 'en', 'wo'
    timezone VARCHAR(50) DEFAULT 'Africa/Dakar',
    
    -- Adresse
    address TEXT,
    city VARCHAR(100),
    country VARCHAR(100) DEFAULT 'Senegal',
    
    -- Vérification
    email_verified BOOLEAN DEFAULT false,
    phone_verified BOOLEAN DEFAULT false,
    verification_token VARCHAR(255),
    verification_token_expires_at TIMESTAMP,
    
    -- Sécurité
    last_login_at TIMESTAMP,
    failed_login_attempts INTEGER DEFAULT 0,
    locked_until TIMESTAMP, -- Verrouillage temporaire après trop de tentatives
    
    -- Métadonnées
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    deleted_at TIMESTAMP -- Soft delete
);

-- ============================================
-- TABLE: driver_profiles
-- ============================================
-- Profils des drivers professionnels
-- Un driver_profile est lié à un user avec role='driver'

CREATE TABLE IF NOT EXISTS driver_profiles (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Informations professionnelles
    license_number VARCHAR(50) UNIQUE,
    license_expiry DATE,
    license_photo_url TEXT, -- URL de la photo du permis
    
    -- Véhicule
    vehicle_type VARCHAR(50) DEFAULT 'motorcycle', -- 'motorcycle', 'scooter', 'bike'
    vehicle_plate VARCHAR(20),
    vehicle_brand VARCHAR(100), -- Ex: Yamaha, Honda
    vehicle_model VARCHAR(100), -- Ex: MT-07, CBR 600
    vehicle_year INTEGER,
    vehicle_color VARCHAR(50),
    vehicle_photo_url TEXT, -- URL de la photo du véhicule
    
    -- Assurance
    insurance_number VARCHAR(100),
    insurance_expiry DATE,
    insurance_company VARCHAR(100),
    insurance_photo_url TEXT, -- URL de la photo de l'assurance
    
    -- Documents additionnels
    identity_card_number VARCHAR(50),
    identity_card_photo_url TEXT,
    criminal_record_url TEXT, -- Casier judiciaire
    
    -- Statut professionnel
    is_online BOOLEAN DEFAULT false, -- Driver connecté à l'app
    is_available BOOLEAN DEFAULT false, -- Driver disponible pour accepter des courses
    is_verified BOOLEAN DEFAULT false, -- Documents vérifiés par l'admin
    verification_status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'approved', 'rejected', 'suspended'
    verification_notes TEXT, -- Notes de l'admin sur la vérification
    
    -- Statistiques
    average_rating DECIMAL(3, 2) DEFAULT 0.00, -- Note moyenne (0.00 à 5.00)
    total_ratings INTEGER DEFAULT 0, -- Nombre total de notes reçues
    total_rides INTEGER DEFAULT 0, -- Nombre total de courses complétées
    total_earnings DECIMAL(12, 2) DEFAULT 0.00, -- Gains totaux en FCFA
    total_distance_km DECIMAL(10, 2) DEFAULT 0.00, -- Distance totale parcourue
    
    -- Préférences
    preferred_radius_km INTEGER DEFAULT 10, -- Rayon de recherche de courses préféré
    max_distance_km INTEGER DEFAULT 50, -- Distance maximale acceptée
    
    -- Métadonnées
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    verified_at TIMESTAMP, -- Date de vérification par l'admin
    last_active_at TIMESTAMP -- Dernière activité
);

-- ============================================
-- INDEX
-- ============================================

-- Index pour users
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
CREATE INDEX IF NOT EXISTS idx_users_role_status ON users(role, status);
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);
CREATE INDEX IF NOT EXISTS idx_users_deleted_at ON users(deleted_at) WHERE deleted_at IS NULL;

-- Index pour driver_profiles
CREATE INDEX IF NOT EXISTS idx_driver_profiles_user_id ON driver_profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_driver_profiles_is_online ON driver_profiles(is_online);
CREATE INDEX IF NOT EXISTS idx_driver_profiles_is_available ON driver_profiles(is_available);
CREATE INDEX IF NOT EXISTS idx_driver_profiles_verification_status ON driver_profiles(verification_status);
CREATE INDEX IF NOT EXISTS idx_driver_profiles_online_available ON driver_profiles(is_online, is_available) WHERE is_online = true AND is_available = true;
CREATE INDEX IF NOT EXISTS idx_driver_profiles_license_number ON driver_profiles(license_number);
CREATE INDEX IF NOT EXISTS idx_driver_profiles_vehicle_plate ON driver_profiles(vehicle_plate);
CREATE INDEX IF NOT EXISTS idx_driver_profiles_average_rating ON driver_profiles(average_rating DESC);

-- ============================================
-- TRIGGERS ET FONCTIONS
-- ============================================

-- Fonction pour mettre à jour updated_at automatiquement
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger pour users
CREATE TRIGGER trigger_update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger pour driver_profiles
CREATE TRIGGER trigger_update_driver_profiles_updated_at
    BEFORE UPDATE ON driver_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Fonction pour mettre à jour last_active_at du driver
CREATE OR REPLACE FUNCTION update_driver_last_active()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_online = true THEN
        NEW.last_active_at = NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger pour mettre à jour last_active_at quand driver se connecte
CREATE TRIGGER trigger_update_driver_last_active
    BEFORE UPDATE OF is_online ON driver_profiles
    FOR EACH ROW
    WHEN (NEW.is_online = true AND OLD.is_online = false)
    EXECUTE FUNCTION update_driver_last_active();

-- ============================================
-- CONTRAINTES DE VALIDATION
-- ============================================

-- Vérifier que l'email est valide (format basique)
ALTER TABLE users ADD CONSTRAINT check_email_format 
    CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- Vérifier que le rôle est valide
ALTER TABLE users ADD CONSTRAINT check_role 
    CHECK (role IN ('client', 'driver', 'admin'));

-- Vérifier que le statut est valide
ALTER TABLE users ADD CONSTRAINT check_status 
    CHECK (status IN ('active', 'inactive', 'suspended', 'pending_verification'));

-- Vérifier que la note moyenne est entre 0 et 5
ALTER TABLE driver_profiles ADD CONSTRAINT check_average_rating 
    CHECK (average_rating >= 0.00 AND average_rating <= 5.00);

-- Vérifier que verification_status est valide
ALTER TABLE driver_profiles ADD CONSTRAINT check_verification_status 
    CHECK (verification_status IN ('pending', 'approved', 'rejected', 'suspended'));

-- ============================================
-- DONNÉES DE TEST (OPTIONNEL)
-- ============================================

-- Un utilisateur admin par défaut (mot de passe à changer)
-- Password hash pour "admin123" (bcrypt avec salt rounds 10)
-- À remplacer par un hash réel lors de la configuration
-- INSERT INTO users (email, password_hash, first_name, last_name, role, status, email_verified)
-- VALUES ('admin@bikeride.pro', '$2b$10$...', 'Admin', 'System', 'admin', 'active', true);

-- ============================================
-- VÉRIFICATION
-- ============================================

SELECT 'Module Users - Tables créées avec succès!' as status;
SELECT COUNT(*) as tables_created FROM information_schema.tables 
WHERE table_schema = 'public' AND table_name IN ('users', 'driver_profiles');

