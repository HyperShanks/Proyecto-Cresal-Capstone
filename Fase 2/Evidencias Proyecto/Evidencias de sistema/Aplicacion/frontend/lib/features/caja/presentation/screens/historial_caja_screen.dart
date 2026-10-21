import 'package:flutter/material.dart';
import '../../../../core/routes/route_observer.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../auth/services/auth_service.dart';
import '../../services/caja_service.dart';
import '../providers/historial_caja_provider.dart';
import '../widgets/historial_metricas_panel.dart';
import '../widgets/historial_tabla_view.dart';
import '../widgets/detalle_auditoria_dialog.dart';
import '../widgets/filtro_rango_fechas_dialog.dart';
import '../../../../core/widgets/cresal_filter_dropdown.dart';

/// Pantalla principal para el Historial de Órdenes y Auditoría de Caja con Filtros (SPEC-HU-4.5 / CRES-217).
/// Diseño responsivo optimizado para pantallas POS, tablets y monitores de escritorio.
class HistorialCajaScreen extends StatefulWidget {
  final HistorialCajaProvider? provider;
  final int? sucursalId;

  const HistorialCajaScreen({super.key, this.provider, this.sucursalId});

  @override
  State<HistorialCajaScreen> createState() => HistorialCajaScreenState();
}

