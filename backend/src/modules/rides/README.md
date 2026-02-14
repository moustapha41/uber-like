# Module Rides - Service de Course

## 📋 Vue d'ensemble

Ce module gère le service professionnel de courses de mototaxi. Il implémente le workflow complet depuis la demande jusqu'au paiement et à la notation.

## 🗄️ Schéma de Base de Données

### Tables principales

- **rides** : Stocke toutes les courses
- **pricing_config** : Configuration des tarifs par l'admin
- **pricing_time_slots** : Plages horaires avec multiplicateurs
- **ride_reviews** : Avis et notations
- **driver_locations** : Positions GPS des drivers en temps réel
- **ride_tracking** : Historique GPS d'une course

### Tables dépendantes (à créer dans le module users)

- **users** : Utilisateurs (clients, drivers, admins)
- **driver_profiles** : Profils des drivers (is_online, is_available, average_rating, etc.)

## 🔄 Workflow des Statuts

```
REQUESTED
  ↓ (driver accepte)
DRIVER_ASSIGNED
  ↓ (driver arrive)
DRIVER_ARRIVED
  ↓ (driver démarre)
IN_PROGRESS
  ↓ (driver termine)
COMPLETED
  ↓ (paiement réussi)
PAID
  ↓ (clôture)
CLOSED

Branches d'annulation:
- REQUESTED → CANCELLED_BY_CLIENT
- REQUESTED → CANCELLED_BY_SYSTEM (timeout)
- DRIVER_ASSIGNED → CANCELLED_BY_DRIVER
- DRIVER_ASSIGNED → CANCELLED_BY_CLIENT
- DRIVER_ARRIVED → CANCELLED_BY_CLIENT (no-show)
```

## 💳 États de Paiement

```
UNPAID
  ↓ (initiation paiement)
PAYMENT_PENDING
  ↓ (confirmation)
PAID
  ↓ (en cas d'échec)
PAYMENT_FAILED
  ↓ (remboursement)
REFUNDED
```

## 🚀 API Endpoints

### Estimation (Public)

**POST** `/api/v1/rides/estimate`
- Estime le prix d'une course
- Body: `{ pickup_lat, pickup_lng, dropoff_lat, dropoff_lng }`
- Response: `{ distance_km, duration_min, fare_estimate, currency, pricing_breakdown }`

### Client

**POST** `/api/v1/rides`
- Crée une nouvelle demande de course
- Auth: Requis (Client)
- Body: `{ pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, pickup_address?, dropoff_address? }`

**GET** `/api/v1/rides`
- Récupère l'historique des courses du client
- Auth: Requis (Client)
- Query: `?limit=50&offset=0`

**GET** `/api/v1/rides/:id`
- Récupère les détails d'une course
- Auth: Requis

**POST** `/api/v1/rides/:id/cancel`
- Annule une course (client)
- Auth: Requis (Client)
- Body: `{ reason? }`

**POST** `/api/v1/rides/:id/rate`
- Note une course
- Auth: Requis
- Body: `{ rating (1-5), comment?, role (client|driver) }`

### Driver

**GET** `/api/v1/rides/driver/available`
- Récupère les courses disponibles
- Auth: Requis (Driver)

**GET** `/api/v1/rides/driver/my-rides`
- Historique des courses du driver
- Auth: Requis (Driver)
- Query: `?limit=50&offset=0`

**POST** `/api/v1/rides/:id/accept`
- Accepte une course
- Auth: Requis (Driver)

**POST** `/api/v1/rides/:id/arrived`
- Marque l'arrivée au point de prise en charge
- Auth: Requis (Driver)

**POST** `/api/v1/rides/:id/start`
- Démarre la course
- Auth: Requis (Driver)

**POST** `/api/v1/rides/:id/location` ⚠️ DÉPRÉCIÉ
- ⚠️ **Utiliser WebSocket à la place** (voir section WebSocket)
- Auth: Requis (Driver)
- Body: `{ lat, lng, heading?, speed? }`

**POST** `/api/v1/rides/:id/complete`
- Termine la course
- Auth: Requis (Driver)
- Body: `{ actual_distance_km, actual_duration_min }`

