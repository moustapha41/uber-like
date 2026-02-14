-- ============================================
-- MIGRATION 001 - AMÉLIORATIONS TERRAIN RÉEL
-- ============================================
-- Ajoute les fonctionnalités critiques pour la production

-- 1. Ajouter les nouveaux statuts dans deliveries
ALTER TABLE deliveries 
  DROP CONSTRAINT IF EXISTS check_delivery_status;

ALTER TABLE deliveries 
  ADD CONSTRAINT check_delivery_status 
  CHECK (status IN (
    'REQUESTED', 'ASSIGNED', 'PICKED_UP', 'IN_TRANSIT', 'DELIVERED',
    'CANCELLED_BY_CLIENT', 'CANCELLED_BY_DRIVER', 'CANCELLED_BY_SYSTEM',
    'NO_SHOW_CLIENT', 'PACKAGE_REFUSED', 'DELIVERY_FAILED', 'RETURN_TO_SENDER'
  ));

-- 2. Ajouter colonnes pour geler le prix au moment ASSIGNED
ALTER TABLE deliveries 
  ADD COLUMN IF NOT EXISTS frozen_fare DECIMAL(10, 2), -- Prix gelé au moment ASSIGNED
  ADD COLUMN IF NOT EXISTS fare_frozen_at TIMESTAMP; -- Quand le prix a été gelé

-- 3. Table pour décomposer les frais (geler les détails)
CREATE TABLE IF NOT EXISTS delivery_fees_breakdown (
    id SERIAL PRIMARY KEY,
    delivery_id INTEGER NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
    
    -- Détails du prix gelé
    base_fare DECIMAL(10, 2) NOT NULL,
    distance_cost DECIMAL(10, 2) NOT NULL,
    time_cost DECIMAL(10, 2) NOT NULL,
    weight_multiplier DECIMAL(5, 2) DEFAULT 1.0,
    type_multiplier DECIMAL(5, 2) DEFAULT 1.0,
    time_multiplier DECIMAL(5, 2) DEFAULT 1.0,
    
    -- Prix calculés
    subtotal DECIMAL(10, 2) NOT NULL,
    total_fare DECIMAL(10, 2) NOT NULL,
    
    -- Métadonnées
    pricing_config_id INTEGER, -- Référence à la config utilisée
    frozen_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(delivery_id)
);

CREATE INDEX IF NOT EXISTS idx_delivery_fees_breakdown_delivery_id ON delivery_fees_breakdown(delivery_id);

-- 4. Ajouter capacités drivers dans driver_profiles
ALTER TABLE driver_profiles 
  ADD COLUMN IF NOT EXISTS delivery_capabilities JSONB DEFAULT '{}'::jsonb;
  -- Structure JSONB:
  -- {
  --   "max_weight_kg": 15,
  --   "has_thermal_bag": true,
  --   "can_handle_fragile": true,
  --   "can_handle_food": true,
  --   "can_handle_electronics": true,
  --   "can_handle_documents": true,
  --   "has_insurance_coverage": true,
  --   "delivery_radius_km": 20
  -- }

CREATE INDEX IF NOT EXISTS idx_driver_profiles_delivery_capabilities ON driver_profiles USING GIN (delivery_capabilities);

-- 5. Table pour preuves de livraison détaillées
CREATE TABLE IF NOT EXISTS delivery_proofs (
    id SERIAL PRIMARY KEY,
    delivery_id INTEGER NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
    
    -- Photos
    package_photo_url TEXT, -- Photo du colis avant livraison
    delivery_photo_url TEXT, -- Photo du colis livré
    location_photo_url TEXT, -- Photo de l'emplacement de livraison
    
    -- Signature
    signature_url TEXT, -- URL de la signature (si requise)
    signature_data JSONB, -- Données de signature (coordonnées, etc.)
    
    -- Informations destinataire
    recipient_name VARCHAR(255), -- Nom de la personne qui a reçu
    recipient_phone VARCHAR(20), -- Téléphone du destinataire
    recipient_id_number VARCHAR(50), -- Pièce d'identité (si vérifiée)
    
    -- Métadonnées
    delivered_by VARCHAR(50) DEFAULT 'driver', -- 'driver', 'recipient', 'neighbor'
    delivery_notes TEXT, -- Notes du driver sur la livraison
    gps_lat DECIMAL(10, 8), -- Position GPS de livraison
    gps_lng DECIMAL(11, 8),
    
    created_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(delivery_id)
);

