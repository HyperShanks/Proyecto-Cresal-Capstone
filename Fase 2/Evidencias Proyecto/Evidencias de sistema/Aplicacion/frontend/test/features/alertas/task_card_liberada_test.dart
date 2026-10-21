// test/features/alertas/task_card_liberada_test.dart
// Suite de pruebas para SPEC-HU-TAREA-19:
// Supervivencia de la Tarea de Pre-Entrega Post-Pago en Bodega (TaskCard)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/alertas/models/tarea_alerta.dart';
import 'package:frontend/features/alertas/presentation/widgets/task_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'read') return 'mock-jwt-token';
        return null;
      },
    );
  });

  group('SPEC-HU-TAREA-19: TaskCard - Botón LISTO en Tareas Liberadas', () {
    testWidgets('Tarea LIBERADA con idDetalle renderiza AMBOS botones: LISTO y BARRERA', (tester) async {
      const tareaLiberada = TareaAlerta(
        idTarea: 'ORD-12345678',
        tipoAlerta: 'LIBERADA',
        accionRequerida: 'ESCANEAR EN BARRERA',
        ordenRef: 'ORDEN #ORD-9999',
        tituloPieza: 'Motor - Toyota Hilux',
        categoria: 'Motor',
        ubicacion: 'P-01 - PAL-10',
        ubicacionPasillo: 'P-01',
        ubicacionPallet: 'PAL-10',
        idDetalle: 'det-abc-123',
        notaEspecial: 'Verificar soporte lateral antes de entrega',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TaskCard(tarea: tareaLiberada),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar que ambos botones existen simultáneamente en pantalla
      expect(find.byKey(const Key('btn_listo_ORD-12345678')), findsOneWidget);
      expect(find.byKey(const Key('btn_barrera_ORD-12345678')), findsOneWidget);
      expect(find.text('LISTO'), findsOneWidget);
      expect(find.text('BARRERA'), findsOneWidget);
    });

    testWidgets('Tarea LIBERADA sin idDetalle renderiza únicamente el botón BARRERA', (tester) async {
      const tareaSinDetalle = TareaAlerta(
        idTarea: 'ORD-87654321',
        tipoAlerta: 'LIBERADA',
        accionRequerida: 'ESCANEAR EN BARRERA',
        ordenRef: 'ORDEN #ORD-8888',
        tituloPieza: 'Caja de Cambios - Nissan Versa',
        categoria: 'Caja de Cambios',
        ubicacion: 'P-02 - PAL-20',
        idDetalle: null,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TaskCard(tarea: tareaSinDetalle),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_listo_ORD-87654321')), findsNothing);
      expect(find.byKey(const Key('btn_barrera_ORD-87654321')), findsOneWidget);
      expect(find.text('BARRERA'), findsOneWidget);
    });

    testWidgets('Tarea LIBERADA con estadoPreparacion Listo renderiza únicamente el botón BARRERA', (tester) async {
      const tareaListo = TareaAlerta(
        idTarea: 'ORD-55667788',
        tipoAlerta: 'LIBERADA',
        accionRequerida: 'ESCANEAR EN BARRERA',
        ordenRef: 'ORDEN #ORD-5555',
        tituloPieza: 'Motor - Nissan Kicks',
        categoria: 'Motor',
        ubicacion: 'P-01 - PAL-05',
        idDetalle: 'det-listo-001',
        estadoPreparacion: 'Listo',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TaskCard(tarea: tareaListo),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_listo_ORD-55667788')), findsNothing);
      expect(find.byKey(const Key('btn_barrera_ORD-55667788')), findsOneWidget);
      expect(find.text('BARRERA'), findsOneWidget);
    });

    testWidgets('Tarea PREPARACION renderiza botón LISTO y DETALLES, ocultando BARRERA', (tester) async {
      const tareaPreparacion = TareaAlerta(
        idTarea: 'ORD-11223344',
        tipoAlerta: 'PREPARACION',
        accionRequerida: 'PREPARAR',
        ordenRef: 'ORDEN #ORD-7777',
        tituloPieza: 'Motor - Hyundai Accent',
        categoria: 'Motor',
        ubicacion: 'P-03 - PAL-30',
        idDetalle: 'det-prep-001',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TaskCard(tarea: tareaPreparacion),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_listo_ORD-11223344')), findsOneWidget);
      expect(find.byKey(const Key('btn_detalles_ORD-11223344')), findsOneWidget);
      expect(find.byKey(const Key('btn_barrera_ORD-11223344')), findsNothing);
    });
  });
}
