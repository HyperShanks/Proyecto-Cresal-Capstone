import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../models/cobro_model.dart';
import '../../models/cobro_pendiente_model.dart';
import 'cobro_pendiente_card.dart';

/// Diálogo modal de confirmación financiera tras registrar un cobro (SPEC-HU-04 / CRES-215).
/// Adaptado 1:1 de prototipo_caja_sprint4.html con Material Icons nativos y AppPalette.
/// Cumple la restricción estricta de NO renderizar imágenes gráficas de código QR en pantalla.
class ResultadoCobroDialog extends StatelessWidget {
  final CobroPendienteModel orden;
  final RegistrarCobroResponseModel resultado;
  final String metodosResumen;
  final VoidCallback onSiguienteOrden;

  const ResultadoCobroDialog({
    super.key,
    required this.orden,
    required this.resultado,
    required this.metodosResumen,
    required this.onSiguienteOrden,
  });

  @override
  Widget build(BuildContext context) {
    final emiteQr = resultado.qrGenerado != null;
    final esMiscelaneoCompleta = !orden.esBackorder && resultado.nuevoSaldoPendiente == 0 && !emiteQr;
    final esAbono = !emiteQr && !esMiscelaneoCompleta;

    return Dialog(
      backgroundColor: AppPalette.surfaceLight,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppPalette.borderLight),
      ),
      elevation: 12,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 1. Círculo de Estado ─────────────────────────────────────────
              _buildStatusCircle(emiteQr, esMiscelaneoCompleta),

              const SizedBox(height: 16),

              // ── 2. Título y Subtítulo Adaptativo ───────────────────────────
              _buildTitleAndSubtitle(emiteQr, esMiscelaneoCompleta),

              const SizedBox(height: 20),

              // ── 3. Tarjeta Resumen Financiero ──────────────────────────────
              _buildFinancialSummaryCard(emiteQr, esAbono),

              const SizedBox(height: 16),

              // ── 4. Recuadro de Instrucción Operativa ───────────────────────
              _buildOperationalInstructionBox(emiteQr, esMiscelaneoCompleta),

              const SizedBox(height: 24),

