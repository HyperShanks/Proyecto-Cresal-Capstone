// lib/features/ventas/services/entregas_envios_storage_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'ordenes_service.dart';

/// Representa una acción operativa realizada en patio/mesón que debe sincronizarse con el backend.
class AccionEntregaEnvio {
  final String idAccion;
  final String tipo; // 'confirmar_entrega', 'marcar_despacho', 'actualizar_estado_despacho'
  final String idOrden;
  final String? idDespacho;
  final String? numeroSeguimiento;
  final String? empresaTransporte;
  final String? nuevoEstado;
  final String fecha;
  final int intentos;

  const AccionEntregaEnvio({
    required this.idAccion,
    required this.tipo,
    required this.idOrden,
    this.idDespacho,
    this.numeroSeguimiento,
    this.empresaTransporte,
    this.nuevoEstado,
    required this.fecha,
    this.intentos = 0,
  });

  AccionEntregaEnvio copyWith({
    int? intentos,
  }) {
    return AccionEntregaEnvio(
      idAccion: idAccion,
      tipo: tipo,
      idOrden: idOrden,
      idDespacho: idDespacho,
      numeroSeguimiento: numeroSeguimiento,
      empresaTransporte: empresaTransporte,
      nuevoEstado: nuevoEstado,
      fecha: fecha,
      intentos: intentos ?? this.intentos,
    );
  }

  Map<String, dynamic> toJson() => {
    'id_accion': idAccion,
    'tipo': tipo,
    'id_orden': idOrden,
    if (idDespacho != null) 'id_despacho': idDespacho,
    if (numeroSeguimiento != null) 'numero_seguimiento': numeroSeguimiento,
    if (empresaTransporte != null) 'empresa_transporte': empresaTransporte,
    if (nuevoEstado != null) 'nuevo_estado': nuevoEstado,
    'fecha': fecha,
    'intentos': intentos,
  };

  factory AccionEntregaEnvio.fromJson(Map<String, dynamic> json) {
    return AccionEntregaEnvio(
      idAccion: json['id_accion']?.toString() ?? '',
      tipo: json['tipo']?.toString() ?? '',
      idOrden: json['id_orden']?.toString() ?? '',
      idDespacho: json['id_despacho']?.toString(),
      numeroSeguimiento: json['numero_seguimiento']?.toString(),
      empresaTransporte: json['empresa_transporte']?.toString(),
      nuevoEstado: json['nuevo_estado']?.toString(),
      fecha: json['fecha']?.toString() ?? DateTime.now().toIso8601String(),
      intentos: json['intentos'] as int? ?? 0,
    );
  }
}

/// Servicio que encapsula la persistencia local en almacenamiento seguro para:
/// 1. Caché inmediata de la lista de Entregas y Envíos (Stale-While-Revalidate).
/// 2. Cola de acciones Outbox pendientes de sincronización por pérdida de señal.
class EntregasEnviosStorageService {
  static const String _keyCache = 'cache_entregas_envios_v1';
  static const String _keyOutbox = 'outbox_entregas_envios_v1';

  static List<EntregaEnvioModel>? _memoriaCache;

  @visibleForTesting
  static void limpiarCacheMemoria() {
    _memoriaCache = null;
  }

  final FlutterSecureStorage _storage;

  EntregasEnviosStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Guarda en almacenamiento local la lista de entregas y envíos para despliegue instantáneo.
  Future<void> guardarCache(List<EntregaEnvioModel> items) async {
    _memoriaCache = List.from(items);
    try {
      final rawList = items.map((i) => i.toJson()).toList();
      await _storage.write(key: _keyCache, value: jsonEncode(rawList));
    } catch (e) {
      debugPrint('⚠️ [STORAGE] Error al guardar caché de entregas: $e');
    }
  }

  /// Recupera la última lista cacheada localmente (< 50ms).
  Future<List<EntregaEnvioModel>> cargarCache() async {
    if (_memoriaCache != null && _memoriaCache!.isNotEmpty) {
      return List.from(_memoriaCache!);
    }
    try {
      final jsonStr = await _storage.read(key: _keyCache);
      if (jsonStr == null || jsonStr.trim().isEmpty) return [];

      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        final parsed = decoded
            .map((item) =>
                EntregaEnvioModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        _memoriaCache = List.from(parsed);
        return parsed;
      }
    } catch (e) {
      debugPrint('⚠️ [STORAGE] Error al leer caché de entregas: $e');
    }
    return [];
  }

  /// Agrega una acción operativa a la cola Outbox para reintento seguro.
  Future<void> encolarAccion(AccionEntregaEnvio accion) async {
    try {
      final pendientes = await obtenerAccionesPendientes();
      // Evitar duplicados por idAccion o idOrden del mismo tipo
      pendientes.removeWhere(
          (a) => a.idAccion == accion.idAccion || (a.idOrden == accion.idOrden && a.tipo == accion.tipo));
      pendientes.add(accion);

      final rawList = pendientes.map((a) => a.toJson()).toList();
      await _storage.write(key: _keyOutbox, value: jsonEncode(rawList));
    } catch (e) {
      debugPrint('⚠️ [STORAGE] Error al encolar acción en outbox: $e');
    }
  }

  /// Obtiene todas las acciones pendientes encoladas.
  Future<List<AccionEntregaEnvio>> obtenerAccionesPendientes() async {
    try {
      final jsonStr = await _storage.read(key: _keyOutbox);
      if (jsonStr == null || jsonStr.trim().isEmpty) return [];

      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        return decoded
            .map((item) =>
                AccionEntregaEnvio.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('⚠️ [STORAGE] Error al leer outbox: $e');
    }
    return [];
  }

  /// Actualiza o incrementa los intentos de una acción en la cola.
  Future<void> actualizarAccion(AccionEntregaEnvio accion) async {
    try {
      final pendientes = await obtenerAccionesPendientes();
      final index = pendientes.indexWhere((a) => a.idAccion == accion.idAccion);
      if (index != -1) {
        pendientes[index] = accion;
        final rawList = pendientes.map((a) => a.toJson()).toList();
        await _storage.write(key: _keyOutbox, value: jsonEncode(rawList));
      }
    } catch (e) {
      debugPrint('⚠️ [STORAGE] Error al actualizar acción en outbox: $e');
    }
  }

  /// Elimina una acción confirmada exitosamente de la cola Outbox.
  Future<void> eliminarAccion(String idAccion) async {
    try {
      final pendientes = await obtenerAccionesPendientes();
      pendientes.removeWhere((a) => a.idAccion == idAccion);

      if (pendientes.isEmpty) {
        await _storage.delete(key: _keyOutbox);
      } else {
        final rawList = pendientes.map((a) => a.toJson()).toList();
        await _storage.write(key: _keyOutbox, value: jsonEncode(rawList));
      }
    } catch (e) {
      debugPrint('⚠️ [STORAGE] Error al eliminar acción de outbox: $e');
    }
  }

  /// Limpia la caché local (por ejemplo en logout o cierre de sesión).
  Future<void> limpiarCache() async {
    try {
      await _storage.delete(key: _keyCache);
    } catch (_) {}
  }

  /// Limpia la cola Outbox (por ejemplo en logout o pruebas).
  Future<void> limpiarCola() async {
    try {
      await _storage.delete(key: _keyOutbox);
    } catch (_) {}
  }
}
