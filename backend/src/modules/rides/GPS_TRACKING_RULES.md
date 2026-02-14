# 📌 RÈGLES DE TRACKING GPS - SOURCE DE VÉRITÉ

## Règle Métier Critique

### Pendant une course (status = IN_PROGRESS)

**`ride_tracking` = VÉRITÉ MÉTIER** ✅

- Toutes les positions GPS pendant la course sont enregistrées dans `ride_tracking`
- Les calculs de distance réelle se basent **UNIQUEMENT** sur `ride_tracking`
- Chaque point est horodaté avec précision

**`driver_locations` = DERNIER SNAPSHOT GLOBAL** 📸

- Position actuelle du driver (mise à jour toutes les 5 secondes)
- Utilisé pour la recherche de drivers disponibles
- **NE PAS** utiliser pour calculer la distance réelle d'une course

## Calcul de Distance Réelle

```sql
-- ✅ CORRECT : Utiliser ride_tracking
SELECT 
  SUM(
    6371 * acos(
      cos(radians(lag(lat) OVER (ORDER BY timestamp))) * 
      cos(radians(lat)) * 
      cos(radians(lng) - radians(lag(lng) OVER (ORDER BY timestamp))) + 
      sin(radians(lag(lat) OVER (ORDER BY timestamp))) * 
      sin(radians(lat))
    )
  ) AS total_distance_km
FROM ride_tracking
WHERE ride_id = :ride_id
ORDER BY timestamp;

-- ❌ INCORRECT : Ne pas utiliser driver_locations pour calculer distance
```

## Workflow

1. **Course démarre** (`IN_PROGRESS`)
   - `ride_tracking` commence à enregistrer les points
   - `driver_locations` continue de se mettre à jour

2. **Pendant la course**
   - WebSocket `driver:location:update` → Enregistre dans **les deux** tables
   - `ride_tracking` : Historique complet (source de vérité)
   - `driver_locations` : Dernière position (pour recherche)

3. **Course terminée** (`COMPLETED`)
   - Calcul distance réelle depuis `ride_tracking`
   - Comparaison avec estimation initiale
   - Application de la formule : `min(estime × 1.10, réel)`

## Validation

- ✅ Vérifier que `ride.status = 'IN_PROGRESS'` avant d'enregistrer dans `ride_tracking`
- ✅ Vérifier que `driver_id` correspond au driver authentifié
- ✅ Rejeter les positions invalides (hors limites, trop rapides, etc.)

