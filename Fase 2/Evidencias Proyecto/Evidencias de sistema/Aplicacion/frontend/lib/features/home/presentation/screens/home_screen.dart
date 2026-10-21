import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../routes/app_routes.dart';
import '../../../auth/services/auth_service.dart';
import '../../../alertas/services/bodega_polling_service.dart';
import '../../../paletizado/services/paletizado_service.dart';
import '../../../../core/widgets/update_dialog.dart';
import '../../../../core/services/app_update_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HOME SCREEN — Panel principal de Bodega (Terminal Bodega) protegido por sesión
// ─────────────────────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  final PaletizadoService? paletizadoService;
  const HomeScreen({super.key, this.paletizadoService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _userRol = AuthService.cachedUser?.nombreRol;
  String? _userSucursal;
  String? _userNombre = AuthService.cachedUser != null && AuthService.cachedUser!.nombres.isNotEmpty
      ? '${AuthService.cachedUser!.nombres} ${AuthService.cachedUser!.apellidos}'.trim()
      : null;
  int? _userSucursalId = AuthService.cachedUser?.idSucursal;

  final TextEditingController _paletizadoIngresoController =
      TextEditingController();
  final FocusNode _paletizadoFocusNode = FocusNode();
  bool _isSearchingPaletizado = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _guardRoute();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppUpdateChecker.check(context, showIfUpToDate: false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BodegaPollingService.instance.detenerPolling();
    _paletizadoIngresoController.dispose();
    _paletizadoFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cargarConteoTareas();
    }
  }

  Future<void> _guardRoute() async {
    final token = await AuthService.getToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      Navigator.of(context).pushReplacementNamed('/login');
      return;
    }

    final idRol = await AuthService.getIdRol();
    if (!mounted) return;

    final targetRoute = AppRoutes.getHomeRouteForRole(idRol);
    if (targetRoute != AppRoutes.home) {
      Navigator.of(context).pushReplacementNamed(targetRoute);
      return;
    }

    final rol = await AuthService.getRol();
    final sucursal = await AuthService.getNombreSucursal();
    final nombre = await AuthService.getNombreUsuario();
    final sucursalId = await AuthService.getSucursalId();

    if (mounted) {
      setState(() {
        _userRol = rol;
        _userSucursal = sucursal;
        _userNombre = nombre;
        _userSucursalId = sucursalId;
      });
      _iniciarServicioPolling(sucursalId: sucursalId);
    }
  }

  Future<void> _iniciarServicioPolling({int? sucursalId}) async {
    final targetSucursalId = sucursalId ?? await AuthService.getSucursalId();
    BodegaPollingService.instance.iniciarPolling(sucursalId: targetSucursalId);
  }

  Future<void> _cargarConteoTareas() async {
    final targetSucursalId =
        _userSucursalId ?? await AuthService.getSucursalId();
    await BodegaPollingService.instance.procesarCiclo(
      sucursalId: targetSucursalId,
    );
  }

  String _getNombreSaludo() {
    if (_userNombre == null || _userNombre!.trim().isEmpty) return 'Operador';
    final parts = _userNombre!.trim().split(' ');
    return parts.first;
  }

  Future<void> _logout() async {
    Navigator.of(context).pop();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Cerrar sesión', style: AppTypography.title),
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
    BodegaPollingService.instance.reset();
    await AuthService.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        FocusScope.of(context).unfocus();
        _paletizadoFocusNode.unfocus();
      },
      child: Scaffold(
        onDrawerChanged: (isOpened) {
          FocusScope.of(context).unfocus();
          _paletizadoFocusNode.unfocus();
        },
        backgroundColor: AppPalette.background,
        appBar: _buildAppBar(),
        drawer: _buildDrawer(context),
        body: _buildBody(context),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppPalette.surface,
      foregroundColor: AppPalette.textPrimary,
      elevation: 0,
      title: Text(
        'Terminal Bodega',
        style: AppTypography.title.copyWith(fontSize: 17),
      ),
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu, color: AppPalette.textPrimary),
          onPressed: () {
            FocusScope.of(context).unfocus();
            _paletizadoFocusNode.unfocus();
            Scaffold.of(context).openDrawer();
          },
          tooltip: 'Menú',
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final nombreCompleto =
        (_userNombre != null && _userNombre!.trim().isNotEmpty)
        ? _userNombre!.trim()
        : (_userRol != null && _userRol!.isNotEmpty
              ? _userRol!.toUpperCase()
              : 'OPERADOR');
    final sucursal = (_userSucursal != null && _userSucursal!.trim().isNotEmpty)
        ? _userSucursal!.trim()
        : 'Sucursal Central';

    return Drawer(
      backgroundColor: AppPalette.surface,
      child: Column(
        children: [
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
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppPalette.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.person,
                    color: AppPalette.textPrimary,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  nombreCompleto,
                  style: AppTypography.title.copyWith(
                    fontSize: 15,
                    letterSpacing: 0.8,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _userRol != null && _userRol!.isNotEmpty
                      ? _userRol!.toUpperCase()
                      : 'OPERADOR DE BODEGA',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
                Text(
                  sucursal,
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _buildDrawerItem(
            icon: Icons.confirmation_number_outlined,
            label: 'TICKET',
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/tickets');
            },
          ),
          _buildDrawerItem(
            icon: Icons.settings_outlined,
            label: 'CONFIGURACIÓN',
            onTap: () => Navigator.of(context).pop(),
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
          FutureBuilder<String>(
            future: AppUpdateService().getCurrentVersion(),
            builder: (context, snapshot) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Cresal App v${snapshot.data ?? "..."}',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondary.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: AppPalette.primary, size: 22),
      title: Text(
        label,
        style: AppTypography.button.copyWith(fontSize: 14, letterSpacing: 1.0),
      ),
      onTap: () {
        _paletizadoFocusNode.unfocus();
        onTap();
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _buildBody(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOperativeHeader(),
            const SizedBox(height: 20),
            _buildHeroAlertaCard(context),
            const SizedBox(height: 24),
            Text(
              'ACCIONES FRECUENTES',
              style: AppTypography.cardTitle.copyWith(
                fontSize: 12,
                color: AppPalette.textSecondary,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            _buildFrequentActionsGrid(context),
            const SizedBox(height: 24),
            Text(
              'OPERACIÓN DE PALETIZADO',
              style: AppTypography.cardTitle.copyWith(
                fontSize: 12,
                color: AppPalette.textSecondary,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            _buildPaletizadoDirectoCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildOperativeHeader() {
    final saludoNombre = _getNombreSaludo();
    final sucursalTexto =
        (_userSucursal != null && _userSucursal!.trim().isNotEmpty)
        ? _userSucursal!.trim()
        : 'Sucursal Central';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hola, $saludoNombre 👋',
                style: AppTypography.headline.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                (_userRol != null &&
                        _userRol!.trim().isNotEmpty &&
                        _userRol != 'Bodeguero')
                    ? _userRol!.trim()
                    : 'Operador de Bodega',
                style: AppTypography.small.copyWith(
                  color: AppPalette.textSecondary,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppPalette.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppPalette.primary.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                color: AppPalette.primary,
                size: 15,
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  '📍 $sucursalTexto',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroAlertaCard(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: BodegaPollingService.instance.totalPendientesNotifier,
      builder: (context, totalPendientes, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: BodegaPollingService.instance.tieneTrasladosNotifier,
          builder: (context, tieneTraslados, _) {
            final tieneTareas = totalPendientes > 0;
            return Material(
              color: AppPalette.surface,
              borderRadius: BorderRadius.circular(14),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () async {
                  _paletizadoFocusNode.unfocus();
                  await Navigator.pushNamed(context, '/alertas');
                  _cargarConteoTareas();
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: tieneTareas
                          ? AppPalette.secondary
                          : AppPalette.success.withValues(alpha: 0.4),
                      width: tieneTareas ? 2.0 : 1.2,
                    ),
                    color: tieneTareas
                        ? AppPalette.secondary.withValues(alpha: 0.07)
                        : AppPalette.success.withValues(alpha: 0.03),
                  ),
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: tieneTareas
                              ? AppPalette.secondary.withValues(alpha: 0.18)
                              : AppPalette.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          tieneTareas
                              ? (tieneTraslados
                                    ? Icons.warning_amber_rounded
                                    : Icons.notifications_active_rounded)
                              : Icons.check_circle_outline_rounded,
                          color: tieneTareas
                              ? AppPalette.secondary
                              : AppPalette.success,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ALERTA TAREAS',
                              style: AppTypography.cardTitle.copyWith(
                                fontSize: 14,
                                letterSpacing: 0.8,
                                color: tieneTareas
                                    ? AppPalette.secondary
                                    : AppPalette.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tieneTareas
                                  ? (tieneTraslados
                                        ? 'Requiere atención inmediata • Incluye traslados prioritarios'
                                        : 'Requiere atención inmediata')
                                  : 'Sin tareas pendientes en sucursal',
                              style: AppTypography.small.copyWith(
                                fontSize: 12,
                                color: tieneTareas
                                    ? AppPalette.textPrimary
                                    : AppPalette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (tieneTareas) ...[
                        Container(
                          key: const Key('home_badge_alertas'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppPalette.secondary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            totalPendientes.toString(),
                            style: const TextStyle(
                              color: AppPalette.background,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: tieneTareas
                            ? AppPalette.secondary
                            : AppPalette.neutral,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _ejecutarBusquedaPaletizadoDirecto() async {
    final folio = _paletizadoIngresoController.text.trim();
    if (folio.isEmpty) {
      return; // Validación Vacía: no realiza ninguna petición HTTP
    }

    setState(() => _isSearchingPaletizado = true);

    final service = widget.paletizadoService ?? PaletizadoService();
    final resultado = await service.consultarIngresoParaPaletizado(folio);

    if (!mounted) return;
    setState(() => _isSearchingPaletizado = false);

    if (resultado.exitoso) {
      _paletizadoFocusNode.unfocus();
      _paletizadoIngresoController.clear();
      Navigator.pushNamed(context, '/paletizado', arguments: folio);
    } else {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resultado.mensajeError ?? 'Error al consultar número de ingreso.',
          ),
          backgroundColor: resultado.statusCode == 404
              ? AppPalette.error
              : (resultado.statusCode == 400
                    ? AppPalette.secondary
                    : AppPalette.error),
        ),
      );

      // 1. Activo No Encontrado (404): Mantener foco en input para corrección rápida
      if (resultado.statusCode == 404) {
        _paletizadoFocusNode.requestFocus();
      }
    }
  }

  Widget _buildFrequentActionsGrid(BuildContext context) {
    return _buildActionCard(
      context: context,
      title: 'Buscador de Inventario',
      subtitle: 'Consulta rápida por SKU, QR, Pasillo o Modelo',
      icon: Icons.search_rounded,
      onTap: () => Navigator.pushNamed(context, '/buscador'),
    );
  }

  Widget _buildPaletizadoDirectoCard(BuildContext context) {
    return Material(
      color: AppPalette.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppPalette.primary.withValues(alpha: 0.25),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppPalette.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: AppPalette.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      _paletizadoFocusNode.unfocus();
                      Navigator.pushNamed(context, '/paletizado');
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Paletizado de Piezas',
                          style: AppTypography.title.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Validación OCR o selección manual del N° de ingreso',
                          style: AppTypography.small.copyWith(
                            fontSize: 11,
                            color: AppPalette.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    _paletizadoFocusNode.unfocus();
                    Navigator.pushNamed(context, '/paletizado');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    child: Text(
                      'Manual >',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 40,
              child: TextField(
                key: const Key('input_numero_ingreso_home'),
                controller: _paletizadoIngresoController,
                focusNode: _paletizadoFocusNode,
                onTapOutside: (_) {
                  _paletizadoFocusNode.unfocus();
                },
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                  color: AppPalette.textPrimary,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  hintText: 'Búsqueda rápida N° Ingreso',
                  hintStyle: const TextStyle(
                    color: AppPalette.textSecondary,
                    fontSize: 12,
                  ),
                  prefixIcon: const Icon(
                    Icons.tag,
                    color: AppPalette.primary,
                    size: 18,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  suffixIcon: _isSearchingPaletizado
                      ? const Padding(
                          padding: EdgeInsets.all(10.0),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppPalette.primary,
                            ),
                          ),
                        )
                      : IconButton(
                          key: const Key('btn_buscar_paletizado_home'),
                          icon: const Icon(
                            Icons.search,
                            color: AppPalette.primary,
                            size: 20,
                          ),
                          onPressed: _ejecutarBusquedaPaletizadoDirecto,
                          tooltip: 'Buscar ingreso',
                          padding: EdgeInsets.zero,
                        ),
                  filled: true,
                  fillColor: AppPalette.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: AppPalette.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: AppPalette.primary.withValues(alpha: 0.2),
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
                onSubmitted: (_) => _ejecutarBusquedaPaletizadoDirecto(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppPalette.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _paletizadoFocusNode.unfocus();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppPalette.primary.withValues(alpha: 0.25),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppPalette.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppPalette.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTypography.title.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTypography.small.copyWith(
                        fontSize: 12,
                        color: AppPalette.textSecondary,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppPalette.textSecondary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
