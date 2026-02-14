#!/usr/bin/env node
/**
 * Simulation de test : 1 client + 1 chauffeur
 * 1. Créer un client
 * 2. Créer un chauffeur
 * 3. Le client fait une demande de course
 * 4. Le chauffeur accepte et mène la course à terme
 * 5. Le client fait une demande de livraison
 * 6. Le chauffeur accepte et livre
 *
 * Usage: node scripts/simulation-course-et-livraison.js
 * Prérequis: backend démarré (npm start), base de données à jour
 */

const http = require('http');

const BASE = process.env.API_BASE_URL || 'http://localhost:3000/api/v1';

const colors = {
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
  reset: '\x1b[0m',
};

function log(msg, color = 'reset') {
  console.log(`${colors[color]}${msg}${colors.reset}`);
}

function request(method, path, headers = {}, body = null) {
  return new Promise((resolve, reject) => {
    const url = path.startsWith('http') ? new URL(path) : new URL(BASE + path);
    const opt = {
      hostname: url.hostname,
      port: url.port || 3000,
      path: url.pathname + url.search,
      method,
      headers: { 'Content-Type': 'application/json', ...headers },
    };
    const req = http.request(opt, (res) => {
      let data = '';
      res.on('data', (c) => (data += c));
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data) });
        } catch {
          resolve({ status: res.statusCode, data: { raw: data } });
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(typeof body === 'string' ? body : JSON.stringify(body));
    req.end();
  });
}

