import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/features/ventas/presentation/widgets/asignar_activo_vendedor_dialog.dart';
import 'package:frontend/features/ventas/services/ordenes_service.dart';

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

  // Datos mock para Orden de Venta en Verde de Motor
  OrdenHistorialModel crearOrdenMotorMock({
    String titulo = '[VENTA EN VERDE] Motor - Peugeot 206 (2008)',
    String? notas = 'Cliente solicita con poleas y sensor CKP',
  }) {
    return OrdenHistorialModel(
      idOrden: '3fa85f64-5717-4562-b3fc-2c963f66afa6',
      numeroOrden: 29,
      folio: 'ORD-0029',
      estadoOrden: 'Pagada',
      totalVenta: 300000,
      montoPendiente: 0,
      totalItems: 1,
      cliente: const ClienteOrdenResumenModel(
        rutCliente: '11.111.111-1',
        nombres: 'DDD',
        apellidos: 'dDDD',
        telefono: '+56911111111',
      ),
      detalles: [
        DetalleOrdenItemModel(
          idDetalle: 'det-motor-01',
          idCategoria: 1,
          nombreCategoria: 'Motor',
          titulo: titulo,
          notasPreparacion: notas,
          cantidad: 1,
          precioFinal: 300000,
          subtotal: 300000,
          esInventariado: false, // Backorder pendiente
        ),
      ],
    );
  }

  // Datos mock para Orden de Venta en Verde de Caja de Cambios
  OrdenHistorialModel crearOrdenCajaMock() {
    return OrdenHistorialModel(
      idOrden: 'caja-8888-4562-b3fc-2c963f66afa6',
      numeroOrden: 30,
      folio: 'ORD-0030',
      estadoOrden: 'Pagada',
      totalVenta: 250000,
      montoPendiente: 0,
      totalItems: 1,
      cliente: const ClienteOrdenResumenModel(
        rutCliente: '22.222.222-2',
        nombres: 'María',
        apellidos: 'González',
      ),
      detalles: [
        DetalleOrdenItemModel(
          idDetalle: 'det-caja-01',
          idCategoria: 2,
          nombreCategoria: 'Caja de Cambios',
          titulo: '[VENTA EN VERDE] Caja de Cambios - Toyota Yaris (2019)',
          notasPreparacion: 'Caja manual de 5 velocidades',
          cantidad: 1,
          precioFinal: 250000,
          subtotal: 250000,
          esInventariado: false,
        ),
      ],
    );
  }

  Widget createTestWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  group('AsignarActivoVendedorDialog - Detección Automática y Contexto', () {
    testWidgets('Detecta automáticamente Motor (MOT-) y elimina el Dropdown selector',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final orden = crearOrdenMotorMock();

      await tester.pumpWidget(
        createTestWidget(
          AsignarActivoVendedorDialog(
            orden: orden,
            onAsignadoExitoso: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar que NO existe selector DropdownButton
      expect(find.byType(DropdownButton<String>), findsNothing);

      // Verificar que aparece el badge fijo del prefijo y filtro MOT-
      expect(find.text('MOT-'), findsOneWidget);
      expect(find.text('Filtro: MOT-'), findsOneWidget);
      expect(find.text('Asignar Motor a Orden'), findsOneWidget);
    });

    testWidgets('Detecta automáticamente Caja de Cambios (CAJ-) en orden de caja',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final orden = crearOrdenCajaMock();

      await tester.pumpWidget(
        createTestWidget(
          AsignarActivoVendedorDialog(
            orden: orden,
            onAsignadoExitoso: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.text('CAJ-'), findsOneWidget);
      expect(find.text('Filtro: CAJ-'), findsOneWidget);
      expect(find.text('Asignar Caja de Cambios a Orden'), findsOneWidget);
    });

    testWidgets('Exhibe la ficha contextual superior con marca, modelo, año y cliente',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final orden = crearOrdenMotorMock(
        titulo: '[VENTA EN VERDE] Motor - Peugeot 206 (2008)',
        notas: 'Cliente solicita con poleas y sensor CKP',
      );

      await tester.pumpWidget(
        createTestWidget(
          AsignarActivoVendedorDialog(
            orden: orden,
            onAsignadoExitoso: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar presencia de elementos en la ficha contextual superior
      expect(find.text('SOLICITADO POR EL CLIENTE'), findsOneWidget);
      expect(find.text('Peugeot 206'), findsOneWidget);
      expect(find.text('(2008)'), findsOneWidget);
      expect(find.textContaining('DDD dDDD • RUT: 11.111.111-1'), findsOneWidget);
      expect(find.text('Cliente solicita con poleas y sensor CKP'), findsOneWidget);
    });
  });

  group('AsignarActivoVendedorDialog - Validación y Comparativa Visual sin Bloqueo', () {
    testWidgets(
        'Al validar ingreso 1000, muestra comparativa lado a lado y mantiene botón habilitado ante diferencias',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool asignacionExitosaLlamada = false;
      bool forzarEnviado = false;

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/validar-activo-backorder')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['sku_activo'], 'MOT-1000');

          return http.Response(
            jsonEncode({
              'coincide': false,
              'discrepancias': [
                'Marca requerida: Peugeot, Marca del repuesto: PEUGEOT',
                'Modelo requerido: 206, Modelo del repuesto: 206 XLINE 1.6',
                'Cilindrada requerida: 1.4, Cilindrada del repuesto: 1.6',
              ],
              'mensaje': 'Hay discrepancias en los atributos técnicos.',
              'activo_detalle': {
                'sku': 'MOT-1000',
                'categoria': 'Motor',
                'marca': 'PEUGEOT',
                'modelo': '206 XLINE 1.6',
                'anio': 2008,
                'cilindrada': '1.6',
                'combustible': 'Bencina',
                'transmision': 'Manual',
                'ubicacion': 'Galpón 1 • Pasillo B • Pallet 22',
                'estado_conservacion': 'Disponible',
                'numero_motor': 'PSA-98231',
              },
              'solicitado_detalle': {
                'categoria': 'Motor',
                'marca': 'Peugeot',
                'modelo': '206',
                'anio': 2008,
                'cilindrada': '1.4',
                'combustible': 'Bencina',
                'transmision': 'Manual',
                'notas': 'Con accesorios',
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        if (request.url.path.contains('/asignar-activo-backorder')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['sku_activo'], 'MOT-1000');
          forzarEnviado = body['forzar_atribucion'] == true;

          return http.Response(
            jsonEncode({
              'success': true,
              'mensaje': 'Activo asignado exitosamente',
              'id_orden': '3fa85f64-5717-4562-b3fc-2c963f66afa6',
              'folio': 'ORD-0029',
              'sku_asignado': 'MOT-1000',
              'qr_transaccional_salida': 'TX-QR-TEST-1234',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        return http.Response('Not found', 404);
      });

      final orden = crearOrdenMotorMock();

      await tester.pumpWidget(
        createTestWidget(
          AsignarActivoVendedorDialog(
            orden: orden,
            onAsignadoExitoso: () {
              asignacionExitosaLlamada = true;
            },
            httpClient: mockClient,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Digitar únicamente el correlativo "1000"
      final inputFinder = find.byKey(const Key('input_numero_ingreso_backorder'));
      await tester.enterText(inputFinder, '1000');
      await tester.pump();

      // Pulsar Validar
      final btnValidarFinder = find.byKey(const Key('btn_validar_ingreso_backorder'));
      await tester.tap(btnValidarFinder);
      await tester.pumpAndSettle();

      // 1. Cero bloqueos rojos: No debe existir el botón punitivo rojo
      expect(find.text('Forzar asignación manual (Ignorar advertencia)'), findsNothing);

      // 2. Debe exhibirse la comparativa visual lado a lado
      expect(find.text('ATRIBUTO'), findsOneWidget);
      expect(find.text('SOLICITADO'), findsOneWidget);
      expect(find.textContaining('VEHÍCULO DONANTE (MOT-1000)'), findsOneWidget);

      // 3. Debe exhibir el aviso informativo en tono preventivo (ámbar/aviso)
      expect(find.textContaining('Aviso de Compatibilidad: Se detectaron diferencias técnicas.'), findsOneWidget);
      expect(find.textContaining('Galpón 1 • Pasillo B • Pallet 22'), findsOneWidget);

      // 4. El botón "Confirmar Asignación y Generar QR" DEBE ESTAR HABILITADO
      final btnConfirmarFinder = find.byKey(const Key('btn_confirmar_asignacion_backorder'));
      expect(btnConfirmarFinder, findsOneWidget);

      final ElevatedButton btnWidget = tester.widget(btnConfirmarFinder);
      expect(btnWidget.onPressed, isNotNull, reason: 'El botón de asignación debe permanecer activo');

      // 5. Presionar confirmar asignación
      await tester.ensureVisible(btnConfirmarFinder);
      await tester.pumpAndSettle();
      await tester.tap(btnConfirmarFinder);
      await tester.pumpAndSettle();

      // Verificar que se envió forzar_atribucion: true automáticamente al backend
      expect(forzarEnviado, isTrue, reason: 'Debe enviar forzar: true automáticamente por criterio comercial');
      expect(asignacionExitosaLlamada, isTrue);
    });

    testWidgets('Muestra error amigable cuando el número de ingreso no existe en inventario (404)',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': "No se encontró un Motor asociado al ingreso o SKU 'MOT-9999' en inventario."
          }),
          404,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final orden = crearOrdenMotorMock();

      await tester.pumpWidget(
        createTestWidget(
          AsignarActivoVendedorDialog(
            orden: orden,
            onAsignadoExitoso: () {},
            httpClient: mockClient,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('input_numero_ingreso_backorder')),
        '9999',
      );
      await tester.tap(find.byKey(const Key('btn_validar_ingreso_backorder')));
      await tester.pumpAndSettle();

      // Debe mostrar el mensaje claro en español sin crashear
      expect(find.text('No se pudo encontrar el repuesto'), findsOneWidget);
      expect(
        find.textContaining("No se encontró un Motor asociado al ingreso o SKU 'MOT-9999'"),
        findsOneWidget,
      );
    });
  });
}
