import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../auth/services/auth_service.dart';
import '../../services/inventario_service.dart';
import '../../controllers/cart_controller.dart';
import 'checkout_wizard_screen.dart';
import 'catalogo_screen.dart';
import 'historial_screen.dart';
import 'bandeja_precios_screen.dart';
import '../../../../core/widgets/update_dialog.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/widgets/floating_glass_nav_bar.dart';

/// Contenedor Principal para el Mesón de Ventas.
/// Implementa un BottomNavigationBar con IndexedStack dinámico según el rol:
///   • Vendedor (id_rol == 2): 3 pestañas (Catálogo, Mis Órdenes, Carrito).
///   • Jefe de Ventas (id_rol == 6): 4 pestañas (Catálogo, Mis Órdenes, Tasación, Carrito).
class VentasMainScreen extends StatefulWidget {
  const VentasMainScreen({super.key});

  @override
  State<VentasMainScreen> createState() => _VentasMainScreenState();
}

class _VentasMainScreenState extends State<VentasMainScreen>
    with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey<CatalogoScreenState> _catalogoKey =
      GlobalKey<CatalogoScreenState>();
  final GlobalKey<HistorialScreenState> _historialKey =
      GlobalKey<HistorialScreenState>();
  final GlobalKey<BandejaPreciosScreenState> _bandejaPreciosKey =
      GlobalKey<BandejaPreciosScreenState>();
  int _currentIndex = 0;
  String? _userRol = AuthService.cachedUser?.nombreRol;
  int? _idRol = AuthService.cachedUser?.idRol;
  String? _userSucursal;
  int _pendientesTasacionCount = 0;
  Timer? _updateCheckTimer;
  bool _isAnyDrawerOpen = false;

  void _handleEndDrawerChanged(bool isOpen) {
    if (_isAnyDrawerOpen != isOpen && mounted) {
      setState(() {
        _isAnyDrawerOpen = isOpen;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargarDatosUsuario();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateCheckTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          AppUpdateChecker.check(context, showIfUpToDate: false);
        }
      });
    });
  }

  @override
  void dispose() {
    _updateCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      CartController.instance.reconciliarConBackend();
    }
  }

  Future<void> _cargarDatosUsuario() async {
    final rol = await AuthService.getRol();
    final idRol = await AuthService.getIdRol();
    final sucursal = await AuthService.getNombreSucursal();

    if (mounted) {
      setState(() {
        _userRol = rol;
        _idRol = idRol;
        _userSucursal = sucursal;
      });
      _actualizarPendientesTasacion();
    }
  }

  Future<void> _actualizarPendientesTasacion() async {
    if (!_esJefeVentas) return;
    try {
      final pendientes = await InventarioService.obtenerPendientesPrecio();
      if (mounted) {
        setState(() {
          _pendientesTasacionCount = pendientes.length;
        });
      }
    } catch (_) {
      // Ignorar errores transitorios de red
    }
  }

  bool get _esJefeVentas =>
      _idRol == 6 ||
      _userRol?.toLowerCase() == 'jefe de ventas' ||
      _userRol?.toLowerCase() == 'auditor';

  bool get _puedeGestionarEntregas {
    if (_idRol == 7) return false;
    final rLower = _userRol?.trim().toLowerCase() ?? '';
    if (rLower == 'vendedoronline' || rLower == 'vendedor online') return false;

    return _idRol == 2 ||
        _idRol == 6 ||
        rLower == 'vendedor' ||
        rLower == 'jefe de ventas' ||
        rLower == 'auditor';
  }

  String get _rolLabel {
    if (_userRol != null && _userRol!.trim().isNotEmpty) {
      final rLower = _userRol!.trim().toLowerCase();
      if (rLower == 'vendedoronline' || rLower == 'vendedor online') {
        return 'VENDEDOR ONLINE';
      }
      return _userRol!.toUpperCase();
    }
    if (_idRol == 7) return 'VENDEDOR ONLINE';
    if (_idRol == 6) return 'JEFE DE VENTAS';
    return 'VENDEDOR';
  }

  // ── Cerrar Sesión ──────────────────────────────────────────────────────────

  Future<void> _logout() async {
    Navigator.of(context).pop(); // Cierra el Drawer

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Cerrar sesión', style: AppTypography.title),
        content: const Text(
          '¿Estás seguro de que deseas cerrar sesión?',
          style: AppTypography.small,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: AppTypography.button.copyWith(color: AppPalette.neutral),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'CERRAR SESIÓN',
              style: AppTypography.button.copyWith(color: AppPalette.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await AuthService.clearToken();

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  // ── Menú Lateral (Drawer) ─────────────────────────────────────────────────

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: AppPalette.surface,
      child: Column(
        children: [
          // ── Encabezado de perfil ─────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            decoration: const BoxDecoration(
              color: AppPalette.background,
              border: Border(
                bottom: BorderSide(color: AppPalette.surface, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar de usuario
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppPalette.primary,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppPalette.primary.withValues(alpha: 0.35),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person,
                    color: AppPalette.textPrimary,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _rolLabel,
                  style: AppTypography.title.copyWith(
                    fontSize: 15,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _userSucursal != null && _userSucursal!.isNotEmpty
                      ? _userSucursal!
                      : 'Sucursal Central',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // ── Opciones de menú ─────────────────────────────────────────────
          if (_puedeGestionarEntregas)
            _buildDrawerItem(
              icon: Icons.local_shipping_outlined,
              label: 'ENTREGAS Y ENVÍOS',
              onTap: () {
                Navigator.of(context).pop(); // Cierra el Drawer
                Navigator.of(context).pushNamed('/entregas-envios');
              },
            ),
          _buildDrawerItem(
            icon: Icons.confirmation_number_outlined,
            label: 'TICKET',
            onTap: () {
              Navigator.of(context).pop(); // Cierra el Drawer
              Navigator.of(context).pushNamed('/tickets');
            },
          ),
          _buildDrawerItem(
            icon: Icons.settings_outlined,
            label: 'CONFIGURACIÓN',
            onTap: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Módulo de Configuración en desarrollo'),
                ),
              );
            },
          ),
          _buildDrawerItem(
            icon: Icons.system_update_alt_rounded,
            label: 'BUSCAR ACTUALIZACIONES',
            onTap: () {
              Navigator.of(context).pop();
              AppUpdateChecker.check(context, showIfUpToDate: true);
            },
          ),

          const Spacer(),

          // Versión actual de la app
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: FutureBuilder<String>(
              future: AppUpdateService().getCurrentVersion(),
              builder: (context, snapshot) {
                return Text(
                  'Cresal App v${snapshot.data ?? "..."}',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondary.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                );
              },
            ),
          ),

          // ── Botón de Cerrar Sesión (anclado en la parte inferior) ─────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, size: 20),
                label: Text(
                  'CERRAR SESIÓN',
                  style: AppTypography.button.copyWith(
                    fontSize: 14,
                    letterSpacing: 0.8,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.error,
                  foregroundColor: AppPalette.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? badgeColor,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(
        icon,
        color: badgeColor ?? AppPalette.textPrimary,
        size: 22,
      ),
      title: Text(
        label,
        style: AppTypography.body.copyWith(
          letterSpacing: 1.0,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: badgeColor ?? AppPalette.textPrimary,
        ),
      ),
      trailing: badgeColor != null
          ? Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
            )
          : null,
      onTap: onTap,
    );
  }

  // ── Construcción Dinámica de Pestañas ──────────────────────────────────────

  List<Widget> _buildTabs() {
    final tabs = <Widget>[
      CatalogoScreen(
        key: _catalogoKey,
        onOpenMenuDrawer: () => _scaffoldKey.currentState?.openDrawer(),
        onEndDrawerChanged: _handleEndDrawerChanged,
      ),
      HistorialScreen(
        key: _historialKey,
        onOpenMenuDrawer: () => _scaffoldKey.currentState?.openDrawer(),
        onRefreshCatalogo: () => _catalogoKey.currentState?.refrescarCatalogo(),
        onEndDrawerChanged: _handleEndDrawerChanged,
      ),
    ];

    if (_esJefeVentas) {
      tabs.add(
        BandejaPreciosScreen(
          key: _bandejaPreciosKey,
          onOpenMenuDrawer: () => _scaffoldKey.currentState?.openDrawer(),
          onRefreshCatalogo: () =>
              _catalogoKey.currentState?.refrescarCatalogo(),
        ),
      );
    }

    tabs.add(
      CheckoutWizardScreen(
        onOpenMenuDrawer: () => _scaffoldKey.currentState?.openDrawer(),
        onNavigateToCatalogo: () {
          _catalogoKey.currentState?.refrescarCatalogo();
          setState(() => _currentIndex = 0);
        },
      ),
    );

    return tabs;
  }

  List<FloatingGlassNavItem> _buildNavItems(int totalItems) {
    final items = <FloatingGlassNavItem>[
      const FloatingGlassNavItem(
        icon: Icons.storefront_outlined,
        activeIcon: Icons.storefront,
        label: 'Catálogo',
      ),
      const FloatingGlassNavItem(
        icon: Icons.receipt_long_outlined,
        activeIcon: Icons.receipt_long,
        label: 'Mis Órdenes',
      ),
    ];

    if (_esJefeVentas) {
      items.add(
        FloatingGlassNavItem(
          icon: Icons.price_change_outlined,
          activeIcon: Icons.price_change,
          label: 'Tasación',
          badgeCount: _pendientesTasacionCount,
        ),
      );
    }

    items.add(
      FloatingGlassNavItem(
        icon: Icons.shopping_cart_outlined,
        activeIcon: Icons.shopping_cart,
        label: 'Carrito',
        badgeCount: totalItems,
      ),
    );

    return items;
  }

  // ── Construcción de la Vista ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final tabs = _buildTabs();
    final safeIndex = _currentIndex.clamp(0, tabs.length - 1);
    final mediaQuery = MediaQuery.of(context);

    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: mediaQuery.textScaler.clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.15,
        ),
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppPalette.background,
        drawer: _buildDrawer(context),
        body: Stack(
          children: [
            Positioned.fill(
              child: IndexedStack(index: safeIndex, children: tabs),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              left: 0,
              right: 0,
              bottom: _isAnyDrawerOpen ? -110.0 : 0.0,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                opacity: _isAnyDrawerOpen ? 0.0 : 1.0,
                child: IgnorePointer(
                  ignoring: _isAnyDrawerOpen,
                  child: ListenableBuilder(
                    listenable: CartController.instance,
                    builder: (context, _) {
                      final totalItems = CartController.instance.totalItems;
                      final navItems = _buildNavItems(totalItems);

                      return FloatingGlassNavBar(
                        currentIndex: safeIndex,
                        items: navItems,
                        onTap: (index) {
                          setState(() {
                            _currentIndex = index;
                          });
                          _actualizarPendientesTasacion();
                          if (index == 0) {
                            _catalogoKey.currentState?.refrescarCatalogoSilencioso();
                          } else if (index == 1) {
                            _historialKey.currentState?.refrescarSilencioso();
                          } else if (_esJefeVentas && index == 2) {
                            _bandejaPreciosKey.currentState?.refrescarSilencioso();
                          } else if (index == tabs.length - 1) {
                            CartController.instance.reconciliarConBackend();
                          }
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}
