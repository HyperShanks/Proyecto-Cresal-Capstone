import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../../auth/services/auth_service.dart';
import '../models/vehiculo_recepcion_model.dart';

class RecepcionService {
  /// Consulta el siguiente número correlativo de patio.
  Future<String> obtenerSiguienteIngreso() async {
    try {
      final uri = Uri.parse('${ApiConstants.vehiculosEndpoint}/recepcion/siguiente-ingreso');
      final res = await ApiService.get(uri, timeout: const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['siguiente_ingreso']?.toString() ?? '1';
      }

      if (res.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
        return '1';
      }

      // Fallback retrocompatible
      final fallbackUri = Uri.parse('${ApiConstants.vehiculosEndpoint}/siguiente-ingreso');
      final fallbackRes = await ApiService.get(fallbackUri, timeout: const Duration(seconds: 15));
      if (fallbackRes.statusCode == 200) {
        final data = jsonDecode(fallbackRes.body);
        return data['siguiente_ingreso']?.toString() ?? '1';
      }

      if (fallbackRes.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
        return '1';
      }
      return '1';
    } catch (e) {
      debugPrint('[RECEPCION_SERVICE] Error al obtener siguiente ingreso: $e');
      return '1';
    }
  }

  /// Obtiene los ingresos vehiculares recientes con soporte de búsqueda para patio.
  Future<List<VehiculoRecepcionModel>> obtenerRecientes({
    String? busqueda,
    int limite = 50,
  }) async {
    try {
      final queryParams = <String, String>{
        'limite': limite.toString(),
        if (busqueda != null && busqueda.trim().isNotEmpty) 'busqueda': busqueda.trim(),
      };

      final uri = Uri.parse('${ApiConstants.vehiculosEndpoint}/recepcion/recientes')
          .replace(queryParameters: queryParams);

      var res = await ApiService.get(uri, timeout: const Duration(seconds: 15));

      if (res.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
        return [];
      }

      // Si el servidor configurado (ej: Render) devuelve 404 porque aún no ha desplegado la ruta,
      // intentamos fallback automático al servidor local de desarrollo si está disponible.
      if (res.statusCode == 404 && !uri.host.contains('127.0.0.1') && !uri.host.contains('localhost')) {
        try {
          final fallbackLocalUri = Uri.parse('http://127.0.0.1:8000/api/v1/vehiculos/recepcion/recientes')
              .replace(queryParameters: queryParams);
          final localRes = await ApiService.get(fallbackLocalUri, timeout: const Duration(seconds: 4));
          if (localRes.statusCode == 200) {
            res = localRes;
          } else if (localRes.statusCode == 401) {
            await AuthService.manejarSesionExpirada();
            return [];
          }
        } catch (_) {}
      }

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final items = (data['items'] as List<dynamic>? ?? []);
        return items
            .map((item) => VehiculoRecepcionModel.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        debugPrint('[RECEPCION_SERVICE] HTTP ${res.statusCode} al obtener recientes: ${res.body}');
      }
      return [];
    } catch (e) {
      debugPrint('[RECEPCION_SERVICE] Error al obtener recientes: $e');
      return [];
    }
  }

  /// Registra un nuevo vehículo donante en patio con las 13 columnas.
  Future<Map<String, dynamic>> registrarVehiculo(Map<String, dynamic> datos) async {
    try {
      final uri = Uri.parse('${ApiConstants.vehiculosEndpoint}/recepcion/registro');

      var res = await ApiService.post(
        uri,
        body: jsonEncode(datos),
        timeout: const Duration(seconds: 30),
      );

      if (res.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
        return {
          'exito': false,
          'mensaje': 'Tu sesión ha expirado. Ingresa tu PIN nuevamente.',
        };
      }

      if (res.statusCode == 404 && !uri.host.contains('127.0.0.1') && !uri.host.contains('localhost')) {
        try {
          final localUri = Uri.parse('http://127.0.0.1:8000/api/v1/vehiculos/recepcion/registro');
          final localRes = await ApiService.post(
            localUri,
            body: jsonEncode(datos),
            timeout: const Duration(seconds: 15),
          );
          if (localRes.statusCode == 200 || localRes.statusCode == 201) {
            res = localRes;
          } else if (localRes.statusCode == 401) {
            await AuthService.manejarSesionExpirada();
            return {
              'exito': false,
              'mensaje': 'Tu sesión ha expirado. Ingresa tu PIN nuevamente.',
            };
          }
        } catch (_) {}
      }

      final body = jsonDecode(res.body);

      if (res.statusCode == 200 || res.statusCode == 201) {
        return {
          'exito': true,
          'mensaje': 'Vehículo registrado exitosamente en patio',
          'vehiculo': VehiculoRecepcionModel.fromJson(body as Map<String, dynamic>),
        };
      } else {
        final detail = body['detail'] ?? body['message_user'] ?? 'Error al registrar vehículo en patio';
        return {
          'exito': false,
          'mensaje': detail.toString(),
        };
      }
    } catch (e) {
      debugPrint('[RECEPCION_SERVICE] Error en registrarVehiculo: $e');
      return {
        'exito': false,
        'mensaje': 'Error de comunicación: $e',
      };
    }
  }

  /// Obtiene la matriz completa formateada en TSV para copiado directo a Excel o Google Sheets.
  Future<Map<String, dynamic>> exportarMatriz({int limite = 100}) async {
    try {
      final uri = Uri.parse('${ApiConstants.vehiculosEndpoint}/recepcion/exportar-matriz?limite=$limite');

      var res = await ApiService.get(uri, timeout: const Duration(seconds: 30));

      if (res.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
        return {
          'exito': false,
          'mensaje': 'Tu sesión ha expirado. Ingresa tu PIN nuevamente.',
        };
      }

      if (res.statusCode == 404 && !uri.host.contains('127.0.0.1') && !uri.host.contains('localhost')) {
        try {
          final localUri = Uri.parse('http://127.0.0.1:8000/api/v1/vehiculos/recepcion/exportar-matriz?limite=$limite');
          final localRes = await ApiService.get(localUri, timeout: const Duration(seconds: 15));
          if (localRes.statusCode == 200) {
            res = localRes;
          } else if (localRes.statusCode == 401) {
            await AuthService.manejarSesionExpirada();
            return {
              'exito': false,
              'mensaje': 'Tu sesión ha expirado. Ingresa tu PIN nuevamente.',
            };
          }
        } catch (_) {}
      }

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return {
          'exito': true,
          'tsv': data['tsv'] as String? ?? '',
          'total': data['total'] as int? ?? 0,
        };
      } else {
        return {
          'exito': false,
          'mensaje': 'Error al exportar matriz vehicular',
        };
      }
    } catch (e) {
      return {
        'exito': false,
        'mensaje': 'Error de red: $e',
      };
    }
  }
}
