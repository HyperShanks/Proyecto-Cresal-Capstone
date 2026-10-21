import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/tokens/app_palette.dart';
import '../theme/tokens/app_typography.dart';

/// SnackBar flotante con diseño Glassmorphism (fondo blur frosted glass
/// y esquinas redondeadas) para notificaciones de interacción del carrito.
class GlassSnackbar {
  static void mostrar(
    BuildContext context, {
    required String mensaje,
    IconData icono = Icons.check_circle_outline_rounded,
    Color colorIcono = AppPalette.primary,
    Duration duracion = const Duration(seconds: 3),
    VoidCallback? onCerrar,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      crear(
        context: context,
        mensaje: mensaje,
        icono: icono,
        colorIcono: colorIcono,
        duracion: duracion,
        onCerrar: onCerrar ?? () => messenger.hideCurrentSnackBar(),
      ),
    );
  }

  static SnackBar crear({
    BuildContext? context,
    required String mensaje,
    IconData icono = Icons.check_circle_outline_rounded,
    Color colorIcono = AppPalette.primary,
    Duration duracion = const Duration(seconds: 3),
    VoidCallback? onCerrar,
  }) {
    return SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: EdgeInsets.zero,
      duration: duracion,
      content: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppPalette.surface.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Row(
                children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colorIcono.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icono,
                    color: colorIcono,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    mensaje,
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (innerCtx) {
                    return GestureDetector(
                      key: const Key('btn_cerrar_snackbar'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onCerrar ??
                          () {
                            ScaffoldMessenger.maybeOf(innerCtx)?.hideCurrentSnackBar();
                          },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.close_rounded,
                            color: AppPalette.textSecondary,
                            size: 16,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }
}
