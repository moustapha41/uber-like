# Guide de Configuration des Tests

## 📋 Prérequis

### 1. Base de Données PostgreSQL

```bash
# Créer la base de données de test
createdb -U postgres bikeride_pro_test

# Ou via psql
psql -U postgres
CREATE DATABASE bikeride_pro_test;
```

### 2. Variables d'Environnement

Créer un fichier `.env.test` dans `backend/` :

```env
NODE_ENV=test
DB_HOST=localhost
DB_PORT=5432
DB_NAME_TEST=bikeride_pro_test
DB_USER=postgres
DB_PASSWORD=votre_mot_de_passe
JWT_SECRET=test-secret-key-for-testing
```

### 3. Créer les Tables

```bash
# Exécuter le script SQL pour créer les tables
psql -U postgres -d bikeride_pro_test -f src/modules/rides/models.sql

# Créer aussi les tables dépendantes (users, driver_profiles)
# Ces tables doivent être créées dans le module users/auth
```

### 4. Tables Dépendantes Requises

Avant d'exécuter les tests, créer ces tables :

```sql
-- Table users (à créer dans module users/auth)
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

-- Table driver_profiles (à créer dans module users/auth)
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
```

## 🚀 Exécution des Tests

```bash
# Vérifier les prérequis
node tests/check-prerequisites.js

# Exécuter tous les tests
npm test

# Un scénario spécifique
npm test -- scenario1-happy-path.test.js

# Avec couverture
npm test -- --coverage
```

## ⚠️ Notes Importantes

1. **Base de données de test séparée** : Utilisez `bikeride_pro_test` pour éviter d'affecter les données de production
2. **Nettoyage automatique** : Les tests nettoient les données créées après exécution
3. **Isolation** : Chaque scénario est indépendant et peut être exécuté séparément

## 🔧 Dépannage

### Erreur : "Table does not exist"
→ Exécutez les scripts SQL pour créer les tables

### Erreur : "Connection refused"
→ Vérifiez que PostgreSQL est démarré et que les credentials dans `.env.test` sont corrects

### Erreur : "JWT_SECRET not defined"
→ Ajoutez `JWT_SECRET` dans `.env.test`

