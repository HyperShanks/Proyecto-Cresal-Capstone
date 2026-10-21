import 'package:flutter/material.dart';
import 'tokens/app_palette.dart';
import 'tokens/app_typography.dart';
import 'app_components.dart';

class AppTheme {
  // Metodo estatico que genera el tema oscuro
  static ThemeData get darkTheme {
    // 1. Generamos la paleta de Material 3 basada en tu azul
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppPalette.primary,
          brightness: Brightness.dark,
        ).copyWith(
          // Forzamos nuestros colores exactos para no depender de la IA de Flutter en los fondos
          surface: AppPalette.surface,
          onSurface: AppPalette.textPrimary,
          primary: AppPalette.primary,
          error: AppPalette.error,
        );

    // 2. Ensamblamos el tema
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          AppPalette.background, // Obligamos al fondo #0F1416
      fontFamily: AppTypography.fontFamily,

      // Eliminación global de InkSparkle (ruido procedural con shaders pesados)
      splashFactory: InkRipple.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: AppPalette.primary.withValues(alpha: 0.12),

      // 3. Mapeo de tipografías nativas de Flutter
      textTheme: const TextTheme(
        headlineLarge: AppTypography.headline,
        titleLarge: AppTypography.title,
        bodyLarge: AppTypography.body,
        bodyMedium: AppTypography.small,
        labelLarge: AppTypography.button,
      ),

      // 4. Inyección de componentes modulares
      elevatedButtonTheme: AppComponents.elevatedButtonTheme,
      outlinedButtonTheme: AppComponents.outlinedButtonTheme,
      iconButtonTheme: AppComponents.iconButtonTheme,
      cardTheme: AppComponents.cardTheme,
      inputDecorationTheme: AppComponents.inputDecorationTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppPalette.surface,
        foregroundColor: AppPalette.textPrimary,
        iconTheme: IconThemeData(color: AppPalette.textPrimary),
      ),
    );
  }

  // Metodo estatico que genera el tema claro
  static ThemeData get lightTheme {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppPalette.primary,
          brightness: Brightness.light,
        ).copyWith(
          surface: AppPalette.surfaceLight,
          onSurface: AppPalette.textPrimaryLight,
          primary: AppPalette.primary,
          error: AppPalette.error,
        );

    // 2. Ensamblamos el tema
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppPalette.backgroundLight,
      fontFamily: AppTypography.fontFamily,

      // Eliminación global de InkSparkle
      splashFactory: InkRipple.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: AppPalette.primary.withValues(alpha: 0.12),

      // 3. Mapeo de tipografías nativas de Flutter
      textTheme: TextTheme(
        headlineLarge: AppTypography.headline.copyWith(
          color: AppPalette.textPrimaryLight,
        ),
        titleLarge: AppTypography.title.copyWith(
          color: AppPalette.textPrimaryLight,
        ),
        bodyLarge: AppTypography.body.copyWith(
          color: AppPalette.textPrimaryLight,
        ),
        bodyMedium: AppTypography.small.copyWith(
          color: AppPalette.textSecondaryLight,
        ),
        labelLarge: AppTypography.button.copyWith(
          color: AppPalette.textPrimaryLight,
        ),
      ),

      // 4. Inyección de componentes modulares
      elevatedButtonTheme: AppComponents.elevatedButtonTheme,
      outlinedButtonTheme: AppComponents.outlinedButtonTheme,
      iconButtonTheme: AppComponents.iconButtonTheme,
      cardTheme: AppComponents.cardThemeLight,
      inputDecorationTheme: AppComponents.inputDecorationThemeLight,
    );
  }
}
