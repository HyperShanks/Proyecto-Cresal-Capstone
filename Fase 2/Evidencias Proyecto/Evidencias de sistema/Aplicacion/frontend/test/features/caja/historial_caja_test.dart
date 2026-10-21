import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/caja/models/cobro_pendiente_model.dart';
import 'package:frontend/features/caja/models/cobro_model.dart';
import 'package:frontend/features/caja/models/historial_caja_model.dart';
import 'package:frontend/features/caja/services/caja_service.dart';
import 'package:frontend/features/caja/presentation/providers/historial_caja_provider.dart';
import 'package:frontend/features/caja/presentation/widgets/historial_metricas_panel.dart';
import 'package:frontend/features/caja/presentation/widgets/detalle_auditoria_dialog.dart';
import 'package:frontend/features/caja/presentation/screens/historial_caja_screen.dart';

class MockCajaHistorialService implements ICajaService {
  HistorialCajaResponseModel? mockResponse;
  bool shouldFail = false;

  @override
  Future<List<CobroPendienteModel>> obtenerCobrosPendientes({
    required int sucursalId,
    String? busqueda,
    String? tipoOperacion,
  }) async {
    return [];
  }

  @override
  Future<RegistrarCobroResponseModel> registrarCobro(
    RegistrarCobroRequestModel request,
  ) async {
    return RegistrarCobroResponseModel(
      success: true,
      mensaje: 'Cobro registrado exitosamente',
      folio: 'ORD-9780',
      montoCobrado: request.montoDeclarado,
      nuevoSaldoPendiente: 0,
      estadoActualizado: 'Pagada',
      transaccionesIds: ['tx-001'],
    );
  }

  @override
  Future<ValidarActivoBackorderResponseModel> validarActivoBackorder(
    ValidarActivoBackorderRequestModel request,
  ) async {
    return ValidarActivoBackorderResponseModel(
      coincide: true,
      discrepancias: [],
      mensaje: 'Activo validado exitosamente',
    );
  }

