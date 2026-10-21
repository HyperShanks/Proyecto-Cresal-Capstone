import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../models/historial_caja_model.dart';
import 'cobro_pendiente_card.dart';

/// Diálogo modal con ficha de cliente, responsables, desglose de ítems, pagos exactos y trazabilidad de auditoría (SPEC-HU-4.5).
class DetalleAuditoriaDialog extends StatelessWidget {
  final HistorialOrdenItemModel orden;

  const DetalleAuditoriaDialog({
    super.key,
    required this.orden,
  });

  static Future<void> show(BuildContext context, HistorialOrdenItemModel orden) {
    return showDialog(
      context: context,
      builder: (context) => DetalleAuditoriaDialog(orden: orden),
    );
  }

  Color _getEstadoColor(String estado) {
    switch (estado.toLowerCase()) {
      case 'pagada':
        return AppPalette.success;
      case 'despachada':
        return const Color(0xFF0284C7);
      case 'reservada':
      case 'pendiente':
        return AppPalette.secondary;
      case 'anulada':
        return AppPalette.error;
      default:
        return AppPalette.textSecondaryLight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final estadoColor = _getEstadoColor(orden.estadoOrden);

    return Dialog(
      backgroundColor: AppPalette.surfaceLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppPalette.neutral.withValues(alpha: 0.2),
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: Container(
        width: 720,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          children: [
            // ── CABECERA DEL MODAL ──
            _buildHeader(context, estadoColor),

            Divider(
              height: 1,
              color: AppPalette.neutral.withValues(alpha: 0.15),
            ),

            // ── CUERPO CON SCROLL ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Ficha de Cliente y Responsables
                    _buildSeccionClientePersonal(),
                    const SizedBox(height: 20),

                    // 2. Desglose de Repuestos y Artículos
                    _buildSeccionArticulos(),
                    const SizedBox(height: 20),

                    // 3. Desglose Exacto de Pagos (Auditoría)
                    _buildSeccionPagos(),
                    const SizedBox(height: 20),

                    // 4. Línea de Tiempo de Auditoría
                    _buildSeccionTimeline(),
                  ],
                ),
              ),
            ),

            Divider(
              height: 1,
              color: AppPalette.neutral.withValues(alpha: 0.15),
            ),

            // ── FOOTER DE ACCIONES ──
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color estadoColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppPalette.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: AppPalette.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            orden.folio,
                            style: AppTypography.headline.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: AppPalette.textPrimaryLight,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: estadoColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: estadoColor.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              orden.estadoOrden.toUpperCase(),
                              style: AppTypography.small.copyWith(
                                color: estadoColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          if (orden.emiteQr)
                            Tooltip(
                              message: 'QR Transaccional emitido para barrera de salida',
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppPalette.backgroundLight,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: AppPalette.neutral.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.qr_code_2_rounded,
                                      size: 13,
                                      color: AppPalette.textPrimaryLight,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'QR Activo',
                                      style: AppTypography.small.copyWith(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: AppPalette.textPrimaryLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Emitida el ${orden.fechaCreacionFormateada ?? orden.fechaHoraFormateada}'.replaceAll('/2026', '/26'),
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textSecondaryLight,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            color: AppPalette.textSecondaryLight,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionClientePersonal() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppPalette.neutral.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cliente
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DATOS DEL CLIENTE',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondaryLight,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  orden.clienteNombre,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textPrimaryLight,
                  ),
                ),
                if (orden.clienteRut != null && orden.clienteRut!.isNotEmpty)
                  Text(
                    'RUT: ${orden.clienteRut}',
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textSecondaryLight,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 50,
            color: AppPalette.neutral.withValues(alpha: 0.2),
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          // Personal Responsable
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PERSONAL RESPONSABLE',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondaryLight,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.person_pin_rounded,
                      size: 14,
                      color: AppPalette.primary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Vendedor: ${orden.vendedorNombre}',
                        style: AppTypography.small.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppPalette.textPrimaryLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(
                      Icons.point_of_sale_rounded,
                      size: 14,
                      color: AppPalette.success,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Cajera: ${orden.cajeraNombre}',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textSecondaryLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (orden.sucursalNombre.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.storefront_rounded,
                        size: 14,
                        color: AppPalette.secondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Sucursal: ${orden.sucursalNombre}',
                          style: AppTypography.small.copyWith(
                            color: AppPalette.textSecondaryLight,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionArticulos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DETALLE DE PIEZAS Y ARTÍCULOS',
          style: AppTypography.small.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: 0.8,
            color: AppPalette.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppPalette.surfaceLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppPalette.neutral.withValues(alpha: 0.18),
            ),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: orden.articulos.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: AppPalette.neutral.withValues(alpha: 0.12),
            ),
            itemBuilder: (context, index) {
              final art = orden.articulos[index];
              final tieneSku = art.sku != null && art.sku!.isNotEmpty;

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppPalette.backgroundLight,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppPalette.neutral.withValues(alpha: 0.2),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${art.cantidad}x',
                        style: AppTypography.small.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppPalette.primary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            art.nombreDisplay,
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppPalette.textPrimaryLight,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (tieneSku)
                            Text(
                              'SKU: ${art.sku}',
                              style: AppTypography.small.copyWith(
                                color: AppPalette.textSecondaryLight,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                            )
                          else
                            Builder(
                              builder: (context) {
                                final bool esVentaVerde = art.tipo == 'RESERVA' ||
                                    art.descripcion.toUpperCase().contains('VENTA EN VERDE');

                                if (esVentaVerde) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3E8FF),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: const Color(0xFFC084FC),
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      'Venta en Verde',
                                      style: AppTypography.small.copyWith(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF7E22CE),
                                      ),
                                    ),
                                  );
                                }

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: AppPalette.neutral.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Misceláneo',
                                    style: AppTypography.small.copyWith(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppPalette.textSecondaryLight,
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                    Text(
                      CobroPendienteCard.formatClp(art.subtotal),
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textPrimaryLight,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSeccionPagos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'DESGLOSE EXACTO DE PAGOS (AUDITORÍA)',
                style: AppTypography.small.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.8,
                  color: AppPalette.textSecondaryLight,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Total Liquidado: ${CobroPendienteCard.formatClp(orden.totalLiquidado)}',
              style: AppTypography.small.copyWith(
                fontWeight: FontWeight.w800,
                color: AppPalette.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (orden.desglosePagos.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.backgroundLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'No se registran transacciones de pago para esta orden.',
              style: AppTypography.small.copyWith(
                color: AppPalette.textSecondaryLight,
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppPalette.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppPalette.neutral.withValues(alpha: 0.18),
              ),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: orden.desglosePagos.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                color: AppPalette.neutral.withValues(alpha: 0.12),
              ),
              itemBuilder: (context, index) {
                final pago = orden.desglosePagos[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppPalette.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          pago.metodoPago,
                          style: AppTypography.small.copyWith(
                            color: AppPalette.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          pago.idTransaccion != null
                              ? 'TX: ${(pago.idTransaccion!.length > 8 ? pago.idTransaccion!.substring(0, 8) : pago.idTransaccion!).toUpperCase()}'
                              : 'Transacción Directa',
                          style: AppTypography.small.copyWith(
                            color: AppPalette.textPrimaryLight,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        CobroPendienteCard.formatClp(pago.monto),
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppPalette.success,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSeccionTimeline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'TRAZABILIDAD Y LÍNEA DE TIEMPO',
          style: AppTypography.small.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: 0.8,
            color: AppPalette.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppPalette.backgroundLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppPalette.neutral.withValues(alpha: 0.18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: orden.historialMovimientos.map((mov) {
              final horaDisplay = mov.hora.replaceAll('/2026', '/26');
              final isLast = mov == orden.historialMovimientos.last;
              return Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 14,
                          color: AppPalette.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          horaDisplay,
                          style: AppTypography.small.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppPalette.textPrimaryLight,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Padding(
                      padding: const EdgeInsets.only(left: 20),
                      child: Text(
                        mov.evento,
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textSecondaryLight,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Total Operación: ${CobroPendienteCard.formatClp(orden.totalVenta)}',
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimaryLight,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CERRAR'),
          ),
        ],
      ),
    );
  }
}
