// frontend/lib/features/gerencia/presentation/screens/backorders_gerencia_view.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/services/api_service.dart';
import '../../models/backorder_gerencia_models.dart';
import '../../services/gerencia_service.dart';
import '../widgets/kpi_card_widget.dart';
import '../../../../core/widgets/cresal_filter_dropdown.dart';

/// Visor Centralizado de Reservas y Backorders (HU-5.4).
/// Panel gerencial para la auditoría y monitoreo de compras por encargo en verde,
/// balances económicos (precio pactado, seña en caja, saldo) y trazabilidad
/// de repuestos físicos asignados (match con vehículos donantes).
class BackordersGerenciaView extends StatefulWidget {
  final int? idSucursalInicial;

  const BackordersGerenciaView({super.key, this.idSucursalInicial});

  @override
  State<BackordersGerenciaView> createState() => BackordersGerenciaViewState();
}

class BackordersGerenciaViewState extends State<BackordersGerenciaView> {
  late final TextEditingController _busquedaController;
  Timer? _debounceTimer;

  /// Permite a vistas contenedoras (como [DashboardGerenciaView]) solicitar una recarga explícita.
  Future<void> refrescar({
    int? idSucursal,
    bool actualizarSucursal = false,
    bool silent = false,
  }) async {
    if (actualizarSucursal) {
      _idSucursal = idSucursal;
    }
    if (silent) {
      await refrescarSilencioso();
      return;
    }
    await _cargarDatos();
  }

  /// Permite refrescar KPIs y lista de reservas en verde de forma silenciosa en segundo plano.
  Future<void> refrescarSilencioso({
    int? idSucursal,
    bool actualizarSucursal = false,
  }) async {
    if (!mounted) return;
    if (actualizarSucursal) {
      _idSucursal = idSucursal;
    }
    try {
      final futures = await Future.wait([
        GerenciaService.obtenerBackordersKpis(idSucursal: _idSucursal),
        GerenciaService.obtenerBackorders(
          idSucursal: _idSucursal,
          estado: _filtroEstado,
          busqueda: _busquedaController.text.trim(),
        ),
      ]);
      if (!mounted) return;
      final kpisData = futures[0] as BackordersKpisModel;
      final listData = futures[1] as PaginatedBackordersResponse;
      setState(() {
        _kpis = kpisData;
        _backorders = listData.items;
        _totalCount = listData.totalCount;
        _totalRecaudadoSenas = listData.totalRecaudadoSenas;
      });
      debugPrint('🌱 [GERENCIA-VENTAS_EN_VERDE] ✅ Sincronización silenciosa completada');
    } catch (e) {
      debugPrint('🌱 [GERENCIA-VENTAS_EN_VERDE] ⚠️ Error en refresco silencioso (ignorado): $e');
    }
  }

  int? _idSucursal;
  String _filtroEstado = 'todos';

  bool _isLoading = false;
  String? _errorMessage;
  String? _codigoError;
  String? _detalleTecnicoError;
  bool _mostrarDetalleTecnico = false;

  BackordersKpisModel _kpis = BackordersKpisModel.empty();
  List<BackorderItemModel> _backorders = [];
  int _totalCount = 0;
  int _totalRecaudadoSenas = 0;

  @override
  void initState() {
    super.initState();
    _idSucursal = widget.idSucursalInicial;
    _busquedaController = TextEditingController();
    _cargarDatos();
  }

  @override
  void didUpdateWidget(covariant BackordersGerenciaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.idSucursalInicial != widget.idSucursalInicial) {
      _idSucursal = widget.idSucursalInicial;
      _cargarDatos();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _busquedaController.dispose();
    super.dispose();
  }

