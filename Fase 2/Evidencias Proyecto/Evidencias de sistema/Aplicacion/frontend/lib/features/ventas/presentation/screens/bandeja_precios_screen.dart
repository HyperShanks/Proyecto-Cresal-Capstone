// lib/features/ventas/presentation/screens/bandeja_precios_screen.dart

import 'package:flutter/material.dart';
import '../../../../core/routes/route_observer.dart';
import '../../../../core/services/silent_polling_manager.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../models/pendiente_precio_model.dart';
import '../../services/inventario_service.dart';
import '../widgets/pendiente_precio_card.dart';
import '../widgets/asignar_precio_dialog.dart';
import 'catalogo_screen.dart';

/// Pantalla exclusiva para el Jefe de Ventas (id_rol == 6) (HU-3.8).
/// Muestra la bandeja de entrada de activos ingresados por bodega que no tienen precio_referencia asignado.
class BandejaPreciosScreen extends StatefulWidget {
  final VoidCallback? onOpenMenuDrawer;
  final VoidCallback? onRefreshCatalogo;

  const BandejaPreciosScreen({
    super.key,
    this.onOpenMenuDrawer,
    this.onRefreshCatalogo,
  });

  @override
  State<BandejaPreciosScreen> createState() => BandejaPreciosScreenState();
}

class BandejaPreciosScreenState extends State<BandejaPreciosScreen> with RouteAware {
  List<ActivoPendientePrecioModel> _pendientes = [];
  bool _isLoading = true;
  String? _errorMessage;
  SilentPollingManager? _pollingManager;

  @override
  void initState() {
    super.initState();
    _cargarPendientes();
    _iniciarPollingSilencioso();
  }

  void _iniciarPollingSilencioso() {
    _pollingManager?.dispose();
    _pollingManager = SilentPollingManager(
      interval: const Duration(seconds: 20),
      debugLabel: 'TasacionPolling',
      onPoll: _cargarPendientesSilencioso,
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
    refrescarSilencioso();
  }

  @override
  void dispose() {
    _pollingManager?.dispose();
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  /// Método público para forzar recarga (Auto-Refresh SPEC-HU-TAREA-20)
  Future<void> refrescar() async {
    await _cargarPendientes();
  }

  /// Recarga silenciosa sin spinners si ya hay datos en memoria
  Future<void> refrescarSilencioso() async {
    if (_pendientes.isEmpty) {
      await _cargarPendientes();
    } else {
      await _cargarPendientesSilencioso();
    }
  }

  Future<void> _cargarPendientesSilencioso() async {
    try {
      final items = await InventarioService.obtenerPendientesPrecio();
      if (!mounted) return;

      setState(() {
        _pendientes = items;
        _errorMessage = null;
        _isLoading = false;
      });
    } catch (_) {
      // Ignorar errores transitorios en ciclo silencioso
    }
  }

  Future<void> _cargarPendientes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await InventarioService.obtenerPendientesPrecio();
      if (!mounted) return;

      setState(() {
        _pendientes = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _abrirDialogoAsignarPrecio(ActivoPendientePrecioModel activo) {
    AsignarPrecioDialog.show(
      context,
      activo: activo,
      onPrecioAsignado: () {
        _cargarPendientesSilencioso();
        CatalogoScreen.refreshNotifier.value++;
        widget.onRefreshCatalogo?.call();
      },
    );
  }

  Widget _buildEmptyState() {
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
                Icons.task_alt_outlined,
                size: 54.0,
                color: AppPalette.success,
              ),
            ),
            const SizedBox(height: 20.0),
            Text(
              '¡Bandeja de Precios al Día!',
              style: AppTypography.title.copyWith(fontSize: 18.0),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8.0),
            Text(
              'No hay repuestos pendientes de precio ingresados por bodega.\n'
              'Cuando se paleticen nuevos activos sin precio, aparecerán aquí.',
              style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24.0),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.primary,
                side: const BorderSide(color: AppPalette.primary),
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
              ),
              icon: const Icon(Icons.refresh, size: 18.0),
              label: const Text('Actualizar Bandeja'),
              onPressed: _cargarPendientes,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48.0, color: AppPalette.error),
            const SizedBox(height: 16.0),
            const Text(
              'Error al cargar bandeja de precios',
              style: AppTypography.title,
            ),
            const SizedBox(height: 8.0),
            Text(
              _errorMessage ?? 'Ocurrió un error inesperado al conectar con el servidor.',
              style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20.0),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.primary,
                foregroundColor: AppPalette.textPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
              ),
              icon: const Icon(Icons.refresh, size: 18.0),
              label: const Text('Reintentar'),
              onPressed: _cargarPendientes,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: AppPalette.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Volver',
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bandeja de Precios',
              style: AppTypography.title,
            ),
            Text(
              _isLoading
                  ? 'Consultando activos...'
                  : '${_pendientes.length} repuestos por tasar',
              style: AppTypography.small.copyWith(
                fontSize: 12.0,
                color: _pendientes.isNotEmpty ? AppPalette.secondary : AppPalette.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppPalette.textPrimary),
            onPressed: _isLoading ? null : _cargarPendientes,
            tooltip: 'Actualizar lista',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppPalette.primary),
            )
          : _errorMessage != null
              ? _buildErrorState()
              : _pendientes.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _cargarPendientes,
                      color: AppPalette.primary,
                      backgroundColor: AppPalette.surface,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.7,
                            child: _buildEmptyState(),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargarPendientes,
                      color: AppPalette.primary,
                      backgroundColor: AppPalette.surface,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          16.0,
                          12.0,
                          16.0,
                          100.0,
                        ),
                        itemCount: _pendientes.length,
                        itemBuilder: (context, index) {
                          final activo = _pendientes[index];
                          return PendientePrecioCard(
                            activo: activo,
                            onAsignarPrecio: () => _abrirDialogoAsignarPrecio(activo),
                          );
                        },
                      ),
                    ),
    );
  }
}
