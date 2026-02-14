import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/geocoding_service.dart';
import '../../services/rides_service.dart';
import '../../services/routing_service.dart';

/// Centre par défaut (Dakar).
const _defaultCenter = LatLng(14.7167, -17.4677);
const _defaultZoom = 13.0;

/// Écran de réservation d'une course avec carte, géolocalisation,
/// sélection de la destination et affichage de l'itinéraire.
class RideBookingScreen extends StatefulWidget {
  const RideBookingScreen({super.key});

  @override
  State<RideBookingScreen> createState() => _RideBookingScreenState();
}

class _RideBookingScreenState extends State<RideBookingScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _dropoffSearchController = TextEditingController();
  final TextEditingController _pickupSearchController = TextEditingController();

  LatLng? _pickup;
  String _pickupLabel = 'Position actuelle (localiser)';

  LatLng? _dropoff;
  String _dropoffLabel = 'Où allez-vous ?';

  bool _editingPickup = false;

  bool _locationLoading = false;
  String? _locationError;

  List<GeocodingResult> _searchResults = [];
  bool _searching = false;
  List<GeocodingResult> _pickupSearchResults = [];
  bool _pickupSearching = false;
  Timer? _pickupSearchDebounce;

  List<LatLng> _routePoints = [];
  double? _estimateDistanceKm;
  int? _estimateDurationMin;
  String? _estimatePrice;
  bool _routeLoading = false;

  bool _isBooking = false;
  String? _error;
  Map<String, dynamic>? _createdRide;
  Map<String, dynamic>? _rideDetail;
  List<Map<String, dynamic>> _nearbyDrivers = [];
  DateTime? _waitingStartTime;
  Timer? _searchDebounce;
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
    _searchDebounce?.cancel();
    _pickupSearchDebounce?.cancel();
    _pollTimer?.cancel();
    _nearbyPollTimer?.cancel();
    _dropoffSearchController.removeListener(_onDropoffSearchChanged);
    _dropoffSearchController.dispose();
    _pickupSearchController.dispose();
    super.dispose();
  }

  // ---- Localisation actuelle -------------------------------------------------

  Future<void> _tryGetCurrentLocation() async {
    setState(() {
      _locationLoading = true;
      _locationError = null;
    });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _locationLoading = false;
            _locationError = 'Activez la localisation';
          });
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            _locationLoading = false;
            _locationError = 'Autorisez l\'accès à la position';
          });
        }
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

  // ---- Recherche destination -------------------------------------------------

  void _onDropoffSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), _runDropoffSearch);
  }

  Future<void> _runDropoffSearch() async {
    final q = _dropoffSearchController.text.trim();
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() {
      _searching = true;
    });
    final results = await GeocodingService.search(
      q,
      currentLat: _pickup?.latitude,
      currentLng: _pickup?.longitude,
    );
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  void _selectSearchResult(GeocodingResult r) {
    setState(() {
      _dropoff = LatLng(r.lat, r.lng);
      _dropoffLabel = r.displayName;
      _dropoffSearchController.text = r.displayName;
      _searchResults = [];
      _clearRouteAndEstimate();
    });
    _mapController.move(LatLng(r.lat, r.lng), 16);
    _loadRouteAndEstimate();
  }

  void _onPickupSearchChanged() {
    _pickupSearchDebounce?.cancel();
    _pickupSearchDebounce = Timer(const Duration(milliseconds: 400), _runPickupSearch);
  }

  Future<void> _runPickupSearch() async {
    final q = _pickupSearchController.text.trim();
    if (q.isEmpty) {
      setState(() => _pickupSearchResults = []);
      return;
    }
    setState(() => _pickupSearching = true);
    final results = await GeocodingService.search(
      q,
      currentLat: _pickup?.latitude,
      currentLng: _pickup?.longitude,
    );
    if (!mounted) return;
    setState(() {
      _pickupSearchResults = results;
      _pickupSearching = false;
    });
  }

  void _selectPickupSearchResult(GeocodingResult r) {
    setState(() {
      _pickup = LatLng(r.lat, r.lng);
      _pickupLabel = r.displayName;
      _pickupSearchController.clear();
      _pickupSearchResults = [];
      _editingPickup = false;
      _clearRouteAndEstimate();
    });
    _mapController.move(LatLng(r.lat, r.lng), 16);
    if (_dropoff != null) _loadRouteAndEstimate();
  }

  // ---- Carte & itinéraire ----------------------------------------------------

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
        _pickupSearchController.clear();
        _pickupSearchResults = [];
        _clearRouteAndEstimate();
      });
      if (_dropoff != null) _loadRouteAndEstimate();
    } else {
      setState(() {
        _dropoff = point;
        _dropoffLabel = 'Point sur la carte';
        _dropoffSearchController.clear();
        _searchResults = [];
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
      final api = auth.apiClient;
      final ridesService = RidesService(apiClient: api);

      final results = await Future.wait([
        RoutingService.getRoutePolyline(_pickup!, _dropoff!),
        ridesService.estimate(
          pickupLat: _pickup!.latitude,
          pickupLng: _pickup!.longitude,
          dropoffLat: _dropoff!.latitude,
          dropoffLng: _dropoff!.longitude,
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

  // ---- Réservation -----------------------------------------------------------

  Future<void> _book() async {
    if (_pickup == null || _dropoff == null) return;
    setState(() {
      _isBooking = true;
      _error = null;
    });
    try {
      final auth = AuthService();
      await auth.loadStoredAuth();
      if (auth.token == null || auth.token!.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = 'Connectez-vous pour réserver';
          _isBooking = false;
        });
        return;
      }
      final service = RidesService(apiClient: auth.apiClient);
      final data = await service.create(
        pickupLat: _pickup!.latitude,
        pickupLng: _pickup!.longitude,
        dropoffLat: _dropoff!.latitude,
        dropoffLng: _dropoff!.longitude,
        pickupAddress: _pickupLabel.isEmpty ? null : _pickupLabel,
        dropoffAddress: _dropoffLabel.isEmpty ? null : _dropoffLabel,
      );
      if (!mounted) return;
      final rideId = data['id'] is int ? data['id'] as int : int.tryParse(data['id'].toString());
      if (rideId == null) return;
      setState(() {
        _createdRide = data;
        _rideDetail = data;
        _waitingStartTime = DateTime.now();
        _isBooking = false;
      });
      _startPolling(rideId);
      HapticFeedback.mediumImpact();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message ?? 'Erreur';
        _isBooking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Erreur réseau';
        _isBooking = false;
      });
    }
  }

  void _startPolling(int rideId) {
    _pollTimer?.cancel();
    _nearbyPollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollRide(rideId));
    _nearbyPollTimer = Timer.periodic(const Duration(seconds: 8), (_) => _pollNearbyDrivers(rideId));
    _pollRide(rideId);
    _pollNearbyDrivers(rideId);
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _nearbyPollTimer?.cancel();
    _nearbyPollTimer = null;
  }

  Future<void> _pollRide(int rideId) async {
    if (_createdRide == null) return;
    final auth = AuthService();
    await auth.loadStoredAuth();
    if (auth.token == null) return;
    try {
      final detail = await RidesService(apiClient: auth.apiClient).getById(rideId);
      if (!mounted) return;
      final status = detail['status']?.toString() ?? '';
      setState(() => _rideDetail = detail);
      if (status == 'COMPLETED' || status == 'PAID' || status == 'CLOSED') {
        _stopPolling();
        _showRatingDialog(rideId);
      }
      if (status == 'CANCELLED_BY_CLIENT' || status == 'CANCELLED_BY_DRIVER' || status == 'CANCELLED_BY_SYSTEM') {
        _stopPolling();
        setState(() {
          _createdRide = null;
          _rideDetail = null;
          _nearbyDrivers = [];
        });
      }
    } catch (_) {}
  }

  Future<void> _pollNearbyDrivers(int rideId) async {
    if (_createdRide == null || (_rideDetail?['status']?.toString() ?? '') != 'REQUESTED') return;
    final auth = AuthService();
    await auth.loadStoredAuth();
    if (auth.token == null) return;
    try {
      final list = await RidesService(apiClient: auth.apiClient).getNearbyDrivers(rideId);
      if (mounted) setState(() => _nearbyDrivers = list);
    } catch (_) {}
  }

  Future<void> _cancelRide(int rideId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la course'),
        content: const Text('Voulez-vous vraiment annuler cette course ?'),
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
      await RidesService(apiClient: auth.apiClient).cancel(rideId);
      if (!mounted) return;
      _stopPolling();
      setState(() {
        _createdRide = null;
        _rideDetail = null;
        _nearbyDrivers = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Course annulée')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    }
  }

  void _showRatingDialog(int rideId) {
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
                  Text('Noter votre course', style: Theme.of(ctx).textTheme.titleLarge),
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
                        await RidesService(apiClient: auth.apiClient).rate(
                          rideId,
                          rating: rating,
                          comment: finalComment.isEmpty ? null : finalComment,
                        );
                        if (!mounted) return;
                        setState(() {
                          _createdRide = null;
                          _rideDetail = null;
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

  Widget _buildRideStatusCard(ThemeData theme) {
    final status = _rideDetail!['status']?.toString() ?? '';
    final rideIdRaw = _createdRide!['id'];
    final rideId = rideIdRaw is int ? rideIdRaw : int.tryParse(rideIdRaw?.toString() ?? '');

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
              Text(
                'Temps d\'attente: ${elapsed ~/ 60} min ${elapsed % 60} s',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                'Ref: ${_createdRide!['ride_code'] ?? _createdRide!['id']}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Chauffeurs à proximité: ${_nearbyDrivers.length}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (rideId != null)
                OutlinedButton(
                  onPressed: () => _cancelRide(rideId),
                  child: const Text('Annuler la course'),
                ),
            ],
          ),
        ),
      );
    }

    if (status == 'DRIVER_ASSIGNED' || status == 'DRIVER_ARRIVED' || status == 'IN_PROGRESS') {
      final driverName =
          '${_rideDetail!['driver_first_name'] ?? ''} ${_rideDetail!['driver_last_name'] ?? ''}'.trim();
      final driverPhoto = _rideDetail!['driver_avatar_url']?.toString();
      final driverRating = _rideDetail!['driver_average_rating'];
      final driverPhone = _rideDetail!['driver_phone']?.toString();
      final statusLabel = status == 'DRIVER_ASSIGNED'
          ? 'Chauffeur en route'
          : status == 'DRIVER_ARRIVED'
              ? 'Chauffeur arrivé'
              : 'Course en cours';
      final rideIdRaw = _createdRide!['id'];
      final rideId = rideIdRaw is int ? rideIdRaw : int.tryParse(rideIdRaw?.toString() ?? '');

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
                        Text(
                          driverName.isNotEmpty ? driverName : 'Chauffeur',
                          style: theme.textTheme.titleSmall,
                        ),
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
                          'Temps d\'arrivée: ~${_estimateDurationMin ?? '?'} min',
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
              if (rideId != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _cancelRide(rideId),
                  icon: const Icon(Icons.cancel, size: 18),
                  label: const Text('Annuler la course'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                ),
              ],
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
            Text('Ref: ${_createdRide!['ride_code'] ?? _createdRide!['id']}'),
          ],
        ),
      ),
    );
  }

  // ---- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouvelle course'),
      ),
      body: Column(
        children: [
          // Carte (hauteur légèrement plus grande)
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
                        ..._nearbyDrivers.map((d) {
                          final lat = (d['lat'] is num) ? (d['lat'] as num).toDouble() : 0.0;
                          final lng = (d['lng'] is num) ? (d['lng'] as num).toDouble() : 0.0;
                          if (lat == 0 && lng == 0) return null;
                          return Marker(
                            point: LatLng(lat, lng),
                            width: 28,
                            height: 28,
                            child: const Icon(Icons.two_wheeler, color: Colors.green, size: 28),
                          );
                        }).whereType<Marker>(),
                        if (_rideDetail != null &&
                            _rideDetail!['driver_lat'] != null &&
                            _rideDetail!['driver_lng'] != null)
                          Marker(
                            point: LatLng(
                              (_rideDetail!['driver_lat'] as num).toDouble(),
                              (_rideDetail!['driver_lng'] as num).toDouble(),
                            ),
                            width: 44,
                            height: 44,
                            child: const Icon(Icons.two_wheeler, color: Colors.deepPurple, size: 44),
                          ),
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
                          'Appuyez sur la carte pour définir le lieu de départ',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Formulaire et actions
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
                          _pickupLabel,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _editingPickup = true;
                          _pickupSearchController.clear();
                          _pickupSearchResults = [];
                        }),
                        child: const Text('Modifier'),
                      ),
                    ],
                  ),
                  if (_editingPickup) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _pickupSearchController,
                      onChanged: (_) => _onPickupSearchChanged(),
                      decoration: InputDecoration(
                        hintText: 'Point de départ (ou sélectionner depuis la carte)',
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        suffixIcon: _pickupSearching
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
                    if (_pickupSearchResults.isNotEmpty)
                      Card(
                        margin: const EdgeInsets.only(top: 8),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _pickupSearchResults.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final r = _pickupSearchResults[index];
                            return ListTile(
                              dense: true,
                              title: Text(
                                r.displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                              onTap: () => _selectPickupSearchResult(r),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _dropoffSearchController,
                    decoration: InputDecoration(
                      labelText: 'Destination',
                      hintText: 'Rechercher une adresse ou cliquer sur la carte',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      suffixIcon: _searching
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
                  if (_searchResults.isNotEmpty)
                    Card(
                      margin: const EdgeInsets.only(top: 8),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final r = _searchResults[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              r.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                            onTap: () => _selectSearchResult(r),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    _dropoff != null
                        ? 'Arrivée: $_dropoffLabel'
                        : 'Cliquez sur la carte pour choisir la destination',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _dropoff != null ? theme.colorScheme.primary : theme.colorScheme.outline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  if (_createdRide != null && _rideDetail != null) ...[
                    const SizedBox(height: 12),
                    _buildRideStatusCard(theme),
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
                              Text('Trajet', style: theme.textTheme.labelLarge),
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
                                    Text(
                                      _estimatePrice!,
                                      style: theme.textTheme.titleLarge,
                                    ),
                                  if (_estimateDurationMin != null)
                                    Text(
                                      '${_estimateDurationMin} min',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  if (_estimateDistanceKm != null)
                                    Text(
                                      '${_estimateDistanceKm!.toStringAsFixed(1)} km',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: (_isBooking || _estimatePrice == null) ? null : _book,
                                icon: _isBooking
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.directions_bike),
                                label: Text(_isBooking ? 'Envoi...' : 'Commander'),
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

