import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/deliveries_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/routing_service.dart';

const _defaultCenter = LatLng(14.7167, -17.4677);
const _defaultZoom = 13.0;

enum DeliveryNature {
  parcel('Paquet / colis', 'standard'),
  luggage('Bagage', 'standard'),
  food('Food', 'food');

  const DeliveryNature(this.label, this.apiValue);
  final String label;
  final String apiValue;
}

/// Écran de demande de livraison express :
/// - Lieu de prise en charge (défaut = position actuelle)
/// - Lieu de livraison (recherche ou clic carte)
/// - Nature (paquet/colis, bagage, food)
/// - Itinéraire + prix + temps + km
/// - Bouton Commander
class DeliveryOrderScreen extends StatefulWidget {
  const DeliveryOrderScreen({super.key});

  @override
  State<DeliveryOrderScreen> createState() => _DeliveryOrderScreenState();
}

class _DeliveryOrderScreenState extends State<DeliveryOrderScreen> {
  final MapController _mapController = MapController();

  final TextEditingController _dropoffSearchController = TextEditingController();

  LatLng? _pickup;
  String _pickupLabel = 'Position actuelle';

  LatLng? _dropoff;
  String _dropoffLabel = 'Où livrer ?';

  bool _editingPickup = false;

  DeliveryNature _nature = DeliveryNature.parcel;

  bool _locationLoading = false;
  String? _locationError;

  List<GeocodingResult> _dropoffResults = [];
  bool _dropoffSearching = false;

  List<LatLng> _routePoints = [];
  double? _estimateDistanceKm;
  int? _estimateDurationMin;
  String? _estimatePrice;
  bool _routeLoading = false;

  bool _isOrdering = false;
  String? _error;
  Map<String, dynamic>? _createdDelivery;
  Map<String, dynamic>? _deliveryDetail;
  List<Map<String, dynamic>> _nearbyDrivers = [];
  DateTime? _waitingStartTime;
  Timer? _dropoffDebounce;
  Timer? _pollTimer;
  Timer? _nearbyPollTimer;

  @override
  void initState() {
    super.initState();
    _dropoffSearchController.addListener(_onDropoffSearchChanged);
    _tryGetCurrentLocation();
  }

  @override
  void dispose() {
    _dropoffDebounce?.cancel();
    _pollTimer?.cancel();
    _nearbyPollTimer?.cancel();
    _dropoffSearchController.removeListener(_onDropoffSearchChanged);
    _dropoffSearchController.dispose();
    super.dispose();
  }

  // --- Localisation actuelle --------------------------------------------------