  void _onBusquedaChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _cargarBackorders();
    });
  }

  void _limpiarFiltros() {
    _busquedaController.clear();
    setState(() {
      _filtroEstado = 'todos';
    });
    _cargarDatos();
  }

  int get _cantidadFiltrosActivos {
    int count = 0;
    if (_busquedaController.text.trim().isNotEmpty) count++;
    if (_filtroEstado != 'todos') count++;
    return count;
  }

  Future<void> _cargarDatos() async {
    debugPrint('🌱 [GERENCIA-VENTAS_EN_VERDE] 🔄 Solicitando KPIs y reservas en verde (Sucursal: ${_idSucursal ?? "Todas"}, Filtro: $_filtroEstado)...');
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _codigoError = null;
      _detalleTecnicoError = null;
      _mostrarDetalleTecnico = false;
    });

    try {
      final futures = await Future.wait([
        GerenciaService.obtenerBackordersKpis(idSucursal: _idSucursal),
        GerenciaService.obtenerBackorders(
          idSucursal: _idSucursal,
          estado: _filtroEstado,
          busqueda: _busquedaController.text.trim(),
        ),
      ]);

      if (!mounted) return;

      final kpisData = futures[0] as BackordersKpisModel;
      final listData = futures[1] as PaginatedBackordersResponse;

      debugPrint('🌱 [GERENCIA-VENTAS_EN_VERDE] ✅ OK 200 - Ventas en verde cargadas exitosamente:');
      debugPrint('   • Total reservas: ${listData.totalCount} (Activas: ${kpisData.totalActivos}, Listas para liquidar: ${kpisData.listosParaLiquidar})');
      debugPrint('   • Señas recaudadas en caja: \$${listData.totalRecaudadoSenas} | Capital retenido: \$${kpisData.capitalRetenido}');

      setState(() {
        _kpis = kpisData;
        _backorders = listData.items;
        _totalCount = listData.totalCount;
        _totalRecaudadoSenas = listData.totalRecaudadoSenas;
        _isLoading = false;
      });
    } on CustomApiException catch (e) {
      if (!mounted) return;
      debugPrint('🌱 [GERENCIA-VENTAS_EN_VERDE] ❌ Error API al cargar datos: ${e.messageUser} (Código: ${e.diagnosticCode})');
      setState(() {
        _errorMessage = e.messageUser;
        _codigoError = e.diagnosticCode;
        _detalleTecnicoError = e.messageDev;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('🌱 [GERENCIA-VENTAS_EN_VERDE] ❌ Error al cargar datos: $e');
      setState(() {
        _errorMessage = ApiService.limpiarMensajeExcepcion(e);
        _codigoError = 'GERENCIA_BACKORDERS_ERROR';
        _detalleTecnicoError = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _cargarBackorders() async {
    debugPrint('🌱 [GERENCIA-VENTAS_EN_VERDE] 🔄 Filtrando reservas (Estado: $_filtroEstado, Búsqueda: "${_busquedaController.text.trim()}")...');
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _codigoError = null;
      _detalleTecnicoError = null;
      _mostrarDetalleTecnico = false;
    });

    try {
      final listData = await GerenciaService.obtenerBackorders(
        idSucursal: _idSucursal,
        estado: _filtroEstado,
        busqueda: _busquedaController.text.trim(),
      );

      if (!mounted) return;

      debugPrint('🌱 [GERENCIA-VENTAS_EN_VERDE] ✅ OK 200 - Filtrado completado: ${listData.items.length} reservas visibles');

      setState(() {
        _backorders = listData.items;
        _totalCount = listData.totalCount;
        _totalRecaudadoSenas = listData.totalRecaudadoSenas;
        _isLoading = false;
      });
    } on CustomApiException catch (e) {
      if (!mounted) return;
      debugPrint('🌱 [GERENCIA-VENTAS_EN_VERDE] ❌ Error API al filtrar: ${e.messageUser} (Código: ${e.diagnosticCode})');
      setState(() {
        _errorMessage = e.messageUser;
        _codigoError = e.diagnosticCode;
        _detalleTecnicoError = e.messageDev;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('🌱 [GERENCIA-VENTAS_EN_VERDE] ❌ Error al filtrar: $e');
      setState(() {
        _errorMessage = ApiService.limpiarMensajeExcepcion(e);
        _codigoError = 'GERENCIA_BACKORDERS_ERROR';
        _detalleTecnicoError = e.toString();
        _isLoading = false;
      });
    }
  }

  String _formatoCLP(int monto) {
    final str = monto.abs().toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
    return monto < 0 ? '-\$ $str' : '\$ $str';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Cabecera Ejecutiva: 3 Tarjetas KPI
          _buildKpisHeader(),
          const SizedBox(height: 20),

          // 2. Barra Superior de Filtros Backorders
          _buildBarraFiltros(),
          const SizedBox(height: 20),

          // 3. Error Banner si ocurre
          if (_errorMessage != null) ...[
            _buildErrorBanner(),
            const SizedBox(height: 20),
          ],

          // 4. Tabla Densa o Estado de Carga
          if (_isLoading && _backorders.isEmpty)
            _buildLoadingIndicator()
          else
            _buildTablaBackorders(),
        ],
      ),
    );
  }

  // =========================================================================
  // 1. TARJETAS KPI
  // =========================================================================
  Widget _buildKpisHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 900;
        final cardWidth = isNarrow
            ? constraints.maxWidth
            : (constraints.maxWidth - 32) / 3;

        final cards = [
          SizedBox(
            width: cardWidth,
            child: KpiCardWidget(
              titulo: 'TOTAL VENTAS EN VERDE ACTIVAS',
              valor: _kpis.totalActivos.toString(),
              subtitulo: 'Encargos vigentes en espera de pieza',
              badgeTexto: 'Activas',
              badgeColor: AppPalette.primary,
              icono: Icons.bookmark_added_rounded,
            ),
          ),
          SizedBox(
            width: cardWidth,
            child: KpiCardWidget(
              titulo: 'CAPITAL RETENIDO EN ABONOS',
              valor: _formatoCLP(_kpis.capitalRetenido),
              subtitulo: 'Señas recaudadas en caja (reserva)',
              badgeTexto: 'En Caja',
              badgeColor: AppPalette.success,
              icono: Icons.payments_rounded,
            ),
          ),
          SizedBox(
            width: cardWidth,
            child: KpiCardWidget(
              titulo: 'LISTOS PARA LIQUIDAR',
              valor: _kpis.listosParaLiquidar.toString(),
              subtitulo: 'Repuestos físicos ya asignados',
              badgeTexto: 'Match Confirmado',
              badgeColor: const Color(0xFF047857),
              icono: Icons.link_rounded,
            ),
          ),
        ];

        if (isNarrow) {
          return Column(
            children: [
              cards[0],
              const SizedBox(height: 14),
              cards[1],
              const SizedBox(height: 14),
              cards[2],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 16),
            Expanded(child: cards[1]),
            const SizedBox(width: 16),
            Expanded(child: cards[2]),
          ],
        );
      },
    );
  }

  // =========================================================================
  // 2. BARRA SUPERIOR DE FILTROS
  // =========================================================================
  Widget _buildBarraFiltros() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.start,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Campo de búsqueda predictiva
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280, maxWidth: 380),
            child: TextField(
              controller: _busquedaController,
              onChanged: (val) {
                setState(() {});
                _onBusquedaChanged(val);
              },
              style: AppTypography.small.copyWith(
                fontSize: 13,
                color: AppPalette.textPrimaryLight,
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar por Marca, Modelo, Cliente o Vendedor...',
                hintStyle: AppTypography.small.copyWith(
                  color: AppPalette.textSecondaryLight.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: AppPalette.textSecondaryLight,
                ),
                suffixIcon: _busquedaController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        color: AppPalette.textSecondaryLight,
                        onPressed: () {
                          _busquedaController.clear();
                          _cargarBackorders();
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

          // Selector de Estado de Ciclo de Reserva (MenuAnchor - 1 solo clic)
          CresalFilterDropdown<String>(
            height: 38,
            value: _filtroEstado,
            backgroundColor: Colors.white,
            borderColor: AppPalette.borderLight,
            isExpanded: false,
            items: const [
              CresalFilterDropdownItem(value: 'todos', label: 'Estado: Todos'),
              CresalFilterDropdownItem(value: 'Pendiente', label: 'Pendiente (Sin Abono)'),
              CresalFilterDropdownItem(value: 'Confirmada', label: 'Confirmada (Abonada en Caja / Activa)'),
              CresalFilterDropdownItem(value: 'Completada', label: 'Completada (Pieza Vinculada)'),
              CresalFilterDropdownItem(value: 'Anulada', label: 'Anulada (Cancelada)'),
            ],
            onChanged: (val) {
              if (val != _filtroEstado) {
                setState(() => _filtroEstado = val);
                _cargarBackorders();
              }
            },
          ),

          // Botón Limpiar Filtros
          _buildBotonLimpiar(),
        ],
      ),
    );
  }

  Widget _buildBotonLimpiar() {
    final count = _cantidadFiltrosActivos;
    final hayFiltros = count > 0;

    return OutlinedButton.icon(
      onPressed: _limpiarFiltros,
      icon: Icon(
        Icons.filter_alt_off_rounded,
        size: 14,
        color: hayFiltros ? AppPalette.tertiary : const Color(0xFF64748B),
      ),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Limpiar',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: hayFiltros ? AppPalette.tertiary : const Color(0xFF64748B),
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
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: hayFiltros ? AppPalette.tertiary : const Color(0xFF64748B),
        backgroundColor: hayFiltros
            ? AppPalette.tertiary.withValues(alpha: 0.1)
            : Colors.white,
        side: BorderSide(
          color: hayFiltros ? AppPalette.tertiary : AppPalette.borderLight,
          width: hayFiltros ? 1.5 : 1.0,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  // =========================================================================
  // 3. TABLA DENSA DE BACKORDERS
  // =========================================================================
  Widget _buildTablaBackorders() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_backorders.isEmpty)
            _buildEmptyState()
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final tableWidth = math.max(constraints.maxWidth, 1150.0);
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Encabezados de Columna ocupando el 100% del ancho con flex
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC), // Slate 50
                            border: Border(
                              bottom: BorderSide(
                                color: Color(0xFFE2E8F0),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              _buildHeaderCell('FOLIO / FECHA', flex: 11),
                              _buildHeaderCell('PIEZA SOLICITADA / MOTOR', flex: 22),
                              _buildHeaderCell('CLIENTE', flex: 14),
                              _buildHeaderCell('VENDEDOR', flex: 13),
                              _buildHeaderCell('PRECIO ACORDADO', flex: 12, alignment: Alignment.centerRight),
                              _buildHeaderCell('ABONO EN CAJA', flex: 11, alignment: Alignment.centerRight),
                              _buildHeaderCell('SALDO PENDIENTE', flex: 11, alignment: Alignment.centerRight),
                              _buildHeaderCell('ESTADO RESERVA', flex: 12, alignment: Alignment.center),
                              _buildHeaderCell('MATCH / ASIGNACIÓN', flex: 13, alignment: Alignment.center),
                            ],
                          ),
                        ),

                        // Filas de Datos con divisores y alineación proporcional
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _backorders.length,
                          separatorBuilder: (context, index) => const Divider(
                            height: 1,
                            thickness: 1,
                            color: Color(0xFFF1F5F9),
                          ),
                          itemBuilder: (context, index) {
                            final b = _backorders[index];
                            return _buildRowItem(b);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          // Footer de la tabla
          _buildTablaFooter(),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String label, {required int flex, Alignment alignment = Alignment.centerLeft}) {
    return Expanded(
      flex: flex,
      child: Align(
        alignment: alignment,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Color(0xFF475569),
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildRowItem(BackorderItemModel b) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          // 1. Folio / Fecha
          Expanded(
            flex: 11,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  b.folio,
                  style: const TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  b.fechaCreacion,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),

          // 2. Ficha Técnica Requerida
          Expanded(
            flex: 22,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCategoriaBadge(
                        b.idCategoriaRequerida,
                        b.categoriaNombre,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${b.marcaRequerida} ${b.modeloRequerido} (${b.anioRequerido?.toString() ?? 'S/A'})',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Comb: ${b.combustibleRequerido ?? 'N/A'} | Transm: ${b.transmisionRequerida ?? 'N/A'}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // 3. Cliente (CRM)
          Expanded(
            flex: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  b.clienteNombre,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (b.clienteTelefono != null && b.clienteTelefono!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    b.clienteTelefono!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // 4. Vendedor
          Expanded(
            flex: 13,
            child: Text(
              b.vendedorNombre,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // 5. Precio Acordado
          Expanded(
            flex: 12,
            child: Align(
              alignment: Alignment.centerRight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _formatoCLP(b.precioAcordado),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  if (b.descuento > 0)
                    Text(
                      '- ${_formatoCLP(b.descuento)}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFDC2626),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 6. Abono en Caja
          Expanded(
            flex: 11,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                _formatoCLP(b.montoAbonado),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF047857), // Emerald 700
                ),
              ),
            ),
          ),

          // 7. Saldo Pendiente
          Expanded(
            flex: 11,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                _formatoCLP(b.saldoPendiente),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: b.saldoPendiente > 0 ? const Color(0xFFB45309) : const Color(0xFF94A3B8),
                ),
              ),
            ),
          ),

          // 8. Estado Reserva
          Expanded(
            flex: 12,
            child: Align(
              alignment: Alignment.center,
              child: _buildEstadoBadge(b.estadoReserva),
            ),
          ),

          // 9. Match / Asignación
          Expanded(
            flex: 13,
            child: Align(
              alignment: Alignment.center,
              child: _buildMatchBadge(b.idActivoAsignado, b.activoAsignadoSku),
            ),
          ),
        ],
      ),
    );
  }

  // Badge para la categoría requerida (Motor vs Caja de Cambios)
  Widget _buildCategoriaBadge(int idCategoria, String nombre) {
    final isMotor = idCategoria == 1;
    final bgColor = isMotor ? const Color(0xFFE0F2FE) : const Color(0xFFFEF3C7);
    final textColor = isMotor
        ? const Color(0xFF0369A1)
        : const Color(0xFFB45309);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isMotor ? 'Motor' : 'Caja de Cambios',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  // Badge de Estado del ciclo de reserva
  Widget _buildEstadoBadge(String estado) {
    Color bg;
    Color text;
    Color border;

    switch (estado.toLowerCase()) {
      case 'pendiente':
        bg = const Color(0xFFFEF3C7); // Amber 100
        text = const Color(0xFFB45309); // Amber 700
        border = const Color(0xFFFDE68A); // Amber 200
        break;
      case 'confirmada':
        bg = const Color(0xFFD1FAE5); // Emerald 100
        text = const Color(0xFF065F46); // Emerald 800
        border = const Color(0xFFA7F3D0); // Emerald 200
        break;
      case 'completada':
        bg = const Color(0xFFE0F2FE); // Sky 100
        text = const Color(0xFF0369A1); // Sky 700
        border = const Color(0xFFBAE6FD); // Sky 200
        break;
      case 'anulada':
      default:
        bg = const Color(0xFFF1F5F9); // Slate 100
        text = const Color(0xFF64748B); // Slate 500
        border = const Color(0xFFE2E8F0); // Slate 200
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        estado,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: text,
        ),
      ),
    );
  }

  // Badge de Match Físico
  Widget _buildMatchBadge(String? idActivoAsignado, String? sku) {
    if (idActivoAsignado != null && idActivoAsignado.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFD1FAE5), // Emerald 100
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_rounded, size: 14, color: Color(0xFF065F46)),
            const SizedBox(width: 4),
            Text(
              sku ?? idActivoAsignado.substring(0, 8),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF065F46),
              ),
            ),
          ],
        ),
      );
    }

    return const Text(
      'En búsqueda',
      style: TextStyle(
        fontSize: 11,
        fontStyle: FontStyle.italic,
        fontWeight: FontWeight.w500,
        color: Color(0xFF94A3B8), // Slate 400
      ),
    );
  }

  // Footer con conteo y montos consolidados
  Widget _buildTablaFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC), // Slate 50
        border: Border(top: BorderSide(color: AppPalette.borderLight)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
              children: [
                const TextSpan(text: 'Total encargos registrados: '),
                TextSpan(
                  text: '$_totalCount',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
              children: [
                const TextSpan(text: 'Total Recaudado en Señas: '),
                TextSpan(
                  text: _formatoCLP(_totalRecaudadoSenas),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF047857), // Emerald 700
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Empty State
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.bookmark_border_rounded,
              size: 48,
              color: const Color(0xFF94A3B8).withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            const Text(
              'No hay reservas que coincidan',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Prueba cambiando el filtro de estado o limpiando el buscador.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }

  // Loading Indicator
  Widget _buildLoadingIndicator() {
    return const Padding(
      padding: EdgeInsets.all(48.0),
      child: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
    );
  }

  // Error Banner
  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppPalette.error,
                size: 20,
              ),
              const SizedBox(width: 10),
              if (_codigoError != null && _codigoError!.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppPalette.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _codigoError!,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppPalette.error,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  _errorMessage ?? 'Ocurrió un error al consultar los datos.',
                  style: const TextStyle(fontSize: 12, color: AppPalette.error),
                ),
              ),
              TextButton(
                onPressed: _cargarDatos,
                child: const Text(
                  'Reintentar',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (_detalleTecnicoError != null &&
              _detalleTecnicoError!.trim().isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 4),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _mostrarDetalleTecnico = !_mostrarDetalleTecnico;
                  });
                },
                child: Text(
                  _mostrarDetalleTecnico
                      ? 'Ocultar detalle técnico ▲'
                      : 'Ver detalle técnico ▼',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppPalette.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
            if (_mostrarDetalleTecnico) ...[
              const SizedBox(height: 6),
              Container(
                margin: const EdgeInsets.only(left: 30),
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: SelectableText(
                  _detalleTecnicoError!,
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
