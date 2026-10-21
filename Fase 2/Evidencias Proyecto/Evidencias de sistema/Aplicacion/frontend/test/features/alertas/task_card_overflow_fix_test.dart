// test/features/alertas/task_card_overflow_fix_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/alertas/models/tarea_alerta.dart';
import 'package:frontend/features/alertas/presentation/widgets/task_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tareaPrueba = TareaAlerta(
    idTarea: 'ORD-TEST-001',
    tipoAlerta: 'PREPARACION',
    ordenRef: 'ORDEN #ORD-99887766',
    tituloPieza: 'Motor Toyota Yaris 1.5 2020 Gasolina Completo con Accesorios',
    categoria: 'Motor',
    ubicacion: 'G-01 - P-03 - PL-07',
    ubicacionGalpon: 'Galpón Principal A-1',
    ubicacionPasillo: 'Pasillo Central 03',
    ubicacionPallet: 'Pallet PL-07-ALTO',
    accionRequerida: 'PREPARAR PARA ENTREGA',
    idDetalle: 'det-1234',
    notaEspecial: 'Verificar cuidadosamente que incluya alternador y compresor de aire acondicionado antes del despacho.',
    qrImpreso: true,
  );

  testWidgets('TaskCard en pantalla movil estrecha (360px) no tiene desbordamiento ni texto cortado', (tester) async {
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TaskCard(tarea: tareaPrueba),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verificar ubicación en la tarjeta sin recorte
    expect(find.byKey(const Key('chip_galpon_tarea')), findsOneWidget);
    expect(find.textContaining('Galpón: Galpón Principal A-1'), findsOneWidget);
    expect(find.textContaining('Pasillo: Pasillo Central 03'), findsOneWidget);
    expect(find.textContaining('Pallet: Pallet PL-07-ALTO'), findsOneWidget);

    // 2. Verificar detalle de la tarea en la tarjeta
    expect(find.text('DETALLE DE LA TAREA'), findsOneWidget);
    expect(find.textContaining('Verificar cuidadosamente que incluya alternador'), findsOneWidget);

    // 3. Verificar botones de acción (LISTO y DETALLES)
    expect(find.byKey(const Key('btn_listo_ORD-TEST-001')), findsOneWidget);
    expect(find.byKey(const Key('btn_detalles_ORD-TEST-001')), findsOneWidget);
    expect(find.text('LISTO'), findsOneWidget);
    expect(find.text('DETALLES'), findsOneWidget);

    // 4. Abrir modal de detalles y verificar que la ubicación es legible y no causa overflow
    await tester.tap(find.byKey(const Key('btn_detalles_ORD-TEST-001')));
    await tester.pumpAndSettle();

    expect(find.text('UBICACIÓN EXACTA'), findsOneWidget);
    expect(find.textContaining('Galpón Principal A-1'), findsWidgets);
    expect(find.textContaining('Pallet PL-07-ALTO'), findsWidgets);
    expect(find.textContaining('Verificar cuidadosamente que incluya alternador'), findsWidgets);

    FlutterError.onError = originalOnError;
    expect(errorCaptured, isNull);
  });
}
