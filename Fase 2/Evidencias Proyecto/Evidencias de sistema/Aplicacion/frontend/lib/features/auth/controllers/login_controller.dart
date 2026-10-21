import 'package:flutter/material.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../routes/app_routes.dart';
import '../services/auth_service.dart';

/// Controlador de autenticación y enrutamiento post-login por rol.
class LoginController {
  /// Redirige al operario a su vista correspondiente según la fuente única de verdad (AppRoutes).
  static Future<void> handlePostLoginNavigation(
    BuildContext context, {
    int? idRol,
    String? rol,
  }) async {
    final effectiveIdRol = idRol ?? await AuthService.getIdRol();
    ThemeController.actualizarPorRol(effectiveIdRol);

    if (!context.mounted) return;

    final targetRoute = AppRoutes.getHomeRouteForRole(effectiveIdRol);
    Navigator.of(context).pushReplacementNamed(targetRoute);
  }

  /// Ejecuta el flujo de login por PIN y despacha la navegación correspondiente si es exitoso.
  static Future<AuthResult> submitPin(BuildContext context, String pin) async {
    final result = await AuthService.loginConPin(pin);

    if (!context.mounted) return result;

    if (result.success) {
      await handlePostLoginNavigation(
        context,
        idRol: result.user?.idRol,
        rol: result.user?.nombreRol,
      );
    }

    return result;
  }
}
