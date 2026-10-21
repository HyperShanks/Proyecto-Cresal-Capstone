// lib/features/ventas/presentation/widgets/qr_ticket_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../services/ordenes_service.dart';

/// Modal de Ticket Digital de Salida con Código QR Transaccional (HU-3.6).
/// Diseñado con alto contraste para lectura instantánea de cámaras de smartphones
/// y escáneres PDA de bodega (Sunmi L3 / Zebra).
class QrTicketDialog extends StatelessWidget {
  final OrdenHistorialModel orden;

  const QrTicketDialog({super.key, required this.orden});

  /// Método estático de conveniencia para invocar el modal de forma limpia y desacoplada.
  static Future<void> mostrar(BuildContext context, OrdenHistorialModel orden) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => QrTicketDialog(orden: orden),
    );
  }

  void _copiarTokenAlPortapapeles(BuildContext context, String token) {
    Clipboard.setData(ClipboardData(text: token));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.copy_rounded,
              color: AppPalette.textPrimary,
              size: 18,
            ),
            const SizedBox(width: 8),
            const Text(
              'Código QR copiado al portapapeles',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        backgroundColor: AppPalette.surface,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppPalette.primary, width: 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool tieneQr = orden.tieneQrDisponible;
    final bool esReservada = orden.esReservada || orden.montoPendiente > 0;
    final String? qrToken = orden.qrTransaccionalSalida;
    final clienteNombre = orden.cliente?.nombreCompleto ?? 'Cliente Mostrador';
    final clienteRut = orden.cliente?.rutCliente ?? 'N/A';

    return Dialog(
      backgroundColor: AppPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: const BorderSide(color: Colors.white12, width: 1.0),
      ),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 20.0,
        vertical: 24.0,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440.0),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header: Título y Botón Cerrar ────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color:
                          (tieneQr
                                  ? AppPalette.primary
                                  : (esReservada
                                        ? AppPalette.warning
                                        : AppPalette.secondary))
                              .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    child: Icon(
                      tieneQr
                          ? Icons.qr_code_2_rounded
                          : (esReservada
                                ? Icons.lock_clock_rounded
                                : Icons.receipt_long_rounded),
                      color: tieneQr
                          ? AppPalette.primary
                          : (esReservada
                                ? AppPalette.warning
                                : AppPalette.secondary),
                      size: 24.0,
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tieneQr
                              ? 'TICKET DE SALIDA'
                              : (esReservada
                                    ? 'TICKET BLOQUEADO'
                                    : 'COMPROBANTE DE VENTA'),
                          style: AppTypography.cardTitle.copyWith(
                            fontSize: 15.0,
                            letterSpacing: 1.0,
                          ),
                        ),
                        Text(
                          orden.folioDisplay,
                          style: AppTypography.small.copyWith(
                            color: AppPalette.textSecondary,
                            fontSize: 12.0,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      color: AppPalette.neutral,
                      size: 22.0,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Cerrar',
                  ),
                ],
              ),

              const SizedBox(height: 16.0),

              // ── Badge de Estado ──────────────────────────────────────────
              if (tieneQr)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8.0,
                    horizontal: 12.0,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(
                      color: AppPalette.success.withValues(alpha: 0.5),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppPalette.success,
                        size: 18.0,
                      ),
                      const SizedBox(width: 8.0),
                      Text(
                        'PAGO CONFIRMADO EN CAJA',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.success,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.0,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                )
              else if (esReservada)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8.0,
                    horizontal: 12.0,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(
                      color: AppPalette.warning.withValues(alpha: 0.5),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: AppPalette.warning,
                        size: 18.0,
                      ),
                      const SizedBox(width: 8.0),
                      Flexible(
                        child: Text(
                          'ORDEN RESERVADA - PAGO PENDIENTE',
                          style: AppTypography.small.copyWith(
                            color: AppPalette.warning,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.0,
                            letterSpacing: 0.8,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8.0,
                    horizontal: 12.0,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(
                      color: AppPalette.secondary.withValues(alpha: 0.5),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: AppPalette.secondary,
                        size: 18.0,
                      ),
                      const SizedBox(width: 8.0),
                      Flexible(
                        child: Text(
                          'PAGO CONFIRMADO - SIN RETIRO PDA',
                          style: AppTypography.small.copyWith(
                            color: AppPalette.secondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.0,
                            letterSpacing: 0.8,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20.0),

              // ── Contenido Central: QR Activo o Estado Bloqueado ──────────
              if (tieneQr && qrToken != null) ...[
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 16.0,
                        spreadRadius: 2.0,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: qrToken,
                    version: QrVersions.auto,
                    size: 210.0,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                    padding: const EdgeInsets.all(0),
                  ),
                ),
                const SizedBox(height: 16.0),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 8.0,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.background,
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.tag_rounded,
                        size: 16.0,
                        color: AppPalette.textSecondary,
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: Text(
                          qrToken,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.0,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(6.0),
                        onTap: () =>
                            _copiarTokenAlPortapapeles(context, qrToken),
                        child: const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.copy_rounded,
                            size: 16.0,
                            color: AppPalette.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (esReservada) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: AppPalette.background,
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(
                      color: AppPalette.warning.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: AppPalette.warning.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.lock_rounded,
                          size: 48.0,
                          color: AppPalette.warning,
                        ),
                      ),
                      const SizedBox(height: 14.0),
                      Text(
                        'CÓDIGO QR BLOQUEADO',
                        style: AppTypography.cardTitle.copyWith(
                          fontSize: 15.0,
                          color: AppPalette.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Text(
                        'El pase digital de salida para Bodega solo se generará tras confirmar la liquidación del pago en Caja.',
                        textAlign: TextAlign.center,
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textSecondary,
                          fontSize: 12.0,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14.0),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14.0,
                          vertical: 8.0,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.surface,
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(
                            color: AppPalette.warning.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text.rich(
                          TextSpan(
                            text: 'Saldo pendiente: ',
                            style: const TextStyle(
                              fontSize: 12.0,
                              color: AppPalette.textSecondary,
                            ),
                            children: [
                              TextSpan(
                                text: orden.montoPendienteFormateado,
                                style: const TextStyle(
                                  fontSize: 13.0,
                                  fontWeight: FontWeight.bold,
                                  color: AppPalette.warning,
                                ),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24.0),
                  decoration: BoxDecoration(
                    color: AppPalette.background,
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(
                      color: AppPalette.secondary.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: AppPalette.secondary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.inventory_2_outlined,
                          size: 48.0,
                          color: AppPalette.secondary,
                        ),
                      ),
                      const SizedBox(height: 14.0),
                      Text(
                        'SIN RETIRO FÍSICO PDA',
                        style: AppTypography.cardTitle.copyWith(
                          fontSize: 15.0,
                          color: AppPalette.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8.0),
                      Text(
                        'Esta orden contiene únicamente servicios o misceláneos. No requiere emisión de QR para validación en Bodega.',
                        textAlign: TextAlign.center,
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textSecondary,
                          fontSize: 12.0,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16.0),

              // ── Resumen de Operación (Cliente y Total) ───────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: AppPalette.background,
                  borderRadius: BorderRadius.circular(10.0),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Cliente:',
                          style: AppTypography.small.copyWith(
                            color: AppPalette.textSecondary,
                            fontSize: 12.0,
                          ),
                        ),
                        Text(
                          clienteNombre,
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 13.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'RUT:',
                          style: AppTypography.small.copyWith(
                            color: AppPalette.textSecondary,
                            fontSize: 12.0,
                          ),
                        ),
                        Text(
                          clienteRut,
                          style: AppTypography.body.copyWith(
                            fontSize: 13.0,
                            color: AppPalette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6.0),
                    const Divider(color: Colors.white10, height: 12.0),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            esReservada
                                ? 'Total de la Venta:'
                                : 'Total Cancelado:',
                            style: AppTypography.title.copyWith(fontSize: 13.0),
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        Text(
                          orden.totalVentaFormateado,
                          style: AppTypography.headline.copyWith(
                            fontSize: 16.0,
                            color: esReservada
                                ? AppPalette.textPrimary
                                : AppPalette.secondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16.0),

              // ── Instrucción Operativa ────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    tieneQr
                        ? Icons.info_outline_rounded
                        : (esReservada
                              ? Icons.lock_clock_outlined
                              : Icons.info_outline_rounded),
                    color: tieneQr
                        ? AppPalette.secondary
                        : (esReservada
                              ? AppPalette.warning
                              : AppPalette.secondary),
                    size: 16.0,
                  ),
                  const SizedBox(width: 8.0),
                  Expanded(
                    child: Text(
                      tieneQr
                          ? 'Muestre este QR al bodeguero en la Barrera de Salida para validar el Handshake y retirar el repuesto.'
                          : (esReservada
                                ? 'Derive al cliente a Caja para liquidar el pago. Bodega no autorizará la salida física hasta la confirmación.'
                                : 'Comprobante administrativo emitido. Los repuestos o servicios fueron entregados en mostrador.'),
                      style: AppTypography.small.copyWith(
                        fontSize: 14,
                        color: AppPalette.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20.0),

              // ── Botón de Cierre ──────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 44.0,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppPalette.textPrimary,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(tieneQr ? 'Cerrar Ticket' : 'Entendido'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
