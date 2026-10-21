import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/caja/models/cobro_model.dart';
import 'package:frontend/features/caja/models/cobro_pendiente_model.dart';
import 'package:frontend/features/caja/presentation/widgets/resultado_cobro_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CobroPendienteModel sampleVenta;
  late CobroPendienteModel sampleBackorder;
  late RegistrarCobroResponseModel resultadoLiquidacionTotal;
  late RegistrarCobroResponseModel resultadoAbonoParcial;
  late RegistrarCobroResponseModel resultadoAbonoBackorder;

  setUp(() {
    sampleVenta = CobroPendienteModel(
      idReferencia: '3fa85f64-5717-4562-b3fc-2c963f66afa6',
      folioDocumento: 'ORD-9780',
      tipoOperacion: 'VENTA',
      estadoDocumento: 'Reservada',
      clienteNombre: 'Cristobal Alejandro Espinoza Perez',
      clienteRut: '14.892.401-2',
      vendedorNombre: 'Juaquin Leiva',
      fechaEmision: DateTime.now(),
      fechaEmisionFormateada: '21/08/2026',
      horaEmisionFormateada: '11:38',
      totalOperacion: 650000,
      abonoPrevio: 150000,
      montoACobrar: 500000,
      articulos: [
        ArticuloResumenModel(
          cantidad: 1,
          tipo: 'INVENTARIADO',
          descripcion: 'Motor MG ZS 1.5 VTi-Tech Completo',
          sku: 'MOT-MG-ZS-15-089',
          precio: 500000,
          subtotal: 500000,
        ),
      ],
      especificacionesBackorder: null,
    );

    sampleBackorder = CobroPendienteModel(
      idReferencia: '7c9e6679-7425-40de-944b-e07fc1f90ae7',
      folioDocumento: 'RES-5401',
      tipoOperacion: 'BACKORDER',
      estadoDocumento: 'Pendiente',
      clienteNombre: 'Camila Andrea Soto Lagos',
      clienteRut: '18.432.109-K',
      vendedorNombre: 'Juaquin Leiva',
      fechaEmision: DateTime.now(),
      fechaEmisionFormateada: '21/08/2026',
      horaEmisionFormateada: '12:20',
      totalOperacion: 1200000,
      abonoPrevio: 900000,
      montoACobrar: 300000,
      articulos: [],
      especificacionesBackorder: BackorderEspecificacionesModel(
        marca: 'Hyundai',
        modelo: 'Tucson 2.0 CRDi Turbo Diesel',
        anio: 2022,
        categoria: 'Conjunto Motor y Turbo',
        cilindrada: '2.0',
        combustible: 'Diesel',
        transito: 'En Tránsito Marítimo',
      ),
    );

    resultadoLiquidacionTotal = RegistrarCobroResponseModel(
      success: true,
      mensaje: 'Cobro registrado exitosamente',
      folio: 'ORD-9780',
      montoCobrado: 500000,
      nuevoSaldoPendiente: 0,
      estadoActualizado: 'Pagada',
      transaccionesIds: ['tx-001'],
      qrGenerado: 'TX-QR-3FA85F64-ABC123DEF456',
    );

    resultadoAbonoParcial = RegistrarCobroResponseModel(
      success: true,
      mensaje: 'Cobro registrado exitosamente',
      folio: 'ORD-9780',
      montoCobrado: 200000,
      nuevoSaldoPendiente: 300000,
      estadoActualizado: 'Reservada',
      transaccionesIds: ['tx-002'],
      qrGenerado: null,
    );

    resultadoAbonoBackorder = RegistrarCobroResponseModel(
      success: true,
      mensaje: 'Cobro registrado exitosamente',
      folio: 'RES-5401',
      montoCobrado: 200000,
      nuevoSaldoPendiente: 100000,
      estadoActualizado: 'Confirmada',
      transaccionesIds: ['tx-003'],
      qrGenerado: null,
    );
  });

  void setDesktopViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget createTestWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: child,
        ),
      ),
    );
  }

  group('SPEC-HU-04: ResultadoCobroDialog Widget Tests', () {
    testWidgets('Liquidación Total renderiza cabecera verde, mensaje QR y aviso de entrega',
        (tester) async {
      setDesktopViewport(tester);
      await tester.pumpWidget(
        createTestWidget(
          ResultadoCobroDialog(
            orden: sampleVenta,
            resultado: resultadoLiquidacionTotal,
            metodosResumen: 'Efectivo: \$500.000',
            onSiguienteOrden: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Título y Subtítulo
      expect(find.text('Pago Registrado Exitosamente'), findsOneWidget);
      expect(find.text('QR Transaccional generado para barrera de salida'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      // Resumen Financiero
      expect(find.text('FOLIO ORDEN'), findsOneWidget);
      expect(find.text('ORD-9780'), findsOneWidget);
      expect(find.text('Cristobal Alejandro Espinoza Perez'), findsOneWidget);
      expect(find.text('RUT: 14.892.401-2'), findsOneWidget);
      expect(find.text('MONTO TOTAL PAGADO'), findsOneWidget);
      expect(find.text('\$500.000'), findsOneWidget);
      expect(find.text('Efectivo: \$500.000'), findsOneWidget);

      // No debe mostrar saldo pendiente cuando es $0 en liquidación total
      expect(find.text('NUEVO SALDO PENDIENTE:'), findsNothing);

      // Instrucción Operativa de entrega física
      expect(find.text('Instrucción Operativa:'), findsOneWidget);
      expect(
        find.text('Derive al cliente al Mesón de Venta para la entrega física de sus piezas y repuestos.'),
        findsOneWidget,
      );

      // Verificación de regla: Cero imágenes gráficas de QR
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('Abono Parcial de Venta renderiza cabecera azul, banner ámbar y nuevo saldo',
        (tester) async {
      setDesktopViewport(tester);
      await tester.pumpWidget(
        createTestWidget(
          ResultadoCobroDialog(
            orden: sampleVenta,
            resultado: resultadoAbonoParcial,
            metodosResumen: 'Transferencia: \$200.000',
            onSiguienteOrden: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Título y Subtítulo
      expect(find.text('Comprobante de Abono Registrado'), findsOneWidget);
      expect(find.text('Abono procesado correctamente • Sin emisión de QR'), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);

      // Resumen Financiero
      expect(find.text('ABONO INGRESADO'), findsOneWidget);
      expect(find.text('\$200.000'), findsOneWidget);
      expect(find.text('NUEVO SALDO PENDIENTE:'), findsOneWidget);
      expect(find.text('\$300.000'), findsOneWidget);

      // Instrucción Operativa con advertencia de retención
      expect(
        find.text(
          'La orden queda retenida en estado \'Reservada\' / Confirmada sin código QR de salida hasta la liquidación final o arribo a bodega.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('Abono de Reserva Backorder renderiza folio de reserva y saldo pendiente',
        (tester) async {
      setDesktopViewport(tester);
      await tester.pumpWidget(
        createTestWidget(
          ResultadoCobroDialog(
            orden: sampleBackorder,
            resultado: resultadoAbonoBackorder,
            metodosResumen: 'Crédito: \$200.000',
            onSiguienteOrden: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FOLIO RESERVA'), findsOneWidget);
      expect(find.text('RES-5401'), findsOneWidget);
      expect(find.text('Camila Andrea Soto Lagos'), findsOneWidget);
      expect(find.text('\$100.000'), findsOneWidget);
    });

    testWidgets('Botón Siguiente Orden dispara el callback onSiguienteOrden',
        (tester) async {
      setDesktopViewport(tester);
      bool siguienteOrdenPulsado = false;

      await tester.pumpWidget(
        createTestWidget(
          ResultadoCobroDialog(
            orden: sampleVenta,
            resultado: resultadoLiquidacionTotal,
            metodosResumen: 'Efectivo: \$500.000',
            onSiguienteOrden: () {
              siguienteOrdenPulsado = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Siguiente Orden'), findsOneWidget);
      await tester.tap(find.text('Siguiente Orden'));
      await tester.pumpAndSettle();

      expect(siguienteOrdenPulsado, isTrue);
    });

    testWidgets('Venta de Misceláneos 100% pagada renderiza cabecera verde de Venta Completada en Mostrador y aviso de entrega en mostrador sin QR',
        (tester) async {
      setDesktopViewport(tester);

      final resultadoMisc = RegistrarCobroResponseModel(
        success: true,
        mensaje: 'Cobro registrado exitosamente',
        folio: 'ORD-2026-0999',
        montoCobrado: 45000,
        nuevoSaldoPendiente: 0,
        estadoActualizado: 'Completada',
        transaccionesIds: ['tx-misc-001'],
        qrGenerado: null,
      );

      await tester.pumpWidget(
        createTestWidget(
          ResultadoCobroDialog(
            orden: sampleVenta,
            resultado: resultadoMisc,
            metodosResumen: 'Efectivo: \$45.000',
            onSiguienteOrden: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Venta Completada en Mostrador'), findsOneWidget);
      expect(find.text('Pago 100% saldado • Entrega inmediata en mostrador'), findsOneWidget);
      expect(
        find.textContaining('La venta de misceláneos ha sido saldada y completada exitosamente'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.qr_code_2_rounded), findsNothing);
    });
  });
}
