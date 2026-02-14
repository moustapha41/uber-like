# Spécification complète : Admin Dashboard + Backend + API

Document de référence pour développer le **dashboard admin** à part, puis le **brancher** au backend.  
Base URL API : `http://localhost:3000/api/v1` (ou la valeur de `VITE_API_URL` en prod).

---

# Partie 1 – Authentification (connexion admin)

Le dashboard doit d’abord obtenir un **JWT** via le login. Toutes les requêtes admin envoient ensuite ce token.

## 1.1 Login

| Élément | Détail |
|--------|--------|
| **Méthode** | `POST` |
| **URL** | `/auth/login` |
| **Headers** | `Content-Type: application/json` |
| **Body** | `{ "email": "string", "password": "string" }` |
| **Réponse 200** | `{ "success": true, "message": "Login successful", "data": { "user": { "id", "email", "phone", "first_name", "last_name", "role", "status", "email_verified", "phone_verified" }, "token": "JWT...", "refreshToken": "JWT..." } }` |
| **Réponse 401** | `{ "success": false, "message": "Invalid email or password" }` |
| **Réponse 403** | Compte non actif : `{ "success": false, "message": "Account is ..." }` |

- Pour le dashboard : utiliser **uniquement** `data.token` et le stocker (ex. localStorage).
- Chaque requête admin doit envoyer : `Authorization: Bearer <data.token>`.
- Si une requête admin retourne **401** : supprimer le token et rediriger vers la page de login.

**Compte admin par défaut (après seed)** : `admin@bikeride.pro` / `Admin123!`.

---

# Partie 2 – Backend Admin (côté serveur)

## 2.1 Structure des fichiers

```
backend/
  src/
    app.js                    → Monte les routes /api/v1/admin
    middleware/auth.js        → authenticate + authorize('admin')
    modules/
      admin/
        routes.js             → Toutes les routes admin (déjà protégées)
        admin.service.js      → Délègue à users, pricing, audit + requêtes SQL dashboard
        README.md
        WORKFLOW_BACKEND.md
      users/
        users.service.js      → listUsers, updateUserStatus, listDrivers, updateDriverVerification
      rides/
        pricing.service.js    → getAllPricingConfigs, getPricingConfigById, updatePricingConfig
      audit/
        service.js            → getLogs(filters, limit, offset)
    config/database.js        → Pool PostgreSQL
```

## 2.2 Tables utilisées (PostgreSQL)

- **users** : id, email, phone, first_name, last_name, role, status, created_at, updated_at (liste users, statut).
- **driver_profiles** : user_id, is_verified, verification_status, verification_notes, is_online, total_rides, total_earnings, etc. (liste drivers, vérification).
- **driver_locations** : optionnel (position).
- **rides** : agrégations (nombre, revenus), dernières courses (id, ride_code, status, fare_final, created_at).
- **deliveries** : agrégations (nombre, revenus).
- **pricing_config** : id, service_type, base_fare, cost_per_km, cost_per_minute, commission_rate, max_distance_km, is_active, updated_at.
- **pricing_time_slots** : lié à pricing_config (plages horaires, multiplicateurs).
- **audit_logs** : id, user_id, action, entity_type, entity_id, details, created_at.

Aucune table propre au “dashboard” : tout passe par l’API admin.

## 2.3 Règles métier côté backend

- Toutes les routes sous `/api/v1/admin` exigent : **JWT valide** + **utilisateur avec `role === 'admin'`**.
- Liste users : champs retournés sans `password_hash`, avec pagination (limit, offset) et total.
- Liste drivers : jointure users + driver_profiles (et optionnellement driver_locations).
- Tarifs : une config par `service_type` (ride, delivery) ; mise à jour partielle (champs envoyés uniquement).
- Audit : filtres optionnels ; réponse paginée (logs + total).

---

# Partie 3 – Contrat API Admin (endpoints)

Format de réponse commun :  
- Succès : `{ "success": true, "message": "...", "data": ... }`  
- Erreur : `{ "success": false, "message": "..." }`  
- Codes HTTP : 200 (OK), 400 (validation / erreur métier), 401 (non authentifié), 403 (non autorisé), 404 (non trouvé), 500 (erreur serveur).

Toutes les requêtes admin doivent inclure : **`Authorization: Bearer <token>`**.

---

## 3.1 GET `/admin` — Dashboard (statistiques)

| Élément | Détail |
|--------|--------|
| **Query** | Aucun |
| **Réponse 200** | `"data"` est un objet avec la structure suivante : |

