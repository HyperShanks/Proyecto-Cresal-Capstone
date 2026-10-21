// lib/features/ventas/presentation/widgets/catalogo_item_detail_sheet.dart

import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../models/catalogo_model.dart';

/// Modal Bottom Sheet de Detalle Rápido de Repuesto (HU-3.2).
/// Despliega la ficha técnica completa, imagen referencial, distintivo de radar de stock
/// y acción inmediata de 'Añadir al Carrito' respetando SystemDesignCresal (Flat Design, sin sombras).
class CatalogoItemDetailSheet extends StatelessWidget {
  final CatalogoItem item;
  final int? vendedorSucursalId;
  final VoidCallback? onAddToCart;

  const CatalogoItemDetailSheet({
    super.key,
    required this.item,
    this.vendedorSucursalId,
    this.onAddToCart,
  });

  bool get _esMismaSucursal =>
      vendedorSucursalId != null && item.idSucursalActual == vendedorSucursalId;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12.0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Tirador visual superior ─────────────────────────────────────────
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppPalette.neutral.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),

          // ── Contenido con Scroll ──────────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20.0, 4.0, 20.0, 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Cabecera: Imagen Placeholder + Botón Cerrar (48x48) ────
                  Stack(
                    children: [
                      // Imagen referencial / Placeholder oscuro
                      Container(
                        width: double.infinity,
                        height: 160,
                        decoration: BoxDecoration(
                          color: AppPalette.background,
                          borderRadius: BorderRadius.circular(10.0),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                            width: 1.0,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              item.idCategoria == 1
                                  ? Icons.speed
                                  : Icons.settings_suggest_outlined,
                              size: 54,
                              color: AppPalette.primary.withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${item.nombreCategoria} Original',
                              style: AppTypography.small.copyWith(
                                color: AppPalette.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Botón 'X' superior derecho con Touch Target garantizado de 48x48
                      Positioned(
                        top: 6,
                        right: 6,
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Material(
                            color: AppPalette.surface.withValues(alpha: 0.85),
                            shape: const CircleBorder(),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () => Navigator.of(context).pop(),
                              child: const Icon(
                                Icons.close,
                                color: AppPalette.textPrimary,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 2. Título del Repuesto ────────────────────────────────────
                  Text(
                    item.tituloRepuesto,
                    style: AppTypography.title.copyWith(fontSize: 18),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),

                  // 3. Badges (Categoría + Radar de Sucursal) ─────────────────
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 6.0,
                    children: [
                      // Chip Categoría
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                        decoration: BoxDecoration(
                          color: AppPalette.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6.0),
                          border: Border.all(color: AppPalette.primary, width: 1.0),
                        ),
                        child: Text(
                          item.nombreCategoria,
                          style: AppTypography.small.copyWith(
                            color: AppPalette.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),

                      // Chip Radar de Sucursal
                      _buildRadarBadge(),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // 4. Ficha Técnica Organizada en 2 Columnas ─────────────────
                  _buildFichaTecnica(),
                ],
              ),
            ),
          ),

          // ── Pie del Modal: Precio + Botón 'Añadir al Carrito' (>= 48px) ───
          _buildBottomAction(context),
        ],
      ),
    );
  }

  /// Badge de Sucursal según algoritmo Radar de Stock
  Widget _buildRadarBadge() {
    if (_esMismaSucursal) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: AppPalette.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6.0),
          border: Border.all(color: AppPalette.primary, width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.my_location, size: 14, color: AppPalette.primary),
            const SizedBox(width: 5),
            Text(
              'En tu sucursal (${item.nombreSucursal})',
              style: AppTypography.small.copyWith(
                fontSize: 12,
                color: AppPalette.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: AppPalette.background,
        borderRadius: BorderRadius.circular(6.0),
        border: Border.all(color: AppPalette.neutral.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storefront_outlined, size: 14, color: AppPalette.neutral),
          const SizedBox(width: 5),
          Text(
            item.nombreSucursal,
            style: AppTypography.small.copyWith(
              fontSize: 12,
              color: AppPalette.neutral,
            ),
          ),
        ],
      ),
    );
  }

  /// Ficha técnica con fondo oscuro organizada en 2 columnas
  Widget _buildFichaTecnica() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppPalette.background,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FICHA TÉCNICA',
            style: AppTypography.small.copyWith(
              fontSize: 11,
              letterSpacing: 1.0,
              fontWeight: FontWeight.bold,
              color: AppPalette.textSecondary,
            ),
          ),
          const SizedBox(height: 12),

          // Fila 1: SKU y Cilindrada
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildDataField(
                  label: 'SKU / N° Pieza:',
                  value: item.skuQrFisico,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDataField(
                  label: 'Cilindrada:',
                  value: item.cilindrada ?? 'No especificada',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Fila 2: Combustible y Transmisión
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildDataField(
                  label: 'Combustible:',
                  value: item.combustible ?? 'No especificado',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDataField(
                  label: 'Transmisión:',
                  value: item.transmisionTipo ?? 'No especificada',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Fila 3: Tracción y Ubicación
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildDataField(
                  label: 'Tracción:',
                  value: item.traccion ?? 'Estándar',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDataField(
                  label: 'Ubicación Física:',
                  value: item.ubicacionFormateada,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Fila 4: Estado del Activo
          _buildDataField(
            label: 'Estado Inventario:',
            value: item.estadoActivo ?? 'Disponible',
          ),
        ],
      ),
    );
  }

  Widget _buildDataField({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.small.copyWith(
            fontSize: 11,
            color: AppPalette.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.body.copyWith(
            fontSize: 13,
            color: AppPalette.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ],
    );
  }

  /// Barra inferior con Precio y Botón de Acción
  Widget _buildBottomAction(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 16.0),
      decoration: const BoxDecoration(
        color: AppPalette.surface,
        border: Border(
          top: BorderSide(
            color: Colors.white10,
            width: 1.0,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Precio Lista Referencia
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PRECIO SUGERIDO:',
                    style: AppTypography.small.copyWith(
                      fontSize: 10,
                      letterSpacing: 0.8,
                      color: AppPalette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.precioSugeridoFormateado,
                    style: AppTypography.headline.copyWith(
                      color: AppPalette.secondary,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (item.precioMinimo != null && item.precioMaximo != null && item.precioMinimo != item.precioMaximo) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Rango: ${item.rangoPrecioFormateado}',
                      style: AppTypography.small.copyWith(
                        fontSize: 11,
                        color: AppPalette.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Botón Compacto Agregar
            SizedBox(
              height: 42,
              child: ElevatedButton.icon(
                onPressed: () {
                  onAddToCart?.call();
                  Navigator.of(context).pop();
                },
                icon: const Icon(
                  Icons.shopping_cart_outlined,
                  size: 18,
                  color: AppPalette.textPrimary,
                ),
                label: Text(
                  'Agregar',
                  style: AppTypography.button.copyWith(
                    color: AppPalette.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.primary,
                  foregroundColor: AppPalette.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 18.0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