  @override
  Future<HistorialCajaResponseModel> obtenerHistorialCaja({
    required int sucursalId,
    String periodo = 'HOY',
    String? fechaDesde,
    String? fechaHasta,
    String estadoOrden = 'TODOS',
    String metodoPago = 'TODOS',
    String? busqueda,
    int? montoMin,
    int? montoMax,
    String? idCajera,
    String? idVendedor,
    int pagina = 1,
    int limite = 20,
  }) async {
    if (shouldFail) {
      throw Exception('Fallo de conexión simulado en historial');
    }

    if (mockResponse != null) {
      var items = List<HistorialOrdenItemModel>.from(mockResponse!.items);

      if (estadoOrden != 'TODOS') {
        items = items.where((e) => e.estadoOrden == estadoOrden).toList();
      }

      if (metodoPago != 'TODOS') {
        items = items.where((e) => e.metodosResumen.toLowerCase().contains(metodoPago.toLowerCase())).toList();
      }

      if (busqueda != null && busqueda.isNotEmpty) {
        final q = busqueda.toLowerCase();
        items = items.where((e) {
          return e.folio.toLowerCase().contains(q) ||
              e.clienteNombre.toLowerCase().contains(q) ||
              (e.clienteRut?.toLowerCase().contains(q) ?? false) ||
              e.vendedorNombre.toLowerCase().contains(q);
        }).toList();
      }

      return HistorialCajaResponseModel(
        totalRegistros: items.length,
        paginaActual: pagina,
        limitePorPagina: limite,
        totalPaginas: 1,
        resumenCuadre: mockResponse!.resumenCuadre,
        items: items,
      );
    }

    return HistorialCajaResponseModel.empty();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockCajaHistorialService mockService;
  late HistorialOrdenItemModel sampleItem1;
  late HistorialOrdenItemModel sampleItem2;
  late ResumenCuadreCajaModel sampleCuadre;
  late HistorialCajaResponseModel sampleResponse;

  setUp(() {
    mockService = MockCajaHistorialService();

    sampleItem1 = HistorialOrdenItemModel(
      idOrden: '8f3b201a-63b7-4dc4-8392-8094a942b001',
      folio: 'ORD-9778',
      tipoOperacion: 'VENTA',
      emiteQr: true,
      fechaIso: '2026-08-21',
      hora: '10:14',
      fechaHoraFormateada: '10:14 - 21/08/2026',
      clienteNombre: 'Taller Mecánico San Cristóbal SpA',
      clienteRut: '77.301.992-1',
      vendedorNombre: 'Andrés Morales (Mesón 2)',
      cajeraNombre: 'Lorena Valenzuela (Caja 01)',
      estadoOrden: 'Pagada',
      modalidadPago: 'split',
      metodosResumen: 'Débito: \$420.000 + Transferencia: \$180.000',
      totalVenta: 600000,
      abonoPrevio: 0,
      totalLiquidado: 600000,
      desglosePagos: [
        HistorialPagoDetalleModel(
          idTransaccion: '1c7a911e-2879-43c3-9821-2e557b451001',
          metodoPago: 'Débito',
          monto: 420000,
          fechaPago: DateTime.now(),
        ),
        HistorialPagoDetalleModel(
          idTransaccion: '2d8b022f-3980-54d4-a932-3f668c562002',
          metodoPago: 'Transferencia',
          monto: 180000,
          fechaPago: DateTime.now(),
        ),
      ],
      articulos: [
        HistorialArticuloModel(
          cantidad: 1,
          tipo: 'INVENTARIADO',
          descripcion: 'Caja de Cambios Automática Toyota Hilux 2.8',
          sku: 'CAJ-TOY-HIL-28-091',
          precio: 500000,
          subtotal: 500000,
        ),
        HistorialArticuloModel(
          cantidad: 1,
          tipo: 'DESARME',
          descripcion: 'Filtro y Sensor de Caja de Cambios',
          sku: null,
          precio: 100000,
          subtotal: 100000,
        ),
      ],
      historialMovimientos: [
        HistorialMovimientoModel(
          hora: '09:45',
          evento: 'Orden emitida en Mesón 2 por Andrés Morales',
        ),
        HistorialMovimientoModel(
          hora: '10:14',
          evento: 'Pago liquidado en ventanilla por Lorena Valenzuela',
        ),
        HistorialMovimientoModel(
          hora: '10:15',
          evento: 'QR Transaccional generado para barrera de salida',
        ),
      ],
    );

    sampleItem2 = HistorialOrdenItemModel(
      idOrden: '9a4c312b-74c8-5ed5-94a3-9105b053c002',
      folio: 'ORD-9773',
      tipoOperacion: 'VENTA',
      emiteQr: true,
      fechaIso: '2026-08-21',
      hora: '09:30',
      fechaHoraFormateada: '09:30 - 21/08/2026',
      clienteNombre: 'Pedro Aguirres Molina',
      clienteRut: '15.420.301-8',
      vendedorNombre: 'Juaquin Leiva (Mesón 1)',
      cajeraNombre: 'Lorena Valenzuela (Caja 01)',
      estadoOrden: 'Despachada',
      modalidadPago: 'unico',
      metodosResumen: 'Efectivo: \$650.000',
      totalVenta: 650000,
      abonoPrevio: 0,
      totalLiquidado: 650000,
      desglosePagos: [
        HistorialPagoDetalleModel(
          idTransaccion: '3e9c133a-4091-65e5-ba43-4a779d673003',
          metodoPago: 'Efectivo',
          monto: 650000,
          fechaPago: DateTime.now(),
        ),
      ],
      articulos: [
        HistorialArticuloModel(
          cantidad: 1,
          tipo: 'INVENTARIADO',
          descripcion: 'Motor Suzuki Swift 1.2 K12M Semiequipado',
          sku: 'MOT-SUZ-SW-12-044',
          precio: 650000,
          subtotal: 650000,
        ),
      ],
      historialMovimientos: [
        HistorialMovimientoModel(
          hora: '09:10',
          evento: 'Orden emitida en Mesón 1 por Juaquin Leiva',
        ),
        HistorialMovimientoModel(
          hora: '09:30',
          evento: 'Cobro total liquidado en efectivo en Caja 01',
        ),
      ],
    );

    sampleCuadre = ResumenCuadreCajaModel(
      totalRecaudado: 1250000,
      totalOrdenesPagadas: 2,
      totalEfectivo: 650000,
      totalPos: 420000,
      totalDebito: 420000,
      totalCredito: 0,
      totalTransferencia: 180000,
      totalCheque: 0,
    );

    sampleResponse = HistorialCajaResponseModel(
      totalRegistros: 2,
      paginaActual: 1,
      limitePorPagina: 20,
      totalPaginas: 1,
      resumenCuadre: sampleCuadre,
      items: [sampleItem1, sampleItem2],
    );

    mockService.mockResponse = sampleResponse;
  });

  group('SPEC-HU-4.5: DTOs & Model Serialization Tests', () {
    test('Modelos de Historial serializan y deserializan correctamente', () {
      final json = sampleItem1.toJson();
      expect(json['folio'], 'ORD-9778');
      expect(json['modalidad_pago'], 'split');
      expect(json['total_liquidado'], 600000);
      expect(sampleItem1.esSplit, isTrue);
      expect(sampleItem1.esPagada, isTrue);
      expect(sampleItem1.esDespachada, isFalse);

      final fromJson = HistorialOrdenItemModel.fromJson(json);
      expect(fromJson.folio, 'ORD-9778');
      expect(fromJson.desglosePagos.length, 2);
      expect(fromJson.desglosePagos.first.metodoPago, 'Débito');
      expect(fromJson.articulos.length, 2);
      expect(fromJson.historialMovimientos.length, 3);
    });

    test('ResumenCuadreCajaModel serializa correctamente', () {
      final json = sampleCuadre.toJson();
      expect(json['total_recaudado'], 1250000);
      expect(json['total_pos'], 420000);
      expect(json['total_efectivo'], 650000);

      final fromJson = ResumenCuadreCajaModel.fromJson(json);
      expect(fromJson.totalRecaudado, 1250000);
      expect(fromJson.totalOrdenesPagadas, 2);
    });
  });

  group('SPEC-HU-4.5: HistorialCajaProvider State & Filter Tests', () {
    test('HistorialCajaProvider carga historial y maneja selección de auditoría', () async {
      final provider = HistorialCajaProvider(
        cajaService: mockService,
        sucursalId: 1,
        autoCargar: false,
      );
      expect(provider.state.data, isNull);

      await provider.cargarHistorial();
      expect(provider.state.data?.items.length, 2);
      expect(provider.state.data?.resumenCuadre.totalRecaudado, 1250000);

      // Selección de orden para auditoría
      provider.seleccionarOrdenAuditoria(sampleItem1);
      expect(provider.state.ordenAuditoria?.folio, 'ORD-9778');

      provider.seleccionarOrdenAuditoria(null);
      expect(provider.state.ordenAuditoria, isNull);
    });

    test('HistorialCajaProvider filtra por estado y método de pago', () async {
      final provider = HistorialCajaProvider(
        cajaService: mockService,
        sucursalId: 1,
      );
      await Future.delayed(Duration.zero);

      provider.cambiarFiltroEstado('Pagada');
      await Future.delayed(Duration.zero);
      expect(provider.state.estadoOrden, 'Pagada');
      expect(provider.state.data?.items.length, 1);
      expect(provider.state.data?.items.first.folio, 'ORD-9778');

      provider.cambiarFiltroMetodo('Efectivo');
      await Future.delayed(Duration.zero);
      expect(provider.state.metodoPago, 'Efectivo');
    });

    test('HistorialCajaProvider maneja errores de red', () async {
      mockService.shouldFail = true;
      final provider = HistorialCajaProvider(
        cajaService: mockService,
        sucursalId: 1,
        autoCargar: false,
      );

      await provider.cargarHistorial();
      expect(provider.state.errorMessage, isNotNull);
      expect(provider.state.data, isNull);
    });
  });

  group('SPEC-HU-4.5: HistorialMetricasPanel Widget Tests', () {
    testWidgets('HistorialMetricasPanel renderiza las 4 tarjetas de cuadre con montos formateados', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistorialMetricasPanel(resumen: sampleCuadre),
          ),
        ),
      );

      expect(find.text('Total Recaudado'), findsOneWidget);
      expect(find.text('\$1.250.000'), findsOneWidget);
      expect(find.text('2 órdenes pagadas'), findsOneWidget);

      expect(find.text('Total Efectivo'), findsOneWidget);
      expect(find.text('\$650.000'), findsOneWidget);

      expect(find.text('Total Tarjetas POS'), findsOneWidget);
      expect(find.text('\$420.000'), findsOneWidget);

      expect(find.text('Transferencias / Cheques'), findsOneWidget);
      expect(find.text('\$180.000'), findsOneWidget);
    });
  });

  group('SPEC-HU-4.5: DetalleAuditoriaDialog & Modal UI Tests', () {
    testWidgets('DetalleAuditoriaDialog renderiza ficha completa, desglose de piezas y pagos', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => DetalleAuditoriaDialog.show(context, sampleItem1),
                child: const Text('Abrir Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Modal'));
      await tester.pumpAndSettle();

      // Cabecera
      expect(find.text('ORD-9778'), findsOneWidget);
      expect(find.text('PAGADA'), findsOneWidget);
      expect(find.text('QR Activo'), findsOneWidget);

      // Ficha Cliente
      expect(find.text('Taller Mecánico San Cristóbal SpA'), findsOneWidget);
      expect(find.text('RUT: 77.301.992-1'), findsOneWidget);

      // Desglose de piezas
      expect(find.text('Caja de Cambios Automática Toyota Hilux 2.8'), findsOneWidget);
      expect(find.text('SKU: CAJ-TOY-HIL-28-091'), findsOneWidget);

      // Desglose pagos
      expect(find.text('Débito'), findsOneWidget);
      expect(find.text('Transferencia'), findsOneWidget);

      // Timeline
      expect(find.text('Orden emitida en Mesón 2 por Andrés Morales'), findsOneWidget);
      expect(find.text('QR Transaccional generado para barrera de salida'), findsOneWidget);

      // Cerrar modal
      await tester.tap(find.text('CERRAR'));
      await tester.pumpAndSettle();
      expect(find.text('DETALLE DE PIEZAS Y ARTÍCULOS'), findsNothing);
    });
  });

  group('SPEC-HU-4.5: HistorialCajaScreen End-to-End Tests', () {
    testWidgets('HistorialCajaScreen renderiza cabecera, filtros, tabla y abre modal al pulsar Ver Detalle', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider = HistorialCajaProvider(
        cajaService: mockService,
        sucursalId: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistorialCajaScreen(provider: provider),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pestañas de períodos
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Esta Semana'), findsOneWidget);
      expect(find.text('Este Mes'), findsOneWidget);

      // Filas de la tabla
      expect(find.text('ORD-9778'), findsOneWidget);
      expect(find.text('ORD-9773'), findsOneWidget);

      // Pulsar Ver Detalle en primera fila
      final verDetalleButtons = find.text('Ver Detalle');
      expect(verDetalleButtons, findsWidgets);
      await tester.tap(verDetalleButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('DESGLOSE EXACTO DE PAGOS (AUDITORÍA)'), findsOneWidget);

      // Cerrar modal
      await tester.tap(find.text('CERRAR'));
      await tester.pumpAndSettle();
    });

    testWidgets('HistorialCajaScreen renderiza Zero State cuando no hay registros', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      mockService.mockResponse = HistorialCajaResponseModel.empty();

      final provider = HistorialCajaProvider(
        cajaService: mockService,
        sucursalId: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistorialCajaScreen(provider: provider),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No se encontraron órdenes en este período o filtro'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
    });

    testWidgets('Botón Limpiar muestra contador activo y restablece filtros al ser pulsado', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider = HistorialCajaProvider(
        cajaService: mockService,
        sucursalId: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HistorialCajaScreen(provider: provider),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Inicialmente no hay filtros activos
      expect(find.text('Limpiar'), findsOneWidget);
      expect(provider.state.cantidadFiltrosActivos, 0);

      // Activar filtro de estado 'Pagada' y período 'Esta Semana'
      provider.cambiarFiltroEstado('Pagada');
      provider.cambiarPeriodo(PeriodoHistorial.estaSemana);
      await tester.pumpAndSettle();

      // Debe mostrar contador de 2 filtros activos en el botón Limpiar
      expect(provider.state.cantidadFiltrosActivos, 2);
      expect(find.text('2'), findsOneWidget);

      // Pulsar Limpiar
      await tester.tap(find.text('Limpiar'));
      await tester.pumpAndSettle();

      // Filtros deben quedar restablecidos
      expect(provider.state.cantidadFiltrosActivos, 0);
      expect(provider.state.estadoOrden, 'TODOS');
      expect(provider.state.periodo, PeriodoHistorial.hoy);
    });

    test('HistorialCajaProvider descarta respuestas asíncronas desfasadas (anti-race condition)', () async {
      final provider = HistorialCajaProvider(
        cajaService: mockService,
        sucursalId: 1,
        autoCargar: false,
      );

      // Disparar carga inicial
      final f1 = provider.cargarHistorial();
      // Inmediatamente cambiar filtro antes de que f1 termine
      provider.cambiarFiltroEstado('Pagada');

      await f1;

      // El estado del provider no debe haber sido pisado por f1
      expect(provider.state.estadoOrden, 'Pagada');
      if (provider.state.data != null) {
        expect(provider.state.data!.items.every((it) => it.estadoOrden == 'Pagada'), isTrue);
      }
    });
  });
}
