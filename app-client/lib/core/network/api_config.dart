import 'package:flutter/foundation.dart';

/// Configuration de l'API BikeRide Pro.
/// - Mode web : http://localhost:3000
/// - Appareil réel / émulateur : IP de la machine où tourne le backend (même réseau WiFi).
///   Modifier [kBackendHost] si votre IP change (voir: ip -4 addr ou hostname -I).
// Adresse IP du VPS
const String kBackendHost = '104.237.132.106';
const int kBackendPort = 3000;

class ApiConfig {
  // URL de base pour le VPS (HTTP pour le moment, à mettre à jour en HTTPS plus tard)
  static final String baseUrl = 'http://$kBackendHost:$kBackendPort/api/v1';
}