class HistorialCajaScreenState extends State<HistorialCajaScreen>
    with RouteAware {
  late final HistorialCajaProvider _provider;
  bool _providerInterno = false;
  bool _isModalAbierto = false;
  bool get isModalAbierto => _isModalAbierto;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();

    if (widget.provider != null) {
      _provider = widget.provider!;
      _providerInterno = false;
      _searchController.text = _provider.state.busqueda;
    } else {
      final sucId = widget.sucursalId ?? 1;
      _provider = HistorialCajaProvider(
        cajaService: CajaService(),
        sucursalId: sucId,
        autoCargar: false,
      );
      _providerInterno = true;
      _initAsync();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    super.didPopNext();
    // SPEC-HU-TAREA-21: Los modales de auditoría y filtros son de solo lectura,
    // no mutan el estado y no deben disparar recargas destructivas ni silenciosas al cerrarse.
  }

  /// Método público para forzar recarga (Auto-Refresh SPEC-HU-TAREA-20)
  void refrescar() {
    _provider.cargarHistorial(pagina: 1);
  }

  /// Recarga silenciosa en segundo plano manteniendo la página y filtros activos
  void refrescarSilencioso() {
    _provider.cargarHistorialSilencioso();
  }

  Future<void> _initAsync() async {
    final sucursalId = await AuthService.getSucursalId();
    if (!mounted) return;
    if (sucursalId != null && sucursalId != _provider.sucursalId) {
      // Re-instanciar con la sucursal del token si es necesario
    }
    _provider.cargarHistorial();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _searchController.dispose();
    if (_providerInterno) {
      _provider.dispose();
    }
    super.dispose();
  }

  Future<void> _abrirDialogoRangoFechas() async {
    _isModalAbierto = true;
    try {
      final res = await FiltroRangoFechasDialog.show(
        context,
        fechaDesde: _provider.state.fechaDesde,
        fechaHasta: _provider.state.fechaHasta,
      );

      if (!mounted || res == null) return;
      _provider.aplicarRangoFechas(res['desde']!, res['hasta']!);
    } finally {
      _isModalAbierto = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _provider,
      builder: (context, _) {
        final state = _provider.state;

        return LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 768;

            return Container(
              color: AppPalette.backgroundLight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 1. CABECERA CON TÍTULO, SUBTÍTULOS Y SELECTOR DE PERÍODOS ──
                  _buildCabecera(state),

                  // ── 2. ÁREA DE CONTENIDO (Métricas, Filtros y Tabla de Órdenes) ──
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isNarrow ? 12 : 24,
                        vertical: isNarrow ? 12 : 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── 2.1 BARRA DE BÚSQUEDA Y FILTROS DESPLEGABLES ──
                          _buildBarraBusquedaFiltros(state),
                          const SizedBox(height: 16),

                          // ── 2.2 PANEL DE MÉTRICAS DE ARQUEO / CUADRE ──
                          if (state.data != null)
                            HistorialMetricasPanel(
                              resumen: state.data!.resumenCuadre,
                            ),
                          const SizedBox(height: 16),

                          // ── 2.3 CONTENIDO PRINCIPAL (TABLA / LOADING / ERROR / ZERO STATE) ──
                          Expanded(child: _buildCuerpoPrincipal(state)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCabecera(HistorialCajaState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 860;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: const BoxDecoration(
            color: AppPalette.surfaceLight,
            border: Border(bottom: BorderSide(color: AppPalette.borderLight)),
          ),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTituloCabecera(),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildBarraPeriodos(state),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: _buildTituloCabecera()),
                    const SizedBox(width: 16),
                    _buildBarraPeriodos(state),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildTituloCabecera() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AUDITORÍA Y CIERRE',
          style: AppTypography.small.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: AppPalette.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Historial de Órdenes',
          style: AppTypography.title.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppPalette.textPrimaryLight,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Control de cobros, arqueo de turno y trazabilidad de ventas',
          style: AppTypography.small.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: AppPalette.textSecondaryLight,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildBarraPeriodos(HistorialCajaState state) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9), // Slate-100 capsule
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPeriodoPill(
            label: 'Hoy',
            isSelected: state.periodo == PeriodoHistorial.hoy,
            onTap: () => _provider.cambiarPeriodo(PeriodoHistorial.hoy),
          ),
          const SizedBox(width: 4),
          _buildPeriodoPill(
            label: 'Esta Semana',
            isSelected: state.periodo == PeriodoHistorial.estaSemana,
            onTap: () => _provider.cambiarPeriodo(PeriodoHistorial.estaSemana),
          ),
          const SizedBox(width: 4),
          _buildPeriodoPill(
            label: 'Este Mes',
            isSelected: state.periodo == PeriodoHistorial.esteMes,
            onTap: () => _provider.cambiarPeriodo(PeriodoHistorial.esteMes),
          ),
          const SizedBox(width: 4),
          _buildPeriodoPill(
            label:
                state.periodo == PeriodoHistorial.rango &&
                    state.fechaDesde != null &&
                    state.fechaHasta != null
                ? '${state.fechaDesde} a ${state.fechaHasta}'
                : 'Rango',
            isSelected: state.periodo == PeriodoHistorial.rango,
            icon: Icons.calendar_today_outlined,
            onTap: _abrirDialogoRangoFechas,
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodoPill({
    required String label,
    required bool isSelected,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected ? Border.all(color: AppPalette.borderLight) : null,
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? AppPalette.primary
                    : AppPalette.textSecondaryLight,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTypography.button.copyWith(
                fontFamily: AppTypography.fontFamily,
                color: isSelected
                    ? AppPalette.primary
                    : AppPalette.textSecondaryLight,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarraBusquedaFiltros(HistorialCajaState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 950;

        if (isCompact) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppPalette.neutral.withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: _buildCampoBusqueda()),
                    const SizedBox(width: 8),
                    _buildBotonLimpiarFiltros(state),
                    const SizedBox(width: 8),
                    _buildBotonRefresh(),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: CresalFilterDropdown<String>(
                        value: state.estadoOrden,
                        items: const [
                          CresalFilterDropdownItem(value: 'TODOS', label: 'Todos los Estados'),
                          CresalFilterDropdownItem(value: 'Pagada', label: 'Pagada'),
                          CresalFilterDropdownItem(value: 'Completada', label: 'Completada'),
                          CresalFilterDropdownItem(value: 'Reservada', label: 'Reservada (Abonada)'),
                          CresalFilterDropdownItem(value: 'Anulada', label: 'Anulada'),
                        ],
                        onChanged: (val) => _provider.cambiarFiltroEstado(val),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CresalFilterDropdown<String>(
                        value: state.metodoPago,
                        items: const [
                          CresalFilterDropdownItem(value: 'TODOS', label: 'Todos los Métodos'),
                          CresalFilterDropdownItem(value: 'Efectivo', label: 'Efectivo'),
                          CresalFilterDropdownItem(value: 'Débito', label: 'Débito'),
                          CresalFilterDropdownItem(value: 'Crédito', label: 'Crédito'),
                          CresalFilterDropdownItem(value: 'Transferencia', label: 'Transferencia'),
                          CresalFilterDropdownItem(value: 'Cheque', label: 'Cheque'),
                        ],
                        onChanged: (val) => _provider.cambiarFiltroMetodo(val),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppPalette.surfaceLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.neutral.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              // Buscador con debounce
              Expanded(
                flex: 5,
                child: _buildCampoBusqueda(),
              ),
              const SizedBox(width: 12),

              // Filtro de Estado
              Expanded(
                flex: 3,
                child: CresalFilterDropdown<String>(
                  value: state.estadoOrden,
                  items: const [
                    CresalFilterDropdownItem(value: 'TODOS', label: 'Todos los Estados'),
                    CresalFilterDropdownItem(value: 'Pagada', label: 'Pagada'),
                    CresalFilterDropdownItem(value: 'Completada', label: 'Completada'),
                    CresalFilterDropdownItem(value: 'Reservada', label: 'Reservada (Abonada)'),
                    CresalFilterDropdownItem(value: 'Anulada', label: 'Anulada'),
                  ],
                  onChanged: (val) => _provider.cambiarFiltroEstado(val),
                ),
              ),
              const SizedBox(width: 12),

              // Filtro de Método de Pago
              Expanded(
                flex: 3,
                child: CresalFilterDropdown<String>(
                  value: state.metodoPago,
                  items: const [
                    CresalFilterDropdownItem(value: 'TODOS', label: 'Todos los Métodos'),
                    CresalFilterDropdownItem(value: 'Efectivo', label: 'Efectivo'),
                    CresalFilterDropdownItem(value: 'Débito', label: 'Débito'),
                    CresalFilterDropdownItem(value: 'Crédito', label: 'Crédito'),
                    CresalFilterDropdownItem(value: 'Transferencia', label: 'Transferencia'),
                    CresalFilterDropdownItem(value: 'Cheque', label: 'Cheque'),
                  ],
                  onChanged: (val) => _provider.cambiarFiltroMetodo(val),
                ),
              ),
              const SizedBox(width: 10),

              // Botón Limpiar Filtros con indicador y contador
              _buildBotonLimpiarFiltros(state),
              const SizedBox(width: 10),

              // Botón de Sincronización / Refresco
              _buildBotonRefresh(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCampoBusqueda() {
    return TextField(
      controller: _searchController,
      style: AppTypography.body.copyWith(
        fontSize: 13,
        color: AppPalette.textPrimaryLight,
      ),
      onChanged: (val) => _provider.actualizarBusqueda(val),
      decoration: InputDecoration(
        hintText: 'Buscar por Folio (ORD-), RUT, Cliente, Vendedor...',
        hintStyle: AppTypography.small.copyWith(
          color: AppPalette.textSecondaryLight,
          fontSize: 15,
        ),
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 18,
          color: AppPalette.textSecondaryLight,
        ),
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: () {
                  _searchController.clear();
                  _provider.limpiarBusqueda();
                },
              )
            : null,
        filled: true,
        fillColor: AppPalette.backgroundLight,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
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
          borderSide: const BorderSide(
            color: AppPalette.primary,
            width: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildBotonRefresh() {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surfaceLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppPalette.neutral.withValues(alpha: 0.25),
        ),
      ),
      child: IconButton(
        icon: const Icon(
          Icons.refresh_rounded,
          size: 20,
          color: AppPalette.neutral,
        ),
        tooltip: 'Actualizar historial',
        onPressed: () => _provider.cargarHistorial(),
      ),
    );
  }

  Widget _buildBotonLimpiarFiltros(HistorialCajaState state) {
    final count = state.cantidadFiltrosActivos;
    final hayFiltros = count > 0;

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        backgroundColor: hayFiltros
            ? AppPalette.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        side: BorderSide(
          color: hayFiltros
              ? AppPalette.primary
              : AppPalette.neutral.withValues(alpha: 0.25),
          width: hayFiltros ? 1.5 : 1.0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      icon: Icon(
        Icons.filter_alt_off_rounded,
        size: 16,
        color: hayFiltros ? AppPalette.primary : AppPalette.textSecondaryLight,
      ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Limpiar',
            style: AppTypography.button.copyWith(
              color: hayFiltros ? AppPalette.primary : AppPalette.textSecondaryLight,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          if (hayFiltros) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppPalette.primary,
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
      onPressed: () {
        _searchController.clear();
        _provider.limpiarFiltros();
      },
    );
  }



  Widget _buildCuerpoPrincipal(HistorialCajaState state) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppPalette.primary),
      );
    }

    if (state.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 44,
                color: AppPalette.error,
              ),
              const SizedBox(height: 12),
              Text(
                state.errorMessage!,
                style: AppTypography.body.copyWith(color: AppPalette.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Reintentar'),
                onPressed: () => _provider.cargarHistorial(),
              ),
            ],
          ),
        ),
      );
    }

    if (state.data == null || state.data!.items.isEmpty) {
      return _buildZeroState(state);
    }

    return HistorialTablaView(
      items: state.data!.items,
      paginaActual: state.paginaActual,
      totalPaginas: state.data!.totalPaginas,
      onCambiarPagina: (pag) => _provider.cargarHistorial(pagina: pag),
      onVerDetalle: (orden) async {
        _isModalAbierto = true;
        try {
          await DetalleAuditoriaDialog.show(context, orden);
        } finally {
          _isModalAbierto = false;
        }
      },
    );
  }

  Widget _buildZeroState(HistorialCajaState state) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppPalette.surfaceLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.neutral.withValues(alpha: 0.18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_rounded,
              size: 52,
              color: AppPalette.neutral.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 14),
            Text(
              'No se encontraron órdenes en este período o filtro',
              style: AppTypography.title.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppPalette.textPrimaryLight,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pruebe seleccionando otro período contable o limpiando la búsqueda.',
              style: AppTypography.body.copyWith(
                color: AppPalette.textSecondaryLight,
              ),
            ),
            if (state.tieneFiltrosActivos) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.primary,
                  side: const BorderSide(color: AppPalette.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.clear_all_rounded, size: 16),
                label: const Text('Restablecer Filtros a Hoy'),
                onPressed: () {
                  _searchController.clear();
                  _provider.limpiarFiltros();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
