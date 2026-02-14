import '../core/network/api_client.dart';

/// Service des courses (estimation, création, liste).
class RidesService {
  RidesService({required ApiClient apiClient}) : _api = apiClient;
  final ApiClient _api;

  /// Estimation du prix (sans auth).
  Future<Map<String, dynamic>> estimate({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
  }) async {
    final res = await _api.post('/rides/estimate', data: {
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'dropoff_lat': dropoffLat,
      'dropoff_lng': dropoffLng,
    });
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// Créer une course (auth requise).
  Future<Map<String, dynamic>> create({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? pickupAddress,
    String? dropoffAddress,
  }) async {
    final res = await _api.post('/rides', data: {
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'dropoff_lat': dropoffLat,
      'dropoff_lng': dropoffLng,
      if (pickupAddress != null && pickupAddress.isNotEmpty) 'pickup_address': pickupAddress,
      if (dropoffAddress != null && dropoffAddress.isNotEmpty) 'dropoff_address': dropoffAddress,
    });
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// Liste des courses du client (auth requise).
  Future<dynamic> getMyRides({int limit = 50, int offset = 0}) async {
    final res = await _api.get('/rides', queryParameters: {'limit': limit, 'offset': offset});
    return res['data'];
  }

  /// Détail d'une course (auth requise).
  Future<Map<String, dynamic>> getById(int id) async {
    final res = await _api.get('/rides/$id');
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// Chauffeurs à proximité du point de départ (course en attente).
  Future<List<Map<String, dynamic>>> getNearbyDrivers(int rideId) async {
    final res = await _api.get('/rides/$rideId/nearby-drivers');
    final data = res['data'];
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return [];
  }

  /// Noter la course (client note le chauffeur).
  Future<Map<String, dynamic>> rate(int id, {required int rating, String? comment}) async {
    final res = await _api.post('/rides/$id/rate', data: {
      'rating': rating,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// Annuler une course (auth requise, client uniquement).
  Future<Map<String, dynamic>> cancel(int id, {String? reason}) async {
    final res = await _api.post('/rides/$id/cancel', data: {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    return res['data'] as Map<String, dynamic>? ?? {};
  }
}
