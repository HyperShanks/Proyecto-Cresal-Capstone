// lib/core/services/api_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../features/auth/services/auth_service.dart';

/// Excepción estandarizada para errores de API y red (SPEC-HU-07).
class CustomApiException implements Exception {
  final String messageUser;
  final String errorCode;
  final int? statusCode;
  final String? messageDev;
  final String diagnosticCode;

  const CustomApiException({
    required this.messageUser,
    this.errorCode = 'API_ERROR',
    this.statusCode,
    this.messageDev,
    String? diagnosticCode,
  }) : diagnosticCode = diagnosticCode ?? errorCode;

  @override
  String toString() => messageUser;
}

/// Cliente HTTP centralizado con soporte para:
/// 1. Conexiones persistentes HTTP Keep-Alive (reutilización de sockets TLS).
/// 2. Reintento automático transparente ante microcortes transitorios.
/// 3. Intercepción automática de respuestas 401 Unauthorized (Sesión Expirada).
/// 4. Inyección automática de token de autenticación Bearer.
/// 5. Normalización y sanitización de respuestas de error (SPEC-HU-07).
class ApiService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Cliente HTTP compartido persistente para reutilización de sockets TLS/TCP (Keep-Alive).
  /// Evita negociar un TLS Handshake desde cero en cada llamada o cambio de pestaña.
  static http.Client _client = http.Client();

  /// Retorna el cliente HTTP compartido
  static http.Client get client => _client;

  /// Permite reiniciar o inyectar un cliente HTTP específico (útil para tests y recuperación de red).
  static void resetClient({http.Client? client}) {
    if (client != null) {
      _client = client;
    } else {
      _client.close();
      _client = http.Client();
    }
  }

  /// Limpia prefijos técnicos de excepciones sin truncar nombres de clases erróneamente.
  static String limpiarMensajeExcepcion(Object e) {
    final raw = e.toString().trim();
    final clean = raw
        .replaceFirst(RegExp(r'^[A-Za-z0-9_]*Exception:\s*'), '')
        .replaceFirst(RegExp(r'^[A-Za-z0-9_]*Error:\s*'), '')
        .trim();
    return clean.isNotEmpty ? clean : raw;
  }

  /// Timeout estándar para todas las peticiones HTTP (resiliente a redes lentas y cold-starts)
  static const Duration defaultTimeout = Duration(seconds: 35);

  /// Callback personalizable para manejar el evento 401 (útil en tests)
  static Future<void> Function()? onUnauthorized;

  /// Retorna los headers por defecto con el token Bearer si existe
  static Future<Map<String, String>> getHeaders({
    Map<String, String>? extraHeaders,
    bool includeAuth = true,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...?extraHeaders,
    };

    if (includeAuth) {
      final token = await AuthService.getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  /// Verifica si el código de estado es 401 y dispara el flujo de sesión expirada
  static void _checkStatusCode(int statusCode) {
    if (statusCode == 401) {
      if (kDebugMode) {
        debugPrint('⚠️ [API-SERVICE] HTTP 401 Unauthorized detectado');
      }
      if (onUnauthorized != null) {
        onUnauthorized!();
      } else {
        AuthService.manejarSesionExpirada();
      }
    }
  }

  /// Extrae el mensaje de error sanitizado para el usuario desde la respuesta HTTP
  static String extraerMensajeError(
    http.Response response, {
    String fallback = 'Ocurrió un error al procesar la solicitud.',
  }) {
    try {
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          if (decoded['message_user'] != null &&
              decoded['message_user'].toString().trim().isNotEmpty) {
            return decoded['message_user'].toString().trim();
          }
          if (decoded['detail'] != null &&
              decoded['detail'].toString().trim().isNotEmpty) {
            return decoded['detail'].toString().trim();
          }
          if (decoded['message'] != null &&
              decoded['message'].toString().trim().isNotEmpty) {
            return decoded['message'].toString().trim();
          }
          if (decoded['msg'] != null &&
              decoded['msg'].toString().trim().isNotEmpty) {
            return decoded['msg'].toString().trim();
          }
        }
      }
    } catch (_) {
      // Si el cuerpo no es JSON válido, usamos el mapeo por código de estado
    }

    switch (response.statusCode) {
      case 400:
        return 'Solicitud incorrecta o parámetros inválidos.';
      case 401:
        return 'Credenciales inválidas o sesión expirada.';
      case 403:
        return 'No tienes permisos suficientes para realizar esta acción.';
      case 404:
        return 'El recurso solicitado no fue encontrado.';
      case 409:
        return 'El registro ya existe o se encuentra en conflicto con otra operación.';
      case 422:
        return 'Los datos ingresados no tienen un formato válido.';
      case 502:
      case 503:
      case 504:
        return 'El servicio no está disponible temporalmente. Intenta más tarde.';
      case 500:
      default:
        return 'Ocurrió un error inesperado en el servidor. Intenta nuevamente.';
    }
  }

  /// Envoltorio resiliente para ejecutar peticiones HTTP y mapear errores de red
  /// con política de 1 reintento automático silencioso ante microcortes de enlace o handshake.
  static Future<T> ejecutarConManejoErrores<T>(
    Future<T> Function() accion, {
    int maxIntentos = 2,
    Duration delayReintento = const Duration(milliseconds: 400),
  }) async {
    int intentos = 0;
    while (true) {
      intentos++;
      try {
        return await accion();
      } on TimeoutException catch (e) {
        throw CustomApiException(
          messageUser: 'Problemas de conexión con el servidor. Reintentando...',
          errorCode: 'NETWORK_TIMEOUT',
          diagnosticCode: 'NET-TIMEOUT-35S',
          messageDev: e.toString(),
        );
      } on HandshakeException catch (e) {
        if (intentos < maxIntentos) {
          debugPrint(
            '🔄 [API-RETRY] Handshake interrumpido. Reintento silencioso ($intentos/$maxIntentos)...',
          );
          await Future.delayed(delayReintento);
          continue;
        }
        throw CustomApiException(
          messageUser:
              'Inestabilidad en la red local. Se interrumpió el enlace seguro con el servidor.',
          errorCode: 'NETWORK_HANDSHAKE_ERROR',
          diagnosticCode: 'NET-ENLACE-LOCAL',
          messageDev: e.toString(),
        );
      } on SocketException catch (e) {
        final errStr = e.toString().toLowerCase();
        final esSinInternet = errStr.contains('failed host lookup') ||
            errStr.contains('network is unreachable') ||
            errStr.contains('no address associated');

        if (!esSinInternet && intentos < maxIntentos) {
          debugPrint(
            '🔄 [API-RETRY] Socket interrumpido. Reintento silencioso ($intentos/$maxIntentos)...',
          );
          await Future.delayed(delayReintento);
          continue;
        }

        if (esSinInternet) {
          throw CustomApiException(
            messageUser:
                'Sin conexión a internet. Verifique su cable de red o router local.',
            errorCode: 'NETWORK_NO_INTERNET',
            diagnosticCode: 'NET-SIN-INTERNET',
            messageDev: e.toString(),
          );
        }

        throw CustomApiException(
          messageUser: 'Problemas de conexión con el servidor. Reintentando...',
          errorCode: 'NETWORK_SOCKET_ERROR',
          diagnosticCode: 'NET-SOCKET-DROP',
          messageDev: e.toString(),
        );
      } on http.ClientException catch (e) {
        final errStr = e.toString().toLowerCase();
        if ((errStr.contains('connection closed') ||
                errStr.contains('connection reset') ||
                errStr.contains('handshake')) &&
            intentos < maxIntentos) {
          debugPrint(
            '🔄 [API-RETRY] ClientException transitorio. Reintento silencioso ($intentos/$maxIntentos)...',
          );
          await Future.delayed(delayReintento);
          continue;
        }
        throw CustomApiException(
          messageUser: 'Problemas de conexión con el servidor. Reintentando...',
          errorCode: 'NETWORK_CLIENT_ERROR',
          diagnosticCode: 'NET-CLIENT-ERROR',
          messageDev: e.toString(),
        );
      } on CustomApiException {
        rethrow;
      } catch (e) {
        final rawStr = e.toString();
        if (rawStr.contains('HandshakeException') ||
            rawStr.contains('terminated during handshake')) {
          if (intentos < maxIntentos) {
            debugPrint(
              '🔄 [API-RETRY] HandshakeException genérico. Reintento silencioso ($intentos/$maxIntentos)...',
            );
            await Future.delayed(delayReintento);
            continue;
          }
          throw CustomApiException(
            messageUser:
                'Inestabilidad en la red local. Se interrumpió el enlace seguro con el servidor.',
            errorCode: 'NETWORK_HANDSHAKE_ERROR',
            diagnosticCode: 'NET-ENLACE-LOCAL',
            messageDev: rawStr,
          );
        }

        throw CustomApiException(
          messageUser: limpiarMensajeExcepcion(e),
          errorCode: 'UNEXPECTED_ERROR',
          diagnosticCode: 'APP-UNEXPECTED',
          messageDev: rawStr,
        );
      }
    }
  }

  /// GET con interceptor 401 y timeout reutilizando el cliente persistente
  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    bool includeAuth = true,
    Duration? timeout,
  }) async {
    return ejecutarConManejoErrores(() async {
      final finalHeaders = await getHeaders(
        extraHeaders: headers,
        includeAuth: includeAuth,
      );
      final response = await _client
          .get(url, headers: finalHeaders)
          .timeout(timeout ?? defaultTimeout);
      _checkStatusCode(response.statusCode);
      return response;
    });
  }

  /// POST con interceptor 401 y timeout reutilizando el cliente persistente
  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool includeAuth = true,
    Duration? timeout,
  }) async {
    return ejecutarConManejoErrores(() async {
      final finalHeaders = await getHeaders(
        extraHeaders: headers,
        includeAuth: includeAuth,
      );
      final response = await _client
          .post(
            url,
            headers: finalHeaders,
            body: body,
            encoding: encoding,
          )
          .timeout(timeout ?? defaultTimeout);
      _checkStatusCode(response.statusCode);
      return response;
    });
  }

  /// PUT con interceptor 401 y timeout reutilizando el cliente persistente
  static Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool includeAuth = true,
    Duration? timeout,
  }) async {
    return ejecutarConManejoErrores(() async {
      final finalHeaders = await getHeaders(
        extraHeaders: headers,
        includeAuth: includeAuth,
      );
      final response = await _client
          .put(
            url,
            headers: finalHeaders,
            body: body,
            encoding: encoding,
          )
          .timeout(timeout ?? defaultTimeout);
      _checkStatusCode(response.statusCode);
      return response;
    });
  }

  /// PATCH con interceptor 401 y timeout reutilizando el cliente persistente
  static Future<http.Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool includeAuth = true,
    Duration? timeout,
  }) async {
    return ejecutarConManejoErrores(() async {
      final finalHeaders = await getHeaders(
        extraHeaders: headers,
        includeAuth: includeAuth,
      );
      final response = await _client
          .patch(
            url,
            headers: finalHeaders,
            body: body,
            encoding: encoding,
          )
          .timeout(timeout ?? defaultTimeout);
      _checkStatusCode(response.statusCode);
      return response;
    });
  }

  /// DELETE con interceptor 401 y timeout reutilizando el cliente persistente
  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    bool includeAuth = true,
    Duration? timeout,
  }) async {
    return ejecutarConManejoErrores(() async {
      final finalHeaders = await getHeaders(
        extraHeaders: headers,
        includeAuth: includeAuth,
      );
      final response = await _client
          .delete(
            url,
            headers: finalHeaders,
            body: body,
            encoding: encoding,
          )
          .timeout(timeout ?? defaultTimeout);
      _checkStatusCode(response.statusCode);
      return response;
    });
  }

  /// Enviar petición personalizada / MultipartRequest con verificación de 401
  static Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return ejecutarConManejoErrores(() async {
      final response = await _client.send(request);
      _checkStatusCode(response.statusCode);
      return response;
    });
  }
}
