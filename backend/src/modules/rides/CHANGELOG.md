# Changelog - Module Rides

## Ajustements Critiques (Production)

### ✅ Statuts renommés
- `pending` → `REQUESTED` (plus clair, moins ambigu)
- Tous les statuts en MAJUSCULES pour cohérence
- Nouveaux statuts: `REQUESTED`, `DRIVER_ASSIGNED`, `DRIVER_ARRIVED`, `IN_PROGRESS`, `COMPLETED`, `PAID`, `CLOSED`
- Statuts d'annulation: `CANCELLED_BY_CLIENT`, `CANCELLED_BY_DRIVER`, `CANCELLED_BY_SYSTEM`

### ✅ Verrou DB critique pour acceptation
- Utilisation de `SELECT ... FOR UPDATE` dans `acceptRide()`
- Protection contre double acceptation simultanée
- Vérification du statut AVANT la mise à jour
- Transaction avec ROLLBACK en cas d'erreur

### ✅ GPS Tracking via WebSocket
- **Remplacement de POST /location** par WebSocket
- Service `websocket.service.js` créé
- Événement `driver:location:update` toutes les 5 secondes
- Broadcast automatique au client en temps réel
- POST /location conservé mais déprécié (compatibilité)

### ✅ Formule prix final ajustée
- **Nouvelle règle**: `prix_final = min(prix_estime × 1.10, prix_calculé_reel)`
- Protection client contre sur-facturation
- Évite litiges et fraude driver

### ✅ Services séparés
- **MatchingService** créé (`matching.service.js`)
- **PricingService** déjà séparé
- **WebSocketService** créé (`websocket.service.js`)
- Facilite migration vers microservices

### ✅ Matching progressif
- **T+0s** → 1 driver le plus proche
- **T+10s** → +2 drivers
- **T+20s** → +5 drivers
- **T+30s** → broadcast large (rayon 10km)
- Meilleur taux d'acceptation, moins de spam push

### ✅ États paiement
- Nouveaux statuts: `UNPAID`, `PAYMENT_PENDING`, `PAID`, `PAYMENT_FAILED`, `REFUNDED`
- State machine pour gestion Mobile Money
- Intégration avec module payment

## Migration

Pour migrer les données existantes:

```sql
-- Mettre à jour les statuts
UPDATE rides SET status = 'REQUESTED' WHERE status = 'pending';
UPDATE rides SET status = 'DRIVER_ASSIGNED' WHERE status = 'driver_assigned';
UPDATE rides SET status = 'DRIVER_ARRIVED' WHERE status = 'driver_arrived';
UPDATE rides SET status = 'IN_PROGRESS' WHERE status = 'in_progress';
UPDATE rides SET status = 'COMPLETED' WHERE status = 'completed';
UPDATE rides SET status = 'CANCELLED_BY_CLIENT' WHERE status = 'cancelled_by_client';
UPDATE rides SET status = 'CANCELLED_BY_DRIVER' WHERE status = 'cancelled_by_driver';
UPDATE rides SET status = 'CANCELLED_BY_SYSTEM' WHERE status = 'cancelled_by_system';

-- Mettre à jour les statuts de paiement
UPDATE rides SET payment_status = 'UNPAID' WHERE payment_status = 'pending';
UPDATE rides SET payment_status = 'PAID' WHERE payment_status = 'completed';
UPDATE rides SET payment_status = 'PAYMENT_FAILED' WHERE payment_status = 'failed';
```

