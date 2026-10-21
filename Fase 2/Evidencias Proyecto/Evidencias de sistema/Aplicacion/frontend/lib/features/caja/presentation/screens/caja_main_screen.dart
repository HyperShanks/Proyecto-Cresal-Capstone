import 'package:flutter/material.dart';
import '../../../../core/routes/route_observer.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/widgets/cresal_logo.dart';
import '../../../auth/services/auth_service.dart';
import '../../../tickets/presentation/widgets/soporte_desktop_view.dart';
import '../providers/caja_provider.dart';
import '../widgets/caja_drawer.dart';
import '../widgets/bandeja_cobros_panel.dart';
import '../widgets/panel_detalle_cobro.dart';
import 'historial_caja_screen.dart';
import '../../../../core/services/silent_polling_manager.dart';
import '../../../../core/widgets/update_dialog.dart';
import '../../../../core/services/app_update_service.dart';

/// Contenedor principal de escritorio para el Módulo de Caja (CRES-213 / CRES-214).
/// Implementa Sidebar Dinámico Colapsable (265px / 68px) y Grid 4/12 + 8/12 Master-Detail.
class CajaMainScreen extends StatefulWidget {
  final CajaProvider? provider;

  const CajaMainScreen({super.key, this.provider});

  @override
  State<CajaMainScreen> createState() => _CajaMainScreenState();
}

class _CajaMainScreenState extends State<CajaMainScreen> with RouteAware {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<HistorialCajaScreenState> _historialKey =
      GlobalKey<HistorialCajaScreenState>();
  late final CajaProvider _cajaProvider;
  bool _providerInterno = false;

  bool _sidebarOpen = true;
  int _selectedNavIndex = 0; // 0: Caja, 1: Historial
  String _cajeraNombre =
      AuthService.cachedUser != null &&
          AuthService.cachedUser!.nombres.isNotEmpty
      ? '${AuthService.cachedUser!.nombres} ${AuthService.cachedUser!.apellidos}'
            .trim()
      : 'Operario de Caja';
  String _sucursalNombre = 'Sucursal Activa';
  int _idSucursal = AuthService.cachedUser?.idSucursal ?? 1;
  SilentPollingManager? _cajaPollingManager;

