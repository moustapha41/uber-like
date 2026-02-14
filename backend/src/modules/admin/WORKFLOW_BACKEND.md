# Workflow backend – Dashboard Admin

Ce document décrit le **flux côté backend** lorsqu’un client (frontend, Postman, curl) appelle l’API admin : qui fait quoi, dans quel ordre, quelles tables et quels services sont utilisés.

---

## 1. Point d’entrée et sécurité

Toutes les routes sous `/api/v1/admin` sont montées dans `app.js` :

```text
app.use(`/api/${API_VERSION}/admin`, require('./modules/admin/routes'));
```

Dans `admin/routes.js` :

1. **authenticate** : lit `Authorization: Bearer <token>`, vérifie le JWT, charge l’utilisateur en base (`users`), vérifie qu’il existe et est `status = 'active'`, attache `req.user` (userId, email, role).
2. **authorize('admin')** : vérifie `req.user.role === 'admin'`. Sinon → 403.

Toute requête admin non authentifiée → 401. Authentifiée mais pas admin → 403.

---

## 2. Workflow par endpoint

### GET /api/v1/admin (Dashboard – statistiques)

| Étape | Composant | Action |
|--------|-----------|--------|
| 1 | `authenticate` | Vérifie JWT, charge user, `req.user` |
| 2 | `authorize('admin')` | Vérifie rôle admin |
| 3 | `adminService.getDashboardStats()` | Exécute 5 requêtes SQL en parallèle |
| 4 | DB | `users` : COUNT par role (client, driver, admin) |
| 5 | DB | `rides` : COUNT + SUM(fare_final) où status IN (COMPLETED, PAID, CLOSED) |
| 6 | DB | `deliveries` : COUNT + SUM(fare_final) où status = COMPLETED (sinon 0 si table absente) |
| 7 | DB | `driver_profiles` : COUNT où verification_status = 'pending' |
| 8 | DB | `rides` : 5 dernières lignes (id, ride_code, status, fare_final, created_at) |
| 9 | Réponse | JSON : users (total, clients, drivers, admins), rides (total, revenue), deliveries (total, revenue), pending_drivers_verification, recent_rides |

Aucune écriture en base. Lecture seule, agrégations.

---

### GET /api/v1/admin/users

| Étape | Composant | Action |
|--------|-----------|--------|
| 1 | Auth | authenticate + authorize('admin') |
| 2 | Validation | Query : role, status, limit, offset (optionnels) |
| 3 | `adminService.listUsers(filters, limit, offset)` | Délègue à `usersService.listUsers` |
| 4 | `users.service` | SELECT COUNT(*) puis SELECT id, email, phone, first_name, last_name, role, status, created_at FROM users WHERE deleted_at IS NULL + filtres, ORDER BY created_at DESC, LIMIT/OFFSET |
| 5 | Réponse | { users: [...], total: N } |

Tables : `users` (lecture seule).

---

### PUT /api/v1/admin/users/:id/status

| Étape | Composant | Action |
|--------|-----------|--------|
| 1 | Auth | authenticate + authorize('admin') |
| 2 | Validation | param id (entier), body status in (active, inactive, suspended, pending_verification) |
| 3 | `adminService.updateUserStatus(userId, status)` | Délègue à `usersService.updateUserStatus` |
| 4 | `users.service` | UPDATE users SET status = $1, updated_at = NOW() WHERE id = $2 AND deleted_at IS NULL RETURNING ... |
| 5 | Réponse | Utilisateur mis à jour ou 404 si non trouvé |

Table : `users` (écriture).

---

### GET /api/v1/admin/drivers

| Étape | Composant | Action |
|--------|-----------|--------|
| 1 | Auth | authenticate + authorize('admin') |
| 2 | Validation | Query : status, verified, is_online, limit, offset |
| 3 | `adminService.listDrivers(filters, limit, offset)` | Délègue à `usersService.listDrivers` |
| 4 | `users.service` | SELECT users + driver_profiles + driver_locations (LEFT JOIN), WHERE role = 'driver' + filtres, ORDER BY created_at DESC |
| 5 | Réponse | Tableau de drivers (avec profil et position si dispo) |

Tables : `users`, `driver_profiles`, `driver_locations` (lecture seule).

---

### PUT /api/v1/admin/drivers/:id/verify

