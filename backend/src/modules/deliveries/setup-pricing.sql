-- ============================================
-- CONFIGURATION TARIFS PAR DÉFAUT - DELIVERIES
-- ============================================
-- Script pour insérer la configuration de tarification par défaut pour les livraisons
-- À exécuter après la création des tables deliveries

-- Configuration principale pour les livraisons
INSERT INTO pricing_config (service_type, base_fare, cost_per_km, cost_per_minute, commission_rate, max_distance_km, is_active)
VALUES ('delivery', 600, 350, 60, 20, 50, true)
ON CONFLICT DO NOTHING;

-- Récupérer l'ID de la configuration créée
DO $$
DECLARE
    config_id INTEGER;
BEGIN
    SELECT id INTO config_id FROM pricing_config WHERE service_type = 'delivery' AND is_active = true LIMIT 1;
    
    IF config_id IS NOT NULL THEN
        -- Plages horaires
        INSERT INTO pricing_time_slots (pricing_config_id, start_time, end_time, multiplier, description)
        VALUES 
            (config_id, '06:00', '22:00', 1.0, 'Jour'),
            (config_id, '22:00', '06:00', 1.3, 'Nuit')
        ON CONFLICT DO NOTHING;
    END IF;
END $$;

-- Vérification
SELECT 'Configuration tarifs livraisons créée avec succès!' as status;
SELECT * FROM pricing_config WHERE service_type = 'delivery' AND is_active = true;
SELECT * FROM pricing_time_slots WHERE pricing_config_id IN (
    SELECT id FROM pricing_config WHERE service_type = 'delivery' AND is_active = true
);

