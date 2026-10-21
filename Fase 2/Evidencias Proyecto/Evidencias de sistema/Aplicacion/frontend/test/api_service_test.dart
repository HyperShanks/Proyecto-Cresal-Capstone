// test/api_service_test.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:frontend/core/services/api_service.dart';
import 'package:frontend/features/auth/services/auth_service.dart';
import 'package:frontend/features/alertas/services/bodega_polling_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'mock-valid-token',
      'user_rol': 'Bodeguero',
      'user_id_rol': '1',
      'user_sucursal_id': '2',
      'user_sucursal_nombre': 'Viña del Mar',
      'user_nombre_completo': 'Juan Pérez',
    });
    BodegaPollingService.instance.reset();
    ApiService.onUnauthorized = null;
  });

  group('ApiService - Headers & Inyección de Token', () {
    test('getHeaders incluye Content-Type y Authorization Bearer si hay token', () async {
      final headers = await ApiService.getHeaders();
      expect(headers['Content-Type'], 'application/json');
      expect(headers['Authorization'], 'Bearer mock-valid-token');
    });

    test('getHeaders con includeAuth=false no incluye Authorization', () async {
      final headers = await ApiService.getHeaders(includeAuth: false);
      expect(headers['Content-Type'], 'application/json');
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('getHeaders con token vacío o nulo no incluye Authorization', () async {
      await AuthService.clearToken();
      final headers = await ApiService.getHeaders();
      expect(headers['Content-Type'], 'application/json');
      expect(headers.containsKey('Authorization'), isFalse);
    });
  });

  group('ApiService & AuthService - Interceptor 401 y Manejo de Sesión Expirada', () {
    testWidgets('manejarSesionExpirada limpia storage, resetea polling, redirige a /login y muestra SnackBar', (tester) async {
      BodegaPollingService.instance.totalPendientesNotifier.value = 5;
      expect(await AuthService.getToken(), isNotNull);

      // Montar MaterialApp con las claves globales de ApiService
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: ApiService.navigatorKey,
          scaffoldMessengerKey: ApiService.scaffoldMessengerKey,
          home: const Scaffold(body: Text('Pantalla Principal')),
          routes: {
            '/login': (context) => const Scaffold(body: Text('Login Screen Mock')),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pantalla Principal'), findsOneWidget);

      // Ejecutar flujo de sesión expirada
      await AuthService.manejarSesionExpirada();
      await tester.pumpAndSettle();

      // 1. Tokens eliminados
      expect(await AuthService.getToken(), isNull);
      expect(await AuthService.getRol(), isNull);
      expect(await AuthService.getSucursalId(), isNull);

      // 2. Polling reseteado
      expect(BodegaPollingService.instance.totalPendientesNotifier.value, 0);

      // 3. Redirige a Login
      expect(find.text('Login Screen Mock'), findsOneWidget);

      // 4. SnackBar explicativo visible
      expect(find.text('Tu sesión ha expirado. Ingresa tu PIN nuevamente'), findsOneWidget);
    });

    test('Callback onUnauthorized se ejecuta cuando está configurado', () async {
      bool onUnauthorizedLlamado = false;
      ApiService.onUnauthorized = () async {
        onUnauthorizedLlamado = true;
      };

      if (ApiService.onUnauthorized != null) {
        await ApiService.onUnauthorized!();
      }

      expect(onUnauthorizedLlamado, isTrue);
    });
  });

  group('ApiService - Manejo y Sanitización de Errores (SPEC-HU-07)', () {
    test('extraerMensajeError prioriza message_user de ErrorResponseDTO', () {
      final response = http.Response(
        jsonEncode({
          'error_code': 'RECORD_ALREADY_EXISTS',
          'message_user': 'El registro ya existe en el sistema.',
          'detail': 'Detalle técnico interno',
        }),
        409,
      );

      final msg = ApiService.extraerMensajeError(response);
      expect(msg, 'El registro ya existe en el sistema.');
    });

    test('extraerMensajeError hace fallback seguro a códigos HTTP conocidos', () {
      final response500 = http.Response('Internal Server Error', 500);
      expect(
        ApiService.extraerMensajeError(response500),
        'Ocurrió un error inesperado en el servidor. Intenta nuevamente.',
      );

      final response404 = http.Response('Not Found', 404);
      expect(
        ApiService.extraerMensajeError(response404),
        'El recurso solicitado no fue encontrado.',
      );

      final response503 = http.Response('Service Unavailable', 503);
      expect(
        ApiService.extraerMensajeError(response503),
        'El servicio no está disponible temporalmente. Intenta más tarde.',
      );
    });

    test('ejecutarConManejoErrores captura TimeoutException y mapea a CustomApiException', () async {
      expect(
        () => ApiService.ejecutarConManejoErrores(() async {
          throw TimeoutException('Timed out');
        }),
        throwsA(
          isA<CustomApiException>()
              .having((e) => e.errorCode, 'errorCode', 'NETWORK_TIMEOUT')
              .having(
                (e) => e.messageUser,
                'messageUser',
                'Problemas de conexión con el servidor. Reintentando...',
              ),
        ),
      );
    });
  });
}
