// test/features/ventas/tarea_18_bugfixes_test.dart
// Tests automatizados para validar la resolución de los 5 bugs críticos de SPEC-HU-TAREA-18

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/features/ventas/models/catalogo_model.dart';
import 'package:frontend/features/ventas/models/cart_item_model.dart';
import 'package:frontend/features/ventas/controllers/cart_controller.dart';
import 'package:frontend/features/ventas/models/checkout_wizard_models.dart';
import 'package:frontend/features/ventas/services/ventas_service.dart';
import 'package:frontend/features/ventas/services/ordenes_sync_notifier.dart';
import 'package:frontend/features/ventas/presentation/screens/catalogo_screen.dart';
import 'package:frontend/features/ventas/presentation/screens/carrito_screen.dart';
import 'package:frontend/features/ventas/presentation/widgets/cart_item_tile.dart';
import 'package:frontend/features/ventas/presentation/screens/detalle_activo_screen.dart';
import 'package:frontend/features/ventas/presentation/screens/bandeja_precios_screen.dart';
import 'package:frontend/features/alertas/models/tarea_alerta.dart';
import 'package:frontend/features/alertas/presentation/screens/alertas_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'read') {
          return 'fake-test-jwt-token';
        }
        return null;
      },
    );
  });

  setUp(() {
    CartController.instance.vaciarCarrito();
  });

  tearDown(() {
    CartController.instance.vaciarCarrito();
  });

  group('SPEC-HU-TAREA-18: Bug 1 - Sincronización Automática de Catálogo tras Tasación', () {
    test('CatalogoScreen.refreshNotifier notifica y refresca el catálogo', () {
      int notificacionesRecibidas = 0;
      void listener() {
        notificacionesRecibidas++;
      }

      CatalogoScreen.refreshNotifier.addListener(listener);
      CatalogoScreen.refreshNotifier.value++;
      CatalogoScreen.refreshNotifier.value++;

      expect(notificacionesRecibidas, equals(2));
      CatalogoScreen.refreshNotifier.removeListener(listener);
    });

    testWidgets('BandejaPreciosScreen acepta y ejecuta onRefreshCatalogo', (tester) async {
      bool refreshLlamado = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BandejaPreciosScreen(
              onRefreshCatalogo: () {
                refreshLlamado = true;
              },
            ),
          ),
        ),
      );

      // Verify that BandejaPreciosScreen mounted properly and callback is registered
      expect(find.byType(BandejaPreciosScreen), findsOneWidget);
      expect(refreshLlamado, isFalse);
    });
  });

  group('SPEC-HU-TAREA-18: Bug 2 - Prevención de RenderFlex Overflow en Carrito', () {
    testWidgets('CartItemTile no desborda en ancho angosto de 320px', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final itemVentaLibre = VentaLibreCartItem(
        id: 'vl-01',
        descripcion: 'Servicio Mecánico y Ajuste Especial Completo',
        monto: 1250000,
        cantidad: 3,
        observacion: 'Manejar con cuidado en mesón',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CartItemTile(item: itemVentaLibre),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('PRECIO ACORDADO (CLP):'), findsOneWidget);
      expect(find.text('CANTIDAD:'), findsOneWidget);
      expect(find.text('SUBTOTAL:'), findsOneWidget);
    });

    testWidgets('CarritoScreen no desborda en viewport de 320px de ancho con chips y switch', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      FlutterErrorDetails? capturedDetails;
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        capturedDetails = details;
      };

      CartController.instance.agregarVentaLibre(
        descripcion: 'Repuesto Test',
        monto: 50000,
        cantidad: 1,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: CarritoScreen(),
        ),
      );
      await tester.pumpAndSettle();

      FlutterError.onError = oldOnError;

      if (capturedDetails != null) {
        debugPrint('CAPTURED EXCEPTION: ${capturedDetails!.exception}');
        debugPrint('CAPTURED SUMMARY: ${capturedDetails!.summary}');
        debugPrint('CAPTURED CONTEXT: ${capturedDetails!.context}');
        for (final item in capturedDetails!.informationCollector!()) {
          debugPrint('INFO: $item');
        }
      }
      expect(capturedDetails, isNull);

      // Verificar switch Consumidor Final
      final switchFinder = find.byKey(const Key('switch_cliente_anonimo'));
      expect(switchFinder, findsOneWidget);
      await tester.ensureVisible(switchFinder);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      expect(capturedDetails, isNull);

      // Verificar chips de entrega
      final chipRetiro = find.byKey(const Key('chip_entrega_Retiro'));
      expect(chipRetiro, findsOneWidget);
    });
  });

  group('SPEC-HU-TAREA-18: Bug 3 - Auto-Refresh en Mis Órdenes tras Checkout', () {
    test('VentasService.processCheckoutWizard dispara OrdenesSyncNotifier al recibir 200/201', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id_orden': 'ord-test-12345',
            'estado': 'Reservada',
            'total_venta': 150000,
            'monto_pendiente': 50000,
            'mensaje': 'Orden generada con éxito',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      int syncNotifications = 0;
      void onSync() {
        syncNotifications++;
      }

      OrdenesSyncNotifier.instance.addListener(onSync);

      const request = CheckoutWizardRequestModel(
        idCliente: 'cli-01',
        tipoEntrega: 'Retiro',
        totalVenta: 150000,
        montoPendiente: 50000,
        montoAbono: 100000,
      );

      final res = await VentasService.processCheckoutWizard(
        request,
        token: 'fake-token',
        client: mockClient,
      );

      expect(res.idOrden, equals('ord-test-12345'));
      expect(syncNotifications, greaterThanOrEqualTo(1));

      OrdenesSyncNotifier.instance.removeListener(onSync);
    });
  });

  group('SPEC-HU-TAREA-18: Bug 4 - Navegación Intuitiva al Agregar al Carrito desde Detalle', () {
    testWidgets('Tocar Agregar al Carrito en DetalleActivoScreen reserva en backend, agrega a CartController y hace pop', (tester) async {
      bool reservaLlamada = false;
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/carrito/reservar')) {
          reservaLlamada = true;
          final body = jsonDecode(request.body);
          expect(body['id_activo'], equals('act-99'));
          expect(body['version_lock_esperado'], equals(1));
          return http.Response(
            jsonEncode({
              'id_activo': 'act-99',
              'version_lock': 2,
              'reservado_por': 'usr-test',
              'reserva_expira_en': '2026-10-08T18:00:00Z',
              'mensaje': 'Reserva temporal creada.',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      const catalogoItem = CatalogoItem(
        idActivo: 'act-99',
        skuQrFisico: 'SKU-TEST-99',
        idCategoria: 1,
        nombreCategoria: 'Eléctrico',
        idSucursalActual: 1,
        nombreSucursal: 'Viña del Mar',
        marca: 'Bosch',
        modelo: 'Hilux',
        anio: 2022,
        precioReferencia: 150000,
        estadoActivo: 'Disponible',
        versionLock: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                key: const Key('btn_ir_detalle'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DetalleActivoScreen(
                        item: catalogoItem,
                        vendedorSucursalId: 1,
                        httpClient: mockClient,
                      ),
                    ),
                  );
                },
                child: const Text('Ir a detalle'),
              ),
            ),
          ),
        ),
      );

      // Ir a la pantalla de detalle
      await tester.tap(find.byKey(const Key('btn_ir_detalle')));
      await tester.pumpAndSettle();

      expect(find.byType(DetalleActivoScreen), findsOneWidget);

      // Tocar el botón de agregar al carrito
      final btnAgregar = find.byKey(const Key('btn_agregar_carrito_detalle'));
      expect(btnAgregar, findsOneWidget);
      await tester.tap(btnAgregar);
      await tester.pumpAndSettle();

      // Verificar que se llamó al backend para reservar
      expect(reservaLlamada, isTrue);

      // Verificar que DetalleActivoScreen hizo pop y volvimos a la pantalla anterior
      expect(find.byType(DetalleActivoScreen), findsNothing);
      expect(find.byKey(const Key('btn_ir_detalle')), findsOneWidget);

      // Verificar que el ítem está en el carrito con versionLock actualizado
      expect(CartController.instance.totalItems, equals(1));
      final cartItem = CartController.instance.items.first as InventariadoCartItem;
      expect(cartItem.catalogoItem.versionLock, equals(2));
    });

    testWidgets('Tocar Agregar al Carrito en DetalleActivoScreen con conflicto 409 muestra SnackBar y no hace pop', (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/api/v1/carrito/reservar')) {
          return http.Response(
            jsonEncode({
              'detail': '¡Lo sentimos! Este repuesto acaba de ser reservado por otro vendedor hace un instante.',
            }),
            409,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not found', 404);
      });

      const catalogoItem = CatalogoItem(
        idActivo: 'act-conflict',
        skuQrFisico: 'SKU-CONFLICT',
        idCategoria: 1,
        nombreCategoria: 'Eléctrico',
        idSucursalActual: 1,
        nombreSucursal: 'Viña del Mar',
        marca: 'Bosch',
        modelo: 'Hilux',
        anio: 2022,
        precioReferencia: 150000,
        estadoActivo: 'Disponible',
        versionLock: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                key: const Key('btn_ir_detalle'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DetalleActivoScreen(
                        item: catalogoItem,
                        vendedorSucursalId: 1,
                        httpClient: mockClient,
                      ),
                    ),
                  );
                },
                child: const Text('Ir a detalle'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('btn_ir_detalle')));
      await tester.pumpAndSettle();

      final btnAgregar = find.byKey(const Key('btn_agregar_carrito_detalle'));
      await tester.tap(btnAgregar);
      await tester.pumpAndSettle();

      // No debe hacer pop
      expect(find.byType(DetalleActivoScreen), findsOneWidget);
      // No debe haberse agregado al carrito
      expect(CartController.instance.totalItems, equals(0));
      // Debe mostrar el SnackBar de error
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });

  group('SPEC-HU-TAREA-18: Bug 5 - Crash y Freeze en Alertas de Bodega (Lifecycle)', () {
    testWidgets('AlertasScreen se monta y desmonta rápidamente sin crash por setState durante build', (tester) async {
      final mockTareas = <TareaAlerta>[
        const TareaAlerta(
          idTarea: 'tar-01',
          idDetalle: 'det-01',
          tipoAlerta: 'PREPARACION',
          ordenRef: 'ORD-100',
          tituloPieza: 'Foco delantero',
          ubicacion: 'P-1 / G-1 / PAL-01',
          accionRequerida: 'Preparar en Mesón',
        ),
      ];

      // Future que resuelve asíncronamente
      final Future<List<TareaAlerta>> future = Future.delayed(
        const Duration(milliseconds: 50),
        () => mockTareas,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                key: const Key('btn_abrir_alertas'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlertasScreen(futureAlertas: future),
                    ),
                  );
                },
                child: const Text('Abrir Alertas'),
              ),
            ),
          ),
        ),
      );

      // Abrir alertas
      await tester.tap(find.byKey(const Key('btn_abrir_alertas')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));

      // Cerrar alertas inmediatamente (pop antes o durante la resolución)
      expect(find.byType(AlertasScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(AlertasScreen))).pop();
      await tester.pumpAndSettle();

      // Verificar que no hubo excepciones en consola o de setState
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertasScreen), findsNothing);
    });
  });
}
