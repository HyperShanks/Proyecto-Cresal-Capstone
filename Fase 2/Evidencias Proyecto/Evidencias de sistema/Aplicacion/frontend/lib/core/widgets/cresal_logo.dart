import 'package:flutter/material.dart';
import '../theme/tokens/app_palette.dart';
import '../theme/tokens/app_typography.dart';

/// Widget oficial para renderizar el logo corporativo de Cresal.
///
/// Incorpora el isotipo oficial desde assets/icon/logo.png con recorte squircle,
/// borde de cristal sutil, sombra de relieve y resplandor perimetral difuso
/// en Azul Institucional Cresal. Incluye fallback resiliente ante contingencias.
class CresalLogo extends StatelessWidget {
  /// Tamaño del lado del contenedor cuadrado (ancho y alto).
  final double size;

  /// Radio de curvatura del squircle. Si es null, se calcula proporcionalmente (25% del tamaño).
  final double? borderRadius;

  /// Controla si se dibuja la sombra y el resplandor perimetral.
  final bool showGlow;

  /// Controla si se dibuja el marco sutil de cristal.
  final bool showBorder;

  /// Ajuste de la imagen dentro del recuadro.
  final BoxFit fit;

  const CresalLogo({
    super.key,
    this.size = 80.0,
    this.borderRadius,
    this.showGlow = true,
    this.showBorder = true,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    final double radius = borderRadius ?? (size * 0.25);
    final double borderW = size >= 60 ? 1.5 : 1.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppPalette.primary,
        borderRadius: BorderRadius.circular(radius),
        border: showBorder
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: borderW,
              )
            : null,
        boxShadow: showGlow
            ? [
                // Sombra de relieve inferior
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: size * 0.2,
                  spreadRadius: 0,
                  offset: Offset(0, size * 0.05),
                ),
                // Halo perimetral corporativo Cresal
                BoxShadow(
                  color: AppPalette.primary.withValues(alpha: 0.38),
                  blurRadius: size * 0.28,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius > 1 ? radius - 1 : radius),
        child: Image.asset(
          'assets/icon/logo.png',
          width: size,
          height: size,
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            // Fallback estilizado en caso de contingencia con el asset
            return Container(
              color: AppPalette.primary,
              alignment: Alignment.center,
              child: Text(
                'C',
                style: AppTypography.headline.copyWith(
                  fontSize: size * 0.5,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
