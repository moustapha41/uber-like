#!/bin/bash

# Script pour créer la base de données de test
# À exécuter manuellement avec les permissions appropriées

echo "🔧 Configuration de la base de données de test pour BikeRide Pro"
echo ""

# Vérifier si la base existe
if psql -U postgres -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw bikeride_pro_test; then
    echo "⚠️  La base de données bikeride_pro_test existe déjà"
    read -p "Voulez-vous la supprimer et la recréer ? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  Suppression..."
        psql -U postgres -c "DROP DATABASE bikeride_pro_test;" 2>/dev/null || echo "Erreur lors de la suppression"
    else
        echo "✅ Utilisation de la base existante"
        SKIP_CREATE=true
    fi
fi

if [ "$SKIP_CREATE" != "true" ]; then
    echo "📦 Création de la base de données..."
    psql -U postgres -c "CREATE DATABASE bikeride_pro_test;" || {
        echo "❌ Erreur: Impossible de créer la base de données"
        echo "💡 Essayez: sudo -u postgres createdb bikeride_pro_test"
        exit 1
    }
    echo "✅ Base de données créée"
fi

echo ""
echo "📋 Création des tables..."
cd "$(dirname "$0")/.."

psql -U postgres -d bikeride_pro_test -f tests/setup-database-complete.sql && {
    echo ""
    echo "✅ Tables créées avec succès !"
    echo ""
    echo "📝 Prochaines étapes :"
    echo "   1. Créer/éditer .env.test avec vos credentials"
    echo "   2. Exécuter: node tests/check-prerequisites.js"
    echo "   3. Exécuter: npm test"
} || {
    echo ""
    echo "❌ Erreur lors de la création des tables"
    echo "💡 Vérifiez vos permissions PostgreSQL"
    exit 1
}