CREATE INDEX IF NOT EXISTS idx_delivery_proofs_delivery_id ON delivery_proofs(delivery_id);
CREATE INDEX IF NOT EXISTS idx_delivery_proofs_created_at ON delivery_proofs(created_at);

-- 6. Table pour tracking temps réel (amélioration)
ALTER TABLE delivery_tracking 
  ADD COLUMN IF NOT EXISTS battery_level INTEGER, -- Niveau batterie device driver (%)
  ADD COLUMN IF NOT EXISTS network_type VARCHAR(20), -- 'wifi', '4g', '3g', '2g'
  ADD COLUMN IF NOT EXISTS accuracy DECIMAL(5, 2); -- Précision GPS en mètres

-- 7. Table pour notifications intelligentes (historique)
CREATE TABLE IF NOT EXISTS delivery_notifications (
    id SERIAL PRIMARY KEY,
    delivery_id INTEGER NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    notification_type VARCHAR(50) NOT NULL, -- 'driver_arrived', 'package_picked', 'in_transit', 'arriving_soon', 'delivered'
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    
    -- Métadonnées
    sent_at TIMESTAMP DEFAULT NOW(),
    read_at TIMESTAMP,
    clicked_at TIMESTAMP,
    
    -- Données additionnelles
    metadata JSONB -- {estimated_arrival_minutes, distance_km, etc.}
);

CREATE INDEX IF NOT EXISTS idx_delivery_notifications_delivery_id ON delivery_notifications(delivery_id);
CREATE INDEX IF NOT EXISTS idx_delivery_notifications_user_id ON delivery_notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_delivery_notifications_sent_at ON delivery_notifications(sent_at);

