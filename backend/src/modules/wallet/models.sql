-- ============================================
-- SCHÉMA BASE DE DONNÉES - MODULE WALLET
-- ============================================
-- Ce module gère le portefeuille électronique pour tous les services
-- (Courses, Livraisons, Covoiturage)

-- ============================================
-- TABLE: wallets
-- ============================================
-- Portefeuille électronique par utilisateur

CREATE TABLE IF NOT EXISTS wallets (
    id SERIAL PRIMARY KEY,
    user_id INTEGER UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    balance DECIMAL(12, 2) DEFAULT 0.00 NOT NULL, -- Solde en FCFA
    currency VARCHAR(3) DEFAULT 'XOF', -- XOF (Franc CFA)
    is_active BOOLEAN DEFAULT true,
    
    -- Métadonnées
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    last_transaction_at TIMESTAMP
);

-- ============================================
-- TABLE: transactions
-- ============================================
-- Historique de toutes les transactions (débits/crédits)

CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    wallet_id INTEGER NOT NULL REFERENCES wallets(id) ON DELETE RESTRICT,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    
    -- Type de transaction
    type VARCHAR(50) NOT NULL, -- 'credit', 'debit', 'refund', 'commission', 'withdrawal', 'deposit'
    amount DECIMAL(12, 2) NOT NULL, -- Montant (toujours positif)
    balance_before DECIMAL(12, 2) NOT NULL, -- Solde avant transaction
    balance_after DECIMAL(12, 2) NOT NULL, -- Solde après transaction
    
    -- Référence à la source
    reference_type VARCHAR(50), -- 'ride', 'delivery', 'carpool', 'manual', 'mobile_money'
    reference_id INTEGER, -- ID de la course/livraison/etc.
    
    -- Description
    description TEXT,
    metadata JSONB, -- Données supplémentaires
    
    -- Statut
    status VARCHAR(50) DEFAULT 'completed', -- 'pending', 'completed', 'failed', 'cancelled'
    
    -- Métadonnées
    created_at TIMESTAMP DEFAULT NOW(),
    processed_at TIMESTAMP
);

-- ============================================
-- INDEX
-- ============================================

-- Index pour wallets
CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON wallets(user_id);
CREATE INDEX IF NOT EXISTS idx_wallets_is_active ON wallets(is_active);

-- Index pour transactions
CREATE INDEX IF NOT EXISTS idx_transactions_wallet_id ON transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON transactions(type);
CREATE INDEX IF NOT EXISTS idx_transactions_reference ON transactions(reference_type, reference_id);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON transactions(created_at DESC);

-- ============================================
-- TRIGGERS ET FONCTIONS
-- ============================================

-- Fonction pour mettre à jour updated_at
CREATE OR REPLACE FUNCTION update_wallet_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger pour wallets
CREATE TRIGGER trigger_update_wallets_updated_at
    BEFORE UPDATE ON wallets
    FOR EACH ROW
    EXECUTE FUNCTION update_wallet_updated_at();

-- Fonction pour mettre à jour last_transaction_at
CREATE OR REPLACE FUNCTION update_wallet_last_transaction()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'completed' THEN
        UPDATE wallets 
        SET last_transaction_at = NOW() 
        WHERE id = NEW.wallet_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger pour transactions
CREATE TRIGGER trigger_update_wallet_last_transaction
    AFTER INSERT ON transactions
    FOR EACH ROW
    EXECUTE FUNCTION update_wallet_last_transaction();

-- ============================================
-- CONTRAINTES DE VALIDATION
-- ============================================

-- Vérifier que le solde ne peut pas être négatif
ALTER TABLE wallets ADD CONSTRAINT check_balance_non_negative 
    CHECK (balance >= 0.00);

-- Vérifier que le type de transaction est valide
ALTER TABLE transactions ADD CONSTRAINT check_transaction_type 
    CHECK (type IN ('credit', 'debit', 'refund', 'commission', 'withdrawal', 'deposit'));

-- Vérifier que le statut est valide
ALTER TABLE transactions ADD CONSTRAINT check_transaction_status 
    CHECK (status IN ('pending', 'completed', 'failed', 'cancelled'));

-- Vérifier que le montant est positif
ALTER TABLE transactions ADD CONSTRAINT check_amount_positive 
    CHECK (amount > 0.00);

-- ============================================
-- VÉRIFICATION
-- ============================================

SELECT 'Module Wallet - Tables créées avec succès!' as status;
SELECT COUNT(*) as tables_created FROM information_schema.tables 
WHERE table_schema = 'public' AND table_name IN ('wallets', 'transactions');

