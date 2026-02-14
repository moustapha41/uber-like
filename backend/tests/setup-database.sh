#!/bin/bash

# Script pour créer la base de données de test et toutes les tables
# Usage: ./setup-database.sh

set -e

echo "🔧 Configuration de la base de données de test..."
echo ""

# Variables
DB_NAME="bikeride_pro_test"
DB_USER="${DB_USER:-postgres}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"

# Vérifier si la base existe déjà
if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo "⚠️  La base de données $DB_NAME existe déjà."
    read -p "Voulez-vous la supprimer et la recréer ? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  Suppression de l'ancienne base..."
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -c "DROP DATABASE IF EXISTS $DB_NAME;"
    else
        echo "✅ Utilisation de la base existante."
        exit 0
    fi
fi

# Créer la base de données
echo "📦 Création de la base de données $DB_NAME..."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -c "CREATE DATABASE $DB_NAME;" || {
    echo "❌ Erreur lors de la création de la base de données"
    exit 1
}

echo "✅ Base de données créée"
echo ""

# Créer les tables
echo "📋 Création des tables..."

# Table users
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<EOF
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
EOF

# Table driver_profiles
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<EOF
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
EOF

# Exécuter le script du module rides
echo "📋 Création des tables du module rides..."
cd "$(dirname "$0")/.."
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f src/modules/rides/models.sql

# Insérer une configuration de prix par défaut
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<EOF
-- Configuration de prix par défaut pour les tests
INSERT INTO pricing_config (service_type, base_fare, cost_per_km, cost_per_minute, commission_rate, max_distance_km, is_active)
VALUES ('ride', 500, 300, 50, 20, 50, true)
ON CONFLICT DO NOTHING;

-- Plages horaires par défaut
INSERT INTO pricing_time_slots (pricing_config_id, start_time, end_time, multiplier, description)
SELECT id, '06:00', '22:00', 1.0, 'Jour'
FROM pricing_config WHERE service_type = 'ride' AND is_active = true
ON CONFLICT DO NOTHING;

INSERT INTO pricing_time_slots (pricing_config_id, start_time, end_time, multiplier, description)
SELECT id, '22:00', '06:00', 1.3, 'Nuit'
FROM pricing_config WHERE service_type = 'ride' AND is_active = true
ON CONFLICT DO NOTHING;
EOF

echo ""
echo "✅ Configuration terminée !"
echo ""
echo "📝 Prochaines étapes :"
echo "   1. Créer le fichier .env.test avec vos credentials"
echo "   2. Exécuter : npm test"
echo ""

