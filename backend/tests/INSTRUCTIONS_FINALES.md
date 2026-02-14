# 🚀 Instructions Finales - Configuration des Tests

## ⚠️ Important

PostgreSQL nécessite des permissions administrateur. Voici les **2 options** pour configurer :

## Option 1 : Via Terminal (Recommandé)

Ouvrez un terminal et exécutez ces commandes **une par une** :

```bash
cd /home/moustapha/Bike/backend

# 1. Créer la base de données
sudo -u postgres createdb bikeride_pro_test

# 2. Créer les tables
sudo -u postgres psql -d bikeride_pro_test -f tests/setup-database-complete.sql

# 3. Configurer .env.test (éditer avec votre mot de passe PostgreSQL)
nano .env.test
# Ou: gedit .env.test
# Modifier DB_PASSWORD=votre_mot_de_passe

# 4. Vérifier
node tests/check-prerequisites.js

# 5. Exécuter les tests
npm test
```

## Option 2 : Via psql Interactif

```bash
# 1. Se connecter à PostgreSQL
sudo -u postgres psql

# 2. Dans psql, exécuter :
CREATE DATABASE bikeride_pro_test;
\q

# 3. Créer les tables
cd /home/moustapha/Bike/backend
sudo -u postgres psql -d bikeride_pro_test -f tests/setup-database-complete.sql

# 4. Configurer .env.test
nano .env.test
# Modifier DB_PASSWORD

# 5. Tester
node tests/check-prerequisites.js
npm test
```

## ✅ Vérification

Après configuration, vous devriez voir :

```
✅ Connexion à la base de données OK
✅ Table users existe
✅ Table driver_profiles existe
✅ Table rides existe
✅ Table pricing_config existe
```

## 📝 Fichiers Créés

- ✅ `.env.test` - Fichier de configuration (à compléter avec votre mot de passe)
- ✅ `tests/setup-database-complete.sql` - Script SQL complet
- ✅ `tests/EXECUTE_SETUP.sh` - Script d'exécution (si vous avez les permissions)

## 🎯 Commandes Rapides

Une fois configuré :

```bash
# Vérifier
node tests/check-prerequisites.js

# Exécuter tous les tests
npm test

# Un scénario spécifique
npm test -- scenario1-happy-path.test.js
```

**Les tests sont prêts, il ne reste qu'à exécuter les commandes PostgreSQL ci-dessus !**

