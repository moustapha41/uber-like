# Déploiement en production – BikeRide Pro (uber-like)

Guide pour mettre en production le **backend** et l’**Admin-dashboard** sur un serveur (VPS, machine dédiée, etc.).

---

## 1. Prérequis sur le serveur

- **Node.js** 18 ou 20 (LTS recommandé). Node 24 peut générer des warnings sur certains packages (ex. opossum).
- **PostgreSQL** 14+
- **Redis** (optionnel, selon les fonctionnalités utilisées)
- **npm** (livré avec Node)

---

## 2. Backend

### 2.1 Base de données PostgreSQL

**Si votre système a l’utilisateur `postgres`** (Linux classique) :

```bash
# Éviter le caractère ! dans le mot de passe en one-liner (bash l’interprète mal)
sudo -u postgres psql -c "CREATE USER bikeride_pro WITH PASSWORD 'VOTRE_MOT_DE_PASSE';"
sudo -u postgres psql -c "CREATE DATABASE bikeride_pro OWNER bikeride_pro;"
```

**Si vous voyez « unknown user postgres »** : vous êtes peut‑être en root ou sur un système sans utilisateur `postgres`. Connectez-vous à PostgreSQL avec l’utilisateur par défaut (souvent `postgres` ou `root`) :

```bash
# Essayer d’abord (en tant que root)
psql -U postgres -h localhost -c "CREATE USER bikeride_pro WITH PASSWORD 'VOTRE_MOT_DE_PASSE';"
psql -U postgres -h localhost -c "CREATE DATABASE bikeride_pro OWNER bikeride_pro;"
```

Si ça échoue, ouvrez une session interactive et exécutez les commandes SQL à la main (pratique si le mot de passe contient `!` ou `'`) :

```bash
psql -U postgres -h localhost
```

Puis dans `psql` :

```sql
CREATE USER bikeride_pro WITH PASSWORD 'ChangeMoi123!';
CREATE DATABASE bikeride_pro OWNER bikeride_pro;
\q
```

(Adapter le mot de passe et le nom de base si vous les changez dans `.env`.)

### 2.2 Fichier d’environnement

Dans le dossier du backend (ex. `~/uber-like/backend`) :

```bash
cd ~/uber-like/backend

# Créer .env à partir du template production
cp .env.production .env

# Éditer et remplir les valeurs réelles
nano .env   # ou vim / vi
```

À renseigner au minimum :

- `DB_PASSWORD` : mot de passe PostgreSQL
- `JWT_SECRET` : chaîne longue et aléatoire (ex. `openssl rand -base64 32`)
- `JWT_REFRESH_SECRET` : autre secret pour les refresh tokens
- `CORS_ORIGIN` : URL du dashboard admin (ex. `https://admin.votredomaine.com`)
- `APP_BASE_URL` : URL publique de l’API (ex. `https://api.votredomaine.com`)

### 2.3 Installation

```bash
npm install
```

### 2.4 Créer les tables (migration) — obligatoire avant le premier lancement

Sans cette étape, l’API renverra des erreurs du type **« relation "users" does not exist »**. À exécuter **une fois** sur une base vide :

```bash
NODE_ENV=production node src/config/migrate.js
```

(En dev : `node src/config/migrate.js`.)

### 2.5 Premier lancement et compte admin

Démarrer le serveur :

```bash
NODE_ENV=production node src/app.js
```

Créer un compte admin (à faire une fois après la migration) :

```bash
# Optionnel : définir email/mot de passe admin
# export ADMIN_EMAIL=admin@votredomaine.com
# export ADMIN_PASSWORD=VotreMotDePasseAdmin
NODE_ENV=production node scripts/seed-admin.js
```

En production, faire tourner le backend avec un process manager (PM2, systemd, etc.) :

**Exemple avec PM2 :**

```bash
npm install -g pm2
NODE_ENV=production pm2 start src/app.js --name bikeride-api
pm2 save && pm2 startup
```

---

## 3. Admin-dashboard (Vite + React)

L’admin dashboard appelle l’API via la variable `VITE_API_URL`. En production, il faut la définir **avant** le build.

### 3.1 Build pour la production

Dans le dossier du dashboard :

```bash
cd ~/uber-like/Admin-dashboard

# Définir l’URL de l’API (sans slash final)
export VITE_API_URL=https://api.votredomaine.com/api/v1
# ou en HTTP : export VITE_API_URL=http://IP_DU_SERVEUR:3000/api/v1

npm install
npm run build
```

Le build génère le dossier `dist/`.

### 3.2 Servir les fichiers statiques

- **Option A – Même machine que l’API (ex. Nginx)**  
  Configurer un virtual host qui sert les fichiers de `Admin-dashboard/dist` pour le domaine du dashboard (ex. `https://admin.votredomaine.com`). L’API peut être sur le même serveur (ex. `https://api.votredomaine.com` ou `:3000`).

- **Option B – Test rapide sur le serveur**  
  Depuis `Admin-dashboard` :  
  `npx serve -s dist -l 5173`  
  Puis ouvrir `http://IP_DU_SERVEUR:5173`. Ne pas utiliser en production longue durée sans reverse proxy et HTTPS.

---

## 4. Résumé des commandes (copier-coller)

Sur le serveur, après `git clone` :

```bash
# Backend
cd ~/uber-like/backend
cp .env.production .env
# Éditer .env (DB_PASSWORD, JWT_SECRET, CORS_ORIGIN, APP_BASE_URL)
npm install
NODE_ENV=production node src/config/migrate.js   # créer les tables (une fois)
NODE_ENV=production node scripts/seed-admin.js  # créer l’admin (une fois)
NODE_ENV=production pm2 start src/app.js --name bikeride-api

# Admin-dashboard
cd ~/uber-like/Admin-dashboard
export VITE_API_URL=https://VOTRE_API/api/v1
npm install && npm run build
# Puis servir dist/ (Nginx, serve, etc.)
```

---

## 5. Vérifications

- **Backend** : il n’y a pas de route à la racine, donc `GET /` renvoie 404 — c’est normal. Tester plutôt :
  - `curl http://localhost:3000/health` → doit renvoyer `{"status":"ok","message":"BikeRide Pro API is running"}`
  - `curl http://localhost:3000/api/v1/auth/login` (sans body) → une réponse JSON (erreur 400 ou 422) confirme que l’API répond.
- **Admin** : ouvrir l’URL du dashboard, se connecter avec le compte créé par `seed-admin.js` (par défaut `admin@bikeride.pro` / `Admin123!` — à changer en prod via `ADMIN_EMAIL` / `ADMIN_PASSWORD` lors du seed).

---

## 6. Notes

- Le fichier **`.env`** ne doit jamais être commité (il est dans `.gitignore`). Seuls `.env.example` et `.env.production` sont des modèles.
- En production, utiliser **HTTPS** (certificat Let’s Encrypt avec Nginx/Caddy, etc.).
- Si vous utilisez **PayTech** ou des **clés cartes** (Mapbox/Google), les ajouter dans `.env` comme indiqué dans `.env.production`.
