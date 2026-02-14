import 'package:flutter/foundation.dart';

/// Configuration de l'API BikeRide Pro (app chauffeur).
/// Configuration pour le VPS de production.
const String kBackendHost = '104.237.132.106';
const int kBackendPort = 3000;

class ApiConfig {
  // URL de base pour le VPS (HTTP pour le moment, à mettre à jour en HTTPS plus tard)
  static final String baseUrl = 'http://$kBackendHost:$kBackendPort/api/v1';
}
