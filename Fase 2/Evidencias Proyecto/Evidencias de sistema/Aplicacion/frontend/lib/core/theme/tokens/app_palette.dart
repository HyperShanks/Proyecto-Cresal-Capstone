import 'package:flutter/material.dart';

/// Single Source of Truth para el Sistema de Diseño de Cresal-SaaS.
/// Garantiza consistencia cromática, accesibilidad WCAG y cero valores 'hardcoded'.
abstract class AppPalette {
  // ── Fondos (Dark Mode) ──
  static const Color background = Color(0xFF0F1416);
  static const Color surface = Color(0xFF1A2226);

  // ── Fondos (Light Mode) ──
  static const Color backgroundLight = Color(0xFFF4F6F8);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE2E8F0);

  // ── Marca y Acentos ──
  static const Color primary = Color(0xFF2596BE); // Azul Institucional Cresal
  static const Color secondary = Color(0xFFFFB800); // Ámbar base
  static const Color tertiary = Color(0xFF004C89); // Azul corporativo / Tarjeta financiera
  static const Color neutral = Color(0xFF73787B); // Gris para elementos inactivos

  // ── Estados Deshabilitados (Disabled / Slate) ──
  static const Color disabled = Color(0xFFCBD5E1); // Gris bloqueo #CBD5E1
  static const Color disabledText = Color(0xFF94A3B8); // Texto de botón bloqueado

  // ── Textos (Dark Mode) ──
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF90A4AE);

  // ── Textos (Light Mode) ──
  static const Color textPrimaryLight = Color(0xFF0F1416);
  static const Color textSecondaryLight = Color(0xFF546E7A);

  // ── Estados de Operación y Alertas ──
  static const Color error = Color(0xFFD32F2F);
  static const Color errorBg = Color(0xFFFEF2F2);
  static const Color errorBorder = Color(0xFFFECACA);
  static const Color errorText = Color(0xFF991B1B);

  static const Color success = Color(0xFF2E7D32);
  static const Color successBg = Color(0xFFF0FDF4);
  static const Color successBorder = Color(0xFFBBF7D0);
  static const Color successText = Color(0xFF166534);

  static const Color warning = Color(0xFFFFB800);
  static const Color warningBg = Color(0xFFFFFBEB);
  static const Color warningBorder = Color(0xFFFDE68A);
  static const Color warningText = Color(0xFF92400E);
}

