# Module Users - Gestion des Utilisateurs et Drivers

## 📋 Vue d'ensemble

Ce module gère les utilisateurs (clients, drivers, admins) et les profils des drivers professionnels. Il est **critique** car le module Rides en dépend.

## 🗄️ Schéma de Base de Données

### Tables principales

#### **users**
Table principale des utilisateurs avec :
- Informations de base (email, phone, password_hash)
- Rôle (`client`, `driver`, `admin`)
- Statut (`active`, `inactive`, `suspended`, `pending_verification`)
- Vérification (email, phone)
- Sécurité (failed_login_attempts, locked_until)

#### **driver_profiles**
Profils des drivers professionnels avec :
- Informations professionnelles (license, vehicle)
- Assurance
- Statut (`is_online`, `is_available`, `is_verified`)
- Statistiques (average_rating, total_rides, total_earnings)
- Préférences (preferred_radius_km, max_distance_km)

### Relations

- `driver_profiles.user_id` → `users(id)` ON DELETE CASCADE
- `rides.client_id` → `users(id)` ON DELETE RESTRICT
- `rides.driver_id` → `users(id)` ON DELETE SET NULL

## 🚀 API Endpoints

### Utilisateur

**GET** `/api/v1/users/profile`
- Récupère le profil de l'utilisateur connecté
- Auth: Requis
- Response: `{ user, driver_profile? }`

**GET** `/api/v1/users/:id`
- Récupère un utilisateur par ID
- Auth: Requis (admin ou propriétaire)
- Response: `{ user }`

**PUT** `/api/v1/users/profile`
- Met à jour le profil de l'utilisateur connecté
- Auth: Requis
- Body: `{ first_name?, last_name?, phone?, avatar_url? }`

### Drivers

**GET** `/api/v1/users/drivers`
- Liste les drivers (admin uniquement)
- Auth: Requis (admin)
- Query: `status?`, `verified?`, `is_online?`, `limit?`, `offset?`
- Response: `[{ driver }]`

**GET** `/api/v1/users/drivers/:id`
- Récupère le profil d'un driver
- Auth: Requis (admin ou driver propriétaire)
- Response: `{ driver_profile }`

**PUT** `/api/v1/users/drivers/:id/status`
- Met à jour le statut online/available d'un driver
- Auth: Requis (driver)
- Body: `{ is_online: boolean, is_available: boolean }`

**POST** `/api/v1/users/drivers/:id/location` ⚠️ DÉPRÉCIÉ
- Met à jour la position GPS d'un driver
- Auth: Requis (driver)
- Body: `{ lat, lng, heading?, speed? }`
- **Note** : Utiliser WebSocket pour le tracking en temps réel

## 💼 Services

### `users.service.js`

#### Méthodes principales :

1. **`createUser(userData)`**
   - Crée un nouvel utilisateur
   - Hash le mot de passe avec bcrypt
   - Crée automatiquement un profil driver si `role = 'driver'`

2. **`createDriverProfile(userId, driverData)`**
   - Crée un profil driver pour un utilisateur
   - Vérifie que l'utilisateur est un driver

3. **`getUserById(userId)`**
   - Récupère un utilisateur par ID
   - Exclut les utilisateurs supprimés (soft delete)

4. **`getUserByEmail(email)`**
   - Récupère un utilisateur par email
   - Utilisé pour l'authentification

5. **`getDriverProfile(userId)`**
   - Récupère le profil driver d'un utilisateur
   - Inclut les informations de l'utilisateur

6. **`updateDriverStatus(driverId, isOnline, isAvailable)`**
   - Met à jour le statut online/available
   - Met à jour `last_active_at` automatiquement

7. **`updateDriverLocation(driverId, lat, lng, heading, speed)`**
   - Met à jour la position GPS dans `driver_locations`
   - Utilise `ON CONFLICT` pour upsert

8. **`updateDriverStats(driverId, rating, distanceKm, earnings)`**
   - Met à jour les statistiques après une course
   - Recalcule la note moyenne
   - Incrémente total_rides, total_distance_km, total_earnings

9. **`verifyCredentials(email, password)`**
   - Vérifie les credentials (email + password)
   - Compare avec bcrypt
   - Met à jour `last_login_at` et réinitialise `failed_login_attempts`

10. **`listDrivers(filters, limit, offset)`**
    - Liste les drivers avec filtres
    - Supporte filtres : status, verified, is_online
    - Inclut la position GPS si disponible

## 🔐 Sécurité

### Authentification
- Mots de passe hashés avec **bcrypt** (10 salt rounds)
- Protection contre les tentatives de connexion échouées
- Verrouillage temporaire après trop de tentatives

### Autorisation
- Middleware `authenticate` : Vérifie le JWT
- Middleware `authorize` : Vérifie le rôle
- Vérification que l'utilisateur modifie son propre profil

### Validation
- `express-validator` pour toutes les entrées
- Validation email, phone, coordonnées GPS
- Contraintes DB pour intégrité

## 📊 Intégration avec Module Rides

Le module Rides dépend du module Users pour :

1. **Création de courses** : Vérifie que `client_id` existe dans `users`
2. **Acceptation de courses** : Vérifie que `driver_id` existe et est disponible
3. **Matching** : Utilise `driver_profiles.is_online` et `is_available`
4. **Statistiques** : Met à jour `driver_profiles` après chaque course
5. **Notation** : Met à jour `average_rating` et `total_ratings`

## 🛠️ Installation

1. **Créer les tables** :
```bash
psql -U postgres -d bikeride_pro -f src/modules/users/models.sql
```

2. **⚠️ IMPORTANT** : Créer les tables Users **AVANT** le module Rides :
```bash
# 1. Users (d'abord)
psql -U postgres -d bikeride_pro -f src/modules/users/models.sql

# 2. Rides (ensuite)
psql -U postgres -d bikeride_pro -f src/modules/rides/models.sql
```

3. **Intégrer dans app.js** :
```javascript
const usersRoutes = require('./modules/users/routes');
app.use('/api/v1/users', usersRoutes);
```

## 📝 Notes Techniques

- **Soft Delete** : Les utilisateurs ne sont pas supprimés physiquement (`deleted_at`)
- **Cascade Delete** : Si un user est supprimé, son `driver_profile` est supprimé automatiquement
- **Index optimisés** : Pour recherche par email, phone, role, status
- **Triggers** : Mise à jour automatique de `updated_at` et `last_active_at`
- **Validation DB** : Contraintes CHECK pour email, role, status, ratings

## 🔄 Workflow Driver

```
1. User s'inscrit avec role='driver'
   ↓
2. Profil driver créé automatiquement (verification_status='pending')
   ↓
3. Driver upload ses documents (license, insurance, etc.)
   ↓
4. Admin vérifie et approuve (verification_status='approved')
   ↓
5. Driver peut se connecter et accepter des courses
   ↓
6. Driver met is_online=true et is_available=true
   ↓
7. Driver apparaît dans les résultats de matching
```

## ✅ État Actuel

- ✅ Schéma DB complet
- ✅ Service users complet
- ✅ Routes API créées
- ✅ Intégration avec module Rides
- ⏳ Module Auth (register/login) - À créer
- ⏳ Upload de documents - À implémenter
- ⏳ Vérification admin - À implémenter

---

**Le module Users est prêt et permet au module Rides de fonctionner !**

