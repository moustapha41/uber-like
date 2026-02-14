import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/deliveries_service.dart';

/// Écran de détail d'une livraison avec possibilité d'annulation.
class DeliveryDetailScreen extends StatefulWidget {
  const DeliveryDetailScreen({super.key, required this.deliveryId});

  final int deliveryId;

  @override
  State<DeliveryDetailScreen> createState() => _DeliveryDetailScreenState();
}

class _DeliveryDetailScreenState extends State<DeliveryDetailScreen> {
  bool _loading = true;
  bool _cancelling = false;
  String? _error;
  Map<String, dynamic>? _delivery;

  @override
  void initState() {
    super.initState();
    _loadDelivery();
  }

  Future<void> _loadDelivery() async {
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
      final service = DeliveriesService(apiClient: auth.apiClient);
      final data = await service.getById(widget.deliveryId);
      if (!mounted) return;
      setState(() {
        _delivery = data;
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
    if (_delivery == null) return false;
    final status = (_delivery!['status'] ?? '').toString().toUpperCase();
    return ['REQUESTED', 'ASSIGNED', 'PICKED_UP', 'IN_TRANSIT'].contains(status);
  }

  Future<void> _cancelDelivery() async {
    if (!_canCancel) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler la livraison'),
        content: const Text(
            'Êtes-vous sûr de vouloir annuler cette livraison ? Des frais d\'annulation peuvent s\'appliquer si le colis a déjà été récupéré.'),
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
      final service = DeliveriesService(apiClient: auth.apiClient);
      final data = await service.cancel(widget.deliveryId);
      if (!mounted) return;
      setState(() {
        _delivery = data;
        _cancelling = false;
      });
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Livraison annulée')),
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
      case 'ASSIGNED':
        return 'Chauffeur assigné';
      case 'PICKED_UP':
        return 'Colis récupéré';
      case 'IN_TRANSIT':
        return 'En route vers la destination';
      case 'DELIVERED':
        return 'Livrée';
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

  String _packageTypeLabel(String? type) {
    switch (type?.toLowerCase()) {
      case 'standard':
        return 'Paquet / colis';
      case 'food':
        return 'Food';
      case 'fragile':
        return 'Fragile';
      case 'document':
        return 'Document';
      case 'electronics':
        return 'Électronique';
      default:
        return type ?? '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail de la livraison'),
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
                          onPressed: _loadDelivery,
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
              : _delivery == null
                  ? const Center(child: Text('Livraison introuvable'))
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
                                        'Livraison ${_delivery!['delivery_code'] ?? _delivery!['id']}',
                                        style: theme.textTheme.titleLarge,
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.secondaryContainer,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          _statusLabel(_delivery!['status']),
                                          style: theme.textTheme.labelMedium,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  _buildInfoRow(
                                    theme,
                                    Icons.trip_origin,
                                    'Lieu de prise en charge',
                                    _delivery!['pickup_address'] ?? '—',
                                  ),
                                  const SizedBox(height: 12),
                                  _buildInfoRow(
                                    theme,
                                    Icons.location_on,
                                    'Lieu de livraison',
                                    _delivery!['dropoff_address'] ?? '—',
                                  ),
                                  if (_delivery!['package_type'] != null) ...[
                                    const SizedBox(height: 12),
                                    _buildInfoRow(
                                      theme,
                                      Icons.inventory_2,
                                      'Nature du colis',
                                      _packageTypeLabel(_delivery!['package_type']),
                                    ),
                                  ],
                                  if (_delivery!['package_weight_kg'] != null) ...[
                                    const SizedBox(height: 12),
                                    _buildInfoRow(
                                      theme,
                                      Icons.scale,
                                      'Poids',
                                      '${_delivery!['package_weight_kg']} kg',
                                    ),
                                  ],
                                  if (_delivery!['estimated_fare'] != null ||
                                      _delivery!['fare_final'] != null) ...[
                                    const SizedBox(height: 12),
                                    _buildInfoRow(
                                      theme,
                                      Icons.attach_money,
                                      'Prix',
                                      _delivery!['fare_final'] != null
                                          ? '${_delivery!['fare_final']} FCFA'
                                          : '${_delivery!['estimated_fare']} FCFA (estimé)',
                                    ),
                                  ],
                                  if (_delivery!['created_at'] != null) ...[
                                    const SizedBox(height: 12),
                                    _buildInfoRow(
                                      theme,
                                      Icons.access_time,
                                      'Créée le',
                                      _delivery!['created_at'].toString(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          if (_canCancel && !_cancelling) ...[
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _cancelDelivery,
                              icon: const Icon(Icons.cancel),
                              label: const Text('Annuler la livraison'),
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
        Icon(icon, size: 20, color: theme.colorScheme.secondary),
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
