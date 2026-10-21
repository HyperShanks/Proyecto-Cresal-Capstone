// lib/features/ventas/services/carrito_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../auth/services/auth_service.dart';

/// Excepción de negocio especializada para el flujo de reserva concurrente en carrito (HU-03).
class CarritoException implements Exception {
  final String message;
  final int? statusCode;
  final String? errorCode;

  const CarritoException(this.message, {this.statusCode, this.errorCode});

  @override
  String toString() => message;
}

/// Servicio HTTP para la gestión de reservas temporales, bloqueo concurrente
/// y mantenimiento de sesión (Heartbeat) de repuestos en el carrito de compras.
class CarritoService {
  /// Solicita el bloqueo temporal de un activo único con control de concurrencia optimista (version_lock).
  ///
  /// Lanza [CarritoException] con mensajes intuitivos si:
  /// - 409 Conflict: Otro vendedor reservó la pieza (`RESERVATION_COLLISION`).
  /// - 400 Bad Request: La pieza está dada de baja o en mantenimiento (`RESERVATION_ASSET_UNAVAILABLE`).
  /// - Error de red o timeout: Problema de conectividad (`RESERVATION_NETWORK_ERROR`).
  static Future<Map<String, dynamic>> reservarActivo(
    String idActivo,
    int versionLock, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final uri = Uri.parse('${ApiConstants.carritoEndpoint}/reservar');
      final token = await AuthService.getToken();

      final response = await httpClient
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'id_activo': idActivo,
              'version_lock_esperado': versionLock,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (kDebugMode) {
          debugPrint('🌐 [CARRITO] HTTP ${response.statusCode} OK en reservar');
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      if (response.statusCode == 401) {
        if (kDebugMode) {
          debugPrint('🌐 [CARRITO] HTTP 401 Unauthorized en reservar');
        }
        await AuthService.manejarSesionExpirada();
        throw const CarritoException(
          'Sesión expirada o token inválido.',
          statusCode: 401,
        );
      }

      if (response.statusCode == 409) {
        throw const CarritoException(
          '¡Lo sentimos! Este repuesto acaba de ser reservado por otro vendedor hace un instante.',
          statusCode: 409,
          errorCode: 'RESERVATION_COLLISION',
        );
      }

      if (response.statusCode == 400) {
        throw const CarritoException(
          'El artículo seleccionado se encuentra en mantenimiento o fue dado de baja del inventario.',
          statusCode: 400,
          errorCode: 'RESERVATION_ASSET_UNAVAILABLE',
        );
      }

      // Otros códigos de error
      String errorMsg = 'Error al asegurar la reserva del repuesto.';
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['detail'] != null) {
          errorMsg = decoded['detail'].toString();
        }
      } catch (_) {}

      throw CarritoException(errorMsg, statusCode: response.statusCode);
    } on SocketException {
      throw const CarritoException(
        'No fue posible asegurar tu reserva debido a un problema de red. Reintentando...',
        errorCode: 'RESERVATION_NETWORK_ERROR',
      );
    } on TimeoutException {
      throw const CarritoException(
        'No fue posible asegurar tu reserva debido a un problema de red. Reintentando...',
        errorCode: 'RESERVATION_NETWORK_ERROR',
      );
    } on http.ClientException {
      throw const CarritoException(
        'No fue posible asegurar tu reserva debido a un problema de red. Reintentando...',
        errorCode: 'RESERVATION_NETWORK_ERROR',
      );
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Libera voluntariamente una reserva temporal devolviendo el activo a estado Disponible.
  static Future<bool> liberarActivo(
    String idActivo, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final uri = Uri.parse('${ApiConstants.carritoEndpoint}/liberar/$idActivo');
      final token = await AuthService.getToken();

      final response = await httpClient
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 401) {
        if (kDebugMode) {
          debugPrint('🌐 [CARRITO] HTTP 401 Unauthorized en liberar');
        }
        await AuthService.manejarSesionExpirada();
        return false;
      }

      if (response.statusCode == 200) {
        if (kDebugMode) {
          debugPrint('🌐 [CARRITO] HTTP 200 OK en liberar');
        }
        return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Envía un pulso de actividad al backend para renovar la expiración de las reservas activas.
  static Future<Map<String, dynamic>?> heartbeat({
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final uri = Uri.parse('${ApiConstants.carritoEndpoint}/heartbeat');
      final token = await AuthService.getToken();

      final response = await httpClient
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 401) {
        if (kDebugMode) {
          debugPrint('🌐 [CARRITO] HTTP 401 Unauthorized en heartbeat');
        }
        await AuthService.manejarSesionExpirada();
        return null;
      }

      if (response.statusCode == 200) {
        if (kDebugMode) {
          debugPrint('🌐 [CARRITO] HTTP 200 OK en heartbeat');
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Consulta la lista de reservas activas del usuario logueado.
  /// Retorna `null` si hay error de red o no hay sesión activa.
  static Future<List<Map<String, dynamic>>?> obtenerMisReservas({
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final uri = Uri.parse('${ApiConstants.carritoEndpoint}/mis-reservas');
      final token = await AuthService.getToken();
      if (token == null || token.isEmpty) return null;

      final response = await httpClient
          .get(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 401) {
        if (kDebugMode) {
          debugPrint('🌐 [CARRITO] HTTP 401 Unauthorized en mis-reservas');
        }
        await AuthService.manejarSesionExpirada();
        return null;
      }

      if (response.statusCode == 200) {
        if (kDebugMode) {
          debugPrint('🌐 [CARRITO] HTTP 200 OK en mis-reservas');
        }
        final List<dynamic> decoded = jsonDecode(response.body);
        return decoded.cast<Map<String, dynamic>>();
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }
}
