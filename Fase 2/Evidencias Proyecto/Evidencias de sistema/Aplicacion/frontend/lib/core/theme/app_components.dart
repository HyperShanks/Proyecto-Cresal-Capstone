import 'package:flutter/material.dart';
import 'tokens/app_palette.dart';
import 'tokens/app_typography.dart';

class AppComponents {
  // REGLA W3C: Touch target mínimo para operarios con guantes en el patio de desarme.
  static const double minTouchTarget = 44.0;
  static const double defaultBorderRadius = 8.0;

  // Configuración global para los botones primarios de la aplicación.
  static ElevatedButtonThemeData get elevatedButtonTheme {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        // CORRECCIÓN: Evitamos el infinito global para que no rompa las filas (Rows)
        minimumSize: const Size(64, minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        backgroundColor: AppPalette.primary,
        foregroundColor: AppPalette.textPrimary,
        splashFactory: InkRipple.splashFactory,
        textStyle: AppTypography.button,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(defaultBorderRadius),
        ),
      ),
    );
  }

  // Configuración global para botones con borde.
  static OutlinedButtonThemeData get outlinedButtonTheme {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        foregroundColor: AppPalette.primary,
        splashFactory: InkRipple.splashFactory,
        textStyle: AppTypography.button,
        side: const BorderSide(color: AppPalette.primary, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(defaultBorderRadius),
        ),
      ),
    );
  }

  // Configuración global para botones de icono.
  static IconButtonThemeData get iconButtonTheme {
    return IconButtonThemeData(
      style: IconButton.styleFrom(
        splashFactory: InkRipple.splashFactory,
        highlightColor: Colors.transparent,
      ),
    );
  }

  // Configuración de tarjetas para el tema oscuro.
  static CardThemeData get cardTheme {
    return cardThemeWithSurface(AppPalette.surface);
  }

  // Configuración de tarjetas para el tema claro.
  static CardThemeData get cardThemeLight {
    return cardThemeWithSurface(AppPalette.surfaceLight);
  }

  // Constructor base para las tarjetas, reutilizable en ambos modos (Claro/Oscuro).
  static CardThemeData cardThemeWithSurface(Color surfaceColor) {
    return CardThemeData(
      color: surfaceColor,
      // Se utiliza elevación 0 para mantener un diseño plano y evitar sombras que ensucien el Dark Mode.
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      margin: const EdgeInsets.only(bottom: 16.0),
    );
  }

  // Configuración de los campos de texto para el tema oscuro.
  static InputDecorationTheme get inputDecorationTheme {
    return inputDecorationThemeWithFill(AppPalette.surface);
  }

  // Configuración de los campos de texto para el tema claro.
  static InputDecorationTheme get inputDecorationThemeLight {
    return inputDecorationThemeWithFill(AppPalette.surfaceLight);
  }

  // Constructor base para los inputs (cajas de texto), definiendo su borde, relleno y estado de foco.
  static InputDecorationTheme inputDecorationThemeWithFill(Color fillColor) {
    return InputDecorationTheme(
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.all(16.0),
      // Borde por defecto (invisible para que resalte el color de fondo).
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(defaultBorderRadius),
        borderSide: BorderSide.none,
      ),
      // Borde de color primario cuando el usuario selecciona el campo para escribir.
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(defaultBorderRadius),
        borderSide: const BorderSide(color: AppPalette.primary, width: 2),
      ),
    );
  }
}
