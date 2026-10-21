import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Diálogo modal persistente e ineludible que exige al vendedor o cajero
/// realizar la devolución física del dinero recaudado tras anular una orden.
///
/// Cuenta con un temporizador de 5 segundos donde el botón de aceptar permanece
/// inhabilitado para asegurar que el personal lea atentamente el monto a devolver.
class DialogoDevolucionDinero extends StatefulWidget {
  final String folio;
  final int montoADevolver;
  final String? clienteNombre;
  final int duracionSegundos;

  const DialogoDevolucionDinero({
    super.key,
    required this.folio,
    required this.montoADevolver,
    this.clienteNombre,
    this.duracionSegundos = 5,
  });

  /// Helper estático para mostrar el diálogo. No permite ser cerrado tocando afuera.
  static Future<void> mostrar(
    BuildContext context, {
    required String folio,
    required int montoADevolver,
    String? clienteNombre,
    int duracionSegundos = 5,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DialogoDevolucionDinero(
        folio: folio,
        montoADevolver: montoADevolver,
        clienteNombre: clienteNombre,
        duracionSegundos: duracionSegundos,
      ),
    );
  }

  @override
  State<DialogoDevolucionDinero> createState() =>
      _DialogoDevolucionDineroState();
}

class _DialogoDevolucionDineroState extends State<DialogoDevolucionDinero> {
  late int _segundosRestantes;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _segundosRestantes = widget.duracionSegundos;
    if (_segundosRestantes > 0) {
      _iniciarTemporizador();
    }
  }

  void _iniciarTemporizador() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_segundosRestantes > 1) {
        setState(() {
          _segundosRestantes--;
        });
      } else {
        setState(() {
          _segundosRestantes = 0;
        });
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool puedeCerrar = _segundosRestantes == 0;
    final montoFormateado = CurrencyFormatter.formatCLP(widget.montoADevolver);

    return PopScope(
      canPop: puedeCerrar,
      child: AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: AppPalette.warning.withValues(alpha: 0.6),
            width: 1.5,
          ),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        actionsPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppPalette.warning.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.payments_outlined,
                color: AppPalette.warning,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'DEVOLUCIÓN DE DINERO',
                    style: AppTypography.title.copyWith(
                      fontSize: 16,
                      color: AppPalette.warning,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Folio: ${widget.folio}',
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tarjeta del Monto a Devolver
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppPalette.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppPalette.warning.withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'MONTO TOTAL A DEVOLVER AL CLIENTE:',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.textSecondary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        montoFormateado,
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: AppPalette.warning,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    if (widget.clienteNombre != null &&
                        widget.clienteNombre!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Cliente: ${widget.clienteNombre}',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Indicaciones Operativas
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppPalette.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppPalette.error.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: AppPalette.error,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'El cliente había pagado o abonado este dinero. La orden ya fue cancelada en el sistema; '
                        'debes entregarle físicamente este importe en Caja o Mesón de inmediato.',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textPrimary,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          // Botón en ancho completo (Extend) para evitar overflow
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              key: const Key('btn_confirmar_devolucion_dinero'),
              style: ElevatedButton.styleFrom(
                backgroundColor: puedeCerrar
                    ? AppPalette.success
                    : AppPalette.surface,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    Colors.white.withValues(alpha: 0.08),
                disabledForegroundColor: const Color(0xFF94A3B8),
                elevation: puedeCerrar ? 2 : 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: puedeCerrar
                        ? AppPalette.success
                        : Colors.white24,
                  ),
                ),
              ),
              icon: puedeCerrar
                  ? const Icon(Icons.check_circle_outline, size: 20)
                  : const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppPalette.warning,
                      ),
                    ),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  puedeCerrar
                      ? 'ENTENDIDO, DINERO DEVUELTO'
                      : 'DEVOLVER DINERO AL CLIENTE (${_segundosRestantes}s)',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
              ),
              onPressed: puedeCerrar
                  ? () => Navigator.of(context).pop()
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
