import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/caja/models/cobro_pendiente_model.dart';
import 'package:frontend/features/caja/presentation/widgets/confirmacion_liquidacion_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CobroPendienteModel ordenPrueba;

  setUp(() {
    ordenPrueba = CobroPendienteModel(
      idReferencia: 'ref-test-liquidar',
      folioDocumento: 'ORD-8821',
      tipoOperacion: 'VENTA',
      estadoDocumento: 'Reservada',
      clienteNombre: 'Valentina Silva Castro',
      clienteRut: '19.876.543-2',
      vendedorNombre: 'Marcos Rivas',
      fechaEmision: DateTime.now(),
      fechaEmisionFormateada: '08/10/2026',
      horaEmisionFormateada: '14:30',
      totalOperacion: 850000,
      abonoPrevio: 350000,
      saldoPendiente: 500000,
      montoACobrar: 500000,
      articulos: [],
    );
  });

  void setViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget createDialogHost({required Widget child, Size? size}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: size?.width ?? 600,
            height: size?.height ?? 700,
            child: child,
          ),
        ),
      ),
    );
  }

  testWidgets(
      'ConfirmacionLiquidacionDialog: Renderiza advertencia, resumen financiero y estado inicial desmarcado',
      (tester) async {
    await tester.pumpWidget(
      createDialogHost(
        child: ConfirmacionLiquidacionDialog(
          orden: ordenPrueba,
          montoALiquidar: 500000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Título y mensaje claro (sin terminología técnica ajena a la cajera)
    expect(find.text('Confirmar Liquidación Total'), findsOneWidget);
    expect(
      find.text('Estás a punto de liquidar el total de la orden.\n¿Estás seguro que no es un abono?'),
      findsOneWidget,
    );
    expect(find.textContaining('Poka'), findsNothing);

    // 2. Resumen financiero visual
    expect(find.text('ORD-8821'), findsOneWidget);
    expect(find.text('Valentina Silva Castro'), findsOneWidget);
    expect(find.text('\$850.000'), findsOneWidget); // Total
    expect(find.text('- \$350.000'), findsOneWidget); // Abonos previos
    expect(find.text('\$500.000'), findsOneWidget); // Monto a liquidar
    expect(find.textContaining('Saldo restante tras este pago: \$0 CLP'), findsOneWidget);

    // 3. Casilla desmarcada por defecto y botón deshabilitado
    final checkboxFinder = find.byType(Checkbox);
    expect(checkboxFinder, findsOneWidget);
    final checkbox = tester.widget<Checkbox>(checkboxFinder);
    expect(checkbox.value, isFalse);

    final btnConfirmarFinder = find.widgetWithText(ElevatedButton, 'Confirmar');
    expect(btnConfirmarFinder, findsOneWidget);
    final btnConfirmar = tester.widget<ElevatedButton>(btnConfirmarFinder);
    expect(btnConfirmar.onPressed, isNull);
  });

  testWidgets(
      'ConfirmacionLiquidacionDialog: Al marcar casilla se activa botón y confirmar retorna true',
      (tester) async {
    setViewport(tester);
    bool? resultadoRetornado;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                resultadoRetornado = await ConfirmacionLiquidacionDialog.show(
                  context: ctx,
                  orden: ordenPrueba,
                  montoALiquidar: 500000,
                );
              },
              child: const Text('Abrir Modal'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Abrir modal
    await tester.tap(find.text('Abrir Modal'));
    await tester.pumpAndSettle();

    // Marcar checkbox
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    // Presionar Confirmar
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(resultadoRetornado, isTrue);
  });

  testWidgets(
      'ConfirmacionLiquidacionDialog: Presionar Cancelar / Volver cierra el modal retornando false',
      (tester) async {
    setViewport(tester);
    bool? resultadoRetornado;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                resultadoRetornado = await ConfirmacionLiquidacionDialog.show(
                  context: ctx,
                  orden: ordenPrueba,
                  montoALiquidar: 500000,
                );
              },
              child: const Text('Abrir Modal'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Abrir modal
    await tester.tap(find.text('Abrir Modal'));
    await tester.pumpAndSettle();

    // Presionar Cancelar / Volver
    await tester.tap(find.text('Cancelar / Volver'));
    await tester.pumpAndSettle();

    expect(resultadoRetornado, isFalse);
  });

  testWidgets(
      'ConfirmacionLiquidacionDialog: Anti-overflow en viewport POS compacto (420 x 600)',
      (tester) async {
    tester.view.physicalSize = const Size(420, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      createDialogHost(
        size: const Size(420, 600),
        child: ConfirmacionLiquidacionDialog(
          orden: ordenPrueba,
          montoALiquidar: 500000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Comprobar que no hay RenderFlex overflow y todos los elementos críticos están presentes
    expect(find.text('Confirmar Liquidación Total'), findsOneWidget);
    expect(find.text('Cancelar / Volver'), findsOneWidget);
    expect(find.text('Confirmar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
