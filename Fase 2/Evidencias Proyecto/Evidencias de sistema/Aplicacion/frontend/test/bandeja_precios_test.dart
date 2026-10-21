// test/bandeja_precios_test.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/features/ventas/models/pendiente_precio_model.dart';
import 'package:frontend/features/ventas/services/inventario_service.dart';
import 'package:frontend/features/ventas/presentation/widgets/pendiente_precio_card.dart';
import 'package:frontend/features/ventas/presentation/widgets/asignar_precio_dialog.dart';
import 'package:frontend/features/ventas/presentation/screens/bandeja_precios_screen.dart';
import 'package:frontend/features/ventas/presentation/screens/ventas_main_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockStorage = {};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'read') {
          final key = methodCall.arguments['key'] as String;
          return mockStorage[key];
        } else if (methodCall.method == 'write') {
          final key = methodCall.arguments['key'] as String;
          final value = methodCall.arguments['value'] as String;
          mockStorage[key] = value;
          return null;
        } else if (methodCall.method == 'delete') {
          final key = methodCall.arguments['key'] as String;
          mockStorage.remove(key);
          return null;
        }
        return null;
      },
    );
  });

  setUp(() {
    mockStorage.clear();
    mockStorage['access_token'] = 'mock_jwt_token_jefe';
    mockStorage['user_rol'] = 'Jefe de Ventas';
    mockStorage['user_id_rol'] = '6';
  });

  final Map<String, dynamic> rawPendienteJson = {
    'id_activo': '33333333-3333-3333-3333-333333333333',
    'sku_qr_fisico': 'MOT-HYU-ACC-001',
    'id_categoria': 1,
    'nombre_categoria': 'Motor',
    'id_sucursal_actual': 1,
    'nombre_sucursal': 'Casa Matriz',
    'ubicacion_pasillo': 'P-03',
    'ubicacion_pallet': 'PL-10',
    'id_vehiculo': 'vvvvvvvv-vvvv-vvvv-vvvv-vvvvvvvvvvvv',
    'numero_ingreso': 'ING-2026-888',
    'marca': 'Hyundai',
    'modelo': 'Accent',
    'anio': 2020,
    'traccion': '4x2',
    'cilindrada': '1.4L',
    'combustible': 'Gasolina',
    'transmision_tipo': 'Manual',
    'titulo_repuesto': 'Motor - Hyundai Accent 2020',
    'estado_activo': 'En Desarme',
    'fecha_creacion': '2026-08-14T10:30:00',
  };

  // ─────────────────────────────────────────────────────────────────────────────
  // 1. UNIT TESTS: MODELOS DTO
  // ─────────────────────────────────────────────────────────────────────────────
  group('PendientePrecioModel Unit Tests', () {
    test('ActivoPendientePrecioModel.fromJson parsea todos los campos y getters', () {
      final model = ActivoPendientePrecioModel.fromJson(rawPendienteJson);

      expect(model.idActivo, '33333333-3333-3333-3333-333333333333');
      expect(model.skuQrFisico, 'MOT-HYU-ACC-001');
      expect(model.idCategoria, 1);
      expect(model.nombreCategoria, 'Motor');
      expect(model.nombreSucursal, 'Casa Matriz');
      expect(model.marca, 'Hyundai');
      expect(model.modelo, 'Accent');
      expect(model.anio, 2020);
      expect(model.cilindrada, '1.4L');
      expect(model.combustible, 'Gasolina');
      expect(model.transmisionTipo, 'Manual');
      expect(model.tituloRepuesto, 'Motor - Hyundai Accent 2020');

      // Getters
      expect(model.ubicacionDisplay, 'P-03 • PL-10');
      expect(model.fichaVehiculoDisplay, 'Hyundai Accent 2020');
      expect(model.especificacionesDisplay, '1.4L • Gasolina • Manual • 4x2');
      expect(model.fechaCreacionFormateada, contains('14/08/2026'));
    });

    test('AsignarPrecioResponseModel.fromJson formatea moneda en pesos chilenos', () {
      final jsonResponse = {
        'id_activo': '33333333-3333-3333-3333-333333333333',
        'sku_qr_fisico': 'MOT-HYU-ACC-001',
        'precio_referencia': 580000,
        'estado_activo': 'Disponible',
        'mensaje': 'Precio asignado exitosamente.',
      };

      final responseModel = AsignarPrecioResponseModel.fromJson(jsonResponse);
      expect(responseModel.precioReferencia, 580000);
      expect(responseModel.estadoActivo, 'Disponible');
      expect(responseModel.precioFormateado, contains('580.000'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 2. UNIT TESTS: INVENTARIO SERVICE (HTTP MOCK)
  // ─────────────────────────────────────────────────────────────────────────────
  group('InventarioService HTTP Client Tests', () {
    test('obtenerPendientesPrecio retorna lista de modelos en respuesta 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, endsWith('/pendientes-precio'));
        expect(request.headers['Authorization'], 'Bearer mock_jwt_token_jefe');

        return http.Response(
          jsonEncode([rawPendienteJson]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final items = await InventarioService.obtenerPendientesPrecio(client: mockClient);
      expect(items.length, 1);
      expect(items.first.skuQrFisico, 'MOT-HYU-ACC-001');
      expect(items.first.tituloRepuesto, 'Motor - Hyundai Accent 2020');
    });

    test('obtenerPendientesPrecio lanza excepción descriptiva ante 403 Forbidden', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Acceso restringido: Se requiere rol de Jefe de Ventas para esta operación.'}),
          403,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      expect(
        () async => await InventarioService.obtenerPendientesPrecio(client: mockClient),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('Acceso restringido'))),
      );
    });

    test('asignarPrecio envía payload y retorna AsignarPrecioResponseModel en 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, contains('/precio'));
        final body = jsonDecode(request.body);
        expect(body['precio_referencia'], 580000);

        return http.Response(
          jsonEncode({
            'id_activo': '33333333-3333-3333-3333-333333333333',
            'sku_qr_fisico': 'MOT-HYU-ACC-001',
            'precio_referencia': 580000,
            'estado_activo': 'Disponible',
            'mensaje': 'Precio asignado exitosamente. El repuesto ahora está disponible en el catálogo de ventas.',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final response = await InventarioService.asignarPrecio(
        '33333333-3333-3333-3333-333333333333',
        precioMinimo: 500000,
        precioMaximo: 600000,
        precioReferencia: 580000,
        client: mockClient,
      );

      expect(response.precioReferencia, 580000);
      expect(response.estadoActivo, 'Disponible');
      expect(response.mensaje, contains('Precio asignado exitosamente'));
    });

    test('asignarPrecio lanza excepción descriptiva ante 422 Unprocessable Entity', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Validation error'}),
          422,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      expect(
        () async => await InventarioService.asignarPrecio(
          '33333333-3333-3333-3333-333333333333',
          precioMinimo: 0,
          precioMaximo: 0,
          client: mockClient,
        ),
        throwsA(isA<Exception>().having((e) => e.toString(), 'msg', contains('precio ingresado no es válido'))),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 3. WIDGET TESTS: PendientePrecioCard & AsignarPrecioDialog
  // ─────────────────────────────────────────────────────────────────────────────
  group('PendientePrecioCard Widget Tests', () {
    testWidgets('Renderiza Título, SKU, Ficha de Vehículo, Ubicación y Botón', (tester) async {
      final model = ActivoPendientePrecioModel.fromJson(rawPendienteJson);
      bool tapExecuted = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PendientePrecioCard(
              activo: model,
              onAsignarPrecio: () => tapExecuted = true,
            ),
          ),
        ),
      );

      expect(find.text('Motor - Hyundai Accent 2020'), findsOneWidget);
      expect(find.text('MOT-HYU-ACC-001'), findsOneWidget);
      expect(find.text('Motor'), findsOneWidget);
      expect(find.text('Hyundai Accent 2020'), findsOneWidget);
      expect(find.text('Casa Matriz • P-03 • PL-10'), findsOneWidget);
      expect(find.text('Fijar Precio de Referencia'), findsOneWidget);

      // Tap en botón de acción
      await tester.tap(find.text('Fijar Precio de Referencia'));
      expect(tapExecuted, isTrue);
    });
  });

  group('AsignarPrecioDialog Widget Tests', () {
    testWidgets('Renderiza formulario, valida campo vacío y permite cancelar', (tester) async {
      final model = ActivoPendientePrecioModel.fromJson(rawPendienteJson);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => AsignarPrecioDialog.show(
                    ctx,
                    activo: model,
                    onPrecioAsignado: () {},
                  ),
                  child: const Text('Abrir Diálogo'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Diálogo'));
      await tester.pumpAndSettle();

      expect(find.text('Fijar Precio de Referencia'), findsOneWidget);
      expect(find.text('PRECIO DE REFERENCIA (CLP)'), findsOneWidget);
      expect(find.text('Confirmar Precio'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);

      // Tap en Confirmar con campo vacío
      await tester.tap(find.text('Confirmar Precio'));
      await tester.pumpAndSettle();

      expect(find.text('Ingresa un precio de referencia'), findsOneWidget);

      // Cancelar
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('PRECIO DE REFERENCIA (CLP)'), findsNothing);
    });

    testWidgets('En pantalla móvil estrecha (360x640) botones Cancelar y Confirmar se renderizan completos', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final model = ActivoPendientePrecioModel.fromJson(rawPendienteJson);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => AsignarPrecioDialog.show(
                    ctx,
                    activo: model,
                    onPrecioAsignado: () {},
                  ),
                  child: const Text('Abrir Diálogo'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Diálogo'));
      await tester.pumpAndSettle();

      expect(find.text('Cancelar'), findsOneWidget);
      expect(find.text('Confirmar Precio'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 4. WIDGET TESTS: BandejaPreciosScreen
  // ─────────────────────────────────────────────────────────────────────────────
  group('BandejaPreciosScreen Widget Tests', () {
    testWidgets('Renderiza AppBar con título y acción de refresh', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BandejaPreciosScreen(),
        ),
      );

      expect(find.text('Bandeja de Precios'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────────
  // 5. RBAC TESTS: VentasMainScreen Drawer y BottomNavigationBar
  // ─────────────────────────────────────────────────────────────────────────────
  group('VentasMainScreen RBAC Tests', () {
    testWidgets('Jefe de Ventas (id_rol == 6) ve opción BANDEJA DE PRECIOS en Drawer y 4 pestañas en BottomNav', (tester) async {
      mockStorage['user_id_rol'] = '6';
      mockStorage['user_rol'] = 'Jefe de Ventas';

      await tester.pumpWidget(
        const MaterialApp(
          home: VentasMainScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar 4 pestañas en BottomNavigationBar
      expect(find.text('Catálogo'), findsOneWidget);
      expect(find.text('Mis Órdenes'), findsOneWidget);
      expect(find.text('Tasación'), findsOneWidget);
      expect(find.text('Carrito'), findsOneWidget);

      // Navegar a Tasación
      await tester.tap(find.text('Tasación'));
      await tester.pumpAndSettle();
      expect(find.text('Bandeja de Precios'), findsOneWidget);

      // Abrir Drawer de hamburguesa
      await tester.tap(find.byTooltip('Menú principal').first);
      await tester.pumpAndSettle();

      expect(find.text('ENTREGAS Y ENVÍOS'), findsOneWidget);
      expect(find.text('TICKET'), findsOneWidget);
      expect(find.text('CONFIGURACIÓN'), findsOneWidget);
      expect(find.text('BANDEJA DE PRECIOS'), findsOneWidget);
      expect(find.byIcon(Icons.price_change_outlined), findsWidgets);
    });

    testWidgets('Vendedor regular (id_rol == 2) ve 3 pestañas, ENTREGAS Y ENVÍOS y NO ve Tasación', (tester) async {
      mockStorage['user_id_rol'] = '2';
      mockStorage['user_rol'] = 'Vendedor';

      await tester.pumpWidget(
        const MaterialApp(
          home: VentasMainScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar exactamente 3 pestañas
      expect(find.text('Catálogo'), findsOneWidget);
      expect(find.text('Mis Órdenes'), findsOneWidget);
      expect(find.text('Tasación'), findsNothing);
      expect(find.text('Carrito'), findsOneWidget);

      // Abrir Drawer de hamburguesa
      await tester.tap(find.byTooltip('Menú principal').first);
      await tester.pumpAndSettle();

      expect(find.text('ENTREGAS Y ENVÍOS'), findsOneWidget);
      expect(find.text('TICKET'), findsOneWidget);
      expect(find.text('CONFIGURACIÓN'), findsOneWidget);
      expect(find.text('BANDEJA DE PRECIOS'), findsNothing);
    });

    testWidgets('VendedorOnline (id_rol == 7) ve 3 pestañas, NO ve ENTREGAS Y ENVÍOS ni Tasación', (tester) async {
      mockStorage['user_id_rol'] = '7';
      mockStorage['user_rol'] = 'Vendedor Online';

      await tester.pumpWidget(
        const MaterialApp(
          home: VentasMainScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar exactamente 3 pestañas
      expect(find.text('Catálogo'), findsOneWidget);
      expect(find.text('Mis Órdenes'), findsOneWidget);
      expect(find.text('Tasación'), findsNothing);
      expect(find.text('Carrito'), findsOneWidget);

      // Abrir Drawer de hamburguesa
      await tester.tap(find.byTooltip('Menú principal').first);
      await tester.pumpAndSettle();

      expect(find.text('VENDEDOR ONLINE'), findsOneWidget);
      expect(find.text('ENTREGAS Y ENVÍOS'), findsNothing);
      expect(find.text('TICKET'), findsOneWidget);
      expect(find.text('CONFIGURACIÓN'), findsOneWidget);
      expect(find.text('BANDEJA DE PRECIOS'), findsNothing);
    });
  });
}
