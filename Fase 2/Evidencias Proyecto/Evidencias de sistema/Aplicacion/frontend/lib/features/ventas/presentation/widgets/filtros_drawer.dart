// lib/features/ventas/presentation/widgets/filtros_drawer.dart

import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/constants/especificaciones_vehiculo.dart';

/// Panel lateral de filtros interactivos para el Catálogo de Repuestos (HU-3.2).
/// Consume opciones dinámicas de repuestos en estado Disponible y se adapta
/// con alto contraste a temas Claro y Oscuro.
class FiltrosDrawer extends StatelessWidget {
  final int? idCategoria;
  final int? idSucursal;
  final String? marca;
  final int? anio;
  final String? cilindrada;
  final String? transmision;
  final String? combustible;
  final String? traccion;

  /// Opciones dinámicas cargadas desde la BD (sólo activos Disponibles)
  final List<String> marcasDisponibles;
  final List<int> aniosDisponibles;
  final List<String> cilindradasDisponibles;
  final List<String> transmisionesDisponibles;

  final ValueChanged<int?> onCategoriaChanged;
  final ValueChanged<int?> onSucursalChanged;
  final ValueChanged<String?> onMarcaChanged;
  final ValueChanged<int?> onAnioChanged;
  final ValueChanged<String?> onCilindradaChanged;
  final ValueChanged<String?> onTransmisionChanged;
  final ValueChanged<String?>? onCombustibleChanged;
  final ValueChanged<String?>? onTraccionChanged;
  final VoidCallback onLimpiarFiltros;

  const FiltrosDrawer({
    super.key,
    required this.idCategoria,
    required this.idSucursal,
    required this.marca,
    required this.anio,
    this.cilindrada,
    this.transmision,
    this.combustible,
    this.traccion,
    this.marcasDisponibles = const [],
    this.aniosDisponibles = const [],
    this.cilindradasDisponibles = const [],
    this.transmisionesDisponibles = const [],
    required this.onCategoriaChanged,
    required this.onSucursalChanged,
    required this.onMarcaChanged,
    required this.onAnioChanged,
    required this.onCilindradaChanged,
    required this.onTransmisionChanged,
    this.onCombustibleChanged,
    this.onTraccionChanged,
    required this.onLimpiarFiltros,
  });

