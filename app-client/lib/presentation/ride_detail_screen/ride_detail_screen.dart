import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/rides_service.dart';

/// Écran de détail d'une course avec possibilité d'annulation.
class RideDetailScreen extends StatefulWidget {
  const RideDetailScreen({super.key, required this.rideId});

  final int rideId;

  @override
  State<RideDetailScreen> createState() => _RideDetailScreenState();
}

class _RideDetailScreenState extends State<RideDetailScreen> {
  bool _loading = true;
  bool _cancelling = false;
  String? _error;
  Map<String, dynamic>? _ride;

  @override
  void initState() {
    super.initState();
    _loadRide();
  }

  Future<void> _loadRide() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = AuthService();
      await auth.loadStoredAuth();
      if (auth.token == null) {
        setState(() {
          _error = 'Connectez-vous pour voir les détails';
          _loading = false;
        });
        return;
      }
      final service = RidesService(apiClient: auth.apiClient);
      final data = await service.getById(widget.rideId);
      if (!mounted) return;
      setState(() {
        _ride = data;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? 'Erreur';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Erreur réseau';
        _loading = false;
      });
    }
  }

  bool get _canCancel {
    if (_ride == null) return false;
    final status = (_ride!['status'] ?? '').toString().toUpperCase();
    return ['REQUESTED', 'DRIVER_ASSIGNED', 'DRIVER_ARRIVED'].contains(status);
  }

  Future<void> _cancelRide() async {
    if (!_canCancel) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler la course'),
        content: const Text('Êtes-vous sûr de vouloir annuler cette course ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _cancelling = true;
      _error = null;
    });
    try {
      final auth = AuthService();
      await auth.loadStoredAuth();
      final service = RidesService(apiClient: auth.apiClient);
      final data = await service.cancel(widget.rideId);
      if (!mounted) return;
      setState(() {
        _ride = data;
        _cancelling = false;
      });
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Course annulée')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? 'Erreur lors de l\'annulation';
        _cancelling = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Erreur réseau';
        _cancelling = false;
      });
    }
  }

  String _statusLabel(String? status) {
    switch (status?.toUpperCase()) {
      case 'REQUESTED':
        return 'En attente de chauffeur';
      case 'DRIVER_ASSIGNED':
        return 'Chauffeur assigné';
      case 'DRIVER_ARRIVED':
        return 'Chauffeur arrivé';
      case 'IN_PROGRESS':
        return 'En cours';
      case 'COMPLETED':
        return 'Terminée';
      case 'CANCELLED_BY_CLIENT':
        return 'Annulée par vous';
      case 'CANCELLED_BY_DRIVER':
        return 'Annulée par le chauffeur';
      case 'CANCELLED_BY_SYSTEM':
        return 'Annulée (timeout)';
      default:
        return status ?? '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail de la course'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadRide,
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
              : _ride == null
                  ? const Center(child: Text('Course introuvable'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Course ${_ride!['ride_code'] ?? _ride!['id']}',
                                        style: theme.textTheme.titleLarge,
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primaryContainer,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          _statusLabel(_ride!['status']),
                                          style: theme.textTheme.labelMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _buildInfoRow(
                                    theme,
                                    Icons.trip_origin,
                                    'Départ',
                                    _ride!['pickup_address'] ?? '—',
                                  ),
                                  const SizedBox(height: 12),
                                  _buildInfoRow(
                                    theme,
                                    Icons.location_on,
                                    'Arrivée',
                                    _ride!['dropoff_address'] ?? '—',
                                  ),
                                  if (_ride!['estimated_fare'] != null ||
                                      _ride!['fare_final'] != null) ...[
                                    const SizedBox(height: 12),
                                    _buildInfoRow(
                                      theme,
                                      Icons.attach_money,
                                      'Prix',
                                      _ride!['fare_final'] != null
                                          ? '${_ride!['fare_final']} FCFA'
                                          : '${_ride!['estimated_fare']} FCFA (estimé)',
                                    ),
                                  ],
                                  if (_ride!['created_at'] != null) ...[
                                    const SizedBox(height: 12),
                                    _buildInfoRow(
                                      theme,
                                      Icons.access_time,
                                      'Créée le',
                                      _ride!['created_at'].toString(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (_canCancel && !_cancelling) ...[
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _cancelRide,
                              icon: const Icon(Icons.cancel),
                              label: const Text('Annuler la course'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: theme.colorScheme.error,
                                side: BorderSide(color: theme.colorScheme.error),
                              ),
                            ),
                          ],
                          if (_cancelling) ...[
                            const SizedBox(height: 16),
                            const Center(child: CircularProgressIndicator()),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            Text(
                              _error!,
                              style: TextStyle(color: theme.colorScheme.error),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Widget _buildInfoRow(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
