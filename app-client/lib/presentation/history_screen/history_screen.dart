import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/deliveries_service.dart';
import '../../services/rides_service.dart';

/// Écran Historique : liste des courses et livraisons du client.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rides = [];
  List<Map<String, dynamic>> _deliveries = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = AuthService();
      await auth.loadStoredAuth();
      if (auth.token == null || auth.token!.isEmpty) {
        setState(() {
          _error = 'Connectez-vous pour voir votre historique';
          _loading = false;
        });
        return;
      }
      final ridesService = RidesService(apiClient: auth.apiClient);
      final deliveriesService = DeliveriesService(apiClient: auth.apiClient);

      final results = await Future.wait([
        ridesService.getMyRides(),
        deliveriesService.getMyDeliveries(),
      ]);

      // Les services retournent directement res['data'] qui est un array
      dynamic ridesRaw = results[0];
      dynamic deliveriesRaw = results[1];

      // Si c'est un array, utiliser directement
      // Si c'est un Map, chercher 'items', 'rides', 'data'
      List<dynamic> ridesList = [];
      if (ridesRaw is List) {
        ridesList = ridesRaw;
      } else if (ridesRaw is Map) {
        final extracted = ridesRaw['items'] ??
            ridesRaw['rides'] ??
            ridesRaw['data'] ??
            [];
        ridesList = extracted is List ? extracted : [];
      }

      List<dynamic> deliveriesList = [];
      if (deliveriesRaw is List) {
        deliveriesList = deliveriesRaw;
      } else if (deliveriesRaw is Map) {
        final extracted = deliveriesRaw['items'] ??
            deliveriesRaw['deliveries'] ??
            deliveriesRaw['data'] ??
            [];
        deliveriesList = extracted is List ? extracted : [];
      }

      final ridesData = ridesList;
      final deliveriesData = deliveriesList;

      setState(() {
        _rides = ridesData
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _deliveries = deliveriesData
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Erreur lors du chargement de l’historique';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Courses'),
            Tab(text: 'Livraisons'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRidesList(theme),
                    _buildDeliveriesList(theme),
                  ],
                ),
    );
  }

  Widget _buildRidesList(ThemeData theme) {
    if (_rides.isEmpty) {
      return const Center(child: Text('Aucune course pour le moment.'));
    }
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _rides.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final r = _rides[index];
          final code = r['ride_code'] ?? r['id'] ?? '-';
          final status = (r['status'] ?? '-').toString();
          final createdAt = (r['created_at'] ?? '').toString();
          final from = (r['pickup_address'] ?? 'Départ inconnu').toString();
          final to = (r['dropoff_address'] ?? 'Arrivée inconnue').toString();

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(Icons.directions_bike,
                  color: theme.colorScheme.primary),
            ),
            title: Text('Course $code'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$from → $to',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  'Statut: $status',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                if (createdAt.isNotEmpty)
                  Text(
                    createdAt,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
              ],
            ),
            onTap: () {
              final id = r['id'];
              if (id != null) {
                final idInt = id is int ? id : int.tryParse(id.toString());
                if (idInt != null) {
                  Navigator.of(context).pushNamed(
                    '/ride-detail-screen',
                    arguments: idInt,
                  );
                }
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildDeliveriesList(ThemeData theme) {
    if (_deliveries.isEmpty) {
      return const Center(child: Text('Aucune livraison pour le moment.'));
    }
    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _deliveries.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final d = _deliveries[index];
          final code = d['delivery_code'] ?? d['id'] ?? '-';
          final status = (d['status'] ?? '-').toString();
          final createdAt = (d['created_at'] ?? '').toString();
          final from = (d['pickup_address'] ?? 'Prise en charge inconnue')
              .toString();
          final to =
              (d['dropoff_address'] ?? 'Destination inconnue').toString();

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Icon(Icons.local_shipping,
                  color: theme.colorScheme.secondary),
            ),
            title: Text('Livraison $code'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$from → $to',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  'Statut: $status',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.secondary),
                ),
                if (createdAt.isNotEmpty)
                  Text(
                    createdAt,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
              ],
            ),
            onTap: () {
              final id = d['id'];
              if (id != null) {
                final idInt = id is int ? id : int.tryParse(id.toString());
                if (idInt != null) {
                  Navigator.of(context).pushNamed(
                    '/delivery-detail-screen',
                    arguments: idInt,
                  );
                }
              }
            },
          );
        },
      ),
    );
  }
}

