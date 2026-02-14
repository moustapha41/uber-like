# Dépendances du Module Rides

## Tables Requises (à créer dans le module users/auth)

### Table: users
```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(20) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    role VARCHAR(20) NOT NULL, -- 'client', 'driver', 'admin'
    status VARCHAR(20) DEFAULT 'active', -- 'active', 'inactive', 'suspended'
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

### Table: driver_profiles
```sql
CREATE TABLE driver_profiles (
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

## Extensions PostgreSQL Requises

Pour les index géospatiaux, activer l'extension PostGIS (optionnel) ou utiliser les types point natifs :

```sql
-- Si PostGIS est disponible (recommandé pour production)
CREATE EXTENSION IF NOT EXISTS postgis;

-- Sinon, utiliser les types point natifs (déjà utilisé dans models.sql)
```

## Notes

- Le module rides dépend du module **users** pour les tables `users` et `driver_profiles`
- Ces tables doivent être créées avant d'exécuter le script `models.sql` du module rides
- Les contraintes de clés étrangères seront vérifiées lors de la création des tables rides

