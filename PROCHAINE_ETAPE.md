# Prochaine étape — Branchement des apps Flutter au backend

**Fait (app-client)**  
- Config API : `lib/core/network/api_config.dart` (baseUrl), `env.json` → `BIKERIDE_API_BASE_URL`.  
- Client HTTP : `lib/core/network/api_client.dart` (Dio + token + 401).  
- Auth : `lib/services/auth_service.dart` (login, register, token stocké, `apiClient` exposé).  
- Écran connexion : `AuthenticationScreen` appelle le backend (login/register), redirection vers home si succès.  
- Splash : vérifie le token stocké et envoie vers home si connecté, sinon vers l’écran d’auth.  
- **Rides** : `lib/services/rides_service.dart` (estimate, create, getMyRides, getById).  
- **Deliveries** : `lib/services/deliveries_service.dart` (estimate, create, getMyDeliveries, getById).  
- **Nouvelle course** : `RideBookingScreen` (départ/arrivée fixes Dakar, bouton Estimer → Réserver), route `/ride-booking-screen`.  
- **Nouvelle livraison** : `DeliveryOrderScreen` (adresses + colis, Estimer → Demander), route `/delivery-order-screen`.  
- Depuis l’accueil, les boutons « Course » et « Livraison » ouvrent ces écrans.

**À faire ensuite**

1. **app-client**  
   - Historique : écran listant `GET /rides` et `GET /deliveries`.  
   - Détail course/livraison : `GET /rides/:id`, `GET /deliveries/:id`, annulation si besoin.

2. **app-driver**  
   - Même couche API (ApiConfig, ApiClient, AuthService avec `role: 'driver'`).  
   - Connexion puis écran « En ligne » : `PUT /users/drivers/:id/status`.  
   - Liste des demandes : `GET /rides/driver/available`, `GET /deliveries/driver/available`.  
   - Accepter / suivre course ou livraison (accept, arrived, start, complete, etc.).

3. **Lancer**  
   - Backend : `cd backend && npm start`.  
   - app-client : `cd app-client && flutter run` (émulateur Android : baseUrl 10.0.2.2 par défaut ; iOS : `flutter run --dart-define=BIKERIDE_API_BASE_URL=http://127.0.0.1:3000/api/v1`).

Référence API : **SPEC_APP_CLIENT_CHAUFFEUR_FLUTTER.md**.
