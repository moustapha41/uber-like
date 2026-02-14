#!/bin/bash

# Script de test complet pour le flow "Course"
# Usage: ./test-ride-complete.sh

BASE_URL="http://localhost:3000/api/v1"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "🚀 TEST COMPLET - FLOW COURSE"
echo "=============================="
echo ""

# Variables pour stocker les IDs et tokens
CLIENT_ID=""
CLIENT_TOKEN=""
DRIVER_ID=""
DRIVER_TOKEN=""
RIDE_ID=""

# 1. Créer le client
echo "1️⃣ Création du client..."
CLIENT_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "client_test_'$(date +%s)'@example.com",
    "password": "Password123",
    "phone": "+221770000'$(date +%s | tail -c 4)'",
    "first_name": "Client",
    "last_name": "Test",
    "role": "client"
  }')

if echo "$CLIENT_RESPONSE" | grep -q '"success":true'; then
  CLIENT_ID=$(echo "$CLIENT_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
  CLIENT_TOKEN=$(echo "$CLIENT_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  echo -e "${GREEN}✅ Client créé: ID=$CLIENT_ID${NC}"
  echo "Token: ${CLIENT_TOKEN:0:50}..."
else
  echo -e "${RED}❌ Erreur création client:${NC}"
  echo "$CLIENT_RESPONSE" | jq '.' 2>/dev/null || echo "$CLIENT_RESPONSE"
  exit 1
fi
echo ""

# 2. Créer le driver
echo "2️⃣ Création du driver..."
DRIVER_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "driver_test_'$(date +%s)'@example.com",
    "password": "Password123",
    "phone": "+221770000'$(date +%s | tail -c 4)'",
    "first_name": "Driver",
    "last_name": "Test",
    "role": "driver"
  }')

if echo "$DRIVER_RESPONSE" | grep -q '"success":true'; then
  DRIVER_ID=$(echo "$DRIVER_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
  DRIVER_TOKEN=$(echo "$DRIVER_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
  echo -e "${GREEN}✅ Driver créé: ID=$DRIVER_ID${NC}"
  echo "Token: ${DRIVER_TOKEN:0:50}..."
else
  echo -e "${RED}❌ Erreur création driver:${NC}"
  echo "$DRIVER_RESPONSE" | jq '.' 2>/dev/null || echo "$DRIVER_RESPONSE"
  exit 1
fi
echo ""

# 3. Créditer le wallet du client (pour le paiement)
echo "3️⃣ Crédit du wallet client (5000 FCFA)..."
WALLET_RESPONSE=$(curl -s -X POST "$BASE_URL/wallet/deposit" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $CLIENT_TOKEN" \
  -d '{
    "user_id": '$CLIENT_ID',
    "amount": 5000,
    "description": "Crédit test"
  }')

if echo "$WALLET_RESPONSE" | grep -q '"success":true'; then
  echo -e "${GREEN}✅ Wallet crédité${NC}"
else
  echo -e "${YELLOW}⚠️ Crédit wallet échoué (peut nécessiter admin):${NC}"
  echo "$WALLET_RESPONSE" | jq '.' 2>/dev/null || echo "$WALLET_RESPONSE"
fi
echo ""

# 4. Mettre le driver en ligne et disponible
echo "4️⃣ Mise en ligne du driver..."
STATUS_RESPONSE=$(curl -s -X PUT "$BASE_URL/users/drivers/$DRIVER_ID/status" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DRIVER_TOKEN" \
  -d '{
    "is_online": true,
    "is_available": true
  }')

if echo "$STATUS_RESPONSE" | grep -q '"success":true'; then
  echo -e "${GREEN}✅ Driver en ligne${NC}"
else
  echo -e "${RED}❌ Erreur mise en ligne driver:${NC}"
  echo "$STATUS_RESPONSE" | jq '.' 2>/dev/null || echo "$STATUS_RESPONSE"
  echo ""
  echo "Vérification du token..."
  echo "Driver ID: $DRIVER_ID"
  echo "Token (premiers 50 chars): ${DRIVER_TOKEN:0:50}..."
  exit 1
fi
echo ""

# 5. Estimer une course
echo "5️⃣ Estimation de la course..."
ESTIMATE_RESPONSE=$(curl -s -X POST "$BASE_URL/rides/estimate" \
  -H "Content-Type: application/json" \
  -d '{
    "pickup_lat": 14.6928,
    "pickup_lng": -17.4467,
    "dropoff_lat": 14.7100,
    "dropoff_lng": -17.4680
  }')

if echo "$ESTIMATE_RESPONSE" | grep -q '"success":true'; then
  ESTIMATED_FARE=$(echo "$ESTIMATE_RESPONSE" | grep -o '"estimated_fare":[0-9.]*' | grep -o '[0-9.]*')
  echo -e "${GREEN}✅ Estimation: ${ESTIMATED_FARE} FCFA${NC}"
else
  echo -e "${YELLOW}⚠️ Estimation échouée:${NC}"
  echo "$ESTIMATE_RESPONSE" | jq '.' 2>/dev/null || echo "$ESTIMATE_RESPONSE"
fi
echo ""

# 6. Créer la course
echo "6️⃣ Création de la course..."
RIDE_RESPONSE=$(curl -s -X POST "$BASE_URL/rides" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $CLIENT_TOKEN" \
  -d '{
    "pickup_lat": 14.6928,
    "pickup_lng": -17.4467,
    "dropoff_lat": 14.7100,
    "dropoff_lng": -17.4680,
    "pickup_address": "Plateau, Dakar",
    "dropoff_address": "Point E, Dakar"
  }')

if echo "$RIDE_RESPONSE" | grep -q '"success":true'; then
  RIDE_ID=$(echo "$RIDE_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | grep -o '[0-9]*')
  RIDE_STATUS=$(echo "$RIDE_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  echo -e "${GREEN}✅ Course créée: ID=$RIDE_ID, Status=$RIDE_STATUS${NC}"
else
  echo -e "${RED}❌ Erreur création course:${NC}"
  echo "$RIDE_RESPONSE" | jq '.' 2>/dev/null || echo "$RIDE_RESPONSE"
  exit 1
fi
echo ""

# 7. Driver accepte la course
echo "7️⃣ Driver accepte la course..."
ACCEPT_RESPONSE=$(curl -s -X POST "$BASE_URL/rides/$RIDE_ID/accept" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DRIVER_TOKEN" \
  -H "Idempotency-Key: test-accept-$(date +%s)")

if echo "$ACCEPT_RESPONSE" | grep -q '"success":true'; then
  ACCEPT_STATUS=$(echo "$ACCEPT_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  echo -e "${GREEN}✅ Course acceptée, Status=$ACCEPT_STATUS${NC}"
else
  echo -e "${RED}❌ Erreur acceptation:${NC}"
  echo "$ACCEPT_RESPONSE" | jq '.' 2>/dev/null || echo "$ACCEPT_RESPONSE"
  exit 1
fi
echo ""

# 8. Driver arrive au point de départ
echo "8️⃣ Driver arrive au point de départ..."
ARRIVED_RESPONSE=$(curl -s -X POST "$BASE_URL/rides/$RIDE_ID/arrived" \
  -H "Authorization: Bearer $DRIVER_TOKEN")

if echo "$ARRIVED_RESPONSE" | grep -q '"success":true'; then
  ARRIVED_STATUS=$(echo "$ARRIVED_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  echo -e "${GREEN}✅ Driver arrivé, Status=$ARRIVED_STATUS${NC}"
else
  echo -e "${RED}❌ Erreur arrivée:${NC}"
  echo "$ARRIVED_RESPONSE" | jq '.' 2>/dev/null || echo "$ARRIVED_RESPONSE"
  exit 1
fi
echo ""

# 9. Démarrer la course
echo "9️⃣ Démarrage de la course..."
START_RESPONSE=$(curl -s -X POST "$BASE_URL/rides/$RIDE_ID/start" \
  -H "Authorization: Bearer $DRIVER_TOKEN")

if echo "$START_RESPONSE" | grep -q '"success":true'; then
  START_STATUS=$(echo "$START_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  echo -e "${GREEN}✅ Course démarrée, Status=$START_STATUS${NC}"
else
  echo -e "${RED}❌ Erreur démarrage:${NC}"
  echo "$START_RESPONSE" | jq '.' 2>/dev/null || echo "$START_RESPONSE"
  exit 1
fi
echo ""

# 10. Terminer la course
echo "🔟 Finalisation de la course..."
COMPLETE_RESPONSE=$(curl -s -X POST "$BASE_URL/rides/$RIDE_ID/complete" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DRIVER_TOKEN" \
  -d '{
    "actual_distance_km": 5.2,
    "actual_duration_min": 18
  }')

if echo "$COMPLETE_RESPONSE" | grep -q '"success":true'; then
  COMPLETE_STATUS=$(echo "$COMPLETE_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  PAYMENT_STATUS=$(echo "$COMPLETE_RESPONSE" | grep -o '"payment_status":"[^"]*"' | cut -d'"' -f4)
  FINAL_FARE=$(echo "$COMPLETE_RESPONSE" | grep -o '"fare_final":[0-9.]*' | grep -o '[0-9.]*')
  echo -e "${GREEN}✅ Course terminée${NC}"
  echo "   Status: $COMPLETE_STATUS"
  echo "   Payment Status: $PAYMENT_STATUS"
  echo "   Prix final: $FINAL_FARE FCFA"
else
  echo -e "${RED}❌ Erreur finalisation:${NC}"
  echo "$COMPLETE_RESPONSE" | jq '.' 2>/dev/null || echo "$COMPLETE_RESPONSE"
  exit 1
fi
echo ""

# 11. Client note la course
echo "1️⃣1️⃣ Notation de la course..."
RATE_RESPONSE=$(curl -s -X POST "$BASE_URL/rides/$RIDE_ID/rate" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $CLIENT_TOKEN" \
  -d '{
    "rating": 5,
    "comment": "Super course, merci !",
    "role": "client"
  }')

if echo "$RATE_RESPONSE" | grep -q '"success":true'; then
  echo -e "${GREEN}✅ Course notée${NC}"
else
  echo -e "${YELLOW}⚠️ Notation échouée:${NC}"
  echo "$RATE_RESPONSE" | jq '.' 2>/dev/null || echo "$RATE_RESPONSE"
fi
echo ""

# 12. Vérifier l'état final
echo "1️⃣2️⃣ Vérification de l'état final..."
FINAL_RESPONSE=$(curl -s -X GET "$BASE_URL/rides/$RIDE_ID" \
  -H "Authorization: Bearer $CLIENT_TOKEN")

if echo "$FINAL_RESPONSE" | grep -q '"success":true'; then
  FINAL_STATUS=$(echo "$FINAL_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
  FINAL_PAYMENT=$(echo "$FINAL_RESPONSE" | grep -o '"payment_status":"[^"]*"' | cut -d'"' -f4)
  echo -e "${GREEN}✅ État final récupéré${NC}"
  echo "   Status: $FINAL_STATUS"
  echo "   Payment Status: $FINAL_PAYMENT"
else
  echo -e "${YELLOW}⚠️ Récupération état final échouée:${NC}"
  echo "$FINAL_RESPONSE" | jq '.' 2>/dev/null || echo "$FINAL_RESPONSE"
fi
echo ""

echo "=============================="
echo -e "${GREEN}🎉 TEST COMPLET TERMINÉ !${NC}"
echo ""
echo "Résumé:"
echo "  Client ID: $CLIENT_ID"
echo "  Driver ID: $DRIVER_ID"
echo "  Ride ID: $RIDE_ID"
echo ""