**POST** `/api/v1/rides/:id/cancel-driver`
- Annule une course (driver)
- Auth: Requis (Driver)
- Body: `{ reason? }`

### Admin

**GET** `/api/v1/rides/admin/all`
- Récupère toutes les courses
- Auth: Requis (Admin)
- Query: `?status=pending&limit=50&offset=0`

## 💰 Calcul de Prix

Le prix est calculé selon la formule :

```
Prix = (Frais de base + (Distance × Prix/km) + (Durée × Prix/minute)) × Multiplicateur horaire
```

- **Frais de base** : 500 FCFA (configurable)
- **Prix/km** : 300 FCFA (configurable)
- **Prix/minute** : 50 FCFA (configurable)
- **Multiplicateur** : Selon la plage horaire (ex: 1.3 la nuit)

### Prix Final (après le trajet)

**Règle officielle**: `prix_final = min(prix_estime × 1.10, prix_calculé_reel)`

- Protection client contre sur-facturation
- Évite litiges et fraude driver
- Tolérance maximale de +10% sur l'estimation

## 🔍 Matching Progressif des Drivers

Le système utilise une stratégie de matching progressif pour optimiser le taux d'acceptation :

1. **T+0s** → 1 driver le plus proche (rayon 5km)
2. **T+10s** → +2 drivers supplémentaires
3. **T+20s** → +5 drivers supplémentaires
4. **T+30s** → Broadcast large (rayon étendu à 10km)
5. **T+2min** → Annulation automatique si aucun driver n'a accepté

**Avantages**:
- Meilleur taux d'acceptation
- Moins de spam push notifications
- Réduction de la charge serveur

## ⏱️ Timeouts

- **Aucun driver** : Annulation automatique après 2-3 minutes
- **Client ne se présente pas** : Annulation après 7 minutes d'attente au point de prise en charge

## 🔔 Notifications

Le module envoie des notifications push à chaque étape :

- Nouvelle demande → Drivers proches
- Course acceptée → Client
- Driver arrivé → Client
- Course démarrée → Client
- Course terminée → Client
- Course annulée → Parties concernées

## 🔌 WebSocket (GPS Tracking)

**⚠️ IMPORTANT**: Le tracking GPS utilise WebSocket, pas POST REST.

### Événements WebSocket

**Driver**:
- `driver:authenticate` - Authentification driver
- `driver:location:update` - Envoie position GPS (toutes les 5 sec)
  ```javascript
  socket.emit('driver:location:update', {
    rideId: 123,
    lat: 14.7167,
    lng: -17.4677,
    heading: 45,
    speed: 30
  });
  ```

**Client**:
- `client:authenticate` - Authentification client
- `ride:subscribe` - S'abonner aux updates d'une course
- Reçoit `driver:location:update` en temps réel

**Serveur**:
- `ride:new_request` - Nouvelle demande de course (broadcast aux drivers)
- `ride:driver_assigned` - Driver assigné (notifie le client)

## 📊 Intégrations

- **Maps Service** : Calcul distance/durée, géocodage
- **Matching Service** : Matching progressif des drivers
- **Pricing Service** : Calcul des prix
- **WebSocket Service** : Tracking GPS en temps réel
- **Notifications Service** : Push notifications
- **Audit Service** : Logging des actions
- **Wallet/Payment** : Paiement (à intégrer)

## 🛠️ Installation

1. Exécuter le script SQL pour créer les tables :
```bash
psql -U postgres -d bikeride_pro -f src/modules/rides/models.sql
```

2. Créer les tables dépendantes (users, driver_profiles) dans le module users

3. Configurer les tarifs par défaut dans `pricing_config`

## 📝 Notes Techniques

- **Verrou DB critique**: `SELECT ... FOR UPDATE` dans `acceptRide()` pour éviter double acceptation
- **WebSocket obligatoire**: Le tracking GPS utilise WebSocket, pas POST REST (performance)
- **Matching progressif**: Envoi par vagues pour optimiser le taux d'acceptation
- **Formule prix**: `min(estime × 1.10, réel)` pour protection client
- **Statuts en MAJUSCULES**: `REQUESTED` au lieu de `pending` (plus clair)
- **State machine stricte**: Les transitions de statut sont validées
- **Idempotence**: Endpoints critiques protégés contre doubles traitements

