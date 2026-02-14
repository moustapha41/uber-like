# Apps Client et Chauffeur — Flutter

Les applications **client** et **chauffeur** sont développées en **Flutter** (pas en React/Web). Ce document décrit le contrat API et les écrans à prévoir.

**Backend** : `http://localhost:3000` (ou variable d’environnement en prod).  
**Préfixe API** : `/api/v1`.

---

## 1. Projets Flutter (déjà présents)

Les deux apps sont dans le repo :

| App | Dossier |
|-----|--------|
| **Client** (passager / expéditeur) | **`app-client/`** |
| **Chauffeur** (conducteur / livreur) | **`app-driver/`** |

Pour lancer : `cd app-client && flutter run` (ou `app-driver`). Flutter doit être installé (`sudo snap install flutter` ou [flutter.dev](https://flutter.dev)).

---

## 2. API commune : Authentification

Toutes les requêtes authentifiées : **`Authorization: Bearer <token>`**.

| Méthode | URL | Rôle | Body | Réponse |
|--------|-----|------|------|--------|
| POST | `/auth/register` | - | `email`, `password`, `phone?`, `first_name?`, `last_name?`, **`role`**: `"client"` ou `"driver"` | `{ success, data: { user, token, refreshToken } }` |
| POST | `/auth/login` | - | `email`, `password` | `{ success, data: { user, token, refreshToken } }` |
| POST | `/auth/refresh` | - | `refreshToken` | Nouveau token |

- Enregistrer `data.token` (et optionnellement `refreshToken`) après login/register.
- 401 → déconnecter et renvoyer vers l’écran de connexion.

---

## 3. App CLIENT (Flutter)

### 3.1 Endpoints utilisés

**Courses (rides)**  
- `POST /rides/estimate` — Body : `pickup_lat`, `pickup_lng`, `dropoff_lat`, `dropoff_lng` → estimation prix.  
- `POST /rides` — Créer une course (même body + `pickup_address?`, `dropoff_address?`). **Auth client.**  
- `GET /rides` — Historique des courses du client (`limit`, `offset`).  
- `GET /rides/:id` — Détail d’une course.  
- `POST /rides/:id/cancel` — Annuler (client). **Idempotency-Key** recommandé.  
- `POST /rides/:id/rate` — Noter la course (body : `rating`, `comment?`, `role: "client"`).

**Livraisons (deliveries)**  
- `POST /deliveries/estimate` — Body : `pickup_lat`, `pickup_lng`, `dropoff_lat`, `dropoff_lng`, `package_weight_kg?`, `package_type?`.  
- `POST /deliveries` — Créer une livraison (même body + adresses, `package_type`, `package_description?`, etc.). **Auth client.**  
- `GET /deliveries` — Historique des livraisons.  
- `GET /deliveries/:id` — Détail.  
- `POST /deliveries/:id/cancel` — Annuler (client).

### 3.2 Écrans à prévoir (app client)

1. **Connexion / Inscription** — Login, Register (role = client).  
2. **Accueil** — Choix « Course » ou « Livraison », accès historique.  
3. **Nouvelle course** — Saisie départ / arrivée (adresses ou carte), estimation, confirmation, création → suivi statut.  
4. **Nouvelle livraison** — Saisie adresses + type/poids colis, estimation, confirmation, création → suivi.  
5. **Détail course / livraison** — Statut en temps réel (optionnel : WebSocket ou polling), annuler, noter (course).  
6. **Historique** — Liste des courses et livraisons passées.

---

## 4. App CHAUFFEUR (Flutter)

### 4.1 Endpoints utilisés

**Profil / statut**  
- `PUT /users/drivers/:id/status` — Body : `is_online`, `is_available`. **Auth driver**, `:id` = son propre `user.id`.  
- `POST /users/drivers/:id/location` — Body : `lat`, `lng`, `heading?`, `speed?` (optionnel, WebSocket possible pour le tracking).

**Courses**  
- `GET /rides/driver/available` — Courses disponibles (à accepter).  
- `GET /rides/driver/my-rides` — Mes courses (`limit`, `offset` en query).  
- `POST /rides/:id/accept` — Accepter une course. **Idempotency-Key** recommandé.  
- `POST /rides/:id/arrived` — Arrivé au point de départ.  
- `POST /rides/:id/start` — Démarrer la course.  
- `POST /rides/:id/complete` — Terminer (body : `actual_distance_km`, `actual_duration_min`).

**Livraisons**  
- `GET /deliveries/driver/available` — Livraisons disponibles.  
- `GET /deliveries/driver/my-deliveries` — Mes livraisons (`limit`, `offset`).  
- `POST /deliveries/:id/accept` — Accepter. **Idempotency-Key** recommandé.  
- `POST /deliveries/:id/picked-up` — Colis récupéré.  
- `POST /deliveries/:id/start-transit` — En transit.  
- `POST /deliveries/:id/complete` — Terminer (body : `actual_distance_km`, `actual_duration_min`).  
- `POST /deliveries/:id/cancel-driver` — Annuler (chauffeur).

### 4.2 Écrans à prévoir (app chauffeur)

1. **Connexion / Inscription** — Login, Register (role = driver).  
2. **Statut en ligne** — Toggle « En ligne » / « Disponible » (PUT status).  
3. **Demandes** — Liste des courses/livraisons disponibles, accepter ou refuser.  
4. **Course en cours** — Enchaînement : acceptée → arrivé → démarré → terminé (boutons + position optionnelle).  
5. **Livraison en cours** — Acceptée → colis récupéré → en transit → livrée.  
6. **Historique / revenus** — Mes courses et livraisons terminées.

---

## 5. Format des réponses backend

- Succès : `{ "success": true, "message": "...", "data": ... }`  
- Erreur : `{ "success": false, "message": "..." }`  
- Codes HTTP : 200, 201, 400, 401, 403, 404, 409, 500.

---

## 6. Structure Flutter recommandée

- `lib/main.dart` — Point d’entrée, `MaterialApp`, routes.  
- `lib/services/api.dart` — Client HTTP (Dio ou `http`), base URL configurable, injection du token.  
- `lib/services/auth_service.dart` — Stockage token (shared_preferences / flutter_secure_storage), login/register.  
- `lib/screens/` — Login, Register, Home, Ride/Delivery creation & detail, History, etc.  
- `lib/models/` — Modèles (User, Ride, Delivery) à partir des réponses API.

Pour le **client** : une base URL type `http://10.0.2.2:3000/api/v1` (émulateur Android) ou `http://localhost:3000/api/v1` (iOS sim) ; en prod, remplacer par l’URL du serveur.

---

## 7. Rappel

- **App client** = Flutter, dossier **`app-client/`**.  
- **App chauffeur** = Flutter, dossier **`app-driver/`**.  
- **Admin** = dashboard React, dossier **`Admin-dashboard/`**.  
- Ce document sert de référence API pour brancher **app-client** et **app-driver** sur le backend.
