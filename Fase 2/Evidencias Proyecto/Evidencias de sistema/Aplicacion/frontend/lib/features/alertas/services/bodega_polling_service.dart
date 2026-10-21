// lib/features/alertas/services/bodega_polling_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/services/silent_polling_manager.dart';
import '../models/tarea_alerta.dart';
import 'logistica_service.dart';
import '../../auth/services/auth_service.dart';
import '../../ventas/services/ordenes_sync_notifier.dart';

/// Servicio de Polling Reactivo de Bodega (SPEC-HU-06):
/// Controla la carga operativa y actualiza el Badge numérico en tiempo real
/// sin emitir notificaciones emergentes invasivas en la UI principal.
class BodegaPollingService {
  static final BodegaPollingService _instance = BodegaPollingService._internal();
  factory BodegaPollingService() => _instance;
  static BodegaPollingService get instance => _instance;

  BodegaPollingService._internal() {
    _registrarSyncListener();
  }

  void _registrarSyncListener() {
    OrdenesSyncNotifier.instance.addListener(_onOrdenesCambiaron);
  }

  void _onOrdenesCambiaron() {
    if (!_isPolling) {
      procesarCiclo();
    }
  }

  Timer? _pollingTimer;
  SilentPollingManager? _silentPolling;

  /// Set en memoria para deduplicar alertas (compatibilidad)
  final Set<String> _tareasNotificadas = {};

  /// Marca de tiempo de la última notificación de resumen emitida
  DateTime? _ultimaAlertaResumen;

  /// Callback personalizable para disparar notificaciones locales o avisos en UI
  void Function(String titulo, String cuerpo)? onNotificacion;

  /// Notifiers reactivos para el Badge del AppBar y el Panel Desplegable
  final ValueNotifier<int> totalPendientesNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> tieneTrasladosNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<List<TareaAlerta>> tareasNotifier = ValueNotifier<List<TareaAlerta>>([]);
  final ValueNotifier<ResumenAlertasModel> resumenNotifier = ValueNotifier<ResumenAlertasModel>(ResumenAlertasModel.vacio());

  /// Notifiers segmentados por categoría para navegación en pestañas (SPEC-HU-TAREA-13)
  final ValueNotifier<List<TareaAlerta>> preentregaNotifier = ValueNotifier<List<TareaAlerta>>([]);
  final ValueNotifier<List<TareaAlerta>> reimpresionNotifier = ValueNotifier<List<TareaAlerta>>([]);
  final ValueNotifier<List<TareaAlerta>> reintegracionNotifier = ValueNotifier<List<TareaAlerta>>([]);

  final ValueNotifier<int> conteoPreentregaNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> conteoReimpresionNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> conteoReintegracionNotifier = ValueNotifier<int>(0);

  bool _isPolling = false;

  Set<String> get tareasNotificadas => Set.unmodifiable(_tareasNotificadas);
  DateTime? get ultimaAlertaResumen => _ultimaAlertaResumen;
  bool get isPollingActive =>
      (_silentPolling != null && _silentPolling!.isRunning) ||
      (_pollingTimer != null && _pollingTimer!.isActive);

  /// Inicia el temporizador de polling (por defecto cada 30-60 segundos)
  void iniciarPolling({
    int? sucursalId,
    Duration interval = const Duration(seconds: 45),
  }) {
    detenerPolling();
    procesarCiclo(sucursalId: sucursalId);

    _silentPolling = SilentPollingManager(
      interval: interval,
      debugLabel: 'BodegaPollingService',
      onPoll: () => procesarCiclo(sucursalId: sucursalId),
    );
    _silentPolling!.start();
  }

