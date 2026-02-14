import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:sizer/sizer.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dart:async';
import 'dart:math';

import '../../core/app_export.dart';
import '../../services/auth_service.dart';
import '../../services/driver_deliveries_service.dart';
import '../../services/driver_rides_service.dart';
import '../../services/driver_service.dart';
import '../../services/routing_service.dart';
import '../../services/geocoding_service.dart';
import './widgets/navigation_overlay_widget.dart';
import './widgets/order_notification_widget.dart';
import './widgets/preference_bottom_sheet_widget.dart';

class MainMapScreenInitialPage extends StatefulWidget {
  const MainMapScreenInitialPage({super.key});

  @override
  State<MainMapScreenInitialPage> createState() =>
      _MainMapScreenInitialPageState();
}

class _MainMapScreenInitialPageState extends State<MainMapScreenInitialPage> {
  late final MapController _mapController;
  Position? _currentPosition;
  LatLng? _currentLatLng;
  bool _isMapReady = false;
  bool _isOnline = false;
  bool _showOrderNotification = false;
  bool _showNavigationOverlay = false;
  Map<String, dynamic>? _currentOrder;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Map<String, dynamic>? _driverUser;

  List<Map<String, dynamic>> _availableRides = [];
  List<Map<String, dynamic>> _availableDeliveries = [];
  bool _loadingAvailable = false;
  Timer? _pollTimer;
  Timer? _pendingDemandTimer;
  Map<String, dynamic>? _currentMission;
  Map<String, dynamic>? _pendingDemand;
  static const int _pendingDemandDurationSeconds = 15;
  Timer? _locationTrackingTimer;
  List<LatLng> _routePolyline = [];
  bool _routeLoading = false;
  bool _isMissionCardExpanded = false;