```json
{
  "users": {
    "total": 42,
    "clients": 30,
    "drivers": 11,
    "admins": 1
  },
  "rides": {
    "total": 150,
    "revenue": 450000
  },
  "deliveries": {
    "total": 25,
    "revenue": 85000
  },
  "pending_drivers_verification": 3,
  "recent_rides": [
    {
      "id": 1,
      "ride_code": "RIDE-2024-001",
      "status": "COMPLETED",
      "fare_final": 2500,
      "created_at": "2026-02-09T12:00:00.000Z"
    }
  ]
}
```

- **recent_rides** : au plus 5 dernières courses (ordre `created_at` DESC).

---

## 3.2 GET `/admin/users` — Liste des utilisateurs

| Élément | Détail |
|--------|--------|
| **Query** | `role` (optionnel) : `client` \| `driver` \| `admin` |
| | `status` (optionnel) : `active` \| `inactive` \| `suspended` \| `pending_verification` |
| | `limit` (optionnel, défaut 50, max 200) |
| | `offset` (optionnel, défaut 0) |
| **Réponse 200** | `"data"`: `{ "users": [ ... ], "total": number }` |

Chaque élément de **users** :

```json
{
  "id": 1,
  "email": "user@example.com",
  "phone": "+221770000001",
  "first_name": "Jean",
  "last_name": "Dupont",
  "role": "client",
  "status": "active",
  "created_at": "...",
  "updated_at": "..."
}
```

---

## 3.3 PUT `/admin/users/:id/status` — Modifier le statut d’un utilisateur

| Élément | Détail |
|--------|--------|
| **Params** | `id` : ID utilisateur (entier) |
| **Body** | `{ "status": "active" | "inactive" | "suspended" | "pending_verification" }` |
| **Réponse 200** | `"data"` : objet utilisateur mis à jour (même forme que dans la liste, sans password_hash) |
| **Réponse 404** | Utilisateur introuvable |

---

## 3.4 GET `/admin/drivers` — Liste des drivers

| Élément | Détail |
|--------|--------|
| **Query** | `status` (optionnel) : `active` \| `inactive` \| `suspended` |
| | `verified` (optionnel) : `true` \| `false` (booléen) |
| | `is_online` (optionnel) : `true` \| `false` |
| | `limit` (optionnel, max 200), `offset` (optionnel) |
| **Réponse 200** | `"data"` : **tableau** direct de drivers (pas `{ drivers, total }`). |

Chaque élément contient les champs **users** (id, email, phone, first_name, last_name, status) + champs **driver_profiles** (user_id, is_verified, verification_status, verification_notes, is_online, total_rides, total_earnings, etc.) + éventuellement lat, lng, last_location_update.

- **id** dans chaque ligne = `user_id` (ID de l’utilisateur driver).
- Pour “Vérifier / Rejeter”, utiliser cet **id** dans `PUT /admin/drivers/:id/verify`.

---

## 3.5 PUT `/admin/drivers/:id/verify` — Vérification driver

| Élément | Détail |
|--------|--------|
| **Params** | `id` : ID **utilisateur** du driver (user_id) |
| **Body** | `{ "verification_status": "pending" | "approved" | "rejected" | "suspended", "verification_notes": "string (optionnel, max 2000)" }` |
| **Réponse 200** | `"data"` : profil driver mis à jour (objet driver_profiles) |
| **Réponse 404** | Driver (profil) non trouvé |

---

## 3.6 GET `/admin/pricing` — Liste des configurations tarifaires

| Élément | Détail |
|--------|--------|
| **Query** | Aucun |
| **Réponse 200** | `"data"` : **tableau** de configs. |

Chaque config :

```json
{
  "id": 1,
  "service_type": "ride",
  "base_fare": 500,
  "cost_per_km": 300,
  "cost_per_minute": 50,
  "commission_rate": 20,
  "max_distance_km": 50,
  "is_active": true,
  "created_at": "...",
  "updated_at": "...",
  "time_slots": [
    { "id": 1, "start_time": "22:00", "end_time": "06:00", "multiplier": 1.2, "description": "Nuit" }
  ]
}
```

- **service_type** : `"ride"` (courses) ou `"delivery"` (livraisons).

---

## 3.7 GET `/admin/pricing/:id` — Détail d’une config tarifaire

| Élément | Détail |
|--------|--------|
| **Params** | `id` : ID de la config (entier) |
| **Réponse 200** | `"data"` : même structure qu’un élément du tableau de GET `/admin/pricing` (avec `time_slots`). |
| **Réponse 404** | Config non trouvée |

---

## 3.8 PUT `/admin/pricing/:id` — Mise à jour d’une config tarifaire

