// test/features/ventas/historial_ordenes_rendimiento_sanitizacion_test.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/features/ventas/presentation/screens/historial_screen.dart';
import 'package:frontend/features/ventas/services/ordenes_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'read') {
          return 'fake-test-jwt-token';
        }
        return null;
      },
    );
  });

  group('[ÓRDENES / RENDIMIENTO] Sanitización de Errores Unit Tests', () {
    test('Oculta IPs de Render, puertos y trazas de SocketException', () {
      const rawSocketError =
          'ClientException with SocketException: Connection failed (OS Error: Connection refused, errno = 111), address = dws-cresal-backend.onrender.com, port = 443';

      final resultado = OrdenesService.sanitizarMensajeError(rawSocketError);

      expect(resultado, isNot(contains('onrender.com')));
      expect(resultado, isNot(contains('errno')));
      expect(resultado, isNot(contains('port = 443')));
      expect(resultado, isNot(contains('SocketException')));
      expect(resultado, contains('No pudimos conectar con el servidor'));
      expect(resultado, contains('Revisa tu conexión a internet o intenta nuevamente'));
    });

    test('Oculta direcciones IP explícitas (IPv4)', () {
      const rawIpError =
          'Error al conectar al host 34.120.45.18:8000 tras caída del servidor';

      final resultado = OrdenesService.sanitizarMensajeError(rawIpError);

      expect(resultado, isNot(contains('34.120.45.18')));
      expect(resultado, isNot(contains(':8000')));
      expect(resultado, contains('El servicio de órdenes no se encuentra disponible temporalmente'));
    });

    test('Mapea Timeouts a mensaje amigable y accionable', () {
      final timeoutEx = TimeoutException('Tiempo de espera agotado al consultar órdenes.');

      final resultado = OrdenesService.sanitizarMensajeError(timeoutEx);

      expect(resultado, contains('El servidor tardó demasiado en responder'));
      expect(resultado, contains('reintenta en unos instantes'));
    });

    test('Mapea errores 502/503/Bad Gateway de Render a mensaje amigable', () {
      const errorRender502 =
          'Error 502 Bad Gateway - Service Unavailable on dws-cresal-backend.onrender.com';

      final resultado = OrdenesService.sanitizarMensajeError(errorRender502);

      expect(resultado, isNot(contains('onrender.com')));
      expect(resultado, isNot(contains('502')));
      expect(resultado, contains('El servicio de órdenes no se encuentra disponible temporalmente'));
    });

    test('Preserva mensajes limpios de validación de negocio', () {
      const mensajeNegocio = 'Solo se pueden anular órdenes en estado Reservada';

      final resultado = OrdenesService.sanitizarMensajeError(mensajeNegocio);

      expect(resultado, equals(mensajeNegocio));
    });
  });

  group('[ÓRDENES / RENDIMIENTO] HistorialScreen UI Sanitización, Espera y Reintento', () {
    testWidgets('Muestra feedback de espera activo con spinner y texto explicativo durante la carga', (tester) async {
      final completer = Completer<http.Response>();
      final mockClient = MockClient((request) => completer.future);

      await tester.pumpWidget(
        MaterialApp(
          home: HistorialScreen(
            client: mockClient,
          ),
        ),
      );

      // Primer frame: Se encuentra en estado _isLoading = true
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Cargando historial de órdenes...'), findsOneWidget);

      // Completar la petición para limpiar el completer
      completer.complete(http.Response('[]', 200));
      await tester.pumpAndSettle();
    });

    testWidgets('Cero Fuga Técnica: Ante fallo de red con IP y Render, muestra mensaje amigable y oculta la infraestructura', (tester) async {
      final mockClient = MockClient((request) async {
        throw http.ClientException(
          'ClientException with SocketException: Connection refused (OS Error: errno = 111), address = dws-cresal-backend.onrender.com, IP: 10.0.24.15',
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: HistorialScreen(
            client: mockClient,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verificamos que NO aparece la IP ni el dominio de Render en ninguna parte de la pantalla
      expect(find.textContaining('10.0.24.15'), findsNothing);
      expect(find.textContaining('onrender.com'), findsNothing);
      expect(find.textContaining('errno'), findsNothing);
      expect(find.textContaining('SocketException'), findsNothing);

      // Verificamos que aparece el mensaje comprensible para el personal
      expect(find.text('Error al cargar órdenes'), findsOneWidget);
      expect(find.textContaining('No pudimos conectar con el servidor'), findsOneWidget);

      // Verificamos el botón de reintento
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('Acción de Reintento Funcional: Presionar "Reintentar" vuelve a solicitar datos y recupera la vista', (tester) async {
      int requestCount = 0;

      final mockClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          // Primer intento: simular caída de red con trazas de Render
          throw http.ClientException(
            'Failed host lookup: dws-cresal-backend.onrender.com (IP: 34.120.10.5)',
          );
        }

        // Segundo intento (tras presionar Reintentar): respuesta exitosa con retardo
        await Future.delayed(const Duration(milliseconds: 50));
        final responseData = [
          {
            'id_orden': 'ord-recuperada-1',
            'estado_orden': 'Reservada',
            'total_venta': 350000,
            'monto_pendiente': 350000,
            'fecha_creacion': '2026-09-27T12:00:00',
            'total_items': 1,
            'detalles': [],
          }
        ];
        return http.Response(jsonEncode(responseData), 200);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: HistorialScreen(
            client: mockClient,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Estado de error inicial
      expect(find.text('Error al cargar órdenes'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);

      // Presionar botón Reintentar
      await tester.tap(find.text('Reintentar'));
      await tester.pump();

      // Feedback de carga activo tras presionar reintentar
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();

      // Ahora la orden recuperada debe mostrarse y el estado de error debe haber desaparecido
      expect(find.text('Error al cargar órdenes'), findsNothing);
      expect(find.text('ORD-ORD-RECU'), findsOneWidget); // Verifica que la card de la orden recuperada se renderizó
      expect(find.byType(HistorialScreen), findsOneWidget);
      expect(requestCount, greaterThanOrEqualTo(2));
    });
  });
}
