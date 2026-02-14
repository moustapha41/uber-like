# Module Admin

API réservée aux utilisateurs avec le rôle `admin`. Toutes les routes exigent `Authorization: Bearer <token>` et un compte admin.

## Endpoints

| Méthode | Route | Description |
|--------|--------|-------------|
| GET | `/api/v1/admin` | Dashboard : stats (utilisateurs, courses, livraisons, revenus, drivers en attente) |
| GET | `/api/v1/admin/users` | Liste utilisateurs (query: `role`, `status`, `limit`, `offset`) |
| PUT | `/api/v1/admin/users/:id/status` | Modifier statut utilisateur (`active`, `inactive`, `suspended`, `pending_verification`) |
| GET | `/api/v1/admin/drivers` | Liste drivers (query: `status`, `verified`, `is_online`, `limit`, `offset`) |
| PUT | `/api/v1/admin/drivers/:id/verify` | Vérification driver (`verification_status`: `pending` \| `approved` \| `rejected` \| `suspended`, `verification_notes` optionnel) |
| GET | `/api/v1/admin/pricing` | Toutes les configs tarifaires (ride + delivery) |
| GET | `/api/v1/admin/pricing/:id` | Une config tarifaire par ID |
| PUT | `/api/v1/admin/pricing/:id` | Mettre à jour une config (champs optionnels: `base_fare`, `cost_per_km`, `cost_per_minute`, `commission_rate`, `max_distance_km`, `is_active`) |
| GET | `/api/v1/admin/audit` | Logs d’audit (query: `entity_type`, `entity_id`, `user_id`, `action`, `date_from`, `date_to`, `limit`, `offset`) |

## Dépendances

- **Users** : `listUsers`, `updateUserStatus`, `listDrivers`, `updateDriverVerification`
- **Pricing** (rides) : `getAllPricingConfigs`, `getPricingConfigById`, `updatePricingConfig`
- **Audit** : `getLogs`

## Créer un compte admin

```bash
# Depuis la racine backend, avec .env configuré (DB_*)
npm run seed:admin
```

Par défaut : `admin@bikeride.pro` / `Admin123!`. Personnalisable via `ADMIN_EMAIL`, `ADMIN_PASSWORD`, `ADMIN_PHONE`, `ADMIN_FIRST_NAME`, `ADMIN_LAST_NAME`.