  @override
  Widget build(BuildContext context) {
    // El catálogo de ventas en mesón utiliza la paleta oscura de alto contraste
    const drawerBg = AppPalette.background;
    const surfaceColor = AppPalette.surface;
    const textPrimaryColor = AppPalette.textPrimary;
    const textSecondaryColor = AppPalette.textSecondary;
    const dividerColor = Colors.white12;

    // Listas seguras para dropdowns (evitan AssertionError si el valor actual no está en la lista)
    final List<String> listaMarcas = [
      if (marca != null && marca!.trim().isNotEmpty && !marcasDisponibles.contains(marca))
        marca!,
      ...marcasDisponibles,
    ];

    final List<int> listaAnios = [
      if (anio != null && !aniosDisponibles.contains(anio))
        anio!,
      ...aniosDisponibles,
    ];

    final List<String> listaCilindradas = [
      if (cilindrada != null && cilindrada!.trim().isNotEmpty && !cilindradasDisponibles.contains(cilindrada))
        cilindrada!,
      ...cilindradasDisponibles,
    ];

    final List<String> listaTransmisiones = transmisionesDisponibles.isNotEmpty
        ? transmisionesDisponibles
        : const ['Mecánica', 'Automática', 'Semiautomática'];

    return Drawer(
      backgroundColor: drawerBg,
      elevation: 0,
      child: SafeArea(
        child: Column(
          children: [
            // ── Cabecera: Título + Botón Ocultar ─────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12.0,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: dividerColor,
                    width: 1.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filtros',
                      style: AppTypography.title.copyWith(
                        color: textPrimaryColor,
                      ),
                    ),
                  ),
                  // Botón "Ocultar" superior derecho
                  Material(
                    color: AppPalette.primary,
                    borderRadius: BorderRadius.circular(8.0),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8.0),
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10.0,
                          vertical: 6.0,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Ocultar',
                              style: AppTypography.button.copyWith(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Cuerpo de Filtros ────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Sección TIPO (CATEGORÍA)
                    _buildSectionHeader('TIPO', textSecondaryColor),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: [
                        _buildChoiceChip(
                          context: context,
                          label: 'Todos',
                          isSelected: idCategoria == null,
                          onSelected: (selected) {
                            if (selected) onCategoriaChanged(null);
                          },
                        ),
                        _buildChoiceChip(
                          context: context,
                          label: 'Motores',
                          isSelected: idCategoria == 1,
                          onSelected: (selected) {
                            onCategoriaChanged(selected ? 1 : null);
                          },
                        ),
                        _buildChoiceChip(
                          context: context,
                          label: 'Cajas',
                          isSelected: idCategoria == 2,
                          onSelected: (selected) {
                            onCategoriaChanged(selected ? 2 : null);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 2. Sección SUCURSAL
                    _buildSectionHeader('SUCURSAL', textSecondaryColor),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: [
                        _buildChoiceChip(
                          context: context,
                          label: 'Todas',
                          isSelected: idSucursal == null,
                          onSelected: (selected) {
                            if (selected) onSucursalChanged(null);
                          },
                        ),
                        _buildChoiceChip(
                          context: context,
                          label: 'Viña del Mar',
                          isSelected: idSucursal == 1,
                          onSelected: (selected) {
                            onSucursalChanged(selected ? 1 : null);
                          },
                        ),
                        _buildChoiceChip(
                          context: context,
                          label: 'Limache',
                          isSelected: idSucursal == 2,
                          onSelected: (selected) {
                            onSucursalChanged(selected ? 2 : null);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // 3. Sección MARCA DEL VEHÍCULO
                    _buildSectionHeader('MARCA DEL VEHÍCULO', textSecondaryColor),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      initialValue: (marca != null && listaMarcas.contains(marca)) ? marca : null,
                      isExpanded: true,
                      dropdownColor: AppPalette.surface,
                      style: AppTypography.body.copyWith(color: textPrimaryColor),
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color: textSecondaryColor,
                      ),
                      decoration: _buildInputDecoration(
                        context: context,
                        hintText: listaMarcas.isEmpty ? 'Sin marcas en inventario' : 'Seleccionar marca',
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            'Todas',
                            style: AppTypography.body.copyWith(color: textPrimaryColor),
                          ),
                        ),
                        ...listaMarcas.map(
                          (m) => DropdownMenuItem<String?>(
                            value: m,
                            child: Text(
                              m,
                              style: AppTypography.body.copyWith(color: textPrimaryColor),
                            ),
                          ),
                        ),
                      ],
                      onChanged: onMarcaChanged,
                    ),
                    const SizedBox(height: 24),

                    // 4. Sección AÑO DEL MOTOR / VEHÍCULO
                    _buildSectionHeader('AÑO DEL MOTOR', textSecondaryColor),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int?>(
                      initialValue: (anio != null && listaAnios.contains(anio)) ? anio : null,
                      isExpanded: true,
                      dropdownColor: AppPalette.surface,
                      style: AppTypography.body.copyWith(color: textPrimaryColor),
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color: textSecondaryColor,
                      ),
                      decoration: _buildInputDecoration(
                        context: context,
                        hintText: listaAnios.isEmpty ? 'Sin años disponibles' : 'Seleccionar año',
                      ),
                      items: [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text(
                            'Todos',
                            style: AppTypography.body.copyWith(color: textPrimaryColor),
                          ),
                        ),
                        ...listaAnios.map(
                          (a) => DropdownMenuItem<int?>(
                            value: a,
                            child: Text(
                              a.toString(),
                              style: AppTypography.body.copyWith(color: textPrimaryColor),
                            ),
                          ),
                        ),
                      ],
                      onChanged: onAnioChanged,
                    ),
                    const SizedBox(height: 24),

                    // 5. Sección CILINDRADA
                    _buildSectionHeader('CILINDRADA', textSecondaryColor),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      initialValue: (cilindrada != null && listaCilindradas.contains(cilindrada)) ? cilindrada : null,
                      isExpanded: true,
                      dropdownColor: AppPalette.surface,
                      style: AppTypography.body.copyWith(color: textPrimaryColor),
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color: textSecondaryColor,
                      ),
                      decoration: _buildInputDecoration(
                        context: context,
                        hintText: listaCilindradas.isEmpty ? 'Sin cilindradas disponibles' : 'Seleccionar cilindrada',
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            'Todas',
                            style: AppTypography.body.copyWith(color: textPrimaryColor),
                          ),
                        ),
                        ...listaCilindradas.map(
                          (c) => DropdownMenuItem<String?>(
                            value: c,
                            child: Text(
                              '$c L',
                              style: AppTypography.body.copyWith(color: textPrimaryColor),
                            ),
                          ),
                        ),
                      ],
                      onChanged: onCilindradaChanged,
                    ),
                    const SizedBox(height: 24),

