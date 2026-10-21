// lib/features/ventas/services/inventario_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../auth/services/auth_service.dart';
import '../models/pendiente_precio_model.dart';

/// Servicio HTTP para la gestión de inventario y tasación de precios (HU-3.8).
class InventarioService {
  /// Consulta la bandeja de activos pendientes de precio (precio_referencia == 0 o null).
  /// Requiere autenticación con rol de Jefe de Ventas (id_rol == 6).
  static Future<List<ActivoPendientePrecioModel>> obtenerPendientesPrecio({
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();

    try {
      final token = await AuthService.getToken();
      final uri = Uri.parse('${ApiConstants.inventarioEndpoint}/pendientes-precio');

      final response = await httpClient
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw Exception('Tiempo de espera agotado al consultar bandeja de precios.'),
          );

      if (kDebugMode) {
        debugPrint('🌐 [INVENTARIO-VENTAS] HTTP ${response.statusCode} ${response.statusCode == 200 ? "OK" : response.statusCode == 401 ? "Unauthorized" : ""} en pendientes-precio');
      }

      final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        if (decoded is List) {
          return decoded
              .map((item) => ActivoPendientePrecioModel.fromJson(item as Map<String, dynamic>))
              .toList();
        }
        return [];
      } else if (response.statusCode == 403) {
        final detail = decoded is Map ? decoded['detail'] : 'Acceso denegado: Se requiere rol de Jefe de Ventas.';
        throw Exception(detail.toString());
      } else if (response.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
        throw Exception('Sesión expirada o token inválido.');
      } else {
        final detail = decoded is Map ? decoded['detail'] : 'Error al consultar repuestos pendientes.';
        throw Exception(detail.toString());
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error de conexión con el servicio de inventario: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Asigna o actualiza el rango de precio (mínimo y máximo) de un repuesto ingresado por bodega.
  /// Cambia automáticamente el estado del activo a 'Disponible'.
  /// Requiere rol de Jefe de Ventas (id_rol == 6) o Gerencia.
  static Future<AsignarPrecioResponseModel> asignarPrecio(
    String idActivo, {
    required int precioMinimo,
    required int precioMaximo,
    int? precioReferencia,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();

    try {
      final token = await AuthService.getToken();
      final uri = Uri.parse('${ApiConstants.inventarioEndpoint}/$idActivo/precio');

      final response = await httpClient
          .patch(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'precio_minimo': precioMinimo,
              'precio_maximo': precioMaximo,
              'precio_referencia': precioReferencia ?? precioMaximo,
            }),
          )
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw Exception('Tiempo de espera agotado al asignar precio.'),
          );

      if (kDebugMode) {
        debugPrint('🌐 [INVENTARIO-VENTAS] HTTP ${response.statusCode} ${response.statusCode == 200 ? "OK" : response.statusCode == 401 ? "Unauthorized" : ""} en asignarPrecio');
      }

      final dynamic decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 200) {
        return AsignarPrecioResponseModel.fromJson(decoded as Map<String, dynamic>);
      } else if (response.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
        throw Exception('Sesión expirada o token inválido.');
      } else if (response.statusCode == 403) {
        final detail = decoded is Map ? decoded['detail'] : 'Acceso denegado: Se requiere rol de Jefe de Ventas.';
        throw Exception(detail.toString());
      } else if (response.statusCode == 404) {
        throw Exception('El repuesto no fue encontrado en el inventario.');
      } else if (response.statusCode == 422) {
        throw Exception('El precio ingresado no es válido (debe ser mayor a \$0).');
      } else {
        final detail = decoded is Map ? decoded['detail'] : 'Error al fijar precio de referencia.';
        throw Exception(detail.toString());
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error de conexión al asignar precio: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }
}
