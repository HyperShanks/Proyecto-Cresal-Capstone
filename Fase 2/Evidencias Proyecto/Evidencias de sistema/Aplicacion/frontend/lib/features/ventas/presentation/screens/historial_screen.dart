import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/routes/route_observer.dart';
import '../../services/ordenes_service.dart';
import '../../services/ordenes_sync_notifier.dart';
import '../widgets/orden_card.dart';
import '../widgets/orden_detail_sheet.dart';
import '../widgets/historial_filtros_drawer.dart';
import '../widgets/asignar_activo_vendedor_dialog.dart';
import '../../../../core/services/silent_polling_manager.dart';

/// Pantalla principal para la visualización y monitoreo de órdenes de venta del vendedor (HU-3.5).
class HistorialScreen extends StatefulWidget {
  final VoidCallback? onOpenMenuDrawer;
  final VoidCallback? onRefreshCatalogo;
  final ValueChanged<bool>? onEndDrawerChanged;
  final List<OrdenHistorialModel>? initialOrdenes;
  final http.Client? client;

  const HistorialScreen({
    super.key,
    this.onOpenMenuDrawer,
    this.onRefreshCatalogo,
    this.onEndDrawerChanged,
    this.initialOrdenes,
    this.client,
  });

  @override
  State<HistorialScreen> createState() => HistorialScreenState();
}

class HistorialScreenState extends State<HistorialScreen> with RouteAware {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _searchController = TextEditingController();

  List<OrdenHistorialModel> _ordenesHistorial = [];
  List<OrdenHistorialModel> _ordenesPorAsignar = [];
  List<OrdenHistorialModel> _ordenesPool = [];
  int _activeRequestId = 0;

