#!/usr/bin/env node

/**
 * Test rapide pour vérifier le problème de permissions driver
 */

const http = require('http');

const BASE_URL = 'http://localhost:3000/api/v1';

function makeRequest(method, path, headers = {}, body = null) {
  return new Promise((resolve, reject) => {
    const fullPath = BASE_URL + path;
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

async function test() {
  console.log('🔍 Test Driver Status Update\n');

  // 1. Créer un driver
  console.log('1. Création du driver...');
  const timestamp = Date.now();
  const driverResponse = await makeRequest('POST', '/auth/register', {}, {
    email: `driver_debug_${timestamp}@example.com`,
    password: 'Password123',
    phone: `+22177000${timestamp.toString().slice(-4)}`,
    first_name: 'Driver',
    last_name: 'Debug',
    role: 'driver'
  });

  if (!driverResponse.data.success) {
    console.error('❌ Erreur création driver:', driverResponse.data);
    return;
  }

  const DRIVER_ID = driverResponse.data.data.user.id;
  const DRIVER_TOKEN = driverResponse.data.data.token;
  const DRIVER_ROLE = driverResponse.data.data.user.role;

  console.log(`✅ Driver créé:`);
  console.log(`   ID: ${DRIVER_ID}`);
  console.log(`   Role (dans réponse): ${DRIVER_ROLE}`);
  console.log(`   Token: ${DRIVER_TOKEN.substring(0, 50)}...`);
  console.log('');

  // 2. Vérifier le rôle dans la DB directement
  console.log('2. Vérification du rôle dans la DB...');
  const meResponse = await makeRequest('GET', '/auth/me', {
    'Authorization': `Bearer ${DRIVER_TOKEN}`
  });

  if (meResponse.data.success) {
    const dbRole = meResponse.data.data?.user?.role;
    console.log(`   Role dans DB (via /me): ${dbRole}`);
  } else {
    console.log(`   ⚠️ Impossible de vérifier via /me:`, meResponse.data);
  }
  console.log('');

  // 3. Tester la mise à jour du statut
  console.log('3. Test mise à jour statut driver...');
  console.log(`   Endpoint: PUT /users/drivers/${DRIVER_ID}/status`);
  console.log(`   Token: ${DRIVER_TOKEN.substring(0, 50)}...`);
  console.log('');

  const statusResponse = await makeRequest('PUT', `/users/drivers/${DRIVER_ID}/status`, {
    'Authorization': `Bearer ${DRIVER_TOKEN}`
  }, {
    is_online: true,
    is_available: true
  });

  console.log(`   Status HTTP: ${statusResponse.status}`);
  console.log(`   Réponse:`, JSON.stringify(statusResponse.data, null, 2));
  console.log('');

  if (statusResponse.data.success) {
    console.log('✅ SUCCÈS ! Le driver peut mettre à jour son statut.');
  } else {
    console.log('❌ ÉCHEC !');
    if (statusResponse.data.debug) {
      console.log('   Debug info:', statusResponse.data.debug);
    }
  }
}

test().catch(console.error);

