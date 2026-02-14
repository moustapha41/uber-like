import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

/// Service de calcul d'itinéraire (OSRM public).
class RoutingService {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://router.project-osrm.org',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  static String _coords(LatLng from, LatLng to) {
    return '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
  }

  /// Retourne une polyline (liste de points) entre deux positions.
  /// En cas d'erreur, retourne une liste vide.
  static Future<List<LatLng>> getRoutePolyline(LatLng from, LatLng to) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/route/v1/driving/${_coords(from, to)}',
        queryParameters: {
          'overview': 'full',
          'geometries': 'geojson',
        },
      );
      final data = response.data;
      if (data == null) return [];
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return [];
      final geometry = routes.first['geometry'] as Map<String, dynamic>?;
      if (geometry == null) return [];
      final coords = geometry['coordinates'] as List<dynamic>?;
      if (coords == null) return [];
      return coords.map((c) {
        final pair = c as List<dynamic>;
        final lng = (pair[0] is num) ? (pair[0] as num).toDouble() : 0.0;
        final lat = (pair[1] is num) ? (pair[1] as num).toDouble() : 0.0;
        return LatLng(lat, lng);
      }).toList();
    } catch (_) {
      return [];
    }
  }
}

