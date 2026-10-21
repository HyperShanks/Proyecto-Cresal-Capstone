import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../models/cobro_pendiente_model.dart';
import 'cobro_pendiente_card.dart';

/// Diálogo modal de confirmación preventiva para Liquidación Total en Caja.
/// Exige validación consciente mediante casilla de verificación antes de saldar la orden al 100%.
class ConfirmacionLiquidacionDialog extends StatefulWidget {
  final CobroPendienteModel orden;
  final int montoALiquidar;

  const ConfirmacionLiquidacionDialog({
    super.key,
    required this.orden,
    required this.montoALiquidar,
  });

  static Future<bool> show({
    required BuildContext context,
    required CobroPendienteModel orden,
    required int montoALiquidar,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ConfirmacionLiquidacionDialog(
        orden: orden,
        montoALiquidar: montoALiquidar,
      ),
    );
    return result ?? false;
  }

  @override
  State<ConfirmacionLiquidacionDialog> createState() =>
      _ConfirmacionLiquidacionDialogState();
}

class _ConfirmacionLiquidacionDialogState
    extends State<ConfirmacionLiquidacionDialog> {
  bool _confirmado = false;

  @override
  Widget build(BuildContext context) {
    final orden = widget.orden;
    final monto = widget.montoALiquidar;

    return Dialog(
      backgroundColor: AppPalette.surfaceLight,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppPalette.borderLight),
      ),
      elevation: 8,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 1. ÍCONO DE ADVERTENCIA DESTACADO ──
              Center(
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppPalette.warningBg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppPalette.warningBorder,
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 34,
                    color: AppPalette.warningText,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── 2. TÍTULO Y PREGUNTA EXPLÍCITA ──
              Text(
                'Confirmar Liquidación Total',
                style: AppTypography.title.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppPalette.textPrimaryLight,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Estás a punto de liquidar el total de la orden.\n¿Estás seguro que no es un abono?',
                style: AppTypography.body.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.textSecondaryLight,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // ── 3. RESUMEN FINANCIERO VISUAL ──
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppPalette.backgroundLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppPalette.borderLight),
                ),
                child: Column(
                  children: [
                    _buildFilaResumen(
                      'Orden / Folio:',
                      orden.folioDocumento,
                      isBold: true,
                    ),
                    const SizedBox(height: 6),
                    _buildFilaResumen('Cliente:', orden.clienteNombre),
                    const SizedBox(height: 6),
                    _buildFilaResumen(
                      'Total de la Orden:',
                      CobroPendienteCard.formatClp(orden.totalOperacion),
                    ),
                    if (orden.abonoPrevio > 0) ...[
                      const SizedBox(height: 6),
                      _buildFilaResumen(
                        'Abonos Previos Realizados:',
                        '- ${CobroPendienteCard.formatClp(orden.abonoPrevio)}',
                        colorValor: const Color(0xFFD97706),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Divider(height: 1, color: AppPalette.borderLight),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            'Monto a Liquidar Ahora:',
                            style: AppTypography.small.copyWith(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.textPrimaryLight,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          CobroPendienteCard.formatClp(monto),
                          style: AppTypography.title.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppPalette.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Badge de saldo final $0
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.successBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppPalette.successBorder),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 16,
                            color: AppPalette.success,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Saldo restante tras este pago: \$0 CLP (Orden Saldada)',
                              style: AppTypography.small.copyWith(
                                color: AppPalette.successText,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // ── 4. CASILLA DE VERIFICACIÓN (CHECKBOX) ──
              InkWell(
                onTap: () {
                  setState(() {
                    _confirmado = !_confirmado;
                  });
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _confirmado
                        ? AppPalette.successBg
                        : AppPalette.backgroundLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _confirmado
                          ? AppPalette.successBorder
                          : AppPalette.borderLight,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Checkbox(
                        value: _confirmado,
                        activeColor: AppPalette.success,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _confirmado = val ?? false;
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Confirmo que el cliente cancela la totalidad de la orden y no un abono.',
                          style: AppTypography.body.copyWith(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textPrimaryLight,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── 5. BOTONES DE ACCIÓN (TAMAÑO UNIFORME, ANTI-OVERFLOW) ──
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppPalette.textSecondaryLight,
                          side: const BorderSide(color: AppPalette.borderLight),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(
                          'Cancelar / Volver',
                          style: AppTypography.button.copyWith(
                            color: AppPalette.textPrimaryLight,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _confirmado
                              ? AppPalette.success
                              : AppPalette.disabled,
                          foregroundColor: _confirmado
                              ? Colors.white
                              : AppPalette.disabledText,
                          disabledBackgroundColor: AppPalette.disabled,
                          disabledForegroundColor: AppPalette.disabledText,
                          elevation: _confirmado ? 2 : 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _confirmado
                            ? () => Navigator.of(context).pop(true)
                            : null,
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text(
                          'Confirmar',
                          style: AppTypography.button.copyWith(
                            color: _confirmado
                                ? Colors.white
                                : AppPalette.disabledText,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilaResumen(
    String label,
    String valor, {
    bool isBold = false,
    Color? colorValor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.small.copyWith(
              fontSize: 12.5,
              color: AppPalette.textSecondaryLight,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            valor,
            style: AppTypography.small.copyWith(
              fontSize: 12.5,
              color: colorValor ?? AppPalette.textPrimaryLight,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
