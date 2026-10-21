// frontend/test/features/gerencia/visor_ordenes_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/caja/models/historial_caja_model.dart';
import 'package:frontend/features/gerencia/presentation/screens/ordenes_gerencia_view.dart';
import 'package:frontend/features/gerencia/presentation/widgets/auditoria_detalle_dialog.dart';
import 'package:frontend/features/gerencia/presentation/widgets/auditoria_tabla_view.dart';
import 'package:frontend/features/gerencia/presentation/widgets/panel_filtros_avanzados.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockItem1 = HistorialOrdenItemModel(
    idOrden: 'ord-001-uuid',
    folio: 'ORD-AUD-001',
    tipoOperacion: 'VENTA',
    emiteQr: true,
    fechaIso: '2026-09-07T10:30:00Z',
    hora: '10:30',
    fechaHoraFormateada: '07/09/2026 10:30',
    clienteNombre: 'Juan Carlos Pérez Cotapos',
    clienteRut: '12.345.678-9',
    vendedorNombre: 'Pedro Vendedor',
    cajeraNombre: 'Lorena Valenzuela',
    estadoOrden: 'Pagada',
    modalidadPago: 'unico',
    metodosResumen: 'Efectivo \$85.000',
    totalVenta: 85000,
    abonoPrevio: 0,
    totalLiquidado: 85000,
    montoPendiente: 0,
    idSucursal: 1,
    sucursalNombre: 'Casa Matriz (Viña)',
    desglosePagos: [
      HistorialPagoDetalleModel(
        idTransaccion: 'tx-001',
        metodoPago: 'Efectivo',
        monto: 85000,
      ),
    ],
    articulos: [
      HistorialArticuloModel(
        cantidad: 1,
        tipo: 'INVENTARIADO',
        descripcion: 'Amortiguador Delantero',
        sku: 'AMORT-FRON-001',
        precio: 85000,
        subtotal: 85000,
      ),
    ],
    historialMovimientos: [
      HistorialMovimientoModel(
        hora: '10:30',
        evento: 'Venta cerrada y pagada 100% en caja',
      ),
    ],
  );

  final mockItem2 = HistorialOrdenItemModel(
    idOrden: 'ord-002-uuid',
    folio: 'ORD-AUD-002',
    tipoOperacion: 'RESERVA',
    emiteQr: false,
    fechaIso: '2026-09-07T11:00:00Z',
    hora: '11:00',
    fechaHoraFormateada: '07/09/2026 11:00',
    clienteNombre: 'María Ignacia González Silva',
    clienteRut: '19.876.543-2',
    vendedorNombre: 'Pedro Vendedor',
    cajeraNombre: 'Lorena Valenzuela',
    estadoOrden: 'Reservada',
    modalidadPago: 'unico',
    metodosResumen: 'Transferencia \$100.000',
    totalVenta: 150000,
    abonoPrevio: 100000,
    totalLiquidado: 100000,
    montoPendiente: 50000,
    idSucursal: 2,
    sucursalNombre: 'Patio Desarme (Limache)',
    desglosePagos: [
      HistorialPagoDetalleModel(
        idTransaccion: 'tx-002',
        metodoPago: 'Transferencia',
        monto: 100000,
      ),
    ],
    articulos: [
      HistorialArticuloModel(
        cantidad: 1,
        tipo: 'INVENTARIADO',
        descripcion: 'Bandeja de Suspensión Derecha',
        sku: 'BAND-SUSP-002',
        precio: 150000,
        subtotal: 150000,
      ),
    ],
    historialMovimientos: [
      HistorialMovimientoModel(
        hora: '11:00',
        evento: 'Abono recibido por reserva de repuesto',
      ),
    ],
  );

  final mockItem3 = HistorialOrdenItemModel(
    idOrden: 'ord-003-uuid',
    folio: 'ORD-AUD-003',
    tipoOperacion: 'VENTA',
    emiteQr: true,
    fechaIso: '2026-09-07T12:00:00Z',
    hora: '12:00',
    fechaHoraFormateada: '07/09/2026 12:00',
    clienteNombre: 'Carlos Santana',
    vendedorNombre: 'Pedro Vendedor',
    cajeraNombre: 'Lorena Valenzuela',
    estadoOrden: 'Pagada',
    modalidadPago: 'unico',
    metodosResumen: 'Efectivo \$450.000',
    totalVenta: 450000,
    abonoPrevio: 0,
    totalLiquidado: 450000,
    montoPendiente: 0,
    sucursalNombre: 'Sucursal Rancagua',
    desglosePagos: [],
    articulos: [
      HistorialArticuloModel(
        cantidad: 1,
        tipo: 'INVENTARIADO',
        descripcion: 'Motor 2.0 HDI Completo',
        categoria: 'Motor',
        sku: 'MOT-HDI-003',
        precio: 450000,
        subtotal: 450000,
      ),
    ],
    historialMovimientos: [],
  );

  final mockItem4 = HistorialOrdenItemModel(
    idOrden: 'ord-004-uuid',
    folio: 'ORD-AUD-004',
    tipoOperacion: 'VENTA',
    emiteQr: true,
    fechaIso: '2026-09-07T13:00:00Z',
    hora: '13:00',
    fechaHoraFormateada: '07/09/2026 13:00',
    clienteNombre: 'Diego Muñoz',
    vendedorNombre: 'Pedro Vendedor',
    cajeraNombre: 'Lorena Valenzuela',
    estadoOrden: 'Pagada',
    modalidadPago: 'unico',
    metodosResumen: 'Efectivo \$25.000',
    totalVenta: 250000,
    abonoPrevio: 0,
    totalLiquidado: 250000,
    montoPendiente: 0,
    sucursalNombre: 'Sucursal La Calera',
    desglosePagos: [],
    articulos: [
      HistorialArticuloModel(
        cantidad: 1,
        tipo: 'DESARME',
        descripcion: 'Espejo Lateral Derecho Usado',
        precio: 25000,
        subtotal: 25000,
      ),
    ],
    historialMovimientos: [],
  );

  group('1. PanelFiltrosAvanzados (HU-5.2)', () {
    testWidgets('Renderiza controles de filtrado multidimensional según prototipo',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = TextEditingController();
      String periodo = 'todos';
      String estado = 'todos';
      String metodo = 'todos';
      String tipoActivo = 'todos';
      bool limpioTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PanelFiltrosAvanzados(
              busquedaController: controller,
              onBusquedaChanged: (_) {},
              periodoSeleccionado: periodo,
              onPeriodoChanged: (p) => periodo = p,
              estadoSeleccionado: estado,
              onEstadoChanged: (e) => estado = e,
              metodoPagoSeleccionado: metodo,
              onMetodoPagoChanged: (m) => metodo = m,
              tipoActivoSeleccionado: tipoActivo,
              onTipoActivoChanged: (t) => tipoActivo = t,
              onLimpiar: () => limpioTriggered = true,
            ),
          ),
        ),
      );

      // Verificamos placeholder predictivo
      expect(
        find.text('Buscar por Folio, Cliente, RUT o Vendedor...'),
        findsOneWidget,
      );

      // Verificamos botones de período predeterminado
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Esta Semana'), findsOneWidget);
      expect(find.text('Este Mes'), findsOneWidget);
      expect(find.text('Todo'), findsOneWidget);

      // Verificamos selects
      expect(find.text('Estado: Todos'), findsOneWidget);
      expect(find.text('Método: Todos'), findsOneWidget);
      expect(find.text('Tipo: Todos'), findsOneWidget);

      // Verificamos botón Limpiar y su callback
      final btnLimpiar = find.text('Limpiar');
      expect(btnLimpiar, findsOneWidget);
      await tester.tap(btnLimpiar);
      expect(limpioTriggered, isTrue);

      // Verificamos interacción con período 'Hoy'
      await tester.tap(find.text('Hoy'));
      expect(periodo, 'hoy');
    });
  });

  group('2. AuditoriaTablaView (10 Columnas del Mockup Oficial HU-5.2)', () {
    testWidgets(
        'Renderiza las 10 columnas exactas del mockup, columna PENDIENTE dedicada e ícono de ojo',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      HistorialOrdenItemModel? ordenAuditada;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: AuditoriaTablaView(
                items: [mockItem1, mockItem2, mockItem3, mockItem4],
                paginaActual: 1,
                totalPaginas: 1,
                totalRegistros: 4,
                totalConsolidado: 935000,
                onCambiarPagina: (_) {},
                onVerDetalle: (orden) => ordenAuditada = orden,
              ),
            ),
          ),
        ),
      );

      // 1. Verificamos las 10 cabeceras oficiales del mockup
      expect(find.text('FOLIO'), findsOneWidget);
      expect(find.text('FECHA / HORA'), findsOneWidget);
      expect(find.text('CLIENTE / RUT'), findsOneWidget);
      expect(find.text('SUCURSAL'), findsOneWidget);
      expect(find.text('VENDEDOR / CAJERA'), findsOneWidget);
      expect(find.text('MÉTODO DE PAGO'), findsOneWidget);
      expect(find.text('TOTAL VENTA'), findsOneWidget);
      expect(find.text('PENDIENTE'), findsOneWidget);
      expect(find.text('ESTADO OFICIAL'), findsOneWidget);
      expect(find.text('ACCIONES'), findsOneWidget);

      // 2. Verificamos celdas de las órdenes
      expect(find.text('ORD-AUD-001'), findsOneWidget);
      expect(find.text('ORD-AUD-002'), findsOneWidget);
      expect(find.text('ORD-AUD-003'), findsOneWidget);
      expect(find.text('ORD-AUD-004'), findsOneWidget);
      expect(find.text('Casa Matriz (Viña)'), findsOneWidget);
      expect(find.text('Patio Desarme (Limache)'), findsOneWidget);

      // 3. Verificamos columna PENDIENTE: '—' para orden 1 pagada, y '$50.000' para orden 2 abonada
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('\$50.000'), findsOneWidget);

      // 4. Verificamos distintivos en FOLIO (despliega SKU exacto MOT-HDI-003, suprimiendo Motor / Caja)
      expect(find.text('MOT-HDI-003'), findsOneWidget);
      expect(find.text('Motor / Caja'), findsNothing);
      expect(find.text('Inventariado'), findsNothing);
      expect(find.text('Desarme'), findsNothing);

      // 5. Verificamos botones de acción "Auditar" con ícono de ojo
      final botonesAuditar = find.text('Auditar');
      expect(botonesAuditar, findsNWidgets(4));
      expect(find.byIcon(Icons.visibility_outlined), findsNWidgets(4));

      // 6. Verificamos pie de tabla integrado
      expect(find.textContaining('Mostrando '), findsOneWidget);
      expect(find.textContaining('Total Consolidado en Vista: '), findsOneWidget);

      // 7. Verificamos clic en auditar la primera orden
      await tester.tap(botonesAuditar.first);
      expect(ordenAuditada, isNotNull);
      expect(ordenAuditada!.folio, 'ORD-AUD-001');
    });
  });

  group('3. AuditoriaDetalleDialog (Modal Forense Oficial del Mockup HU-5.2)', () {
    testWidgets('Muestra cabecera oficial, tarjetas, artículos con badge 1x, pagos y botón Cerrar',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => AuditoriaDetalleDialog.show(context, mockItem3),
                child: const Text('Abrir Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Modal'));
      await tester.pumpAndSettle();

      // 1. Verificamos cabecera oficial con Folio y Badge con SKU físico del Motor (MOT-HDI-003)
      expect(find.text('AUDITORÍA DE VENTA'), findsOneWidget);
      expect(find.text('ORD-AUD-003'), findsOneWidget);
      expect(find.text('MOT-HDI-003'), findsWidgets);
      expect(find.text('Motor / Caja'), findsNothing);

      // 2. Verificamos tarjeta de Cliente y Responsables
      expect(find.text('CLIENTE'), findsOneWidget);
      expect(find.text('Carlos Santana'), findsOneWidget);
      expect(find.text('RESPONSABLES'), findsOneWidget);
      expect(find.textContaining('Pedro Vendedor'), findsWidgets);

      // 3. Verificamos desglose de artículos con badge 1x y tag de Activo Físico
      expect(find.text('ARTÍCULOS Y REPUESTOS'), findsOneWidget);
      expect(find.text('1x'), findsOneWidget);
      expect(find.text('Motor 2.0 HDI Completo'), findsOneWidget);
      expect(find.textContaining('SKU: MOT-HDI-003'), findsOneWidget);
      expect(find.text('Activo Físico'), findsOneWidget);

      // 4. Verificamos desglose de pagos y total liquidado
      expect(find.text('DESGLOSE EXACTO DE PAGOS'), findsOneWidget);
      expect(find.text('TOTAL LIQUIDADO:'), findsOneWidget);

      // 5. Verificamos línea de tiempo
      expect(find.text('LÍNEA DE TIEMPO / MOVIMIENTOS'), findsOneWidget);

      // 6. Verificamos botón de cierre
      expect(find.text('Cerrar'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      // Verificamos que el modal se cerró
      expect(find.text('AUDITORÍA DE VENTA'), findsNothing);
    });
  });

  group('4. OrdenesGerenciaView (Integración de Pantalla)', () {
    testWidgets('Renderiza barra de filtros, banner de total consolidado y estado',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OrdenesGerenciaView(idSucursalInicial: null),
          ),
        ),
      );

      // Verificamos que se renderiza la barra de filtros
      expect(
        find.text('Buscar por Folio, Cliente, RUT o Vendedor...'),
        findsOneWidget,
      );

      // Verificamos que inicialmente muestra el indicador de carga
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
