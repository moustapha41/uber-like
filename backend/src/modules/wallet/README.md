# Module Wallet - Portefeuille Électronique

## 📋 Vue d'ensemble

Ce module gère le portefeuille électronique pour tous les services (Courses, Livraisons, Covoiturage). Il permet les transactions (débits/crédits) et l'historique.

## 🗄️ Schéma de Base de Données

### Tables principales

#### **wallets**
- Portefeuille par utilisateur
- Champs : `user_id`, `balance`, `currency` (XOF)
- Solde ne peut pas être négatif (contrainte DB)

#### **transactions**
- Historique de toutes les transactions
- Types : `credit`, `debit`, `refund`, `commission`, `withdrawal`, `deposit`
- Référence à la source (`reference_type`, `reference_id`)
- Statuts : `pending`, `completed`, `failed`, `cancelled`

## 🚀 API Endpoints

### Utilisateur

**GET** `/api/v1/wallet/balance`
- Récupère le solde de l'utilisateur connecté
- Auth: Requis
- Response: `{ balance, currency, wallet_id }`

**GET** `/api/v1/wallet/transactions`
- Historique des transactions
- Auth: Requis
- Query: `type?`, `status?`, `reference_type?`, `limit?`, `offset?`
- Response: `[{ transaction }]`

**POST** `/api/v1/wallet/withdraw`
- Retrait depuis le wallet
- Auth: Requis
- Body: `{ amount, description? }`
- Response: `{ transaction }`

### Admin

**POST** `/api/v1/wallet/deposit`
- Dépôt manuel (admin uniquement)
- Auth: Requis (admin)
- Body: `{ user_id, amount, description? }`
- Response: `{ transaction }`

## 💼 Services

### `wallet.service.js`

#### Méthodes principales :

1. **`createWallet(userId)`**
   - Crée un wallet pour un utilisateur
   - Solde initial : 0.00 FCFA

2. **`getWallet(userId)`**
   - Récupère le wallet d'un utilisateur
   - Crée automatiquement s'il n'existe pas

3. **`getBalance(userId)`**
   - Récupère le solde en FCFA

4. **`credit(userId, amount, options)`**
   - Crédite un wallet
   - Transaction atomique avec verrou DB
   - Crée une entrée dans `transactions`

5. **`debit(userId, amount, options)`**
   - Débite un wallet
   - Vérifie solde suffisant
   - Transaction atomique avec verrou DB

6. **`processRidePayment(rideId, clientId, amount, driverId, commissionRate)`** ⭐
   - Traite le paiement d'une course
   - Débite le client
   - Crédite le driver (moins commission)
   - Crée transaction commission
   - **Utilisé dans `completeRide()`**

7. **`getTransactions(userId, filters)`**
   - Historique avec filtres
   - Supporte pagination

8. **`hasSufficientBalance(userId, amount)`**
   - Vérifie si solde suffisant

## 🔗 Intégration avec Module Rides

### Dans `completeRide()`

```javascript
// Vérifier solde
const hasBalance = await walletService.hasSufficientBalance(clientId, finalFare);

if (hasBalance) {
  // Paiement automatique
  await walletService.processRidePayment(
    rideId,
    clientId,
    finalFare,
    driverId,
    commissionRate
  );
  
  // Mettre à jour statut paiement
  await pool.query(
    `UPDATE rides SET payment_status = 'PAID', status = 'PAID' WHERE id = $1`,
    [rideId]
  );
} else {
  // Demander paiement
  await notificationService.sendPaymentRequest(clientId, rideId, finalFare);
}
```

## 🔐 Sécurité

### Transactions Atomiques
- Utilisation de `BEGIN` / `COMMIT` / `ROLLBACK`
- Verrous DB (`SELECT ... FOR UPDATE`)
- Protection contre race conditions

### Validation
- Solde ne peut pas être négatif (contrainte DB)
- Vérification solde avant débit
- Montant toujours positif

## 📊 Workflow Paiement Course

```
1. Driver termine course (COMPLETED)
   ↓
2. Vérifier solde client
   ↓
3a. Si solde suffisant:
    - Débiter client
    - Créditer driver (moins commission)
    - Statut → PAID
   ↓
3b. Si solde insuffisant:
    - Notification paiement
    - Statut → PAYMENT_PENDING
```

## 🛠️ Installation

1. **Créer les tables** :
```bash
psql -U postgres -d bikeride_pro -f src/modules/wallet/models.sql
```

2. **⚠️ IMPORTANT** : Créer les tables Users **AVANT** Wallet :
```bash
# 1. Users (d'abord)
psql -U postgres -d bikeride_pro -f src/modules/users/models.sql

# 2. Wallet (ensuite)
psql -U postgres -d bikeride_pro -f src/modules/wallet/models.sql
```

3. **Routes intégrées** :
```javascript
app.use(`/api/${API_VERSION}/wallet`, require('./modules/wallet/routes'));
```

## ✅ État Actuel

- ✅ Schéma DB complet
- ✅ Service wallet complet
- ✅ Routes API créées
- ✅ Intégration avec module Rides
- ✅ Transactions atomiques
- ✅ Protection race conditions

---

**Le module Wallet est prêt et intégré avec le module Rides !**

