import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../providers/caja_provider.dart';
import 'cobro_pendiente_card.dart';

/// Panel lateral izquierdo para la Bandeja de Cobros de Caja.
/// Estructurado según el prototipo: Tag "CAJA", "Pagos Pendientes", segmented control y buscador.
class BandejaCobrosPanel extends StatefulWidget {
  final CajaProvider provider;

  const BandejaCobrosPanel({super.key, required this.provider});

  @override
  State<BandejaCobrosPanel> createState() => _BandejaCobrosPanelState();
}

class _BandejaCobrosPanelState extends State<BandejaCobrosPanel> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.provider.terminoBusqueda;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;

    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surfaceLight,
        border: Border(
          right: BorderSide(
            color: AppPalette.neutral.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(provider),
          _buildSearchBar(provider),
          _buildPillFilters(provider),
          const SizedBox(height: 4),
          Expanded(child: _buildListContent(provider)),
        ],
      ),
    );
  }

  Widget _buildHeader(CajaProvider provider) {
    final ordenesTexto = provider.totalCobros == 1
        ? '1 orden esperando cobro'
        : '${provider.totalCobros} órdenes esperando cobro';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppPalette.neutral.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tag superior "CAJA" en gris
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.backgroundLight,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppPalette.neutral.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'CAJA',
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textSecondaryLight,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Título en negrita grande
                Text(
                  'Pagos Pendientes',
                  style: AppTypography.headline.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimaryLight,
                  ),
                ),
                const SizedBox(height: 2),
                // Subtítulo con total de órdenes
                Text(
                  ordenesTexto,
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondaryLight,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Botón de refresco animado
          Container(
            decoration: BoxDecoration(
              color: AppPalette.backgroundLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppPalette.neutral.withValues(alpha: 0.2),
              ),
            ),
            child: IconButton(
              icon: provider.isRefreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppPalette.primary,
                      ),
                    )
                  : const Icon(
                      Icons.refresh_rounded,
                      color: AppPalette.textSecondaryLight,
                      size: 20,
                    ),
              tooltip: 'Sincronizar bandeja',
              onPressed: provider.isRefreshing
                  ? null
                  : () => provider.cargarCobrosPendientes(refresh: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillFilters(CajaProvider provider) {
    final bool esNuevas =
        provider.filtroTipo == 'NUEVAS' || provider.filtroTipo == 'VENTA';
    final bool esAbonos =
        provider.filtroTipo == 'ABONOS' || provider.filtroTipo == 'ABONO';

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppPalette.backgroundLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.neutral.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          _buildPill(
            label: 'Ordenes Nuevas (${provider.totalNuevasCount})',
            isSelected: esNuevas,
            activeColor: AppPalette.primary,
            onTap: () => provider.setFiltroTipo('NUEVAS'),
          ),
          const SizedBox(width: 4),
          _buildPill(
            label: 'Ordenes Abonadas (${provider.totalAbonosCount})',
            isSelected: esAbonos,
            activeColor: const Color(0xFF7E22CE),
            onTap: () => provider.setFiltroTipo('ABONOS'),
          ),
        ],
      ),
    );
  }

  Widget _buildPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? activeColor,
  }) {
    final bgColor = isSelected ? AppPalette.surfaceLight : Colors.transparent;
    final textColor = isSelected
        ? (activeColor ?? AppPalette.primary)
        : AppPalette.textSecondaryLight;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTypography.small.copyWith(
              color: textColor,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(CajaProvider provider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: TextField(
        controller: _searchController,
        style: AppTypography.body.copyWith(
          fontSize: 13,
          color: AppPalette.textPrimaryLight,
        ),
        onChanged: (val) {
          setState(() {});
          provider.buscar(val);
        },
        decoration: InputDecoration(
          hintText: 'Buscar por Folio, RUT, Cliente o Vendedor...',
          hintStyle: AppTypography.small.copyWith(
            color: AppPalette.textSecondaryLight,
            fontSize: 14,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppPalette.textSecondaryLight,
            size: 18,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(
                    Icons.close_rounded,
                    color: AppPalette.textSecondaryLight,
                    size: 16,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                    provider.limpiarBusqueda();
                  },
                )
              : null,
          filled: true,
          fillColor: AppPalette.backgroundLight,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: AppPalette.neutral.withValues(alpha: 0.2),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: AppPalette.neutral.withValues(alpha: 0.2),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildListContent(CajaProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppPalette.primary),
      );
    }

    if (provider.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppPalette.error,
                size: 36,
              ),
              const SizedBox(height: 8),
              Text(
                provider.errorMessage!,
                style: AppTypography.small.copyWith(color: AppPalette.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Reintentar'),
                onPressed: () => provider.cargarCobrosPendientes(),
              ),
            ],
          ),
        ),
      );
    }

    if (provider.cobros.isEmpty) {
      return _buildZeroState(provider);
    }

    return ListView.builder(
      itemCount: provider.cobros.length,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemBuilder: (context, index) {
        final orden = provider.cobros[index];
        final isSelected =
            provider.ordenSeleccionada?.idReferencia == orden.idReferencia;

        return CobroPendienteCard(
          orden: orden,
          isSelected: isSelected,
          onTap: () => provider.seleccionarOrden(orden),
        );
      },
    );
  }

  Widget _buildZeroState(CajaProvider provider) {
    final tieneFiltros =
        provider.terminoBusqueda.isNotEmpty || provider.filtroTipo != 'TODOS';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppPalette.backgroundLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppPalette.neutral.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.inbox_rounded,
                size: 48,
                color: AppPalette.textSecondaryLight,
              ),
              const SizedBox(height: 12),
              Text(
                'No se encontraron órdenes pendientes',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppPalette.textPrimaryLight,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                tieneFiltros
                    ? 'No hay registros que coincidan con la búsqueda o filtro aplicado.'
                    : 'La bandeja de cobros de esta sucursal está al día.',
                style: AppTypography.small.copyWith(
                  color: AppPalette.textSecondaryLight,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
              if (tieneFiltros) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppPalette.primary,
                    side: const BorderSide(color: AppPalette.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.clear_all_rounded, size: 16),
                  label: const Text('Limpiar filtros'),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                    provider.limpiarBusqueda();
                    provider.setFiltroTipo('TODOS');
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
