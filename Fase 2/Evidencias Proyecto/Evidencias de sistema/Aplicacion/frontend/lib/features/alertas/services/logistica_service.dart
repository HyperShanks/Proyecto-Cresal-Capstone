import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/tarea_alerta.dart';
import '../../../core/constants/api_constants.dart';
import '../../auth/services/auth_service.dart';

/// DTO de respuesta para un ítem individual en la inspección de salida
class ItemSalidaInfoModel {
  final String idDetalle;
  final String? idActivo;
  final String titulo;
  final String? skuQrFisico;
  final bool esInventariado;
  final String ubicacion;
  final String? notasPreparacion;
  final int cantidad;
  final int precioFinal;
  bool qrImpreso;
  final Map<String, dynamic>? etiquetaData;

  ItemSalidaInfoModel({
    required this.idDetalle,
    this.idActivo,
    required this.titulo,
    this.skuQrFisico,
    required this.esInventariado,
    required this.ubicacion,
    this.notasPreparacion,
    required this.cantidad,
    required this.precioFinal,
    this.qrImpreso = true,
    this.etiquetaData,
  });

  factory ItemSalidaInfoModel.fromJson(Map<String, dynamic> json) {
    return ItemSalidaInfoModel(
      idDetalle: json['id_detalle']?.toString() ?? '',
      idActivo: json['id_activo']?.toString(),
      titulo: json['titulo'] ?? 'Repuesto',
      skuQrFisico: json['sku_qr_fisico'],
      esInventariado: json['es_inventariado'] ?? false,
      ubicacion: json['ubicacion'] ?? 'N/A',
      notasPreparacion: json['notas_preparacion'],
      cantidad: json['cantidad'] ?? 1,
      precioFinal: json['precio_final'] ?? 0,
      qrImpreso: json['qr_impreso'] ?? true,
      etiquetaData: json['etiqueta_data'] != null
          ? Map<String, dynamic>.from(json['etiqueta_data'])
          : null,
    );
  }
}

/// DTO de respuesta para la verificación previa del QR del vendedor
class VerificarQrSalidaResponseModel {
  final String idOrden;
  final String folio;
  final String estadoOrden;
  final int totalVenta;
  final int montoPendiente;
  final int idSucursal;
  final String clienteNombre;
  final String clienteRut;
  final String? clienteTelefono;
  final List<ItemSalidaInfoModel> itemsRequeridos;
  final int totalItemsFisicos;
  final String qrTransaccionalSalida;

  const VerificarQrSalidaResponseModel({
    required this.idOrden,
    required this.folio,
    required this.estadoOrden,
    required this.totalVenta,
    required this.montoPendiente,
    required this.idSucursal,
    required this.clienteNombre,
    required this.clienteRut,
    this.clienteTelefono,
    required this.itemsRequeridos,
    required this.totalItemsFisicos,
    required this.qrTransaccionalSalida,
  });

  factory VerificarQrSalidaResponseModel.fromJson(Map<String, dynamic> json) {
    return VerificarQrSalidaResponseModel(
      idOrden: json['id_orden']?.toString() ?? '',
      folio: json['folio'] ?? '',
      estadoOrden: json['estado_orden'] ?? 'Pagada',
      totalVenta: json['total_venta'] ?? 0,
      montoPendiente: json['monto_pendiente'] ?? 0,
      idSucursal: json['id_sucursal'] ?? 1,
      clienteNombre: json['cliente_nombre'] ?? 'Cliente General',
      clienteRut: json['cliente_rut'] ?? 'N/A',
      clienteTelefono: json['cliente_telefono'],
      itemsRequeridos: (json['items_requeridos'] as List<dynamic>? ?? [])
          .map((item) => ItemSalidaInfoModel.fromJson(item as Map<String, dynamic>))
          .toList(),
      totalItemsFisicos: json['total_items_fisicos'] ?? 0,
      qrTransaccionalSalida: json['qr_transaccional_salida'] ?? '',
    );
  }
}

/// DTO de confirmación tras el Dual-Scan match exitoso
class EscanearSalidaResponseModel {
  final String idOrden;
  final String folio;
  final String estadoOrden;
  final String idBodeguero;
  final String bodegueroNombre;
  final String fechaEntrega;
  final List<String> activosEntregados;
  final int totalEntregados;
  final String mensaje;