| Élément | Détail |
|--------|--------|
| **Params** | `id` : ID de la config |
| **Body** | Tous optionnels. Uniquement les champs à modifier : |
| | `base_fare` (number ≥ 0) |
| | `cost_per_km` (number ≥ 0) |
| | `cost_per_minute` (number ≥ 0) |
| | `commission_rate` (number 0–100) |
| | `max_distance_km` (number ≥ 0) |
| | `is_active` (boolean) |
| **Réponse 200** | `"data"` : config mise à jour (objet pricing_config, sans time_slots selon implémentation actuelle) |
| **Réponse 404** | Config non trouvée |

- Les **time_slots** ne sont pas modifiés par cet endpoint (uniquement la config principale).

---

## 3.9 GET `/admin/audit` — Logs d’audit

| Élément | Détail |
|--------|--------|
| **Query** | `entity_type` (optionnel, string) |
| | `entity_id` (optionnel) |
| | `user_id` (optionnel, entier) |
| | `action` (optionnel, string) |
| | `date_from` (optionnel, ISO 8601) |
| | `date_to` (optionnel, ISO 8601) |
| | `limit` (optionnel, défaut 100, max 500) |
| | `offset` (optionnel) |
| **Réponse 200** | `"data"`: `{ "logs": [ ... ], "total": number }` |

Chaque log :

```json
{
  "id": 1,
  "user_id": 5,
  "action": "ride_completed",
  "entity_type": "ride",
  "entity_id": 42,
  "details": {},
  "created_at": "2026-02-09T14:30:00.000Z"
}
```

---

# Partie 4 – Admin Dashboard (frontend) – à réaliser à part

## 4.1 Principes généraux

- **Authentification** : une seule page de **login** (email + mot de passe). Appel à `POST /auth/login`. Stocker `data.token` (ex. localStorage). Vérifier que `data.user.role === 'admin'` (optionnel mais recommandé).
- **Requêtes admin** : pour chaque appel à `/admin/*`, envoyer le header **`Authorization: Bearer <token>`**. En cas de **401** : supprimer le token et rediriger vers la page de login.
- **Base URL** : en dev, utiliser une variable d’environnement (ex. `VITE_API_URL`) pointant vers `http://localhost:3000/api/v1` (ou proxy équivalent). En prod, l’URL de l’API déployée.

## 4.2 Structure recommandée des écrans

1. **Login**  
   - Champs : email, mot de passe.  
   - Bouton : “Se connecter”.  
   - Comportement : `POST /auth/login` → si succès, enregistrer le token (et éventuellement l’utilisateur), rediriger vers la page d’accueil (dashboard). Sinon afficher le message d’erreur (`message`).

2. **Layout global (après login)**  
   - Menu ou onglets : Dashboard, Utilisateurs, Drivers, Tarifs, Audit.  
   - Bouton “Déconnexion” : supprimer le token et rediriger vers Login.  
   - Zone de contenu : affichage de la route courante (voir ci‑dessous).

3. **Dashboard (page d’accueil)**  
   - Données : **GET `/admin`**.  
   - Afficher :  
     - Nombre total d’utilisateurs (et éventuellement répartition clients / drivers / admins).  
     - Nombre de courses et revenus associés.  
     - Nombre de livraisons et revenus associés.  
     - Nombre de drivers en attente de vérification.  
     - Tableau ou liste des “dernières courses” (recent_rides) : code, statut, montant, date.

4. **Utilisateurs**  
   - Données : **GET `/admin/users`** avec query `role`, `status`, `limit`, `offset`.  
   - Afficher : filtres (rôle, statut), tableau (id, email, nom, rôle, statut), total.  
   - Actions :  
     - “Suspendre” : **PUT `/admin/users/:id/status`** avec `{ "status": "suspended" }`.  
     - “Réactiver” : même endpoint avec `{ "status": "active" }`.  
   - Après action réussie : recharger la liste (ou mettre à jour l’état local).

5. **Drivers**  
   - Données : **GET `/admin/drivers`** (avec éventuels filtres `status`, `verified`, `is_online`).  
   - Afficher : tableau (id user, email, nom, statut de vérification, en ligne, etc.).  
   - Actions :  
     - “Approuver” : **PUT `/admin/drivers/:id/verify`** avec `{ "verification_status": "approved", "verification_notes": "..." }`.  
     - “Rejeter” : même endpoint avec `{ "verification_status": "rejected", "verification_notes": "..." }`.  
   - **:id** = `id` de l’utilisateur (colonne `id` dans chaque ligne du tableau).

