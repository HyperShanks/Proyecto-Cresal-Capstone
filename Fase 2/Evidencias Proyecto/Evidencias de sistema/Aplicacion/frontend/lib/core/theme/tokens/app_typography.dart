import 'package:flutter/material.dart';
import 'app_palette.dart';

abstract class AppTypography {
  static const String fontFamily = 'Roboto';

  // Títulos
  static const TextStyle headline = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    height: 1.3,
    color: AppPalette.textPrimary,
    fontFamily: fontFamily,
  );

  static const TextStyle title = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppPalette.textPrimary,
    fontFamily: fontFamily,
  );

  // Cuerpo
  static const TextStyle body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    height: 1.5,
    color: AppPalette.textPrimary,
    fontFamily: fontFamily,
  );

  static const TextStyle small = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    height: 1.4,
    color: AppPalette.textSecondary,
    fontFamily: fontFamily,
  );

  // Botones
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppPalette.textPrimary,
    fontFamily: fontFamily,
  );

  // Tarjetas
  static const TextStyle cardTitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.bold,
    color: AppPalette.textPrimary,
    fontFamily: fontFamily,
    letterSpacing: 0.4,
  );
}
