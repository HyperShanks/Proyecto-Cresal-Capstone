// frontend/lib/features/gerencia/presentation/screens/dashboard_gerencia_view.dart
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/routes/route_observer.dart';
import '../../../../core/services/api_service.dart';
import '../../../../routes/app_routes.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/custom_error_snackbar.dart';
import '../../../auth/services/auth_service.dart';
import '../../models/gerencia_models.dart';
import '../../services/gerencia_service.dart';
import '../widgets/kpi_card_widget.dart';
import '../widgets/metodos_pago_chart.dart';
import 'inventario_gerencia_view.dart';
import 'ordenes_gerencia_view.dart';
import 'backorders_gerencia_view.dart';
import '../../../../core/widgets/update_dialog.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/services/silent_polling_manager.dart';

/// Enumeración de vistas principales del panel gerencial (HU-5.1 y HU-5.2).
enum VistaGerencia { dashboard, ordenes, inventario, backorders }

/// Vista principal del Dashboard Ejecutivo para Gerencia (HU-5.1).
/// Diseñé esta pantalla integrando la barra superior de filtros de sucursal,
/// la grilla superior de KPIs financieros y el trío de Bento cards para
/// métodos de pago, alertas operativas y flujo de despacho de bodega.
class DashboardGerenciaView extends StatefulWidget {
  final int? sucursalInicial;

  const DashboardGerenciaView({super.key, this.sucursalInicial});

  @override
  State<DashboardGerenciaView> createState() => _DashboardGerenciaViewState();
}

