import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math' as math;

/// Résultat d'une recherche d'adresse (géocodage Nominatim).
class GeocodingResult {
  GeocodingResult({
    required this.displayName,
    required this.lat,
    required this.lng,
    this.type,
    this.importance,
  });

  final String displayName;
  final double lat;
  final double lng;
  final String? type; // airport, hospital, university, etc.
  final double? importance; // Pour trier par pertinence locale
}

/// Géocodage via l'API Nominatim (OpenStreetMap) - gratuit, sans clé.
/// Avec autocomplete géolocalisé et historique local.
class GeocodingService {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://nominatim.openstreetmap.org',
      headers: {
        'User-Agent': 'BikeRidePro-Driver/1.0',
      },
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  static const String _historyKey = 'geocoding_search_history';
  static const int _maxHistoryItems = 50;
  static const double _defaultRadiusKm = 30.0; // Rayon par défaut : 30 km

  /// Recherche d'adresse avec autocomplete géolocalisé.
  /// Priorité : pays > ville > rayon de 30-50 km autour de la position.
  static Future<List<GeocodingResult>> search(
    String query, {
    double? currentLat,
    double? currentLng,
    double radiusKm = _defaultRadiusKm,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      // Si vide, retourner l'historique local + lieux populaires
      return await _getLocalSuggestions(currentLat, currentLng);
    }

    try {
      // Calculer viewbox autour de la position actuelle (si disponible)
      String? viewbox;
      if (currentLat != null && currentLng != null) {
        // Viewbox : [min_lng, min_lat, max_lng, max_lat]
        // Rayon de ~radiusKm km autour de la position
        final delta = radiusKm / 111.0; // Approximation : 1 degré ≈ 111 km
        final minLat = currentLat - delta;
        final maxLat = currentLat + delta;
        final minLng = currentLng - delta;
        final maxLng = currentLng + delta;
        viewbox = '$minLng,$minLat,$maxLng,$maxLat';
      }

      // Recherche avec priorité géolocalisée
      final params = <String, dynamic>{
        'q': q,
        'format': 'json',
        'limit': 10,
        'addressdetails': 1,
        'extratags': 1,
        'namedetails': 1,
      };

      if (viewbox != null) {
        params['viewbox'] = viewbox;
        params['bounded'] = 1; // Limiter aux résultats dans le viewbox
      }

      // Si position disponible, ajouter priorité par distance
      if (currentLat != null && currentLng != null) {
        // Utiliser la recherche avec "near" pour prioriser les résultats proches
        params['lat'] = currentLat.toString();
        params['lon'] = currentLng.toString();
      }

      final response = await _dio.get<List<dynamic>>(
        '/search',
        queryParameters: params,
      );

      final data = response.data;
      if (data == null) return [];

      final results = data.map((e) {
        final m = e as Map<String, dynamic>;
        final address = m['address'] as Map<String, dynamic>? ?? {};
        final type = _extractType(m, address);
        
        return GeocodingResult(
          displayName: (m['display_name'] as String?) ?? '',
          lat: _parseDouble(m['lat']),
          lng: _parseDouble(m['lon']),
          type: type,
          importance: _parseDouble(m['importance']),
        );
      }).toList();

      // Trier par pertinence locale (importance + distance si position disponible)
      if (currentLat != null && currentLng != null) {
        results.sort((a, b) {
          final distA = _distanceKm(currentLat, currentLng, a.lat, a.lng);
          final distB = _distanceKm(currentLat, currentLng, b.lat, b.lng);
          
          // Priorité aux lieux populaires (aéroports, hôpitaux, etc.)
          final priorityA = _getLocalPriority(a.type) + (a.importance ?? 0.0);
          final priorityB = _getLocalPriority(b.type) + (b.importance ?? 0.0);
          
          // Si même priorité, trier par distance
          if ((priorityA - priorityB).abs() < 0.1) {
            return distA.compareTo(distB);
          }
          return priorityB.compareTo(priorityA);
        });
      }

      // Sauvegarder dans l'historique
      await _saveToHistory(q, results.take(3).toList());

      return results.take(8).toList(); // Retourner les 8 meilleurs résultats
    } catch (_) {
      return [];
    }
  }

  /// Suggestions locales : historique + lieux populaires
  static Future<List<GeocodingResult>> _getLocalSuggestions(
    double? currentLat,
    double? currentLng,
  ) async {
    final suggestions = <GeocodingResult>[];

    // 1. Historique local
    final history = await _getHistory();
    suggestions.addAll(history);

    // 2. Lieux populaires locaux (si position disponible)
    if (currentLat != null && currentLng != null) {
      final popularPlaces = await _searchPopularPlaces(currentLat, currentLng);
      suggestions.addAll(popularPlaces);
    }

    return suggestions.take(10).toList();
  }