  const EscanearSalidaResponseModel({
    required this.idOrden,
    required this.folio,
    required this.estadoOrden,
    required this.idBodeguero,
    required this.bodegueroNombre,
    required this.fechaEntrega,
    required this.activosEntregados,
    required this.totalEntregados,
    required this.mensaje,
  });

  factory EscanearSalidaResponseModel.fromJson(Map<String, dynamic> json) {
    return EscanearSalidaResponseModel(
      idOrden: json['id_orden']?.toString() ?? '',
      folio: json['folio'] ?? '',
      estadoOrden: json['estado_orden'] ?? 'Completada',
      idBodeguero: json['id_bodeguero']?.toString() ?? '',
      bodegueroNombre: json['bodeguero_nombre'] ?? 'Bodeguero',
      fechaEntrega: json['fecha_entrega'] ?? '',
      activosEntregados: (json['activos_entregados'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      totalEntregados: json['total_entregados'] ?? 0,
      mensaje: json['mensaje'] ?? 'Entrega completada exitosamente.',
    );
  }
}

/// Servicio para operaciones logísticas, tareas de bodega y Handshake de Salida (HU-3.6)
class LogisticaService {
  /// Obtiene la lista de tareas operativas pendientes de bodega para la sucursal del usuario
  static Future<List<TareaAlerta>> obtenerAlertas({int? sucursalId, http.Client? client}) async {
    final httpClient = client ?? http.Client();
    try {
      final token = await AuthService.getToken();
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      int targetSucursal = sucursalId ?? 1;
      final uri = Uri.parse('${ApiConstants.bodegaEndpoint}/tareas-pendientes?sucursal_id=$targetSucursal');

      final response = await httpClient.get(
        uri,
        headers: headers,
      );

      if (kDebugMode) {
        debugPrint('🌐 [LOGISTICA] HTTP ${response.statusCode} ${response.statusCode == 200 ? "OK" : response.statusCode == 401 ? "Unauthorized" : ""} en tareas-pendientes');
      }

      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(utf8.decode(response.bodyBytes));
        return body.map((dynamic item) => TareaAlerta.fromJson(item)).toList();
      } else {
        if (response.statusCode == 401) {
          await AuthService.manejarSesionExpirada();
        }
        throw Exception('Error al cargar alertas del servidor: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error de conexión: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Consulta previa de la orden escaneando el código QR Digital del Vendedor (TX-QR-...)
  static Future<VerificarQrSalidaResponseModel> verificarQrSalida({
    required String qrTransaccionalSalida,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final token = await AuthService.getToken();
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      debugPrint('🚪 [SERVICE-BODEGA] Verificando QR de salida: $qrTransaccionalSalida');

      final response = await httpClient.post(
        Uri.parse('${ApiConstants.bodegaEndpoint}/verificar-qr-salida'),
        headers: headers,
        body: jsonEncode({
          'qr_transaccional_salida': qrTransaccionalSalida.trim(),
        }),
      );

      if (kDebugMode) {
        debugPrint('🌐 [LOGISTICA] HTTP ${response.statusCode} ${response.statusCode == 200 ? "OK" : response.statusCode == 401 ? "Unauthorized" : ""} en verificar-qr-salida');
      }

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        debugPrint('✅ [SERVICE-BODEGA] Inspección de orden exitosa: ${data['folio']}');
        return VerificarQrSalidaResponseModel.fromJson(data);
      } else {
        if (response.statusCode == 401) {
          await AuthService.manejarSesionExpirada();
        }
        final Map<String, dynamic> errorData = jsonDecode(utf8.decode(response.bodyBytes));
        final detail = errorData['detail'] ?? 'Error al verificar QR de salida.';
        debugPrint('⚠️ [SERVICE-BODEGA] Error al verificar QR: $detail');
        throw Exception(detail);
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error de conexión al verificar QR de salida: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Ejecuta el Handshake de salida Dual-Scan enviando el token digital y los SKUs físicos
  static Future<EscanearSalidaResponseModel> escanearSalida({
    required String qrTransaccionalSalida,
    required List<String> skusEscaneados,
    String? observacionesEntrega,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final token = await AuthService.getToken();
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      debugPrint('🚪 [SERVICE-BODEGA] Enviando Dual-Scan (QR: $qrTransaccionalSalida, SKUs: $skusEscaneados)...');

      final response = await httpClient.post(
        Uri.parse('${ApiConstants.bodegaEndpoint}/escanear-salida'),
        headers: headers,
        body: jsonEncode({
          'qr_transaccional_salida': qrTransaccionalSalida.trim(),
          'skus_escaneados': skusEscaneados,
          if (observacionesEntrega != null && observacionesEntrega.isNotEmpty)
            'observaciones_entrega': observacionesEntrega,
        }),
      );

      if (kDebugMode) {
        debugPrint('🌐 [LOGISTICA] HTTP ${response.statusCode} ${response.statusCode == 200 ? "OK" : response.statusCode == 401 ? "Unauthorized" : ""} en escanear-salida');
      }

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        debugPrint('✅ [SERVICE-BODEGA] Match exitoso en barrera para orden: ${data['folio']}');
        return EscanearSalidaResponseModel.fromJson(data);
      } else {
        if (response.statusCode == 401) {
          await AuthService.manejarSesionExpirada();
        }
        final Map<String, dynamic> errorData = jsonDecode(utf8.decode(response.bodyBytes));
        final detail = errorData['detail'] ?? 'Error al autorizar salida en barrera.';
        debugPrint('⚠️ [SERVICE-BODEGA] Rechazo en barrera (${response.statusCode}): $detail');
        throw Exception(detail);
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error de conexión al escanear salida: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Marca la preparación de pre-entrega de una pieza como 'Listo'
  static Future<bool> completarPreentrega(String idDetalle) async {
    try {
      final token = await AuthService.getToken();
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final uri = Uri.parse('${ApiConstants.bodegaEndpoint}/tareas/$idDetalle/completar-preentrega');
      final response = await http.patch(uri, headers: headers);

      if (kDebugMode) {
        debugPrint('🌐 [LOGISTICA] HTTP ${response.statusCode} ${response.statusCode == 200 ? "OK" : response.statusCode == 401 ? "Unauthorized" : ""} en completar-preentrega');
      }

      if (response.statusCode == 200) {
        return true;
      } else {
        if (response.statusCode == 401) {
          await AuthService.manejarSesionExpirada();
        }
        final errorData = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorData['detail'] ?? 'Error al completar pre-entrega: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error al marcar listo: $e');
    }
  }

  /// Consulta el resumen consolidado de alertas de bodega para el Badge (SPEC-HU-06)
  static Future<ResumenAlertasModel> obtenerResumenAlertas({int? sucursalId, http.Client? client}) async {
    final httpClient = client ?? http.Client();
    try {
      final token = await AuthService.getToken();
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      int targetSucursal = sucursalId ?? 1;
      final uri = Uri.parse('${ApiConstants.bodegaEndpoint}/resumen-alertas?sucursal_id=$targetSucursal');

      final response = await httpClient.get(uri, headers: headers);

      if (kDebugMode) {
        debugPrint('🌐 [LOGISTICA] HTTP ${response.statusCode} ${response.statusCode == 200 ? "OK" : response.statusCode == 401 ? "Unauthorized" : ""} en resumen-alertas');
      }

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        return ResumenAlertasModel.fromJson(data);
      } else {
        if (response.statusCode == 401) {
          await AuthService.manejarSesionExpirada();
        }
        return ResumenAlertasModel.vacio();
      }
    } catch (_) {
      return ResumenAlertasModel.vacio();
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }
}

/// DTO de respuesta para el resumen consolidado de alertas de bodega (SPEC-HU-06)
class ResumenAlertasModel {
  final int totalTareas;
  final int desglosePreparacion;
  final int desgloseEntregas;
  final int desgloseReingresos;

  const ResumenAlertasModel({
    required this.totalTareas,
    required this.desglosePreparacion,
    required this.desgloseEntregas,
    required this.desgloseReingresos,
  });

  factory ResumenAlertasModel.fromJson(Map<String, dynamic> json) {
    return ResumenAlertasModel(
      totalTareas: json['total_tareas'] ?? 0,
      desglosePreparacion: json['desglose_preparacion'] ?? 0,
      desgloseEntregas: json['desglose_entregas'] ?? 0,
      desgloseReingresos: json['desglose_reingresos'] ?? 0,
    );
  }

  factory ResumenAlertasModel.vacio() {
    return const ResumenAlertasModel(
      totalTareas: 0,
      desglosePreparacion: 0,
      desgloseEntregas: 0,
      desgloseReingresos: 0,
    );
  }
}