  /// Detiene el ciclo de polling
  void detenerPolling() {
    _silentPolling?.dispose();
    _silentPolling = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Reinicia el estado interno del servicio (al cambiar de usuario o cerrar sesión)
  void reset() {
    detenerPolling();
    _tareasNotificadas.clear();
    _ultimaAlertaResumen = null;
    totalPendientesNotifier.value = 0;
    tieneTrasladosNotifier.value = false;
    tareasNotifier.value = [];
    resumenNotifier.value = ResumenAlertasModel.vacio();

    preentregaNotifier.value = [];
    reimpresionNotifier.value = [];
    reintegracionNotifier.value = [];
    conteoPreentregaNotifier.value = 0;
    conteoReimpresionNotifier.value = 0;
    conteoReintegracionNotifier.value = 0;
  }

  /// Decrementa manualmente el contador reactivo tras completar una tarea (Zero Latency UI)
  void decrementarPendiente({String? tipoAlerta}) {
    if (totalPendientesNotifier.value > 0) {
      totalPendientesNotifier.value--;
    }
    if (tipoAlerta != null) {
      final tipo = tipoAlerta.toUpperCase();
      if (tipo == 'IMPRESION') {
        if (conteoReimpresionNotifier.value > 0) conteoReimpresionNotifier.value--;
      } else if (tipo == 'REINGRESO') {
        if (conteoReintegracionNotifier.value > 0) conteoReintegracionNotifier.value--;
      } else {
        if (conteoPreentregaNotifier.value > 0) conteoPreentregaNotifier.value--;
      }
    }
  }

  /// Ejecuta un ciclo completo de sincronización de alertas y resumen con el backend
  Future<void> procesarCiclo({int? sucursalId, List<TareaAlerta>? tareasMock}) async {
    if (_isPolling) return;
    _isPolling = true;

    try {
      List<TareaAlerta> tareas;
      ResumenAlertasModel resumen;

      if (tareasMock != null) {
        tareas = tareasMock;
        final prep = tareas.where((t) => t.tipoAlerta == 'PREPARACION' || t.tipoAlerta == 'TRASLADO').length;
        final ent = tareas.where((t) => t.tipoAlerta == 'LIBERADA' || t.tipoAlerta == 'IMPRESION').length;
        final reing = tareas.where((t) => t.tipoAlerta == 'REINGRESO').length;
        resumen = ResumenAlertasModel(
          totalTareas: tareas.length,
          desglosePreparacion: prep,
          desgloseEntregas: ent,
          desgloseReingresos: reing,
        );
      } else {
        final targetSucursal = sucursalId ?? await AuthService.getSucursalId();
        final futures = await Future.wait([
          LogisticaService.obtenerAlertas(sucursalId: targetSucursal),
          LogisticaService.obtenerResumenAlertas(sucursalId: targetSucursal),
        ]);
        tareas = futures[0] as List<TareaAlerta>;
        resumen = futures[1] as ResumenAlertasModel;
      }

      // Segmentación por Tipo de Operación (SPEC-HU-TAREA-13)
      final preentrega = tareas
          .where((t) =>
              t.tipoAlerta == 'PREPARACION' ||
              t.tipoAlerta == 'LIBERADA' ||
              t.tipoAlerta == 'TRASLADO')
          .toList();
      final reimpresion = tareas.where((t) => t.tipoAlerta == 'IMPRESION').toList();
      final reintegracion = tareas.where((t) => t.tipoAlerta == 'REINGRESO').toList();

      // Actualizar estados reactivos para la UI (Badge, Panel y Pestañas)
      tareasNotifier.value = tareas;
      resumenNotifier.value = resumen;

      preentregaNotifier.value = preentrega;
      reimpresionNotifier.value = reimpresion;
      reintegracionNotifier.value = reintegracion;

      conteoPreentregaNotifier.value = preentrega.length;
      conteoReimpresionNotifier.value = reimpresion.length;
      conteoReintegracionNotifier.value = reintegracion.length;

      // Sincronizar el total pendiente con el valor más preciso
      totalPendientesNotifier.value = tareas.isNotEmpty ? tareas.length : resumen.totalTareas;
      tieneTrasladosNotifier.value = tareas.any((t) => t.esTraslado || t.tipoAlerta == 'TRASLADO');

      // ── Deduplicación y Notificaciones Opcionales ─────────────────────────
      final tareasNuevas = tareas.where((t) {
        final idClave = t.idDetalle ?? t.idTarea;
        return idClave.isNotEmpty && !_tareasNotificadas.contains(idClave);
      }).toList();

      if (tareasNuevas.isNotEmpty) {
        final esTraslado = tareasNuevas.any((t) => t.esTraslado || t.tipoAlerta == 'TRASLADO');
        final titulo = '¡Nueva tarea de bodega!';
        final cuerpo = esTraslado
            ? 'Se ha asignado un nuevo traslado inter-sucursal pendiente de preparación.'
            : 'Se ha asignado una nueva preparación/traslado.';

        _emitirNotificacion(titulo, cuerpo);

        for (final t in tareasNuevas) {
          final idClave = t.idDetalle ?? t.idTarea;
          if (idClave.isNotEmpty) {
            _tareasNotificadas.add(idClave);
          }
        }
      }

      // Sincronizar el set: Retener solo los IDs que sigan existiendo en el backend
      final idsActuales = tareas
          .map((t) => t.idDetalle ?? t.idTarea)
          .where((id) => id.isNotEmpty)
          .toSet();

      _tareasNotificadas.removeWhere((id) => !idsActuales.contains(id));

      // Recordatorio Periódico (Ciclo de 2 horas)
      final ahora = DateTime.now();
      if (tareas.isNotEmpty) {
        final bool debeEmitirResumen = _ultimaAlertaResumen == null ||
            ahora.difference(_ultimaAlertaResumen!) >= const Duration(hours: 2);

        if (debeEmitirResumen) {
          final total = tareas.length;
          _emitirNotificacion(
            'Recordatorio de Bodega',
            'Tienes $total ${total == 1 ? "tarea pendiente" : "tareas pendientes"} en tu sucursal.',
          );
          _ultimaAlertaResumen = ahora;
        }
      }
    } catch (e) {
      debugPrint('BodegaPollingService error en ciclo: $e');
    } finally {
      _isPolling = false;
    }
  }

  void _emitirNotificacion(String titulo, String cuerpo) {
    debugPrint('[BODEGA NOTIFICACIÓN] $titulo - $cuerpo');
    if (onNotificacion != null) {
      onNotificacion!(titulo, cuerpo);
    }
  }
}