6. **Tarifs**  
   - Données : **GET `/admin/pricing`**.  
   - Afficher : une carte ou section par config (ride / delivery) : id, service_type, base_fare, cost_per_km, cost_per_minute, commission_rate, max_distance_km, is_active. Optionnel : time_slots en lecture seule.  
   - Actions : formulaire ou champs éditables par config. À la modification (blur ou “Enregistrer”) : **PUT `/admin/pricing/:id`** avec uniquement les champs modifiés (number ou boolean).  
   - Gérer les erreurs (404, 400) et le feedback (succès / erreur).

7. **Audit**  
   - Données : **GET `/admin/audit`** avec query optionnelles : `entity_type`, `user_id`, `action`, `date_from`, `date_to`, `limit`, `offset`.  
   - Afficher : filtres + tableau des logs (date, user_id, action, entity_type, entity_id, éventuellement details).  
   - Pagination : utiliser `limit` / `offset` et `total` pour afficher les pages ou “Charger plus”.

## 4.3 Récapitulatif des appels API depuis le dashboard

| Écran      | Méthode | Endpoint                      | Rôle |
|------------|--------|-------------------------------|------|
| Login      | POST   | `/auth/login`                 | Obtenir le token |
| Dashboard  | GET    | `/admin`                      | Stats + recent_rides |
| Utilisateurs | GET  | `/admin/users`                | Liste + total |
| Utilisateurs | PUT  | `/admin/users/:id/status`     | Changer statut |
| Drivers    | GET    | `/admin/drivers`              | Liste |
| Drivers    | PUT    | `/admin/drivers/:id/verify`   | Approuver / Rejeter |
| Tarifs     | GET    | `/admin/pricing`             | Liste des configs |
| Tarifs     | PUT    | `/admin/pricing/:id`         | Mettre à jour une config |
| Audit      | GET    | `/admin/audit`               | Logs + total |

- Tous les endpoints admin nécessitent **Authorization: Bearer &lt;token&gt;**.
- Réponses : toujours `{ success, message, data? }`. En cas d’erreur, afficher `message`.

---

# Partie 5 – Branchement du dashboard au backend

Quand le dashboard est prêt (même dans un autre dépôt ou un autre dossier) :

1. **URL de l’API**  
   - En dev : soit **proxy** (ex. Vite `proxy: { '/api': 'http://localhost:3000' }`) avec des appels vers `/api/v1/...`, soit variable d’environnement (ex. `VITE_API_URL=http://localhost:3000/api/v1`).  
   - En prod : définir `VITE_API_URL` (ou équivalent) vers l’URL réelle de l’API (ex. `https://api.mondomaine.com/api/v1`).

2. **CORS**  
   - Le backend doit autoriser l’origine du dashboard (header `Origin`). Déjà configuré côté backend (CORS). Si le dashboard est sur un autre domaine, ajouter cette origine dans la config CORS du backend.

3. **Token**  
   - Après login, stocker `data.token` et l’envoyer dans **chaque** requête vers `/admin/*` avec le header **`Authorization: Bearer <token>`**.  
   - Gérer **401** : supprimer le token et rediriger vers la page de login.

4. **Forme des réponses**  
   - Toujours lire `res.success` et `res.data` (ou `res.message` en erreur).  
   - Pour **GET /admin/drivers**, `data` est un **tableau** directement (pas `data.drivers`).  
   - Pour **GET /admin/users**, `data` est **`{ users, total }`**.  
   - Pour **GET /admin/audit**, `data` est **`{ logs, total }`**.

5. **Tests rapides**  
   - Créer un compte admin (backend : `npm run seed:admin`).  
   - Depuis le dashboard : login avec ce compte, puis ouvrir chaque écran (Dashboard, Utilisateurs, Drivers, Tarifs, Audit) et vérifier que les données s’affichent et que les actions (changer statut, vérifier driver, modifier tarif) fonctionnent.

---

# Résumé

- **Backend** : module `admin` sous `/api/v1/admin`, auth JWT + rôle admin, délégation aux services users, pricing, audit et requêtes SQL pour le dashboard.  
- **API** : ce document décrit tous les endpoints (auth login + admin) avec paramètres, body et structure de `data`.  
- **Dashboard** : login, layout, 5 écrans (Dashboard, Utilisateurs, Drivers, Tarifs, Audit) avec les appels API et actions listés.  
- **Branchement** : configurer l’URL de l’API, CORS si besoin, gestion du token et des 401, puis vérifier chaque écran et action.

Tu peux développer le dashboard entièrement à part en te basant sur ce spec ; quand tu veux brancher, on pourra détailler les points 1 à 5 (URL, CORS, token, parsing des réponses, tests) pas à pas.
