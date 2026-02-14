# Module Payment - PayTech (Mobile Money)

Intégration **PayTech** (paytech.sn) pour paiements Mobile Money (Orange Money, Wave, etc.) en **mode test** puis production.

## Configuration

1. **Créer la table** (une fois). Si tu as l’erreur « Peer authentication failed », utilise le mot de passe et `-h localhost` :
   ```bash
   PGPASSWORD=ton_mot_de_passe_postgres psql -U postgres -h localhost -d bikeride_pro -f src/modules/payment/models.sql
   ```
   Remplace par le vrai mot de passe (celui de `DB_PASSWORD` dans `.env`). Exemple :  
   `PGPASSWORD='ChangeMoi123!' psql -U postgres -h localhost -d bikeride_pro -f src/modules/payment/models.sql`

2. **Variables d'environnement** (`.env`) :
   - `PAYTECH_API_KEY` : clé API (dashboard PayTech)
   - `PAYTECH_API_SECRET` : clé secrète
   - `PAYTECH_ENV` : `test` (sandbox) ou `prod`
   - `APP_BASE_URL` : URL publique de l’API (pour l’IPN), ex. `https://api.mondomaine.com`

En mode test, seul un montant aléatoire 100–150 FCFA est débité (doc PayTech).

## Endpoints

| Méthode | Route | Auth | Description |
|--------|--------|------|-------------|
| POST | `/api/v1/payment/initiate` | Oui | Initie un paiement. Body: `amount`, `reference_type` (ride \| delivery \| wallet_deposit), `reference_id`, `success_url?`, `cancel_url?`, `target_payment?`. Retourne `redirect_url` (rediriger le client). |
| POST | `/api/v1/payment/ipn` | Non | Webhook PayTech (IPN). Appelé par PayTech pour notifier succès/échec. |
| GET | `/api/v1/payment/status/:ref_command` | Oui | Statut d’une intention (ex. `RIDE-123`). |

## Flux

1. **Course/Livraison terminée** avec `payment_method: 'mobile_money'` → `payment_status = PAYMENT_PENDING`.
2. **Client** (ou app) appelle **POST /payment/initiate** avec `reference_type: 'ride'`, `reference_id: rideId`, `amount: fare_final`.
3. Backend crée une `payment_intent`, appelle PayTech **request-payment**, retourne **redirect_url**.
4. **Client** est redirigé vers la page PayTech, paie (Orange Money, Wave, etc.).
5. **PayTech** appelle **POST /payment/ipn** avec le résultat. Backend met à jour `payment_intent`, puis `rides`/`deliveries` → `PAID` ou `PAYMENT_FAILED`, et crédite le driver si succès.

## Référence

- Doc PayTech : https://doc.paytech.sn/
