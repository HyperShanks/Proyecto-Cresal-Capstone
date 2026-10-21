import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../services/logistica_service.dart';

/// Diálogo modal centrado de confirmación tras validar el Dual-Scan en Barrera de Salida (HU-3.6).
/// Presenta los repuestos liberados, el folio comercial y un botón con temporizador de 5 segundos.
class ResultadoSalidaDialog extends StatefulWidget {
  final EscanearSalidaResponseModel resultado;
  final VerificarQrSalidaResponseModel? ordenVerificada;
  final VoidCallback onFinalizar;

  const ResultadoSalidaDialog({
    super.key,
    required this.resultado,
    this.ordenVerificada,
    required this.onFinalizar,
  });

  @override
  State<ResultadoSalidaDialog> createState() => _ResultadoSalidaDialogState();
}

class _ResultadoSalidaDialogState extends State<ResultadoSalidaDialog> {
  int _segundosRestantes = 5;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _iniciarCuentaRegresiva();
  }

  void _iniciarCuentaRegresiva() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_segundosRestantes <= 1) {
        timer.cancel();
        widget.onFinalizar();
      } else {
        setState(() {
          _segundosRestantes--;
        });
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cliente = widget.ordenVerificada?.clienteNombre ?? 'Cliente General';
    final items = widget.ordenVerificada?.itemsRequeridos ?? [];

    return Dialog(
      backgroundColor: AppPalette.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppPalette.success, width: 1.5),
      ),
      elevation: 24,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 1. Círculo de Estado de Éxito ─────────────────────────────
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppPalette.success.withValues(alpha: 0.15),
                  border: Border.all(color: AppPalette.success, width: 2),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: AppPalette.success,
                  size: 38,
                ),
              ),
              const SizedBox(height: 14),

              // ── 2. Título y Folio ──────────────────────────────────────────
              Text(
                '¡SALIDA AUTORIZADA!',
                textAlign: TextAlign.center,
                style: AppTypography.headline.copyWith(
                  color: AppPalette.success,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.resultado.folio,
                textAlign: TextAlign.center,
                style: AppTypography.title.copyWith(
                  color: AppPalette.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 16),

              // ── 3. Tarjeta de Detalle de Entrega ───────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppPalette.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 16,
                          color: AppPalette.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Cliente: $cliente',
                            style: AppTypography.small.copyWith(
                              color: AppPalette.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.badge_outlined,
                          size: 16,
                          color: AppPalette.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Auditor: ${widget.resultado.bodegueroNombre}',
                            style: AppTypography.small.copyWith(
                              color: AppPalette.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 18, color: Colors.white12),
                    Text(
                      'REPUESTOS DESPACHADOS (${widget.resultado.totalEntregados}):',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (items.isNotEmpty) ...[
                      ...items.map((it) {
                        final esFisico = it.esInventariado;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Icon(
                                esFisico ? Icons.verified : Icons.storefront_outlined,
                                size: 14,
                                color: esFisico ? AppPalette.success : AppPalette.secondary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  it.titulo,
                                  style: AppTypography.small.copyWith(
                                    color: AppPalette.textPrimary,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (esFisico && it.skuQrFisico != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF00A3FF,
                                    ).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    it.skuQrFisico!,
                                    style: const TextStyle(
                                      color: Color(0xFF00A3FF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              else if (!esFisico)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppPalette.secondary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'MESÓN',
                                    style: TextStyle(
                                      color: AppPalette.secondary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                    ] else ...[
                      ...widget.resultado.activosEntregados.map((sku) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.verified,
                                size: 14,
                                color: AppPalette.success,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                sku,
                                style: const TextStyle(
                                  color: Color(0xFF00A3FF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── 4. Botón de Acción Principal con Temporizador ───────────────
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.success,
                    foregroundColor: Colors.black,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () {
                    _countdownTimer?.cancel();
                    widget.onFinalizar();
                  },
                  icon: const Icon(Icons.check, size: 20, color: Colors.black),
                  label: Text(
                    'FINALIZAR ENTREGA (${_segundosRestantes}s)',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
