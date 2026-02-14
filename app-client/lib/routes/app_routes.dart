import 'package:flutter/material.dart';
import '../presentation/splash_screen/splash_screen.dart';
import '../presentation/authentication_screen/authentication_screen.dart';
import '../presentation/home_screen/home_screen.dart';
import '../presentation/ride_booking_screen/ride_booking_screen.dart';
import '../presentation/delivery_order_screen/delivery_order_screen.dart';
import '../presentation/history_screen/history_screen.dart';
import '../presentation/ride_detail_screen/ride_detail_screen.dart';
import '../presentation/delivery_detail_screen/delivery_detail_screen.dart';

class AppRoutes {
  static const String initial = '/';
  static const String splash = '/splash-screen';
  static const String authentication = '/authentication-screen';
  static const String home = '/home-screen';
  static const String rideBooking = '/ride-booking-screen';
  static const String deliveryOrder = '/delivery-order-screen';
  static const String history = '/history-screen';
  static const String rideDetail = '/ride-detail-screen';
  static const String deliveryDetail = '/delivery-detail-screen';

  static Map<String, WidgetBuilder> routes = {
    initial: (context) => const SplashScreen(),
    splash: (context) => const SplashScreen(),
    authentication: (context) => const AuthenticationScreen(),
    home: (context) => const HomeScreen(),
    rideBooking: (context) => const RideBookingScreen(),
    deliveryOrder: (context) => const DeliveryOrderScreen(),
    history: (context) => const HistoryScreen(),
    rideDetail: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      final id = args is int ? args : (args is String ? int.tryParse(args) : null);
      if (id == null) {
        return const Scaffold(
          body: Center(child: Text('ID de course invalide')),
        );
      }
      return RideDetailScreen(rideId: id);
    },
    deliveryDetail: (context) {
      final args = ModalRoute.of(context)?.settings.arguments;
      final id = args is int ? args : (args is String ? int.tryParse(args) : null);
      if (id == null) {
        return const Scaffold(
          body: Center(child: Text('ID de livraison invalide')),
        );
      }
      return DeliveryDetailScreen(deliveryId: id);
    },
  };
}
