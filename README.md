<<<<<<< HEAD
# uber-like
=======
# BikeRide Pro - Backend

Application de MotoTaxi, Livraison & Covoiturage

## Architecture

- **Backend** : Node.js + Express (API REST modulaire)
- **Base de données** : PostgreSQL + Redis (cache)
- **Services** :
  - 🏍️ Courses de mototaxi (Service Professionnel)
  - 📦 Livraison de colis (Service Professionnel)
  - 🚗 Covoiturage urbain/interurbain (Service Communautaire)

## Structure du Projet

```
backend/
├── src/
│   ├── modules/
│   │   ├── auth/           # Authentification
│   │   ├── rides/          # Service Course (Pro)
│   │   ├── deliveries/     # Service Livraison (Pro)
│   │   ├── carpool/        # Service Covoiturage (Communautaire)
│   │   ├── wallet/         # Portefeuille électronique
│   │   ├── users/          # Gestion utilisateurs
│   │   ├── admin/          # Dashboard Admin
│   │   ├── notifications/  # Notifications Push & SMS
│   │   ├── audit/          # Logs & Traçabilité
│   │   ├── maps/           # Intégration Cartographie
│   │   └── payment/        # Paiement (Mobile Money)
│   ├── config/             # Configuration
│   ├── middleware/         # Middlewares
│   ├── utils/              # Utilitaires
│   └── app.js              # Point d'entrée
├── tests/
└── package.json
```

## Services Tiers

- **Cartographie** : Google Maps/Mapbox, OpenStreetMap
- **Paiement** : Mobile Money
- **SMS** : Twilio/Africas Talking
- **Notifications Push** : Firebase Cloud Messaging

## Plan de Déploiement

### Phase 1 (MVP - 2 mois)
- Backend core + API (Modules auth, wallet, pro-services)
- Application Client (Onglet Courses uniquement)
- Application Driver (Courses uniquement)
- Dashboard Admin basique
- Système paiement (Wallet, Mobile Money)
- Tracking GPS

### Phase 2 (3-4 mois)
- Livraison de colis
- Covoiturage urbain
- Système parrainage
- Analytics avancé

### Phase 3 (5-6 mois)
- Covoiturage interurbain
- Driver Pro program
- API publique pour partenaires
- Système de fidélité

>>>>>>> b91528e (my-app)
