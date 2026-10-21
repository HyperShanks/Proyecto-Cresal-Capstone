import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/alertas/models/tarea_alerta.dart';
import 'package:frontend/features/alertas/presentation/screens/auditoria_salida_screen.dart';
import 'package:frontend/features/alertas/presentation/widgets/task_card.dart';
import 'package:frontend/features/paletizado/domain/models/etiqueta_data.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
    mockStorage['access_token'] = 'test_token';
  });

  final mockEtiqueta = EtiquetaData.fromMap({
    'id_activo': 'act-999',
    'categoria': 'Motor',
    'marca': 'Toyota',
    'modelo': 'Yaris',
    'anio': 2020,
    'sku_qr_fisico': 'MOT-TOY-YAR-001',
    'numero_ingreso': 'ING-2026-001',
    'galpon': 'G-01',
    'pasillo': 'P-03',
    'pallet': 'PL-07',
  });

  group('Opción C: Flujo Preventivo y Reactivo de Impresión Obligatoria de QR', () {
    testWidgets('TaskCard muestra badge [QR NO IMPRESO] y botón [IMPRIMIR QR] cuando qrImpreso es false', (tester) async {
      final tarea = TareaAlerta(
        idTarea: 'T-C-001',
        tipoAlerta: 'PREPARACION',
        ordenRef: 'ORD-2026-0099',
        tituloPieza: 'Motor Toyota Yaris 2020',
        ubicacion: 'Galpón 1 - P-03',
        accionRequerida: 'PREPARAR PARA ENTREGA',
        idDetalle: 'det-001',
        idActivo: 'act-999',
        skuQrFisico: 'MOT-TOY-YAR-001',
        categoria: 'Motor',
        qrImpreso: false,
        etiquetaData: mockEtiqueta,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskCard(tarea: tarea),
          ),
        ),
      );
      await tester.pump();

      // Debe mostrar el SKU y el badge de advertencia QR NO IMPRESO
      expect(find.text('MOT-TOY-YAR-001'), findsOneWidget);
      expect(find.text('QR NO IMPRESO'), findsOneWidget);

      // Debe mostrar botón directo de IMPRIMIR QR para que el bodeguero no busque una pieza sin etiqueta
      expect(find.text('IMPRIMIR QR'), findsOneWidget);
      expect(find.byKey(const Key('btn_imprimir_qr_T-C-001')), findsOneWidget);
    });

    testWidgets('AuditoriaSalidaScreen muestra botón [IMPRIMIR ETIQUETA QR AHORA] cuando la pieza tiene qrImpreso == false', (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/verificar-qr-salida')) {
          return http.Response(
            '''
            {
              "id_orden": "ord-uuid-123",
              "folio": "ORD-0099",
              "estado_orden": "Pagada",
              "total_venta": 500000,
              "monto_pendiente": 0,
              "id_sucursal": 1,
              "cliente_nombre": "Carlos Pérez",
              "cliente_rut": "12.345.678-9",
              "cliente_telefono": "+56911223344",
              "total_items_fisicos": 1,
              "qr_transaccional_salida": "TX-QR-12345678-TEST",
              "items_requeridos": [
                {
                  "id_detalle": "det-123",
                  "id_activo": "act-999",
                  "titulo": "Motor Toyota Yaris",
                  "sku_qr_fisico": "MOT-TOY-YAR-001",
                  "es_inventariado": true,
                  "ubicacion": "P-03 - PL-07",
                  "notas_preparacion": "Revisar alternador",
                  "cantidad": 1,
                  "precio_final": 500000,
                  "qr_impreso": false,
                  "etiqueta_data": {
                    "id_activo": "act-999",
                    "categoria": "Motor",
                    "marca": "Toyota",
                    "modelo": "Yaris",
                    "sku": "MOT-TOY-YAR-001",
                    "numero_ingreso": "ING-2026-001"
                  }
                }
              ]
            }
            ''',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{"detail": "Not found"}', 404);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: AuditoriaSalidaScreen(httpClient: mockClient),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Paso 1: Escanear el QR de la orden del vendedor
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);
      await tester.enterText(textFieldFinder, 'TX-QR-12345678-TEST');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Debe mostrar la pieza con badge SIN QR y el botón para imprimir en situ
      expect(find.text('SIN QR'), findsOneWidget);
      expect(find.text('IMPRIMIR ETIQUETA QR AHORA'), findsOneWidget);
      expect(find.byKey(const Key('btn_imprimir_salida_det-123')), findsOneWidget);

      // Si el bodeguero intenta escanear el SKU físico antes de imprimir
      await tester.enterText(textFieldFinder, 'MOT-TOY-YAR-001');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Debe bloquearlo con mensaje claro
      expect(find.textContaining('no registra impresión de etiqueta QR'), findsOneWidget);
    });
  });
}
