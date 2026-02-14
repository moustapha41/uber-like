#!/bin/bash

# Script pour configurer automatiquement la base de données de test
# À exécuter avec les permissions appropriées

set -e

echo "🔧 Configuration automatique de la base de données de test"
echo "============================================================"
echo ""

DB_NAME="bikeride_pro_test"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

# Fonction pour créer la base de données
create_database() {
    echo "📦 Étape 1/3 : Création de la base de données..."
    
    # Essayer différentes méthodes
    if command -v createdb &> /dev/null; then
        if createdb "$DB_NAME" 2>/dev/null; then
            echo "✅ Base de données créée avec createdb"
            return 0
        fi
    fi
    
    if psql -U postgres -c "CREATE DATABASE $DB_NAME;" 2>/dev/null; then
        echo "✅ Base de données créée avec psql -U postgres"
        return 0
    fi
    
    if sudo -u postgres createdb "$DB_NAME" 2>/dev/null; then
        echo "✅ Base de données créée avec sudo -u postgres"
        return 0
    fi
    
    echo "❌ Impossible de créer la base de données automatiquement"
    echo "💡 Veuillez créer manuellement :"
    echo "   sudo -u postgres createdb $DB_NAME"
    return 1
}

# Fonction pour créer les tables
create_tables() {
    echo ""
    echo "📋 Étape 2/3 : Création des tables..."
    
    SQL_FILE="$SCRIPT_DIR/setup-database-complete.sql"
    
    if [ ! -f "$SQL_FILE" ]; then
        echo "❌ Fichier SQL non trouvé : $SQL_FILE"
        return 1
    fi
    
    # Essayer différentes méthodes
    if psql -d "$DB_NAME" -f "$SQL_FILE" 2>/dev/null; then
        echo "✅ Tables créées avec psql"
        return 0
    fi
    
    if psql -U postgres -d "$DB_NAME" -f "$SQL_FILE" 2>/dev/null; then
        echo "✅ Tables créées avec psql -U postgres"
        return 0
    fi
    
    if sudo -u postgres psql -d "$DB_NAME" -f "$SQL_FILE" 2>/dev/null; then
        echo "✅ Tables créées avec sudo -u postgres"
        return 0
    fi
    
    echo "❌ Impossible de créer les tables automatiquement"
    echo "💡 Veuillez exécuter manuellement :"
    echo "   sudo -u postgres psql -d $DB_NAME -f $SQL_FILE"
    return 1
}

# Fonction pour créer .env.test
create_env_test() {
    echo ""
    echo "📝 Étape 3/3 : Création du fichier .env.test..."
    
    ENV_FILE="$PROJECT_DIR/.env.test"
    
    if [ -f "$ENV_FILE" ]; then
        echo "⚠️  .env.test existe déjà"
        read -p "Voulez-vous le recréer ? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "✅ Utilisation du fichier existant"
            return 0
        fi
    fi
    
    cat > "$ENV_FILE" << 'EOF'
NODE_ENV=test
DB_HOST=localhost
DB_PORT=5432
DB_NAME_TEST=bikeride_pro_test
DB_USER=postgres
DB_PASSWORD=
JWT_SECRET=test-secret-key-for-testing-only-do-not-use-in-production
REDIS_HOST=localhost
REDIS_PORT=6379
EOF

    echo "✅ Fichier .env.test créé"
    echo ""
    echo "⚠️  IMPORTANT : Éditez .env.test et ajoutez votre mot de passe PostgreSQL :"
    echo "   nano .env.test"
    echo "   # Modifier DB_PASSWORD=votre_mot_de_passe"
}

# Exécution
main() {
    create_database || {
        echo ""
        echo "❌ Échec de la création de la base de données"
        echo "💡 Veuillez créer manuellement et réessayer"
        exit 1
    }
    
    create_tables || {
        echo ""
        echo "❌ Échec de la création des tables"
        echo "💡 Veuillez créer manuellement et réessayer"
        exit 1
    }
    
    create_env_test
    
    echo ""
    echo "============================================================"
    echo "✅ Configuration terminée !"
    echo ""
    echo "📝 Prochaines étapes :"
    echo "   1. Éditer .env.test et ajouter votre mot de passe PostgreSQL"
    echo "   2. Exécuter : node tests/check-prerequisites.js"
    echo "   3. Exécuter : npm test"
    echo ""
}

main