  @override
  void initState() {
    super.initState();

    if (widget.provider != null) {
      _cajaProvider = widget.provider!;
      _providerInterno = false;
    } else {
      _cajaProvider = CajaProvider();
      _providerInterno = true;
    }

    _cargarDatosCajera();

    _cajaPollingManager = SilentPollingManager(
      interval: const Duration(seconds: 3),
      debugLabel: 'CajaPolling',
      shouldPause: () {
        if (_selectedNavIndex == 0) {
          return _cajaProvider.isProcesandoCobro ||
              _cajaProvider.pagosDivididos.isNotEmpty;
        } else if (_selectedNavIndex == 1) {
          return _historialKey.currentState?.isModalAbierto ?? false;
        }
        return true;
      },
      onPoll: () async {
        if (!mounted) return;
        if (_selectedNavIndex == 0) {
          await _cajaProvider.cargarCobrosPendientesSilencioso(
            sucursalId: _idSucursal,
          );
        } else if (_selectedNavIndex == 1) {
          _historialKey.currentState?.refrescarSilencioso();
        }
      },
    )..start();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppUpdateChecker.check(context, showIfUpToDate: false);
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
    // SPEC-HU-TAREA-21: Los modales de auditoría (como ver detalle de una orden) son de solo lectura
    // y no deben disparar recargas agresivas ni reseteos de página.
    // Solo si estamos en la bandeja de cobros y no hay operación activa, sincronizamos en background.
    if (_selectedNavIndex == 0 &&
        !_cajaProvider.isProcesandoCobro &&
        _cajaProvider.pagosDivididos.isEmpty) {
      _cajaProvider.cargarCobrosPendientesSilencioso(sucursalId: _idSucursal);
    }
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _cajaPollingManager?.dispose();
    if (_providerInterno) {
      _cajaProvider.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarDatosCajera() async {
    final nombre = await AuthService.getNombreUsuario();
    final sucursal = await AuthService.getNombreSucursal();
    final sucursalId = await AuthService.getSucursalId();

    if (!mounted) return;

    setState(() {
      if (nombre != null && nombre.isNotEmpty) {
        _cajeraNombre = nombre;
      }
      if (sucursal != null && sucursal.isNotEmpty) {
        _sucursalNombre = sucursal;
      }
      if (sucursalId != null) {
        _idSucursal = sucursalId;
      }
    });

    _cajaProvider.cargarCobrosPendientes(sucursalId: _idSucursal);
  }

  Future<void> _handleLogout() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppPalette.surfaceLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: AppPalette.neutral.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppPalette.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: AppPalette.error,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Cerrar Sesión',
                style: AppTypography.title.copyWith(
                  color: AppPalette.textPrimaryLight,
                ),
              ),
            ],
          ),
          content: Text(
            '¿Está seguro de que desea cerrar la sesión del turno de caja actual?',
            style: AppTypography.body.copyWith(
              color: AppPalette.textPrimaryLight,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'CANCELAR',
                style: AppTypography.button.copyWith(
                  color: AppPalette.textSecondaryLight,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'CERRAR SESIÓN',
                style: AppTypography.button.copyWith(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _cajaProvider,
      builder: (context, _) {
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppPalette.backgroundLight,
          drawer: CajaDrawer(
            selectedIndex: _selectedNavIndex,
            onSectionSelected: (index) {
              setState(() {
                _selectedNavIndex = index;
              });
              if (index == 0) {
                if (_cajaProvider.cobros.isEmpty) {
                  _cajaProvider.cargarCobrosPendientes(sucursalId: _idSucursal);
                } else {
                  _cajaProvider.cargarCobrosPendientesSilencioso(
                    sucursalId: _idSucursal,
                  );
                }
              } else if (index == 1) {
                _historialKey.currentState?.refrescarSilencioso();
              }
            },
          ),
          body: SafeArea(
            child: Row(
              children: [
                // ── 1. SIDEBAR DINÁMICO COLAPSABLE (265px / 68px) ──
                _buildSidebar(),

                // ── 2. ÁREA DE CONTENIDO PRINCIPAL ──
                Expanded(
                  child: Column(
                    children: [
                      _buildHeader(),
                      Expanded(
                        child: IndexedStack(
                          index: _selectedNavIndex.clamp(0, 2),
                          children: [
                            _buildBandejaCobrosView(),
                            _buildHistorialPagosView(),
                            const SoporteDesktopView(),
                          ],
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

  Widget _buildSidebar() {
    final width = _sidebarOpen ? 265.0 : 68.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: width,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: AppPalette.tertiary,
        border: Border(right: BorderSide(color: Colors.white12, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              // Header del Sidebar
              Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.white12)),
                ),
                child: Row(
                  children: [
                    const CresalLogo(size: 38, showGlow: false),
                    if (_sidebarOpen) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'MÓDULO DE CAJA',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Terminal POS & Cobros',
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

              // Navegación Vertical
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 10,
                  ),
                  children: [
                    if (_sidebarOpen)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 8),
                        child: Text(
                          'OPERACIONES DE CAJA',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    _buildSidebarItem(
                      icon: Icons.point_of_sale_rounded,
                      title: 'Caja',
                      subtitle: 'Bandeja de Cobros',
                      isSelected: _selectedNavIndex == 0,
                      onTap: () {
                        setState(() {
                          _selectedNavIndex = 0;
                        });
                        if (_cajaProvider.cobros.isEmpty) {
                          _cajaProvider.cargarCobrosPendientes(
                            sucursalId: _idSucursal,
                          );
                        } else {
                          _cajaProvider.cargarCobrosPendientesSilencioso(
                            sucursalId: _idSucursal,
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 6),
                    _buildSidebarItem(
                      icon: Icons.history_rounded,
                      title: 'Historial',
                      subtitle: 'Historial de Pagos',
                      isSelected: _selectedNavIndex == 1,
                      onTap: () {
                        setState(() {
                          _selectedNavIndex = 1;
                        });
                        _historialKey.currentState?.refrescarSilencioso();
                      },
                    ),
                    const SizedBox(height: 6),
                    _buildSidebarItem(
                      icon: Icons.contact_support_rounded,
                      title: 'Soporte',
                      subtitle: 'Tickets de Soporte',
                      isSelected: _selectedNavIndex == 2,
                      onTap: () {
                        setState(() {
                          _selectedNavIndex = 2;
                        });
                      },
                    ),
                    const SizedBox(height: 6),
                    _buildSidebarItem(
                      icon: Icons.system_update_alt_rounded,
                      title: 'Actualizar',
                      subtitle: 'Buscar Actualizaciones',
                      isSelected: false,
                      onTap: () {
                        AppUpdateChecker.check(context, showIfUpToDate: true);
                      },
                    ),
                  ],
                ),
              ),

              // Footer de Cajera & Logout
              _buildSidebarFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebarItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final itemContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.white.withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: _sidebarOpen
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
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
                title,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: _sidebarOpen
            ? itemContent
            : Tooltip(message: '$title - $subtitle', child: itemContent),
      ),
    );
  }

  Widget _buildSidebarFooter() {
    final displayName = _cajeraNombre;
    final initialLetter = _cajeraNombre.isNotEmpty
        ? _cajeraNombre[0].toUpperCase()
        : 'C';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                    initialLetter,
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text(
                        'Operario de Caja',
                        style: TextStyle(
                          color: Color(0xFFBAE6FD),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
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
                  onPressed: _handleLogout,
                ),
              ],
            )
          : Center(
              child: Tooltip(
                message: 'Cerrar sesión ($displayName)',
                child: InkWell(
                  onTap: _handleLogout,
                  borderRadius: BorderRadius.circular(16),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white24,
                    child: Text(
                      initialLetter,
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
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppPalette.surfaceLight,
        border: Border(
          bottom: BorderSide(
            color: AppPalette.neutral.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Botón Hamburguesa para Colapsar/Expandir Sidebar
          IconButton(
            icon: Icon(
              _sidebarOpen ? Icons.menu_open_rounded : Icons.menu_rounded,
              color: AppPalette.textPrimaryLight,
              size: 22,
            ),
            tooltip: _sidebarOpen
                ? 'Colapsar menú lateral'
                : 'Expandir menú lateral',
            onPressed: () {
              setState(() {
                _sidebarOpen = !_sidebarOpen;
              });
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _selectedNavIndex == 0
                  ? 'Bandeja de Cobros'
                  : _selectedNavIndex == 1
                  ? 'Historial de Pagos'
                  : 'Soporte Técnico',
              style: AppTypography.title.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimaryLight,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          // Badge Sucursal Activa
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppPalette.backgroundLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppPalette.neutral.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.store_rounded,
                  size: 15,
                  color: AppPalette.primary,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _sucursalNombre,
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textPrimaryLight,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Campana de Notificaciones
          Container(
            decoration: BoxDecoration(
              color: AppPalette.backgroundLight,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppPalette.neutral.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: IconButton(
              icon: const Icon(
                Icons.notifications_none_rounded,
                size: 20,
                color: AppPalette.textSecondaryLight,
              ),
              tooltip: 'Notificaciones del turno',
              onPressed: () {},
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBandejaCobrosView() {
    // ── Proporciones Master-Detail (Desktop Grid: flex 4 / flex 8) ──
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Columna Izquierda: Bandeja de Cobros (4/12 de ancho)
        Expanded(flex: 4, child: BandejaCobrosPanel(provider: _cajaProvider)),
        // Columna Derecha: Panel de Detalle y Cobro (8/12 de ancho)
        Expanded(flex: 8, child: PanelDetalleCobro(provider: _cajaProvider)),
      ],
    );
  }

  Widget _buildHistorialPagosView() {
    return HistorialCajaScreen(key: _historialKey, sucursalId: _idSucursal);
  }
}