  static const List<String> _nombresMeses = [
    '',
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  String _obtenerMesAnioLabel(String? fechaIso) {
    if (fechaIso == null || fechaIso.isEmpty) return 'Sin fecha';
    final dt = DateTime.tryParse(fechaIso)?.toLocal();
    if (dt == null) return 'Sin fecha';
    final mes = (dt.month >= 1 && dt.month <= 12) ? _nombresMeses[dt.month] : '';
    return '$mes ${dt.year}'.trim();
  }

  Widget _buildMonthHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0, left: 4.0, right: 4.0),
      child: Row(
        children: [
          Container(
            width: 4.0,
            height: 16.0,
            decoration: BoxDecoration(
              color: AppPalette.primary,
              borderRadius: BorderRadius.circular(2.0),
            ),
          ),
          const SizedBox(width: 8.0),
          Text(
            label,
            style: AppTypography.small.copyWith(
              color: AppPalette.textPrimary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              fontSize: 14.0,
            ),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: Container(
              height: 1.0,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  List<OrdenHistorialModel> get _ordenes =>
      _seccionActual == 'por_asignar' ? _ordenesPorAsignar : _ordenesHistorial;

  List<OrdenHistorialModel> get _baseOrdenes {
    if (_seccionActual == 'por_asignar') {
      return _ordenesPorAsignar;
    }
    var lista = _ordenesHistorial;
    if (_filtroAnio != null || _filtroMes != null) {
      lista = lista.where((o) {
        if (o.fechaCreacion == null || o.fechaCreacion!.isEmpty) return false;
        final dt = DateTime.tryParse(o.fechaCreacion!)?.toLocal();
        if (dt == null) return false;
        if (_filtroAnio != null && dt.year != _filtroAnio) return false;
        if (_filtroMes != null && dt.month != _filtroMes) return false;
        return true;
      }).toList();
    }
    return lista;
  }

  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';

  // Paginación y scroll infinito de 10 en 10
  static const int _tamanoPagina = 10;
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMas = false;
  bool _hasMore = true;

  // Filtros aplicados
  bool _verTodas = false;
  String? _filtroEstado;
  int? _filtroAnio;
  int? _filtroMes;

  // Filtros temporales mientras el drawer está abierto
  bool _tempVerTodas = false;
  String? _tempFiltroEstado;
  int? _tempFiltroAnio;
  int? _tempFiltroMes;

  // Compatibilidad hacia atrás
  String? get _filtroPeriodoMes => (_filtroAnio != null && _filtroMes != null)
      ? '$_filtroAnio-${_filtroMes.toString().padLeft(2, '0')}'
      : (_filtroMes != null
          ? _filtroMes.toString().padLeft(2, '0')
          : (_filtroAnio != null ? '$_filtroAnio' : null));

  String? get _tempFiltroPeriodoMes => (_tempFiltroAnio != null && _tempFiltroMes != null)
      ? '$_tempFiltroAnio-${_tempFiltroMes.toString().padLeft(2, '0')}'
      : (_tempFiltroMes != null
          ? _tempFiltroMes.toString().padLeft(2, '0')
          : (_tempFiltroAnio != null ? '$_tempFiltroAnio' : null));

  // Sección actual: 'normal' (Historial de Órdenes) o 'por_asignar' (Ventas en Verde Pagadas sin activo asignado)
  String _seccionActual = 'normal';
  int _conteoPorAsignar = 0;
  SilentPollingManager? _pollingManager;
  bool _isModalAbierto = false;

  @override
  void initState() {
    super.initState();
    _tempVerTodas = _verTodas;
    _tempFiltroEstado = _filtroEstado;
    _tempFiltroAnio = _filtroAnio;
    _tempFiltroMes = _filtroMes;
    _scrollController.addListener(_onScroll);

    OrdenesSyncNotifier.instance.addListener(_onSyncNotification);
    _iniciarAutoRefresh();

    if (widget.initialOrdenes != null) {
      _ordenesHistorial = List.from(widget.initialOrdenes!);
      _ordenarOrdenes(_ordenesHistorial);
      _isLoading = false;
      _hasMore = false;
    } else {
      _cargarOrdenes();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    if (maxScroll > 0 && currentScroll >= maxScroll * 0.85) {
      if (!_isLoading && !_isLoadingMas && _hasMore) {
        _cargarSiguientesOrdenes();
      }
    }
  }

  List<int> get _aniosDisponibles {
    final currentYear = DateTime.now().year;
    final Set<int> anios = {currentYear, currentYear - 1, currentYear - 2};
    final fuentes = _ordenesPool.isNotEmpty
        ? _ordenesPool
        : (_ordenesHistorial.isNotEmpty ? _ordenesHistorial : _ordenes);

    for (final orden in fuentes) {
      if (orden.fechaCreacion == null || orden.fechaCreacion!.isEmpty) continue;
      final dt = DateTime.tryParse(orden.fechaCreacion!);
      if (dt != null) anios.add(dt.year);
    }

    final lista = anios.toList()..sort((a, b) => b.compareTo(a));
    return lista;
  }

  List<PeriodoMesModel> get _periodosDisponibles {
    final Map<String, PeriodoMesModel> periodos = {};
    final fuentes = _ordenesPool.isNotEmpty
        ? _ordenesPool
        : (_ordenesHistorial.isNotEmpty ? _ordenesHistorial : _ordenes);

    for (final orden in fuentes) {
      if (orden.fechaCreacion == null || orden.fechaCreacion!.isEmpty) continue;
      final dt = DateTime.tryParse(orden.fechaCreacion!);
      if (dt != null) {
        final key = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
        if (!periodos.containsKey(key)) {
          final label = '${_nombresMeses[dt.month]} ${dt.year}';
          periodos[key] = PeriodoMesModel(
            year: dt.year,
            month: dt.month,
            key: key,
            label: label,
          );
        }
      }
    }

    final lista = periodos.values.toList();
    lista.sort((a, b) => b.key.compareTo(a.key));
    return lista;
  }

  String _labelPeriodo([String? key]) {
    if (key != null) {
      for (final p in _periodosDisponibles) {
        if (p.key == key) return p.label;
      }
      return key;
    }
    if (_filtroAnio != null && _filtroMes != null) {
      return '${_nombresMeses[_filtroMes!]} $_filtroAnio';
    } else if (_filtroMes != null) {
      return _nombresMeses[_filtroMes!];
    } else if (_filtroAnio != null) {
      return '$_filtroAnio';
    }
    return '';
  }

  void _iniciarAutoRefresh() {
    _pollingManager?.dispose();
    _pollingManager = SilentPollingManager(
      interval: const Duration(seconds: 15),
      debugLabel: 'HistorialPolling',
      shouldPause: () => _isModalAbierto || _isLoading,
      onPoll: () async {
        if (mounted) {
          await _cargarOrdenesSilencioso();
        }
      },
    )..start();
  }

  /// Prioridad de ordenamiento: 0 = Activas/Pendientes, 1 = Completadas, 2 = Anuladas (al final absoluto)
  static int _prioridadEstado(String estado) {
    final est = estado.trim().toLowerCase();
    if (est == 'anulada') return 2;
    if (est == 'completada' || est == 'entregada') return 1;
    return 0;
  }

  void _ordenarOrdenes(List<OrdenHistorialModel> lista) {
    lista.sort((a, b) {
      final aPrio = _prioridadEstado(a.estadoOrden);
      final bPrio = _prioridadEstado(b.estadoOrden);
      if (aPrio != bPrio) {
        return aPrio.compareTo(bPrio);
      }
      return (b.fechaCreacion ?? '').compareTo(a.fechaCreacion ?? '');
    });
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
    _cargarOrdenesSilencioso();
  }

  void _onSyncNotification() {
    if (mounted) {
      _cargarOrdenesSilencioso();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pollingManager?.dispose();
    routeObserver.unsubscribe(this);
    OrdenesSyncNotifier.instance.removeListener(_onSyncNotification);
    _searchController.dispose();
    super.dispose();
  }

  /// Método público para forzar recarga de órdenes (Auto-Refresh SPEC-HU-TAREA-20)
  Future<void> refrescar() async {
    await _cargarOrdenes();
  }

  /// Recarga silenciosa sin loaders si ya hay datos en memoria
  Future<void> refrescarSilencioso() async {
    if (_ordenesHistorial.isEmpty && _ordenesPorAsignar.isEmpty) {
      await _cargarOrdenes();
    } else {
      await _cargarOrdenesSilencioso();
    }
  }

  Future<void> _cargarOrdenes() async {
    final int requestId = ++_activeRequestId;
    final String seccionSolicitada = _seccionActual;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Si se inyectaron órdenes iniciales (en tests o modo local) sin cliente HTTP mocked,
    // conservamos los datos iniciales y dejamos que _ordenesFiltradas realice el filtrado reactivo.
    setState(() {
      _isLoading = true;
      _isLoadingMas = false;
      _hasMore = true;
      _errorMessage = null;
    });

    if (widget.initialOrdenes != null && widget.client == null) {
      setState(() {
        _isLoading = false;
        _hasMore = false;
        _errorMessage = null;
      });
      return;
    }

    try {
      final String? estadoParaBackend =
          (seccionSolicitada == 'por_asignar' || _filtroEstado == 'Abonado')
              ? null
              : _filtroEstado;

      final ordenes = await OrdenesService.obtenerMisVentas(
        todas: seccionSolicitada == 'por_asignar'
            ? true
            : (_verTodas || _filtroAnio != null || _filtroMes != null),
        estado: estadoParaBackend,
        seccion: seccionSolicitada,
        limit: _tamanoPagina,
        offset: 0,
        mes: _filtroMes,
        anio: _filtroAnio,
        client: widget.client,
      );

      if (!mounted ||
          requestId != _activeRequestId ||
          _seccionActual != seccionSolicitada) {
        return;
      }

      // Ordenar: Activas al principio, completadas al final y anuladas al final absoluto
      _ordenarOrdenes(ordenes);

      setState(() {
        if (seccionSolicitada == 'por_asignar') {
          _ordenesPorAsignar = ordenes;
          _conteoPorAsignar = ordenes.length;
        } else {
          // Salvaguarda: si el servidor retorna más de 10 órdenes (ej. versión de Render sin paginación),
          // retenemos el conjunto completo en el pool local y mostramos estrictamente los primeros 10.
          if (ordenes.length > _tamanoPagina) {
            _ordenesPool = List.from(ordenes);
            _ordenesHistorial = _ordenesPool.take(_tamanoPagina).toList();
            _hasMore = true;
          } else {
            _ordenesPool = [];
            _ordenesHistorial = ordenes;
            _hasMore = ordenes.length >= _tamanoPagina;
          }
        }
        _isLoading = false;
        _errorMessage = null;
      });

      // Carga asíncrona del conteo 'por asignar' en segundo plano sin demorar la visualización de la lista
      if (seccionSolicitada != 'por_asignar') {
        OrdenesService.obtenerMisVentas(
          seccion: 'por_asignar',
          todas: true,
          limit: 100,
          client: widget.client,
        ).then((porAsignar) {
          if (mounted && requestId == _activeRequestId) {
            setState(() {
              _conteoPorAsignar = porAsignar.length;
            });
          }
        }).catchError((_) {});
      }
    } catch (e) {
      if (!mounted ||
          requestId != _activeRequestId ||
          _seccionActual != seccionSolicitada) {
        return;
      }
      setState(() {
        _errorMessage = OrdenesService.sanitizarMensajeError(e);
        _isLoading = false;
      });
    }
  }

  /// Carga la siguiente página de órdenes (de 10 en 10) al alcanzar el scroll inferior
  Future<void> _cargarSiguientesOrdenes() async {
    if (!mounted || _isLoading || _isLoadingMas || !_hasMore) return;
    if (widget.initialOrdenes != null && widget.client == null) return;

    final int requestId = _activeRequestId;
    final String seccionSolicitada = _seccionActual;
    final currentList = (seccionSolicitada == 'por_asignar')
        ? _ordenesPorAsignar
        : _ordenesHistorial;

    // Si ya tenemos órdenes en el pool local (recibidas en bloque), consumimos los siguientes 10 instantáneamente
    if (seccionSolicitada != 'por_asignar' &&
        _ordenesPool.isNotEmpty &&
        currentList.length < _ordenesPool.length) {
      final siguientes = _ordenesPool.skip(currentList.length).take(_tamanoPagina).toList();
      setState(() {
        _ordenesHistorial.addAll(siguientes);
        _hasMore = _ordenesHistorial.length < _ordenesPool.length;
      });
      return;
    }

    setState(() {
      _isLoadingMas = true;
    });

    try {
      final String? estadoParaBackend =
          (seccionSolicitada == 'por_asignar' || _filtroEstado == 'Abonado')
              ? null
              : _filtroEstado;

      final nuevasOrdenes = await OrdenesService.obtenerMisVentas(
        todas: seccionSolicitada == 'por_asignar'
            ? true
            : (_verTodas || _filtroAnio != null || _filtroMes != null),
        estado: estadoParaBackend,
        seccion: seccionSolicitada,
        limit: _tamanoPagina,
        offset: currentList.length,
        mes: _filtroMes,
        anio: _filtroAnio,
        client: widget.client,
      );

      if (!mounted || requestId != _activeRequestId || _seccionActual != seccionSolicitada) {
        return;
      }

      setState(() {
        if (nuevasOrdenes.isNotEmpty) {
          final existingIds = currentList.map((o) => o.idOrden).toSet();
          final uniqueNew = nuevasOrdenes.where((o) => !existingIds.contains(o.idOrden)).toList();

          if (seccionSolicitada == 'por_asignar') {
            _ordenesPorAsignar.addAll(uniqueNew);
            _ordenarOrdenes(_ordenesPorAsignar);
          } else {
            _ordenesHistorial.addAll(uniqueNew);
            _ordenarOrdenes(_ordenesHistorial);
          }
        }
        _hasMore = nuevasOrdenes.length >= _tamanoPagina;
        _isLoadingMas = false;
      });
    } catch (_) {
      if (!mounted || requestId != _activeRequestId) return;
      setState(() {
        _isLoadingMas = false;
      });
    }
  }

  /// Recarga en segundo plano sin interrumpir la interacción del usuario
  Future<void> _cargarOrdenesSilencioso() async {
    if (!mounted || _isLoading) return;
    if (widget.initialOrdenes != null && widget.client == null) return;
    final int requestId = ++_activeRequestId;
    final String seccionSolicitada = _seccionActual;

    try {
      final String? estadoParaBackend =
          (seccionSolicitada == 'por_asignar' || _filtroEstado == 'Abonado')
              ? null
              : _filtroEstado;

      final limitSilencioso = _ordenesHistorial.length > _tamanoPagina
          ? _ordenesHistorial.length
          : _tamanoPagina;

      final ordenes = await OrdenesService.obtenerMisVentas(
        todas: seccionSolicitada == 'por_asignar'
            ? true
            : (_verTodas || _filtroAnio != null || _filtroMes != null),
        estado: estadoParaBackend,
        seccion: seccionSolicitada,
        limit: limitSilencioso,
        offset: 0,
        mes: _filtroMes,
        anio: _filtroAnio,
        client: widget.client,
      );

      if (!mounted ||
          requestId != _activeRequestId ||
          _seccionActual != seccionSolicitada) {
        return;
      }
      _ordenarOrdenes(ordenes);

      setState(() {
        if (seccionSolicitada == 'por_asignar') {
          _ordenesPorAsignar = ordenes;
          _conteoPorAsignar = ordenes.length;
        } else {
          if (_ordenesPool.isNotEmpty) {
            _ordenesPool = List.from(ordenes);
            _ordenesHistorial = _ordenesPool.take(_ordenesHistorial.length).toList();
          } else if (ordenes.length > _ordenesHistorial.length && _ordenesHistorial.length <= _tamanoPagina) {
            _ordenesHistorial = ordenes.take(_tamanoPagina).toList();
          } else {
            _ordenesHistorial = ordenes;
          }
        }
      });

      if (seccionSolicitada != 'por_asignar') {
        OrdenesService.obtenerMisVentas(
          seccion: 'por_asignar',
          todas: true,
          client: widget.client,
        ).then((porAsignar) {
          if (mounted && requestId == _activeRequestId) {
            setState(() {
              _conteoPorAsignar = porAsignar.length;
            });
          }
        }).catchError((_) {});
      }
    } catch (_) {
      // Ignorar errores en ciclo silencioso
    }
  }

  /// Lista filtrada reactivamente según el término de búsqueda ingresado
  List<OrdenHistorialModel> get _ordenesFiltradas {
    var lista = _baseOrdenes;

    // Regla de Negocio: Las órdenes anuladas salen ocultas por defecto en Mis Órdenes,
    // salvo que se seleccione explícitamente el filtro de 'Anulada'.
    if (_filtroEstado != null) {
      if (_filtroEstado == 'Anulada') {
        lista = lista.where((orden) => orden.esAnulada).toList();
      } else if (_filtroEstado == 'Abonado') {
        lista = lista
            .where((orden) =>
                !orden.esAnulada &&
                orden.montoPendiente > 0 &&
                orden.totalVenta > orden.montoPendiente)
            .toList();
      } else {
        lista = lista
            .where((orden) =>
                orden.estadoOrden.toLowerCase() == _filtroEstado!.toLowerCase())
            .toList();
      }
    } else {
      lista = lista.where((orden) => !orden.esAnulada).toList();
    }

    if (_searchQuery.trim().isEmpty) {
      return lista;
    }

    final query = _searchQuery.trim().toLowerCase();
    final cleanQuery = query.replaceAll('#', '').trim();

    return lista.where((orden) {
      // 1. Folio / ID de Orden / Token QR
      final idMatch = orden.idOrden.toLowerCase().contains(cleanQuery);
      final folioMatch =
          orden.folioDisplay.toLowerCase().contains(cleanQuery) ||
          orden.folioDisplay.toLowerCase().contains(query);
      final qrMatch =
          orden.qrTransaccionalSalida != null &&
          orden.qrTransaccionalSalida!.toLowerCase().contains(cleanQuery);

      // 2. Cliente: Nombre Completo y RUT
      final cliente = orden.cliente;
      final clienteNombreMatch =
          cliente != null &&
          cliente.nombreCompleto.toLowerCase().contains(cleanQuery);
      final clienteRutMatch =
          cliente != null &&
          (cliente.rutCliente.toLowerCase().contains(cleanQuery) ||
              cliente.rutCliente
                  .replaceAll('.', '')
                  .replaceAll('-', '')
                  .toLowerCase()
                  .contains(
                    cleanQuery.replaceAll('.', '').replaceAll('-', ''),
                  ));

      // 3. Despacho: Receptor y RUT
      final despacho = orden.despacho;
      final receptorNombreMatch =
          despacho != null &&
          despacho.receptorNombres.toLowerCase().contains(cleanQuery);
      final receptorRutMatch =
          despacho != null &&
          despacho.receptorRut.toLowerCase().contains(cleanQuery);

      // 4. Marca / Modelo / Título o SKU del Repuesto en líneas de detalle
      final repuestosMatch = orden.detalles.any((detalle) {
        final titulo = detalle.titulo.toLowerCase();
        final desc = (detalle.descripcionManual ?? '').toLowerCase();
        final sku = (detalle.skuQrFisico ?? '').toLowerCase();
        return titulo.contains(cleanQuery) ||
            desc.contains(cleanQuery) ||
            sku.contains(cleanQuery);
      });

      return idMatch ||
          folioMatch ||
          qrMatch ||
          clienteNombreMatch ||
          clienteRutMatch ||
          receptorNombreMatch ||
          receptorRutMatch ||
          repuestosMatch;
    }).toList();
  }

  Future<void> _abrirDetalleOrden(OrdenHistorialModel orden) async {
    _isModalAbierto = true;
    try {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        builder: (ctx) => OrdenDetailSheet(
          orden: orden,
          onOrderUpdated: () {
            _cargarOrdenesSilencioso();
            widget.onRefreshCatalogo?.call();
          },
        ),
      );
    } finally {
      _isModalAbierto = false;
    }
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 10.0, 16.0, 6.0),
      child: TextField(
        key: const Key('buscador_ordenes_textfield'),
        controller: _searchController,
        onChanged: (val) {
          setState(() {
            _searchQuery = val;
          });
        },
        style: AppTypography.body.copyWith(
          color: AppPalette.textPrimary,
          fontSize: 14,
        ),
        cursorColor: AppPalette.primary,
        decoration: InputDecoration(
          hintText: 'Buscar por Folio, Cliente, RUT o Repuesto...',
          hintStyle: AppTypography.body.copyWith(
            color: AppPalette.textSecondary.withValues(alpha: 0.65),
            fontSize: 13,
          ),
          prefixIcon: const Icon(
            Icons.search,
            color: AppPalette.textSecondary,
            size: 20,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  key: const Key('btn_limpiar_busqueda_ordenes'),
                  icon: const Icon(
                    Icons.clear,
                    color: AppPalette.textSecondary,
                    size: 20,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  tooltip: 'Limpiar búsqueda',
                )
              : null,
          filled: true,
          fillColor: AppPalette.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14.0,
            vertical: 10.0,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: BorderSide(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1.0,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10.0),
            borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildSeccionTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Container(
        padding: const EdgeInsets.all(4.0),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildTabButton(
                titulo: 'Historial de Órdenes',
                seccion: 'normal',
                icon: Icons.history,
              ),
            ),
            const SizedBox(width: 4.0),
            Expanded(
              child: _buildTabButton(
                titulo: 'Por Asignar',
                seccion: 'por_asignar',
                icon: Icons.pending_actions,
                badgeCount: _conteoPorAsignar,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required String titulo,
    required String seccion,
    required IconData icon,
    int badgeCount = 0,
  }) {
    final isSelected = _seccionActual == seccion;
    return InkWell(
      key: Key('tab_seccion_$seccion'),
      onTap: () {
        if (_seccionActual != seccion) {
          setState(() {
            _seccionActual = seccion;
          });
          _cargarOrdenes();
        }
      },
      borderRadius: BorderRadius.circular(8.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        decoration: BoxDecoration(
          color: isSelected
              ? AppPalette.primary.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8.0),
          border: isSelected
              ? Border.all(
                  color: AppPalette.primary.withValues(alpha: 0.6),
                  width: 1.0,
                )
              : Border.all(color: Colors.transparent, width: 1.0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16.0,
              color: isSelected ? AppPalette.primary : AppPalette.textSecondary,
            ),
            const SizedBox(width: 4.0),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  titulo,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 16.0,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected
                        ? AppPalette.textPrimary
                        : AppPalette.textSecondary,
                    fontFamily: AppTypography.fontFamily,
                  ),
                ),
              ),
            ),
            if (badgeCount > 0) ...[
              const SizedBox(width: 4.0),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5.0,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppPalette.secondary : AppPalette.warning,
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    fontSize: 10.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFilterChips() {
    if (_seccionActual != 'normal') return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _buildQuickChip(
              label: 'Activas',
              isSelected: _filtroEstado == null && !_verTodas && _filtroAnio == null && _filtroMes == null,
              icon: Icons.check_circle_outline,
              onTap: () {
                if (_filtroEstado != null || _verTodas || _filtroAnio != null || _filtroMes != null) {
                  setState(() {
                    _filtroEstado = null;
                    _verTodas = false;
                    _filtroAnio = null;
                    _filtroMes = null;
                  });
                  _cargarOrdenes();
                }
              },
            ),
            const SizedBox(width: 8.0),
            _buildQuickChip(
              label: 'Reservadas',
              isSelected: _filtroEstado == 'Reservada',
              activeColor: AppPalette.secondary,
              onTap: () {
                setState(() {
                  if (_filtroEstado == 'Reservada') {
                    _filtroEstado = null;
                    _verTodas = false;
                  } else {
                    _filtroEstado = 'Reservada';
                    _verTodas = true;
                    _filtroAnio = null;
                    _filtroMes = null;
                  }
                });
                _cargarOrdenes();
              },
            ),
            const SizedBox(width: 8.0),
            _buildQuickChip(
              label: 'Abonados',
              isSelected: _filtroEstado == 'Abonado',
              activeColor: AppPalette.warning,
              icon: Icons.account_balance_wallet_outlined,
              onTap: () {
                setState(() {
                  if (_filtroEstado == 'Abonado') {
                    _filtroEstado = null;
                    _verTodas = false;
                  } else {
                    _filtroEstado = 'Abonado';
                    _verTodas = true;
                    _filtroAnio = null;
                    _filtroMes = null;
                  }
                });
                _cargarOrdenes();
              },
            ),
            const SizedBox(width: 8.0),
            _buildQuickChip(
              label: 'Pagadas',
              isSelected: _filtroEstado == 'Pagada',
              activeColor: AppPalette.success,
              onTap: () {
                setState(() {
                  if (_filtroEstado == 'Pagada') {
                    _filtroEstado = null;
                    _verTodas = false;
                  } else {
                    _filtroEstado = 'Pagada';
                    _verTodas = false;
                    _filtroAnio = null;
                    _filtroMes = null;
                  }
                });
                _cargarOrdenes();
              },
            ),
            const SizedBox(width: 8.0),
            _buildQuickChip(
              label: 'Completadas',
              isSelected: _filtroEstado == 'Completada',
              activeColor: AppPalette.primary,
              onTap: () {
                setState(() {
                  if (_filtroEstado == 'Completada') {
                    _filtroEstado = null;
                    _verTodas = false;
                  } else {
                    _filtroEstado = 'Completada';
                    _verTodas = false;
                    _filtroAnio = null;
                    _filtroMes = null;
                  }
                });
                _cargarOrdenes();
              },
            ),
            const SizedBox(width: 8.0),
            _buildQuickChip(
              label: 'Solo Anuladas',
              isSelected: _filtroEstado == 'Anulada',
              activeColor: AppPalette.error,
              icon: Icons.cancel_outlined,
              onTap: () {
                setState(() {
                  if (_filtroEstado == 'Anulada') {
                    _filtroEstado = null;
                    _verTodas = false;
                  } else {
                    _filtroEstado = 'Anulada';
                    _verTodas = false;
                    _filtroAnio = null;
                    _filtroMes = null;
                  }
                });
                _cargarOrdenes();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? activeColor,
    IconData? icon,
  }) {
    final selectedColor = activeColor ?? AppPalette.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
          decoration: BoxDecoration(
            color: isSelected ? selectedColor.withValues(alpha: 0.22) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(
              color: isSelected ? selectedColor : const Color(0xFF334155),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? selectedColor : const Color(0xFFCBD5E1),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? (activeColor != null ? selectedColor : Colors.white) : const Color(0xFFCBD5E1),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnuladasBanner() {
    if (_seccionActual != 'normal' || _filtroEstado != 'Anulada') {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: AppPalette.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: AppPalette.error.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cancel_outlined, color: AppPalette.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Visualizando únicamente órdenes anuladas (${_verTodas ? "Historial Completo" : "Hoy"}).',
                style: const TextStyle(
                  color: AppPalette.error,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            InkWell(
              onTap: () {
                setState(() {
                  _filtroEstado = null;
                  _tempFiltroEstado = null;
                });
                _cargarOrdenes();
              },
              borderRadius: BorderRadius.circular(4),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  'Ver Activas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdenPorAsignarCard(OrdenHistorialModel orden) {
    // Guardia de seguridad: Asegurar que la orden sea venta en verde con ítem pendiente
    final tieneBackorderPendiente = orden.detalles.any(
      (d) => !d.esInventariado,
    );
    if (!tieneBackorderPendiente) {
      return const SizedBox.shrink();
    }

    return Container(
      key: Key('orden_por_asignar_${orden.idOrden}'),
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: AppPalette.warning.withValues(alpha: 0.4),
          width: 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12.0),
        child: InkWell(
          borderRadius: BorderRadius.circular(12.0),
          onTap: () => _abrirDetalleOrden(orden),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cabecera: Folio y Badge de Advertencia
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6.0),
                            decoration: BoxDecoration(
                              color: AppPalette.warning.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: const Icon(
                              Icons.hourglass_top,
                              size: 18.0,
                              color: AppPalette.warning,
                            ),
                          ),
                          const SizedBox(width: 8.0),
                          Expanded(
                            child: Text(
                              orden.folioDisplay,
                              style: AppTypography.title.copyWith(
                                fontSize: 16.0,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10.0,
                        vertical: 4.0,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.warning.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20.0),
                        border: Border.all(
                          color: AppPalette.warning.withValues(alpha: 0.6),
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.pending_actions,
                            size: 13.0,
                            color: AppPalette.warning,
                          ),
                          const SizedBox(width: 4.0),
                          Text(
                            'Por Asignar Activo',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: AppPalette.warning,
                              fontFamily: AppTypography.fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12.0),
                const Divider(color: Colors.white10, height: 1.0),
                const SizedBox(height: 12.0),

                // Cliente
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      size: 16.0,
                      color: AppPalette.textSecondary,
                    ),
                    const SizedBox(width: 6.0),
                    Expanded(
                      child: Text(
                        orden.cliente != null &&
                                orden.cliente!.nombres.isNotEmpty
                            ? '${orden.cliente!.nombreCompleto} (${orden.cliente!.rutCliente})'
                            : 'Cliente General',
                        style: AppTypography.body.copyWith(
                          fontSize: 14.0,
                          color: AppPalette.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6.0),

                // Fecha y estado de pago
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 14.0,
                      color: AppPalette.textSecondary,
                    ),
                    const SizedBox(width: 6.0),
                    Text(
                      orden.fechaFormateada,
                      style: AppTypography.small.copyWith(
                        fontSize: 12.5,
                        color: AppPalette.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8.0),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8.0,
                            vertical: 2.0,
                          ),
                          decoration: BoxDecoration(
                            color: AppPalette.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4.0),
                            border: Border.all(
                              color: AppPalette.success.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            'Pagada al 100% (${orden.totalVentaFormateado})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.0,
                              fontWeight: FontWeight.bold,
                              color: AppPalette.success,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // Detalle del ítem en verde
                if (orden.detalles.isNotEmpty) ...[
                  const SizedBox(height: 10.0),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10.0),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Repuesto en Verde Solicitado:',
                          style: AppTypography.small.copyWith(
                            fontSize: 11.0,
                            color: AppPalette.textSecondary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          orden.detalles.first.titulo,
                          style: AppTypography.body.copyWith(
                            fontSize: 13.0,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12.0),
                // Botón de asignación física
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.primary,
                      foregroundColor: AppPalette.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    icon: const Icon(Icons.qr_code_scanner, size: 20.0),
                    label: const Text(
                      'Asignar Activo Físico',
                      style: TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () {
                      AsignarActivoVendedorDialog.mostrar(
                        context,
                        orden: orden,
                        onAsignadoExitoso: _cargarOrdenes,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoSearchResultsState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: AppPalette.surface,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white10),
              ),
              child: const Icon(
                Icons.search_off,
                size: 50.0,
                color: AppPalette.textSecondary,
              ),
            ),
            const SizedBox(height: 20.0),
            Text(
              'No se encontraron órdenes que coincidan con la búsqueda',
              style: AppTypography.title.copyWith(fontSize: 16.0),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8.0),
            Text(
              'No hay resultados para "$_searchQuery". Verifica el folio (#...), cliente, RUT o nombre del repuesto.',
              style: AppTypography.small.copyWith(
                color: AppPalette.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20.0),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.primary,
                side: const BorderSide(color: AppPalette.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              icon: const Icon(Icons.clear, size: 18.0),
              label: const Text('Limpiar Búsqueda'),
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final bool esPorAsignar = _seccionActual == 'por_asignar';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                color: AppPalette.surface,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white10),
              ),
              child: Icon(
                esPorAsignar
                    ? Icons.assignment_turned_in_outlined
                    : Icons.receipt_long_outlined,
                size: 54.0,
                color: esPorAsignar
                    ? AppPalette.success
                    : AppPalette.textSecondary,
              ),
            ),
            const SizedBox(height: 20.0),
            Text(
              esPorAsignar
                  ? 'Sin ventas en verde por asignar'
                  : (_filtroAnio != null || _filtroMes != null)
                  ? 'No hay órdenes en ${_labelPeriodo()}'
                  : _filtroEstado != null
                  ? 'No hay órdenes en estado "$_filtroEstado"'
                  : _verTodas
                  ? 'No tienes órdenes en tu historial'
                  : 'No has generado órdenes hoy',
              style: AppTypography.title.copyWith(fontSize: 18.0),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8.0),
            Text(
              esPorAsignar
                  ? 'Todas tus ventas en verde pagadas ya cuentan con su activo físico asignado o están en proceso.'
                  : (_filtroEstado != null || _filtroAnio != null || _filtroMes != null)
                  ? 'Prueba cambiando o limpiando los filtros para ver otras ventas.'
                  : _verTodas
                  ? 'Tus ventas derivadas a caja aparecerán aquí con su estado en tiempo real.'
                  : 'Las ventas creadas durante el día se listarán aquí para su seguimiento y gestión.',
              style: AppTypography.small.copyWith(
                color: AppPalette.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24.0),
            if (!esPorAsignar && (_filtroEstado != null || _filtroAnio != null || _filtroMes != null || !_verTodas))
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.primary,
                  side: const BorderSide(color: AppPalette.primary),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20.0,
                    vertical: 12.0,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                icon: Icon(
                  (_filtroEstado != null || _filtroAnio != null || _filtroMes != null)
                      ? Icons.filter_alt_off
                      : Icons.history,
                  size: 18.0,
                ),
                label: Text(
                  (_filtroEstado != null || _filtroAnio != null || _filtroMes != null)
                      ? 'Limpiar Filtros'
                      : 'Ver Historial Completo',
                ),
                onPressed: () {
                  setState(() {
                    if (_filtroEstado != null || _filtroAnio != null || _filtroMes != null) {
                      _filtroEstado = null;
                      _tempFiltroEstado = null;
                      _filtroAnio = null;
                      _filtroMes = null;
                      _tempFiltroAnio = null;
                      _tempFiltroMes = null;
                      _verTodas = false;
                      _tempVerTodas = false;
                    } else {
                      _verTodas = true;
                      _tempVerTodas = true;
                    }
                  });
                  _cargarOrdenes();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final mensajeLimpio = OrdenesService.sanitizarMensajeError(_errorMessage);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480.0),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          decoration: BoxDecoration(
            color: AppPalette.surface,
            borderRadius: BorderRadius.circular(16.0),
            border: Border.all(
              color: AppPalette.error.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12.0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52.0,
                height: 52.0,
                decoration: BoxDecoration(
                  color: AppPalette.error.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  size: 28.0,
                  color: AppPalette.error,
                ),
              ),
              const SizedBox(height: 12.0),
              const Text(
                'Error al cargar órdenes',
                style: AppTypography.title,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8.0),
              Text(
                mensajeLimpio,
                style: AppTypography.small.copyWith(
                  color: AppPalette.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20.0),
              ElevatedButton.icon(
                key: const Key('btn_reintentar_historial'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.primary,
                  foregroundColor: AppPalette.textPrimary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 12.0,
                  ),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                icon: const Icon(Icons.refresh, size: 18.0),
                label: const Text(
                  'Reintentar',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onPressed: _cargarOrdenes,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hayFiltrosActivos =
        _verTodas || _filtroEstado != null || _filtroAnio != null || _filtroMes != null;
    final ordenesMostradas = _ordenesFiltradas;

    String subtitleText;
    if (_seccionActual == 'por_asignar') {
      subtitleText = 'Ventas en verde pagadas pendientes de activo';
    } else {
      String periodoTexto = '';
      if (_filtroAnio != null && _filtroMes != null) {
        periodoTexto = 'Periodo: ${_nombresMeses[_filtroMes!]} $_filtroAnio';
      } else if (_filtroMes != null) {
        periodoTexto = 'Mes: ${_nombresMeses[_filtroMes!]}';
      } else if (_filtroAnio != null) {
        periodoTexto = 'Año: $_filtroAnio';
      }

      if (periodoTexto.isNotEmpty) {
        subtitleText = '$periodoTexto${_filtroEstado != null ? " · $_filtroEstado" : ""}';
      } else if (_filtroEstado != null) {
        subtitleText = 'Filtro: $_filtroEstado (${_verTodas ? "Historial" : "Hoy"})';
      } else if (_verTodas) {
        subtitleText = 'Historial completo de ventas';
      } else {
        subtitleText = 'Ventas del día (Hoy)';
      }
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        backgroundColor: AppPalette.background,
        elevation: 0,
        leading: widget.onOpenMenuDrawer != null
            ? IconButton(
                icon: const Icon(Icons.menu, color: AppPalette.textPrimary),
                onPressed: widget.onOpenMenuDrawer,
                tooltip: 'Menú principal',
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mis Órdenes', style: AppTypography.title),
            Text(
              subtitleText,
              style: AppTypography.small.copyWith(
                fontSize: 12.0,
                color: (_seccionActual == 'por_asignar' || hayFiltrosActivos)
                    ? AppPalette.secondary
                    : AppPalette.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          // Botón de Filtros (Abre el EndDrawer)
          Builder(
            builder: (ctx) => Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.tune,
                    color: hayFiltrosActivos
                        ? AppPalette.secondary
                        : AppPalette.textPrimary,
                  ),
                  onPressed: () {
                    setState(() {
                      _tempVerTodas = _verTodas;
                      _tempFiltroEstado = _filtroEstado;
                      _tempFiltroAnio = _filtroAnio;
                      _tempFiltroMes = _filtroMes;
                    });
                    Scaffold.of(ctx).openEndDrawer();
                  },
                  tooltip: 'Filtrar órdenes',
                ),
                if (hayFiltrosActivos)
                  Positioned(
                    top: 10,
                    right: 10,
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
          IconButton(
            icon: const Icon(Icons.refresh, color: AppPalette.textPrimary),
            onPressed: _isLoading ? null : _cargarOrdenes,
            tooltip: 'Actualizar lista',
          ),
          const SizedBox(width: 8),
        ],
      ),
      endDrawer: HistorialFiltrosDrawer(
        verTodas: _tempVerTodas,
        filtroEstado: _tempFiltroEstado,
        filtroAnio: _tempFiltroAnio,
        filtroMes: _tempFiltroMes,
        aniosDisponibles: _aniosDisponibles,
        periodoMes: _tempFiltroPeriodoMes,
        periodosDisponibles: _periodosDisponibles,
        onPeriodoChanged: (val) {
          setState(() {
            _tempVerTodas = val;
            if (!val) {
              _tempFiltroAnio = null;
              _tempFiltroMes = null;
            }
          });
        },
        onEstadoChanged: (val) {
          setState(() {
            _tempFiltroEstado = val;
            if (val == 'Reservada' || val == 'Abonado') {
              _tempVerTodas = true;
              _tempFiltroAnio = null;
              _tempFiltroMes = null;
            }
          });
        },
        onAnioChanged: (val) {
          setState(() {
            _tempFiltroAnio = val;
            if (val != null) _tempVerTodas = true;
          });
        },
        onMesChanged: (val) {
          setState(() {
            _tempFiltroMes = val;
            if (val != null) _tempVerTodas = true;
          });
        },
        onPeriodoMesChanged: (val) {
          setState(() {
            if (val != null && val.contains('-')) {
              final parts = val.split('-');
              _tempFiltroAnio = int.tryParse(parts[0]);
              _tempFiltroMes = int.tryParse(parts[1]);
              _tempVerTodas = true;
            } else {
              _tempFiltroAnio = null;
              _tempFiltroMes = null;
            }
          });
        },
        onAplicar: () {
          setState(() {
            _verTodas = _tempVerTodas;
            _filtroEstado = _tempFiltroEstado;
            _filtroAnio = _tempFiltroAnio;
            _filtroMes = _tempFiltroMes;
          });
          _cargarOrdenes();
        },
        onLimpiar: () {
          setState(() {
            _verTodas = false;
            _filtroEstado = null;
            _filtroAnio = null;
            _filtroMes = null;
            _tempVerTodas = false;
            _tempFiltroEstado = null;
            _tempFiltroAnio = null;
            _tempFiltroMes = null;
          });
          _cargarOrdenes();
        },
      ),
      onEndDrawerChanged: widget.onEndDrawerChanged,
      body: Column(
        children: [
          _buildSearchBar(),
          _buildSeccionTabs(),
          _buildQuickFilterChips(),
          _buildAnuladasBanner(),
          Expanded(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: AppPalette.primary),
                        const SizedBox(height: 16.0),
                        Text(
                          'Cargando historial de órdenes...',
                          style: AppTypography.body.copyWith(
                            color: AppPalette.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                : _errorMessage != null
                ? _buildErrorState()
                : _baseOrdenes.isEmpty || (_searchQuery.isEmpty && ordenesMostradas.isEmpty)
                ? RefreshIndicator(
                    onRefresh: _cargarOrdenes,
                    color: AppPalette.primary,
                    backgroundColor: AppPalette.surface,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.65,
                          child: _buildEmptyState(),
                        ),
                      ],
                    ),
                  )
                : ordenesMostradas.isEmpty
                ? RefreshIndicator(
                    onRefresh: _cargarOrdenes,
                    color: AppPalette.primary,
                    backgroundColor: AppPalette.surface,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.65,
                          child: _buildNoSearchResultsState(),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _cargarOrdenes,
                    color: AppPalette.primary,
                    backgroundColor: AppPalette.surface,
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        16.0,
                        8.0,
                        16.0,
                        100.0,
                      ),
                      itemCount: ordenesMostradas.length + (_isLoadingMas ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= ordenesMostradas.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20.0),
                            child: Center(
                              child: SizedBox(
                                width: 24.0,
                                height: 24.0,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: AppPalette.primary,
                                ),
                              ),
                            ),
                          );
                        }

                        final orden = ordenesMostradas[index];
                        final String labelMesActual = _obtenerMesAnioLabel(orden.fechaCreacion);
                        final bool esNuevoGrupo = index == 0 ||
                            _obtenerMesAnioLabel(ordenesMostradas[index - 1].fechaCreacion) != labelMesActual;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (esNuevoGrupo) _buildMonthHeader(labelMesActual),
                            if (_seccionActual == 'por_asignar')
                              _buildOrdenPorAsignarCard(orden)
                            else
                              OrdenCard(
                                orden: orden,
                                onTap: () => _abrirDetalleOrden(orden),
                                onEstadoDespachoCambiado: _cargarOrdenes,
                                onOrdenActualizada: () {
                                  _cargarOrdenes();
                                  widget.onRefreshCatalogo?.call();
                                },
                                client: widget.client,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
