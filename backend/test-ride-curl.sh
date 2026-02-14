#!/bin/bash

# Script de test complet avec curl pour le flow "Course"
# Usage: ./test-ride-curl.sh

BASE_URL="http://localhost:3000/api/v1"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 TEST COMPLET - FLOW COURSE (avec curl)${NC}"
echo "=========================================="
echo ""

# Variables
CLIENT_ID=""
CLIENT_TOKEN=""
DRIVER_ID=""
DRIVER_TOKEN=""
RIDE_ID=""
TIMESTAMP=$(date +%s)

# Fonction pour faire une requête curl et extraire les données JSON
make_request() {
    local method=$1
    local endpoint=$2
    local auth_header=$3
    local idempotency_header=$4
    local body=$5
    
    local curl_cmd="curl -s -X $method \"$BASE_URL$endpoint\" -H \"Content-Type: application/json\""
    
    if [ -n "$auth_header" ]; then
        curl_cmd="$curl_cmd -H \"Authorization: Bearer $auth_header\""
    fi
    
    if [ -n "$idempotency_header" ]; then
        curl_cmd="$curl_cmd -H \"Idempotency-Key: $idempotency_header\""
    fi
    
    if [ -n "$body" ]; then
        curl_cmd="$curl_cmd -d '$body'"
    fi
    
    eval $curl_cmd
}

# Fonction pour extraire une valeur JSON
extract_json() {
    local json=$1
    local key=$2
    echo "$json" | grep -o "\"$key\":\"[^\"]*\"" | cut -d'"' -f4 || echo "$json" | grep -o "\"$key\":[0-9]*" | cut -d':' -f2
}

# Fonction pour extraire un ID numérique
extract_id() {
    local json=$1
    local key=$2
    echo "$json" | grep -o "\"$key\":[0-9]*" | head -1 | cut -d':' -f2
}

# 1. Créer le client
echo -e "${YELLOW}1️⃣ Création du client...${NC}"
CLIENT_RESPONSE=$(make_request "POST" "/auth/register" "" "" "{
    \"email\": \"client_curl_${TIMESTAMP}@example.com\",
    \"password\": \"Password123\",
    \"phone\": \"+22177000$(echo $TIMESTAMP | tail -c 4)\",
    \"first_name\": \"Client\",
    \"last_name\": \"Curl\",
    \"role\": \"client\"
}")

if echo "$CLIENT_RESPONSE" | grep -q '"success":true'; then
    CLIENT_ID=$(extract_id "$CLIENT_RESPONSE" "id")
    CLIENT_TOKEN=$(extract_json "$CLIENT_RESPONSE" "token")
    echo -e "${GREEN}✅ Client créé: ID=$CLIENT_ID${NC}"
    echo "   Token: ${CLIENT_TOKEN:0:50}..."
else
    echo -e "${RED}❌ Erreur création client:${NC}"
    echo "$CLIENT_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$CLIENT_RESPONSE"
    exit 1
fi
echo ""

# 2. Créer le driver
echo -e "${YELLOW}2️⃣ Création du driver...${NC}"
DRIVER_RESPONSE=$(make_request "POST" "/auth/register" "" "" "{
    \"email\": \"driver_curl_${TIMESTAMP}@example.com\",
    \"password\": \"Password123\",
    \"phone\": \"+22177000$(echo $((TIMESTAMP + 1)) | tail -c 4)\",
    \"first_name\": \"Driver\",
    \"last_name\": \"Curl\",
    \"role\": \"driver\"
}")

if echo "$DRIVER_RESPONSE" | grep -q '"success":true'; then
    DRIVER_ID=$(extract_id "$DRIVER_RESPONSE" "id")
    DRIVER_TOKEN=$(extract_json "$DRIVER_RESPONSE" "token")
    echo -e "${GREEN}✅ Driver créé: ID=$DRIVER_ID${NC}"
    echo "   Token: ${DRIVER_TOKEN:0:50}..."
else
    echo -e "${RED}❌ Erreur création driver:${NC}"
    echo "$DRIVER_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$DRIVER_RESPONSE"
    exit 1
fi
echo ""

