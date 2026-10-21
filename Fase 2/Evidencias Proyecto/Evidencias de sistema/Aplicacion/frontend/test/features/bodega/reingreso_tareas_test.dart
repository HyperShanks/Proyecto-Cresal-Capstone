import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/features/alertas/services/bodega_service.dart';
import 'package:frontend/features/bodega/presentation/screens/reingreso_tareas_screen.dart';

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

  group('BodegaService - Logística Inversa Unit Tests', () {
    test('obtenerReingresosPendientes retorna lista de tareas correctamente', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, contains('/reingresos-pendientes'));
        expect(request.url.queryParameters['sucursal_id'], '10');

        return http.Response(
          jsonEncode([
            {
              'id_orden': 'ord-12345678',
              'id_activo': 'act-001',
              'sku_qr_fisico': 'MOT-NIS-SEN-001',
              'ubicacion_pallet': 'PAL-01',
              'ubicacion_pasillo': 'P-01',
              'descripcion_pieza': 'Motor Nissan Sentra 2021',
              'folio_orden': 'ORD-A1B2C3D4',
              'motivo_anulacion': 'Devolución cliente',
            }
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final tareas = await BodegaService.obtenerReingresosPendientes(
        sucursalId: 10,
        client: mockClient,
      );

      expect(tareas.length, 1);
      expect(tareas.first.skuQrFisico, 'MOT-NIS-SEN-001');
      expect(tareas.first.descripcionPieza, 'Motor Nissan Sentra 2021');
      expect(tareas.first.folioOrden, 'ORD-A1B2C3D4');
    });

    test('confirmarReingreso envía payload correcto y parsea respuesta 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, contains('/confirmar-reingreso'));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['sku_qr_fisico'], 'MOT-NIS-SEN-001');
        expect(body['id_orden_anulada'], 'ord-12345678');
        expect(body['ubicacion_pasillo'], 'P-03');
        expect(body['ubicacion_pallet'], 'PAL-99');

        return http.Response(
          jsonEncode({
            'msg': 'Activo reingresado y disponible exitosamente',
            'id_activo': 'act-001',
            'sku_qr_fisico': 'MOT-NIS-SEN-001',
            'nuevo_estado': 'Disponible',
            'ubicacion_pasillo': 'P-03',
            'ubicacion_pallet': 'PAL-99',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final res = await BodegaService.confirmarReingreso(
        skuQrFisico: 'MOT-NIS-SEN-001',
        idOrdenAnulada: 'ord-12345678',
        ubicacionPasillo: 'P-03',
        ubicacionPallet: 'PAL-99',
        client: mockClient,
      );

      expect(res.msg, contains('disponible'));
      expect(res.skuQrFisico, 'MOT-NIS-SEN-001');
      expect(res.nuevoEstado, 'Disponible');
    });

    test('confirmarReingreso lanza excepción ante error 400', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'El SKU físico no pertenece a la orden anulada especificada.'}),
          400,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      expect(
        () => BodegaService.confirmarReingreso(
          skuQrFisico: 'SKU-ERRONEO',
          idOrdenAnulada: 'ord-12345678',
          client: mockClient,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ReingresoTareasScreen - Widget Tests', () {
    testWidgets('Muestra cabecera y estado de carga o vacío', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: ReingresoTareasScreen(),
        ),
      );

      await tester.pump();

      expect(find.text('Logística Inversa'), findsOneWidget);
      expect(find.text('Reingresos y Paletizado PDA'), findsOneWidget);
    });
  });
}
