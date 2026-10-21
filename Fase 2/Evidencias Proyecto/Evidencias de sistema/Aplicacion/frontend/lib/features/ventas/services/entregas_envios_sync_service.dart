// lib/features/ventas/services/entregas_envios_sync_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'ordenes_service.dart';
import 'ordenes_sync_notifier.dart';
import 'entregas_envios_storage_service.dart';

enum SyncStatusState {
  alDia,
  sincronizando,
  conexionInestable,
  conPendientes,
}

class SyncStatus {
  final SyncStatusState state;
  final int pendientesCount;
  final String? mensaje;

  const SyncStatus({
    required this.state,
    this.pendientesCount = 0,
    this.mensaje,
  });

  bool get estaAlDia => state == SyncStatusState.alDia && pendientesCount == 0;
  bool get tienePendientes => pendientesCount > 0;
  bool get esInestable => state == SyncStatusState.conexionInestable;
  bool get estaSincronizando => state == SyncStatusState.sincronizando;
}

/// Servicio que coordina la resiliencia en red, reintentos con backoff exponencial
/// y vaciado seguro de la cola Outbox para el Módulo de Retiro y Envíos.
class EntregasEnviosSyncService {
  final EntregasEnviosStorageService _storageService;
  final http.Client? client;
  bool _estaProcesandoCola = false;
  bool _isDisposed = false;

  final ValueNotifier<SyncStatus> statusNotifier = ValueNotifier<SyncStatus>(
    const SyncStatus(state: SyncStatusState.alDia),
  );

  EntregasEnviosSyncService({
    EntregasEnviosStorageService? storageService,
    this.client,
  })  : _storageService = storageService ?? EntregasEnviosStorageService();

  EntregasEnviosStorageService get storage => _storageService;
  int get colaPendienteCount => statusNotifier.value.pendientesCount;

  Future<void> procesarCola() => procesarColaPendiente();

  /// Consulta la lista de entregas y envíos con tolerancia a microcortes y backoff exponencial.
  /// Si la red falla tras 3 intentos, recupera automáticamente la versión en caché local (Stale-While-Revalidate).
  Future<List<EntregaEnvioModel>> sincronizarEntregas({
    int? sucursalId,
    String? tipo,
    String? busquedaCliente,
    String? busquedaVendedor,
    String? busqueda,
    String? estadoPago,
    bool soloActivas = true,
    int? limit,
    int? offset,
  }) async {
    _notificarEstado(SyncStatusState.sincronizando, 'Sincronizando entregas...');

    List<EntregaEnvioModel>? resultado;
    dynamic ultimoError;

    // Política de 3 reintentos con backoff exponencial
    const int maxIntentos = 3;
    const List<int> delaysMs = [300, 1000, 2000];

    for (int i = 0; i < maxIntentos; i++) {
      try {
        resultado = await OrdenesService.obtenerEntregasEnvios(
          sucursalId: sucursalId,
          tipo: tipo,
          busquedaCliente: busquedaCliente,
          busquedaVendedor: busquedaVendedor,
          busqueda: busqueda,
          estadoPago: estadoPago,
          soloActivas: soloActivas,
          limit: limit,
          offset: offset,
          client: client,
        );
        break; // Éxito
      } catch (e) {
        ultimoError = e;
        final errorStr = e.toString().toLowerCase();
        final esErrorCliente = errorStr.contains('400') ||
            errorStr.contains('401') ||
            errorStr.contains('403') ||
            errorStr.contains('404');

        if (esErrorCliente || _isDisposed) {
          break; // No reintentar ante errores de solicitud cliente (4xx) ni si fue cancelado
        }

        if (i < maxIntentos - 1) {
          _notificarEstado(
            SyncStatusState.conexionInestable,
            'Conexión inestable - Reintentando...',
          );
          await Future.delayed(Duration(milliseconds: delaysMs[i]));
          if (_isDisposed) break;
        }
      }
    }

    if (resultado != null) {
      // Guardar en caché local para próximas aperturas instantáneas
      unawaited(_storageService.guardarCache(resultado));

      // Procesar cualquier acción encolada pendiente
      unawaited(procesarColaPendiente());

      final pendientes = await _storageService.obtenerAccionesPendientes();
      if (pendientes.isNotEmpty) {
        _notificarEstado(
          SyncStatusState.conPendientes,
          '${pendientes.length} confirmación(es) en cola',
          pendientes.length,
        );
      } else {
        _notificarEstado(SyncStatusState.alDia, 'Al día');
      }

      return resultado;
    }

    // Fallo de red tras todos los reintentos: recuperar caché local
    _notificarEstado(
      SyncStatusState.conexionInestable,
      'Conexión inestable - Mostrando datos locales',
    );

    final cacheLocal = await _storageService.cargarCache();
    if (cacheLocal.isNotEmpty) {
      return cacheLocal;
    }

    // Si ni siquiera hay caché local, re-lanzamos el error para avisar en UI
    throw ultimoError ?? Exception('Sin conexión y sin datos locales disponibles.');
  }

