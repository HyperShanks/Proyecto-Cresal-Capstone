import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../models/historial_caja_model.dart';
import 'cobro_pendiente_card.dart';

/// Tabla estructurada para la visualización del historial y auditoría de órdenes de caja (SPEC-HU-4.5).
/// Diseño responsivo con scroll horizontal automático en pantallas estrechas/POS para evitar desbordamientos.
class HistorialTablaView extends StatelessWidget {
  final List<HistorialOrdenItemModel> items;
  final int paginaActual;
  final int totalPaginas;
  final ValueChanged<int> onCambiarPagina;
  final ValueChanged<HistorialOrdenItemModel> onVerDetalle;
  final bool isReadOnly;
  final bool mostrarSucursal;

  const HistorialTablaView({
    super.key,
    required this.items,
    required this.paginaActual,
    required this.totalPaginas,
    required this.onCambiarPagina,
    required this.onVerDetalle,
    this.isReadOnly = false,
    this.mostrarSucursal = false,
  });

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final minTableWidth = mostrarSucursal ? 1040.0 : 960.0;
        final needsHorizontalScroll = constraints.maxWidth < minTableWidth;
        final isCompactPagination = constraints.maxWidth < 640;

        Widget tableBody = SizedBox(
          width: needsHorizontalScroll ? minTableWidth : constraints.maxWidth,
          child: Column(
            children: [
              // ── CABECERA DE LA TABLA ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppPalette.backgroundLight,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(11),
                    topRight: Radius.circular(11),
                  ),
                  border: Border(
                    bottom: BorderSide(
                      color: AppPalette.neutral.withValues(alpha: 0.15),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _buildHeaderCell('FOLIO', flex: 2),
                    _buildHeaderCell('FECHA / HORA', flex: 2),
                    _buildHeaderCell('CLIENTE / RUT', flex: 3),
                    if (mostrarSucursal)
                      _buildHeaderCell('SUCURSAL', flex: 2),
                    _buildHeaderCell('VENDEDOR / CAJERA', flex: 3),
                    _buildHeaderCell('ESTADO', flex: 2),
                    _buildHeaderCell('MÉTODOS DE PAGO', flex: 3),
                    _buildHeaderCell('TOTAL', flex: 2, alignment: Alignment.centerRight),
                    _buildHeaderCell('AUDITORÍA', flex: 2, alignment: Alignment.center),
                  ],
                ),
              ),

              // ── FILAS DE DATOS ──
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: AppPalette.neutral.withValues(alpha: 0.1),
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final estadoColor = _getEstadoColor(item.estadoOrden);

                    return InkWell(
                      onTap: () => onVerDetalle(item),
                      hoverColor: AppPalette.primary.withValues(alpha: 0.03),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            // Folio + QR indicator
                            Expanded(
                              flex: 2,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      item.folio,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.body.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: AppPalette.textPrimaryLight,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  if (item.emiteQr) ...[
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.qr_code_2_rounded,
                                      size: 15,
                                      color: AppPalette.primary,
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // Fecha / Hora
                            Expanded(
                              flex: 2,
                              child: Text(
                                item.fechaHoraFormateada,
                                style: AppTypography.small.copyWith(
                                  color: AppPalette.textSecondaryLight,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),

                            // Cliente / RUT
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.clienteNombre,
                                    style: AppTypography.small.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppPalette.textPrimaryLight,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Builder(
                                    builder: (context) {
                                      final rut = item.clienteRut;
                                      final rutLimpio = rut?.replaceAll(RegExp(r'[^0-9kK]'), '') ?? '';
                                      final esGenerico = rut == null ||
                                          rutLimpio.isEmpty ||
                                          rutLimpio.startsWith('666666') ||
                                          rut == '6.666.666-6';

                                      if (esGenerico) {
                                        return Text(
                                          'Sin RUT',
                                          style: AppTypography.small.copyWith(
                                            color: AppPalette.textSecondaryLight,
                                            fontSize: 11,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        );
                                      }

                                      return Text(
                                        rut,
                                        style: AppTypography.small.copyWith(
                                          color: AppPalette.textSecondaryLight,
                                          fontSize: 12,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),

                            // Sucursal (si aplica vista consolidada)
                            if (mostrarSucursal)
                              Expanded(
                                flex: 2,
                                child: Text(
                                  item.sucursalNombre.isNotEmpty
                                      ? item.sucursalNombre
                                      : 'Casa Matriz',
                                  style: AppTypography.small.copyWith(
                                    color: AppPalette.textPrimaryLight,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),

                            // Vendedor / Cajera
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.vendedorNombre,
                                    style: AppTypography.small.copyWith(
                                      color: AppPalette.textPrimaryLight,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Caja: ${item.cajeraNombre}',
                                    style: AppTypography.small.copyWith(
                                      color: AppPalette.textSecondaryLight,
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),

                            // Estado Badge
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
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
                                    item.estadoOrden,
                                    style: AppTypography.small.copyWith(
                                      color: estadoColor,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // Métodos de Pago
                            Expanded(
                              flex: 3,
                              child: Text(
                                item.metodosResumen,
                                style: AppTypography.small.copyWith(
                                  color: AppPalette.textSecondaryLight,
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),

                            // Total
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      CobroPendienteCard.formatClp(
                                        item.totalVenta > 0
                                            ? item.totalVenta
                                            : item.totalLiquidado,
                                      ),
                                      style: AppTypography.body.copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: item.esAnulada
                                            ? AppPalette.textSecondaryLight
                                            : AppPalette.textPrimaryLight,
                                      ),
                                    ),
                                    if (item.montoPendiente > 0)
                                      Text(
                                        'Pend: ${CobroPendienteCard.formatClp(item.montoPendiente)}',
                                        style: AppTypography.small.copyWith(
                                          color: AppPalette.secondary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            // Acciones: Botón "Auditar" o "Ver Detalle"
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.center,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    side: BorderSide(
                                      color: isReadOnly
                                          ? AppPalette.tertiary.withValues(alpha: 0.5)
                                          : AppPalette.primary.withValues(alpha: 0.5),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  icon: Icon(
                                    isReadOnly
                                        ? Icons.manage_search_rounded
                                        : Icons.visibility_rounded,
                                    size: 14,
                                    color: isReadOnly
                                        ? AppPalette.tertiary
                                        : AppPalette.primary,
                                  ),
                                  label: Text(
                                    isReadOnly ? 'Auditar' : 'Ver Detalle',
                                    style: AppTypography.button.copyWith(
                                      color: isReadOnly
                                          ? AppPalette.tertiary
                                          : AppPalette.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  onPressed: () => onVerDetalle(item),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );

        if (needsHorizontalScroll) {
          tableBody = Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: tableBody,
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: AppPalette.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppPalette.neutral.withValues(alpha: 0.18),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Expanded(child: tableBody),

              // ── BARRA DE PAGINACIÓN INFERIOR RESPONSIVA ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppPalette.backgroundLight,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(11),
                    bottomRight: Radius.circular(11),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: AppPalette.neutral.withValues(alpha: 0.15),
                      width: 1,
                    ),
                  ),
                ),
                child: isCompactPagination
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Página $paginaActual de $totalPaginas (${items.length} regs)',
                            style: AppTypography.small.copyWith(
                              color: AppPalette.textSecondaryLight,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildBotonPaginacion(
                                icon: Icons.chevron_left_rounded,
                                label: 'Anterior',
                                habilitado: paginaActual > 1,
                                onTap: () => onCambiarPagina(paginaActual - 1),
                              ),
                              const SizedBox(width: 8),
                              _buildBotonPaginacion(
                                icon: Icons.chevron_right_rounded,
                                label: 'Siguiente',
                                habilitado: paginaActual < totalPaginas,
                                onTap: () => onCambiarPagina(paginaActual + 1),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Mostrando página $paginaActual de $totalPaginas (${items.length} registros en esta página)',
                            style: AppTypography.small.copyWith(
                              color: AppPalette.textSecondaryLight,
                              fontSize: 13,
                            ),
                          ),
                          Row(
                            children: [
                              _buildBotonPaginacion(
                                icon: Icons.chevron_left_rounded,
                                label: 'Anterior',
                                habilitado: paginaActual > 1,
                                onTap: () => onCambiarPagina(paginaActual - 1),
                              ),
                              const SizedBox(width: 8),
                              _buildBotonPaginacion(
                                icon: Icons.chevron_right_rounded,
                                label: 'Siguiente',
                                habilitado: paginaActual < totalPaginas,
                                onTap: () => onCambiarPagina(paginaActual + 1),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBotonPaginacion({
    required IconData icon,
    required String label,
    required bool habilitado,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppPalette.primary,
        disabledForegroundColor:
            AppPalette.textSecondaryLight.withValues(alpha: 0.45),
        disabledIconColor: AppPalette.textSecondaryLight.withValues(alpha: 0.45),
        backgroundColor: Colors.white,
        disabledBackgroundColor: AppPalette.backgroundLight,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(
          color: AppPalette.neutral.withValues(alpha: 0.25),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: AppTypography.button.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
      onPressed: habilitado ? onTap : null,
    );
  }

  Widget _buildHeaderCell(
    String label, {
    required int flex,
    Alignment alignment = Alignment.centerLeft,
  }) {
    return Expanded(
      flex: flex,
      child: Align(
        alignment: alignment,
        child: Text(
          label,
          style: AppTypography.small.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 12,
            color: AppPalette.textSecondaryLight,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}