  final List<Map<String, dynamic>> _mockOrders = [
    {
      "orderId": "ORD-2026-001",
      "type": "Ride",
      "pickupLocation": "15 Rue de la République, Paris",
      "pickupLat": 48.8566,
      "pickupLng": 2.3522,
      "deliveryLocation": "42 Avenue des Champs-Élysées, Paris",
      "deliveryLat": 48.8698,
      "deliveryLng": 2.3078,
      "estimatedEarnings": "12,50 €",
      "distance": "3,2 km",
      "estimatedTime": "15 min",
      "customerName": "Marie Dubois",
      "customerPhone": "+33 6 12 34 56 78",
      "customerRating": 4.8,
      "customerImage":
          "https://img.rocket.new/generatedImages/rocket_gen_img_1453e1878-1763300003100.png",
      "semanticLabel":
          "Profile photo of a woman with shoulder-length brown hair wearing a light blue blouse",
    },
    {
      "orderId": "ORD-2026-002",
      "type": "Delivery",
      "pickupLocation": "Restaurant Le Petit Bistro, 8 Rue Saint-Antoine",
      "pickupLat": 48.8534,
      "pickupLng": 2.3642,
      "deliveryLocation": "28 Boulevard Voltaire, Paris",
      "deliveryLat": 48.8631,
      "deliveryLng": 2.3708,
      "estimatedEarnings": "8,75 €",
      "distance": "1,8 km",
      "estimatedTime": "10 min",
      "customerName": "Jean Martin",
      "customerPhone": "+33 6 98 76 54 32",
      "customerRating": 4.5,
      "customerImage":
          "https://img.rocket.new/generatedImages/rocket_gen_img_1ad36cffb-1763296582563.png",
      "semanticLabel":
          "Profile photo of a man with short gray hair and glasses wearing a dark sweater",
    },
  ];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadAuth();
    _getCurrentLocation();
  }

  Future<void> _loadAuth() async {
    final auth = AuthService();
    await auth.loadStoredAuth();
    if (mounted) setState(() => _driverUser = auth.user);
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    setState(() {
      _currentPosition = position;
    });

    setState(() {
      _currentLatLng = LatLng(position.latitude, position.longitude);
    });

    if (_isMapReady && _currentLatLng != null) {
      _mapController.move(_currentLatLng!, 15.0);
    }
  }

  Future<void> _toggleOnlineStatus() async {
    final auth = AuthService();
    await auth.loadStoredAuth();
    final driverId = auth.driverId;
    if (driverId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session invalide. Reconnectez-vous.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final newOnline = !_isOnline;
    setState(() => _isOnline = newOnline);
    HapticFeedback.mediumImpact();

    final driverService = DriverService(apiClient: auth.apiClient);
    try {
      await driverService.updateStatus(
        driverId: driverId,
        isOnline: newOnline,
        isAvailable: newOnline,
      );
      if (mounted) {
        if (newOnline) {
          _loadAvailableRequests();
          _pollTimer?.cancel();
          _pollTimer = Timer.periodic(
            const Duration(seconds: 12),
            (_) => _loadAvailableRequests(),
          );
        } else {
          _pollTimer?.cancel();
          _pollTimer = null;
          _stopLocationTracking();
          setState(() {
            _availableRides = [];
            _availableDeliveries = [];
            _currentMission = null;
            _routePolyline = [];
            _pendingDemand = null;
            _pendingDemandTimer?.cancel();
            _pendingDemandTimer = null;
            _showOrderNotification = false;
            _currentOrder = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isOnline = !newOnline);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur statut: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _acceptOrder() {
    setState(() {
      _showOrderNotification = false;
      _showNavigationOverlay = true;
    });

    HapticFeedback.lightImpact();
  }

  void _declineOrder() {
    setState(() {
      _showOrderNotification = false;
      _currentOrder = null;
    });
    HapticFeedback.lightImpact();
  }

  /// Distance en km entre deux points (formule approchée).
  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lng2 - lng1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  Future<void> _loadAvailableRequests() async {
    if (!_isOnline || _currentMission != null) return;
    final auth = AuthService();
    await auth.loadStoredAuth();
    if (auth.driverId == null) return;
    setState(() => _loadingAvailable = true);
    try {
      final ridesService = DriverRidesService(apiClient: auth.apiClient);
      final deliveriesService =
          DriverDeliveriesService(apiClient: auth.apiClient);
      final results = await Future.wait([
        ridesService.getAvailable(),
        deliveriesService.getAvailable(),
      ]);
      if (mounted) {
        final rides = results[0];
        final deliveries = results[1];
        setState(() {
          _availableRides = rides;
          _availableDeliveries = deliveries;
          _loadingAvailable = false;
        });
        if (_pendingDemand == null && (rides.isNotEmpty || deliveries.isNotEmpty)) {
          final Map<String, dynamic> next;
          final String type;
          if (rides.isNotEmpty) {
            next = rides.first;
            type = 'ride';
          } else {
            next = deliveries.first;
            type = 'delivery';
          }
          final id = next['id'] is int
              ? next['id'] as int
              : int.tryParse(next['id'].toString()) ?? 0;
          _pendingDemandTimer?.cancel();
          setState(() => _pendingDemand = {'type': type, 'id': id, 'data': next});
          _pendingDemandTimer = Timer(
            const Duration(seconds: _pendingDemandDurationSeconds),
            () {
              if (mounted && _pendingDemand != null) {
                setState(() {
                  _pendingDemand = null;
                  _pendingDemandTimer = null;
                });
              }
            },
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAvailable = false);
    }
  }

  void _dismissPendingDemand() {
    _pendingDemandTimer?.cancel();
    _pendingDemandTimer = null;
    setState(() => _pendingDemand = null);
  }

  void _refusePendingDemand() {
    _dismissPendingDemand();
    HapticFeedback.lightImpact();
  }

  Future<void> _acceptRide(int rideId) async {
    final auth = AuthService();
    await auth.loadStoredAuth();
    if (auth.driverId == null) return;
    final idempotencyKey =
        'ride_${rideId}_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final ride = await DriverRidesService(apiClient: auth.apiClient)
          .accept(rideId, idempotencyKey: idempotencyKey);
      if (mounted) {
        _pendingDemandTimer?.cancel();
        _pendingDemandTimer = null;
        setState(() {
          _currentMission = {
            'type': 'ride',
            'id': rideId,
            'data': ride,
          };
          _pendingDemand = null;
          _showOrderNotification = false;
          _currentOrder = null;
          _isMissionCardExpanded = false;
          _availableRides =
              _availableRides.where((r) => r['id'] != rideId).toList();
        });
        _startLocationTracking();
        _loadRouteForMission();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _acceptDelivery(int deliveryId) async {
    final auth = AuthService();
    await auth.loadStoredAuth();
    if (auth.driverId == null) return;
    final idempotencyKey =
        'delivery_${deliveryId}_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final delivery =
          await DriverDeliveriesService(apiClient: auth.apiClient)
              .accept(deliveryId, idempotencyKey: idempotencyKey);
      if (mounted) {
        _pendingDemandTimer?.cancel();
        _pendingDemandTimer = null;
        setState(() {
          _currentMission = {
            'type': 'delivery',
            'id': deliveryId,
            'data': delivery,
          };
          _pendingDemand = null;
          _showOrderNotification = false;
          _currentOrder = null;
          _isMissionCardExpanded = false;
          _availableDeliveries = _availableDeliveries
              .where((d) => d['id'] != deliveryId)
              .toList();
        });
        _startLocationTracking();
        _loadRouteForMission();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _startLocationTracking() {
    _locationTrackingTimer?.cancel();
    if (_currentMission == null) return;
    final type = _currentMission!['type'] as String? ?? '';
    final id = _currentMission!['id'] as int? ?? 0;
    if (type.isEmpty || id == 0) return;
    _locationTrackingTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _sendLocationUpdate(type, id),
    );
    _sendLocationUpdate(type, id);
  }

  void _stopLocationTracking() {
    _locationTrackingTimer?.cancel();
    _locationTrackingTimer = null;
  }

  Future<void> _sendLocationUpdate(String type, int id) async {
    if (_currentMission == null || _currentLatLng == null) return;
    final auth = AuthService();
    await auth.loadStoredAuth();
    if (auth.token == null) return;
    try {
      if (type == 'ride') {
        await DriverRidesService(apiClient: auth.apiClient)
            .sendLocation(id, lat: _currentLatLng!.latitude, lng: _currentLatLng!.longitude);
      } else {
        await DriverDeliveriesService(apiClient: auth.apiClient)
            .sendLocation(id, lat: _currentLatLng!.latitude, lng: _currentLatLng!.longitude);
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      if (mounted) {
        setState(() => _currentLatLng = LatLng(pos.latitude, pos.longitude));
        // Mettre à jour l'itinéraire si on est en mission
        if (_currentMission != null) {
          _loadRouteForMission();
        }
      }
    } catch (_) {}
  }

  Future<void> _launchMapsToMission() async {
    if (_currentMission == null || _currentLatLng == null) return;
    final data = _currentMission!['data'] as Map<String, dynamic>? ?? {};
    final pickupLat = _parseDouble(data['pickup_lat']);
    final pickupLng = _parseDouble(data['pickup_lng']);
    final dropoffLat = _parseDouble(data['dropoff_lat']);
    final dropoffLng = _parseDouble(data['dropoff_lng']);
    if (pickupLat == null || pickupLng == null || dropoffLat == null || dropoffLng == null) return;
    final origin = '${_currentLatLng!.latitude},${_currentLatLng!.longitude}';
    final waypoints = '$pickupLat,$pickupLng';
    final destination = '$dropoffLat,$dropoffLng';
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&origin=$origin&destination=$destination&waypoints=$waypoints&travelmode=driving',
    );
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Future<void> _launchCall(String? phone) async {
    if (phone == null || phone.toString().trim().isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone.toString().trim());
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchSms(String? phone) async {
    if (phone == null || phone.toString().trim().isEmpty) return;
    final uri = Uri(scheme: 'sms', path: phone.toString().trim());
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _loadRouteForMission() async {
    if (_currentMission == null || _currentLatLng == null) {
      setState(() => _routePolyline = []);
      return;
    }
    final data = _currentMission!['data'] as Map<String, dynamic>? ?? {};
    final status = (data['status'] ?? '').toString();
    final type = _currentMission!['type'] as String? ?? '';

    LatLng? destination;
    if (type == 'ride') {
      if (status == 'DRIVER_ASSIGNED' || status == 'DRIVER_ARRIVED') {
        // Itinéraire vers le pickup
        final pickupLat = _parseDouble(data['pickup_lat']);
        final pickupLng = _parseDouble(data['pickup_lng']);
        if (pickupLat != null && pickupLng != null) {
          destination = LatLng(pickupLat, pickupLng);
        }
      } else if (status == 'IN_PROGRESS') {
        // Itinéraire vers le dropoff
        final dropoffLat = _parseDouble(data['dropoff_lat']);
        final dropoffLng = _parseDouble(data['dropoff_lng']);
        if (dropoffLat != null && dropoffLng != null) {
          destination = LatLng(dropoffLat, dropoffLng);
        }
      }
    } else {
      if (status == 'ASSIGNED' || status == 'PICKED_UP') {
        // Itinéraire vers le pickup (pour livraison)
        final pickupLat = _parseDouble(data['pickup_lat']);
        final pickupLng = _parseDouble(data['pickup_lng']);
        if (pickupLat != null && pickupLng != null) {
          destination = LatLng(pickupLat, pickupLng);
        }
      } else if (status == 'IN_TRANSIT') {
        // Itinéraire vers le dropoff
        final dropoffLat = _parseDouble(data['dropoff_lat']);
        final dropoffLng = _parseDouble(data['dropoff_lng']);
        if (dropoffLat != null && dropoffLng != null) {
          destination = LatLng(dropoffLat, dropoffLng);
        }
      }
    }

    if (destination == null) {
      setState(() => _routePolyline = []);
      return;
    }

    setState(() => _routeLoading = true);
    try {
      final route = await RoutingService.getRoutePolyline(_currentLatLng!, destination);
      if (mounted) {
        setState(() {
          _routePolyline = route;
          _routeLoading = false;
        });
        if (route.isNotEmpty) {
          _fitMapToRoute(_currentLatLng!, destination, route);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _routeLoading = false);
    }
  }

  void _fitMapToRoute(LatLng from, LatLng to, List<LatLng> routePoints) {
    if (routePoints.isEmpty) return;
    final bounds = LatLngBounds.fromPoints([from, to, ...routePoints]);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(80),
      ),
    );
  }

  Future<void> _missionAction(String action) async {
    if (_currentMission == null) return;
    final type = _currentMission!['type'] as String? ?? '';
    final id = _currentMission!['id'] as int? ?? 0;
    final data = _currentMission!['data'] as Map<String, dynamic>? ?? {};
    final auth = AuthService();
    await auth.loadStoredAuth();
    if (auth.driverId == null) return;

    try {
      if (type == 'ride') {
        final svc = DriverRidesService(apiClient: auth.apiClient);
        if (action == 'arrived') {
          final updated = await svc.arrived(id);
          if (mounted) {
            setState(() => _currentMission!['data'] = updated);
            _loadRouteForMission();
          }
        } else if (action == 'start') {
          final updated = await svc.start(id);
          if (mounted) {
            setState(() => _currentMission!['data'] = updated);
            _loadRouteForMission();
          }
        } else if (action == 'complete') {
          final km = (data['estimated_distance_km'] is num)
              ? (data['estimated_distance_km'] as num).toDouble()
              : 0.0;
          final min = (data['estimated_duration_min'] is int)
              ? data['estimated_duration_min'] as int
              : 0;
          await svc.complete(
            id,
            actualDistanceKm: km > 0 ? km : 1.0,
            actualDurationMin: min >= 0 ? min : 1,
          );
          if (mounted) {
            _stopLocationTracking();
            setState(() {
              _currentMission = null;
              _routePolyline = [];
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Course terminée')),
            );
          }
        }
      } else {
        final svc = DriverDeliveriesService(apiClient: auth.apiClient);
        if (action == 'picked_up') {
          final updated = await svc.pickedUp(id);
          if (mounted) {
            setState(() => _currentMission!['data'] = updated);
            _loadRouteForMission();
          }
        } else if (action == 'start_transit') {
          final updated = await svc.startTransit(id);
          if (mounted) {
            setState(() => _currentMission!['data'] = updated);
            _loadRouteForMission();
          }
        } else if (action == 'complete') {
          final km = (data['estimated_distance_km'] is num)
              ? (data['estimated_distance_km'] as num).toDouble()
              : 0.0;
          final min = (data['estimated_duration_min'] is int)
              ? data['estimated_duration_min'] as int
              : 0;
          await svc.complete(
            id,
            actualDistanceKm: km > 0 ? km : 1.0,
            actualDurationMin: min >= 0 ? min : 1,
          );
          if (mounted) {
            _stopLocationTracking();
            setState(() {
              _currentMission = null;
              _routePolyline = [];
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Livraison terminée')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _completeTrip() {
    setState(() {
      _showNavigationOverlay = false;
      _currentOrder = null;
    });

    HapticFeedback.mediumImpact();
  }

  void _showPreferences() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const PreferenceBottomSheetWidget(),
    );
  }

  void _showSearch() {
    showDialog(context: context, builder: (context) => _buildSearchDialog());
  }

  Widget _buildSearchDialog() {
    final theme = Theme.of(context);
    final TextEditingController searchController = TextEditingController();
    return _SearchDialogWidget(
      theme: theme,
      currentLat: _currentLatLng?.latitude,
      currentLng: _currentLatLng?.longitude,
      onResultSelected: (result) {
        Navigator.pop(context);
        _mapController.move(LatLng(result.lat, result.lng), 15.0);
      },
    );
  }
}

class _SearchDialogWidget extends StatefulWidget {
  final ThemeData theme;
  final double? currentLat;
  final double? currentLng;
  final Function(GeocodingResult) onResultSelected;

  const _SearchDialogWidget({
    required this.theme,
    this.currentLat,
    this.currentLng,
    required this.onResultSelected,
  });

  @override
  State<_SearchDialogWidget> createState() => _SearchDialogWidgetState();
}

class _SearchDialogWidgetState extends State<_SearchDialogWidget> {
  final TextEditingController _searchController = TextEditingController();
  List<GeocodingResult> _searchResults = [];
  bool _searching = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadLocalSuggestions();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), _runSearch);
  }

  Future<void> _runSearch() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      await _loadLocalSuggestions();
      return;
    }
    setState(() => _searching = true);
    final results = await GeocodingService.search(
      q,
      currentLat: widget.currentLat,
      currentLng: widget.currentLng,
    );
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _searching = false;
    });
  }

  Future<void> _loadLocalSuggestions() async {
    final suggestions = await GeocodingService.search(
      '',
      currentLat: widget.currentLat,
      currentLng: widget.currentLng,
    );
    if (mounted) setState(() => _searchResults = suggestions);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(4.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Rechercher un lieu', style: widget.theme.textTheme.titleLarge),
            SizedBox(height: 2.h),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Point de départ (ou sélectionner depuis la carte)',
                prefixIcon: CustomIconWidget(
                  iconName: 'search',
                  color: widget.theme.colorScheme.onSurfaceVariant,
                  size: 24,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
            if (_searchResults.isNotEmpty) ...[
              SizedBox(height: 2.h),
              SizedBox(
                height: 30.h,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final r = _searchResults[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        r.type == 'airport'
                            ? Icons.flight
                            : r.type == 'station'
                                ? Icons.train
                                : r.type == 'hospital'
                                    ? Icons.local_hospital
                                    : r.type == 'university'
                                        ? Icons.school
                                        : Icons.location_on,
                        color: widget.theme.colorScheme.primary,
                      ),
                      title: Text(
                        r.displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: widget.theme.textTheme.bodySmall,
                      ),
                      onTap: () => widget.onResultSelected(r),
                    );
                  },
                ),
              ),
            ],
            SizedBox(height: 2.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Fermer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      body: SafeArea(
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLatLng ?? const LatLng(48.8566, 2.3522),
                initialZoom: 15.0,
                onMapReady: () {
                  setState(() {
                    _isMapReady = true;
                  });
                  if (_currentLatLng != null) {
                    _mapController.move(_currentLatLng!, 15.0);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.example.motodriver',
                  tileProvider: CancellableNetworkTileProvider(),
                ),
                if (_routePolyline.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _routePolyline,
                        strokeWidth: 5,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    if (_currentLatLng != null)
                      Marker(
                        point: _currentLatLng!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    if (_currentMission != null) ...[
                      ...(){
                        final data = _currentMission!['data'] as Map<String, dynamic>? ?? {};
                        final status = (data['status'] ?? '').toString();
                        final type = _currentMission!['type'] as String? ?? '';
                        final markers = <Marker>[];
                        
                        // Marqueur pickup (si on va vers le pickup ou si on est au pickup)
                        if (type == 'ride' && (status == 'DRIVER_ASSIGNED' || status == 'DRIVER_ARRIVED')) {
                          final pickupLat = _parseDouble(data['pickup_lat']);
                          final pickupLng = _parseDouble(data['pickup_lng']);
                          if (pickupLat != null && pickupLng != null) {
                            markers.add(Marker(
                              point: LatLng(pickupLat, pickupLng),
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
                            ));
                          }
                        } else if (type == 'delivery' && (status == 'ASSIGNED' || status == 'PICKED_UP')) {
                          final pickupLat = _parseDouble(data['pickup_lat']);
                          final pickupLng = _parseDouble(data['pickup_lng']);
                          if (pickupLat != null && pickupLng != null) {
                            markers.add(Marker(
                              point: LatLng(pickupLat, pickupLng),
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.local_shipping, color: Colors.blue, size: 40),
                            ));
                          }
                        }
                        
                        // Marqueur dropoff (si on va vers le dropoff)
                        if (type == 'ride' && status == 'IN_PROGRESS') {
                          final dropoffLat = _parseDouble(data['dropoff_lat']);
                          final dropoffLng = _parseDouble(data['dropoff_lng']);
                          if (dropoffLat != null && dropoffLng != null) {
                            markers.add(Marker(
                              point: LatLng(dropoffLat, dropoffLng),
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.location_on, color: Colors.green, size: 40),
                            ));
                          }
                        } else if (type == 'delivery' && status == 'IN_TRANSIT') {
                          final dropoffLat = _parseDouble(data['dropoff_lat']);
                          final dropoffLng = _parseDouble(data['dropoff_lng']);
                          if (dropoffLat != null && dropoffLng != null) {
                            markers.add(Marker(
                              point: LatLng(dropoffLat, dropoffLng),
                              width: 40,
                              height: 40,
                              child: const Icon(Icons.location_on, color: Colors.green, size: 40),
                            ));
                          }
                        }
                        
                        return markers;
                      }(),
                    ],
                  ],
                ),
              ],
            ),
            Positioned(
              top: 2.h,
              left: 4.w,
              child: Material(
                elevation: 4,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 12.w,
                    height: 12.w,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: CustomIconWidget(
                        iconName: 'menu',
                        color: theme.colorScheme.onSurface,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 2.h,
              right: 4.w,
              child: Material(
                elevation: 4,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _showSearch,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 12.w,
                    height: 12.w,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: CustomIconWidget(
                        iconName: 'search',
                        color: theme.colorScheme.onSurface,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 20.h,
              left: 4.w,
              child: Material(
                elevation: 4,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _showPreferences,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 14.w,
                    height: 14.w,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: CustomIconWidget(
                        iconName: 'tune',
                        color: theme.colorScheme.onSurface,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 4.h,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  elevation: 8,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: _toggleOnlineStatus,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 20.w,
                      height: 20.w,
                      decoration: BoxDecoration(
                        color: _isOnline
                            ? AppTheme.successLight
                            : theme.colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isOnline
                              ? AppTheme.successLight
                              : theme.colorScheme.outline,
                          width: 3,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _isOnline ? 'EN LIGNE' : 'HORS LIGNE',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: _isOnline
                                ? Colors.white
                                : theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_isOnline)
              Positioned(
                top: 2.h,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 4.w,
                      vertical: 1.h,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.successLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'EN LIGNE',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            if (_pendingDemand != null) _buildPendingDemandCard(theme),
            if (_currentMission != null) _buildMissionCard(theme),
            if (_showOrderNotification && _currentOrder != null)
              OrderNotificationWidget(
                order: _currentOrder!,
                onAccept: _acceptOrder,
                onDecline: _declineOrder,
              ),
            if (_showNavigationOverlay && _currentOrder != null)
              NavigationOverlayWidget(
                order: _currentOrder!,
                onComplete: _completeTrip,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    final theme = Theme.of(context);
    final auth = AuthService();
    final user = _driverUser ?? auth.user;
    final displayName = user != null
        ? '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim()
        : '';
    final email = user?['email']?.toString() ?? '';

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(4.w),
              decoration: BoxDecoration(color: theme.colorScheme.primary),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: theme.colorScheme.surface,
                    child: CustomIconWidget(
                      iconName: 'person',
                      color: theme.colorScheme.primary,
                      size: 40,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    displayName.isNotEmpty ? displayName : 'Chauffeur',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                  SizedBox(height: 0.5.h),
                  Text(
                    email.isNotEmpty ? email : 'Conducteur Moto',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(vertical: 2.h),
                children: [
                  _buildDrawerItem(
                    icon: 'account_circle',
                    title: 'Mon Profil',
                    onTap: () {},
                  ),
                  _buildDrawerItem(
                    icon: 'euro',
                    title: 'Mes Gains',
                    onTap: () {},
                  ),
                  _buildDrawerItem(
                    icon: 'history',
                    title: 'Historique',
                    onTap: () {},
                  ),
                  _buildDrawerItem(
                    icon: 'settings',
                    title: 'Paramètres',
                    onTap: () {},
                  ),
                  _buildDrawerItem(icon: 'help', title: 'Aide', onTap: () {}),
                  Divider(height: 4.h),
                  _buildDrawerItem(
                    icon: 'logout',
                    title: 'Déconnexion',
                    onTap: () async {
                      Navigator.pop(context);
                      await auth.logout();
                      if (!mounted) return;
                      Navigator.of(context, rootNavigator: true)
                          .pushReplacementNamed('/authentication');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required String icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return ListTile(
      leading: CustomIconWidget(
        iconName: icon,
        color: theme.colorScheme.onSurface,
        size: 24,
      ),
      title: Text(title, style: theme.textTheme.bodyLarge),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  Widget _buildPendingDemandCard(ThemeData theme) {
    final pending = _pendingDemand!;
    final type = pending['type'] as String? ?? '';
    final id = pending['id'] as int? ?? 0;
    final data = pending['data'] as Map<String, dynamic>? ?? {};
    double? pickupLat;
    double? pickupLng;
    final plat = data['pickup_lat'];
    final plng = data['pickup_lng'];
    if (plat != null) pickupLat = (plat is num) ? plat.toDouble() : double.tryParse(plat.toString());
    if (plng != null) pickupLng = (plng is num) ? plng.toDouble() : double.tryParse(plng.toString());
    double? distanceToPickupKm;
    if (_currentLatLng != null && pickupLat != null && pickupLng != null) {
      distanceToPickupKm = _distanceKm(
        _currentLatLng!.latitude,
        _currentLatLng!.longitude,
        pickupLat,
        pickupLng,
      );
    }
    final estimatedKm = data['estimated_distance_km'] != null
        ? ((data['estimated_distance_km'] is num) ? (data['estimated_distance_km'] as num).toDouble() : double.tryParse(data['estimated_distance_km'].toString()))
        : null;
    final durationMin = data['estimated_duration_min'] is int
        ? data['estimated_duration_min'] as int
        : (data['estimated_duration_min'] is num)
            ? (data['estimated_duration_min'] as num).toInt()
            : null;
    final pickupAddress = data['pickup_address']?.toString() ?? '—';
    final dropoffAddress = data['dropoff_address']?.toString() ?? '—';
    final fare = data['estimated_fare'] ?? data['frozen_fare'];
    final priceStr = fare != null
        ? (fare is num ? (fare as num).toStringAsFixed(0) : fare.toString()) + ' XOF'
        : '—';

    return Positioned(
      bottom: 4.h,
      left: 4.w,
      right: 4.w,
      child: Card(
        elevation: 8,
        child: Padding(
          padding: EdgeInsets.all(4.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                type == 'ride' ? 'Nouvelle course' : 'Nouvelle livraison',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 1.5.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.euro, size: 20, color: AppTheme.successLight),
                      SizedBox(width: 2.w),
                      Text(priceStr, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 18, color: theme.colorScheme.onSurfaceVariant),
                      SizedBox(width: 1.w),
                      Text('${durationMin ?? '—'} min', style: theme.textTheme.bodyMedium),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.straighten, size: 18, color: theme.colorScheme.onSurfaceVariant),
                      SizedBox(width: 1.w),
                      Text(
                        '${estimatedKm?.toStringAsFixed(1) ?? distanceToPickupKm?.toStringAsFixed(1) ?? '—'} km',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 1.5.h),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.trip_origin, size: 18, color: Colors.blue),
                  SizedBox(width: 2.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Prise en charge', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        Text(pickupAddress, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 1.h),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on, size: 18, color: Colors.red),
                  SizedBox(width: 2.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Destination', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        Text(dropoffAddress, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 1.5.h),
              Text(
                'Disparaît dans $_pendingDemandDurationSeconds s',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
              ),
              SizedBox(height: 1.5.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _refusePendingDemand,
                      child: const Text('Refuser'),
                    ),
                  ),
                  SizedBox(width: 3.w),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        if (type == 'ride') _acceptRide(id);
                        else _acceptDelivery(id);
                      },
                      child: const Text('Accepter'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMissionCard(ThemeData theme) {
    final mission = _currentMission!;
    final type = mission['type'] as String? ?? '';
    final data = mission['data'] as Map<String, dynamic>? ?? {};
    final status = (data['status'] ?? '').toString();

    String title;
    String subtitle;
    if (type == 'ride') {
      title = 'Course ${data['ride_code'] ?? mission['id']}';
      subtitle =
          '${data['pickup_address'] ?? ''} → ${data['dropoff_address'] ?? ''}';
    } else {
      title = 'Livraison ${data['delivery_code'] ?? mission['id']}';
      subtitle =
          '${data['pickup_address'] ?? ''} → ${data['dropoff_address'] ?? ''}';
    }

    Widget? actionButton;
    if (type == 'ride') {
      if (status == 'DRIVER_ASSIGNED') {
        actionButton = FilledButton(
          onPressed: () => _missionAction('arrived'),
          child: const Text('Je suis arrivé'),
        );
      } else if (status == 'DRIVER_ARRIVED') {
        actionButton = FilledButton(
          onPressed: () => _missionAction('start'),
          child: const Text('Démarrer la course'),
        );
      } else if (status == 'IN_PROGRESS') {
        actionButton = FilledButton(
          onPressed: () => _missionAction('complete'),
          child: const Text('Terminer la course'),
        );
      }
    } else {
      if (status == 'ASSIGNED') {
        actionButton = FilledButton(
          onPressed: () => _missionAction('picked_up'),
          child: const Text('Colis récupéré'),
        );
      } else if (status == 'PICKED_UP') {
        actionButton = FilledButton(
          onPressed: () => _missionAction('start_transit'),
          child: const Text('En route'),
        );
      } else if (status == 'IN_TRANSIT') {
        actionButton = FilledButton(
          onPressed: () => _missionAction('complete'),
          child: const Text('Livraison effectuée'),
        );
      }
    }

    final clientName = '${data['client_first_name'] ?? ''} ${data['client_last_name'] ?? ''}'.trim();
    final clientPhone = data['client_phone']?.toString();
    final estimatedFare = data['estimated_fare'] ?? data['frozen_fare'];
    final fareStr = estimatedFare != null
        ? (estimatedFare is num ? (estimatedFare as num).toStringAsFixed(0) : estimatedFare.toString()) + ' XOF'
        : '—';

    // Interface réduite en bas : barre minimale par défaut, s'étend au clic
    return Positioned(
      bottom: 2.h,
      left: 4.w,
      right: 4.w,
      child: GestureDetector(
        onTap: () => setState(() => _isMissionCardExpanded = !_isMissionCardExpanded),
        child: Card(
          elevation: 8,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: _isMissionCardExpanded ? 2.5.h : 1.5.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ligne principale (toujours visible)
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                          if (_isMissionCardExpanded)
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    Text(fareStr, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
                    Icon(
                      _isMissionCardExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
                // Détails (seulement si étendu)
                if (_isMissionCardExpanded) ...[
                  SizedBox(height: 1.5.h),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          clientName.isNotEmpty ? clientName : 'Client',
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        onPressed: () => _launchCall(clientPhone),
                        icon: Icon(Icons.phone, size: 20, color: AppTheme.successLight),
                        tooltip: 'Appeler',
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        onPressed: () => _launchSms(clientPhone),
                        icon: Icon(Icons.message, size: 20, color: theme.colorScheme.primary),
                        tooltip: 'SMS',
                      ),
                    ],
                  ),
                  SizedBox(height: 1.5.h),
                  if (actionButton != null) ...[
                    actionButton!,
                    SizedBox(height: 1.h),
                  ],
                  OutlinedButton.icon(
                    onPressed: () => _cancelMission(),
                    icon: const Icon(Icons.cancel, size: 18),
                    label: const Text('Annuler'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancelMission() async {
    if (_currentMission == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Annuler la mission'),
        content: const Text('Voulez-vous vraiment annuler cette mission ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final type = _currentMission!['type'] as String? ?? '';
    final id = _currentMission!['id'] as int? ?? 0;
    final auth = AuthService();
    await auth.loadStoredAuth();
    try {
      if (type == 'ride') {
        await DriverRidesService(apiClient: auth.apiClient).cancel(id);
      } else {
        await DriverDeliveriesService(apiClient: auth.apiClient).cancel(id);
      }
      if (mounted) {
        _stopLocationTracking();
        setState(() {
          _currentMission = null;
          _routePolyline = [];
          _isMissionCardExpanded = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(type == 'ride' ? 'Course annulée' : 'Livraison annulée')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _locationTrackingTimer?.cancel();
    _pendingDemandTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }
}
