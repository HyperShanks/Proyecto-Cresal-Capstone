// frontend/lib/core/widgets/custom_error_snackbar.dart
import 'package:flutter/material.dart';
import '../theme/tokens/app_palette.dart';
import '../theme/tokens/app_typography.dart';
import '../services/api_service.dart';

/// Componente visual homogéneo para notificaciones de error y reintento (SPEC-HU-07).
/// Diseñado para ser no invasivo, con soporte para reintento y diseño visual industrial.
class CustomErrorSnackbar {
  /// Muestra el SnackBar en el ScaffoldMessenger del [BuildContext] actual.
  static void mostrar(
    BuildContext context, {
    required String mensaje,
    String? codigoError,
    VoidCallback? onReintentar,
    String textoAccion = 'Reintentar',
    Duration duracion = const Duration(seconds: 4),
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      _crearSnackBar(
        mensaje: mensaje,
        codigoError: codigoError,
        onReintentar: onReintentar,
        textoAccion: textoAccion,
        duracion: duracion,
      ),
    );
  }

  /// Muestra el SnackBar globalmente utilizando [ApiService.scaffoldMessengerKey].
  static void mostrarGlobal({
    required String mensaje,
    String? codigoError,
    VoidCallback? onReintentar,
    String textoAccion = 'Reintentar',
    Duration duracion = const Duration(seconds: 4),
  }) {
    final state = ApiService.scaffoldMessengerKey.currentState;
    if (state == null) return;

    state.hideCurrentSnackBar();
    state.showSnackBar(
      _crearSnackBar(
        mensaje: mensaje,
        codigoError: codigoError,
        onReintentar: onReintentar,
        textoAccion: textoAccion,
        duracion: duracion,
      ),
    );
  }

  static SnackBar _crearSnackBar({
    required String mensaje,
    String? codigoError,
    VoidCallback? onReintentar,
    required String textoAccion,
    required Duration duracion,
  }) {
    return SnackBar(
      elevation: 6,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      duration: duracion,
      backgroundColor: const Color(0xFF1E222B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: AppPalette.error.withValues(alpha: 0.6),
          width: 1.2,
        ),
      ),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppPalette.error.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              color: AppPalette.error,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (codigoError != null && codigoError.isNotEmpty) ...[
                  Text(
                    codigoError,
                    style: AppTypography.small.copyWith(
                      color: AppPalette.error,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  mensaje,
                  style: AppTypography.body.copyWith(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (onReintentar != null) ...[
            const SizedBox(width: 8),
            TextButton(
              key: const Key('btn_reintentar_snackbar'),
              style: TextButton.styleFrom(
                foregroundColor: AppPalette.secondary,
                backgroundColor: AppPalette.secondary.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: const BorderSide(color: AppPalette.secondary, width: 0.8),
                ),
              ),
              onPressed: () {
                ApiService.scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
                onReintentar();
              },
              child: Text(
                textoAccion,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
