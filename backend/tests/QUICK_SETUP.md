# 🚀 Configuration Rapide des Tests

## Option 1 : Configuration Automatique (si vous avez accès PostgreSQL)

```bash
cd backend

# Créer la base de données
createdb bikeride_pro_test

# Ou via psql
psql -U postgres
CREATE DATABASE bikeride_pro_test;
\q

# Créer les tables
psql -U postgres -d bikeride_pro_test -f tests/setup-database-complete.sql
```

## Option 2 : Configuration Manuelle

### Étape 1 : Créer la base de données

```bash
# Se connecter à PostgreSQL
sudo -u postgres psql

# Dans psql :
CREATE DATABASE bikeride_pro_test;
\q
```

### Étape 2 : Créer les tables

```bash
# Exécuter le script SQL complet
psql -U postgres -d bikeride_pro_test -f backend/tests/setup-database-complete.sql
```

### Étape 3 : Créer le fichier .env.test

```bash
cd backend
cp .env.test.example .env.test
# Éditer .env.test avec vos credentials PostgreSQL
```

### Étape 4 : Vérifier la configuration

```bash
node tests/check-prerequisites.js
```

### Étape 5 : Exécuter les tests

```bash
npm test
```

## 🔧 Dépannage

### Erreur : "Peer authentication failed"
→ Utilisez `sudo -u postgres psql` ou configurez l'authentification dans `pg_hba.conf`

### Erreur : "Database does not exist"
→ Créez la base avec `createdb bikeride_pro_test` ou via psql

### Erreur : "Table does not exist"
→ Exécutez `tests/setup-database-complete.sql`

## ✅ Vérification

Une fois configuré, vous devriez voir :

```
✅ Connexion à la base de données OK
✅ Table users existe
✅ Table driver_profiles existe
✅ Table rides existe
✅ Table pricing_config existe
```