              // ── 5. Botón de Acción Principal (Siguiente Orden) ─────────────
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.primary,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onSiguienteOrden,
                  child: Text(
                    'Siguiente Orden',
                    style: AppTypography.button.copyWith(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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

  Widget _buildStatusCircle(bool emiteQr, bool esMiscelaneoCompleta) {
    final isSuccess = emiteQr || esMiscelaneoCompleta;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: isSuccess ? AppPalette.successBg : AppPalette.primary.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(
          color: isSuccess ? AppPalette.successBorder : AppPalette.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Icon(
        isSuccess ? Icons.check_circle_rounded : Icons.receipt_long_rounded,
        size: 36,
        color: isSuccess ? AppPalette.success : AppPalette.primary,
      ),
    );
  }

  Widget _buildTitleAndSubtitle(bool emiteQr, bool esMiscelaneoCompleta) {
    final esBackorderCompleta = orden.esBackorder && resultado.nuevoSaldoPendiente == 0;
    final String title;
    final String subtitle;
    final Color subtitleColor;

    if (emiteQr) {
      title = 'Pago Registrado Exitosamente';
      subtitle = 'QR Transaccional generado para barrera de salida';
      subtitleColor = AppPalette.success;
    } else if (esMiscelaneoCompleta) {
      title = 'Venta Completada en Mostrador';
      subtitle = 'Pago 100% saldado • Entrega inmediata en mostrador';
      subtitleColor = AppPalette.success;
    } else if (esBackorderCompleta) {
      title = 'Venta en Verde Pagada al 100%';
      subtitle = 'Pago completado • Pasa a "Por Asignar" del vendedor';
      subtitleColor = AppPalette.primary;
    } else {
      title = 'Comprobante de Abono Registrado';
      subtitle = 'Abono procesado correctamente • Sin emisión de QR';
      subtitleColor = AppPalette.primary;
    }

    return Column(
      children: [
        Text(
          title,
          style: AppTypography.title.copyWith(
            fontSize: 19,
            fontWeight: FontWeight.w900,
            color: AppPalette.textPrimaryLight,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: AppTypography.body.copyWith(
            color: subtitleColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildFinancialSummaryCard(bool emiteQr, bool esAbono) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.borderLight),
      ),
      child: Column(
        children: [
          // Fila 1: Folio y Cliente
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    orden.esBackorder ? 'FOLIO RESERVA' : 'FOLIO ORDEN',
                    style: AppTypography.small.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textSecondaryLight,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    resultado.folio,
                    style: AppTypography.title.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppPalette.primary,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'CLIENTE',
                      style: AppTypography.small.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textSecondaryLight,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      orden.clienteNombre,
                      style: AppTypography.body.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textPrimaryLight,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                    Builder(
                      builder: (context) {
                        final rutLimpio = orden.clienteRut.replaceAll(RegExp(r'[^0-9kK]'), '');
                        final esClienteGenerico = rutLimpio.isEmpty ||
                            rutLimpio.startsWith('666666') ||
                            orden.clienteRut == '6.666.666-6' ||
                            orden.clienteNombre.trim().toLowerCase().contains('consumidor final');
                        final rutTexto = esClienteGenerico
                            ? 'Sin RUT registrado'
                            : 'RUT: ${orden.clienteRut}';

                        return Text(
                          rutTexto,
                          style: AppTypography.small.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppPalette.textSecondaryLight,
                            fontStyle: esClienteGenerico ? FontStyle.italic : FontStyle.normal,
                          ),
                          textAlign: TextAlign.right,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: AppPalette.borderLight, height: 1),
          ),

          // Fila 2: Monto Liquidado y Métodos
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (emiteQr || resultado.nuevoSaldoPendiente == 0) ? 'MONTO TOTAL PAGADO' : 'ABONO INGRESADO',
                    style: AppTypography.small.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textSecondaryLight,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    CobroPendienteCard.formatClp(resultado.montoCobrado),
                    style: AppTypography.title.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppPalette.textPrimaryLight,
                    ),
                  ),
                ],
              ),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppPalette.surfaceLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppPalette.borderLight),
                  ),
                  child: Text(
                    metodosResumen.isNotEmpty ? metodosResumen : 'Efectivo',
                    style: AppTypography.small.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textPrimaryLight,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            ],
          ),

          // Fila 3: Si es Abono, mostrar Nuevo Saldo Pendiente
          if (esAbono || resultado.nuevoSaldoPendiente > 0) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(color: AppPalette.borderLight, height: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'NUEVO SALDO PENDIENTE:',
                    style: AppTypography.small.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textSecondaryLight,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Text(
                  CobroPendienteCard.formatClp(resultado.nuevoSaldoPendiente),
                  style: AppTypography.title.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.primary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOperationalInstructionBox(bool emiteQr, bool esMiscelaneoCompleta) {
    final esBackorderCompleta = orden.esBackorder && resultado.nuevoSaldoPendiente == 0;
    final Color bgColor;
    final Color borderColor;
    final Color headerTextColor;
    final Color iconColor;
    final Color bodyTextColor;
    final IconData icon;
    final String instructionText;

    if (emiteQr) {
      bgColor = AppPalette.surfaceLight;
      borderColor = AppPalette.borderLight;
      headerTextColor = AppPalette.textPrimaryLight;
      iconColor = AppPalette.primary;
      bodyTextColor = AppPalette.textSecondaryLight;
      icon = Icons.info_outline_rounded;
      instructionText = 'Derive al cliente al Mesón de Venta para la entrega física de sus piezas y repuestos.';
    } else if (esMiscelaneoCompleta) {
      bgColor = AppPalette.successBg;
      borderColor = AppPalette.successBorder;
      headerTextColor = AppPalette.success;
      iconColor = AppPalette.success;
      bodyTextColor = AppPalette.textPrimaryLight;
      icon = Icons.check_circle_outline_rounded;
      instructionText = 'La venta de misceláneos ha sido saldada y completada exitosamente. Entregue los repuestos o insumos directamente al cliente en el mostrador. No requiere paso por bodega ni barrera.';
    } else if (esBackorderCompleta) {
      bgColor = AppPalette.primary.withValues(alpha: 0.08);
      borderColor = AppPalette.primary.withValues(alpha: 0.25);
      headerTextColor = AppPalette.primary;
      iconColor = AppPalette.primary;
      bodyTextColor = AppPalette.textPrimaryLight;
      icon = Icons.pending_actions_rounded;
      instructionText = 'La venta en verde ha sido pagada al 100%. La orden ya está disponible en la sección "Por Asignar" del vendedor (${orden.vendedorNombre}) para que realice la asignación física del motor o caja cuando arribe a bodega.';
    } else {
      bgColor = AppPalette.warningBg;
      borderColor = AppPalette.warningBorder;
      headerTextColor = AppPalette.warningText;
      iconColor = AppPalette.warningText;
      bodyTextColor = AppPalette.warningText;
      icon = Icons.warning_amber_rounded;
      instructionText = 'La orden queda retenida en estado \'Reservada\' / Confirmada sin código QR de salida hasta la liquidación final o arribo a bodega.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: iconColor,
              ),
              const SizedBox(width: 6),
              Text(
                'Instrucción Operativa:',
                style: AppTypography.body.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: headerTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            instructionText,
            style: AppTypography.small.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: bodyTextColor,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
