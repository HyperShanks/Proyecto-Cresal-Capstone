import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/services/api_service.dart';
import 'features/auth/presentation/screens/splash_screen.dart';
import 'routes/app_routes.dart';

import 'core/theme/theme_controller.dart';
import 'core/routes/route_observer.dart';
import 'core/services/session_inactivity_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.themeMode,
      builder: (context, currentThemeMode, _) {
        return MaterialApp(
          title: 'Cresal Capstone',
          debugShowCheckedModeBanner: false,
          navigatorKey: ApiService.navigatorKey,
          scaffoldMessengerKey: ApiService.scaffoldMessengerKey,
          navigatorObservers: [routeObserver],
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentThemeMode,
          // Pantalla inicial: Splash que decide la ruta según sesión
          home: const SplashScreen(),

          // Rutas centralizadas y unificadas bajo Single Source of Truth (SSOT)
          routes: AppRoutes.getRoutes(),
          onGenerateRoute: AppRoutes.onGenerateRoute,

          // Detector global de inactividad de 10 min en todas las vistas y roles
          builder: (context, child) {
            return SessionInactivityWatcher(
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}


