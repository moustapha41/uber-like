# 🚀 Installation du Module Users

## ⚠️ IMPORTANT

Le module Users **DOIT** être installé **AVANT** le module Rides car les tables `users` et `driver_profiles` sont des dépendances critiques.

## 📋 Étapes d'Installation

### 1. Créer la Base de Données

```bash
createdb -U postgres bikeride_pro
```

### 2. Créer les Tables Users

```bash
cd backend
psql -U postgres -d bikeride_pro -f src/modules/users/models.sql
```

### 3. Vérifier la Création

```bash
psql -U postgres -d bikeride_pro -c "\dt users driver_profiles"
```

Vous devriez voir :
```
              List of relations
 Schema |      Name       | Type  |  Owner   
--------+-----------------+-------+----------
 public | users           | table | postgres
 public | driver_profiles | table | postgres
```

### 4. Créer les Tables Rides (Après Users)

```bash
psql -U postgres -d bikeride_pro -f src/modules/rides/models.sql
```

### 5. Vérifier l'Intégration

Les routes sont déjà intégrées dans `app.js` :
```javascript
app.use(`/api/${API_VERSION}/users`, require('./modules/users/routes'));
```

## ✅ Vérification

### Test de Connexion

```bash
# Démarrer le serveur
npm start

# Tester l'endpoint health
curl http://localhost:3000/health
```

### Test des Routes (avec authentification)

Les routes nécessitent une authentification JWT. Une fois le module Auth implémenté, vous pourrez tester :

```bash
# Récupérer le profil (nécessite token JWT)
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3000/api/v1/users/profile
```

## 📊 Tables Créées

### users
- ✅ 20+ colonnes (email, phone, role, status, etc.)
- ✅ Index sur email, phone, role, status
- ✅ Triggers pour updated_at
- ✅ Contraintes de validation

### driver_profiles
- ✅ 30+ colonnes (license, vehicle, stats, etc.)
- ✅ Index sur user_id, is_online, is_available
- ✅ Triggers pour updated_at et last_active_at
- ✅ Contraintes de validation

## 🔗 Dépendances

### Dépendances NPM
- ✅ `bcryptjs` - Hash des mots de passe (déjà dans package.json)
- ✅ `express-validator` - Validation (déjà dans package.json)
- ✅ `pg` - PostgreSQL (déjà dans package.json)

### Dépendances Modules
- ✅ `middleware/auth.js` - Authentification JWT
- ✅ `utils/response.js` - Helpers de réponse
- ✅ `utils/logger.js` - Logging structuré

## 🎯 Prochaines Étapes

1. ✅ Module Users créé
2. ⏳ Implémenter module Auth (register/login)
3. ⏳ Tester les endpoints avec Postman
4. ⏳ Créer des utilisateurs de test
5. ⏳ Tester l'intégration avec le module Rides

## 📝 Notes

- Les mots de passe sont hashés avec **bcryptjs** (10 salt rounds)
- Les utilisateurs utilisent le **soft delete** (`deleted_at`)
- Les drivers ont un profil séparé avec statistiques
- Les positions GPS sont dans `driver_locations` (module rides)

**Le module Users est prêt à être utilisé !**

