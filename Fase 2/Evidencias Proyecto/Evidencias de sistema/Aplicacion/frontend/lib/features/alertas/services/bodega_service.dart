import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../auth/services/auth_service.dart';

/// DTO de modelo para Tarea de Reingreso / Logística Inversa
class TareaReingresoModel {
  final String idOrden;
  final String idActivo;
  final String skuQrFisico;
  final String? ubicacionPallet;
  final String? ubicacionPasillo;
  final String? ubicacionGalpon;
  final String descripcionPieza;
  final String? folioOrden;
  final String? motivoAnulacion;

  const TareaReingresoModel({
    required this.idOrden,
    required this.idActivo,
    required this.skuQrFisico,
    this.ubicacionPallet,
    this.ubicacionPasillo,
    this.ubicacionGalpon,
    required this.descripcionPieza,
    this.folioOrden,
    this.motivoAnulacion,
  });

  factory TareaReingresoModel.fromJson(Map<String, dynamic> json) {
    return TareaReingresoModel(
      idOrden: json['id_orden']?.toString() ?? '',
      idActivo: json['id_activo']?.toString() ?? '',
      skuQrFisico: json['sku_qr_fisico']?.toString() ?? '',
      ubicacionPallet: json['ubicacion_pallet']?.toString(),
      ubicacionPasillo: json['ubicacion_pasillo']?.toString(),
      ubicacionGalpon: json['ubicacion_galpon']?.toString(),
      descripcionPieza: json['descripcion_pieza']?.toString() ?? 'Repuesto',
      folioOrden: json['folio_orden']?.toString(),
      motivoAnulacion: json['motivo_anulacion']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id_orden': idOrden,
    'id_activo': idActivo,
    'sku_qr_fisico': skuQrFisico,
    'ubicacion_pallet': ubicacionPallet,
    'ubicacion_pasillo': ubicacionPasillo,
    'ubicacion_galpon': ubicacionGalpon,
    'descripcion_pieza': descripcionPieza,
    'folio_orden': folioOrden,
    'motivo_anulacion': motivoAnulacion,
  };
}

/// DTO de respuesta para confirmación de reingreso en bodega
class ConfirmarReingresoResponseModel {
  final String msg;
  final String? idActivo;
  final String? skuQrFisico;
  final String? nuevoEstado;
  final String? ubicacionPasillo;
  final String? ubicacionPallet;
  final String? ubicacionGalpon;

  const ConfirmarReingresoResponseModel({
    required this.msg,
    this.idActivo,
    this.skuQrFisico,
    this.nuevoEstado,
    this.ubicacionPasillo,
    this.ubicacionPallet,
    this.ubicacionGalpon,
  });

  factory ConfirmarReingresoResponseModel.fromJson(Map<String, dynamic> json) {
    return ConfirmarReingresoResponseModel(
      msg: json['msg']?.toString() ?? 'Reingreso confirmado exitosamente.',
      idActivo: json['id_activo']?.toString(),
      skuQrFisico: json['sku_qr_fisico']?.toString(),
      nuevoEstado: json['nuevo_estado']?.toString(),
      ubicacionPasillo: json['ubicacion_pasillo']?.toString(),
      ubicacionPallet: json['ubicacion_pallet']?.toString(),
      ubicacionGalpon: json['ubicacion_galpon']?.toString(),
    );
  }
}

/// Servicio de gestión de tareas de bodega y logística inversa
class BodegaService {
  /// Consulta las tareas de reingreso pendientes originadas por órdenes anuladas (SPEC-HU-TAREA-4).
  static Future<List<TareaReingresoModel>> obtenerReingresosPendientes({
    int? sucursalId,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();

    try {
      final targetSucursal = sucursalId ?? await AuthService.getSucursalId() ?? 1;
      final uri = Uri.parse('${ApiConstants.bodegaEndpoint}/reingresos-pendientes?sucursal_id=$targetSucursal');
      final token = await AuthService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await httpClient.get(uri, headers: headers).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Tiempo de espera agotado al consultar reingresos pendientes.'),
      );

      if (kDebugMode) {
        debugPrint('🌐 [BODEGA] HTTP ${response.statusCode} ${response.statusCode == 200 ? "OK" : response.statusCode == 401 ? "Unauthorized" : ""} en reingresos-pendientes');
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is List) {
          return decoded.map((e) => TareaReingresoModel.fromJson(e as Map<String, dynamic>)).toList();
        }
        return [];
      } else if (response.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
        throw Exception('Sesión expirada. Por favor vuelve a iniciar sesión.');
      } else if (response.statusCode == 403) {
        throw Exception('Acceso denegado. No tienes permisos para gestionar reingresos.');
      } else {
        throw Exception('Error al obtener reingresos pendientes (${response.statusCode}).');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error inesperado al obtener reingresos: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Confirma el reingreso y paletizado de un repuesto físico mediante escaneo de QR (SPEC-HU-TAREA-4).
  static Future<ConfirmarReingresoResponseModel> confirmarReingreso({
    required String skuQrFisico,
    required String idOrdenAnulada,
    String? ubicacionPasillo,
    String? ubicacionPallet,
    String? ubicacionGalpon,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();

    try {
      final uri = Uri.parse('${ApiConstants.bodegaEndpoint}/confirmar-reingreso');
      final token = await AuthService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final body = jsonEncode({
        'sku_qr_fisico': skuQrFisico.trim().toUpperCase(),
        'id_orden_anulada': idOrdenAnulada.trim(),
        if (ubicacionPasillo != null && ubicacionPasillo.trim().isNotEmpty)
          'ubicacion_pasillo': ubicacionPasillo.trim().toUpperCase(),
        if (ubicacionPallet != null && ubicacionPallet.trim().isNotEmpty)
          'ubicacion_pallet': ubicacionPallet.trim().toUpperCase(),
        if (ubicacionGalpon != null && ubicacionGalpon.trim().isNotEmpty)
          'ubicacion_galpon': ubicacionGalpon.trim().toUpperCase(),
      });

      final response = await httpClient
          .post(uri, headers: headers, body: body)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Tiempo de espera agotado al confirmar reingreso.'),
          );

      if (kDebugMode) {
        debugPrint('🌐 [BODEGA] HTTP ${response.statusCode} ${response.statusCode == 200 ? "OK" : response.statusCode == 401 ? "Unauthorized" : ""} en confirmar-reingreso');
      }

      dynamic decodedBody;
      try {
        decodedBody = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        try {
          decodedBody = jsonDecode(response.body);
        } catch (_) {
          decodedBody = null;
        }
      }

      if (response.statusCode == 200) {
        if (decodedBody is Map<String, dynamic>) {
          return ConfirmarReingresoResponseModel.fromJson(decodedBody);
        }
        return const ConfirmarReingresoResponseModel(msg: 'Activo paletizado/disponible exitosamente');
      } else if (response.statusCode == 400 || response.statusCode == 404 || response.statusCode == 403) {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        throw Exception(detail?.toString() ?? 'Error al confirmar reingreso (${response.statusCode}).');
      } else if (response.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
        throw Exception('Sesión expirada. Por favor vuelve a iniciar sesión.');
      } else {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        throw Exception(detail?.toString() ?? 'Error del servidor al confirmar reingreso (${response.statusCode}).');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error inesperado al confirmar reingreso: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }
}
