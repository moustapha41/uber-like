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
  static const String _frequentKey = 'geocoding_frequent_destinations';
  static const int _maxHistoryItems = 50;
  static const int _maxFrequentItems = 100;
  static const double _defaultRadiusKm = 30.0;
  static const double _maxRadiusKm = 50.0;

  /// Autocomplete strictement local : priorité pays/ville puis rayon 30–50 km. Géolocalisation requise pour la recherche textuelle.
  static Future<List<GeocodingResult>> search(
    String query, {
    double? currentLat,
    double? currentLng,
    double radiusKm = _defaultRadiusKm,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return await _getLocalSuggestions(currentLat, currentLng);
    if (currentLat == null || currentLng == null) return await _getLocalSuggestions(null, null);

    try {
      final effectiveRadius = radiusKm.clamp(5.0, _maxRadiusKm);
      final delta = effectiveRadius / 111.0;
      final viewbox = '${currentLng - delta},${currentLat - delta},${currentLng + delta},${currentLat + delta}';
      final params = <String, dynamic>{
        'q': q,
        'format': 'json',
        'limit': 15,
        'addressdetails': 1,
        'extratags': 1,
        'viewbox': viewbox,
        'bounded': 1,
        'lat': currentLat.toString(),
        'lon': currentLng.toString(),
      };

      final response = await _dio.get<List<dynamic>>('/search', queryParameters: params);
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

      results.sort((a, b) {
        final distA = _distanceKm(currentLat, currentLng, a.lat, a.lng);
        final distB = _distanceKm(currentLat, currentLng, b.lat, b.lng);
        final priorityA = _getLocalPriority(a.type) + (a.importance ?? 0.0);
        final priorityB = _getLocalPriority(b.type) + (b.importance ?? 0.0);
        if ((priorityA - priorityB).abs() < 0.1) return distA.compareTo(distB);
        return priorityB.compareTo(priorityA);
      });

      await _saveToHistory(q, results.take(3).toList());
      return results.take(10).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> recordFrequentDestination(double lat, double lng, String displayName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_frequentKey);
      final list = json != null
          ? (jsonDecode(json) as List).map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      final i = list.indexWhere((e) =>
          (e['lat'] as num).toDouble().toStringAsFixed(3) == lat.toStringAsFixed(3) &&
          (e['lng'] as num).toDouble().toStringAsFixed(3) == lng.toStringAsFixed(3));
      if (i >= 0) {
        list[i]['count'] = ((list[i]['count'] as int?) ?? 1) + 1;
        list[i]['displayName'] = displayName;
        list[i]['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      } else {
        list.add({
          'lat': lat,
          'lng': lng,
          'displayName': displayName,
          'count': 1,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
      list.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
      if (list.length > _maxFrequentItems) list.removeRange(_maxFrequentItems, list.length);
      await prefs.setString(_frequentKey, jsonEncode(list));
    } catch (_) {}
  }

  static Future<List<GeocodingResult>> _getLocalSuggestions(double? currentLat, double? currentLng) async {
    final suggestions = <GeocodingResult>[];
    if (currentLat != null && currentLng != null) {
      suggestions.addAll(await _getFrequentInZone(currentLat, currentLng, _defaultRadiusKm));
    }
    final history = await _getHistory();
    for (final h in history) {
      if (suggestions.any((s) => s.lat == h.lat && s.lng == h.lng)) continue;
      suggestions.add(h);
    }
    if (currentLat != null && currentLng != null) {
      final popularPlaces = await _searchPopularPlaces(currentLat, currentLng);
      for (final p in popularPlaces) {
        if (suggestions.any((s) => s.lat == p.lat && s.lng == p.lng)) continue;
        suggestions.add(p);
      }
    }
    return suggestions.take(20).toList();
  }

  static Future<List<GeocodingResult>> _getFrequentInZone(double lat, double lng, double radiusKm) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_frequentKey);
      if (json == null) return [];
      final list = (jsonDecode(json) as List).map((e) => Map<String, dynamic>.from(e)).toList();
      final inZone = <GeocodingResult>[];
      for (final e in list) {
        final plat = (e['lat'] as num).toDouble();
        final plng = (e['lng'] as num).toDouble();
        if (_distanceKm(lat, lng, plat, plng) <= radiusKm) {
          inZone.add(GeocodingResult(
            displayName: e['displayName'] as String? ?? '',
            lat: plat,
            lng: plng,
            type: 'frequent',
            importance: (e['count'] as num?)?.toDouble(),
          ));
        }
      }
      inZone.sort((a, b) => (b.importance ?? 0).compareTo(a.importance ?? 0));
      return inZone.take(8).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<GeocodingResult>> _searchPopularPlaces(double lat, double lng) async {
    final categories = [
      'aerodrome',
      'bus station',
      'railway station',
      'hospital',
      'university',
      'school',
      'stadium',
      'supermarket',
      'market',
      'bus stop',
      'police',
      'shop',
    ];
    final results = <GeocodingResult>[];
    final delta = 0.45;
    final viewbox = '${lng - delta},${lat - delta},${lng + delta},${lat + delta}';
    for (final category in categories) {
      try {
        final response = await _dio.get<List<dynamic>>(
          '/search',
          queryParameters: {
            'q': category,
            'format': 'json',
            'limit': 2,
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
      } catch (_) {}
    }
    results.sort((a, b) {
      final distA = _distanceKm(lat, lng, a.lat, a.lng);
      final distB = _distanceKm(lat, lng, b.lat, b.lng);
      return distA.compareTo(distB);
    });
    return results.take(12).toList();
  }

  static String? _extractType(Map<String, dynamic> m, Map<String, dynamic> address) {
    final type = m['type']?.toString() ?? '';
    final amenity = m['amenity']?.toString() ?? address['amenity']?.toString();
    final aeroway = m['aeroway']?.toString() ?? address['aeroway']?.toString();
    final railway = m['railway']?.toString() ?? address['railway']?.toString();
    final shop = m['shop']?.toString() ?? address['shop']?.toString();
    final leisure = m['leisure']?.toString() ?? address['leisure']?.toString();
    final highway = m['highway']?.toString() ?? address['highway']?.toString();
    if (aeroway == 'aerodrome') return 'airport';
    if (railway == 'station') return 'station';
    if (amenity == 'bus_station') return 'bus_station';
    if (highway == 'bus_stop') return 'bus_stop';
    if (amenity == 'hospital') return 'hospital';
    if (amenity == 'university') return 'university';
    if (amenity == 'school') return 'school';
    if (leisure == 'stadium') return 'stadium';
    if (shop == 'supermarket') return 'supermarket';
    if (amenity == 'market') return 'market';
    if (amenity == 'police') return 'police';
    if (shop != null && shop.isNotEmpty) return 'shop';
    if (type == 'neighbourhood' || address['neighbourhood'] != null) return 'neighbourhood';
    return null;
  }

  static double _getLocalPriority(String? type) {
    switch (type) {
      case 'frequent':
        return 1.2;
      case 'airport':
        return 1.0;
      case 'station':
      case 'bus_station':
        return 0.95;
      case 'hospital':
        return 0.9;
      case 'university':
      case 'school':
        return 0.85;
      case 'stadium':
        return 0.8;
      case 'supermarket':
      case 'market':
        return 0.75;
      case 'bus_stop':
        return 0.7;
      case 'police':
        return 0.65;
      case 'shop':
        return 0.6;
      case 'neighbourhood':
        return 0.55;
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

  /// Reverse geocoding : convertir coordonnées en adresse complète
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

  /// Reverse geocoding court : "Quartier, Ville" ou "Ville" (pour affichage après tap sur la carte)
  static Future<String?> reverseGeocodeShort(double lat, double lng) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/reverse',
        queryParameters: {
          'lat': lat.toString(),
          'lon': lng.toString(),
          'format': 'json',
          'addressdetails': 1,
          'zoom': 18, // Niveau de détail plus élevé
          'namedetails': 1, // Inclure les noms alternatifs
        },
      );

      final data = response.data;
      if (data == null) return null;

      final address = data['address'] as Map<String, dynamic>? ?? {};
      
      // 1. Essayer de récupérer le nom du lieu si disponible (parc, hôtel, etc.)
      final String? placeName = _str(address['name']) ?? _str(address['tourism']) ?? _str(address['amenity']);
      
      // 2. Quartier / zone locale (plusieurs clés possibles selon pays)
      String? quartier = _str(address['neighbourhood']) ??
          _str(address['suburb']) ??
          _str(address['quarter']) ??
          _str(address['locality']) ??
          _str(address['hamlet']) ??
          _str(address['district']);
          
      // 3. Ville / agglomération
      String? ville = _str(address['city']) ??
          _str(address['town']) ??
          _str(address['village']) ??
          _str(address['municipality']) ??
          _str(address['county']) ??
          _str(address['state_district']) ??
          _str(address['state']);
          
      // 4. Rue et numéro
      final String? road = _str(address['road']);
      final String? houseNumber = _str(address['house_number']);
      final String? roadWithNumber = houseNumber != null ? '$road $houseNumber' : road;

      // 5. Construire l'adresse de manière hiérarchique
      if (placeName != null && ville != null) {
        return '$placeName, $ville';  // Ex: "Parc National, Dakar"
      }
      if (roadWithNumber != null && ville != null) {
        return '$roadWithNumber, $ville';  // Ex: "Rue 12, Dakar"
      }
      if (quartier != null && ville != null) {
        return '$quartier, $ville';  // Ex: "Plateau, Dakar"
      }
      if (ville != null) return ville;
      if (quartier != null) return quartier;
      if (roadWithNumber != null) return roadWithNumber;
      
      // 6. En dernier recours, utiliser le nom d'affichage complet
      final displayName = _str(data['display_name'] as String?);
      if (displayName != null) {
        // Prendre les 2-3 premiers éléments séparés par des virgules
        final parts = displayName.split(',').take(3).map((s) => s.trim()).where((s) => s.isNotEmpty);
        if (parts.isNotEmpty) {
          return parts.join(', ');
        }
      }
      
      // 7. Si vraiment rien n'est trouvé, retourner les coordonnées
      return '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';
    } catch (_) {
      return null;
    }
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}