                    // 6. Sección TIPO DE TRANSMISIÓN
                    _buildSectionHeader('TIPO DE TRANSMISIÓN', textSecondaryColor),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: [
                        _buildChoiceChip(
                          context: context,
                          label: 'Todas',
                          isSelected: transmision == null,
                          onSelected: (selected) {
                            if (selected) onTransmisionChanged(null);
                          },
                        ),
                        ...listaTransmisiones.map((t) {
                          final isSelected = transmision != null &&
                              (transmision!.toLowerCase() == t.toLowerCase() ||
                               (t.toLowerCase() == 'mecánica' && (transmision!.toLowerCase() == 'manual' || transmision!.toLowerCase() == 'mecanica')));
                          return _buildChoiceChip(
                            context: context,
                            label: t,
                            isSelected: isSelected,
                            onSelected: (selected) {
                              onTransmisionChanged(selected ? t : null);
                            },
                          );
                        }),
                      ],
                    ),
                    if (onCombustibleChanged != null) ...[
                      const SizedBox(height: 24),
                      _buildSectionHeader('TIPO DE COMBUSTIBLE', textSecondaryColor),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: OpcionesCombustible.listaFiltros.map((opcion) {
                          final isTodas = opcion == 'Todos';
                          final isSelected = isTodas
                              ? (combustible == null || combustible!.isEmpty)
                              : combustible == opcion;
                          return _buildChoiceChip(
                            context: context,
                            label: opcion,
                            isSelected: isSelected,
                            onSelected: (selected) {
                              if (isTodas) {
                                if (selected) onCombustibleChanged!(null);
                              } else {
                                onCombustibleChanged!(selected ? opcion : null);
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    if (onTraccionChanged != null) ...[
                      const SizedBox(height: 24),
                      _buildSectionHeader('TIPO DE TRACCIÓN', textSecondaryColor),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: OpcionesTraccion.listaFiltros.map((opcion) {
                          final isTodas = opcion == 'Todas';
                          final isSelected = isTodas
                              ? (traccion == null || traccion!.isEmpty)
                              : traccion == opcion;
                          return _buildChoiceChip(
                            context: context,
                            label: opcion,
                            isSelected: isSelected,
                            onSelected: (selected) {
                              if (isTodas) {
                                if (selected) onTraccionChanged!(null);
                              } else {
                                onTraccionChanged!(selected ? opcion : null);
                              }
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Botón Inferior: Limpiar Filtros ──────────────────────────────
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: dividerColor,
                    width: 1.5,
                  ),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: onLimpiarFiltros,
                  icon: const Icon(
                    Icons.close,
                    color: AppPalette.error,
                    size: 20,
                  ),
                  label: Text(
                    'Limpiar filtros',
                    style: AppTypography.button.copyWith(
                      color: AppPalette.error,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14.0),
                    backgroundColor: surfaceColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                      side: BorderSide(color: AppPalette.error.withValues(alpha: 0.5)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color textColor) {
    return Text(
      title,
      style: AppTypography.small.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.8,
        color: const Color(0xFFCBD5E1),
      ),
    );
  }

  Widget _buildChoiceChip({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required ValueChanged<bool> onSelected,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelected(!isSelected),
        borderRadius: BorderRadius.circular(8.0),
        splashColor: AppPalette.primary.withValues(alpha: 0.25),
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: isSelected ? AppPalette.primary : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(
              color: isSelected ? AppPalette.primary : Colors.transparent,
              width: 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required BuildContext context,
    required String hintText,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 14,
      ),
      filled: true,
      fillColor: AppPalette.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 13.0,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.0),
        borderSide: const BorderSide(
          color: Color(0xFF334155),
          width: 1.0,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.0),
        borderSide: const BorderSide(
          color: Color(0xFF334155),
          width: 1.0,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.0),
        borderSide: const BorderSide(
          color: AppPalette.primary,
          width: 1.5,
        ),
      ),
    );
  }
}
