// frontend/test/features/ventas/carrito_concurrencia_test.dart
// Pruebas unitarias y de widgets para Reserva Temporal y Bloqueo Concurrente (SPEC-HU-TAREA-3)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter/services.dart';
import 'package:frontend/features/ventas/models/catalogo_model.dart';
import 'package:frontend/features/ventas/controllers/cart_controller.dart';
import 'package:frontend/features/ventas/services/carrito_service.dart';
import 'package:frontend/features/ventas/presentation/widgets/catalogo_item_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'read') {
          return 'fake-jwt-token-test';
        }
        return null;
      },
    );
  });

  group('SPEC-HU-TAREA-3: CarritoService - Pruebas Unitarias de Red y Errores', () {
    test('reservarActivo exitoso retorna 200 con version_lock actualizado', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/carrito/reservar')) {
          final body = jsonDecode(request.body);
          expect(body['id_activo'], equals('act-123'));
          expect(body['version_lock_esperado'], equals(1));

          return http.Response(
            jsonEncode({
              'id_activo': 'act-123',
              'version_lock': 2,
              'reservado_por': 'user-456',
              'reserva_expira_en': '2026-09-06T15:00:00',
              'mensaje': 'Activo reservado temporalmente en el carrito con éxito.',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final res = await CarritoService.reservarActivo(
        'act-123',
        1,
        client: mockClient,
      );

      expect(res['version_lock'], equals(2));
      expect(res['id_activo'], equals('act-123'));
    });

    test('reservarActivo falla con 409 Conflict y lanza mensaje intuitivo de colisión', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': '¡Lo sentimos! Este repuesto acaba de ser reservado por otro vendedor hace un instante.',
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      });

      expect(
        () => CarritoService.reservarActivo('act-123', 1, client: mockClient),
        throwsA(
          predicate((e) =>
              e is CarritoException &&
              e.statusCode == 409 &&
              e.errorCode == 'RESERVATION_COLLISION' &&
              e.message.contains('¡Lo sentimos! Este repuesto acaba de ser reservado por otro vendedor hace un instante.')),
        ),
      );
    });

    test('reservarActivo falla con 400 Bad Request por activo no disponible / en mantenimiento', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'El artículo seleccionado se encuentra en mantenimiento o fue dado de baja del inventario.',
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      expect(
        () => CarritoService.reservarActivo('act-123', 1, client: mockClient),
        throwsA(
          predicate((e) =>
              e is CarritoException &&
              e.statusCode == 400 &&
              e.errorCode == 'RESERVATION_ASSET_UNAVAILABLE' &&
              e.message.contains('El artículo seleccionado se encuentra en mantenimiento o fue dado de baja del inventario.')),
        ),
      );
    });

    test('liberarActivo exitoso retorna true al enviar POST /liberar', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/carrito/liberar/act-123')) {
          return http.Response(
            jsonEncode({
              'id_activo': 'act-123',
              'version_lock': 3,
              'mensaje': 'Reserva liberada exitosamente.',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Error', 400);
      });

      final liberado = await CarritoService.liberarActivo('act-123', client: mockClient);
      expect(liberado, isTrue);
    });

    test('heartbeat exitoso renueva la expiración de las reservas', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/carrito/heartbeat')) {
          return http.Response(
            jsonEncode({
              'mensaje': 'Heartbeat de carrito procesado exitosamente.',
              'activos_renovados': 2,
              'nueva_expiracion': '2026-09-06T15:30:00',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Error', 400);
      });

      final res = await CarritoService.heartbeat(client: mockClient);
      expect(res, isNotNull);
      expect(res!['activos_renovados'], equals(2));
    });
  });

  group('SPEC-HU-TAREA-3: CatalogoItemCard - Reactividad Visual de Bloqueo', () {
    const itemDisponible = CatalogoItem(
      idActivo: 'act-disp',
      skuQrFisico: 'SKU-DISP-01',
      precioReferencia: 500000,
      idCategoria: 1,
      nombreCategoria: 'Motor',
      idSucursalActual: 1,
      nombreSucursal: 'Casa Matriz',
      marca: 'Toyota',
      modelo: 'Yaris',
      anio: 2020,
      idEstado: 1,
      estadoActivo: 'Disponible',
      versionLock: 1,
    );

    const itemReservado = CatalogoItem(
      idActivo: 'act-res',
      skuQrFisico: 'SKU-RES-02',
      precioReferencia: 850000,
      idCategoria: 1,
      nombreCategoria: 'Motor',
      idSucursalActual: 1,
      nombreSucursal: 'Casa Matriz',
      marca: 'Nissan',
      modelo: 'Navara',
      anio: 2021,
      idEstado: 2,
      estadoActivo: 'Reservado',
      versionLock: 2,
    );

    testWidgets('Item disponible no muestra etiqueta redundante DISPONIBLE y tiene botón de carrito activo', (tester) async {
      bool tapExecuted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogoItemCard(
              item: itemDisponible,
              vendedorSucursalId: 1,
              onAddToCart: () {
                tapExecuted = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('DISPONIBLE'), findsNothing);
      expect(find.byIcon(Icons.add_shopping_cart), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_shopping_cart));
      await tester.pump();

      expect(tapExecuted, isTrue);
    });

    testWidgets('Item con observación muestra badge Obs con puntos suspensivos y sin chip DISPONIBLE', (tester) async {
      final itemConObs = itemDisponible.copyWith(
        observacionEstado: 'Unida al motor y probada en banco con detalles estéticos menores',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogoItemCard(
              item: itemConObs,
              vendedorSucursalId: 1,
            ),
          ),
        ),
      );

      expect(find.text('DISPONIBLE'), findsNothing);
      expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
      expect(find.textContaining('Obs: Unida al motor'), findsOneWidget);

      final textWidget = tester.widget<Text>(find.textContaining('Obs: Unida al motor'));
      expect(textWidget.maxLines, 1);
      expect(textWidget.overflow, TextOverflow.ellipsis);
    });

    testWidgets('Item reservado (id_estado = 2) muestra chip RESERVADO y botón desactivado', (tester) async {
      bool tapExecuted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogoItemCard(
              item: itemReservado,
              vendedorSucursalId: 1,
              onAddToCart: () {
                tapExecuted = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('RESERVADO'), findsOneWidget);
      expect(find.byIcon(Icons.lock_clock_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.lock_clock_outlined));
      await tester.pump();

      // No debe haberse ejecutado la función al estar deshabilitado
      expect(tapExecuted, isFalse);
    });
  });

  group('SPEC-HU-TAREA-3: CartController - Integración de Estado', () {
    setUp(() {
      CartController.instance.vaciarCarrito();
    });

    test('Agregar inventariado y verificar estaEnCarrito', () {
      const item = CatalogoItem(
        idActivo: 'act-test-01',
        skuQrFisico: 'SKU-001',
        idCategoria: 1,
        nombreCategoria: 'Motor',
        idSucursalActual: 1,
        nombreSucursal: 'Casa Matriz',
        versionLock: 1,
      );

      final ok = CartController.instance.agregarInventariado(item);
      expect(ok, isTrue);
      expect(CartController.instance.estaEnCarrito('act-test-01'), isTrue);

      // Duplicado no se vuelve a agregar
      final duplicado = CartController.instance.agregarInventariado(item);
      expect(duplicado, isFalse);
      expect(CartController.instance.items.length, equals(1));
    });

    test('Eliminar ítem inventariado lo remueve del carrito', () {
      const item = CatalogoItem(
        idActivo: 'act-test-02',
        skuQrFisico: 'SKU-002',
        idCategoria: 1,
        nombreCategoria: 'Caja',
        idSucursalActual: 1,
        nombreSucursal: 'Casa Matriz',
        versionLock: 1,
      );

      CartController.instance.agregarInventariado(item);
      expect(CartController.instance.items.length, equals(1));

      CartController.instance.eliminarItem('act-test-02', liberarEnBackend: false);
      expect(CartController.instance.items.length, equals(0));
      expect(CartController.instance.estaEnCarrito('act-test-02'), isFalse);
    });
  });
}
