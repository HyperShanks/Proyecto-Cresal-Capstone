// frontend/lib/core/theme/theme_controller.dart
import 'package:flutter/material.dart';

/// Controlador centralizado y reactivo del ThemeMode de la aplicación.
/// Administra la Única Fuente de Verdad para temas por rol:
/// - Rol 1 (Bodeguero / Operario): ThemeMode.dark (PDA industrial, alto contraste para escaneo en patio/bodega).
/// - Roles 2, 3, 4, 5, 6, 7 (Vendedor, Cajero, Gerente, Administrador, Jefe de Ventas, Vendedor Online): ThemeMode.light (Web/Desktop claro y limpio).
class ThemeController {
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.dark);

  /// Actualiza de forma reactiva el tema de toda la ventana según el rol del usuario.
  static void actualizarPorRol(int? idRol) {
    if (idRol == 1) {
      themeMode.value = ThemeMode.dark;
    } else if (idRol != null && [2, 3, 4, 5, 6, 7, 8].contains(idRol)) {
      themeMode.value = ThemeMode.light;
    } else {
      themeMode.value = ThemeMode.dark;
    }
  }

  /// Restablece el tema por defecto al cerrar sesión.
  static void reset() {
    themeMode.value = ThemeMode.dark;
  }
}