| Étape | Composant | Action |
|--------|-----------|--------|
| 1 | Auth | authenticate + authorize('admin') |
| 2 | Validation | param id, body verification_status (pending|approved|rejected|suspended), verification_notes optionnel |
| 3 | `adminService.updateDriverVerification(...)` | Délègue à `usersService.updateDriverVerification` |
| 4 | `users.service` | UPDATE driver_profiles SET verification_status, verification_notes, is_verified = (status === 'approved'), verified_at = NOW() WHERE user_id = $1 RETURNING * |
| 5 | Réponse | Profil driver mis à jour ou 404 |

Table : `driver_profiles` (écriture).

---

### GET /api/v1/admin/pricing et GET /api/v1/admin/pricing/:id

| Étape | Composant | Action |
|--------|-----------|--------|
| 1 | Auth | authenticate + authorize('admin') |
| 2 | GET /pricing | `adminService.getAllPricingConfigs()` → `pricingService.getAllPricingConfigs()` |
| 2b | GET /pricing/:id | `adminService.getPricingConfigById(id)` → `pricingService.getPricingConfigById(id)` |
| 3 | `pricing.service` | SELECT * FROM pricing_config (et par id pour :id) + SELECT * FROM pricing_time_slots WHERE pricing_config_id = ... |
| 4 | Réponse | Liste de configs (avec time_slots) ou une config |

Tables : `pricing_config`, `pricing_time_slots` (lecture seule).

---

### PUT /api/v1/admin/pricing/:id

| Étape | Composant | Action |
|--------|-----------|--------|
| 1 | Auth | authenticate + authorize('admin') |
| 2 | Validation | body : base_fare, cost_per_km, cost_per_minute, commission_rate, max_distance_km, is_active (optionnels) |
| 3 | `adminService.updatePricingConfig(id, data)` | Délègue à `pricingService.updatePricingConfig` |
| 4 | `pricing.service` | UPDATE pricing_config SET <champs fournis>, updated_at = NOW() WHERE id = $1 RETURNING * |
| 5 | Réponse | Config mise à jour ou 404 |

Table : `pricing_config` (écriture). Les `pricing_time_slots` ne sont pas modifiés par cet endpoint.

---

### GET /api/v1/admin/audit

| Étape | Composant | Action |
|--------|-----------|--------|
| 1 | Auth | authenticate + authorize('admin') |
| 2 | Validation | Query : entity_type, entity_id, user_id, action, date_from, date_to, limit, offset |
| 3 | `adminService.getAuditLogs(filters, limit, offset)` | Délègue à `auditService.getLogs` |
| 4 | `audit.service` | SELECT COUNT(*) puis SELECT * FROM audit_logs WHERE <filtres> ORDER BY created_at DESC LIMIT/OFFSET |
| 5 | Réponse | { logs: [...], total: N } |

Table : `audit_logs` (lecture seule).

---

## 3. Schéma récapitulatif

```text
Client (frontend / curl)
    │
    ▼
Express app  →  /api/v1/admin/*  →  admin/routes.js
                                        │
                    authenticate ───────┼──► JWT + users (role, status)
                    authorize('admin') ──┼──► 403 si role !== admin
                                        │
                    Validation (express-validator)
                                        │
                    admin.service  ──────┼──► Délégation selon la route
                                        │
        ┌───────────────────────────────┼───────────────────────────────┐
        ▼                               ▼                               ▼
  users.service              pricing.service                  audit.service
  (users, driver_profiles,   (pricing_config,                  (audit_logs)
   driver_locations)          pricing_time_slots)
        │                               │                               │
        ▼                               ▼                               ▼
  PostgreSQL                  PostgreSQL                      PostgreSQL
```

- **Tables lues** : users, driver_profiles, driver_locations, rides, deliveries, pricing_config, pricing_time_slots, audit_logs.
- **Tables écrites** : users (statut), driver_profiles (vérification), pricing_config (tarifs). Aucune écriture pour dashboard, liste users, liste drivers, liste pricing, audit.

---

## 4. Dépendances entre modules (backend)

| Module admin (routes + admin.service) | Utilise |
|--------------------------------------|---------|
| middleware/auth | authenticate, authorize |
| users.service | listUsers, updateUserStatus, listDrivers, updateDriverVerification |
| rides/pricing.service | getAllPricingConfigs, getPricingConfigById, updatePricingConfig |
| audit.service | getLogs |
| config/database (pool) | Uniquement dans admin.service pour getDashboardStats (requêtes directes) |

Le “workflow dashboard admin” côté backend est donc : **auth → validation → admin.service (ou délégation users/pricing/audit) → SQL → réponse JSON**.