  /// Ejecuta una confirmación operativa registrándola de inmediato en la cola Outbox
  /// e intentando despacharla de inmediato al backend.
  Future<bool> ejecutarAccionConCola(AccionEntregaEnvio accion) async {
    // 1. Encolar de inmediato en almacenamiento seguro
    await _storageService.encolarAccion(accion);
    _notificarEstado(SyncStatusState.sincronizando, 'Confirmando en servidor...');

    // 2. Intentar despacho al servidor
    final exito = await _despacharAccion(accion);

    if (exito) {
      await _storageService.eliminarAccion(accion.idAccion);
      OrdenesSyncNotifier.instance.notificarCambio();

      final pendientes = await _storageService.obtenerAccionesPendientes();
      if (pendientes.isNotEmpty) {
        _notificarEstado(
          SyncStatusState.conPendientes,
          '${pendientes.length} acción(es) pendiente(s)',
          pendientes.length,
        );
      } else {
        _notificarEstado(SyncStatusState.alDia, 'Confirmación sincronizada');
      }
      return true;
    } else {
      // No se pudo enviar por microcorte: se mantiene encolado
      await _storageService.actualizarAccion(accion.copyWith(intentos: accion.intentos + 1));
      final pendientes = await _storageService.obtenerAccionesPendientes();
      _notificarEstado(
        SyncStatusState.conPendientes,
        '${pendientes.length} confirmación(es) guardada(s) localmente',
        pendientes.length,
      );
      return false;
    }
  }

  /// Procesa secuencialmente las acciones encoladas en background.
  Future<void> procesarColaPendiente() async {
    if (_estaProcesandoCola) return;
    _estaProcesandoCola = true;

    try {
      final pendientes = await _storageService.obtenerAccionesPendientes();
      if (pendientes.isEmpty) return;

      for (final accion in pendientes) {
        final exito = await _despacharAccion(accion);
        if (exito) {
          await _storageService.eliminarAccion(accion.idAccion);
          OrdenesSyncNotifier.instance.notificarCambio();
        } else {
          // Si una falla por red, detener el ciclo para no agotar recursos
          await _storageService.actualizarAccion(accion.copyWith(intentos: accion.intentos + 1));
          break;
        }
      }

      final restantes = await _storageService.obtenerAccionesPendientes();
      if (restantes.isNotEmpty) {
        _notificarEstado(
          SyncStatusState.conPendientes,
          '${restantes.length} acción(es) pendiente(s)',
          restantes.length,
        );
      } else {
        _notificarEstado(SyncStatusState.alDia, 'Todas las confirmaciones sincronizadas');
      }
    } finally {
      _estaProcesandoCola = false;
    }
  }

  Future<bool> _despacharAccion(AccionEntregaEnvio accion) async {
    try {
      if (accion.tipo == 'confirmar_entrega') {
        return await OrdenesService.confirmarEntregaTienda(
          accion.idOrden,
          client: client,
        );
      } else if ((accion.tipo == 'marcar_despacho' || accion.tipo == 'marcar_enviado') &&
          accion.idDespacho != null) {
        return await OrdenesService.marcarDespachoEnviado(
          accion.idDespacho!,
          client: client,
        );
      } else if (accion.tipo == 'actualizar_estado_despacho' &&
          accion.idDespacho != null &&
          accion.nuevoEstado != null) {
        return await OrdenesService.actualizarEstadoDespacho(
          accion.idDespacho!,
          accion.nuevoEstado!,
          client: client,
        );
      }
      return false;
    } catch (e) {
      final msg = e.toString().toLowerCase();
      // Si la respuesta es idempotente o ya estaba entregada/despachada, tratar como éxito
      if (msg.contains('ya confirmada') ||
          msg.contains('ya fue entregada') ||
          msg.contains('ya se encontraba marcado como enviado') ||
          msg.contains('ya se encontraba como')) {
        return true;
      }
      debugPrint('⚠️ [SYNC] Error transitorio al despachar acción ${accion.idAccion}: $e');
      return false;
    }
  }

  void _notificarEstado(SyncStatusState state, String mensaje, [int pendientes = 0]) {
    if (_isDisposed) return;
    statusNotifier.value = SyncStatus(
      state: state,
      mensaje: mensaje,
      pendientesCount: pendientes,
    );
  }

  void dispose() {
    _isDisposed = true;
    statusNotifier.dispose();
  }
}
