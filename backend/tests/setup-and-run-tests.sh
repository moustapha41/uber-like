#!/bin/bash

# Script pour configurer et exécuter les 9 scénarios de tests
# Usage: ./setup-and-run-tests.sh

set -e  # Arrêter en cas d'erreur

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 CONFIGURATION ET EXÉCUTION DES TESTS${NC}"
echo "=========================================="
echo ""

# Variables
DB_NAME="bikeride_pro_test"
DB_USER="${DB_USER:-postgres}"
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"

# 1. Vérifier que PostgreSQL est accessible
echo -e "${YELLOW}1️⃣ Vérification de PostgreSQL...${NC}"
if ! command -v psql &> /dev/null; then
    echo -e "${RED}❌ psql n'est pas installé${NC}"
    exit 1
fi

# Tester la connexion
if ! PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT 1;" &> /dev/null; then
    echo -e "${RED}❌ Impossible de se connecter à PostgreSQL${NC}"
    echo "   Vérifiez que DB_PASSWORD est défini et que PostgreSQL est démarré"
    exit 1
fi
echo -e "${GREEN}✅ PostgreSQL accessible${NC}"
echo ""

# 2. Créer la base de données de test
echo -e "${YELLOW}2️⃣ Création de la base de données de test...${NC}"
if PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo -e "${YELLOW}⚠️ La base $DB_NAME existe déjà${NC}"
    read -p "Voulez-vous la supprimer et la recréer ? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Suppression de la base existante..."
        PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;"
        PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME;"
        echo -e "${GREEN}✅ Base de données recréée${NC}"
    else
        echo -e "${YELLOW}⚠️ Utilisation de la base existante${NC}"
    fi
else
    PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME;"
    echo -e "${GREEN}✅ Base de données créée${NC}"
fi
echo ""

# 3. Créer les tables
echo -e "${YELLOW}3️⃣ Création des tables...${NC}"
if [ ! -f "tests/setup-database-complete.sql" ]; then
    echo -e "${RED}❌ Fichier tests/setup-database-complete.sql introuvable${NC}"
    exit 1
fi

# Exécuter le script SQL
PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f tests/setup-database-complete.sql > /dev/null 2>&1
echo -e "${GREEN}✅ Tables créées${NC}"
echo ""

# 4. Insérer la configuration de tarifs
echo -e "${YELLOW}4️⃣ Configuration des tarifs par défaut...${NC}"
if [ -f "src/modules/rides/setup-pricing.sql" ]; then
    PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f src/modules/rides/setup-pricing.sql > /dev/null 2>&1
    echo -e "${GREEN}✅ Tarifs configurés${NC}"
else
    echo -e "${YELLOW}⚠️ Fichier setup-pricing.sql introuvable, création manuelle...${NC}"
    PGPASSWORD="${DB_PASSWORD}" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" <<EOF
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
    echo -e "${GREEN}✅ Tarifs configurés${NC}"
fi
echo ""

# 5. Créer le fichier .env.test
echo -e "${YELLOW}5️⃣ Configuration du fichier .env.test...${NC}"
if [ -f ".env.test" ]; then
    echo -e "${YELLOW}⚠️ .env.test existe déjà${NC}"
    read -p "Voulez-vous le recréer ? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm .env.test
    else
        echo -e "${YELLOW}⚠️ Utilisation du fichier existant${NC}"
        echo ""
        # Passer à l'étape suivante
    fi
fi

if [ ! -f ".env.test" ]; then
    cat > .env.test <<EOF
NODE_ENV=test

# Base de données de test
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NAME_TEST=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}

# JWT
JWT_SECRET=test-secret-key-change-in-production
JWT_EXPIRES_IN=1h

# Redis (optionnel pour tests)
REDIS_HOST=localhost
REDIS_PORT=6379

# Maps (optionnel)
GOOGLE_MAPS_API_KEY=
MAPBOX_ACCESS_TOKEN=
EOF
    echo -e "${GREEN}✅ Fichier .env.test créé${NC}"
fi
echo ""

# 6. Vérifier que Jest est installé
echo -e "${YELLOW}6️⃣ Vérification des dépendances...${NC}"
if [ ! -d "node_modules/jest" ]; then
    echo -e "${YELLOW}⚠️ Installation des dépendances de test...${NC}"
    npm install
fi
echo -e "${GREEN}✅ Dépendances OK${NC}"
echo ""

# 7. Exécuter les tests
echo -e "${BLUE}=========================================="
echo -e "🚀 EXÉCUTION DES 9 SCÉNARIOS DE TESTS${NC}"
echo -e "${BLUE}==========================================${NC}"
echo ""

npm test

echo ""
echo -e "${BLUE}=========================================="
echo -e "${GREEN}✅ TESTS TERMINÉS !${NC}"
echo -e "${BLUE}==========================================${NC}"

