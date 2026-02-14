import 'package:dio/dio.dart';

import '../core/network/api_client.dart';

/// Service chauffeur : livraisons disponibles, accepter, colis récupéré, en route, terminer.
class DriverDeliveriesService {
  DriverDeliveriesService({required ApiClient apiClient}) : _api = apiClient;
  final ApiClient _api;

  /// GET /deliveries/driver/available
  Future<List<Map<String, dynamic>>> getAvailable() async {
    final res = await _api.get('/deliveries/driver/available');
    final data = res['data'];
    if (data is List) {
      return data
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    }
    return [];
  }

  /// POST /deliveries/:id/accept (header Idempotency-Key requis)
  Future<Map<String, dynamic>> accept(int id, {String? idempotencyKey}) async {
    final options = idempotencyKey != null && idempotencyKey.isNotEmpty
        ? Options(headers: {'Idempotency-Key': idempotencyKey})
        : null;
    final res = await _api.request(
      '/deliveries/$id/accept',
      method: 'POST',
      options: options,
    );
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// POST /deliveries/:id/picked-up
  Future<Map<String, dynamic>> pickedUp(int id) async {
    final res = await _api.post('/deliveries/$id/picked-up');
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// POST /deliveries/:id/start-transit
  Future<Map<String, dynamic>> startTransit(int id) async {
    final res = await _api.post('/deliveries/$id/start-transit');
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// POST /deliveries/:id/complete
  Future<Map<String, dynamic>> complete(
    int id, {
    required double actualDistanceKm,
    required int actualDurationMin,
    Map<String, dynamic>? deliveryProof,
  }) async {
    final data = <String, dynamic>{
      'actual_distance_km': actualDistanceKm,
      'actual_duration_min': actualDurationMin,
    };
    if (deliveryProof != null) data['delivery_proof'] = deliveryProof;
    final res = await _api.post('/deliveries/$id/complete', data: data);
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// POST /deliveries/:id/location — envoi position GPS pendant la livraison (suivi en temps réel)
  Future<void> sendLocation(
    int id, {
    required double lat,
    required double lng,
    double? heading,
    double? speed,
  }) async {
    final data = <String, dynamic>{
      'lat': lat,
      'lng': lng,
    };
    if (heading != null) data['heading'] = heading;
    if (speed != null) data['speed'] = speed;
    await _api.post('/deliveries/$id/location', data: data);
  }

  /// POST /deliveries/:id/cancel-driver — annuler une livraison (chauffeur)
  Future<Map<String, dynamic>> cancel(int id, {String? reason}) async {
    final res = await _api.post('/deliveries/$id/cancel-driver', data: {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    return res['data'] as Map<String, dynamic>? ?? {};
  }
}
