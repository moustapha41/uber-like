import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sizer/sizer.dart';

import '../../core/app_export.dart';
import '../../services/auth_service.dart';
import '../../widgets/custom_icon_widget.dart';

/// Splash Screen for MotoRide motorcycle ride-hailing application
/// Displays branded launch experience while initializing core services
/// Handles authentication status check and navigation routing
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _isInitializing = true;
  bool _hasError = false;
  int _retryCount = 0;
  static const int _maxRetries = 3;
  static const Duration _initializationTimeout = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeApp();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _animationController.forward();
  }

  /// Initialize app services and determine navigation path
  Future<void> _initializeApp() async {
    try {
      setState(() {
        _isInitializing = true;
        _hasError = false;
      });

      // Simulate initialization tasks with timeout
      await Future.wait([
        _checkAuthenticationStatus(),
        _loadUserPreferences(),
        _fetchDriverAvailability(),
        _prepareCachedMapTiles(),
        Future.delayed(const Duration(milliseconds: 2000)),
      ]).timeout(
        _initializationTimeout,
        onTimeout: () {
          throw TimeoutException('Initialization timeout');
        },
      );

      if (mounted) {
        await _navigateToNextScreen();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isInitializing = false;
        });
      }
    }
  }

  bool _isAuthenticated = false;

  /// Check user authentication status (token BikeRide stocké)
  Future<void> _checkAuthenticationStatus() async {
    final authService = AuthService();
    await authService.loadStoredAuth();
    _isAuthenticated = await authService.isLoggedIn();
  }

  /// Load user preferences from storage
  Future<void> _loadUserPreferences() async {
    await Future.delayed(const Duration(milliseconds: 300));
    // Simulated preferences loading
  }

  /// Fetch current driver availability data
  Future<void> _fetchDriverAvailability() async {
    await Future.delayed(const Duration(milliseconds: 400));
    // Simulated driver availability fetch
  }

  /// Prepare cached map tiles for OSM integration
  Future<void> _prepareCachedMapTiles() async {
    await Future.delayed(const Duration(milliseconds: 600));
    // Simulated map tiles preparation
  }

  /// Navigate to appropriate screen based on authentication status
  Future<void> _navigateToNextScreen() async {
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    if (_isAuthenticated) {
      Navigator.of(context, rootNavigator: true)
          .pushReplacementNamed('/home-screen');
    } else {
      Navigator.of(context, rootNavigator: true)
          .pushReplacementNamed('/authentication-screen');
    }
  }

  /// Retry initialization after error
  Future<void> _retryInitialization() async {
    if (_retryCount < _maxRetries) {
      _retryCount++;
      await _initializeApp();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Impossible de se connecter. Veuillez vérifier votre connexion internet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onError,
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Réessayer',
              textColor: Theme.of(context).colorScheme.onError,
              onPressed: () {
                _retryCount = 0;
                _initializeApp();
              },
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: theme.scaffoldBackgroundColor,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 24.w,
                  height: 24.w,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(26),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: CustomIconWidget(
                      iconName: 'two_wheeler',
                      color: theme.colorScheme.primary,
                      size: 12.w,
                    ),
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'MotoRide',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: 1.h),
                Text(
                  'Votre course en un instant',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 6.h),
                if (_isInitializing && !_hasError)
                  SizedBox(
                    width: 10.w,
                    height: 10.w,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                if (_hasError)
                  Column(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                        size: 10.w,
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        'Erreur de connexion',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      ElevatedButton(
                        onPressed: _retryInitialization,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
}
