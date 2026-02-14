#!/bin/bash

# Script simplifié pour créer la base de données de test
# Utilise l'utilisateur système actuel

set -e

DB_NAME="bikeride_pro_test"
CURRENT_USER=$(whoami)

echo "🔧 Configuration de la base de données de test..."
echo "Utilisateur: $CURRENT_USER"
echo ""

# Vérifier si psql est accessible
if ! command -v psql &> /dev/null; then
    echo "❌ psql n'est pas installé ou n'est pas dans le PATH"
    exit 1
fi

# Essayer de se connecter
echo "🔌 Test de connexion à PostgreSQL..."
if psql -d postgres -c "SELECT 1;" &> /dev/null; then
    echo "✅ Connexion réussie"
    DB_USER="$CURRENT_USER"
elif psql -U postgres -d postgres -c "SELECT 1;" &> /dev/null; then
    echo "✅ Connexion réussie avec utilisateur postgres"
    DB_USER="postgres"
else
    echo "❌ Impossible de se connecter à PostgreSQL"
    echo ""
    echo "💡 Solutions possibles :"
    echo "   1. Créer la base manuellement :"
    echo "      createdb $DB_NAME"
    echo "   2. Ou exécuter le script SQL manuellement :"
    echo "      psql -d $DB_NAME -f tests/setup-database-complete.sql"
    exit 1
fi

# Vérifier si la base existe
if psql -d "$DB_NAME" -c "SELECT 1;" &> /dev/null 2>&1; then
    echo "⚠️  La base de données $DB_NAME existe déjà"
    read -p "Voulez-vous la supprimer et la recréer ? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  Suppression de l'ancienne base..."
        dropdb "$DB_NAME" || psql -U "$DB_USER" -c "DROP DATABASE $DB_NAME;"
    else
        echo "✅ Utilisation de la base existante"
        RECREATE=false
    fi
fi

# Créer la base si nécessaire
if [ "$RECREATE" != "false" ]; then
    echo "📦 Création de la base de données $DB_NAME..."
    createdb "$DB_NAME" 2>/dev/null || psql -U "$DB_USER" -c "CREATE DATABASE $DB_NAME;" || {
        echo "❌ Erreur lors de la création de la base de données"
        exit 1
    }
    echo "✅ Base de données créée"
fi

# Créer les tables
echo ""
echo "📋 Création des tables..."
cd "$(dirname "$0")/.."

if psql -d "$DB_NAME" -f tests/setup-database-complete.sql; then
    echo ""
    echo "✅ Configuration terminée avec succès !"
    echo ""
    echo "📝 Prochaines étapes :"
    echo "   1. Créer le fichier .env.test (voir tests/SETUP_GUIDE.md)"
    echo "   2. Exécuter : npm test"
else
    echo ""
    echo "❌ Erreur lors de la création des tables"
    echo "💡 Essayez d'exécuter manuellement :"
    echo "   psql -d $DB_NAME -f tests/setup-database-complete.sql"
    exit 1
fi

