#!/usr/bin/env node

/**
 * Script de test complet pour le flow "Course"
 * Usage: node test-ride-complete.js
 */

const https = require('https');
const http = require('http');

const BASE_URL = 'http://localhost:3000/api/v1';

// Couleurs pour la console
const colors = {
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  reset: '\x1b[0m'
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

function makeRequest(method, path, headers = {}, body = null) {
  return new Promise((resolve, reject) => {
    // Construire l'URL complète
    const fullPath = path.startsWith('http') ? path : BASE_URL + path;
    const url = new URL(fullPath);
    const options = {
      hostname: url.hostname,
      port: url.port || 3000,
      path: url.pathname + (url.search || ''),
      method,
      headers: {
        'Content-Type': 'application/json',
        ...headers
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          resolve({ status: res.statusCode, data: json });
        } catch (e) {
          resolve({ status: res.statusCode, data: { raw: data } });
        }
      });
    });

    req.on('error', reject);
    
    if (body) {
      req.write(typeof body === 'string' ? body : JSON.stringify(body));
    }
    
    req.end();
  });
}

async function testCompleteFlow() {
  log('\n🚀 TEST COMPLET - FLOW COURSE', 'blue');
  log('==============================\n', 'blue');

  let CLIENT_ID, CLIENT_TOKEN, DRIVER_ID, DRIVER_TOKEN, RIDE_ID;

  try {
    // 1. Créer le client
    log('1️⃣ Création du client...', 'yellow');
    const timestamp = Date.now();
    const clientResponse = await makeRequest('POST', '/auth/register', {}, {
      email: `client_test_${timestamp}@example.com`,
      password: 'Password123',
      phone: `+22177000${timestamp.toString().slice(-4)}`,
      first_name: 'Client',
      last_name: 'Test',
      role: 'client'
    });

    if (clientResponse.data.success && clientResponse.data.data) {
      CLIENT_ID = clientResponse.data.data.user.id;
      CLIENT_TOKEN = clientResponse.data.data.token;
      log(`✅ Client créé: ID=${CLIENT_ID}`, 'green');
    } else {
      log(`❌ Erreur création client: ${JSON.stringify(clientResponse.data)}`, 'red');
      return;
    }

    // 2. Créer le driver
    log('\n2️⃣ Création du driver...', 'yellow');
    const driverResponse = await makeRequest('POST', '/auth/register', {}, {
      email: `driver_test_${timestamp}@example.com`,
      password: 'Password123',
      phone: `+22177000${(timestamp + 1).toString().slice(-4)}`,
      first_name: 'Driver',
      last_name: 'Test',
      role: 'driver'
    });

    if (driverResponse.data.success && driverResponse.data.data) {
      DRIVER_ID = driverResponse.data.data.user.id;
      DRIVER_TOKEN = driverResponse.data.data.token;
      log(`✅ Driver créé: ID=${DRIVER_ID}`, 'green');
    } else {
      log(`❌ Erreur création driver: ${JSON.stringify(driverResponse.data)}`, 'red');
      return;
    }

    // 3. Mettre le driver en ligne
    log('\n3️⃣ Mise en ligne du driver...', 'yellow');
    const statusResponse = await makeRequest('PUT', `/users/drivers/${DRIVER_ID}/status`, {
      'Authorization': `Bearer ${DRIVER_TOKEN}`
    }, {
      is_online: true,
      is_available: true
    });

    if (statusResponse.data.success) {
      log('✅ Driver en ligne', 'green');
    } else {
      log(`❌ Erreur mise en ligne: ${JSON.stringify(statusResponse.data)}`, 'red');
      log(`   Driver ID: ${DRIVER_ID}`, 'yellow');
      log(`   Token (premiers 50 chars): ${DRIVER_TOKEN.substring(0, 50)}...`, 'yellow');
      return;
    }

    // 4. Estimer une course
    log('\n4️⃣ Estimation de la course...', 'yellow');
    const estimateResponse = await makeRequest('POST', '/rides/estimate', {}, {
      pickup_lat: 14.6928,
      pickup_lng: -17.4467,
      dropoff_lat: 14.7100,
      dropoff_lng: -17.4680
    });

    if (estimateResponse.data.success) {
      const estimatedFare = estimateResponse.data.data?.estimated_fare || 'N/A';
      log(`✅ Estimation: ${estimatedFare} FCFA`, 'green');
    } else {
      log(`⚠️ Estimation échouée: ${JSON.stringify(estimateResponse.data)}`, 'yellow');
    }

    // 5. Créer la course
    log('\n5️⃣ Création de la course...', 'yellow');
    const rideResponse = await makeRequest('POST', '/rides', {
      'Authorization': `Bearer ${CLIENT_TOKEN}`
    }, {
      pickup_lat: 14.6928,
      pickup_lng: -17.4467,
      dropoff_lat: 14.7100,
      dropoff_lng: -17.4680,
      pickup_address: 'Plateau, Dakar',
      dropoff_address: 'Point E, Dakar'
    });

    if (rideResponse.data.success && rideResponse.data.data) {
      RIDE_ID = rideResponse.data.data.id;
      const rideStatus = rideResponse.data.data.status;
      log(`✅ Course créée: ID=${RIDE_ID}, Status=${rideStatus}`, 'green');
    } else {
      log(`❌ Erreur création course: ${JSON.stringify(rideResponse.data)}`, 'red');
      return;
    }

    // 6. Driver accepte la course
    log('\n6️⃣ Driver accepte la course...', 'yellow');
    const acceptResponse = await makeRequest('POST', `/rides/${RIDE_ID}/accept`, {
      'Authorization': `Bearer ${DRIVER_TOKEN}`,
      'Idempotency-Key': `test-accept-${timestamp}`
    });

    if (acceptResponse.data.success) {
      const acceptStatus = acceptResponse.data.data?.status || 'N/A';
      log(`✅ Course acceptée, Status=${acceptStatus}`, 'green');
    } else {
      log(`❌ Erreur acceptation: ${JSON.stringify(acceptResponse.data)}`, 'red');
      return;
    }

    // 7. Driver arrive
    log('\n7️⃣ Driver arrive au point de départ...', 'yellow');
    const arrivedResponse = await makeRequest('POST', `/rides/${RIDE_ID}/arrived`, {
      'Authorization': `Bearer ${DRIVER_TOKEN}`
    });

    if (arrivedResponse.data.success) {
      const arrivedStatus = arrivedResponse.data.data?.status || 'N/A';
      log(`✅ Driver arrivé, Status=${arrivedStatus}`, 'green');
    } else {
      log(`❌ Erreur arrivée: ${JSON.stringify(arrivedResponse.data)}`, 'red');
      return;
    }

    // 8. Démarrer la course
    log('\n8️⃣ Démarrage de la course...', 'yellow');
    const startResponse = await makeRequest('POST', `/rides/${RIDE_ID}/start`, {
      'Authorization': `Bearer ${DRIVER_TOKEN}`
    });

    if (startResponse.data.success) {
      const startStatus = startResponse.data.data?.status || 'N/A';
      log(`✅ Course démarrée, Status=${startStatus}`, 'green');
    } else {
      log(`❌ Erreur démarrage: ${JSON.stringify(startResponse.data)}`, 'red');
      return;
    }

    // 9. Terminer la course
    log('\n9️⃣ Finalisation de la course...', 'yellow');
    const completeResponse = await makeRequest('POST', `/rides/${RIDE_ID}/complete`, {
      'Authorization': `Bearer ${DRIVER_TOKEN}`
    }, {
      actual_distance_km: 5.2,
      actual_duration_min: 18
    });

    if (completeResponse.data.success) {
      const completeStatus = completeResponse.data.data?.status || 'N/A';
      const paymentStatus = completeResponse.data.data?.payment_status || 'N/A';
      const finalFare = completeResponse.data.data?.fare_final || 'N/A';
      log('✅ Course terminée', 'green');
      log(`   Status: ${completeStatus}`, 'green');
      log(`   Payment Status: ${paymentStatus}`, 'green');
      log(`   Prix final: ${finalFare} FCFA`, 'green');
    } else {
      log(`❌ Erreur finalisation: ${JSON.stringify(completeResponse.data)}`, 'red');
      return;
    }

    // 10. Client note la course
    log('\n🔟 Notation de la course...', 'yellow');
    const rateResponse = await makeRequest('POST', `/rides/${RIDE_ID}/rate`, {
      'Authorization': `Bearer ${CLIENT_TOKEN}`
    }, {
      rating: 5,
      comment: 'Super course, merci !',
      role: 'client'
    });

    if (rateResponse.data.success) {
      log('✅ Course notée', 'green');
    } else {
      log(`⚠️ Notation échouée: ${JSON.stringify(rateResponse.data)}`, 'yellow');
    }

    // 11. Vérifier l'état final
    log('\n1️⃣1️⃣ Vérification de l\'état final...', 'yellow');
    const finalResponse = await makeRequest('GET', `/rides/${RIDE_ID}`, {
      'Authorization': `Bearer ${CLIENT_TOKEN}`
    });

    if (finalResponse.data.success) {
      const finalStatus = finalResponse.data.data?.status || 'N/A';
      const finalPayment = finalResponse.data.data?.payment_status || 'N/A';
      log('✅ État final récupéré', 'green');
      log(`   Status: ${finalStatus}`, 'green');
      log(`   Payment Status: ${finalPayment}`, 'green');
    } else {
      log(`⚠️ Récupération état final échouée: ${JSON.stringify(finalResponse.data)}`, 'yellow');
    }

    log('\n==============================', 'blue');
    log('🎉 TEST COMPLET TERMINÉ !', 'green');
    log('\nRésumé:', 'blue');
    log(`  Client ID: ${CLIENT_ID}`, 'blue');
    log(`  Driver ID: ${DRIVER_ID}`, 'blue');
    log(`  Ride ID: ${RIDE_ID}`, 'blue');
    log('', 'reset');

  } catch (error) {
    log(`\n❌ ERREUR FATALE: ${error.message}`, 'red');
    console.error(error);
    process.exit(1);
  }
}

// Exécuter le test
testCompleteFlow();

