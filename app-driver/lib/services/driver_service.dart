import '../core/network/api_client.dart';

/// Service chauffeur : statut en ligne, position, etc.
class DriverService {
  DriverService({required ApiClient apiClient}) : _api = apiClient;
  final ApiClient _api;

  /// Met à jour le statut en ligne / disponible du chauffeur.
  /// PUT /users/drivers/:id/status
  Future<Map<String, dynamic>> updateStatus({
    required int driverId,
    required bool isOnline,
    required bool isAvailable,
  }) async {
    final res = await _api.put('/users/drivers/$driverId/status', data: {
      'is_online': isOnline,
      'is_available': isAvailable,
    });
    return res['data'] as Map<String, dynamic>? ?? {};
  }
}