class _DashboardGerenciaViewState extends State<DashboardGerenciaView>
    with SingleTickerProviderStateMixin, RouteAware {
  int? _sucursalSeleccionada;
  bool _cargando = false;
  String? _mensajeError;
  String? _codigoError;
  String? _detalleTecnicoError;
  bool _mostrarDetalleTecnico = false;

  KpiFinancieroModel? _kpis;
  ResumenPagosModel? _pagos;
  FlujoOperativoModel? _flujo;
  String _nombreUsuario =
      AuthService.cachedUser != null &&
          AuthService.cachedUser!.nombres.isNotEmpty
      ? '${AuthService.cachedUser!.nombres} ${AuthService.cachedUser!.apellidos}'
            .trim()
      : 'Gerencia';
  String _emailUsuario = AuthService.cachedUser?.email ?? '';

  bool _esAuditorSucursal = AuthService.esAuditorSucursalSync;
  late VistaGerencia _vistaActiva = _esAuditorSucursal
      ? VistaGerencia.inventario
      : VistaGerencia.dashboard;
  bool _sidebarOpen = true;
  bool _filtroSinTasar = false;
  bool _bellHovered = false;
  String? _filtroEstadoOrdenes;
  bool _dashboardDirty = false;

  late AnimationController _spinController;
  SilentPollingManager? _gerenciaPollingManager;
  Timer? _updateCheckTimer;

  final GlobalKey<OrdenesGerenciaViewState> _ordenesKey =
      GlobalKey<OrdenesGerenciaViewState>();
  final GlobalKey<InventarioGerenciaViewState> _inventarioKey =
      GlobalKey<InventarioGerenciaViewState>();
  final GlobalKey<BackordersGerenciaViewState> _backordersKey =
      GlobalKey<BackordersGerenciaViewState>();

  List<SucursalGerenciaModel> _listaSucursales = const [
    SucursalGerenciaModel(
      idSucursal: 1,
      nombreSucursal: 'Viña del Mar',
      esCasaMatriz: true,
    ),
    SucursalGerenciaModel(
      idSucursal: 2,
      nombreSucursal: 'Limache',
      esCasaMatriz: false,
    ),
  ];

  Future<void> _cerrarSesion() async {
    await AuthService.logout();
    if (mounted) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
    }
  }

  @override
  void initState() {
    super.initState();
    _esAuditorSucursal = AuthService.esAuditorSucursalSync;
    if (_esAuditorSucursal) {
      _vistaActiva = VistaGerencia.inventario;
    }
    _sucursalSeleccionada = widget.sucursalInicial;
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _cargarDatosIniciales();

    _gerenciaPollingManager = SilentPollingManager(
      interval: const Duration(seconds: 45),
      debugLabel: 'GerenciaPolling',
      shouldPause: () {
        final modalInventarioAbierto =
            _inventarioKey.currentState?.isModalAbierto ?? false;
        return _cargando || modalInventarioAbierto;
      },
      onPoll: () async {
        if (!mounted) return;
        if (_esAuditorSucursal) {
          if (_vistaActiva == VistaGerencia.inventario) {
            await _inventarioKey.currentState?.refrescarSilencioso();
          }
          return;
        }
        switch (_vistaActiva) {
          case VistaGerencia.dashboard:
            await _cargarDashboard(silent: true);
            break;
          case VistaGerencia.ordenes:
            await _ordenesKey.currentState?.refrescarSilencioso();
            break;
          case VistaGerencia.inventario:
            await _inventarioKey.currentState?.refrescarSilencioso();
            break;
          case VistaGerencia.backorders:
            await _backordersKey.currentState?.refrescarSilencioso();
            break;
        }
      },
    )..start();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateCheckTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          AppUpdateChecker.check(context, showIfUpToDate: false);
        }
      });
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
    // Solo recargamos si el dashboard quedó marcado como sucio por una mutación
    // y la vista visible es el Dashboard, evitando falsos refrescos al cerrar modales o cancelar diálogos.
    if (_dashboardDirty &&
        _vistaActiva == VistaGerencia.dashboard &&
        !_esAuditorSucursal) {
      _dashboardDirty = false;
      _cargarDashboard(silent: true);
    }
  }

  @override
  void dispose() {
    _updateCheckTimer?.cancel();
    routeObserver.unsubscribe(this);
    _gerenciaPollingManager?.dispose();
    // Libero explícitamente el controlador de animación según RULES.md
    _spinController.dispose();
    super.dispose();
  }

  Future<void> _cargarSucursales() async {
    try {
      final sucursales = await GerenciaService.obtenerSucursales();
      if (mounted && sucursales.isNotEmpty) {
        setState(() {
          _listaSucursales = sucursales;
        });
      }
    } catch (e) {
      debugPrint('⚠️ [GERENCIA] Error cargando sucursales dinámicas: $e');
    }
  }

  Future<void> _cargarDatosIniciales() async {
    final nombre = await AuthService.getNombreUsuario();
    final email = await AuthService.getEmailUsuario();
    final esAuditorSatelite = await AuthService.esAuditorSucursal();
    if (mounted) {
      setState(() {
        _esAuditorSucursal = esAuditorSatelite;
        if (nombre != null && nombre.trim().isNotEmpty) {
          _nombreUsuario = nombre.trim();
        }
        if (email != null && email.trim().isNotEmpty) {
          _emailUsuario = email.trim();
        }
        if (esAuditorSatelite) {
          _vistaActiva = VistaGerencia.inventario;
        }
      });
    }
    if (esAuditorSatelite) {
      await _cargarSucursales();
    } else {
      await Future.wait([_cargarSucursales(), _cargarDashboard()]);
    }
  }

  /// Cargo simultáneamente los 3 endpoints analíticos aplicando guardas de montaje.
  Future<void> _cargarDashboard({
    bool mostrarToast = false,
    bool silent = false,
  }) async {
    if (!mounted || _esAuditorSucursal) return;

    debugPrint(
      '📊 [GERENCIA-DASHBOARD] 🔄 Solicitando KPIs, métodos de pago y flujo operativo (Sucursal: ${_sucursalSeleccionada ?? "Todas"})...',
    );
    if (!silent) {
      setState(() {
        _cargando = true;
        _mensajeError = null;
        _codigoError = null;
        _detalleTecnicoError = null;
        _mostrarDetalleTecnico = false;
      });
      _spinController.repeat();
    }

    try {
      final futures = await Future.wait([
        GerenciaService.obtenerKpis(idSucursal: _sucursalSeleccionada),
        GerenciaService.obtenerResumenPagos(idSucursal: _sucursalSeleccionada),
        GerenciaService.obtenerFlujoOperativo(
          idSucursal: _sucursalSeleccionada,
        ),
      ]);

      if (!mounted) return;

      setState(() {
        _kpis = futures[0] as KpiFinancieroModel;
        _pagos = futures[1] as ResumenPagosModel;
        _flujo = futures[2] as FlujoOperativoModel;
        _cargando = false;
      });
      if (!silent) {
        _spinController.stop();
        _spinController.reset();
      }

      debugPrint(
        '📊 [GERENCIA-DASHBOARD] ✅ OK 200 - Métricas analíticas cargadas exitosamente:',
      );
      debugPrint(
        '   • Ventas Hoy: \$${_kpis?.ventasDelDia ?? 0} | Transacciones: ${_kpis?.transaccionesHoy ?? 0}',
      );
      debugPrint(
        '   • Ticket Promedio: \$${_kpis?.ticketPromedio ?? 0} | Efectivo/Electrónico: \$${_pagos?.efectivoFisico ?? 0} / \$${_pagos?.canalesElectronicos ?? 0}',
      );
      debugPrint(
        '   • Despacho Bodega: ${_flujo?.enPreparacion ?? 0} en prep | ${_flujo?.listosMostrador ?? 0} listos | Cuellos de botella: ${_flujo?.cuellosBotellaPaletizados ?? 0}',
      );

      if (mostrarToast && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Dashboard gerencial sincronizado exitosamente.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppPalette.success,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (silent) {
        debugPrint(
          '📊 [GERENCIA-DASHBOARD] ⚠️ Error en polling silencioso (ignorado): $e',
        );
        return;
      }

      String errorStr;
      String? codigoDiag;
      String? devDetails;

      if (e is CustomApiException) {
        errorStr = e.messageUser;
        codigoDiag = e.diagnosticCode;
        devDetails = e.messageDev;
      } else {
        errorStr = ApiService.limpiarMensajeExcepcion(e);
        codigoDiag = 'GERENCIA_NETWORK_ERROR';
        devDetails = e.toString();
      }

      debugPrint(
        '📊 [GERENCIA-DASHBOARD] ❌ Error al cargar dashboard: $errorStr [$codigoDiag]',
      );
      setState(() {
        _cargando = false;
        _mensajeError = errorStr;
        _codigoError = codigoDiag;
        _detalleTecnicoError = devDetails;
      });
      _spinController.stop();
      _spinController.reset();

      CustomErrorSnackbar.mostrar(
        context,
        mensaje: errorStr,
        codigoError: codigoDiag,
        onReintentar: () => _cargarDashboard(),
      );
    }
  }

  /// Refresca la vista actualmente activa (Dashboard, Órdenes, Inventario o Backorders)
  /// activando la animación de spin en el botón superior y mostrando feedback visual.
  Future<void> _refrescarVistaActiva({bool mostrarToast = false}) async {
    if (!mounted) return;

    if (_vistaActiva == VistaGerencia.dashboard) {
      await _cargarDashboard(mostrarToast: mostrarToast);
      return;
    }

    setState(() {
      _cargando = true;
      _mensajeError = null;
    });
    _spinController.repeat();

    try {
      String mensajeExito = '';
      switch (_vistaActiva) {
        case VistaGerencia.dashboard:
          break;
        case VistaGerencia.ordenes:
          await _ordenesKey.currentState?.refrescar(
            idSucursal: _sucursalSeleccionada,
            actualizarSucursal: true,
          );
          mensajeExito = 'Historial de órdenes sincronizado exitosamente.';
          break;
        case VistaGerencia.inventario:
          await _inventarioKey.currentState?.refrescar(
            idSucursal: _sucursalSeleccionada,
            actualizarSucursal: true,
          );
          mensajeExito = 'Inventario y tasación sincronizado exitosamente.';
          break;
        case VistaGerencia.backorders:
          await _backordersKey.currentState?.refrescar(
            idSucursal: _sucursalSeleccionada,
            actualizarSucursal: true,
          );
          mensajeExito = 'Ventas en verde sincronizado exitosamente.';
          break;
      }

      if (mostrarToast && mounted && mensajeExito.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mensajeExito,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppPalette.success,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ [GERENCIA] Error al refrescar vista activa: $e');
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
        _spinController.stop();
        _spinController.reset();
      }
    }
  }

  void _navegarAOrdenesConEstado(String estado) {
    setState(() {
      _filtroEstadoOrdenes = estado;
      _vistaActiva = VistaGerencia.ordenes;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ordenesKey.currentState?.aplicarFiltroEstado(estado);
    });
  }

  void _navegarAInventarioSinTasar() {
    setState(() {
      _filtroSinTasar = true;
      _vistaActiva = VistaGerencia.inventario;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inventarioKey.currentState?.aplicarFiltroSinTasar(true);
    });
  }

  String _formatearFechaHoy() {
    final ahora = DateTime.now();
    final dias = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo',
    ];
    final meses = [
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

    final diaNombre = dias[ahora.weekday - 1];
    final mesNombre = meses[ahora.month - 1];
    return '$diaNombre ${ahora.day} de $mesNombre de ${ahora.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.backgroundLight,
      body: Row(
        children: [
          // Sidebar Corporativo Deep Blue (#004c89 / AppPalette.tertiary)
          _buildSidebar(),

          // Área Principal (Topbar + Contenido Dinámico)
          Expanded(
            child: Column(
              children: [
                _buildTopbar(),
                Expanded(
                  child: IndexedStack(
                    index: _vistaActiva.index,
                    children: [
                      // 0: VistaGerencia.dashboard
                      _esAuditorSucursal
                          ? const SizedBox.shrink()
                          : _buildDashboardContent(),
                      // 1: VistaGerencia.ordenes
                      _esAuditorSucursal
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.all(24),
                              child: OrdenesGerenciaView(
                                key: _ordenesKey,
                                idSucursalInicial: _sucursalSeleccionada,
                                estadoInicial: _filtroEstadoOrdenes,
                              ),
                            ),
                      // 2: VistaGerencia.inventario
                      InventarioGerenciaView(
                        key: _inventarioKey,
                        idSucursalInicial: _sucursalSeleccionada,
                        filtroSinTasarInicial: _filtroSinTasar,
                        onStockMutado: () {
                          _dashboardDirty = true;
                          if (_vistaActiva == VistaGerencia.dashboard &&
                              !_esAuditorSucursal) {
                            _cargarDashboard(silent: true);
                          }
                        },
                      ),
                      // 3: VistaGerencia.backorders
                      _esAuditorSucursal
                          ? const SizedBox.shrink()
                          : BackordersGerenciaView(
                              key: _backordersKey,
                              idSucursalInicial: _sucursalSeleccionada,
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardContent() {
    return _cargando && _kpis == null
        ? const Center(
            child: CircularProgressIndicator(color: AppPalette.primary),
          )
        : _mensajeError != null && _kpis == null
        ? _buildErrorState()
        : RefreshIndicator(
            onRefresh: () => _cargarDashboard(mostrarToast: true),
            color: AppPalette.primary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Banner de Bienvenida y Fecha
                  _buildWelcomeBanner(),
                  const SizedBox(height: 20),

                  // Grid Superior de 4 KPIs
                  _buildKpiGrid(),
                  const SizedBox(height: 24),

                  // Bento Trío de Visualizaciones
                  _buildBentoSection(),
                ],
              ),
            ),
          );
  }

  Widget _buildSidebar() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _sidebarOpen ? 265 : 68,
      decoration: const BoxDecoration(
        color: AppPalette.tertiary,
        border: Border(right: BorderSide(color: Colors.white12, width: 1)),
      ),
      child: ClipRect(
        child: Column(
          children: [
            // Header del Sidebar con Llave Mecánica Oficial
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Icon(
                      Icons.build_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  if (_sidebarOpen) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _esAuditorSucursal
                                ? 'CONSULTA DE STOCK'
                                : 'PANEL EJECUTIVO',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _esAuditorSucursal
                                ? 'Auditoría Satélite'
                                : 'Control Ejecutivo V1',
                            style: const TextStyle(
                              color: Color(0xFFBAE6FD),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Navegación de las 4 Vistas Principales (HU 5.1 a 5.4)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 16,
                ),
                children: [
                  if (_sidebarOpen)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 8),
                      child: Text(
                        _esAuditorSucursal
                            ? 'CONSULTA DE STOCK'
                            : 'SUPERVISIÓN Y CONTROL',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),

                  if (!_esAuditorSucursal) ...[
                    // 1. Dashboard Ejecutivo
                    _buildSidebarNavItem(
                      icon: Icons.dashboard_rounded,
                      label: 'Dashboard Ejecutivo',
                      isSelected: _vistaActiva == VistaGerencia.dashboard,
                      onTap: () {
                        if (_vistaActiva != VistaGerencia.dashboard) {
                          debugPrint(
                            '🔀 [GERENCIA-NAV] 📂 Cambiando a pestaña: Dashboard Ejecutivo',
                          );
                          final needsHardLoad =
                              _kpis == null || _dashboardDirty;
                          setState(() {
                            _vistaActiva = VistaGerencia.dashboard;
                            _dashboardDirty = false;
                          });
                          if (needsHardLoad) {
                            _cargarDashboard();
                          } else {
                            _cargarDashboard(silent: true);
                          }
                        } else {
                          // Re-clic en la pestaña activa: refresca intencionalmente
                          _cargarDashboard(mostrarToast: true);
                        }
                      },
                    ),

                    const SizedBox(height: 6),

                    // 2. Historial de Órdenes
                    _buildSidebarNavItem(
                      icon: Icons.receipt_long_rounded,
                      label: 'Historial de Órdenes',
                      isSelected: _vistaActiva == VistaGerencia.ordenes,
                      onTap: () {
                        if (_vistaActiva != VistaGerencia.ordenes) {
                          debugPrint(
                            '🔀 [GERENCIA-NAV] 📂 Cambiando a pestaña: Historial de Órdenes',
                          );
                          setState(() {
                            _filtroEstadoOrdenes = null;
                            _vistaActiva = VistaGerencia.ordenes;
                          });
                          _ordenesKey.currentState?.refrescarSilencioso();
                        } else {
                          // Re-clic en la pestaña activa: refresca intencionalmente
                          _refrescarVistaActiva(mostrarToast: true);
                        }
                      },
                    ),

                    const SizedBox(height: 6),
                  ],

                  // 3. Maestro de Inventario y Tasación
                  _buildSidebarNavItem(
                    icon: Icons.inventory_2_rounded,
                    label: _esAuditorSucursal
                        ? 'Catálogo e Inventario'
                        : 'Inventario y Tasación',
                    isSelected: _vistaActiva == VistaGerencia.inventario,
                    badgeText:
                        !_esAuditorSucursal &&
                            (_flujo?.cuellosBotellaPaletizados ?? 0) > 0
                        ? '${_flujo!.cuellosBotellaPaletizados}'
                        : null,
                    onTap: () {
                      if (_vistaActiva != VistaGerencia.inventario) {
                        debugPrint(
                          '🔀 [GERENCIA-NAV] 📂 Cambiando a pestaña: Inventario y Tasación',
                        );
                        setState(() {
                          _vistaActiva = VistaGerencia.inventario;
                          _filtroSinTasar = false;
                        });
                        _inventarioKey.currentState?.refrescarSilencioso();
                      } else {
                        // Re-clic en la pestaña activa: refresca intencionalmente
                        _refrescarVistaActiva(mostrarToast: true);
                      }
                    },
                  ),

                  if (!_esAuditorSucursal) ...[
                    const SizedBox(height: 6),

                    // 4. Visor Centralizado de Backorders (Ventas en Verde)
                    _buildSidebarNavItem(
                      icon: Icons.bookmark_added_rounded,
                      label: 'Ventas en Verde',
                      isSelected: _vistaActiva == VistaGerencia.backorders,
                      badgeText: null,
                      onTap: () {
                        if (_vistaActiva != VistaGerencia.backorders) {
                          debugPrint(
                            '🔀 [GERENCIA-NAV] 📂 Cambiando a pestaña: Ventas en Verde',
                          );
                          setState(() {
                            _vistaActiva = VistaGerencia.backorders;
                          });
                          _backordersKey.currentState?.refrescarSilencioso();
                        } else {
                          // Re-clic en la pestaña activa: refresca intencionalmente
                          _refrescarVistaActiva(mostrarToast: true);
                        }
                      },
                    ),
                  ],

                  const SizedBox(height: 12),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 6),

                  // 5. Botón de Actualizaciones
                  _buildSidebarNavItem(
                    icon: Icons.system_update_alt_rounded,
                    label: 'Actualizaciones',
                    isSelected: false,
                    badgeText: null,
                    onTap: () =>
                        AppUpdateChecker.check(context, showIfUpToDate: true),
                  ),
                ],
              ),
            ),

            // Footer del Sidebar: Perfil Gerencial y Cerrar Sesión
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white12)),
                color: Colors.black12,
              ),
              child: _sidebarOpen
                  ? Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.white24,
                          child: Text(
                            _nombreUsuario.isNotEmpty
                                ? _nombreUsuario[0].toUpperCase()
                                : 'G',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _nombreUsuario,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _emailUsuario.isNotEmpty
                                    ? _emailUsuario
                                    : 'gerencia@cresal.cl',
                                style: const TextStyle(
                                  color: Color(0xFFBAE6FD),
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              FutureBuilder<String>(
                                future: AppUpdateService().getCurrentVersion(),
                                builder: (context, snapshot) {
                                  return Text(
                                    'v${snapshot.data ?? "..."}',
                                    style: const TextStyle(
                                      color: Colors.white38,
                                      fontSize: 9,
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.logout_rounded,
                            color: Color(0xFFFCA5A5),
                            size: 18,
                          ),
                          tooltip: 'Cerrar sesión',
                          onPressed: _cerrarSesion,
                        ),
                      ],
                    )
                  : Center(
                      child: Tooltip(
                        message: 'Cerrar sesión ($_nombreUsuario)',
                        child: InkWell(
                          onTap: _cerrarSesion,
                          borderRadius: BorderRadius.circular(16),
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: Colors.white24,
                            child: Text(
                              _nombreUsuario.isNotEmpty
                                  ? _nombreUsuario[0].toUpperCase()
                                  : 'G',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
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

  Widget _buildSidebarNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    String? badgeText,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? const Color(0xFF7DD3FC) : Colors.white70,
            ),
            if (_sidebarOpen) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      color: Color(0xFFBAE6FD),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopbar() {
    final cuellosBotella = _flujo?.cuellosBotellaPaletizados ?? 0;
    final saldoPendiente = _flujo?.alertasSaldoPendiente ?? 0;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(bottom: BorderSide(color: AppPalette.borderLight)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 1000;
          final isNarrow = constraints.maxWidth < 800;

          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Lado Izquierdo: Botón Colapsar Menú + Identidad Ejecutiva
              Expanded(
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _sidebarOpen
                            ? Icons.menu_open_rounded
                            : Icons.menu_rounded,
                        color: const Color(0xFF0F172A),
                        size: 22,
                      ),
                      tooltip: _sidebarOpen
                          ? 'Colapsar menú lateral'
                          : 'Expandir menú lateral',
                      onPressed: () =>
                          setState(() => _sidebarOpen = !_sidebarOpen),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppPalette.tertiary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _vistaActiva == VistaGerencia.dashboard
                            ? Icons.dashboard_customize
                            : _vistaActiva == VistaGerencia.ordenes
                            ? Icons.receipt_long
                            : _vistaActiva == VistaGerencia.inventario
                            ? Icons.inventory_2
                            : Icons.bookmark_added_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _vistaActiva == VistaGerencia.dashboard
                                ? 'CRESAL GERENCIA'
                                : _vistaActiva == VistaGerencia.ordenes
                                ? 'HISTORIAL DE ÓRDENES'
                                : _vistaActiva == VistaGerencia.inventario
                                ? (_esAuditorSucursal
                                      ? 'CATÁLOGO E INVENTARIO'
                                      : 'MAESTRO DE INVENTARIO Y TASACIÓN')
                                : 'VENTAS EN VERDE',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (!isCompact)
                            Text(
                              _vistaActiva == VistaGerencia.dashboard
                                  ? 'Dashboard Ejecutivo y Pulso Operativo'
                                  : _vistaActiva == VistaGerencia.ordenes
                                  ? 'Historial y Auditoría de Órdenes'
                                  : _vistaActiva == VistaGerencia.inventario
                                  ? (_esAuditorSucursal
                                        ? 'Consulta de stock físico y disponibilidad en Viña del Mar y sucursales'
                                        : 'Control de stock físico, ubicaciones en rack y fijación de precios comerciales')
                                  : 'Monitoreo de compras en verde',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF64748B),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Lado Derecho: Selector de Sucursal, Guía Indicadores (Icono), Botón Refrescar y Campana
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Selector Dropdown de Sucursal (Fiel a Foto 4)
                  _buildSelectorSucursales(isNarrow: isNarrow),
                  const SizedBox(width: 8),

                  // Icono en Topbar "Guía de Indicadores"
                  if (!_esAuditorSucursal) ...[
                    _buildBotonIconoGuiaIndicadores(),
                    const SizedBox(width: 8),
                  ],

                  // Botón Refrescar con Spin
                  if (isNarrow)
                    IconButton(
                      onPressed: _cargando
                          ? null
                          : () => _refrescarVistaActiva(mostrarToast: true),
                      tooltip: _cargando ? 'Actualizando...' : 'Actualizar',
                      icon: RotationTransition(
                        turns: _spinController,
                        child: const Icon(
                          Icons.sync,
                          size: 18,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: AppPalette.borderLight),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _cargando
                          ? null
                          : () => _refrescarVistaActiva(mostrarToast: true),
                      icon: RotationTransition(
                        turns: _spinController,
                        child: const Icon(Icons.sync, size: 16),
                      ),
                      label: Text(
                        _cargando ? 'Actualizando...' : 'Actualizar',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0F172A),
                        side: const BorderSide(color: AppPalette.borderLight),
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),

                  // Campana de Notificaciones Ejecutivas con Badge y Hover Rectangular
                  if (!_esAuditorSucursal) ...[
                    const SizedBox(width: 10),
                    PopupMenuButton<String>(
                      tooltip: 'Alertas y Notificaciones Ejecutivas',
                      offset: const Offset(0, 48),
                      color: Colors.white,
                      surfaceTintColor: Colors.white,
                      elevation: 6,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppPalette.borderLight),
                      ),
                      child: StatefulBuilder(
                        builder: (context, setBellHover) {
                          return MouseRegion(
                            onEnter: (_) =>
                                setBellHover(() => _bellHovered = true),
                            onExit: (_) =>
                                setBellHover(() => _bellHovered = false),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: _bellHovered
                                        ? const Color(0xFFF1F5F9)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppPalette.borderLight,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.notifications_outlined,
                                    color: Color(0xFF0F172A),
                                    size: 20,
                                  ),
                                ),
                                if (cuellosBotella > 0)
                                  Positioned(
                                    top: -4,
                                    right: -4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFDC2626),
                                        shape: BoxShape.circle,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 18,
                                        minHeight: 18,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$cuellosBotella',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                      itemBuilder: (context) => [
                        PopupMenuItem<String>(
                          value: 'tasacion',
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFB923C,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.hourglass_top,
                                  color: Color(0xFFEA580C),
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$cuellosBotella repuestos sin tasar',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const Text(
                                      'En espera de fijación de precio en bodega',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem<String>(
                          value: 'ordenes',
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFBBF24,
                                  ).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.pending_actions,
                                  color: Color(0xFFB45309),
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$saldoPendiente órdenes con saldo retenido',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const Text(
                                      'Retiro condicionado a liquidación total',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      onSelected: (val) {
                        if (_esAuditorSucursal) return;
                        if (val == 'tasacion') {
                          _navegarAInventarioSinTasar();
                        } else if (val == 'ordenes') {
                          _navegarAOrdenesConEstado('Reservada');
                        }
                      },
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // =========================================================================
  // GUÍA DE INDICADORES (KPIs)
  // =========================================================================

  /// Icono compacto en Topbar con Tooltip informativo
  Widget _buildBotonIconoGuiaIndicadores() {
    return Tooltip(
      message: 'Guía de Indicadores',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _mostrarGuiaIndicadores(context),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppPalette.borderLight),
            ),
            child: const Icon(
              Icons.help_outline_rounded,
              color: Color(0xFF0F172A),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  /// Modal explicativo institucional para la toma de decisiones gerenciales
  void _mostrarGuiaIndicadores(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Ejecutivo
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  decoration: const BoxDecoration(
                    color: AppPalette.tertiary, // Azul profundo #004C89
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.analytics_outlined,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Guía Ejecutiva de Indicadores y Métricas (KPIs)',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Definición técnica, origen de datos y fórmulas para la toma de decisiones gerenciales',
                              style: TextStyle(
                                color: Color(0xFFBAE6FD),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        tooltip: 'Cerrar guía',
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),
                // Contenido explicativo scrollable
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      _buildItemGuia(
                        icono: Icons.attach_money_rounded,
                        colorIcono: const Color(0xFF16A34A),
                        titulo: 'Facturación Hoy',
                        subtitulo:
                            'Suma bruta de ventas del día en curso (00:00 a 23:59)',
                        descripcion:
                            'Representa el monto total facturado y liquidado en el día actual en tiempo real (suma de transacciones con estado "Procesado" para órdenes no anuladas). Se actualiza de manera reactiva ante cada cobro en mesón o transferencia bancaria.',
                        formula:
                            '∑(monto_pago) para pagos Procesados en la jornada',
                      ),
                      const SizedBox(height: 14),
                      _buildItemGuia(
                        icono: Icons.calendar_month_rounded,
                        colorIcono: const Color(0xFF0284C7),
                        titulo: 'Acumulado Mes (MTD - Month to Date)',
                        subtitulo:
                            'Facturación acumulada del mes calendario actual',
                        descripcion:
                            'Mide la tracción financiera acumulada desde el día 1 del mes hasta el momento de consulta. El avance de transacciones totaliza las ventas liquidadas para proyectar el cumplimiento del presupuesto mensual.',
                        formula:
                            '∑(ventas_diarias) desde el día 1 del mes hasta la fecha actual',
                      ),
                      const SizedBox(height: 14),
                      _buildItemGuia(
                        icono: Icons.receipt_long_rounded,
                        colorIcono: const Color(0xFF7C3AED),
                        titulo: 'Ticket Promedio (Productividad Comercial)',
                        subtitulo:
                            'Venta promedio generada por cada transacción cerrada',
                        descripcion:
                            'Indica el gasto medio de los clientes en mesón o canales digitales. Sirve a la gerencia para monitorear la venta cruzada (ej: lubricantes, retenes o empaquetaduras adquiridas junto al motor o caja) y la eficacia de los vendedores.',
                        formula:
                            'Ticket Promedio = (Total Facturación Hoy) / (N° Transacciones Hoy)',
                      ),
                      const SizedBox(height: 14),
                      _buildItemGuia(
                        icono: Icons.pie_chart_outline_rounded,
                        colorIcono: const Color(0xFF0F766E),
                        titulo: 'Recaudación por Medios de Pago',
                        subtitulo:
                            'Distribución de liquidez: Efectivo vs Canales Electrónicos',
                        descripcion:
                            'Desglosa el flujo monetario según Transferencia Bancaria, Tarjeta de Débito, Tarjeta de Crédito, Efectivo y Cheque. Permite agilizar los arqueos de caja en mesón y optimizar la conciliación de extractos bancarios.',
                        formula:
                            'Porcentaje = (Monto Canal / Total Recaudado) * 100',
                      ),
                      const SizedBox(height: 14),
                      _buildItemGuia(
                        icono: Icons.shield_outlined,
                        colorIcono: const Color(0xFFEA580C),
                        titulo: 'Control de Riesgo y Alertas Operativas',
                        subtitulo:
                            'Saldos Retenidos por Cobrar y Cuellos de Botella de Tasación',
                        descripcion:
                            '• Saldos por Cobrar: Alerta preventiva sobre órdenes en estado "Reservada" donde el cliente retirará en mesón pero tiene saldo pendiente. Al hacer clic, audita directamente las órdenes en cuestión para evitar fugas de mercadería sin liquidación total.\n• Cuello de Botella Tasación: Repuestos desmontados y paletizados que carecen de precio de venta fijado en bodega.',
                        formula:
                            'Total Alertas = Saldos Pendientes Retenidos + Repuestos Sin Tasar',
                      ),
                      const SizedBox(height: 14),
                      _buildItemGuia(
                        icono: Icons.local_shipping_outlined,
                        colorIcono: const Color(0xFF0284C7),
                        titulo: 'Bodega & Flujo de Despacho',
                        subtitulo:
                            'Seguimiento logístico en vivo: Preparación, Mostrador y Courier',
                        descripcion:
                            'Audita el ciclo de vida del repuesto físico en bodega:\n1. En Preparación: Bajada del rack y embalaje con film industrial.\n2. Listo Mostrador: Esperando entrega a cliente o taller mecánico.\n3. Despacho Courier: En ruta vía Starken o Chilexpress con número de seguimiento.',
                        formula:
                            'Total en flujo = Piezas en rack + Listas en mostrador + Despachos courier',
                      ),
                    ],
                  ),
                ),
                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(20),
                    ),
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppPalette.tertiary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Entendido',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemGuia({
    required IconData icono,
    required Color colorIcono,
    required String titulo,
    required String subtitulo,
    required String descripcion,
    required String formula,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorIcono.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icono, color: colorIcono, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            descripcion,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.functions_rounded,
                  size: 14,
                  color: Color(0xFF0284C7),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    formula,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0369A1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorSucursales({bool isNarrow = false}) {
    final Map<int, ({String titulo, String subtitulo, IconData icon})>
    sucursales = {
      -1: (
        titulo: 'Todas las Sucursales',
        subtitulo: 'Consolidado general',
        icon: Icons.domain_rounded,
      ),
    };

    for (final suc in _listaSucursales) {
      sucursales[suc.idSucursal] = (
        titulo: suc.tituloDisplay,
        subtitulo: suc.subtituloDisplay,
        icon: suc.esCasaMatriz
            ? Icons.storefront_rounded
            : Icons.warehouse_rounded,
      );
    }

    final idActivo = _sucursalSeleccionada ?? -1;
    final actual = sucursales[idActivo] ?? sucursales[-1]!;

    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: PopupMenuButton<int>(
        tooltip: 'Seleccionar sucursal de auditoría',
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 8,
        constraints: const BoxConstraints(minWidth: 320, maxWidth: 390),
        shadowColor: Colors.black.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        offset: const Offset(0, 42),
        initialValue: idActivo,
        onSelected: (nuevoId) {
          final idNormalizado = nuevoId == -1 ? null : nuevoId;
          // Evita peticiones y spinners redundantes si se selecciona la misma sucursal activa
          if (idNormalizado == _sucursalSeleccionada) return;

          setState(() {
            _sucursalSeleccionada = idNormalizado;
          });
          if (_vistaActiva == VistaGerencia.dashboard && !_esAuditorSucursal) {
            _cargarDashboard();
          } else {
            _refrescarVistaActiva();
          }
        },
        itemBuilder: (context) {
          return sucursales.entries.map((entry) {
            final id = entry.key;
            final data = entry.value;
            final isSelected = id == idActivo;

            return PopupMenuItem<int>(
              value: id,
              padding: EdgeInsets.zero,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFF0F9FF)
                      : Colors.transparent,
                ),
                child: Row(
                  children: [
                    Icon(
                      data.icon,
                      size: 20,
                      color: isSelected
                          ? const Color(0xFF0284C7)
                          : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            data.titulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              color: isSelected
                                  ? const Color(0xFF0284C7)
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            data.subtitulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (isSelected)
                      const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: Color(0xFF0284C7),
                      )
                    else
                      const SizedBox(width: 18),
                  ],
                ),
              ),
            );
          }).toList();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.storefront_rounded,
                size: 16,
                color: AppPalette.primary,
              ),
              const SizedBox(width: 8),
              if (!isNarrow) ...[
                const Text(
                  'Sucursal: ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
              Flexible(
                child: Text(
                  actual.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0284C7),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.expand_more_rounded,
                size: 16,
                color: Color(0xFF64748B),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Buenos días, $_nombreUsuario',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text(
                'Resumen operativo de hoy • ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
              Text(
                _formatearFechaHoy(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // GRID DE KPIS FINANCIEROS Y EJECUTIVOS (HU-5.1)
  // =========================================================================
  // Los 3 indicadores ejecutivos principales:
  // 1. Facturación Hoy:
  //    - Fuente: backend 'ventas_del_dia' (suma real de pagos con estado Procesado del día actual).
  //    - Muestra la facturación neta liquidada y el conteo verídico de transacciones hoy.
  // 2. Acumulado Mes (MTD - Month To Date):
  //    - Fuente: backend 'acumulado_mensual_mtd' (suma histórica de pagos desde el día 1 del mes en curso a hoy).
  // 3. Ticket Promedio (Métrica de Productividad Comercial):
  //    - Fuente: backend 'ticket_promedio' (calculado dinámicamente: Ventas Hoy / Transacciones Hoy).
  //    - Utilidad gerencial: Monitorea el volumen monetario por cada orden cerrada en mesón.
  Widget _buildKpiGrid() {
    final kpis =
        _kpis ??
        const KpiFinancieroModel(
          ventasDelDia: 0,
          transaccionesHoy: 0,
          acumuladoMensualMtd: 0,
          ticketPromedio: 0,
        );

    final facturacionFmt = CurrencyFormatter.formatCLP(kpis.ventasDelDia);
    final mtdFmt = CurrencyFormatter.formatCLP(kpis.acumuladoMensualMtd);
    final ticketFmt = CurrencyFormatter.formatCLP(kpis.ticketPromedio.toInt());

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 3;
        if (constraints.maxWidth < 650) {
          crossAxisCount = 1;
        } else if (constraints.maxWidth < 950) {
          crossAxisCount = 2;
        }

        // Fijo la altura vertical Y de las tarjetas KPI a 110px mediante mainAxisExtent,
        // garantizando que no se estiren verticalmente en monitores anchos y preservando
        // la distribución visual interna original (espaciado superior e inferior limpio).
        return GridView(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 110,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            // KPI 1: Facturación Hoy (Calculado sobre ventas reales de la jornada)
            KpiCardWidget(
              titulo: 'Facturación Hoy',
              valor: facturacionFmt,
              subtitulo:
                  '${kpis.transaccionesHoy} ${kpis.transaccionesHoy == 1 ? "orden liquidada" : "órdenes liquidadas"} hoy',
            ),

            // KPI 2: Acumulado Mes (MTD)
            KpiCardWidget(
              titulo: 'Acumulado Mes (MTD)',
              valor: mtdFmt,
              subtitulo: 'Consolidado mensual acumulado',
              valorColor: AppPalette.tertiary,
            ),

            // KPI 3: Ticket Promedio (Ratio real de ventas/transacciones)
            KpiCardWidget(
              titulo: 'Ticket Promedio',
              valor: ticketFmt,
              subtitulo: 'Promedio por orden de mesón del día',
            ),
          ],
        );
      },
    );
  }

  Widget _buildBentoSection() {
    final pagos =
        _pagos ??
        const ResumenPagosModel(
          efectivoFisico: 0,
          canalesElectronicos: 0,
          desglose: [],
        );
    final flujo =
        _flujo ??
        const FlujoOperativoModel(
          enPreparacion: 0,
          listosMostrador: 0,
          enviadosCourier: 0,
          alertasSaldoPendiente: 0,
          cuellosBotellaPaletizados: 0,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1050;

        if (!isDesktop) {
          return Column(
            children: [
              SizedBox(height: 400, child: MetodosPagoChart(resumen: pagos)),
              const SizedBox(height: 16),
              SizedBox(height: 400, child: _buildBentoAlertas(flujo)),
              const SizedBox(height: 16),
              SizedBox(height: 400, child: _buildBentoFlujoDespacho(flujo)),
            ],
          );
        }

        return SizedBox(
          height: 410,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Bento 1: Medios de Pago
              Expanded(flex: 4, child: MetodosPagoChart(resumen: pagos)),
              const SizedBox(width: 16),

              // Bento 2: Control de Riesgo & Alertas
              Expanded(flex: 3, child: _buildBentoAlertas(flujo)),
              const SizedBox(width: 16),

              // Bento 3: Flujo de Despacho en Bodega
              Expanded(flex: 3, child: _buildBentoFlujoDespacho(flujo)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBentoAlertas(FlujoOperativoModel flujo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'CONTROL DE RIESGO',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Alertas Operativas',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7), // Amber 100
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${flujo.alertasSaldoPendiente + flujo.cuellosBotellaPaletizados} Activas',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Órdenes con saldo retenido y piezas sin tasar',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 16),

                // Alerta 1: Saldos por Cobrar (Clic para auditar órdenes con saldo pendiente)
                InkWell(
                  onTap: () => _navegarAOrdenesConEstado('Reservada'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFBBF24,
                            ).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.pending_actions,
                            color: Color(0xFFB45309),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Saldos por Cobrar',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF78350F),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${flujo.alertasSaldoPendiente} órdenes',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFB45309),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Retiro en mesón condicionado al pago total.',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Alerta 2: Cuellos de Botella de Tasación (Clic para tasar stock)
                InkWell(
                  onTap: _navegarAInventarioSinTasar,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFB923C,
                            ).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.hourglass_top,
                            color: Color(0xFFC2410C),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Cuello de Botella Tasación',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF7C2D12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${flujo.cuellosBotellaPaletizados} piezas',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFC2410C),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Paletizados sin precio fijado por Jefe de Ventas.',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF9A3412),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Footer Bento 2: Nivel de Riesgo Operativo dinámico según alertas activas
            const Divider(height: 16, thickness: 1, color: Color(0xFFF1F5F9)),
            Builder(
              builder: (context) {
                final totalAlertas =
                    flujo.alertasSaldoPendiente +
                    flujo.cuellosBotellaPaletizados;
                final String etiquetaRiesgo;
                final Color colorRiesgo;
                if (totalAlertas <= 6) {
                  etiquetaRiesgo = 'Controlado';
                  colorRiesgo = AppPalette.success;
                } else if (totalAlertas <= 12) {
                  etiquetaRiesgo = 'Moderado';
                  colorRiesgo = const Color(0xFFD97706);
                } else {
                  etiquetaRiesgo = 'Crítico';
                  colorRiesgo = AppPalette.error;
                }

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Nivel de Riesgo Operativo:',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      etiquetaRiesgo,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: colorRiesgo,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBentoFlujoDespacho(FlujoOperativoModel flujo) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'BODEGA & SALIDAS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: Color(0xFF64748B),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Flujo de Despacho',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: const [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color: AppPalette.success,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Flujo Normal',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Seguimiento en vivo de preparación, retiro y courier',
                  style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 16),

                // 3 Etapas Logísticas
                _buildEtapaFila(
                  numero: '1',
                  titulo: 'En Preparación (Rack)',
                  descripcion: 'Piezas bajando para embalaje',
                  conteo: flujo.enPreparacion,
                  badgeBg: const Color(0xFFFEF3C7),
                  badgeTextColor: const Color(0xFF92400E),
                  onTap: () => _navegarAOrdenesConEstado('Reservada'),
                ),
                const SizedBox(height: 10),

                _buildEtapaFila(
                  numero: '2',
                  titulo: 'Listo Mostrador',
                  descripcion: 'Esperando retiro cliente',
                  conteo: flujo.listosMostrador,
                  badgeBg: const Color(0xFFDCFCE7),
                  badgeTextColor: const Color(0xFF166534),
                  onTap: () => _navegarAOrdenesConEstado('Pagada'),
                ),
                const SizedBox(height: 10),

                _buildEtapaFila(
                  numero: '3',
                  titulo: 'Despacho Courier',
                  descripcion: 'Starken & Chilexpress en ruta',
                  conteo: flujo.enviadosCourier,
                  badgeBg: const Color(0xFFE0F2FE),
                  badgeTextColor: const Color(0xFF075985),
                  onTap: () => _navegarAOrdenesConEstado('Despachada'),
                ),
              ],
            ),

            // Footer Bento 3: Total consolidado en flujo logístico (métrica real calculada de la BD)
            const Divider(height: 24, thickness: 1, color: Color(0xFFF1F5F9)),
            Builder(
              builder: (context) {
                final totalEnFlujo =
                    flujo.enPreparacion +
                    flujo.listosMostrador +
                    flujo.enviadosCourier;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Total en flujo logístico:',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$totalEnFlujo ${totalEnFlujo == 1 ? "pieza" : "piezas"}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEtapaFila({
    required String numero,
    required String titulo,
    required String descripcion,
    required int conteo,
    required Color badgeBg,
    required Color badgeTextColor,
    VoidCallback? onTap,
  }) {
    final contenido = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    numero,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: badgeTextColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        descripcion,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              conteo.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: badgeTextColor,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return Tooltip(
        message: 'Ver órdenes en etapa "$titulo"',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: contenido,
          ),
        ),
      );
    }

    return contenido;
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 56, color: AppPalette.error),
            const SizedBox(height: 16),
            const Text(
              'No fue posible cargar el Dashboard Ejecutivo',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
              textAlign: TextAlign.center,
            ),
            if (_codigoError != null && _codigoError!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppPalette.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppPalette.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'Código: ${_codigoError!}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppPalette.error,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _mensajeError ?? 'Ocurrió un error al consultar el servidor.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
            if (_detalleTecnicoError != null &&
                _detalleTecnicoError!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    _mostrarDetalleTecnico = !_mostrarDetalleTecnico;
                  });
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    _mostrarDetalleTecnico
                        ? 'Ocultar detalle técnico ▲'
                        : 'Ver detalle técnico ▼',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppPalette.primary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
              if (_mostrarDetalleTecnico) ...[
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxWidth: 480),
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
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _cargarDashboard(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reintentar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
