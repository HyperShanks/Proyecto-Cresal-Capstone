// lib/features/alertas/presentation/screens/alertas_screen.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/routes/route_observer.dart';
import '../../../../core/services/silent_polling_manager.dart';
import '../../models/tarea_alerta.dart';
import '../../services/logistica_service.dart';
import '../../services/bodega_polling_service.dart';
import '../widgets/alerta_preentrega_tab.dart';
import '../widgets/alerta_reimpresion_tab.dart';
import '../widgets/alerta_reintegracion_tab.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';

/// Centro de Alertas y Tareas de Bodega PDA con navegación por pestañas (SPEC-HU-TAREA-13 / SPEC-HU-TAREA-21).
/// Segmenta el flujo de trabajo en:
/// 1. Pre-entrega (Preparación, Liberada, Traslado)
/// 2. Re-impresión (Etiquetas QR por imprimir)
/// 3. Re-integración (Logística Inversa por órdenes anuladas)
///
/// Arquitectura de Refresco Silencioso (SPEC-HU-TAREA-21):
/// - Navegación instantánea en memoria entre pestañas sin loaders destructivos ni peticiones redundantes.
/// - Sincronización silenciosa en segundo plano con [SilentPollingManager] cada 15 segundos.
/// - Reanudación y actualización suave al volver de rutas secundarias ([didPopNext]) sin parpadeo.
class AlertasScreen extends StatefulWidget {
  final Future<List<TareaAlerta>>? futureAlertas;
  final Future<List<TareaAlerta>> Function()? onFetchAlertas;

  const AlertasScreen({
    super.key,
    this.futureAlertas,
    this.onFetchAlertas,
  });

  @override
  State<AlertasScreen> createState() => _AlertasScreenState();
}

