// lib/features/ventas/presentation/screens/catalogo_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/routes/route_observer.dart';
import '../../../../core/services/silent_polling_manager.dart';
import '../../../../core/widgets/glass_snackbar.dart';
import '../../../auth/services/auth_service.dart';
import '../../controllers/cart_controller.dart';
import '../../models/catalogo_model.dart';
import '../../services/catalogo_service.dart';
import '../../services/carrito_service.dart';
import '../../services/ordenes_sync_notifier.dart';
import '../widgets/catalogo_item_card.dart';
import '../widgets/filtros_drawer.dart';
import '../widgets/modal_backorder_form.dart';
import 'detalle_activo_screen.dart';

/// Pantalla Principal del Catálogo de Ventas con Radar de Stock (HU-3.2).
/// Incluye buscador con debounce de 500ms, panel lateral de filtros interactivo,
/// scroll infinito y FAB de Venta Rápida.
class CatalogoScreen extends StatefulWidget {
  final VoidCallback? onOpenMenuDrawer;
  final ValueChanged<bool>? onEndDrawerChanged;

  /// Notificador estático global para recargar el catálogo automáticamente
  /// tras tasación de precios u otros eventos externos.
  static final ValueNotifier<int> refreshNotifier = ValueNotifier<int>(0);

  const CatalogoScreen({
    super.key,
    this.onOpenMenuDrawer,
    this.onEndDrawerChanged,
  });

  @override
  State<CatalogoScreen> createState() => CatalogoScreenState();
}

class CatalogoScreenState extends State<CatalogoScreen> with RouteAware {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Timer? _debounceTimer;
  SilentPollingManager? _pollingManager;

  /// Método público para forzar la recarga del catálogo desde el backend
  /// (usado tras derivar órdenes a caja para sincronizar stock en tiempo real).
  Future<void> refrescarCatalogo() async {
    await _fetchCatalogo(resetPagination: true);
  }

  /// Recarga silenciosa en segundo plano sin reiniciar paginación ni resetear scroll.
  Future<void> refrescarCatalogoSilencioso() async {
    if (!mounted || _isLoadingInitial || _isLoadingMore) return;
    try {
      final currentQuery = _searchController.text.trim();
      final countToFetch = _items.isEmpty ? _limit : _items.length;

      final response = await CatalogoService.obtenerCatalogo(
        q: currentQuery.isNotEmpty ? currentQuery : null,
        idCategoria: _idCategoria,
        idSucursal: _idSucursalFiltro,
        marca: _marca,
        anio: _anio,
        cilindrada: _cilindrada,
        transmision: _transmision,
        limit: countToFetch,
        offset: 0,
      );

      if (!mounted) return;

      final itemsDisponibles = response.items
          .where(
            (i) =>
                i.estadoActivo?.toLowerCase() != 'vendido' &&
                i.estadoActivo?.toLowerCase() != 'de baja',
          )
          .toList();

      setState(() {
        _items = itemsDisponibles;
        _totalCount = response.totalCount;
      });
    } catch (_) {
      // Ignorar errores en ciclo silencioso
    }
  }

  void _onExternalRefresh() {
    if (mounted) {
      refrescarCatalogoSilencioso();
    }
  }

  // Estado del catálogo
  List<CatalogoItem> _items = [];
  int _totalCount = 0;
  int _offset = 0;
  static const int _limit = 20;

  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  String? _errorMessage;

  // ID de la sucursal del vendedor logueado (para radar)
  int? _vendedorSucursalId;

  // Filtros activos
  int? _idCategoria;
  int? _idSucursalFiltro;
  int? _anio;
  String? _marca;
  String? _cilindrada;
  String? _transmision;

  // Opciones dinámicas de filtros desde la BD (solo disponibles)
  List<String> _opcionesMarcas = [];
  List<int> _opcionesAnios = [];
  List<String> _opcionesCilindradas = [];
  List<String> _opcionesTransmisiones = [];

  bool get _tieneFiltrosActivos =>
      _idCategoria != null ||
      _idSucursalFiltro != null ||
      _anio != null ||
      _marca != null ||
      _cilindrada != null ||
      _transmision != null;

  @override
  void initState() {
    super.initState();
    CatalogoScreen.refreshNotifier.addListener(_onExternalRefresh);
    OrdenesSyncNotifier.instance.addListener(_onExternalRefresh);
    _scrollController.addListener(_onScroll);
    _cargarSucursalYCatalogo();
    _iniciarPollingSilencioso();
  }