async function run() {
  const ts = Date.now();
  let clientId, clientToken, driverId, driverToken, rideId, deliveryId;

  log('\n═══ Simulation : Course + Livraison ═══\n', 'cyan');

  // ─── 1. Créer un client ───
  log('1. Création du client...', 'yellow');
  const regClient = await request('POST', '/auth/register', {}, {
    email: `client_sim_${ts}@example.com`,
    password: 'Password123',
    phone: `+22177${String(ts).slice(-6)}`,
    first_name: 'Moustapha2',
    last_name: 'Sy2',
    role: 'client',
  });
  if (!regClient.data.success || !regClient.data.data?.user) {
    log('Erreur création client: ' + JSON.stringify(regClient.data), 'red');
    process.exit(1);
  }
  clientId = regClient.data.data.user.id;
  clientToken = regClient.data.data.token;
  log(`   Client créé (id=${clientId})`, 'green');

  // ─── 2. Créer un chauffeur ───
  log('\n2. Création du chauffeur...', 'yellow');
  const regDriver = await request('POST', '/auth/register', {}, {
    email: `driver_sim_${ts}@example.com`,
    password: 'Password123',
    phone: `+22178${String(ts).slice(-6)}`,
    first_name: 'Landing2',
    last_name: 'Savage2',
    role: 'driver',
  });
  if (!regDriver.data.success || !regDriver.data.data?.user) {
    log('Erreur création chauffeur: ' + JSON.stringify(regDriver.data), 'red');
    process.exit(1);
  }
  driverId = regDriver.data.data.user.id;
  driverToken = regDriver.data.data.token;
  log(`   Chauffeur créé (id=${driverId})`, 'green');

  // ─── 3. Mettre le chauffeur en ligne ───
  log('\n3. Chauffeur en ligne...', 'yellow');
  const statusRes = await request('PUT', `/users/drivers/${driverId}/status`, {
    Authorization: `Bearer ${driverToken}`,
  }, { is_online: true, is_available: true });
  if (!statusRes.data.success) {
    log('Erreur statut chauffeur: ' + JSON.stringify(statusRes.data), 'red');
    process.exit(1);
  }
  log('   Chauffeur en ligne', 'green');

  // ─── 4. Client : demande de course ───
  log('\n4. Client demande une course...', 'yellow');
  const rideEst = await request('POST', '/rides/estimate', {}, {
    pickup_lat: 14.6928,
    pickup_lng: -17.4467,
    dropoff_lat: 14.71,
    dropoff_lng: -17.468,
  });
  if (rideEst.data.success) {
    log(`   Estimation: ${rideEst.data.data?.fare_estimate ?? 'N/A'} FCFA`, 'green');
  }

  const rideCreate = await request('POST', '/rides', { Authorization: `Bearer ${clientToken}` }, {
    pickup_lat: 14.6928,
    pickup_lng: -17.4467,
    dropoff_lat: 14.71,
    dropoff_lng: -17.468,
    pickup_address: 'Plateau, Dakar',
    dropoff_address: 'Point b, Dakar',
  });
  if (!rideCreate.data.success || !rideCreate.data.data?.id) {
    log('Erreur création course: ' + JSON.stringify(rideCreate.data), 'red');
    process.exit(1);
  }
  rideId = rideCreate.data.data.id;
  log(`   Course créée (id=${rideId})`, 'green');

  // ─── 5. Chauffeur accepte et termine la course ───
  log('\n5. Chauffeur accepte et termine la course...', 'yellow');

  let r = await request('POST', `/rides/${rideId}/accept`, {
    Authorization: `Bearer ${driverToken}`,
    'Idempotency-Key': `sim-accept-ride-${ts}`,
  });
  if (!r.data.success) {
    log('Erreur acceptation course: ' + JSON.stringify(r.data), 'red');
    process.exit(1);
  }
  log('   Course acceptée', 'green');

  r = await request('POST', `/rides/${rideId}/arrived`, { Authorization: `Bearer ${driverToken}` });
  if (!r.data.success) {
    log('Erreur arrivée: ' + JSON.stringify(r.data), 'red');
    process.exit(1);
  }
  log('   Chauffeur arrivé', 'green');

  r = await request('POST', `/rides/${rideId}/start`, { Authorization: `Bearer ${driverToken}` });
  if (!r.data.success) {
    log('Erreur démarrage: ' + JSON.stringify(r.data), 'red');
    process.exit(1);
  }
  log('   Course démarrée', 'green');

  r = await request('POST', `/rides/${rideId}/complete`, { Authorization: `Bearer ${driverToken}` }, {
    actual_distance_km: 5.2,
    actual_duration_min: 18,
  });
  if (!r.data.success) {
    log('Erreur fin de course: ' + JSON.stringify(r.data), 'red');
    process.exit(1);
  }
  const fareFinal = r.data.data?.fare_final ?? 'N/A';
  log(`   Course terminée (prix final: ${fareFinal} FCFA)`, 'green');

  // ─── 6. Client : demande de livraison ───
  log('\n6. Client demande une livraison...', 'yellow');
  const delEst = await request('POST', '/deliveries/estimate', {}, {
    pickup_lat: 14.71,
    pickup_lng: -17.468,
    dropoff_lat: 14.72,
    dropoff_lng: -17.45,
  });
  if (delEst.data.success) {
    log(`   Estimation livraison: ${delEst.data.data?.fare_estimate ?? delEst.data.data?.estimated_fare ?? 'N/A'} FCFA`, 'green');
  }

  const delCreate = await request('POST', '/deliveries', { Authorization: `Bearer ${clientToken}` }, {
    pickup_lat: 14.71,
    pickup_lng: -17.468,
    dropoff_lat: 14.72,
    dropoff_lng: -17.45,
    pickup_address: 'Point b, Dakar',
    dropoff_address: 'Almadies, Dakar',
    package_type: 'standard',
    package_weight_kg: 2,
    package_description: 'Colis simulation',
  });
  if (!delCreate.data.success || !delCreate.data.data?.id) {
    log('Erreur création livraison: ' + JSON.stringify(delCreate.data), 'red');
    process.exit(1);
  }
  deliveryId = delCreate.data.data.id;
  log(`   Livraison créée (id=${deliveryId})`, 'green');

  // ─── 7. Chauffeur accepte et livre ───
  log('\n7. Chauffeur accepte et livre...', 'yellow');

  r = await request('POST', `/deliveries/${deliveryId}/accept`, {
    Authorization: `Bearer ${driverToken}`,
    'Idempotency-Key': `sim-accept-del-${ts}`,
  });
  if (!r.data.success) {
    log('Erreur acceptation livraison: ' + JSON.stringify(r.data), 'red');
    process.exit(1);
  }
  log('   Livraison acceptée', 'green');

  r = await request('POST', `/deliveries/${deliveryId}/picked-up`, { Authorization: `Bearer ${driverToken}` });
  if (!r.data.success) {
    log('Erreur colis récupéré: ' + JSON.stringify(r.data), 'red');
    process.exit(1);
  }
  log('   Colis récupéré', 'green');

  r = await request('POST', `/deliveries/${deliveryId}/start-transit`, { Authorization: `Bearer ${driverToken}` });
  if (!r.data.success) {
    log('Erreur démarrage trajet: ' + JSON.stringify(r.data), 'red');
    process.exit(1);
  }
  log('   Trajet démarré', 'green');

  r = await request('POST', `/deliveries/${deliveryId}/complete`, { Authorization: `Bearer ${driverToken}` }, {
    actual_distance_km: 4.5,
    actual_duration_min: 15,
  });
  if (!r.data.success) {
    log('Erreur livraison terminée: ' + JSON.stringify(r.data), 'red');
    process.exit(1);
  }
  log('   Livraison terminée', 'green');

  // ─── Résumé ───
  log('\n═══ Simulation terminée ═══', 'cyan');
  log(`Client ID: ${clientId}  |  Chauffeur ID: ${driverId}`, 'blue');
  log(`Course ID: ${rideId}  |  Livraison ID: ${deliveryId}`, 'blue');
  log('', 'reset');
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
