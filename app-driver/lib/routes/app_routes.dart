import 'package:flutter/material.dart';

import '../presentation/authentication_screen/authentication_screen.dart';
import '../presentation/main_map_screen/main_map_screen.dart';
import '../presentation/splash_screen/splash_screen.dart';

class AppRoutes {
  static const String initial = '/';
  static const String splash = '/splash';
  static const String authentication = '/authentication';
  static const String mainMap = '/main-map-screen';

  static Map<String, WidgetBuilder> routes = {
    initial: (context) => const SplashScreen(),
    splash: (context) => const SplashScreen(),
    authentication: (context) => const AuthenticationScreen(),
    mainMap: (context) => const MainMapScreen(),
  };
}
