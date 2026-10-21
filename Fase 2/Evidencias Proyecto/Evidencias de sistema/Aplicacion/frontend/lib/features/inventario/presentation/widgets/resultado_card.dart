import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../screens/detalle_activo_screen.dart';

class ResultadoCard extends StatelessWidget {
  final Map<String, dynamic> itemCompleto;
  final String marca;
  final String modelo;
  final String sku;
  final String ubicacion;
  final String estado;

  const ResultadoCard({
    super.key,
    required this.itemCompleto,
    required this.marca,
    required this.modelo,
    required this.sku,
    required this.ubicacion,
    required this.estado,
  });

  String _formatearUbicacionHumana() {
    final pasillo = (itemCompleto['pasillo']?.toString() ?? itemCompleto['ubicacion_pasillo']?.toString() ?? '').trim();
    final pallet = (itemCompleto['pallet']?.toString() ?? itemCompleto['ubicacion_pallet']?.toString() ?? '').trim();
    final galpon = (itemCompleto['galpon']?.toString() ?? itemCompleto['ubicacion_galpon']?.toString() ?? '').trim();

    final bool tienePasillo = pasillo.isNotEmpty && pasillo != 'S/P' && pasillo != 'null';
    final bool tienePallet = pallet.isNotEmpty && pallet != 'S/P' && pallet != 'null';
    final bool tieneGalpon = galpon.isNotEmpty && galpon != 'S/G' && galpon != 'null';

    if (tienePasillo || tienePallet || tieneGalpon) {
      final pStr = tienePasillo ? pasillo : 'S/P';
      final paStr = tienePallet ? pallet : 'S/P';
      final gStr = tieneGalpon ? galpon : 'S/G';
      return 'Pasillo: $pStr | Pallet: $paStr | Galpón: $gStr';
    }

    return ubicacion.isNotEmpty && ubicacion != 'S/P - S/P' && ubicacion != 'No asignada' && ubicacion != 'null'
        ? ubicacion
        : 'Sin Paletizar / Sin Ubicación Asignada';
  }

  @override
  Widget build(BuildContext context) {
    final isReservado = estado.toUpperCase() == 'RESERVADO';
    final isVendido = estado.toUpperCase() == 'VENDIDO';
    final isDisponible = estado.toUpperCase() == 'DISPONIBLE';

    Color estadoColor;
    if (isDisponible) {
      estadoColor = AppPalette.success;
    } else if (isReservado) {
      estadoColor = AppPalette.secondary;
    } else if (isVendido) {
      estadoColor = AppPalette.error;
    } else {
      estadoColor = AppPalette.neutral;
    }

    final imagenes = itemCompleto['imagenes'] as List<dynamic>?;
    final String? imagenUrl = (imagenes != null && imagenes.isNotEmpty)
        ? imagenes.first.toString()
        : null;

    final pasillo = (itemCompleto['pasillo']?.toString() ?? itemCompleto['ubicacion_pasillo']?.toString() ?? '').trim();
    final pallet = (itemCompleto['pallet']?.toString() ?? itemCompleto['ubicacion_pallet']?.toString() ?? '').trim();
    final galpon = (itemCompleto['galpon']?.toString() ?? itemCompleto['ubicacion_galpon']?.toString() ?? '').trim();

    final bool tienePasillo = pasillo.isNotEmpty && pasillo != 'S/P' && pasillo != 'null';
    final bool tienePallet = pallet.isNotEmpty && pallet != 'S/P' && pallet != 'null';
    final bool tieneGalpon = galpon.isNotEmpty && galpon != 'S/G' && galpon != 'null';
    final bool tieneUbicacion = tienePasillo || tienePallet || tieneGalpon;

    final ubicacionHumana = _formatearUbicacionHumana();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isReservado
            ? AppPalette.secondary.withValues(alpha: 0.08)
            : AppPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isReservado
              ? AppPalette.secondary
              : AppPalette.neutral.withValues(alpha: 0.2),
          width: isReservado ? 1.8 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DetalleActivoScreen(activo: itemCompleto),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Miniatura o Placeholder Corporativo ──
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 52,
                    height: 52,
                    color: AppPalette.background,
                    child: (imagenUrl != null && imagenUrl.isNotEmpty)
                        ? Image.network(
                            imagenUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, error, stackTrace) => const Icon(
                              Icons.precision_manufacturing_outlined,
                              color: AppPalette.primary,
                              size: 28,
                            ),
                          )
                        : const Icon(
                            Icons.precision_manufacturing_outlined,
                            color: AppPalette.primary,
                            size: 28,
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              '${itemCompleto['categoria'] ?? 'Activo'} $marca $modelo',
                              style: AppTypography.title.copyWith(fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: estadoColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: estadoColor, width: 1),
                            ),
                            child: Text(
                              estado.toUpperCase(),
                              style: AppTypography.small.copyWith(
                                color: estadoColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 9,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'SKU: $sku',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (!tieneUbicacion) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppPalette.warning.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppPalette.warning.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 14, color: AppPalette.warning),
                              const SizedBox(width: 6),
                              Text(
                                'Sin Galpón / Sin Ubicación asignada',
                                style: AppTypography.small.copyWith(
                                  color: AppPalette.warning,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sin Paletizar / Sin Ubicación Asignada',
                          style: AppTypography.small.copyWith(
                            color: AppPalette.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              size: 14,
                              color: AppPalette.primary,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                ubicacionHumana,
                                style: AppTypography.small.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                      // ── Rango de Precio / Tasación ──
                      Builder(
                        builder: (context) {
                          final pMin = itemCompleto['precio_minimo'] as int?;
                          final pMax = itemCompleto['precio_maximo'] as int? ?? itemCompleto['precio_referencia'] as int?;
                          final pRef = itemCompleto['precio_referencia'] as int?;

                          String? rangoTexto;
                          if (pMin != null && pMax != null && pMin > 0 && pMax > 0) {
                            if (pMin == pMax) {
                              rangoTexto = 'Precio: \$${CurrencyFormatter.formatNumber(pMin)}';
                            } else {
                              rangoTexto = 'Rango: \$${CurrencyFormatter.formatNumber(pMin)} - \$${CurrencyFormatter.formatNumber(pMax)}';
                            }
                          } else if (pRef != null && pRef > 0) {
                            rangoTexto = 'Sugerido: \$${CurrencyFormatter.formatNumber(pRef)}';
                          }

                          if (rangoTexto == null) return const SizedBox.shrink();

                          return Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.sell_outlined,
                                  size: 13,
                                  color: AppPalette.secondary,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    rangoTexto,
                                    style: AppTypography.small.copyWith(
                                      color: AppPalette.secondary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
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
