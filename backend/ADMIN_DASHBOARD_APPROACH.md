# Approche Dashboard Admin

## 1. Bug login (corrigé)

L’appel à `successResponse` utilisait les arguments dans le mauvais ordre :  
`successResponse(res, data, message, statusCode)`  
La route login passait `(res, result, 200, 'Login successful')` au lieu de `(res, result, 'Login successful', 200)`.  
C’est corrigé ; les autres routes concernées (refresh, logout, wallet, users) le sont aussi.

**Test :**
```bash
curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@bikeride.pro","password":"Admin123!"}'
```
Réponse attendue : `{"success":true,"message":"Login successful","data":{"user":...,"token":"...","refreshToken":"..."}}`

---

## 2. Comment faire le dashboard admin (frontend)

Deux options réalistes :

### Option A : SPA légère (recommandée)

- **Stack** : Vite + React (ou Vue) dans un dossier dédié, ex. `admin-dashboard/` à la racine du projet (ou dans `Bike/`).
- **Fonctionnement** :
  - Page **Login** : formulaire email/mot de passe → `POST /api/v1/auth/login` → stocker le token (localStorage ou cookie httpOnly si on ajoute une route backend pour le cookie).
  - Après login, redirection vers le dashboard.
  - **Dashboard** : `GET /api/v1/admin` → afficher cartes (nombre users, drivers, courses, livraisons, revenus, drivers en attente) + liste des dernières courses.
  - **Utilisateurs** : `GET /api/v1/admin/users` avec filtres (role, status) + tableau + bouton pour changer le statut (`PUT /api/v1/admin/users/:id/status`).
  - **Drivers** : `GET /api/v1/admin/drivers` + tableau + bouton Vérifier / Rejeter (`PUT /api/v1/admin/drivers/:id/verify`).
  - **Tarifs** : `GET /api/v1/admin/pricing` + formulaire d’édition par config (`PUT /api/v1/admin/pricing/:id`).
  - **Audit** : `GET /api/v1/admin/audit` avec filtres + tableau des logs.
- **CORS** : le backend autorise déjà l’origine (CORS_ORIGIN ou `*`). En prod, définir une origine précise pour le dashboard.
- **Auth** : chaque requête API envoie `Authorization: Bearer <token>`. Si 401, rediriger vers la page login.

Avantages : une vraie UI, réutilisable, évolutive (graphiques, exports, etc.).

### Option B : Pages HTML + JS minimal (sans build)

- **Stack** : quelques fichiers HTML + JS vanilla (ou Alpine.js) servis par Express (`express.static('public')`) ou depuis un sous-dossier `public/admin/`.
- **Fonctionnement** : même flux (login → token → appels API), mais une page par écran (dashboard.html, users.html, etc.) et `fetch()` vers l’API.
- Avantage : pas de build, déploiement simple.  
- Inconvénient : moins confortable pour faire évoluer l’UI (tableaux, filtres, formulaires).

---

## 3. Recommandation

- **Court terme** : Option A avec Vite + React (ou Vue) dans un dossier `admin-dashboard/` : structure claire, composants réutilisables, un seul point d’entrée (router) pour Login, Dashboard, Users, Drivers, Pricing, Audit.
- **Backend** : rien à changer ; l’API admin est prête. Il suffit d’une app frontend qui appelle ces endpoints avec le token après login.

Si tu veux, on peut détailler la structure du projet (dossiers, routes frontend, exemple de composant Login + appel API et stockage du token) ou partir directement sur la création du squelette `admin-dashboard/` (Vite + React).
