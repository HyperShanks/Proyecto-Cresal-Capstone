// lib/features/ventas/presentation/widgets/pendiente_precio_card.dart

import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../models/pendiente_precio_model.dart';

/// Tarjeta Flat Design para representar un repuesto pendiente de fijación de precio (HU-3.8).
class PendientePrecioCard extends StatelessWidget {
  final ActivoPendientePrecioModel activo;
  final VoidCallback onAsignarPrecio;

  const PendientePrecioCard({
    super.key,
    required this.activo,
    required this.onAsignarPrecio,
  });

  IconData _getCategoryIcon(int idCategoria) {
    switch (idCategoria) {
      case 1:
        return Icons.build_circle_outlined; // Motor
      case 2:
        return Icons.settings_input_component_outlined; // Caja de cambios
      default:
        return Icons.auto_awesome_mosaic_outlined; // Accesorios / Otros
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12.0),
          onTap: onAsignarPrecio,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Cabecera: Icono + Título + SKU ─────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: AppPalette.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: Icon(
                        _getCategoryIcon(activo.idCategoria),
                        color: AppPalette.primary,
                        size: 24.0,
                      ),
                    ),
                    const SizedBox(width: 12.0),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activo.tituloVehiculo,
                            style: AppTypography.title.copyWith(
                              fontSize: 16.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4.0),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                  vertical: 2.0,
                                ),
                                decoration: BoxDecoration(
                                  color: AppPalette.background,
                                  borderRadius: BorderRadius.circular(6.0),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Text(
                                  activo.skuQrFisico,
                                  style: AppTypography.small.copyWith(
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w600,
                                    color: AppPalette.secondary,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8.0),
                              Text(
                                activo.nombreCategoria,
                                style: AppTypography.small.copyWith(
                                  color: AppPalette.textSecondary,
                                  fontSize: 12.0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14.0),
                const Divider(color: Colors.white10, height: 1.0),
                const SizedBox(height: 12.0),

                // ── Ficha Técnica del Repuesto ─────────────────────────────
                Row(
                  children: [
                    const Icon(Icons.directions_car_outlined, size: 16.0, color: AppPalette.textSecondary),
                    const SizedBox(width: 6.0),
                    Expanded(
                      child: Text(
                        activo.fichaVehiculoDisplay,
                        style: AppTypography.body.copyWith(
                          fontSize: 13.0,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6.0),

                Row(
                  children: [
                    const Icon(Icons.miscellaneous_services_outlined, size: 16.0, color: AppPalette.textSecondary),
                    const SizedBox(width: 6.0),
                    Expanded(
                      child: Text(
                        activo.especificacionesDisplay,
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textSecondary,
                          fontSize: 12.0,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6.0),

                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 16.0, color: AppPalette.textSecondary),
                    const SizedBox(width: 6.0),
                    Expanded(
                      child: Text(
                        '${activo.nombreSucursal} • ${activo.ubicacionDisplay}',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textSecondary,
                          fontSize: 12.0,
                        ),
                      ),
                    ),
                  ],
                ),

                if (activo.observacionEstado != null &&
                    activo.observacionEstado!.trim().isNotEmpty &&
                    activo.observacionEstado!.trim() != 'null' &&
                    activo.observacionEstado!.trim() != 'Sin observaciones registradas.') ...[
                  const SizedBox(height: 10.0),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      color: AppPalette.secondary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(
                        color: AppPalette.secondary.withValues(alpha: 0.3),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.sticky_note_2_outlined, size: 16.0, color: AppPalette.secondary),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: AppTypography.small.copyWith(
                                color: AppPalette.textPrimary,
                                fontSize: 12.0,
                              ),
                              children: [
                                const TextSpan(
                                  text: 'Obs. Bodega: ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppPalette.secondary,
                                  ),
                                ),
                                TextSpan(
                                  text: activo.observacionEstado!.trim(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14.0),

                // ── Botón de Acción: Asignar Precio ────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 48.0,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.primary,
                      foregroundColor: AppPalette.textPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                    ),
                    icon: const Icon(Icons.price_change_outlined, size: 20.0),
                    label: const Text(
                      'Fijar Precio de Referencia',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.0,
                      ),
                    ),
                    onPressed: onAsignarPrecio,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
