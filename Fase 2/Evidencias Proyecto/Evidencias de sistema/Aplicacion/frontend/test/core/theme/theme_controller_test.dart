// frontend/test/core/theme/theme_controller_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/theme_controller.dart';

void main() {
  group('ThemeController - SSOT Theme Mode by Role Tests', () {
    setUp(() {
      ThemeController.reset();
    });

    test('Por defecto y tras reset() se encuentra en ThemeMode.dark', () {
      expect(ThemeController.themeMode.value, equals(ThemeMode.dark));
    });

    test('Rol 1 (Bodeguero / Operario PDA) activa ThemeMode.dark (Ergonomía industrial de alto contraste)', () {
      ThemeController.actualizarPorRol(2); // Ponemos primero light
      expect(ThemeController.themeMode.value, equals(ThemeMode.light));

      ThemeController.actualizarPorRol(1);
      expect(ThemeController.themeMode.value, equals(ThemeMode.dark));
    });

    test('Roles 2 al 7 (Cajero, Administrador, Gerente, Vendedor, Jefe de Ventas, Vendedor Online) activan ThemeMode.light', () {
      for (final rol in [2, 3, 4, 5, 6, 7]) {
        ThemeController.reset(); // Vuelve a dark
        ThemeController.actualizarPorRol(rol);
        expect(
          ThemeController.themeMode.value,
          equals(ThemeMode.light),
          reason: 'Rol $rol debe activar ThemeMode.light según SSOT',
        );
      }
    });

    test('Rol nulo o desconocido regresa con seguridad a ThemeMode.dark', () {
      ThemeController.actualizarPorRol(2);
      expect(ThemeController.themeMode.value, equals(ThemeMode.light));

      ThemeController.actualizarPorRol(null);
      expect(ThemeController.themeMode.value, equals(ThemeMode.dark));

      ThemeController.actualizarPorRol(2);
      ThemeController.actualizarPorRol(999);
      expect(ThemeController.themeMode.value, equals(ThemeMode.dark));
    });
  });
}