  void _iniciarPollingSilencioso() {
    _pollingManager?.dispose();
    _pollingManager = SilentPollingManager(
      interval: const Duration(seconds: 30),
      debugLabel: 'CatalogoPolling',
      shouldPause: () => _isLoadingInitial || _isLoadingMore,
      onPoll: refrescarCatalogoSilencioso,
    )..start();
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
    refrescarCatalogoSilencioso();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _pollingManager?.dispose();
    CatalogoScreen.refreshNotifier.removeListener(_onExternalRefresh);
    OrdenesSyncNotifier.instance.removeListener(_onExternalRefresh);
    _debounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _cargarSucursalYCatalogo() async {
    final sucursalId = await AuthService.getSucursalId();
    if (mounted) {
      setState(() {
        _vendedorSucursalId = sucursalId;
      });
    }
    _cargarOpcionesFiltros();
    await _fetchCatalogo(resetPagination: true);
  }

  Future<void> _cargarOpcionesFiltros() async {
    try {
      final opts = await CatalogoService.obtenerOpcionesFiltrosCatalogo(
        idCategoria: _idCategoria,
        idSucursal: _idSucursalFiltro,
      );
      if (mounted) {
        setState(() {
          _opcionesMarcas = opts['marcas'] as List<String>? ?? [];
          _opcionesAnios = opts['anios'] as List<int>? ?? [];
          _opcionesCilindradas = opts['cilindradas'] as List<String>? ?? [];
          _opcionesTransmisiones = opts['transmisiones'] as List<String>? ?? [];
        });
      }
    } catch (_) {
      // Continuar con listas vacías en caso de error
    }
  }

  // ── Búsqueda en Tiempo Real (Debounce 250 ms) ──────────────────────────────

  void _onSearchChanged(String query) {
    setState(() {}); // Actualiza de inmediato el icono de limpiar / indicador
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _fetchCatalogo(resetPagination: true);
    });
  }

  void _onClearSearch() {
    _searchController.clear();
    setState(() {});
    _fetchCatalogo(resetPagination: true);
  }

  // ── Gestión de Filtros ───────────────────────────────────────────────────

  void _aplicarFiltros() {
    _fetchCatalogo(resetPagination: true);
  }

  void _limpiarFiltros() {
    setState(() {
      _idCategoria = null;
      _idSucursalFiltro = null;
      _anio = null;
      _marca = null;
      _cilindrada = null;
      _transmision = null;
    });
    _cargarOpcionesFiltros();
    _aplicarFiltros();
  }

  // ── Infinite Scrolling (80% del scroll) ───────────────────────────────────

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    if (maxScroll > 0 && currentScroll >= maxScroll * 0.8) {
      if (!_isLoadingMore &&
          !_isLoadingInitial &&
          _items.length < _totalCount) {
        _fetchCatalogo(resetPagination: false);
      }
    }
  }

  // ── Consulta al Servicio HTTP ─────────────────────────────────────────────

  Future<void> _fetchCatalogo({required bool resetPagination}) async {
    if (resetPagination) {
      setState(() {
        _isLoadingInitial = true;
        _errorMessage = null;
        _offset = 0;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final currentQuery = _searchController.text.trim();
      final targetOffset = resetPagination ? 0 : _offset + _limit;

      final response = await CatalogoService.obtenerCatalogo(
        q: currentQuery.isNotEmpty ? currentQuery : null,
        idCategoria: _idCategoria,
        idSucursal: _idSucursalFiltro,
        marca: _marca,
        anio: _anio,
        cilindrada: _cilindrada,
        transmision: _transmision,
        limit: _limit,
        offset: targetOffset,
      );

      if (!mounted) return;

      final itemsDisponibles = response.items
          .where(
            (i) =>
                i.estadoActivo?.toLowerCase() != 'vendido' &&
                i.estadoActivo?.toLowerCase() != 'de baja',
          )
          .toList();

      setState(() {
        if (resetPagination) {
          _items = itemsDisponibles;
          _offset = 0;
        } else {
          _items.addAll(itemsDisponibles);
          _offset = targetOffset;
        }
        _totalCount = response.totalCount;
        _isLoadingInitial = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.contains('Sesión expirada') || msg.contains('token inválido')) {
        return;
      }
      setState(() {
        _errorMessage = msg;
        _isLoadingInitial = false;
        _isLoadingMore = false;
      });
    }
  }

  // ── Interacciones de Usuario ──────────────────────────────────────────────

  void _showDetalleRepuesto(CatalogoItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => DetalleActivoScreen(
          item: item,
          vendedorSucursalId: _vendedorSucursalId,
        ),
      ),
    );
  }

  Future<void> _onAddToCart(CatalogoItem item) async {
    if (item.esReservado) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppPalette.surface,
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppPalette.error,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '¡Lo sentimos! Este repuesto acaba de ser reservado por otro vendedor hace un instante.',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    if (CartController.instance.estaEnCarrito(item.idActivo)) {
      GlassSnackbar.mostrar(
        context,
        mensaje: 'Este activo ya está en el carrito',
        icono: Icons.info_outline,
        colorIcono: AppPalette.secondary,
      );
      return;
    }

    if (CartController.instance.tieneVentaEnVerde) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'No se pueden combinar productos con una Venta en Verde. Las ventas en verde van solas en el pedido.',
          ),
        ),
      );
      return;
    }

    try {
      final reserva = await CarritoService.reservarActivo(
        item.idActivo,
        item.versionLock,
      );

      final updatedItem = item.copyWith(
        versionLock: reserva['version_lock'] as int? ?? (item.versionLock + 1),
      );

      // Agrega al CartController global inmediatamente para no perder el ítem aunque el widget se desmonte
      final agregado = CartController.instance.agregarInventariado(updatedItem);

      if (!mounted) return;

      GlassSnackbar.mostrar(
        context,
        mensaje: agregado
            ? '${item.tituloRepuesto} agregado al carrito'
            : 'Este activo ya está en el carrito',
        icono: agregado
            ? Icons.check_circle_outline_rounded
            : Icons.info_outline,
        colorIcono: agregado ? AppPalette.primary : AppPalette.secondary,
      );
    } on CarritoException catch (e) {
      if (!mounted) return;

      if (e.statusCode == 409 || e.errorCode == 'RESERVATION_COLLISION') {
        setState(() {
          final idx = _items.indexWhere((it) => it.idActivo == item.idActivo);
          if (idx != -1) {
            _items[idx] = _items[idx].copyWith(
              idEstado: 2,
              estadoActivo: 'Reservado',
            );
          }
        });
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppPalette.surface,
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppPalette.error,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  e.message,
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppPalette.surface,
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: AppTypography.small.copyWith(color: AppPalette.error),
          ),
        ),
      );
    }
  }

  // ── Construcción de la Vista ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      endDrawer: FiltrosDrawer(
        idCategoria: _idCategoria,
        idSucursal: _idSucursalFiltro,
        marca: _marca,
        anio: _anio,
        cilindrada: _cilindrada,
        transmision: _transmision,
        marcasDisponibles: _opcionesMarcas,
        aniosDisponibles: _opcionesAnios,
        cilindradasDisponibles: _opcionesCilindradas,
        transmisionesDisponibles: _opcionesTransmisiones,
        onCategoriaChanged: (val) {
          setState(() => _idCategoria = val);
          _cargarOpcionesFiltros();
          _aplicarFiltros();
        },
        onSucursalChanged: (val) {
          setState(() => _idSucursalFiltro = val);
          _cargarOpcionesFiltros();
          _aplicarFiltros();
        },
        onMarcaChanged: (val) {
          setState(() => _marca = val);
          _aplicarFiltros();
        },
        onAnioChanged: (val) {
          setState(() => _anio = val);
          _aplicarFiltros();
        },
        onCilindradaChanged: (val) {
          setState(() => _cilindrada = val);
          _aplicarFiltros();
        },
        onTransmisionChanged: (val) {
          setState(() => _transmision = val);
          _aplicarFiltros();
        },
        onLimpiarFiltros: () {
          _limpiarFiltros();
          Navigator.of(context).pop();
        },
      ),
      onEndDrawerChanged: widget.onEndDrawerChanged,
      appBar: AppBar(
        backgroundColor: AppPalette.background,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: AppPalette.textPrimary),
          onPressed: () {
            if (widget.onOpenMenuDrawer != null) {
              widget.onOpenMenuDrawer!();
            } else {
              Scaffold.of(context).openDrawer();
            }
          },
          tooltip: 'Menú principal',
        ),
        actions: [
          IconButton(
            key: const Key('btn_refrescar_catalogo_appbar'),
            icon: const Icon(Icons.refresh, color: AppPalette.textPrimary),
            tooltip: 'Actualizar catálogo',
            onPressed: () => _fetchCatalogo(resetPagination: true),
          ),
          const SizedBox(width: 8),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Catálogo de Repuestos', style: AppTypography.title),
            if (!_isLoadingInitial && _errorMessage == null)
              Text(
                '$_totalCount repuestos disponibles',
                style: AppTypography.small.copyWith(fontSize: 14),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Barra de Búsqueda en Tiempo Real + Botón de Filtros (48x48 px) ────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('input_busqueda_catalogo'),
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      style: AppTypography.body,
                      decoration: InputDecoration(
                        hintText: 'Buscar repuesto, marca, modelo o SKU...',
                        hintStyle: AppTypography.body.copyWith(
                          color: AppPalette.textSecondary,
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: AppPalette.surface,
                        prefixIcon: const Icon(
                          Icons.search,
                          color: AppPalette.primary,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear,
                                  color: AppPalette.textSecondary,
                                ),
                                onPressed: _onClearSearch,
                                tooltip: 'Limpiar búsqueda',
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 14.0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: const BorderSide(
                            color: AppPalette.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  // Botón para abrir FiltrosDrawer con Touch Target 48x48
                  Builder(
                    builder: (scaffoldCtx) => SizedBox(
                      width: 48.0,
                      height: 48.0,
                      child: Material(
                        color: _tieneFiltrosActivos
                            ? AppPalette.primary
                            : AppPalette.surface,
                        borderRadius: BorderRadius.circular(12.0),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12.0),
                          onTap: () => Scaffold.of(scaffoldCtx).openEndDrawer(),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                Icons.tune,
                                color: _tieneFiltrosActivos
                                    ? AppPalette.textPrimary
                                    : AppPalette.textSecondary,
                                size: 22,
                              ),
                              if (_tieneFiltrosActivos)
                                Positioned(
                                  top: 9,
                                  right: 9,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: AppPalette.secondary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Fila de Chips de Filtros Activos ────────────────────────────
            if (_tieneFiltrosActivos)
              Container(
                height: 40,
                margin: const EdgeInsets.only(bottom: 8.0),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  children: [
                    if (_idCategoria != null)
                      _buildActiveFilterChip(
                        label: _idCategoria == 1 ? 'Motores' : 'Cajas',
                        onDeleted: () {
                          setState(() => _idCategoria = null);
                          _cargarOpcionesFiltros();
                          _aplicarFiltros();
                        },
                      ),
                    if (_idSucursalFiltro != null)
                      _buildActiveFilterChip(
                        label: _idSucursalFiltro == 1
                            ? 'Viña del Mar'
                            : 'Limache',
                        onDeleted: () {
                          setState(() => _idSucursalFiltro = null);
                          _cargarOpcionesFiltros();
                          _aplicarFiltros();
                        },
                      ),
                    if (_marca != null)
                      _buildActiveFilterChip(
                        label: _marca!,
                        onDeleted: () {
                          setState(() => _marca = null);
                          _aplicarFiltros();
                        },
                      ),
                    if (_anio != null)
                      _buildActiveFilterChip(
                        label: 'Año: $_anio',
                        onDeleted: () {
                          setState(() => _anio = null);
                          _aplicarFiltros();
                        },
                      ),
                    if (_cilindrada != null)
                      _buildActiveFilterChip(
                        label: '$_cilindrada L',
                        onDeleted: () {
                          setState(() => _cilindrada = null);
                          _aplicarFiltros();
                        },
                      ),
                    if (_transmision != null)
                      _buildActiveFilterChip(
                        label: _transmision!,
                        onDeleted: () {
                          setState(() => _transmision = null);
                          _aplicarFiltros();
                        },
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Material(
                        color: AppPalette.surface,
                        borderRadius: BorderRadius.circular(8.0),
                        child: InkWell(
                          onTap: _limpiarFiltros,
                          borderRadius: BorderRadius.circular(8.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 7.0,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(
                                color: AppPalette.error.withValues(alpha: 0.6),
                                width: 1.2,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.close,
                                  size: 15,
                                  color: AppPalette.error,
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Limpiar todos',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppPalette.error,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Contenido Principal (Lista / Carga / Error) ─────────────────
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveFilterChip({
    required String label,
    required VoidCallback onDeleted,
  }) {
    return Container(
      margin: const EdgeInsets.only(right: 6.0),
      child: Chip(
        label: Text(
          label,
          style: const TextStyle(
            color: AppPalette.primary,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        deleteIcon: const Icon(Icons.close, size: 15, color: AppPalette.primary),
        onDeleted: onDeleted,
        backgroundColor: AppPalette.surface,
        side: const BorderSide(color: AppPalette.primary, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoadingInitial) {
      return const Center(
        child: CircularProgressIndicator(color: AppPalette.primary),
      );
    }

    if (_errorMessage != null) {
      return RefreshIndicator(
        color: AppPalette.primary,
        backgroundColor: AppPalette.surface,
        onRefresh: () => _fetchCatalogo(resetPagination: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            padding: const EdgeInsets.all(24.0),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppPalette.error,
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(
                    color: AppPalette.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _fetchCatalogo(resetPagination: true),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.primary,
                    foregroundColor: AppPalette.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return RefreshIndicator(
        color: AppPalette.primary,
        backgroundColor: AppPalette.surface,
        onRefresh: () => _fetchCatalogo(resetPagination: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Container(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            padding: const EdgeInsets.all(24.0),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 56,
                  color: AppPalette.neutral,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No se encontraron repuestos',
                  style: AppTypography.title,
                ),
                const SizedBox(height: 6),
                Text(
                  _tieneFiltrosActivos || _searchController.text.isNotEmpty
                      ? 'Intenta ajustar los filtros o el término de búsqueda.'
                      : 'No hay repuestos disponibles en el inventario.',
                  textAlign: TextAlign.center,
                  style: AppTypography.body.copyWith(
                    color: AppPalette.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.secondary,
                    foregroundColor: AppPalette.background,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.bookmark_add, size: 18),
                  label: const Text(
                    '¿NO ESTÁ? VENTA EN VERDE',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  onPressed: () async {
                    if (CartController.instance.items.isNotEmpty) {
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: AppPalette.error,
                          behavior: SnackBarBehavior.floating,
                          content: Text(
                            'No se pueden agregar ventas en verde porque el carrito ya contiene productos. Las ventas en verde van solas.',
                          ),
                        ),
                      );
                      return;
                    }
                    final messenger = ScaffoldMessenger.of(context);
                    final reserva = await ModalBackorderForm.mostrar(context);
                    if (!mounted || reserva == null) return;
                    final ok = CartController.instance.agregarReservaBackorder(
                      idCategoria: reserva.idCategoriaRequerida,
                      categoriaNombre: reserva.categoriaNombre,
                      marca: reserva.marcaRequerida,
                      modelo: reserva.modeloRequerido,
                      anio: reserva.anioRequerido,
                      precioAcordado: reserva.precioAcordado,
                      montoAbonado: reserva.montoAbonado,
                      notas: reserva.notasPreparacion,
                    );
                    if (!ok) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Las ventas en verde deben tramitarse de manera individual. Por favor vacía el carrito antes de agregar una venta en verde.',
                          ),
                          backgroundColor: AppPalette.error,
                        ),
                      );
                      return;
                    }
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Venta en verde (${reserva.marcaRequerida} ${reserva.modeloRequerido}) añadida al Checkout Wizard.',
                        ),
                        backgroundColor: AppPalette.secondary,
                      ),
                    );
                  },
                ),
                if (_tieneFiltrosActivos ||
                    _searchController.text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      _searchController.clear();
                      _limpiarFiltros();
                    },
                    child: Text(
                      'Limpiar todos los filtros',
                      style: AppTypography.button.copyWith(
                        color: AppPalette.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppPalette.primary,
      backgroundColor: AppPalette.surface,
      onRefresh: () => _fetchCatalogo(resetPagination: true),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          16.0,
          4.0,
          16.0,
          100.0,
        ),
        itemCount: _items.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20.0),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppPalette.primary,
                  ),
                ),
              ),
            );
          }

          final item = _items[index];
          return CatalogoItemCard(
            item: item,
            vendedorSucursalId: _vendedorSucursalId,
            onAddToCart: () => _onAddToCart(item),
            onTap: () => _showDetalleRepuesto(item),
          );
        },
      ),
    );
  }
}
