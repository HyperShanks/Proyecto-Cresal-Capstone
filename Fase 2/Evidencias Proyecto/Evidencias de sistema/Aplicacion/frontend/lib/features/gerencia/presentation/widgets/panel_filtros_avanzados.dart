// frontend/lib/features/gerencia/presentation/widgets/panel_filtros_avanzados.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/widgets/cresal_filter_dropdown.dart';

/// Barra de filtros multidimensionales de alta densidad para el visor de órdenes (HU-5.2).
/// Diseñé este widget inspirándome en la barra unificada de `prototipo_gerencia_v1.html`,
/// permitiendo filtrar simultáneamente por término libre, rango temporal predeterminado,
/// estado oficial de la orden y método de pago con botón de limpieza inmediata.
class PanelFiltrosAvanzados extends StatelessWidget {
  final TextEditingController busquedaController;
  final ValueChanged<String> onBusquedaChanged;
  final String periodoSeleccionado;
  final ValueChanged<String> onPeriodoChanged;
  final String estadoSeleccionado;
  final ValueChanged<String> onEstadoChanged;
  final String metodoPagoSeleccionado;
  final ValueChanged<String> onMetodoPagoChanged;
  final String tipoActivoSeleccionado;
  final ValueChanged<String> onTipoActivoChanged;
  final VoidCallback onLimpiar;

