// test/bodega_optimizaciones_test.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/alertas/models/tarea_alerta.dart';
import 'package:frontend/features/alertas/presentation/widgets/task_card.dart';
import 'package:frontend/features/inventario/presentation/widgets/resultado_card.dart';
import 'package:frontend/features/inventario/presentation/screens/detalle_activo_screen.dart';
import 'package:frontend/features/recepcion/presentation/screens/recepcion_vehiculo_screen.dart';

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
    mockStorage['access_token'] = 'mock_token';
    mockStorage['user_rol'] = 'Bodeguero';
    mockStorage['user_sucursal'] = 'Sucursal Limache';
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 1. UNIT TESTS: MODELO TareaAlerta
  // ─────────────────────────────────────────────────────────────────────────────
  group('TareaAlerta Model Tests', () {
    test('TareaAlerta.fromJson parsea correctamente campos de pre-entrega y traslados', () {
      final json = {
        'id_tarea': 'T-001',
        'tipo_alerta': 'TRASLADO',
        'orden_ref': 'ORD-2026-0001',
        'titulo_pieza': 'Motor Hyundai Accent 2020',
        'ubicacion': 'G1 - P2 - Pa05',
        'nota_especial': '[TRASLADO DESDE LIMACHE A VIÑA]',
        'accion_requerida': 'PREPARAR Y TRASLADAR',
        'id_detalle': '11111111-1111-1111-1111-111111111111',
        'id_activo': '22222222-2222-2222-2222-222222222222',
        'id_sucursal_origen': 2,
        'id_sucursal_destino': 1,
        'es_traslado': true,
        'estado_preparacion': 'Pendiente',
      };

      final tarea = TareaAlerta.fromJson(json);

      expect(tarea.idTarea, 'T-001');
      expect(tarea.tipoAlerta, 'TRASLADO');
      expect(tarea.ordenRef, 'ORD-2026-0001');
      expect(tarea.idDetalle, '11111111-1111-1111-1111-111111111111');
      expect(tarea.idActivo, '22222222-2222-2222-2222-222222222222');
      expect(tarea.idSucursalOrigen, 2);
      expect(tarea.idSucursalDestino, 1);
      expect(tarea.esTraslado, true);
      expect(tarea.estadoPreparacion, 'Pendiente');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 2. WIDGET TESTS: TaskCard
  // ─────────────────────────────────────────────────────────────────────────────
  group('TaskCard Widget Tests', () {
    testWidgets('Renderiza boton LISTO para tareas con id_detalle, título explícito Motor y TRASLADO', (tester) async {
      final tarea = TareaAlerta(
        idTarea: 'T-001',
        tipoAlerta: 'TRASLADO',
        ordenRef: 'ORD-2026-0001',
        tituloPieza: 'Repuesto de Hyundai Accent 2020',
        ubicacion: 'Galpón 1 - Pasillo 2',
        notaEspecial: '[TRASLADO A VIÑA]',
        accionRequerida: 'PREPARAR Y TRASLADAR',
        idDetalle: '11111111-1111-1111-1111-111111111111',
        esTraslado: true,
        categoria: 'Motor',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskCard(tarea: tarea),
          ),
        ),
      );

      // Verificaciones en la UI: título reformateado con Motor, TRASLADO, LISTO visible, BARRERA oculto
      expect(find.text('ORD-2026-0001'), findsOneWidget);
      expect(find.text('TRASLADO'), findsOneWidget);
      expect(find.text('Motor - Hyundai Accent 2020'), findsOneWidget);
      expect(find.text('LISTO'), findsOneWidget);
      expect(find.text('DETALLES'), findsOneWidget);
      expect(find.text('BARRERA'), findsNothing);
      expect(find.byKey(const Key('btn_listo_T-001')), findsOneWidget);
    });

    testWidgets('Renderiza título explícito Caja de Cambios y modal sin chips redundantes', (tester) async {
      final tarea = TareaAlerta(
        idTarea: 'T-002',
        tipoAlerta: 'PREPARACION',
        ordenRef: 'ORD-2026-0002',
        tituloPieza: 'Repuesto de Toyota Yaris',
        ubicacion: 'P-03 | Pallet 12',
        accionRequerida: 'PREPARAR PARA ENTREGA',
        idDetalle: '22222222-2222-2222-2222-222222222222',
        categoria: 'Caja de Cambios',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskCard(tarea: tarea),
          ),
        ),
      );

      expect(find.text('Caja de Cambios - Toyota Yaris'), findsOneWidget);
      expect(find.text('LISTO'), findsOneWidget);
      expect(find.text('DETALLES'), findsOneWidget);
      expect(find.text('BARRERA'), findsNothing);

      // Tap en DETALLES
      await tester.tap(find.text('DETALLES'));
      await tester.pumpAndSettle();

      // Modal desplegado
      expect(find.text('UBICACIÓN EXACTA'), findsOneWidget);
      expect(find.text('MARCAR COMO LISTO'), findsOneWidget);
      expect(find.text('ESCANEAR EN BARRERA'), findsNothing);
    });

    testWidgets('Estado LIBERADA muestra exclusivamente botón BARRERA y oculta LISTO', (tester) async {
      final tarea = TareaAlerta(
        idTarea: 'T-003',
        tipoAlerta: 'LIBERADA',
        ordenRef: 'ORD-2026-0003',
        tituloPieza: 'Motor Nissan Versa 2021',
        ubicacion: 'G2 - P1 - Pa03',
        accionRequerida: 'ESCANEAR EN BARRERA',
        idDetalle: '33333333-3333-3333-3333-333333333333',
        categoria: 'Motor',
        estadoPreparacion: 'Listo',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskCard(tarea: tarea),
          ),
        ),
      );

      // Verificaciones: BARRERA presente, LISTO ausente
      expect(find.text('BARRERA'), findsOneWidget);
      expect(find.byKey(const Key('btn_barrera_T-003')), findsOneWidget);
      expect(find.text('LISTO'), findsNothing);
      expect(find.byKey(const Key('btn_listo_T-003')), findsNothing);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 3. WIDGET TESTS: ResultadoCard (Ubicación Humana & Reservado)
  // ─────────────────────────────────────────────────────────────────────────────
  group('ResultadoCard Widget Tests', () {
    testWidgets('Formatea ubicación humana estructurada correctamente', (tester) async {
      final itemCompleto = {
        'id_activo': 'abc-123',
        'categoria': 'Motor',
        'marca': 'Nissan',
        'modelo': 'Versa',
        'sku': 'MOT-NIS-VER-001',
        'pasillo': 'P-05',
        'pallet': 'PL-18',
        'galpon': 'G-02',
        'estado': 'DISPONIBLE',
        'imagenes': [],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultadoCard(
              itemCompleto: itemCompleto,
              marca: 'Nissan',
              modelo: 'Versa',
              sku: 'MOT-NIS-VER-001',
              ubicacion: 'P-05 - PL-18',
              estado: 'DISPONIBLE',
            ),
          ),
        ),
      );

      expect(find.text('Motor Nissan Versa'), findsOneWidget);
      expect(find.text('SKU: MOT-NIS-VER-001'), findsOneWidget);
      expect(find.text('DISPONIBLE'), findsOneWidget);
      // Ubicación estructurada
      expect(find.text('Pasillo: P-05 | Pallet: PL-18 | Galpón: G-02'), findsOneWidget);
    });

    testWidgets('Muestra Sin Paletizar / Sin Ubicación Asignada cuando no hay pasillo ni pallet', (tester) async {
      final itemSinUbicacion = {
        'id_activo': 'sin-001',
        'categoria': 'Accesorio',
        'marca': 'Kia',
        'modelo': 'Rio',
        'sku': 'ACC-KIA-RIO-001',
        'pasillo': '',
        'pallet': '',
        'galpon': '',
        'estado': 'DISPONIBLE',
        'imagenes': [],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultadoCard(
              itemCompleto: itemSinUbicacion,
              marca: 'Kia',
              modelo: 'Rio',
              sku: 'ACC-KIA-RIO-001',
              ubicacion: '',
              estado: 'DISPONIBLE',
            ),
          ),
        ),
      );

      expect(find.text('Sin Paletizar / Sin Ubicación Asignada'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 3.5. WIDGET TESTS: DetalleActivoScreen (Bodega Inventario)
  // ─────────────────────────────────────────────────────────────────────────────
  group('DetalleActivoScreen (Bodega Inventario) Widget Tests', () {
    testWidgets('Renderiza AppBar limpio, ID en pill y UBICACIÓN ACTUAL estructurada', (tester) async {
      final activoData = {
        'id_activo': 'act-1010',
        'categoria': 'Motor',
        'marca': 'Toyota',
        'modelo': 'Hilux',
        'sku': 'MOT-1010',
        'estado': 'DISPONIBLE',
        'ubicacion': 'P-03 - PL-09',
        'pasillo': 'P-03',
        'pallet': 'PL-09',
        'galpon': 'G-01',
        'numero_ingreso': 'ING-2026-088',
        'cilindrada': '2.8L',
        'combustible': 'DIESEL',
        'transmision': 'AUTOMÁTICA',
        'observacion': 'Motor en óptimas condiciones.',
        'qr_impreso': false,
        'imagenes': [],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: DetalleActivoScreen(activo: activoData),
        ),
      );
      await tester.pumpAndSettle();

      // 1. AppBar limpio
      expect(find.text('Detalle de Motor'), findsOneWidget);
      expect(find.byTooltip('Volver'), findsOneWidget);

      // 2. ID en pill y estado
      expect(find.text('ID: MOT-1010'), findsOneWidget);
      expect(find.text('DISPONIBLE'), findsOneWidget);
      expect(
        find.byWidgetPredicate((widget) => widget is RichText && widget.text.toPlainText().contains('Toyota Hilux')),
        findsOneWidget,
      );

      // 3. Ubicación Actual estructurada y legible
      expect(find.text('UBICACIÓN ACTUAL'), findsOneWidget);
      expect(find.text('Pasillo: P-03 | Pallet: PL-09 | Galpón: G-01'), findsOneWidget);

      // 4. Especificaciones técnicas
      expect(find.text('Nº DE INGRESO VEHÍCULO'), findsOneWidget);
      expect(find.text('ING-2026-088'), findsOneWidget);
      expect(find.text('2.8L'), findsOneWidget);
    });

    testWidgets('Renderiza Sin Paletizar / Sin Ubicación Asignada cuando no tiene ubicación', (tester) async {
      final activoSinUbicacion = {
        'id_activo': 'act-2020',
        'categoria': 'Caja de Cambios',
        'marca': 'Nissan',
        'modelo': 'Kicks',
        'sku': 'CAJ-2020',
        'estado': 'DISPONIBLE',
        'ubicacion': 'No asignada',
        'pasillo': '',
        'pallet': '',
        'galpon': '',
        'numero_ingreso': 'ING-2026-099',
        'transmision': 'CVT',
        'qr_impreso': false,
        'imagenes': [],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: DetalleActivoScreen(activo: activoSinUbicacion),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Detalle de Caja de Cambios'), findsOneWidget);
      expect(find.text('Sin Paletizar / Sin Ubicación Asignada'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // 4. WIDGET TESTS: RecepcionVehiculoScreen (Flujo Atómico OCR)
  // ─────────────────────────────────────────────────────────────────────────────
  group('RecepcionVehiculoScreen Widget Tests', () {
    testWidgets('Renderiza boton unificado GUARDAR / REGISTRAR INGRESO y no boton separado', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RecepcionVehiculoScreen(),
        ),
      );
      await tester.pump();

      // No debe existir el botón/tarjeta independiente anterior de captura OCR
      expect(find.byKey(const Key('btn_captura_ocr_puerta')), findsNothing);
      expect(find.text('Tomar Foto a la Puerta (Poka-Yoke OCR)'), findsNothing);

      // Debe existir el botón unificado
      expect(find.byKey(const Key('btn_guardar_ingreso_ocr')), findsOneWidget);
      expect(find.text('GUARDAR / REGISTRAR INGRESO'), findsOneWidget);
    });

    testWidgets('Muestra banner instructivo de validacion obligatoria OCR encima del boton de guardar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RecepcionVehiculoScreen(),
        ),
      );
      await tester.pump();

      expect(
        find.textContaining('Validación Obligatoria: Al continuar se solicitará fotografiar el N° de ingreso físico'),
        findsOneWidget,
      );
    });

    testWidgets('Bloquea guardado con SnackBar si faltan datos obligatorios', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RecepcionVehiculoScreen(),
        ),
      );
      await tester.pump();

      // Tap en el botón guardar sin llenar campos
      await tester.ensureVisible(find.byKey(const Key('btn_guardar_ingreso_ocr')));
      await tester.tap(find.byKey(const Key('btn_guardar_ingreso_ocr')));
      await tester.pumpAndSettle();

      // Debe mostrar advertencia de campos obligatorios
      expect(find.textContaining('Bloqueo: Completa los datos obligatorios'), findsOneWidget);
    });
  });
}
