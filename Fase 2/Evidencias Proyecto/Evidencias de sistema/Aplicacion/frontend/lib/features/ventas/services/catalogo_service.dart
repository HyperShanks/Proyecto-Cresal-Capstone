// lib/features/ventas/services/catalogo_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../auth/services/auth_service.dart';
import '../models/catalogo_model.dart';

class CatalogoService {
  /// Obtiene los repuestos del catálogo paginado aplicando el algoritmo 'Radar de Stock'.
  ///
  /// Soporta búsqueda libre por texto [q] (marca, modelo, SKU), filtros por [idCategoria],
  /// [idSucursal], [marca], [anio], así como paginación con [limit] y [offset].
  static Future<PaginatedCatalogoResponse> obtenerCatalogo({
    String? q,
    int? idCategoria,
    int? idSucursal,
    String? marca,
    int? anio,
    String? cilindrada,
    String? transmision,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final Map<String, String> queryParams = {
        'limit': limit.toString(),
        'offset': offset.toString(),
      };

      if (q != null && q.trim().isNotEmpty) {
        queryParams['q'] = q.trim();
      }
      if (idCategoria != null) {
        queryParams['id_categoria'] = idCategoria.toString();
      }
      if (idSucursal != null) {
        queryParams['id_sucursal'] = idSucursal.toString();
      }
      if (marca != null && marca.trim().isNotEmpty) {
        queryParams['marca'] = marca.trim();
      }
      if (anio != null) {
        queryParams['anio'] = anio.toString();
      }
      if (cilindrada != null && cilindrada.trim().isNotEmpty) {
        queryParams['cilindrada'] = cilindrada.trim();
      }
      if (transmision != null && transmision.trim().isNotEmpty) {
        queryParams['transmision'] = transmision.trim();
      }

      final uri = Uri.parse(
        '${ApiConstants.inventarioEndpoint}/catalogo',
      ).replace(queryParameters: queryParams);

      final token = await AuthService.getToken();
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final response = await http
          .get(uri, headers: headers)
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw Exception('Tiempo de espera agotado al consultar catálogo'),
          );

      if (kDebugMode) {
        debugPrint('🌐 [CATALOGO] HTTP ${response.statusCode} ${response.statusCode == 200 ? "OK" : response.statusCode == 401 ? "Unauthorized" : ""}');
      }

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(
          utf8.decode(response.bodyBytes),
        ) as Map<String, dynamic>;

        return PaginatedCatalogoResponse.fromJson(data);
      } else if (response.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
        throw Exception('Sesión expirada o token inválido');
      } else {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        final detail = body is Map ? body['detail'] ?? 'Error en el servidor' : 'Error en el servidor';
        throw Exception(detail.toString());
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error de conexión con el catálogo: $e');
    }
  }

  /// Obtiene dinámicamente desde la BD las opciones de filtro (marcas, años,
  /// cilindradas, transmisiones) correspondientes únicamente a activos disponibles en catálogo.
  static Future<Map<String, dynamic>> obtenerOpcionesFiltrosCatalogo({
    int? idCategoria,
    int? idSucursal,
  }) async {
    try {
      final Map<String, String> queryParams = {};
      if (idCategoria != null) {
        queryParams['id_categoria'] = idCategoria.toString();
      }
      if (idSucursal != null) {
        queryParams['id_sucursal'] = idSucursal.toString();
      }

      final uri = Uri.parse(
        '${ApiConstants.inventarioEndpoint}/catalogo/opciones-filtros',
      ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final token = await AuthService.getToken();
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final response = await http.get(uri, headers: headers).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Tiempo de espera agotado al consultar opciones de filtro'),
          );

      if (kDebugMode) {
        debugPrint('🌐 [CATALOGO-FILTROS] HTTP ${response.statusCode} ${response.statusCode == 200 ? "OK" : response.statusCode == 401 ? "Unauthorized" : ""}');
      }

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(
          utf8.decode(response.bodyBytes),
        ) as Map<String, dynamic>;

        return {
          'marcas': List<String>.from(data['marcas'] ?? []),
          'anios': List<int>.from(data['anios'] ?? []),
          'cilindradas': List<String>.from(data['cilindradas'] ?? []),
          'transmisiones': List<String>.from(data['transmisiones'] ?? []),
        };
      } else {
        if (response.statusCode == 401) {
          await AuthService.manejarSesionExpirada();
        }
        return {
          'marcas': <String>[],
          'anios': <int>[],
          'cilindradas': <String>[],
          'transmisiones': <String>[],
        };
      }
    } catch (_) {
      return {
        'marcas': <String>[],
        'anios': <int>[],
        'cilindradas': <String>[],
        'transmisiones': <String>[],
      };
    }
  }
}