  /// Recherche de lieux populaires locaux
  static Future<List<GeocodingResult>> _searchPopularPlaces(
    double lat,
    double lng,
  ) async {
    final categories = [
      'aeroway=aerodrome', // Aéroports
      'railway=station', // Gares
      'amenity=hospital', // Hôpitaux
      'amenity=university', // Universités
      'place=neighbourhood', // Quartiers
    ];

    final results = <GeocodingResult>[];

    for (final category in categories) {
      try {
        final delta = 0.5; // ~50 km
        final viewbox = '${lng - delta},${lat - delta},${lng + delta},${lat + delta}';
        
        final response = await _dio.get<List<dynamic>>(
          '/search',
          queryParameters: {
            'q': category,
            'format': 'json',
            'limit': 3,
            'viewbox': viewbox,
            'bounded': 1,
            'lat': lat.toString(),
            'lon': lng.toString(),
          },
        );

        final data = response.data;
        if (data != null) {
          for (final e in data) {
            final m = e as Map<String, dynamic>;
            final address = m['address'] as Map<String, dynamic>? ?? {};
            results.add(GeocodingResult(
              displayName: (m['display_name'] as String?) ?? '',
              lat: _parseDouble(m['lat']),
              lng: _parseDouble(m['lon']),
              type: _extractType(m, address),
              importance: _parseDouble(m['importance']),
            ));
          }
        }
      } catch (_) {
        // Ignorer les erreurs pour une catégorie
      }
    }

    // Trier par distance
    results.sort((a, b) {
      final distA = _distanceKm(lat, lng, a.lat, a.lng);
      final distB = _distanceKm(lat, lng, b.lat, b.lng);
      return distA.compareTo(distB);
    });

    return results.take(5).toList();
  }

  /// Extraire le type de lieu depuis les données Nominatim
  static String? _extractType(Map<String, dynamic> m, Map<String, dynamic> address) {
    final type = m['type']?.toString() ?? '';
    final amenity = m['amenity']?.toString() ?? address['amenity']?.toString();
    final aeroway = m['aeroway']?.toString() ?? address['aeroway']?.toString();
    final railway = m['railway']?.toString() ?? address['railway']?.toString();
    
    if (aeroway == 'aerodrome') return 'airport';
    if (railway == 'station') return 'station';
    if (amenity == 'hospital') return 'hospital';
    if (amenity == 'university' || amenity == 'school') return 'university';
    if (type == 'neighbourhood' || address['neighbourhood'] != null) return 'neighbourhood';
    
    return null;
  }

  /// Priorité locale pour les types de lieux
  static double _getLocalPriority(String? type) {
    switch (type) {
      case 'airport':
        return 1.0;
      case 'station':
        return 0.9;
      case 'hospital':
        return 0.8;
      case 'university':
        return 0.7;
      case 'neighbourhood':
        return 0.6;
      default:
        return 0.5;
    }
  }

  /// Distance en km entre deux points (formule Haversine)
  static double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0; // Rayon de la Terre en km
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  static double _toRadians(double degrees) => degrees * (math.pi / 180.0);

  /// Sauvegarder une recherche dans l'historique local
  static Future<void> _saveToHistory(String query, List<GeocodingResult> results) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_historyKey);
      final history = historyJson != null
          ? (jsonDecode(historyJson) as List).map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];

      // Ajouter les nouveaux résultats (éviter les doublons)
      for (final result in results) {
        final entry = {
          'query': query.toLowerCase(),
          'displayName': result.displayName,
          'lat': result.lat,
          'lng': result.lng,
          'type': result.type,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        
        // Vérifier si déjà présent
        final exists = history.any((e) =>
            e['displayName'] == result.displayName &&
            (e['lat'] as num).toDouble() == result.lat &&
            (e['lng'] as num).toDouble() == result.lng);
        
        if (!exists) {
          history.insert(0, entry);
        }
      }

      // Limiter à _maxHistoryItems
      if (history.length > _maxHistoryItems) {
        history.removeRange(_maxHistoryItems, history.length);
      }

      await prefs.setString(_historyKey, jsonEncode(history));
    } catch (_) {
      // Ignorer les erreurs de sauvegarde
    }
  }

  /// Récupérer l'historique local
  static Future<List<GeocodingResult>> _getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString(_historyKey);
      if (historyJson == null) return [];

      final history = (jsonDecode(historyJson) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // Trier par timestamp (plus récent en premier)
      history.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));

      return history.map((e) => GeocodingResult(
            displayName: e['displayName'] as String,
            lat: (e['lat'] as num).toDouble(),
            lng: (e['lng'] as num).toDouble(),
            type: e['type'] as String?,
          )).toList();
    } catch (_) {
      return [];
    }
  }

  /// Reverse geocoding : convertir coordonnées en adresse
  static Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/reverse',
        queryParameters: {
          'lat': lat.toString(),
          'lon': lng.toString(),
          'format': 'json',
          'addressdetails': 1,
        },
      );

      final data = response.data;
      if (data == null) return null;

      return data['display_name'] as String?;
    } catch (_) {
      return null;
    }
  }

  static double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
