// lib/features/paletizado/presentation/widgets/dialogo_falla_impresora.dart

import 'package:flutter/material.dart';
import '../../domain/exceptions/printer_exceptions.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';

/// Modal de diagnóstico y resolución de problemas físicos para la impresora térmica.
/// Diseñado para terminales móviles PDA de bodega (Sunmi L3) en Modo Oscuro.
class DialogoFallaImpresora extends StatelessWidget {
  final PrinterException error;

  const DialogoFallaImpresora({super.key, required this.error});

  /// Muestra el modal de diagnóstico y retorna `true` si el operador pulsa "REINTENTAR",
  /// o `false` si decide cancelar la operación.
  static Future<bool> mostrar(BuildContext context, PrinterException error) async {
    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DialogoFallaImpresora(error: error),
    );
    return resultado ?? false;
  }

  Color _obtenerColorAlerta() {
    if (error is PrinterPaperOutException || error is PrinterRibbonOutException) {
      return AppPalette.error; // Rojo: Falta de insumo crítico
    }
    if (error is PrinterHeadOpenException || error is PrinterPausedException || error is PrinterOverheatException) {
      return AppPalette.secondary; // Naranja: Condición mecánica corregible
    }
    return const Color(0xFF78909C); // Azul grisáceo: Conectividad / Red
  }

  @override
  Widget build(BuildContext context) {
    final alertColor = _obtenerColorAlerta();

    return AlertDialog(
      backgroundColor: AppPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: alertColor.withValues(alpha: 0.4), width: 1.5),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: alertColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(error.icono, color: alertColor, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  error.titulo,
                  style: AppTypography.title.copyWith(
                    color: AppPalette.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Impresora Honeywell PC42E-T',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error.mensaje,
            style: const TextStyle(
              color: AppPalette.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          // Caja de instrucción operativa destacada
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.background,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: alertColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.build_circle_outlined, size: 18, color: alertColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Acción requerida:',
                        style: TextStyle(
                          color: alertColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        error.instruccionOperativa,
                        style: const TextStyle(
                          color: AppPalette.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'CANCELAR',
            style: TextStyle(
              color: AppPalette.neutral,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text(
            'REINTENTAR',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: alertColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}
