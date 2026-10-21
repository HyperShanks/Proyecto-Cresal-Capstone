// lib/core/routes/route_observer.dart
import 'package:flutter/material.dart';

/// Observador global de rutas para toda la aplicación (SPEC-HU-TAREA-20).
/// Permite a cualquier pantalla suscrita mediante `RouteAware` recibir notificaciones
/// del ciclo de vida de navegación, en particular `didPopNext()` para auto-refrescar
/// datos cuando una pantalla vuelve a quedar en primer plano, y mantiene el nombre
/// de la ruta activa para el control de inactividad global.
class AppRouteObserver extends RouteObserver<ModalRoute<void>> {
  static String? currentRouteName;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (route.settings.name != null) {
      currentRouteName = route.settings.name;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute?.settings.name != null) {
      currentRouteName = previousRoute?.settings.name;
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute?.settings.name != null) {
      currentRouteName = newRoute?.settings.name;
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (previousRoute?.settings.name != null) {
      currentRouteName = previousRoute?.settings.name;
    }
  }
}

final AppRouteObserver routeObserver = AppRouteObserver();
