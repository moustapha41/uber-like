import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import './main_map_screen_initial_page.dart';

class MainMapScreen extends StatefulWidget {
  const MainMapScreen({super.key});

  @override
  MainMapScreenState createState() => MainMapScreenState();
}

class MainMapScreenState extends State<MainMapScreen> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  int currentIndex = 0;

  final List<String> routes = ['/main-map-screen', '/profile'];
  final List<IconData> icons = [Icons.map, Icons.person];
  final List<String> labels = ['Carte', 'Profil'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Navigator(
        key: navigatorKey,
        initialRoute: '/main-map-screen',
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/main-map-screen':
            case '/':
              return MaterialPageRoute(
                builder: (context) => const MainMapScreenInitialPage(),
                settings: settings,
              );
            default:
              if (AppRoutes.routes.containsKey(settings.name)) {
                return MaterialPageRoute(
                  builder: AppRoutes.routes[settings.name]!,
                  settings: settings,
                );
              }
              return null;
          }
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          if (!AppRoutes.routes.containsKey(routes[index])) {
            return;
          }
          if (currentIndex != index) {
            setState(() => currentIndex = index);
            navigatorKey.currentState?.pushReplacementNamed(routes[index]);
          }
        },
        items: List.generate(routes.length, (index) => BottomNavigationBarItem(
          icon: Icon(icons[index]),
          label: labels[index],
        )),
      ),
    );
  }
}