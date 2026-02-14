import '../core/network/api_client.dart';

/// Service des livraisons (estimation, création, liste).
class DeliveriesService {
  DeliveriesService({required ApiClient apiClient}) : _api = apiClient;
  final ApiClient _api;

  /// Estimation du prix (sans auth).
  Future<Map<String, dynamic>> estimate({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    double? packageWeightKg,
    String? packageType,
  }) async {
    final data = <String, dynamic>{
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'dropoff_lat': dropoffLat,
      'dropoff_lng': dropoffLng,
    };
    if (packageWeightKg != null) data['package_weight_kg'] = packageWeightKg;
    if (packageType != null && packageType.isNotEmpty) data['package_type'] = packageType;
    final res = await _api.post('/deliveries/estimate', data: data);
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// Créer une livraison (auth requise).
  Future<Map<String, dynamic>> create({
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    String? pickupAddress,
    String? dropoffAddress,
    String? packageType,
    double? packageWeightKg,
    String? packageDescription,
  }) async {
    final data = <String, dynamic>{
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'dropoff_lat': dropoffLat,
      'dropoff_lng': dropoffLng,
    };
    if (pickupAddress != null && pickupAddress.isNotEmpty) data['pickup_address'] = pickupAddress;
    if (dropoffAddress != null && dropoffAddress.isNotEmpty) data['dropoff_address'] = dropoffAddress;
    if (packageType != null && packageType.isNotEmpty) data['package_type'] = packageType;
    if (packageWeightKg != null) data['package_weight_kg'] = packageWeightKg;
    if (packageDescription != null && packageDescription.isNotEmpty) data['package_description'] = packageDescription;
    final res = await _api.post('/deliveries', data: data);
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// Liste des livraisons du client (auth requise).
  Future<dynamic> getMyDeliveries({int limit = 50, int offset = 0}) async {
    final res = await _api.get('/deliveries', queryParameters: {'limit': limit, 'offset': offset});
    return res['data'];
  }

  /// Détail d'une livraison (auth requise).
  Future<Map<String, dynamic>> getById(int id) async {
    final res = await _api.get('/deliveries/$id');
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// Annuler une livraison (auth requise, client uniquement).
  Future<Map<String, dynamic>> cancel(int id, {String? reason}) async {
    final res = await _api.post('/deliveries/$id/cancel', data: {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// Chauffeurs à proximité du point de prise en charge (livraison en attente).
  Future<List<Map<String, dynamic>>> getNearbyDrivers(int deliveryId) async {
    final res = await _api.get('/deliveries/$deliveryId/nearby-drivers');
    final data = res['data'];
    if (data is List) {
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    }
    return [];
  }

  /// Noter la livraison (client note le chauffeur).
  Future<Map<String, dynamic>> rate(int id, {required int rating, String? comment}) async {
    final res = await _api.post('/deliveries/$id/rate', data: {
      'rating': rating,
      'role': 'client',
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
    return res['data'] as Map<String, dynamic>? ?? {};
  }
}