  const PanelFiltrosAvanzados({
    super.key,
    required this.busquedaController,
    required this.onBusquedaChanged,
    required this.periodoSeleccionado,
    required this.onPeriodoChanged,
    required this.estadoSeleccionado,
    required this.onEstadoChanged,
    required this.metodoPagoSeleccionado,
    required this.onMetodoPagoChanged,
    this.tipoActivoSeleccionado = 'todos',
    required this.onTipoActivoChanged,
    required this.onLimpiar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppPalette.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppPalette.neutral.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1200;

          final widgets = [
            // 1. Buscador Predictivo (Folio, Cliente, RUT o Vendedor)
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: isWide ? 180 : 200,
                maxWidth: 340,
              ),
              child: TextField(
                controller: busquedaController,
                onChanged: onBusquedaChanged,
                style: AppTypography.small.copyWith(
                  fontSize: 13,
                  color: AppPalette.textPrimaryLight,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar por Folio, Cliente, RUT o Vendedor...',
                  hintStyle: AppTypography.small.copyWith(
                    color: AppPalette.textSecondaryLight.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: AppPalette.textSecondaryLight,
                  ),
                  suffixIcon: busquedaController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          color: AppPalette.textSecondaryLight,
                          onPressed: () {
                            busquedaController.clear();
                            onBusquedaChanged('');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: AppPalette.backgroundLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: AppPalette.neutral.withValues(alpha: 0.25),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: AppPalette.neutral.withValues(alpha: 0.25),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: AppPalette.tertiary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),

            // 2. Segmented Buttons para Período Temporal Oficial
            _buildSegmentedPeriodo(),

            // 3. Dropdown de Estado Oficial (5 estados)
            _buildDropdownEstado(),

            // 4. Dropdown de Método de Pago
            _buildDropdownMetodoPago(),

            // 5. Dropdown de Tipo de Activo (Motores y Cajas, Inventariados, Desarme)
            _buildDropdownTipoActivo(),

            // 6. Botón Limpiar Filtros
            _buildBotonLimpiar(),
          ];

          if (isWide) {
            return Row(
              children: [
                Expanded(child: widgets[0]),
                const SizedBox(width: 6),
                widgets[1],
                const SizedBox(width: 6),
                widgets[2],
                const SizedBox(width: 6),
                widgets[3],
                const SizedBox(width: 6),
                widgets[4],
                const SizedBox(width: 6),
                widgets[5],
              ],
            );
          } else {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: widgets,
            );
          }
        },
      ),
    );
  }

  Widget _buildSegmentedPeriodo() {
    final periodos = [
      {'id': 'hoy', 'label': 'Hoy'},
      {'id': '7d', 'label': 'Esta Semana'},
      {'id': '30d', 'label': 'Este Mes'},
      {'id': 'todos', 'label': 'Todo'},
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppPalette.backgroundLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppPalette.neutral.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: periodos.map((p) {
          final isSelected = periodoSeleccionado == p['id'];
          return InkWell(
            onTap: () => onPeriodoChanged(p['id']!),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? AppPalette.surfaceLight : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                p['label']!,
                style: AppTypography.small.copyWith(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? AppPalette.tertiary
                      : AppPalette.textSecondaryLight,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDropdownEstado() {
    final estados = const [
      CresalFilterDropdownItem(value: 'todos', label: 'Estado: Todos'),
      CresalFilterDropdownItem(value: 'Reservada', label: 'Reservada'),
      CresalFilterDropdownItem(value: 'Pagada', label: 'Pagada'),
      CresalFilterDropdownItem(value: 'Completada', label: 'Completada'),
      CresalFilterDropdownItem(value: 'Despachada', label: 'Despachada'),
      CresalFilterDropdownItem(value: 'Anulada', label: 'Anulada'),
    ];

    final effectiveValue = estados.any((e) => e.value == estadoSeleccionado)
        ? estadoSeleccionado
        : 'todos';

    return CresalFilterDropdown<String>(
      height: 32,
      value: effectiveValue,
      backgroundColor: Colors.white,
      borderColor: AppPalette.borderLight,
      isExpanded: false,
      items: estados,
      onChanged: onEstadoChanged,
    );
  }

  Widget _buildDropdownMetodoPago() {
    final metodos = const [
      CresalFilterDropdownItem(value: 'todos', label: 'Método: Todos'),
      CresalFilterDropdownItem(value: 'Transferencia', label: 'Transferencia'),
      CresalFilterDropdownItem(value: 'Débito', label: 'Débito'),
      CresalFilterDropdownItem(value: 'Crédito', label: 'Crédito'),
      CresalFilterDropdownItem(value: 'Efectivo', label: 'Efectivo'),
      CresalFilterDropdownItem(value: 'Cheque', label: 'Cheque'),
    ];

    final effectiveValue = metodos.any((m) => m.value == metodoPagoSeleccionado)
        ? metodoPagoSeleccionado
        : 'todos';

    return CresalFilterDropdown<String>(
      height: 32,
      value: effectiveValue,
      backgroundColor: Colors.white,
      borderColor: AppPalette.borderLight,
      isExpanded: false,
      items: metodos,
      onChanged: onMetodoPagoChanged,
    );
  }

  Widget _buildDropdownTipoActivo() {
    final tipos = const [
      CresalFilterDropdownItem(value: 'todos', label: 'Tipo: Todos'),
      CresalFilterDropdownItem(value: 'MOTORES_CAJAS', label: '⚙️ Solo Motores y Cajas'),
    ];

    final effectiveValue = tipos.any((t) => t.value == tipoActivoSeleccionado)
        ? tipoActivoSeleccionado
        : 'todos';
    final isActive = effectiveValue != 'todos';

    return CresalFilterDropdown<String>(
      height: 32,
      value: effectiveValue,
      backgroundColor: isActive ? const Color(0xFFEEF2FF) : Colors.white,
      borderColor: isActive ? const Color(0xFF6366F1) : AppPalette.borderLight,
      isExpanded: false,
      items: tipos,
      onChanged: onTipoActivoChanged,
    );
  }

  int get _cantidadFiltrosActivos {
    int count = 0;
    if (busquedaController.text.trim().isNotEmpty) count++;
    if (periodoSeleccionado != 'hoy') count++;
    if (estadoSeleccionado.isNotEmpty && estadoSeleccionado.toLowerCase() != 'todos') count++;
    if (metodoPagoSeleccionado.isNotEmpty && metodoPagoSeleccionado.toLowerCase() != 'todos') count++;
    if (tipoActivoSeleccionado.isNotEmpty && tipoActivoSeleccionado.toLowerCase() != 'todos') count++;
    return count;
  }

  Widget _buildBotonLimpiar() {
    final count = _cantidadFiltrosActivos;
    final hayFiltros = count > 0;

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: hayFiltros
            ? AppPalette.tertiary.withValues(alpha: 0.1)
            : Colors.transparent,
        side: BorderSide(
          color: hayFiltros
              ? AppPalette.tertiary
              : AppPalette.neutral.withValues(alpha: 0.3),
          width: hayFiltros ? 1.5 : 1.0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      icon: Icon(
        Icons.filter_alt_off_rounded,
        size: 16,
        color: hayFiltros ? AppPalette.tertiary : AppPalette.textSecondaryLight,
      ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Limpiar',
            style: AppTypography.button.copyWith(
              color: hayFiltros ? AppPalette.tertiary : AppPalette.textSecondaryLight,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          if (hayFiltros) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppPalette.tertiary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      onPressed: onLimpiar,
    );
  }
}
