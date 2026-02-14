# Module Auth - Authentification

## 📋 Vue d'ensemble

Ce module gère l'authentification des utilisateurs (register, login, tokens JWT). Il est **critique** car tous les autres modules en dépendent pour sécuriser les endpoints.

## 🚀 API Endpoints

### Public

**POST** `/api/v1/auth/register`
- Enregistre un nouvel utilisateur
- Body: `{ email, password, phone?, first_name?, last_name?, role? }`
- Response: `{ user, token, refreshToken }`
- Validation:
  - Email valide
  - Password min 6 caractères
  - Role: 'client' ou 'driver' (défaut: 'client')

**POST** `/api/v1/auth/login`
- Connecte un utilisateur
- Body: `{ email, password }`
- Response: `{ user, token, refreshToken }`
- Validation:
  - Email valide
  - Password requis

**POST** `/api/v1/auth/refresh`
- Rafraîchit un token
- Body: `{ refreshToken }`
- Response: `{ token, refreshToken }`

**POST** `/api/v1/auth/verify-email`
- Vérifie l'email d'un utilisateur (avec token)
- Body: `{ token }`
- ⚠️ À implémenter

### Authentifié

**POST** `/api/v1/auth/logout`
- Déconnecte un utilisateur
- Auth: Requis
- Response: `{ message: 'Logout successful' }`

**GET** `/api/v1/auth/me`
- Récupère les informations de l'utilisateur connecté
- Auth: Requis
- Response: `{ user, driver_profile? }`

## 💼 Service

### `auth.service.js`

#### Méthodes principales :

1. **`register(userData)`**
   - Crée un nouvel utilisateur via `usersService.createUser()`
   - Génère token et refreshToken
   - Retourne user (sans password_hash), token, refreshToken

2. **`login(email, password)`**
   - Vérifie credentials via `usersService.verifyCredentials()`
   - Vérifie que le compte est actif
   - Génère token et refreshToken
   - Met à jour `last_login_at`

3. **`refreshToken(refreshToken)`**
   - Vérifie le refresh token
   - Génère de nouveaux tokens
   - Vérifie que le compte est toujours actif

4. **`logout(userId)`**
   - Log la déconnexion
   - ⚠️ Pour invalidation côté serveur, créer une table `blacklist_tokens`

5. **`generateToken(user)`**
   - Génère un JWT avec payload: `{ userId, email, role }`
   - Expiration: 7 jours (configurable via `JWT_EXPIRES_IN`)

6. **`generateRefreshToken(user)`**
   - Génère un refresh token
   - Expiration: 30 jours (configurable via `JWT_REFRESH_EXPIRES_IN`)

7. **`verifyToken(token)`**
   - Vérifie un token JWT
   - Utilisé par le middleware `authenticate`

## 🔐 Sécurité

### Tokens JWT

- **Access Token** : Expiration courte (7 jours par défaut)
  - Payload: `{ userId, email, role }`
  - Secret: `JWT_SECRET`
  - Utilisé pour authentifier les requêtes

- **Refresh Token** : Expiration longue (30 jours par défaut)
  - Payload: `{ userId, type: 'refresh' }`
  - Secret: `JWT_REFRESH_SECRET` (ou `JWT_SECRET` si non défini)
  - Utilisé pour obtenir un nouveau access token

### Validation

- **express-validator** pour toutes les entrées
- Validation email, password, phone
- Rate limiting sur register/login (100 req/15min)

### Protection

- Mots de passe hashés avec **bcryptjs** (10 salt rounds)
- Protection contre les tentatives de connexion échouées
- Vérification que le compte est actif avant login
- Tokens vérifiés à chaque requête authentifiée

## 🔗 Intégration

### Avec Module Users

- Utilise `usersService.createUser()` pour register
- Utilise `usersService.verifyCredentials()` pour login
- Utilise `usersService.getUserById()` pour refresh token

### Avec Middleware Auth

Le middleware `authenticate` vérifie :
- Présence du token dans header `Authorization: Bearer <token>`
- Validité du token (signature, expiration)
- Existence de l'utilisateur en DB
- Statut actif de l'utilisateur

### Format Token

```javascript
// Header
Authorization: Bearer <token>

// Payload décodé
{
  userId: 123,
  email: "user@example.com",
  role: "client",
  iat: 1234567890,
  exp: 1234567890
}
```

## 📊 Variables d'Environnement

```env
# JWT
JWT_SECRET=your-secret-key-change-in-production
JWT_EXPIRES_IN=7d
JWT_REFRESH_SECRET=your-refresh-secret-key
JWT_REFRESH_EXPIRES_IN=30d
```

## 🛠️ Installation

1. **Variables d'environnement** :
   - Ajouter `JWT_SECRET` dans `.env`
   - Optionnel: `JWT_EXPIRES_IN`, `JWT_REFRESH_SECRET`, `JWT_REFRESH_EXPIRES_IN`

2. **Routes intégrées** :
   - Déjà intégrées dans `app.js` :
   ```javascript
   app.use(`/api/${API_VERSION}/auth`, require('./modules/auth/routes'));
   ```

3. **Dépendances** :
   - ✅ `jsonwebtoken` (déjà dans package.json)
   - ✅ `bcryptjs` (déjà dans package.json)
   - ✅ `express-validator` (déjà dans package.json)

## 📝 Exemples d'Utilisation

### Register

```bash
curl -X POST http://localhost:3000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "client@example.com",
    "password": "password123",
    "phone": "+221771234567",
    "first_name": "John",
    "last_name": "Doe",
    "role": "client"
  }'
```

Response:
```json
{
  "success": true,
  "data": {
    "user": {
      "id": 1,
      "email": "client@example.com",
      "phone": "+221771234567",
      "first_name": "John",
      "last_name": "Doe",
      "role": "client",
      "status": "active"
    },
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  },
  "message": "User registered successfully"
}
```

### Login

```bash
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "client@example.com",
    "password": "password123"
  }'
```

### Utiliser le Token

```bash
curl -X GET http://localhost:3000/api/v1/users/profile \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

### Refresh Token

```bash
curl -X POST http://localhost:3000/api/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{
    "refreshToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  }'
```

## ✅ État Actuel

- ✅ Service auth complet
- ✅ Routes API complètes
- ✅ Intégration avec module Users
- ✅ Intégration avec middleware auth
- ✅ Validation des entrées
- ✅ Rate limiting
- ⏳ Vérification email (à implémenter)
- ⏳ Blacklist tokens pour logout (optionnel)

## 🔄 Workflow

```
1. User s'inscrit (POST /register)
   ↓
2. User créé dans DB + tokens générés
   ↓
3. User se connecte (POST /login)
   ↓
4. Tokens générés
   ↓
5. User utilise token dans header Authorization
   ↓
6. Middleware authenticate vérifie le token
   ↓
7. User accède aux endpoints protégés
   ↓
8. Token expire → User utilise refresh token
   ↓
9. Nouveaux tokens générés
```

---

**Le module Auth est prêt et permet l'authentification complète !**

