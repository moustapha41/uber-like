# Audit : à quoi ça sert et pourquoi

## En une phrase

L’**Audit** enregistre **qui a fait quoi, sur quelle ressource et à quel moment**, pour pouvoir retrouver l’historique des actions importantes (traçabilité).

---

## À quoi ça sert (concrètement)

- **Enregistrer des événements** : à chaque action importante (création de course, acceptation par un chauffeur, course terminée, création de livraison, etc.), le backend appelle `auditService.logAction(...)` et écrit une ligne dans la table **`audit_logs`**.
- **Consulter l’historique** : l’admin peut voir ces logs via **GET /api/v1/admin/audit** (filtres par type d’entité, utilisateur, action, dates). C’est la page **Audit** du dashboard admin.

Chaque enregistrement contient typiquement :
- **user_id** : l’utilisateur qui a fait l’action (client, chauffeur, ou système)
- **action** : le type d’action (ex. `ride_created`, `ride_accepted`, `delivery_completed`)
- **entity_type** : le type de ressource concernée (`ride`, `delivery`, etc.)
- **entity_id** : l’ID de la ressource (ID de la course, de la livraison, etc.)
- **details** : données optionnelles (JSON), ex. montant, statut
- **created_at** : date/heure de l’action

---

## Pourquoi c’est utile

1. **Support / litiges** : en cas de conflit (course non reconnue, litige de paiement), on peut retrouver la chaîne d’actions (création → acceptation → démarrage → fin).
2. **Sécurité et conformité** : traçabilité des opérations sensibles (qui a modifié quoi, quand).
3. **Analyse** : compter les types d’actions, voir l’activité par période ou par utilisateur.
4. **Debug** : comprendre après coup pourquoi une course ou une livraison est dans un certain statut.

---

## Où c’est utilisé dans le backend

Le service **`audit/service.js`** expose notamment :
- **logAction(userId, action, entityType, entityId, details)** : écrit une ligne dans `audit_logs`.

Les modules **rides** et **deliveries** appellent `logAction` aux étapes clés, par exemple :
- **Courses** : `ride_created`, `ride_accepted`, `ride_started`, `ride_completed`, `ride_cancelled`, etc.
- **Livraisons** : `delivery_created`, `delivery_accepted`, `delivery_in_transit`, `delivery_completed`, etc.

L’admin ne fait pas d’action “Audit” à part **consulter** ces logs (page Audit du dashboard = appel à **GET /admin/audit**).

---

## Si la page Audit affiche rien

1. **Vérifier que la table existe**  
   Les logs sont stockés dans la table **`audit_logs`**. Si elle n’a jamais été créée, les INSERT échouent (en silence) et la page reste vide.

   Créer la table avec (en utilisant **la même base** que l’app, par ex. `bikeride_pro` si c’est la valeur de `DB_NAME` dans ton `.env`) :
   ```bash
   cd backend
   psql -U postgres -h localhost -d bikeride_pro -f src/modules/audit/models.sql
   ```

2. **Être connecté en admin**  
   La route **GET /api/v1/admin/audit** exige une authentification avec un compte **admin**. Vérifier que vous êtes bien connecté au dashboard avec un utilisateur ayant le rôle `admin`.

3. **Avoir des actions en base**  
   Les logs sont créés quand des courses ou livraisons sont créées/acceptées/terminées, etc. Lancer une simulation (ex. `node scripts/simulation-course-et-livraison.js`) puis rafraîchir la page Audit.
