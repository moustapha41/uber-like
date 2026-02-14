import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/app_export.dart';
import '../../services/geocoding_service.dart';
import '../../widgets/custom_icon_widget.dart';
import './widgets/promotional_banner_widget.dart';
import './widgets/recent_destination_chip_widget.dart';
import './widgets/service_card_widget.dart';

class HomeScreenInitialPage extends StatefulWidget {
  const HomeScreenInitialPage({super.key});

  @override
  State<HomeScreenInitialPage> createState() => _HomeScreenInitialPageState();
}

class _HomeScreenInitialPageState extends State<HomeScreenInitialPage> {
  String currentLocation = "Chargement de votre position...";
  bool isLoadingLocation = true;
  int _currentBannerIndex = 0;

  final List<Map<String, dynamic>> recentDestinations = [
    {
      "id": 1,
      "name": "Gare du Nord",
      "address": "18 Rue de Dunkerque, 75010 Paris",
    },
    {
      "id": 2,
      "name": "Tour Eiffel",
      "address": "Champ de Mars, 5 Avenue Anatole France, 75007 Paris",
    },
    {
      "id": 3,
      "name": "Aéroport Charles de Gaulle",
      "address": "95700 Roissy-en-France",
    },
    {
      "id": 4,
      "name": "La Défense",
      "address": "1 Parvis de la Défense, 92800 Puteaux",
    },
  ];

  final List<Map<String, dynamic>> promotionalBanners = [
    {
      "id": 1,
      "title": "Première course gratuite",
      "description": "Utilisez le code MOTO2026 pour votre première course",
      "image": "https://images.unsplash.com/photo-1683183191700-b8072f734c2c",
      "semanticLabel":
          "Promotional banner showing a motorcycle rider in urban setting with helmet and leather jacket",
      "code": "MOTO2026",
    },
    {
      "id": 2,
      "title": "Livraison express -20%",
      "description": "Réduction sur toutes les livraisons ce week-end",
      "image": "https://images.unsplash.com/photo-1695653420508-f2481c1d783c",
      "semanticLabel":
          "Delivery package being handed over with motorcycle in background",
      "code": "EXPRESS20",
    },
    {
      "id": 3,
      "title": "Parrainez un ami",
      "description": "Gagnez 10€ pour chaque ami parrainé",
      "image":
          "https://img.rocket.new/generatedImages/rocket_gen_img_1c1ebfa0a-1768839826769.png",
      "semanticLabel":
          "Two people shaking hands with city skyline in background",
      "code": "PARRAIN10",
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  Future<void> _loadCurrentLocation() async {
    setState(() {
      isLoadingLocation = true;
      currentLocation = "Chargement de votre position...";
    });

    try {
      // Vérifier que le service de localisation est activé
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            currentLocation = "Localisation désactivée";
            isLoadingLocation = false;
          });
        }
        return;
      }

      // Demander la permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
        if (mounted) {
          setState(() {
            currentLocation = "Autorisation de localisation requise";
            isLoadingLocation = false;
          });
        }
        return;
      }

      // Obtenir la position actuelle
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Reverse geocoding pour obtenir l'adresse
      final address = await GeocodingService.reverseGeocode(
        position.latitude,
        position.longitude,
      );

      if (mounted) {
        setState(() {
          currentLocation = address ?? 
              "${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}";
          isLoadingLocation = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          currentLocation = "Impossible de déterminer votre position";
          isLoadingLocation = false;
        });
      }
    }
  }

  Future<void> _refreshContent() async {
    setState(() {
      isLoadingLocation = true;
    });
    await _loadCurrentLocation();
  }

  void _navigateToRideBooking() {
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamed('/ride-booking-screen');
  }

  void _navigateToDeliveryOrder() {
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamed('/delivery-order-screen');
  }

  void _navigateToDestination(Map<String, dynamic> destination) {
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushNamed('/ride-booking-screen', arguments: destination);
  }

  void _showEmergencyContact() {
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: Text('Contact d\'urgence', style: theme.textTheme.titleLarge),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Numéro d\'urgence: 112', style: theme.textTheme.bodyLarge),
              SizedBox(height: 2.h),
              Text(
                'Support MotoRide: +33 1 23 45 67 89',
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshContent,
          color: theme.colorScheme.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLocationHeader(theme),
                SizedBox(height: 3.h),
                _buildServiceCards(theme),
                SizedBox(height: 3.h),
                _buildRecentDestinations(theme),
                SizedBox(height: 3.h),
                _buildPromotionalBanners(theme),
                SizedBox(height: 2.h),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationHeader(ThemeData theme) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withAlpha(77),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(2.5.w),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(26),
              borderRadius: BorderRadius.circular(12),
            ),
            child: CustomIconWidget(
              iconName: 'location_on',
              color: theme.colorScheme.primary,
              size: 24,
            ),
          ),
          SizedBox(width: 3.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Votre position',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 0.5.h),
                isLoadingLocation
                    ? SizedBox(
                        height: 2.h,
                        width: 20.w,
                        child: LinearProgressIndicator(
                          backgroundColor: theme.colorScheme.outline.withAlpha(
                            51,
                          ),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.primary,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )
                    : Text(
                        currentLocation,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
              ],
            ),
          ),
          IconButton(
            onPressed: _showEmergencyContact,
            icon: Icon(
              Icons.emergency_outlined,
              color: theme.colorScheme.error,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCards(ThemeData theme) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Services',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 2.h),
          Row(
            children: [
              Expanded(
                child: ServiceCardWidget(
                  title: 'Réserver une course',
                  icon: 'two_wheeler',
                  color: theme.colorScheme.primary,
                  onTap: _navigateToRideBooking,
                ),
              ),
              SizedBox(width: 3.w),
              Expanded(
                child: ServiceCardWidget(
                  title: 'Livraison express',
                  icon: 'local_shipping',
                  color: theme.colorScheme.secondary,
                  onTap: _navigateToDeliveryOrder,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentDestinations(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w),
          child: Text(
            'Destinations récentes',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(height: 2.h),
        SizedBox(
          height: 5.h,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: 4.w),
            scrollDirection: Axis.horizontal,
            itemCount: recentDestinations.length,
            separatorBuilder: (context, index) => SizedBox(width: 2.w),
            itemBuilder: (context, index) {
              final destination = recentDestinations[index];
              return RecentDestinationChipWidget(
                name: destination['name'],
                onTap: () => _navigateToDestination(destination),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPromotionalBanners(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w),
          child: Text(
            'Offres spéciales',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(height: 2.h),
        CarouselSlider.builder(
          itemCount: promotionalBanners.length,
          itemBuilder: (context, index, realIndex) {
            final banner = promotionalBanners[index];
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 2.w),
              child: PromotionalBannerWidget(
                title: banner['title'],
                description: banner['description'],
                imageUrl: banner['image'],
                semanticLabel: banner['semanticLabel'],
                code: banner['code'],
              ),
            );
          },
          options: CarouselOptions(
            height: 20.h,
            viewportFraction: 0.9,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 5),
            autoPlayAnimationDuration: const Duration(milliseconds: 800),
            autoPlayCurve: Curves.easeInOut,
            enlargeCenterPage: false,
            onPageChanged: (index, reason) {
              setState(() {
                _currentBannerIndex = index;
              });
            },
          ),
        ),
        SizedBox(height: 1.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: promotionalBanners.asMap().entries.map((entry) {
            return Container(
              width: _currentBannerIndex == entry.key ? 8.w : 2.w,
              height: 1.h,
              margin: EdgeInsets.symmetric(horizontal: 1.w),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _currentBannerIndex == entry.key
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withAlpha(77),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