  Future<void> _tryGetCurrentLocation() async {
    setState(() {
      _locationLoading = true;
      _locationError = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          _locationLoading = false;
          _locationError = 'Activez la localisation';
        });
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
        if (!mounted) return;
        setState(() {
          _locationLoading = false;
          _locationError = 'Autorisez l\'accès à la position';
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      if (!mounted) return;
      setState(() {
        _pickup = LatLng(pos.latitude, pos.longitude);
        _pickupLabel = 'Position actuelle';
        _locationLoading = false;
        _locationError = null;
      });
      _mapController.move(_pickup!, 15);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locationLoading = false;
        _locationError = 'Impossible d\'obtenir la position';
      });
    }
  }

  // --- Recherche dropoff ------------------------------------------------------

  void _onDropoffSearchChanged() {
    _dropoffDebounce?.cancel();
    _dropoffDebounce = Timer(const Duration(milliseconds: 400), _runDropoffSearch);
  }

  Future<void> _runDropoffSearch() async {
    final q = _dropoffSearchController.text.trim();
    if (q.isEmpty) {
      setState(() => _dropoffResults = []);
      return;
    }
    setState(() => _dropoffSearching = true);
    final results = await GeocodingService.search(
      q,
      currentLat: _pickup?.latitude,
      currentLng: _pickup?.longitude,
    );
    if (!mounted) return;
    setState(() {
      _dropoffResults = results;
      _dropoffSearching = false;
    });
  }

  void _selectDropoffResult(GeocodingResult r) {
    setState(() {
      _dropoff = LatLng(r.lat, r.lng);
      _dropoffLabel = r.displayName;
      _dropoffSearchController.text = r.displayName;
      _dropoffResults = [];
      _clearRouteAndEstimate();
    });
    _mapController.move(LatLng(r.lat, r.lng), 16);
    _loadRouteAndEstimate();
  }

  // --- Carte & itinéraire ----------------------------------------------------

  void _clearRouteAndEstimate() {
    _routePoints = [];
    _estimateDistanceKm = null;
    _estimateDurationMin = null;
    _estimatePrice = null;
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    if (_editingPickup) {
      setState(() {
        _pickup = point;
        _pickupLabel = 'Point sur la carte';
        _editingPickup = false;
        _clearRouteAndEstimate();
      });
      if (_dropoff != null) _loadRouteAndEstimate();
    } else {
      setState(() {
        _dropoff = point;
        _dropoffLabel = 'Point sur la carte';
        _dropoffSearchController.clear();
        _dropoffResults = [];
        _clearRouteAndEstimate();
      });
      _loadRouteAndEstimate();
    }
  }

  Future<void> _loadRouteAndEstimate() async {
    if (_pickup == null || _dropoff == null) return;
    setState(() {
      _routeLoading = true;
      _error = null;
      _clearRouteAndEstimate();
    });
    try {
      final auth = AuthService();
      await auth.loadStoredAuth();
      final service = DeliveriesService(apiClient: auth.apiClient);

      final results = await Future.wait([
        RoutingService.getRoutePolyline(_pickup!, _dropoff!),
        service.estimate(
          pickupLat: _pickup!.latitude,
          pickupLng: _pickup!.longitude,
          dropoffLat: _dropoff!.latitude,
          dropoffLng: _dropoff!.longitude,
          packageType: _nature.apiValue,
          packageWeightKg: 2,
        ),
      ]);

      final routePoints = results[0] as List<LatLng>;
      final estimate = results[1] as Map<String, dynamic>;

      final fare = estimate['fare_estimate'] ?? estimate['estimated_fare'];
      final distanceKm = estimate['distance_km'];
      final durationMin = estimate['duration_min'];

      if (!mounted) return;
      setState(() {
        _routePoints = routePoints;
        _estimatePrice = fare != null ? '$fare FCFA' : '—';
        _estimateDistanceKm = distanceKm is num ? distanceKm.toDouble() : null;
        _estimateDurationMin = durationMin is int ? durationMin : (durationMin is num ? durationMin.toInt() : null);
        _routeLoading = false;
      });
      _fitMapToRoute();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? 'Erreur';
        _routeLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Erreur réseau';
        _routeLoading = false;
      });
    }
  }

  void _fitMapToRoute() {
    if (_pickup == null || _dropoff == null || _routePoints.isEmpty) return;
    final bounds = LatLngBounds.fromPoints([_pickup!, _dropoff!, ..._routePoints]);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(48),
      ),
    );
  }

  // --- Création de la livraison ----------------------------------------------

  Future<void> _order() async {
    if (_pickup == null || _dropoff == null) return;
    setState(() {
      _isOrdering = true;
      _error = null;
    });
    try {
      final auth = AuthService();
      await auth.loadStoredAuth();
      if (auth.token == null || auth.token!.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = 'Connectez-vous pour demander une livraison';
          _isOrdering = false;
        });
        return;
      }
      final service = DeliveriesService(apiClient: auth.apiClient);
      final data = await service.create(
        pickupLat: _pickup!.latitude,
        pickupLng: _pickup!.longitude,
        dropoffLat: _dropoff!.latitude,
        dropoffLng: _dropoff!.longitude,
        pickupAddress: _pickupLabel.isEmpty ? null : _pickupLabel,
        dropoffAddress: _dropoffLabel.isEmpty ? null : _dropoffLabel,
        packageType: _nature.apiValue,
        packageWeightKg: 2,
      );
      if (!mounted) return;
      final deliveryId = data['id'] is int ? data['id'] as int : int.tryParse(data['id'].toString());
      if (deliveryId == null) return;
      setState(() {
        _createdDelivery = data;
        _deliveryDetail = data;
        _waitingStartTime = DateTime.now();
        _isOrdering = false;
      });
      _startPolling(deliveryId);
      HapticFeedback.mediumImpact();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? 'Erreur';
        _isOrdering = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Erreur réseau';
        _isOrdering = false;
      });
    }
  }

  void _startPolling(int deliveryId) {
    _pollTimer?.cancel();
    _nearbyPollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollDelivery(deliveryId));
    _nearbyPollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _pollNearbyDrivers(deliveryId));
    _pollDelivery(deliveryId);
    _pollNearbyDrivers(deliveryId);
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _nearbyPollTimer?.cancel();
    _nearbyPollTimer = null;
  }

  Future<void> _pollDelivery(int deliveryId) async {
    if (_createdDelivery == null) return;
    final auth = AuthService();
    await auth.loadStoredAuth();
    if (auth.token == null) return;
    try {
      final detail = await DeliveriesService(apiClient: auth.apiClient).getById(deliveryId);
      if (!mounted) return;
      final status = detail['status']?.toString() ?? '';
      setState(() => _deliveryDetail = detail);
      if (status == 'DELIVERED' || status == 'PAID') {
        _stopPolling();
        _showRatingDialog(deliveryId);
      }
      if (status == 'CANCELLED_BY_CLIENT' || status == 'CANCELLED_BY_DRIVER' || status == 'CANCELLED_BY_SYSTEM') {
        _stopPolling();
        setState(() {
          _createdDelivery = null;
          _deliveryDetail = null;
          _nearbyDrivers = [];
        });
      }
    } catch (_) {}
  }

  Future<void> _pollNearbyDrivers(int deliveryId) async {
    if (_createdDelivery == null || (_deliveryDetail?['status']?.toString() ?? '') != 'REQUESTED') return;
    final auth = AuthService();
    await auth.loadStoredAuth();
    if (auth.token == null) return;
    try {
      final list = await DeliveriesService(apiClient: auth.apiClient).getNearbyDrivers(deliveryId);
      if (mounted) setState(() => _nearbyDrivers = list);
    } catch (_) {}
  }

  Future<void> _cancelDelivery(int deliveryId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la livraison'),
        content: const Text('Voulez-vous vraiment annuler cette livraison ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui, annuler')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final auth = AuthService();
    await auth.loadStoredAuth();
    try {
      await DeliveriesService(apiClient: auth.apiClient).cancel(deliveryId);
      if (!mounted) return;
      _stopPolling();
      setState(() {
        _createdDelivery = null;
        _deliveryDetail = null;
        _nearbyDrivers = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Livraison annulée')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  void _showRatingDialog(int deliveryId) {
    int rating = 5;
    final commentController = TextEditingController();
    final reportController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Noter votre livraison', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  const Text('Note'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final star = i + 1;
                      return IconButton(
                        icon: Icon(rating >= star ? Icons.star : Icons.star_border),
                        onPressed: () => setModalState(() => rating = star),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: commentController,
                    decoration: const InputDecoration(
                      labelText: 'Commentaire (optionnel)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reportController,
                    decoration: const InputDecoration(
                      labelText: 'Signaler un problème (optionnel)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final auth = AuthService();
                      await auth.loadStoredAuth();
                      final comment = commentController.text.trim();
                      final report = reportController.text.trim();
                      final finalComment = report.isNotEmpty ? '[Problème] $report${comment.isNotEmpty ? '\n$comment' : ''}' : comment;
                      try {
                        await DeliveriesService(apiClient: auth.apiClient).rate(
                          deliveryId,
                          rating: rating,
                          comment: finalComment.isEmpty ? null : finalComment,
                        );
                        if (!mounted) return;
                        setState(() {
                          _createdDelivery = null;
                          _deliveryDetail = null;
                          _nearbyDrivers = [];
                        });
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Merci pour votre avis')));
                      } catch (_) {}
                    },
                    child: const Text('Envoyer'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _launchCall(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone.trim());
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchSms(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'sms', path: phone.trim());
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Widget _buildDeliveryStatusCard(ThemeData theme) {
    final status = _deliveryDetail!['status']?.toString() ?? '';
    final deliveryIdRaw = _createdDelivery!['id'];
    final deliveryId = deliveryIdRaw is int ? deliveryIdRaw : int.tryParse(deliveryIdRaw?.toString() ?? '');

    if (status == 'REQUESTED') {
      final elapsed = _waitingStartTime != null
          ? DateTime.now().difference(_waitingStartTime!).inSeconds
          : 0;
      return Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Recherche d\'un chauffeur...',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Temps d\'attente: ${elapsed ~/ 60} min ${elapsed % 60} s', style: theme.textTheme.bodyMedium),
              Text('Ref: ${_createdDelivery!['delivery_code'] ?? _createdDelivery!['id']}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              Text('Chauffeurs à proximité: ${_nearbyDrivers.length}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              if (deliveryId != null)
                OutlinedButton(
                  onPressed: () => _cancelDelivery(deliveryId),
                  child: const Text('Annuler la livraison'),
                ),
            ],
          ),
        ),
      );
    }

    if (status == 'ASSIGNED' || status == 'PICKED_UP' || status == 'IN_TRANSIT') {
      final driverName =
          '${_deliveryDetail!['driver_first_name'] ?? ''} ${_deliveryDetail!['driver_last_name'] ?? ''}'.trim();
      final driverPhoto = _deliveryDetail!['driver_avatar_url']?.toString();
      final driverRating = _deliveryDetail!['driver_average_rating'];
      final driverPhone = _deliveryDetail!['driver_phone']?.toString();
      final statusLabel = status == 'ASSIGNED'
          ? 'Chauffeur en route'
          : status == 'PICKED_UP'
              ? 'Colis récupéré'
              : 'En cours de livraison';

      return Card(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(statusLabel, style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    backgroundImage: driverPhoto != null && driverPhoto.isNotEmpty
                        ? NetworkImage(driverPhoto)
                        : null,
                    child: driverPhoto == null || driverPhoto.isEmpty
                        ? Text(
                            driverName.isNotEmpty ? driverName[0].toUpperCase() : '?',
                            style: theme.textTheme.titleLarge,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(driverName.isNotEmpty ? driverName : 'Chauffeur', style: theme.textTheme.titleSmall),
                        if (driverRating != null)
                          Row(
                            children: [
                              Icon(Icons.star, size: 16, color: theme.colorScheme.primary),
                              const SizedBox(width: 4),
                              Text(
                                (driverRating is num) ? (driverRating as num).toStringAsFixed(1) : driverRating.toString(),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        Text(
                          'Temps estimé: ~${_estimateDurationMin ?? '?'} min',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _launchCall(driverPhone),
                      icon: const Icon(Icons.phone, size: 20),
                      label: const Text('Appeler'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _launchSms(driverPhone),
                      icon: const Icon(Icons.message, size: 20),
                      label: const Text('Message'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Statut: $status', style: theme.textTheme.titleMedium),
            Text('Ref: ${_createdDelivery!['delivery_code'] ?? _createdDelivery!['id']}'),
          ],
        ),
      ),
    );
  }

  // --- UI ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Livraison express'),
      ),
      body: Column(
        children: [
          // Carte : même hauteur que l'écran course (flex: 3)
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _pickup ?? _defaultCenter,
                    initialZoom: _pickup != null ? 15.0 : _defaultZoom,
                    onTap: _onMapTap,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'dev.motoride.app',
                    ),
                    if (_routePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            strokeWidth: 5,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        if (_pickup != null)
                          Marker(
                            point: _pickup!,
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
                          ),
                        if (_dropoff != null)
                          Marker(
                            point: _dropoff!,
                            width: 40,
                            height: 40,
                            child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                          ),
                        for (final d in _nearbyDrivers)
                          if (d['lat'] != null && d['lng'] != null)
                            Marker(
                              point: LatLng(
                                (d['lat'] is num) ? (d['lat'] as num).toDouble() : double.tryParse(d['lat'].toString()) ?? 0,
                                (d['lng'] is num) ? (d['lng'] as num).toDouble() : double.tryParse(d['lng'].toString()) ?? 0,
                              ),
                              width: 32,
                              height: 32,
                              child: const Icon(Icons.two_wheeler, color: Colors.green, size: 32),
                            ),
                        if (_deliveryDetail != null)
                          ...(){
                            final lat = _deliveryDetail!['driver_lat'];
                            final lng = _deliveryDetail!['driver_lng'];
                            if (lat == null || lng == null) return <Marker>[];
                            final latD = (lat is num) ? lat.toDouble() : double.tryParse(lat.toString());
                            final lngD = (lng is num) ? lng.toDouble() : double.tryParse(lng.toString());
                            if (latD == null || lngD == null) return <Marker>[];
                            return [
                              Marker(
                                point: LatLng(latD, lngD),
                                width: 40,
                                height: 40,
                                child: const Icon(Icons.delivery_dining, color: Colors.orange, size: 40),
                              ),
                            ];
                          }(),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(8),
                    child: IconButton(
                      onPressed: _locationLoading ? null : _tryGetCurrentLocation,
                      icon: _locationLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                      tooltip: 'Ma position',
                    ),
                  ),
                ),
                if (_locationError != null)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(8),
                      color: theme.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(
                          _locationError!,
                          style: TextStyle(color: theme.colorScheme.onErrorContainer),
                        ),
                      ),
                    ),
                  ),
                if (_editingPickup)
                  Positioned(
                    bottom: 12,
                    left: 12,
                    right: 12,
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(8),
                      color: theme.colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Appuyez sur la carte pour définir le lieu de prise en charge',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Formulaire & actions (flex: 2, même ratio que course)
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_pin_circle, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Lieu de prise en charge ($_pickupLabel)',
                          style: theme.textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _editingPickup = true),
                        child: const Text('Modifier'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _dropoffSearchController,
                    decoration: InputDecoration(
                      labelText: 'Lieu de livraison',
                      hintText: 'Rechercher ou cliquer sur la carte',
                      prefixIcon: const Icon(Icons.location_on),
                      border: const OutlineInputBorder(),
                      suffixIcon: _dropoffSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                    ),
                  ),
                  if (_dropoffResults.isNotEmpty)
                    Card(
                      margin: const EdgeInsets.only(top: 8),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _dropoffResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final r = _dropoffResults[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              r.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                            onTap: () => _selectDropoffResult(r),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<DeliveryNature>(
                    value: _nature,
                    decoration: const InputDecoration(
                      labelText: 'Nature du colis',
                      border: OutlineInputBorder(),
                    ),
                    items: DeliveryNature.values
                        .map((n) => DropdownMenuItem(value: n, child: Text(n.label)))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _nature = v;
                        _clearRouteAndEstimate();
                      });
                      if (_pickup != null && _dropoff != null) _loadRouteAndEstimate();
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  if (_createdDelivery != null && _deliveryDetail != null) ...[
                    const SizedBox(height: 12),
                    _buildDeliveryStatusCard(theme),
                  ] else if (_dropoff != null) ...[
                    const SizedBox(height: 12),
                    if (_routeLoading)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      )
                    else
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Livraison', style: theme.textTheme.labelLarge),
                              const SizedBox(height: 4),
                              Text(
                                _dropoffLabel,
                                style: theme.textTheme.bodyLarge,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  if (_estimatePrice != null)
                                    Text(_estimatePrice!, style: theme.textTheme.titleLarge),
                                  if (_estimateDurationMin != null)
                                    Text('${_estimateDurationMin} min', style: theme.textTheme.bodyMedium),
                                  if (_estimateDistanceKm != null)
                                    Text('${_estimateDistanceKm!.toStringAsFixed(1)} km',
                                        style: theme.textTheme.bodyMedium),
                                ],
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: (_isOrdering || _estimatePrice == null) ? null : _order,
                                icon: _isOrdering
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.local_shipping),
                                label: Text(_isOrdering ? 'Envoi...' : 'Commander'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 48),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

