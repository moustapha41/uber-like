# Tests - Module Rides

## 📋 Scénarios de Test

9 scénarios complets pour valider le module de courses :

1. **Scenario 1** : Course normale (happy path)
   - Création → Acceptation → Trajet → Paiement → Notation
   - Vérification verrous DB, WebSocket, prix final

2. **Scenario 2** : Annulation par le client
   - Annulation avant démarrage
   - Libération du driver
   - Idempotency

3. **Scenario 3** : Timeouts système
   - Timeout NO_DRIVER (2 min)
   - Timeout CLIENT_NO_SHOW (7 min)
   - Survie au redémarrage serveur

4. **Scenario 4** : Race condition
   - 10 drivers acceptent simultanément
   - Un seul doit réussir

5. **Scenario 5** : WebSocket flow complet
   - Connexion client/driver
   - Tracking GPS temps réel
   - Validation autorisation

6. **Scenario 6** : Rate Limiting
   - Limite création courses
   - Limite acceptation

7. **Scenario 7** : Idempotency
   - Double acceptation
   - Double paiement
   - Double notation

8. **Scenario 8** : Calcul de prix
   - Estimation initiale
   - Règle de tolérance (+10%)
   - Multiplicateurs horaires

9. **Scenario 9** : Libération driver
   - Après COMPLETED
   - Après annulations
   - Disponibilité immédiate

## 🚀 Exécution des Tests

```bash
# Installer les dépendances de test
npm install --save-dev jest supertest

# Exécuter tous les tests
npm test

# Exécuter un scénario spécifique
npm test -- scenario1-happy-path.test.js

# Avec couverture
npm test -- --coverage
```

## 📝 Configuration

Créer un fichier `.env.test` :

```env
NODE_ENV=test
DB_NAME=bikeride_pro_test
JWT_SECRET=test-secret
```

## ✅ Critères de Validation

Chaque scénario vérifie :
- ✅ Statuts corrects à chaque étape
- ✅ Libération des ressources (drivers)
- ✅ Protection contre race conditions
- ✅ Idempotency fonctionnelle
- ✅ Timeouts gérés correctement
- ✅ Prix calculés selon les règles
- ✅ WebSocket fonctionnel

