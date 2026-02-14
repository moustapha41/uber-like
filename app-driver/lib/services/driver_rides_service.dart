import 'package:dio/dio.dart';

import '../core/network/api_client.dart';

/// Service chauffeur : courses disponibles, accepter, arrivé, démarrer, terminer.
class DriverRidesService {
  DriverRidesService({required ApiClient apiClient}) : _api = apiClient;
  final ApiClient _api;

  /// GET /rides/driver/available
  Future<List<Map<String, dynamic>>> getAvailable() async {
    final res = await _api.get('/rides/driver/available');
    final data = res['data'];
    if (data is List) {
      return data
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    }
    return [];
  }

  /// POST /rides/:id/accept (header Idempotency-Key requis)
  Future<Map<String, dynamic>> accept(int id, {String? idempotencyKey}) async {
    final options = idempotencyKey != null && idempotencyKey.isNotEmpty
        ? Options(headers: {'Idempotency-Key': idempotencyKey})
        : null;
    final res = await _api.request(
      '/rides/$id/accept',
      method: 'POST',
      options: options,
    );
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// POST /rides/:id/arrived
  Future<Map<String, dynamic>> arrived(int id) async {
    final res = await _api.post('/rides/$id/arrived');
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// POST /rides/:id/start
  Future<Map<String, dynamic>> start(int id) async {
    final res = await _api.post('/rides/$id/start');
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// POST /rides/:id/complete
  Future<Map<String, dynamic>> complete(
    int id, {
    required double actualDistanceKm,
    required int actualDurationMin,
  }) async {
    final res = await _api.post('/rides/$id/complete', data: {
      'actual_distance_km': actualDistanceKm,
      'actual_duration_min': actualDurationMin,
    });
    return res['data'] as Map<String, dynamic>? ?? {};
  }

  /// POST /rides/:id/location — envoi position GPS pendant la course (suivi en temps réel)
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
    await _api.post('/rides/$id/location', data: data);
  }

  /// POST /rides/:id/cancel-driver — annuler une course (chauffeur)
  Future<Map<String, dynamic>> cancel(int id, {String? reason}) async {
    final res = await _api.post('/rides/$id/cancel-driver', data: {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    return res['data'] as Map<String, dynamic>? ?? {};
  }
}
