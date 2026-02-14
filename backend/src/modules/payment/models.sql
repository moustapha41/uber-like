-- ============================================
-- MODULE PAYMENT - Intentions de paiement (PayTech / Mobile Money)
-- ============================================
-- Lie une demande de paiement externe (PayTech) à une entité (ride, delivery, wallet_deposit)

CREATE TABLE IF NOT EXISTS payment_intents (
    id SERIAL PRIMARY KEY,
    ref_command VARCHAR(100) UNIQUE NOT NULL,  -- ex: RIDE-123, DEL-456, DEP-789
    token VARCHAR(255),                        -- token PayTech (checkout)
    reference_type VARCHAR(50) NOT NULL,      -- 'ride', 'delivery', 'wallet_deposit'
    reference_id INTEGER NOT NULL,            -- id de la course, livraison, etc.
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    amount DECIMAL(12, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'XOF',
    status VARCHAR(50) DEFAULT 'pending',      -- pending, completed, failed, cancelled
    provider VARCHAR(50) DEFAULT 'paytech',
    metadata JSONB,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    completed_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_payment_intents_ref_command ON payment_intents(ref_command);
CREATE INDEX IF NOT EXISTS idx_payment_intents_reference ON payment_intents(reference_type, reference_id);
CREATE INDEX IF NOT EXISTS idx_payment_intents_user_id ON payment_intents(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_intents_status ON payment_intents(status);