# 3. Mettre le driver en ligne
echo -e "${YELLOW}3️⃣ Mise en ligne du driver...${NC}"
STATUS_RESPONSE=$(make_request "PUT" "/users/drivers/$DRIVER_ID/status" \
    "$DRIVER_TOKEN" "" "{
    \"is_online\": true,
    \"is_available\": true
}")

if echo "$STATUS_RESPONSE" | grep -q '"success":true'; then
    echo -e "${GREEN}✅ Driver en ligne${NC}"
else
    echo -e "${RED}❌ Erreur mise en ligne:${NC}"
    echo "$STATUS_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$STATUS_RESPONSE"
    exit 1
fi
echo ""

# 4. Estimer une course
echo -e "${YELLOW}4️⃣ Estimation de la course...${NC}"
ESTIMATE_RESPONSE=$(make_request "POST" "/rides/estimate" "" "" "{
    \"pickup_lat\": 14.6928,
    \"pickup_lng\": -17.4467,
    \"dropoff_lat\": 14.7100,
    \"dropoff_lng\": -17.4680
}")

if echo "$ESTIMATE_RESPONSE" | grep -q '"success":true'; then
    ESTIMATED_FARE=$(echo "$ESTIMATE_RESPONSE" | grep -o '"fare_estimate":[0-9]*' | cut -d':' -f2)
    DISTANCE=$(echo "$ESTIMATE_RESPONSE" | grep -o '"distance_km":[0-9.]*' | cut -d':' -f2)
    DURATION=$(echo "$ESTIMATE_RESPONSE" | grep -o '"duration_min":[0-9]*' | cut -d':' -f2)
    echo -e "${GREEN}✅ Estimation: ${ESTIMATED_FARE} FCFA (${DISTANCE} km, ${DURATION} min)${NC}"
else
    echo -e "${YELLOW}⚠️ Estimation échouée:${NC}"
    echo "$ESTIMATE_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$ESTIMATE_RESPONSE"
fi
echo ""

# 5. Créer la course
echo -e "${YELLOW}5️⃣ Création de la course...${NC}"
RIDE_RESPONSE=$(make_request "POST" "/rides" \
    "$CLIENT_TOKEN" "" "{
    \"pickup_lat\": 14.6928,
    \"pickup_lng\": -17.4467,
    \"dropoff_lat\": 14.7100,
    \"dropoff_lng\": -17.4680,
    \"pickup_address\": \"Plateau, Dakar\",
    \"dropoff_address\": \"Point E, Dakar\"
}")

if echo "$RIDE_RESPONSE" | grep -q '"success":true'; then
    RIDE_ID=$(extract_id "$RIDE_RESPONSE" "id")
    RIDE_STATUS=$(extract_json "$RIDE_RESPONSE" "status")
    echo -e "${GREEN}✅ Course créée: ID=$RIDE_ID, Status=$RIDE_STATUS${NC}"
    if [ "$RIDE_STATUS" != "REQUESTED" ]; then
        echo -e "${RED}⚠️ ATTENTION: Le statut devrait être REQUESTED mais est $RIDE_STATUS${NC}"
    fi
else
    echo -e "${RED}❌ Erreur création course:${NC}"
    echo "$RIDE_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RIDE_RESPONSE"
    exit 1
fi
echo ""

# 6. Voir les courses disponibles (driver)
echo -e "${YELLOW}6️⃣ Courses disponibles pour le driver...${NC}"
AVAILABLE_RESPONSE=$(make_request "GET" "/rides/driver/available" \
    "$DRIVER_TOKEN" "" "")

if echo "$AVAILABLE_RESPONSE" | grep -q '"success":true'; then
    RIDE_COUNT=$(echo "$AVAILABLE_RESPONSE" | grep -o '"id":[0-9]*' | wc -l)
    echo -e "${GREEN}✅ $RIDE_COUNT course(s) disponible(s)${NC}"
    if echo "$AVAILABLE_RESPONSE" | grep -q "\"id\":$RIDE_ID"; then
        echo -e "${GREEN}   ✅ La course $RIDE_ID est dans la liste${NC}"
    else
        echo -e "${YELLOW}   ⚠️ La course $RIDE_ID n'est pas dans la liste${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ Erreur récupération courses disponibles:${NC}"
    echo "$AVAILABLE_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$AVAILABLE_RESPONSE"
