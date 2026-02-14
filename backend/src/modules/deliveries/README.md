# Module Deliveries - Service de Livraison

## 📋 Vue d'ensemble

Ce module gère le service de livraison de colis. Il implémente le workflow complet depuis la demande jusqu'à la livraison et au paiement.

## 🗄️ Schéma de Base de Données

### Tables principales

- **deliveries** : Stocke toutes les livraisons
- **delivery_timeouts** : Timeouts pour les livraisons
- **delivery_tracking** : Historique GPS d'une livraison

### Tables partagées

- **pricing_config** : Configuration des tarifs (service_type='delivery')
- **pricing_time_slots** : Plages horaires avec multiplicateurs
- **driver_locations** : Positions GPS des drivers en temps réel
- **users** : Utilisateurs (clients, drivers, admins)
- **driver_profiles** : Profils des drivers

## 🔄 Workflow des Statuts

```
REQUESTED
  ↓ (driver accepte)
ASSIGNED
  ↓ (driver récupère le colis)
PICKED_UP
  ↓ (driver démarre vers destinataire)
IN_TRANSIT
  ↓ (driver livre le colis)
DELIVERED
  ↓ (paiement réussi)
PAID (si applicable)

Branches d'annulation:
- REQUESTED → CANCELLED_BY_CLIENT
- REQUESTED → CANCELLED_BY_SYSTEM (timeout)
- ASSIGNED → CANCELLED_BY_DRIVER
- ASSIGNED → CANCELLED_BY_CLIENT
- PICKED_UP → CANCELLED_BY_DRIVER
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

**POST** `/api/v1/deliveries/estimate`
- Estime le prix d'une livraison
- Body: `{ pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, package_weight_kg?, package_type? }`
- Response: `{ distance_km, duration_min, fare_estimate, currency, pricing_breakdown }`

### Client

**POST** `/api/v1/deliveries`
- Crée une nouvelle demande de livraison
- Auth: Requis (Client)
- Body: `{ pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, package_type?, package_weight_kg?, ... }`

**GET** `/api/v1/deliveries`
- Récupère l'historique des livraisons du client

**GET** `/api/v1/deliveries/:id`
- Récupère les détails d'une livraison

**POST** `/api/v1/deliveries/:id/cancel`
- Annule une livraison (client)

**POST** `/api/v1/deliveries/:id/rate`
- Note une livraison (client, driver ou destinataire)

### Driver

**GET** `/api/v1/deliveries/driver/available`
- Récupère les livraisons disponibles

**GET** `/api/v1/deliveries/driver/my-deliveries`
- Récupère l'historique des livraisons du driver

**POST** `/api/v1/deliveries/:id/accept`
- Accepte une livraison (driver)
- Header: `Idempotency-Key` requis

**POST** `/api/v1/deliveries/:id/picked-up`
- Marque que le driver a récupéré le colis

**POST** `/api/v1/deliveries/:id/start-transit`
- Démarre le trajet vers le destinataire

**POST** `/api/v1/deliveries/:id/complete`
- Termine la livraison (colis livré)
- Body: `{ actual_distance_km, actual_duration_min, delivery_proof? }`

**POST** `/api/v1/deliveries/:id/cancel-driver`
- Annule une livraison (driver)

### Admin

**GET** `/api/v1/deliveries/admin/all`
- Récupère toutes les livraisons (admin)

## 📦 Informations Colis

- **package_type** : 'standard', 'fragile', 'food', 'document', 'electronics'
- **package_weight_kg** : Poids en kg
- **package_dimensions** : {length, width, height} en cm
- **package_value** : Valeur déclarée en FCFA
- **requires_signature** : Signature requise à la livraison
- **insurance_required** : Assurance requise

## 💰 Calcul de Prix

Le prix est calculé avec :
- Prix de base (selon pricing_config pour 'delivery')
- Distance × coût/km
- Durée × coût/minute
- Multiplicateur selon poids (>5kg: +20%, >10kg: +50%)
- Multiplicateur selon type (fragile: +30%, food: +10%, electronics: +20%)
- Multiplicateur selon plage horaire (nuit: +30%)

Règle de tolérance : `min(prix_estime × 1.10, prix_calculé_réel)`

## 🔐 Sécurité

- Authentification JWT requise pour toutes les routes sauf `/estimate`
- Autorisation par rôle (client, driver, admin)
- Rate limiting sur création et acceptation
- Idempotency sur actions critiques (accept, cancel, rate)
- Verrous DB pour éviter double acceptation

## 🔗 Intégrations

- **Pricing Service** : Calcul des tarifs
- **Matching Service** : Matching progressif des drivers
- **Timeout Service** : Gestion des timeouts (NO_DRIVER, PICKUP_TIMEOUT)
- **Wallet Service** : Paiement automatique
- **Notifications Service** : Notifications push
- **Maps Service** : Calcul distance/durée
- **Audit Service** : Logging des actions

## 📝 Notes

- Les livraisons utilisent le même système de matching progressif que les courses
- Le driver est libéré immédiatement après `DELIVERED`
- Support du paiement à la livraison (`cash_on_delivery`)
- Preuve de livraison possible (photo, signature)

