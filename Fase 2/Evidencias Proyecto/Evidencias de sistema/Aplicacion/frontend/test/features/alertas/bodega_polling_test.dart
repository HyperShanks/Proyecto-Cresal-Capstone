// test/features/alertas/bodega_polling_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/alertas/services/bodega_polling_service.dart';
import 'package:frontend/features/alertas/models/tarea_alerta.dart';
import 'package:frontend/features/alertas/presentation/widgets/panel_tareas_desplegable.dart';
import 'package:frontend/features/alertas/presentation/widgets/task_card.dart';
import 'package:frontend/core/theme/tokens/app_palette.dart';

void main() {
  group('SPEC-HU-06: BodegaPollingService - Pruebas Unitarias de Estado Reactivo', () {
    setUp(() {
      BodegaPollingService.instance.reset();
    });

    tearDown(() {
      BodegaPollingService.instance.reset();
    });

    test('Estado inicial comienza en 0 y sin traslados', () {
      expect(BodegaPollingService.instance.totalPendientesNotifier.value, 0);
      expect(BodegaPollingService.instance.tieneTrasladosNotifier.value, false);
      expect(BodegaPollingService.instance.tareasNotifier.value.isEmpty, true);
    });

    test('procesarCiclo con mock actualiza notifiers y desglose', () async {
      final mockTareas = [
        const TareaAlerta(
          idTarea: 'ORD-1',
          tipoAlerta: 'PREPARACION',
          tituloPieza: 'Motor Toyota Hilux',
          accionRequerida: 'PREPARAR',
          categoria: 'Motor',
          tipoRepuesto: 'Motor',
          ubicacion: 'P1-R1',
          esTraslado: false,
        ),
        const TareaAlerta(
          idTarea: 'ORD-2',
          tipoAlerta: 'TRASLADO',
          tituloPieza: 'Caja Nissan Versa',
          accionRequerida: 'TRASLADAR',
          categoria: 'Caja',
          tipoRepuesto: 'Caja',
          ubicacion: 'P2-R2',
          esTraslado: true,
        ),
        const TareaAlerta(
          idTarea: 'ORD-3',
          tipoAlerta: 'LIBERADA',
          tituloPieza: 'Alternador Chevrolet',
          accionRequerida: 'ESCANEAR',
          categoria: 'Repuesto',
          tipoRepuesto: 'Repuesto',
          ubicacion: 'P3-R3',
          esTraslado: false,
        ),
      ];

      await BodegaPollingService.instance.procesarCiclo(tareasMock: mockTareas);

      expect(BodegaPollingService.instance.totalPendientesNotifier.value, 3);
      expect(BodegaPollingService.instance.tieneTrasladosNotifier.value, true);
      expect(BodegaPollingService.instance.tareasNotifier.value.length, 3);
      expect(BodegaPollingService.instance.resumenNotifier.value.desglosePreparacion, 2); // 1 prep + 1 traslado
      expect(BodegaPollingService.instance.resumenNotifier.value.desgloseEntregas, 1); // 1 liberada
    });

    test('decrementarPendiente reduce el total reactivo sin latencia', () async {
      final mockTareas = [
        const TareaAlerta(
          idTarea: 'ORD-1',
          tipoAlerta: 'PREPARACION',
          tituloPieza: 'Motor',
          accionRequerida: 'PREPARAR',
          categoria: 'Motor',
          tipoRepuesto: 'Motor',
          ubicacion: 'P1',
        ),
      ];

      await BodegaPollingService.instance.procesarCiclo(tareasMock: mockTareas);
      expect(BodegaPollingService.instance.totalPendientesNotifier.value, 1);

      BodegaPollingService.instance.decrementarPendiente();
      expect(BodegaPollingService.instance.totalPendientesNotifier.value, 0);

      // No decrementar por debajo de 0
      BodegaPollingService.instance.decrementarPendiente();
      expect(BodegaPollingService.instance.totalPendientesNotifier.value, 0);
    });

    test('reset reinicia todos los notifiers a 0', () async {
      final mockTareas = [
        const TareaAlerta(
          idTarea: 'ORD-1',
          tipoAlerta: 'PREPARACION',
          tituloPieza: 'Motor',
          accionRequerida: 'PREPARAR',
          categoria: 'Motor',
          tipoRepuesto: 'Motor',
          ubicacion: 'P1',
        ),
      ];
      await BodegaPollingService.instance.procesarCiclo(tareasMock: mockTareas);
      expect(BodegaPollingService.instance.totalPendientesNotifier.value, 1);

      BodegaPollingService.instance.reset();
      expect(BodegaPollingService.instance.totalPendientesNotifier.value, 0);
      expect(BodegaPollingService.instance.tieneTrasladosNotifier.value, false);
      expect(BodegaPollingService.instance.tareasNotifier.value, isEmpty);
    });
  });

  group('SPEC-HU-06: Badge del AppBar & PanelTareasDesplegable - Pruebas Widget', () {
    setUp(() {
      BodegaPollingService.instance.reset();
    });

    tearDown(() {
      BodegaPollingService.instance.reset();
    });

    testWidgets('Badge en AppBar se oculta cuando totalPendientes es 0', (tester) async {
      BodegaPollingService.instance.totalPendientesNotifier.value = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ValueListenableBuilder<int>(
                  valueListenable: BodegaPollingService.instance.totalPendientesNotifier,
                  builder: (context, totalPendientes, _) {
                    return IconButton(
                      key: const Key('btn_appbar_tareas_badge'),
                      icon: Badge(
                        key: const Key('badge_appbar_contador'),
                        isLabelVisible: totalPendientes > 0,
                        label: Text('$totalPendientes'),
                        backgroundColor: AppPalette.secondary,
                        child: const Icon(Icons.assignment_outlined),
                      ),
                      onPressed: () {},
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('btn_appbar_tareas_badge')), findsOneWidget);
      final badgeWidget = tester.widget<Badge>(find.byKey(const Key('badge_appbar_contador')));
      expect(badgeWidget.isLabelVisible, false);
    });

    testWidgets('Badge en AppBar muestra número cuando totalPendientes > 0', (tester) async {
      BodegaPollingService.instance.totalPendientesNotifier.value = 4;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ValueListenableBuilder<int>(
                  valueListenable: BodegaPollingService.instance.totalPendientesNotifier,
                  builder: (context, totalPendientes, _) {
                    return IconButton(
                      key: const Key('btn_appbar_tareas_badge'),
                      icon: Badge(
                        key: const Key('badge_appbar_contador'),
                        isLabelVisible: totalPendientes > 0,
                        label: Text('$totalPendientes'),
                        backgroundColor: AppPalette.secondary,
                        child: const Icon(Icons.assignment_outlined),
                      ),
                      onPressed: () {},
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('btn_appbar_tareas_badge')), findsOneWidget);
      final badgeWidget = tester.widget<Badge>(find.byKey(const Key('badge_appbar_contador')));
      expect(badgeWidget.isLabelVisible, true);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('PanelTareasDesplegable renderiza chips de métricas y tareas', (tester) async {
      final mockTareas = [
        const TareaAlerta(
          idTarea: 'ORD-101',
          tipoAlerta: 'PREPARACION',
          tituloPieza: 'Motor Toyota Hilux 2.8',
          ordenRef: 'ORDEN #A1B2C3D4',
          accionRequerida: 'PREPARAR',
          categoria: 'Motor',
          tipoRepuesto: 'Motor',
          ubicacion: 'P1 - R5',
        ),
      ];

      await BodegaPollingService.instance.procesarCiclo(tareasMock: mockTareas);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: PanelTareasDesplegable(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Tareas Operativas'), findsOneWidget);
      expect(find.text('Preparación'), findsOneWidget);
      expect(find.text('Salidas/Barrera'), findsOneWidget);
      expect(find.text('Reingresos'), findsOneWidget);
      expect(find.text('Motor Toyota Hilux 2.8'), findsOneWidget);
      expect(find.text('ORDEN #A1B2C3D4'), findsOneWidget);
      expect(find.text('Marcar Listo'), findsOneWidget);
      expect(find.text('VER TABLERO COMPLETO'), findsOneWidget);
    });

    testWidgets('TaskCard renderiza botón REINGRESAR / PALETIZAR para tareas de tipo REINGRESO', (tester) async {
      const tareaReingreso = TareaAlerta(
        idTarea: 'REING-001',
        tipoAlerta: 'REINGRESO',
        tituloPieza: 'Motor Toyota Tercel XLI 1.5',
        ordenRef: 'ORDEN ANULADA #A6B0E068',
        accionRequerida: 'REINGRESAR / PALETIZAR',
        skuQrFisico: 'MOT-1006',
        ubicacion: 'P-01 - PAL-04',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TaskCard(tarea: tareaReingreso),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Motor Toyota Tercel XLI 1.5'), findsOneWidget);
      expect(find.text('ORDEN ANULADA'), findsOneWidget);
      expect(find.text('MOT-1006'), findsOneWidget);
      expect(find.text('REINGRESAR / PALETIZAR'), findsWidgets);
      expect(find.byKey(const Key('btn_reingresar_REING-001')), findsOneWidget);
    });
  });
}
