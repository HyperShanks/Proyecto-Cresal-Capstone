// test/features/alertas/auditoria_salida_orden_mixta_test.dart
// Pruebas de widget que validan que la barrera de salida solo exige QR para repuestos activos (inventariados),
// omitiendo la solicitud de escaneo físico para ítems misceláneos o venta libre.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/features/alertas/presentation/screens/auditoria_salida_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String> mockStorage = {};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (MethodCall methodCall) async {
        if (methodCall.method == 'read') {
          return mockStorage[methodCall.arguments['key'] as String];
        } else if (methodCall.method == 'write') {
          mockStorage[methodCall.arguments['key'] as String] = methodCall.arguments['value'] as String;
          return null;
        }
        return null;
      },
    );
  });

  setUp(() {
    mockStorage.clear();
    mockStorage['access_token'] = 'fake-test-jwt-token';
  });

  group('AuditoriaSalidaScreen - Validación de Órdenes Mixtas y Múltiples Activos', () {
    testWidgets(
      'Orden Mixta (1 Motor + 2 Misceláneos): Solo exige 1 QR físico y autoriza salida al escanear el motor',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        bool escanearSalidaLlamado = false;
        List<dynamic>? skusEnviados;

        final mockClient = MockClient((request) async {
          if (request.url.path.contains('/verificar-qr-salida')) {
            return http.Response(
              jsonEncode({
                'id_orden': 'ord-mixta-001',
                'folio': 'ORD-MIX-001',
                'estado_orden': 'Pagada',
                'total_venta': 650000,
                'monto_pendiente': 0,
                'id_sucursal': 1,
                'cliente_nombre': 'Carlos Conductor',
                'cliente_rut': '11.222.333-4',
                'total_items_fisicos': 1,
                'qr_transaccional_salida': 'TX-QR-ORD-MIX-001-TOKEN123',
                'items_requeridos': [
                  {
                    'id_detalle': 'det-001',
                    'id_activo': 'act-motor-01',
                    'titulo': 'Motor Toyota Yaris 1.5 (2019)',
                    'sku_qr_fisico': 'MOT-TOY-YAR-100',
                    'es_inventariado': true,
                    'ubicacion': 'Galpón 1 - Pasillo 3 - Pallet 7',
                    'cantidad': 1,
                    'precio_final': 600000,
                    'qr_impreso': true,
                  },
                  {
                    'id_detalle': 'det-002',
                    'id_activo': null,
                    'titulo': 'Aceite Sintético 5W-30 (4L)',
                    'sku_qr_fisico': 'MISCELÁNEO (No requiere escaneo físico)',
                    'es_inventariado': false,
                    'ubicacion': 'Mostrador / Despacho',
                    'cantidad': 1,
                    'precio_final': 35000,
                    'qr_impreso': true,
                  },
                  {
                    'id_detalle': 'det-003',
                    'id_activo': null,
                    'titulo': 'Filtro de Aceite Universal',
                    'sku_qr_fisico': 'MISCELÁNEO (No requiere escaneo físico)',
                    'es_inventariado': false,
                    'ubicacion': 'Mostrador / Despacho',
                    'cantidad': 1,
                    'precio_final': 15000,
                    'qr_impreso': true,
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }

          if (request.url.path.contains('/escanear-salida')) {
            escanearSalidaLlamado = true;
            final body = jsonDecode(request.body);
            skusEnviados = body['skus_escaneados'];

            return http.Response(
              jsonEncode({
                'id_orden': 'ord-mixta-001',
                'folio': 'ORD-MIX-001',
                'estado_orden': 'Completada',
                'id_bodeguero': 'user-bod-01',
                'bodeguero_nombre': 'Martín Bodeguero',
                'fecha_entrega': '2026-09-15T19:40:00',
                'activos_entregados': ['MOT-TOY-YAR-100'],
                'total_entregados': 1,
                'mensaje': '¡Entrega en barrera autorizada exitosamente!',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }

          return http.Response('{}', 200);
        });

        await tester.pumpWidget(
          MaterialApp(
            home: AuditoriaSalidaScreen(httpClient: mockClient),
          ),
        );
        await tester.pump();

        // 1. Escanear Ticket del Vendedor
        final textField = find.byType(TextField);
        await tester.enterText(textField, 'TX-QR-ORD-MIX-001-TOKEN123');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Debe indicar exactamente 1 repuesto físico requerido (y no 3)
        expect(find.textContaining('1 repuesto(s) físico(s) a despachar'), findsOneWidget);
        expect(find.textContaining('(0/1)'), findsOneWidget);

        // Los misceláneos deben mostrar badge de 'MISCELÁNEO' y texto 'Entrega en mesón'
        expect(find.text('MISCELÁNEO'), findsNWidgets(2));
        expect(find.textContaining('Entrega en mesón (No requiere QR físico)'), findsNWidgets(2));

        // 2. Escanear el único activo físico (Motor)
        await tester.enterText(textField, 'MOT-TOY-YAR-100');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Debe haber invocado escanear-salida sin bloquear
        expect(escanearSalidaLlamado, isTrue);
        expect(skusEnviados, equals(['MOT-TOY-YAR-100']));

        // Debe mostrar el modal de éxito ¡SALIDA AUTORIZADA!
        expect(find.text('¡SALIDA AUTORIZADA!'), findsOneWidget);
      },
    );

    testWidgets(
      'Orden con 2 Activos (Motor + Caja): Exige exactamente 2 escaneos físicos antes de liberar',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        bool escanearSalidaLlamado = false;

        final mockClient = MockClient((request) async {
          if (request.url.path.contains('/verificar-qr-salida')) {
            return http.Response(
              jsonEncode({
                'id_orden': 'ord-doble-002',
                'folio': 'ORD-DOB-002',
                'estado_orden': 'Pagada',
                'total_venta': 950000,
                'monto_pendiente': 0,
                'id_sucursal': 1,
                'cliente_nombre': 'Pedro Repuestos',
                'cliente_rut': '99.888.777-6',
                'total_items_fisicos': 2,
                'qr_transaccional_salida': 'TX-QR-ORD-DOB-002',
                'items_requeridos': [
                  {
                    'id_detalle': 'det-101',
                    'id_activo': 'act-motor-101',
                    'titulo': 'Motor Hyundai Accent',
                    'sku_qr_fisico': 'MOT-HYU-ACC-001',
                    'es_inventariado': true,
                    'ubicacion': 'Galpón 1 - Pasillo 2',
                    'cantidad': 1,
                    'precio_final': 550000,
                    'qr_impreso': true,
                  },
                  {
                    'id_detalle': 'det-102',
                    'id_activo': 'act-caja-102',
                    'titulo': 'Caja de Cambios Hyundai Accent',
                    'sku_qr_fisico': 'CAJ-HYU-ACC-002',
                    'es_inventariado': true,
                    'ubicacion': 'Galpón 1 - Pasillo 5',
                    'cantidad': 1,
                    'precio_final': 400000,
                    'qr_impreso': true,
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }

          if (request.url.path.contains('/escanear-salida')) {
            escanearSalidaLlamado = true;
            return http.Response(
              jsonEncode({
                'id_orden': 'ord-doble-002',
                'folio': 'ORD-DOB-002',
                'estado_orden': 'Completada',
                'id_bodeguero': 'user-bod-01',
                'bodeguero_nombre': 'Martín Bodeguero',
                'fecha_entrega': '2026-09-15T19:42:00',
                'activos_entregados': ['MOT-HYU-ACC-001', 'CAJ-HYU-ACC-002'],
                'total_entregados': 2,
                'mensaje': '¡Entrega en barrera autorizada exitosamente!',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }

          return http.Response('{}', 200);
        });

        await tester.pumpWidget(
          MaterialApp(
            home: AuditoriaSalidaScreen(httpClient: mockClient),
          ),
        );
        await tester.pump();

        // 1. Escanear Ticket
        final textField = find.byType(TextField);
        await tester.enterText(textField, 'TX-QR-ORD-DOB-002');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Debe exigir 2 repuestos físicos
        expect(find.textContaining('2 repuesto(s) físico(s) a despachar'), findsOneWidget);
        expect(find.textContaining('(0/2)'), findsOneWidget);

        // 2. Escaneo del 1er Activo (Motor)
        await tester.enterText(textField, 'MOT-HYU-ACC-001');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // NO debe haber llamado aún a escanear-salida
        expect(escanearSalidaLlamado, isFalse);
        expect(find.textContaining('(1/2)'), findsOneWidget);
        expect(find.textContaining('Faltan 1 repuesto(s) físico(s) por escanear'), findsOneWidget);

        // 3. Escaneo del 2do Activo (Caja)
        await tester.enterText(textField, 'CAJ-HYU-ACC-002');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Ahora sí debe haber llamado a escanear-salida y mostrar diálogo de éxito
        expect(escanearSalidaLlamado, isTrue);
        expect(find.text('¡SALIDA AUTORIZADA!'), findsOneWidget);
      },
    );

    testWidgets(
      'Orden Mixta con 2 Activos + 1 Misceláneo: Requiere 2 escaneos físicos y excluye el misceláneo del conteo',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        bool escanearSalidaLlamado = false;

        final mockClient = MockClient((request) async {
          if (request.url.path.contains('/verificar-qr-salida')) {
            return http.Response(
              jsonEncode({
                'id_orden': 'ord-mixta-2act-003',
                'folio': 'ORD-MIX2-003',
                'estado_orden': 'Pagada',
                'total_venta': 970000,
                'monto_pendiente': 0,
                'id_sucursal': 1,
                'cliente_nombre': 'Ana Mecánica',
                'cliente_rut': '15.555.444-3',
                'total_items_fisicos': 2,
                'qr_transaccional_salida': 'TX-QR-ORD-MIX2-003',
                'items_requeridos': [
                  {
                    'id_detalle': 'det-201',
                    'id_activo': 'act-motor-201',
                    'titulo': 'Motor Nissan Qashqai',
                    'sku_qr_fisico': 'MOT-NIS-QAS-001',
                    'es_inventariado': true,
                    'ubicacion': 'Galpón 2 - Pasillo 1',
                    'cantidad': 1,
                    'precio_final': 600000,
                    'qr_impreso': true,
                  },
                  {
                    'id_detalle': 'det-202',
                    'id_activo': null,
                    'titulo': 'Líquido de Frenos DOT4',
                    'sku_qr_fisico': 'MISCELÁNEO (No requiere escaneo físico)',
                    'es_inventariado': false,
                    'ubicacion': 'Mostrador / Despacho',
                    'cantidad': 1,
                    'precio_final': 20000,
                    'qr_impreso': true,
                  },
                  {
                    'id_detalle': 'det-203',
                    'id_activo': 'act-caja-203',
                    'titulo': 'Caja de Cambios Nissan Qashqai',
                    'sku_qr_fisico': 'CAJ-NIS-QAS-002',
                    'es_inventariado': true,
                    'ubicacion': 'Galpón 2 - Pasillo 4',
                    'cantidad': 1,
                    'precio_final': 350000,
                    'qr_impreso': true,
                  },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }

          if (request.url.path.contains('/escanear-salida')) {
            escanearSalidaLlamado = true;
            return http.Response(
              jsonEncode({
                'id_orden': 'ord-mixta-2act-003',
                'folio': 'ORD-MIX2-003',
                'estado_orden': 'Completada',
                'id_bodeguero': 'user-bod-01',
                'bodeguero_nombre': 'Martín Bodeguero',
                'fecha_entrega': '2026-09-15T19:44:00',
                'activos_entregados': ['MOT-NIS-QAS-001', 'CAJ-NIS-QAS-002'],
                'total_entregados': 2,
                'mensaje': '¡Entrega en barrera autorizada exitosamente!',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }

          return http.Response('{}', 200);
        });

        await tester.pumpWidget(
          MaterialApp(
            home: AuditoriaSalidaScreen(httpClient: mockClient),
          ),
        );
        await tester.pump();

        // 1. Escanear Ticket
        final textField = find.byType(TextField);
        await tester.enterText(textField, 'TX-QR-ORD-MIX2-003');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Debe contar exactamente 2 físicos a pesar de haber 3 ítems totales
        expect(find.textContaining('2 repuesto(s) físico(s) a despachar'), findsOneWidget);
        expect(find.textContaining('(0/2)'), findsOneWidget);
        expect(find.text('MISCELÁNEO'), findsOneWidget);

        // 2. Escanear 1er activo
        await tester.enterText(textField, 'MOT-NIS-QAS-001');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(escanearSalidaLlamado, isFalse);
        expect(find.textContaining('(1/2)'), findsOneWidget);

        // 3. Escanear 2do activo
        await tester.enterText(textField, 'CAJ-NIS-QAS-002');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(escanearSalidaLlamado, isTrue);
        expect(find.text('¡SALIDA AUTORIZADA!'), findsOneWidget);
      },
    );
  });
}