class _AlertasScreenState extends State<AlertasScreen>
    with SingleTickerProviderStateMixin, RouteAware {
  late final TabController _tabController;
  List<TareaAlerta> _tareas = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isDisposed = false;
  SilentPollingManager? _pollingManager;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _cargarInicial();
    _iniciarPollingSilencioso();
  }

  void _iniciarPollingSilencioso() {
    _pollingManager = SilentPollingManager(
      interval: const Duration(seconds: 15),
      debugLabel: 'BodegaAlertasPolling',
      onPoll: () => _sincronizarSilencioso(isSilent: true),
    );
    _pollingManager?.start();
  }

  Future<void> _cargarInicial() async {
    final initialFuture = widget.onFetchAlertas?.call() ??
        widget.futureAlertas ??
        LogisticaService.obtenerAlertas();

    try {
      final tareas = await initialFuture;
      if (mounted && !_isDisposed) {
        setState(() {
          _tareas = tareas;
          _isLoading = false;
          _errorMessage = null;
        });
        _sincronizarNotifiers(tareas);
      }
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant AlertasScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.futureAlertas != null && widget.futureAlertas != oldWidget.futureAlertas) {
      _cargarFuture(widget.futureAlertas!);
    }
  }

  Future<void> _cargarFuture(Future<List<TareaAlerta>> fut) async {
    try {
      final tareas = await fut;
      if (mounted && !_isDisposed) {
        setState(() {
          _tareas = tareas;
          _errorMessage = null;
          _isLoading = false;
        });
        _sincronizarNotifiers(tareas);
      }
    } catch (e) {
      if (mounted && !_isDisposed) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
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
    // Al regresar de un modal o tarea secundaria, sincronizamos silenciosamente
    // sin mostrar pantalla de carga completa ni resetear el scroll o la pestaña activa.
    _sincronizarSilencioso(isSilent: true);
  }

  @override
  void dispose() {
    _isDisposed = true;
    routeObserver.unsubscribe(this);
    _pollingManager?.dispose();
    _pollingManager = null;
    _tabController.dispose();
    super.dispose();
  }

  void _sincronizarNotifiers(List<TareaAlerta> tareas) {
    if (!mounted || _isDisposed) return;

    final preentrega = tareas
        .where((t) =>
            t.tipoAlerta == 'PREPARACION' ||
            t.tipoAlerta == 'LIBERADA' ||
            t.tipoAlerta == 'TRASLADO')
        .toList();
    final reimpresion = tareas.where((t) => t.tipoAlerta == 'IMPRESION').toList();
    final reintegracion = tareas.where((t) => t.tipoAlerta == 'REINGRESO').toList();

    final s = BodegaPollingService.instance;
    s.tareasNotifier.value = tareas;
    s.preentregaNotifier.value = preentrega;
    s.reimpresionNotifier.value = reimpresion;
    s.reintegracionNotifier.value = reintegracion;
    s.conteoPreentregaNotifier.value = preentrega.length;
    s.conteoReimpresionNotifier.value = reimpresion.length;
    s.conteoReintegracionNotifier.value = reintegracion.length;
    s.totalPendientesNotifier.value = tareas.length;
  }

  Future<void> _sincronizarSilencioso({bool isSilent = false}) async {
    if (!isSilent && _tareas.isEmpty) {
      if (mounted && !_isDisposed) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }
    }

    try {
      final fut = widget.onFetchAlertas?.call() ??
          (widget.futureAlertas != null && !isSilent ? widget.futureAlertas! : null) ??
          LogisticaService.obtenerAlertas();
      final tareas = await fut;
      if (mounted && !_isDisposed) {
        setState(() {
          _tareas = tareas;
          _errorMessage = null;
          _isLoading = false;
        });
        _sincronizarNotifiers(tareas);
      }
    } catch (e) {
      debugPrint('[AlertasScreen] Sincronización silenciosa omitida/error: $e');
      if (mounted && !_isDisposed) {
        if (_tareas.isEmpty) {
          setState(() {
            _errorMessage = e.toString();
            _isLoading = false;
          });
        }
      }
    }
  }

  Widget _buildTabItem({
    required String label,
    required ValueListenable<int> countNotifier,
  }) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: countNotifier,
            builder: (context, count, _) {
              if (count <= 0) return const SizedBox.shrink();
              return Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: AppPalette.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final polling = BodegaPollingService.instance;

    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        foregroundColor: AppPalette.textPrimary,
        elevation: 0.5,
        centerTitle: false,
        title: Text(
          'Alertas Tareas',
          style: AppTypography.title.copyWith(fontSize: 18),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppPalette.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Volver',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppPalette.primary),
            onPressed: () => _sincronizarSilencioso(isSilent: false),
            tooltip: 'Actualizar tareas',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppPalette.primary,
          indicatorWeight: 3,
          indicatorSize: TabBarIndicatorSize.tab,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          labelColor: AppPalette.primary,
          unselectedLabelColor: AppPalette.textSecondary,
          tabs: [
            _buildTabItem(
              label: 'Entrega',
              countNotifier: polling.conteoPreentregaNotifier,
            ),
            _buildTabItem(
              label: 'Imprimir',
              countNotifier: polling.conteoReimpresionNotifier,
            ),
            _buildTabItem(
              label: 'Re-integración',
              countNotifier: polling.conteoReintegracionNotifier,
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppPalette.primary),
            )
          : _errorMessage != null && _tareas.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.wifi_off_rounded, color: AppPalette.error, size: 52),
                        const SizedBox(height: 16),
                        const Text(
                          'No se pudieron cargar las tareas. Reintentando conexión con la bodega...',
                          style: TextStyle(
                            color: AppPalette.error,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () => _sincronizarSilencioso(isSilent: false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppPalette.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    AlertaPreentregaTab(
                      tareas: _tareas
                          .where((t) =>
                              t.tipoAlerta == 'PREPARACION' ||
                              t.tipoAlerta == 'LIBERADA' ||
                              t.tipoAlerta == 'TRASLADO')
                          .toList(),
                      onRefresh: () => _sincronizarSilencioso(isSilent: true),
                    ),
                    AlertaReimpresionTab(
                      tareas: _tareas.where((t) => t.tipoAlerta == 'IMPRESION').toList(),
                      onRefresh: () => _sincronizarSilencioso(isSilent: true),
                    ),
                    AlertaReintegracionTab(
                      tareas: _tareas.where((t) => t.tipoAlerta == 'REINGRESO').toList(),
                      onRefresh: () => _sincronizarSilencioso(isSilent: true),
                    ),
                  ],
                ),
    );
  }
}
