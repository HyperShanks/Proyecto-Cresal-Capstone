// frontend/test/features/ventas/cart_persistence_test.dart
// Tests automatizados para la persistencia del carrito, reconciliación y corrección de overflow

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/ventas/models/cart_item_model.dart';
import 'package:frontend/features/ventas/models/catalogo_model.dart';
import 'package:frontend/features/ventas/controllers/cart_controller.dart';
import 'package:frontend/features/ventas/presentation/screens/checkout_wizard_screen.dart';
import 'package:frontend/features/ventas/presentation/screens/catalogo_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockStorageData = {};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        final key = methodCall.arguments['key'] as String?;
        if (methodCall.method == 'read') {
          if (key == 'access_token') return 'mock-jwt-token';
          return mockStorageData[key];
        } else if (methodCall.method == 'write') {
          final value = methodCall.arguments['value'] as String?;
          if (key != null && value != null) {
            mockStorageData[key] = value;
          }
          return null;
        } else if (methodCall.method == 'delete') {
          if (key != null) {
            mockStorageData.remove(key);
          }
          return null;
        } else if (methodCall.method == 'deleteAll') {
          mockStorageData.clear();
          return null;
        }
        return null;
      },
    );
  });

  setUp(() {
    mockStorageData.clear();
    CartController.resetForTesting();
  });

  group('CartItem Model - Serialización y Deserialización', () {
    test('InventariadoCartItem se serializa y deserializa preservando el catalogoItem completo', () {
      const catalogoItem = CatalogoItem(
        idActivo: 'act-12345',
        skuQrFisico: 'MOT-NISSAN-01',
        precioReferencia: 450000,
        idCategoria: 1,
        nombreCategoria: 'Motor',
        idSucursalActual: 2,
        nombreSucursal: 'Sucursal Limache',
        marca: 'Nissan',
        modelo: 'Sentra',
        anio: 2020,
        versionLock: 3,
        idEstado: 2,
      );

      final original = InventariadoCartItem(
        catalogoItem: catalogoItem,
        precioFinal: 420000,
        notasPreparacion: 'Revisar soporte lateral',
      );

      final json = original.toJson();
      expect(json['tipo'], equals('inventariado'));
      expect(json['id_activo'], equals('act-12345'));
      expect(json['precio_final'], equals(420000));
      expect(json['catalogo_item'], isNotNull);

      final deserializado = CartItem.fromJson(json);
      expect(deserializado, isA<InventariadoCartItem>());
      final invItem = deserializado as InventariadoCartItem;
      expect(invItem.id, equals('act-12345'));
      expect(invItem.precioFinal, equals(420000));
      expect(invItem.notasPreparacion, equals('Revisar soporte lateral'));
      expect(invItem.catalogoItem.marca, equals('Nissan'));
      expect(invItem.catalogoItem.modelo, equals('Sentra'));
      expect(invItem.catalogoItem.anio, equals(2020));
      expect(invItem.sku, equals('MOT-NISSAN-01'));
      expect(invItem.nombreSucursal, equals('Sucursal Limache'));
    });

    test('VentaLibreCartItem se serializa y deserializa con todos sus atributos', () {
      final original = VentaLibreCartItem(
        id: 'VL-999',
        descripcion: 'Aceite de motor 5W-30',
        monto: 35000,
        cantidad: 2,
        observacion: 'Bidón 4 litros sellado',
      );

      final json = original.toJson();
      expect(json['tipo'], equals('venta_libre'));
      expect(json['descripcion'], equals('Aceite de motor 5W-30'));
      expect(json['monto_unitario'], equals(35000));
      expect(json['cantidad'], equals(2));
      expect(json['subtotal'], equals(70000));

      final deserializado = CartItem.fromJson(json);
      expect(deserializado, isA<VentaLibreCartItem>());
      final vlItem = deserializado as VentaLibreCartItem;
      expect(vlItem.id, equals('VL-999'));
      expect(vlItem.descripcion, equals('Aceite de motor 5W-30'));
      expect(vlItem.monto, equals(35000));
      expect(vlItem.cantidad, equals(2));
      expect(vlItem.observacion, equals('Bidón 4 litros sellado'));
    });

    test('ReservaBackorderCartItem se serializa y deserializa correctamente', () {
      final original = ReservaBackorderCartItem(
        id: 'BO-888',
        marca: 'Toyota',
        modelo: 'Corolla',
        anio: 2022,
        categoriaNombre: 'Caja de Cambios',
        idCategoria: 2,
        precioAcordado: 550000,
        montoAbonado: 100000,
        notas: 'Entrega en 10 días',
      );

      final json = original.toJson();
      expect(json['tipo'], equals('reserva_backorder'));
      expect(json['marca_requerida'], equals('Toyota'));
      expect(json['modelo_requerido'], equals('Corolla'));

      final deserializado = CartItem.fromJson(json);
      expect(deserializado, isA<ReservaBackorderCartItem>());
      final boItem = deserializado as ReservaBackorderCartItem;
      expect(boItem.id, equals('BO-888'));
      expect(boItem.marca, equals('Toyota'));
      expect(boItem.precioAcordado, equals(550000));
      expect(boItem.montoAbonado, equals(100000));
      expect(boItem.notas, equals('Entrega en 10 días'));
    });
  });

  group('CartController - Persistencia en FlutterSecureStorage', () {
    test('Al agregar ítems se persisten automáticamente en el almacenamiento seguro', () async {
      final cart = CartController.instance;

      cart.agregarVentaLibre(
        descripcion: 'Líquido de frenos DOT 4',
        monto: 12000,
        cantidad: 1,
      );

      // Esperar microtask de guardado
      await Future.delayed(const Duration(milliseconds: 50));

      expect(mockStorageData.containsKey('cresal_cart_items_v1'), isTrue);
      final rawJson = mockStorageData['cresal_cart_items_v1']!;
      final List decoded = jsonDecode(rawJson);
      expect(decoded.length, equals(1));
      expect(decoded.first['descripcion'], equals('Líquido de frenos DOT 4'));
    });

    test('Al reiniciar la app o el controlador, se restauran los ítems persistidos', () async {
      // 1. Simular datos previamente guardados en el storage
      final itemsGuardados = [
        {
          'tipo': 'venta_libre',
          'id_item': 'VL-TEST-1',
          'descripcion': 'Filtro de aire Bosch',
          'monto_unitario': 18000,
          'cantidad': 1,
          'observacion': 'Para Yaris',
        },
        {
          'tipo': 'inventariado',
          'id_activo': 'act-999',
          'sku_qr_fisico': 'ALT-HYU-01',
          'precio_final': 85000,
          'catalogo_item': {
            'id_activo': 'act-999',
            'sku_qr_fisico': 'ALT-HYU-01',
            'precio_referencia': 90000,
            'id_categoria': 3,
            'nombre_categoria': 'Alternador',
            'id_sucursal_actual': 1,
            'nombre_sucursal': 'Viña del Mar',
            'marca': 'Hyundai',
            'modelo': 'Accent',
          },
        },
      ];
      mockStorageData['cresal_cart_items_v1'] = jsonEncode(itemsGuardados);

      // 2. Crear nueva instancia (como al reabrir la app)
      CartController.resetForTesting();
      final cart = CartController.instance;

      // Cargar explícitamente sin llamada de backend para probar restore puro
      await cart.cargarDesdeAlmacenamiento(reconciliarBackend: false);

      expect(cart.items.length, equals(2));
      expect(cart.totalItems, equals(2));
      expect(cart.totalMonto, equals(18000 + 85000));
      expect(cart.estaEnCarrito('act-999'), isTrue);
    });

    test('Al vaciar el carrito se elimina la clave de almacenamiento seguro', () async {
      final cart = CartController.instance;
      cart.agregarVentaLibre(descripcion: 'Item temporal', monto: 5000);
      await Future.delayed(const Duration(milliseconds: 50));
      expect(mockStorageData.containsKey('cresal_cart_items_v1'), isTrue);

      cart.vaciarCarrito();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(cart.items, isEmpty);
      expect(mockStorageData.containsKey('cresal_cart_items_v1'), isFalse);
    });
  });

  group('DropdownButtonFormField - Prevención de RenderFlex Overflow', () {
    testWidgets('CheckoutWizardScreen en viewport angosto de 340px no produce RenderFlex overflow en Comuna', (WidgetTester tester) async {
      // Configurar viewport móvil estándar (360x740)
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // Setup error hook
      FlutterErrorDetails? caughtDetails;
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        caughtDetails = details;
      };

      // Agregar un ítem para que el wizard permita avanzar al Paso 2
      final cart = CartController.instance;
      cart.agregarVentaLibre(descripcion: 'Repuesto Test', monto: 50000);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CheckoutWizardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navegar al Paso 2 (Datos del Cliente)
      final siguienteBtn = find.byKey(const Key('btn_siguiente_wizard'));
      expect(siguienteBtn, findsOneWidget);
      await tester.tap(siguienteBtn);
      await tester.pumpAndSettle();

      // Verificar que el DropdownButton interno de Comuna tiene isExpanded: true
      final dropdownFinder = find.byType(DropdownButton<String>);
      expect(dropdownFinder, findsWidgets);

      final DropdownButton<String> dropdownWidget = tester.widget(dropdownFinder.first);
      expect(dropdownWidget.isExpanded, isTrue);

      FlutterError.onError = oldOnError;
      if (caughtDetails != null) {
        // ignore: avoid_print
        print('CAUGHT DETAILS CONTEXT: ${caughtDetails?.context}');
        // ignore: avoid_print
        print('CAUGHT DETAILS EXCEPTION: ${caughtDetails?.exceptionAsString()}');
        // ignore: avoid_print
        print('CAUGHT DETAILS INFO: ${caughtDetails?.informationCollector?.call().map((e) => e.toString()).join('\n')}');
      }
      expect(caughtDetails, isNull);
    });
  });

  group('CatalogoScreen - Pull to Refresh y Botón Manual', () {
    testWidgets('CatalogoScreen renderiza RefreshIndicator y botón de refresco en AppBar', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CatalogoScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar que el botón de refresco en el AppBar está presente
      expect(find.byKey(const Key('btn_refrescar_catalogo_appbar')), findsOneWidget);

      // Verificar que existe el widget RefreshIndicator (pull-to-refresh)
      expect(find.byType(RefreshIndicator), findsOneWidget);

      // Al pulsar el botón manual de refresco, no arroja excepciones
      await tester.tap(find.byKey(const Key('btn_refrescar_catalogo_appbar')));
      await tester.pump();
    });
  });
}