-- 8. Table pour gestion des retours (RETURN_TO_SENDER)
CREATE TABLE IF NOT EXISTS delivery_returns (
    id SERIAL PRIMARY KEY,
    delivery_id INTEGER NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
    
    return_reason VARCHAR(100) NOT NULL, -- 'recipient_refused', 'address_incorrect', 'unreachable', 'damaged'
    return_initiated_by VARCHAR(50) NOT NULL, -- 'driver', 'system', 'client'
    return_initiated_at TIMESTAMP DEFAULT NOW(),
    
    -- Nouvelle tentative ou retour définitif
    return_type VARCHAR(50) DEFAULT 'permanent', -- 'permanent', 'retry'
    retry_delivery_id INTEGER REFERENCES deliveries(id), -- Si retry
    
    -- Informations retour
    return_notes TEXT,
    return_photo_url TEXT, -- Photo du colis retourné
    
    -- Statut
    returned_at TIMESTAMP, -- Quand le colis est retourné à l'expéditeur
    status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'in_transit', 'returned', 'cancelled'
    
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_delivery_returns_delivery_id ON delivery_returns(delivery_id);
CREATE INDEX IF NOT EXISTS idx_delivery_returns_status ON delivery_returns(status);

-- 9. Ajouter colonnes pour edge cases paiement
ALTER TABLE deliveries 
  ADD COLUMN IF NOT EXISTS payment_frozen_at TIMESTAMP, -- Quand le paiement a été gelé
  ADD COLUMN IF NOT EXISTS cancellation_fee DECIMAL(10, 2) DEFAULT 0, -- Frais d'annulation
  ADD COLUMN IF NOT EXISTS refund_amount DECIMAL(10, 2) DEFAULT 0, -- Montant remboursé
  ADD COLUMN IF NOT EXISTS refund_reason TEXT; -- Raison du remboursement

-- 10. Table pour historique des changements de statut (audit trail)
CREATE TABLE IF NOT EXISTS delivery_status_history (
    id SERIAL PRIMARY KEY,
    delivery_id INTEGER NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
    
    old_status VARCHAR(50),
    new_status VARCHAR(50) NOT NULL,
    
    changed_by INTEGER REFERENCES users(id), -- Qui a changé le statut
    changed_by_type VARCHAR(50), -- 'client', 'driver', 'system', 'admin'
    
    reason TEXT, -- Raison du changement
    metadata JSONB, -- Données additionnelles
    
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_delivery_status_history_delivery_id ON delivery_status_history(delivery_id);
CREATE INDEX IF NOT EXISTS idx_delivery_status_history_created_at ON delivery_status_history(created_at);

-- 11. Ajouter colonnes pour features business (loyalty, insurance, corporate)
ALTER TABLE deliveries 
  ADD COLUMN IF NOT EXISTS loyalty_points_earned INTEGER DEFAULT 0, -- Points fidélité gagnés
  ADD COLUMN IF NOT EXISTS insurance_fee DECIMAL(10, 2) DEFAULT 0, -- Frais assurance optionnelle
  ADD COLUMN IF NOT EXISTS corporate_account_id INTEGER, -- Compte entreprise (si applicable)
  ADD COLUMN IF NOT EXISTS discount_amount DECIMAL(10, 2) DEFAULT 0, -- Réduction appliquée
  ADD COLUMN IF NOT EXISTS discount_code VARCHAR(50); -- Code promo utilisé

-- 12. Table pour comptes entreprise
CREATE TABLE IF NOT EXISTS corporate_accounts (
    id SERIAL PRIMARY KEY,
    company_name VARCHAR(255) NOT NULL,
    company_email VARCHAR(255) UNIQUE NOT NULL,
    company_phone VARCHAR(20),
    
    -- Contact principal
    contact_person_name VARCHAR(255),
    contact_person_email VARCHAR(255),
    contact_person_phone VARCHAR(20),
    
    -- Facturation
    billing_address TEXT,
    tax_id VARCHAR(100), -- Numéro fiscal
    payment_terms VARCHAR(50) DEFAULT 'net_30', -- 'net_30', 'net_60', 'prepaid'
    
    -- Limites et crédit
    credit_limit DECIMAL(12, 2) DEFAULT 0,
    current_balance DECIMAL(12, 2) DEFAULT 0,
    
    -- Statut
    status VARCHAR(50) DEFAULT 'active', -- 'active', 'suspended', 'closed'
    is_active BOOLEAN DEFAULT true,
    
    -- Métadonnées
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_corporate_accounts_email ON corporate_accounts(company_email);
CREATE INDEX IF NOT EXISTS idx_corporate_accounts_status ON corporate_accounts(status);

-- 13. Table pour programme fidélité
CREATE TABLE IF NOT EXISTS loyalty_programs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- Points
    total_points INTEGER DEFAULT 0,
    available_points INTEGER DEFAULT 0,
    used_points INTEGER DEFAULT 0,
    
    -- Niveau
    tier VARCHAR(50) DEFAULT 'bronze', -- 'bronze', 'silver', 'gold', 'platinum'
    tier_multiplier DECIMAL(3, 2) DEFAULT 1.0, -- Multiplicateur de points selon niveau
    
    -- Statistiques
    total_deliveries INTEGER DEFAULT 0,
    total_spent DECIMAL(12, 2) DEFAULT 0,
    
    -- Métadonnées
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    
    UNIQUE(user_id)
);

CREATE INDEX IF NOT EXISTS idx_loyalty_programs_user_id ON loyalty_programs(user_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_programs_tier ON loyalty_programs(tier);

-- 14. Table pour transactions fidélité
CREATE TABLE IF NOT EXISTS loyalty_transactions (
    id SERIAL PRIMARY KEY,
    loyalty_program_id INTEGER NOT NULL REFERENCES loyalty_programs(id) ON DELETE CASCADE,
    delivery_id INTEGER REFERENCES deliveries(id),
    
    transaction_type VARCHAR(50) NOT NULL, -- 'earned', 'redeemed', 'expired', 'bonus'
    points INTEGER NOT NULL, -- Positif pour gagné, négatif pour utilisé
    description TEXT,
    
    created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_loyalty_transactions_program_id ON loyalty_transactions(loyalty_program_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_transactions_delivery_id ON loyalty_transactions(delivery_id);

-- Vérification
SELECT 'Migration 001 complétée avec succès!' as status;

