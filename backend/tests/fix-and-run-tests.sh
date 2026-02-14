#!/bin/bash

# Script pour recréer la base de test et exécuter les tests
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔧 RÉPARATION ET EXÉCUTION DES TESTS${NC}"
echo "=========================================="
echo ""

# Charger les variables depuis .env
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ Fichier .env introuvable${NC}"
    exit 1
fi

export $(cat .env | grep -v '^#' | xargs)

DB_NAME_TEST="${DB_NAME_TEST:-bikeride_pro_test}"
DB_USER="${DB_USER:-postgres}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"

# 1. Supprimer et recréer la base de test
echo -e "${YELLOW}1️⃣ Recréation de la base de données de test...${NC}"
PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME_TEST;" 2>/dev/null || true
PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME_TEST;" 2>/dev/null
echo -e "${GREEN}✅ Base de données recréée${NC}"
echo ""

# 2. Créer toutes les tables
echo -e "${YELLOW}2️⃣ Création des tables...${NC}"
PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME_TEST" -f tests/setup-database-complete.sql > /dev/null 2>&1
echo -e "${GREEN}✅ Tables créées${NC}"
echo ""

# 3. Configurer les tarifs
echo -e "${YELLOW}3️⃣ Configuration des tarifs...${NC}"
if [ -f "src/modules/rides/setup-pricing.sql" ]; then
    PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME_TEST" -f src/modules/rides/setup-pricing.sql > /dev/null 2>&1
else
    PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME_TEST" <<EOF > /dev/null 2>&1
INSERT INTO pricing_config (service_type, base_fare, cost_per_km, cost_per_minute, commission_rate, max_distance_km, is_active)
VALUES ('ride', 500, 300, 50, 20, 50, true)
ON CONFLICT DO NOTHING;

INSERT INTO pricing_time_slots (pricing_config_id, start_time, end_time, multiplier, description)
SELECT id, '06:00', '22:00', 1.0, 'Jour' FROM pricing_config WHERE service_type = 'ride' LIMIT 1
ON CONFLICT DO NOTHING;

INSERT INTO pricing_time_slots (pricing_config_id, start_time, end_time, multiplier, description)
SELECT id, '22:00', '06:00', 1.3, 'Nuit' FROM pricing_config WHERE service_type = 'ride' LIMIT 1
ON CONFLICT DO NOTHING;
EOF
fi
echo -e "${GREEN}✅ Tarifs configurés${NC}"
echo ""

# 4. Créer .env.test
echo -e "${YELLOW}4️⃣ Configuration de .env.test...${NC}"
cat > .env.test <<EOF
NODE_ENV=test
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NAME_TEST=${DB_NAME_TEST}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
JWT_SECRET=${JWT_SECRET:-test-secret-key}
JWT_EXPIRES_IN=1h
REDIS_HOST=${REDIS_HOST:-localhost}
REDIS_PORT=${REDIS_PORT:-6379}
EOF
echo -e "${GREEN}✅ .env.test créé${NC}"
echo ""

# 5. Exécuter les tests
echo -e "${BLUE}=========================================="
echo -e "🚀 EXÉCUTION DES 9 SCÉNARIOS DE TESTS${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""

npm test

echo ""
echo -e "${BLUE}=========================================="
echo -e "${GREEN}✅ TESTS TERMINÉS !${NC}"
echo -e "${BLUE}==========================================${NC}"