fi
echo ""

# 7. Driver accepte la course
echo -e "${YELLOW}7️⃣ Driver accepte la course...${NC}"
ACCEPT_RESPONSE=$(make_request "POST" "/rides/$RIDE_ID/accept" \
    "$DRIVER_TOKEN" "ride-accept-curl-$TIMESTAMP" "")

if echo "$ACCEPT_RESPONSE" | grep -q '"success":true'; then
    ACCEPT_STATUS=$(extract_json "$ACCEPT_RESPONSE" "status")
    echo -e "${GREEN}✅ Course acceptée, Status=$ACCEPT_STATUS${NC}"
    if [ "$ACCEPT_STATUS" != "DRIVER_ASSIGNED" ]; then
        echo -e "${RED}⚠️ ATTENTION: Le statut devrait être DRIVER_ASSIGNED mais est $ACCEPT_STATUS${NC}"
    fi
else
    echo -e "${RED}❌ Erreur acceptation:${NC}"
    echo "$ACCEPT_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$ACCEPT_RESPONSE"
    exit 1
fi
echo ""

# 8. Driver arrive au point de départ
echo -e "${YELLOW}8️⃣ Driver arrive au point de départ...${NC}"
ARRIVED_RESPONSE=$(make_request "POST" "/rides/$RIDE_ID/arrived" \
    "$DRIVER_TOKEN" "" "")

if echo "$ARRIVED_RESPONSE" | grep -q '"success":true'; then
    ARRIVED_STATUS=$(extract_json "$ARRIVED_RESPONSE" "status")
    echo -e "${GREEN}✅ Driver arrivé, Status=$ARRIVED_STATUS${NC}"
    if [ "$ARRIVED_STATUS" != "DRIVER_ARRIVED" ]; then
        echo -e "${RED}⚠️ ATTENTION: Le statut devrait être DRIVER_ARRIVED mais est $ARRIVED_STATUS${NC}"
    fi
else
    echo -e "${RED}❌ Erreur arrivée:${NC}"
    echo "$ARRIVED_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$ARRIVED_RESPONSE"
    exit 1
fi
echo ""

# 9. Démarrer la course
echo -e "${YELLOW}9️⃣ Démarrage de la course...${NC}"
START_RESPONSE=$(make_request "POST" "/rides/$RIDE_ID/start" \
    "$DRIVER_TOKEN" "" "")

if echo "$START_RESPONSE" | grep -q '"success":true'; then
    START_STATUS=$(extract_json "$START_RESPONSE" "status")
    echo -e "${GREEN}✅ Course démarrée, Status=$START_STATUS${NC}"
    if [ "$START_STATUS" != "IN_PROGRESS" ]; then
        echo -e "${RED}⚠️ ATTENTION: Le statut devrait être IN_PROGRESS mais est $START_STATUS${NC}"
    fi
else
    echo -e "${RED}❌ Erreur démarrage:${NC}"
    echo "$START_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$START_RESPONSE"
    exit 1
fi
echo ""

# 10. Envoyer une position GPS (fallback HTTP)
echo -e "${YELLOW}🔟 Envoi position GPS (HTTP fallback)...${NC}"
LOCATION_RESPONSE=$(make_request "POST" "/rides/$RIDE_ID/location" \
    "$DRIVER_TOKEN" "" "{
    \"lat\": 14.7000,
    \"lng\": -17.4550,
    \"heading\": 90,
    \"speed\": 30
}")

if echo "$LOCATION_RESPONSE" | grep -q '"success":true'; then
    echo -e "${GREEN}✅ Position GPS envoyée${NC}"
else
    echo -e "${YELLOW}⚠️ Erreur envoi position:${NC}"
    echo "$LOCATION_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$LOCATION_RESPONSE"
fi
echo ""

# 11. Terminer la course
echo -e "${YELLOW}1️⃣1️⃣ Finalisation de la course...${NC}"
COMPLETE_RESPONSE=$(make_request "POST" "/rides/$RIDE_ID/complete" \
    "$DRIVER_TOKEN" "" "{
    \"actual_distance_km\": 5.2,
    \"actual_duration_min\": 18
}")

