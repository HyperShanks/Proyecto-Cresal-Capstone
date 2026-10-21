// test/features/alertas/alertas_tabs_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/alertas/models/tarea_alerta.dart';
import 'package:frontend/features/alertas/presentation/screens/alertas_screen.dart';
import 'package:frontend/features/alertas/presentation/widgets/alerta_preentrega_tab.dart';
import 'package:frontend/features/alertas/presentation/widgets/alerta_reimpresion_tab.dart';
import 'package:frontend/features/alertas/presentation/widgets/alerta_reintegracion_tab.dart';
import 'package:frontend/features/alertas/presentation/widgets/task_card.dart';
import 'package:frontend/features/alertas/presentation/screens/auditoria_salida_screen.dart';
import 'package:frontend/features/alertas/services/bodega_polling_service.dart';

void main() {
  group('SPEC-HU-TAREA-13: BodegaPollingService - Segmentación por Tipo de Operación', () {
    setUp(() {
      BodegaPollingService.instance.reset();
    });

    tearDown(() {
      BodegaPollingService.instance.reset();
    });

    test('Segmenta correctamente en preentrega, reimpresión y reintegración', () async {
      final mockTareas = [
        const TareaAlerta(
          idTarea: 'ORD-1',
          tipoAlerta: 'PREPARACION',
          tituloPieza: 'Motor Toyota Hilux',
          accionRequerida: 'PREPARAR',
          ubicacion: 'P1-R1',
        ),
        const TareaAlerta(
          idTarea: 'ORD-2',
          tipoAlerta: 'TRASLADO',
          tituloPieza: 'Caja Nissan Versa',
          accionRequerida: 'TRASLADAR',
          ubicacion: 'P2-R2',
          esTraslado: true,
        ),
        const TareaAlerta(
          idTarea: 'ORD-3',
          tipoAlerta: 'LIBERADA',
          tituloPieza: 'Alternador Chevrolet',
          accionRequerida: 'ESCANEAR',
          ubicacion: 'P3-R3',
        ),
        const TareaAlerta(
          idTarea: 'IMP-1',
          tipoAlerta: 'IMPRESION',
          tituloPieza: 'Bandeja Suspensión Delantera',
          accionRequerida: 'GENERAR QR AHORA',
          ubicacion: 'P4-R1',
        ),
        const TareaAlerta(
          idTarea: 'REING-1',
          tipoAlerta: 'REINGRESO',
          tituloPieza: 'Faro Trasero Hyundai',
          accionRequerida: 'REINGRESAR / PALETIZAR',
          ubicacion: 'P5-R2',
        ),
      ];

      await BodegaPollingService.instance.procesarCiclo(tareasMock: mockTareas);

      final s = BodegaPollingService.instance;
      expect(s.totalPendientesNotifier.value, 5);

      // 1. Pre-entrega: PREPARACION (1), TRASLADO (1), LIBERADA (1) => 3
      expect(s.preentregaNotifier.value.length, 3);
      expect(s.conteoPreentregaNotifier.value, 3);
      expect(s.preentregaNotifier.value.map((t) => t.idTarea).toList(), ['ORD-1', 'ORD-2', 'ORD-3']);

      // 2. Re-impresión: IMPRESION (1) => 1
      expect(s.reimpresionNotifier.value.length, 1);
      expect(s.conteoReimpresionNotifier.value, 1);
      expect(s.reimpresionNotifier.value.first.idTarea, 'IMP-1');

      // 3. Re-integración: REINGRESO (1) => 1
      expect(s.reintegracionNotifier.value.length, 1);
      expect(s.conteoReintegracionNotifier.value, 1);
      expect(s.reintegracionNotifier.value.first.idTarea, 'REING-1');
    });

    test('decrementarPendiente con tipoAlerta decrementa el conteo específico', () async {
      final mockTareas = [
        const TareaAlerta(
          idTarea: 'ORD-1',
          tipoAlerta: 'PREPARACION',
          tituloPieza: 'Motor',
          accionRequerida: 'PREPARAR',
          ubicacion: 'P1',
        ),
        const TareaAlerta(
          idTarea: 'IMP-1',
          tipoAlerta: 'IMPRESION',
          tituloPieza: 'Caja',
          accionRequerida: 'IMPRIMIR',
          ubicacion: 'P2',
        ),
      ];

      await BodegaPollingService.instance.procesarCiclo(tareasMock: mockTareas);
      final s = BodegaPollingService.instance;

      expect(s.conteoPreentregaNotifier.value, 1);
      expect(s.conteoReimpresionNotifier.value, 1);
      expect(s.totalPendientesNotifier.value, 2);

      s.decrementarPendiente(tipoAlerta: 'IMPRESION');
      expect(s.conteoReimpresionNotifier.value, 0);
      expect(s.conteoPreentregaNotifier.value, 1);
      expect(s.totalPendientesNotifier.value, 1);

      s.decrementarPendiente(tipoAlerta: 'PREPARACION');
      expect(s.conteoPreentregaNotifier.value, 0);
      expect(s.totalPendientesNotifier.value, 0);
    });

    test('reset limpia todos los notifiers segmentados', () async {
      final mockTareas = [
        const TareaAlerta(
          idTarea: 'ORD-1',
          tipoAlerta: 'PREPARACION',
          tituloPieza: 'Motor',
          accionRequerida: 'PREPARAR',
          ubicacion: 'P1',
        ),
      ];

      await BodegaPollingService.instance.procesarCiclo(tareasMock: mockTareas);
      BodegaPollingService.instance.reset();

      final s = BodegaPollingService.instance;
      expect(s.preentregaNotifier.value.isEmpty, true);
      expect(s.reimpresionNotifier.value.isEmpty, true);
      expect(s.reintegracionNotifier.value.isEmpty, true);
      expect(s.conteoPreentregaNotifier.value, 0);
      expect(s.conteoReimpresionNotifier.value, 0);
      expect(s.conteoReintegracionNotifier.value, 0);
    });
  });

  group('SPEC-HU-TAREA-13: Widgets de Tabs Individuales y Empty States', () {
    testWidgets('AlertaPreentregaTab renderiza tareas y badge de traslados', (tester) async {
      final tareas = [
        const TareaAlerta(
          idTarea: 'ORD-101',
          tipoAlerta: 'PREPARACION',
          tituloPieza: 'Motor Toyota Yaris',
          accionRequerida: 'PREPARAR',
          ubicacion: 'A1 - B2',
          esTraslado: false,
        ),
        const TareaAlerta(
          idTarea: 'ORD-102',
          tipoAlerta: 'TRASLADO',
          tituloPieza: 'Caja Hyundai Accent',
          accionRequerida: 'TRASLADAR',
          ubicacion: 'C3 - D4',
          esTraslado: true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlertaPreentregaTab(
              tareas: tareas,
              onRefresh: () async {},
            ),
          ),
        ),
      );

      expect(find.text('2 PRE-ENTREGAS PENDIENTES'), findsOneWidget);
      expect(find.text('1 TRASLADO(S)'), findsOneWidget);
      expect(find.text('Motor Toyota Yaris'), findsOneWidget);
      expect(find.text('Caja Hyundai Accent'), findsOneWidget);
    });

    testWidgets('AlertaPreentregaTab muestra empty state cuando no hay tareas', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlertaPreentregaTab(
              tareas: const [],
              onRefresh: () async {},
            ),
          ),
        ),
      );

      expect(find.text('¡Todo al día en Pre-entrega!'), findsOneWidget);
      expect(find.text('No hay tareas de preparación ni despacho pendientes.'), findsOneWidget);
      expect(find.byIcon(Icons.local_shipping_outlined), findsOneWidget);
    });

    testWidgets('AlertaReimpresionTab renderiza tareas y empty state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlertaReimpresionTab(
              tareas: const [],
              onRefresh: () async {},
            ),
          ),
        ),
      );

      expect(find.text('Sin tareas de re-impresión'), findsOneWidget);
      expect(find.text('Todas las piezas cuentan con su código QR físico impreso.'), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_scanner), findsOneWidget);
    });

    testWidgets('AlertaReintegracionTab renderiza tareas y empty state', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AlertaReintegracionTab(
              tareas: const [],
              onRefresh: () async {},
            ),
          ),
        ),
      );

      expect(find.text('Sin re-integraciones pendientes'), findsOneWidget);
      expect(find.text('No hay piezas de órdenes anuladas pendientes por reingresar al rack.'), findsOneWidget);
      expect(find.byIcon(Icons.assignment_return_outlined), findsOneWidget);
    });
  });

  group('SPEC-HU-TAREA-13: AlertasScreen (Navegación por Tabs y Badges)', () {
    setUp(() {
      BodegaPollingService.instance.reset();
    });

    tearDown(() {
      BodegaPollingService.instance.reset();
    });

    testWidgets('Renderiza AppBar con las 3 pestañas y permite navegación', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockTareas = [
        const TareaAlerta(
          idTarea: 'ORD-1',
          tipoAlerta: 'PREPARACION',
          tituloPieza: 'Motor Toyota Yaris',
          accionRequerida: 'PREPARAR',
          ubicacion: 'P1-R1',
        ),
        const TareaAlerta(
          idTarea: 'ORD-2',
          tipoAlerta: 'TRASLADO',
          tituloPieza: 'Caja Nissan Versa',
          accionRequerida: 'TRASLADAR',
          ubicacion: 'P2-R2',
          esTraslado: true,
        ),
        const TareaAlerta(
          idTarea: 'IMP-1',
          tipoAlerta: 'IMPRESION',
          tituloPieza: 'Alternador Chevrolet',
          accionRequerida: 'IMPRIMIR',
          ubicacion: 'P3-R3',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: AlertasScreen(
            futureAlertas: Future.value(mockTareas),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verificamos que se renderizan los nombres de las 3 pestañas
      expect(find.text('Entrega'), findsOneWidget);
      expect(find.text('Imprimir'), findsOneWidget);
      expect(find.text('Re-integración'), findsOneWidget);

      // Verificamos los badges de conteo reactivos
      expect(find.text('2'), findsOneWidget); // badge pre-entrega (PREPARACION + TRASLADO)
      expect(find.text('1'), findsOneWidget); // badge re-impresión (IMPRESION)

      // Verificamos contenido de la pestaña activa (Pre-entrega)
      expect(find.text('Motor Toyota Yaris'), findsOneWidget);
      expect(find.text('Caja Nissan Versa'), findsOneWidget);

      // Cambiamos a la pestaña 2 (Imprimir)
      await tester.tap(find.text('Imprimir'));
      await tester.pumpAndSettle();
      expect(find.text('Alternador Chevrolet'), findsOneWidget);

      // Cambiamos a la pestaña 3 (Re-integración - vacío)
      await tester.tap(find.text('Re-integración'));
      await tester.pumpAndSettle();
      expect(find.text('Sin re-integraciones pendientes'), findsOneWidget);
    });

    testWidgets('Muestra mensaje de error estipulado y botón reintentar si falla la conexión', (tester) async {
      final futureConError = Future<List<TareaAlerta>>.error(Exception('Falla de red'));
      futureConError.catchError((_) => <TareaAlerta>[]);

      await tester.pumpWidget(
        MaterialApp(
          home: AlertasScreen(
            futureAlertas: futureConError,
          ),
        ),
      );

      await tester.pump();

      expect(
        find.text('No se pudieron cargar las tareas. Reintentando conexión con la bodega...'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    });

    testWidgets('Renderiza en pantalla movil estrecha (360px) sin overflow en tabs con badges grandes', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FlutterErrorDetails? errorCaptured;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errorCaptured = details;
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final tareas = [
        for (int i = 0; i < 4; i++)
          TareaAlerta(idTarea: 'PRE-$i', tipoAlerta: 'PREPARACION', tituloPieza: 'P$i', accionRequerida: 'A', ubicacion: 'U'),
        for (int i = 0; i < 5; i++)
          TareaAlerta(idTarea: 'IMP-$i', tipoAlerta: 'IMPRESION', tituloPieza: 'I$i', accionRequerida: 'A', ubicacion: 'U'),
        for (int i = 0; i < 15; i++)
          TareaAlerta(idTarea: 'REI-$i', tipoAlerta: 'REINGRESO', tituloPieza: 'R$i', accionRequerida: 'A', ubicacion: 'U'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: AlertasScreen(
            futureAlertas: Future.value(tareas),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Entrega'), findsOneWidget);
      expect(find.text('Imprimir'), findsOneWidget);
      expect(find.text('Re-integración'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      FlutterError.onError = originalOnError;
      expect(errorCaptured, isNull);
    });
  });

  group('TaskCard BARRERA Flow Tests', () {
    testWidgets('TaskCard con tarea LIBERADA renderiza botón BARRERA y al presionar abre AuditoriaSalidaScreen', (tester) async {
      const tareaLiberada = TareaAlerta(
        idTarea: 'ORD-999',
        tipoAlerta: 'LIBERADA',
        tituloPieza: 'Culata de Motor Toyota',
        accionRequerida: 'ESCANEAR EN BARRERA',
        ubicacion: 'P-1 - R-2',
      );

      bool actualizado = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskCard(
              tarea: tareaLiberada,
              onActualizar: () {
                actualizado = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final botonBarrera = find.byKey(const Key('btn_barrera_ORD-999'));
      expect(botonBarrera, findsOneWidget);
      expect(find.text('BARRERA'), findsOneWidget);

      await tester.tap(botonBarrera);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AuditoriaSalidaScreen), findsOneWidget);
      expect(actualizado, isFalse); // No actualizado todavía hasta que retorne
    });
  });
}