if echo "$COMPLETE_RESPONSE" | grep -q '"success":true'; then
    COMPLETE_STATUS=$(extract_json "$COMPLETE_RESPONSE" "status")
    PAYMENT_STATUS=$(extract_json "$COMPLETE_RESPONSE" "payment_status")
    FINAL_FARE=$(echo "$COMPLETE_RESPONSE" | grep -o '"fare_final":[0-9.]*' | cut -d':' -f2 || echo "N/A")
    echo -e "${GREEN}✅ Course terminée${NC}"
    echo "   Status: $COMPLETE_STATUS"
    echo "   Payment Status: $PAYMENT_STATUS"
    echo "   Prix final: $FINAL_FARE FCFA"
    if [ "$COMPLETE_STATUS" != "COMPLETED" ] && [ "$COMPLETE_STATUS" != "PAID" ]; then
        echo -e "${YELLOW}   ⚠️ Le statut devrait être COMPLETED ou PAID${NC}"
    fi
else
    echo -e "${RED}❌ Erreur finalisation:${NC}"
    echo "$COMPLETE_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$COMPLETE_RESPONSE"
    exit 1
fi
echo ""

# 12. Client note la course
echo -e "${YELLOW}1️⃣2️⃣ Notation de la course...${NC}"
RATE_RESPONSE=$(make_request "POST" "/rides/$RIDE_ID/rate" \
    "$CLIENT_TOKEN" "" "{
    \"rating\": 5,
    \"comment\": \"Super course, merci !\",
    \"role\": \"client\"
}")

if echo "$RATE_RESPONSE" | grep -q '"success":true'; then
    echo -e "${GREEN}✅ Course notée (5 étoiles)${NC}"
else
    echo -e "${YELLOW}⚠️ Erreur notation:${NC}"
    echo "$RATE_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RATE_RESPONSE"
fi
echo ""

# 13. Vérifier l'état final
echo -e "${YELLOW}1️⃣3️⃣ Vérification de l'état final...${NC}"
FINAL_RESPONSE=$(make_request "GET" "/rides/$RIDE_ID" \
    "$CLIENT_TOKEN" "" "")

if echo "$FINAL_RESPONSE" | grep -q '"success":true'; then
    FINAL_STATUS=$(extract_json "$FINAL_RESPONSE" "status")
    FINAL_PAYMENT=$(extract_json "$FINAL_RESPONSE" "payment_status")
    FINAL_FARE=$(echo "$FINAL_RESPONSE" | grep -o '"fare_final":[0-9.]*' | cut -d':' -f2 || echo "N/A")
    echo -e "${GREEN}✅ État final récupéré${NC}"
    echo "   Status: $FINAL_STATUS"
    echo "   Payment Status: $FINAL_PAYMENT"
    echo "   Prix final: $FINAL_FARE FCFA"
else
    echo -e "${YELLOW}⚠️ Erreur récupération état final:${NC}"
    echo "$FINAL_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$FINAL_RESPONSE"
fi
echo ""

# Résumé final
echo "=========================================="
echo -e "${GREEN}🎉 TEST COMPLET TERMINÉ !${NC}"
echo ""
echo "Résumé:"
echo "  Client ID: $CLIENT_ID"
echo "  Driver ID: $DRIVER_ID"
echo "  Ride ID: $RIDE_ID"
echo ""
echo "Pour tester manuellement avec curl:"
echo ""
echo "# Voir la course:"
echo "curl -X GET $BASE_URL/rides/$RIDE_ID \\"
echo "  -H \"Authorization: Bearer $CLIENT_TOKEN\""
echo ""
echo "# Voir l'historique du client:"
echo "curl -X GET $BASE_URL/rides \\"
echo "  -H \"Authorization: Bearer $CLIENT_TOKEN\""
echo ""
echo "# Voir l'historique du driver:"
echo "curl -X GET $BASE_URL/rides/driver/my-rides \\"
echo "  -H \"Authorization: Bearer $DRIVER_TOKEN\""
echo ""

