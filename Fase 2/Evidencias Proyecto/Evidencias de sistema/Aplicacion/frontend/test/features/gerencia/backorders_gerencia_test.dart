// frontend/test/features/gerencia/backorders_gerencia_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/gerencia/models/backorder_gerencia_models.dart';
import 'package:frontend/features/gerencia/presentation/screens/backorders_gerencia_view.dart';
import 'package:frontend/features/gerencia/presentation/widgets/kpi_card_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HU-5.4: Modelos de Backorders', () {
    test('BackorderItemModel deserializa correctamente todos los campos', () {
      final json = {
        'id_reserva': 'res-001',
        'folio': 'RES-5401',
        'fecha_creacion': 'Hoy 10:15',
        'fecha_creacion_iso': '2026-09-08T10:15:00Z',
        'id_cliente': 'cli-101',
        'cliente_nombre': 'Marcelo Gómez T.',
        'cliente_telefono': '+56987654321',
        'cliente_rut': '18.111.222-3',
        'id_vendedor': 'usr-201',
        'vendedor_nombre': 'Gastón Zamora',
        'id_sucursal': 1,
        'sucursal_nombre': 'Casa Matriz (Viña)',
        'id_categoria_requerida': 1,
        'categoria_nombre': 'Motor',
        'marca_requerida': 'Mitsubishi',
        'modelo_requerido': 'L200 Dakar',
        'anio_requerido': 2021,
        'cilindrada_requerida': '2.4',
        'combustible_requerido': 'Diesel',
        'transmision_requerida': 'Automática',
        'notas_preparacion': 'Revisar inyectores',
        'precio_acordado': 2100000,
        'monto_abonado': 500000,
        'saldo_pendiente': 1600000,
        'estado_reserva': 'Confirmada',
        'id_activo_asignado': 'act-901',
        'activo_asignado_sku': 'MOT-9001-A1',
        'id_orden': null,
      };

      final item = BackorderItemModel.fromJson(json);

      expect(item.idReserva, 'res-001');
      expect(item.folio, 'RES-5401');
      expect(item.fechaCreacion, 'Hoy 10:15');
      expect(item.clienteNombre, 'Marcelo Gómez T.');
      expect(item.vendedorNombre, 'Gastón Zamora');
      expect(item.idSucursal, 1);
      expect(item.idCategoriaRequerida, 1);
      expect(item.marcaRequerida, 'Mitsubishi');
      expect(item.modeloRequerido, 'L200 Dakar');
      expect(item.anioRequerido, 2021);
      expect(item.precioAcordado, 2100000);
      expect(item.montoAbonado, 500000);
      expect(item.saldoPendiente, 1600000);
      expect(item.estadoReserva, 'Confirmada');
      expect(item.idActivoAsignado, 'act-901');
      expect(item.activoAsignadoSku, 'MOT-9001-A1');
    });

    test('BackordersKpisModel deserializa correctamente métricas ejecutivas', () {
      final json = {
        'total_activos': 12,
        'capital_retenido': 4800000,
        'listos_para_liquidar': 3,
        'total_registrados': 28,
        'total_recaudado_senas': 9500000,
      };

      final kpis = BackordersKpisModel.fromJson(json);

      expect(kpis.totalActivos, 12);
      expect(kpis.capitalRetenido, 4800000);
      expect(kpis.listosParaLiquidar, 3);
      expect(kpis.totalRegistrados, 28);
      expect(kpis.totalRecaudadoSenas, 9500000);
    });

    test('PaginatedBackordersResponse deserializa items y totales', () {
      final json = {
        'total_count': 1,
        'total_recaudado_senas': 350000,
        'items': [
          {
            'id_reserva': 'res-002',
            'folio': 'RES-5402',
            'fecha_creacion': 'Ayer 15:30',
            'fecha_creacion_iso': '2026-09-07T15:30:00Z',
            'id_cliente': 'cli-102',
            'cliente_nombre': 'Flotas del Puerto S.A.',
            'id_vendedor': 'usr-202',
            'vendedor_nombre': 'Ignacio Vendedor',
            'id_sucursal': 2,
            'sucursal_nombre': 'Patio Desarme (Limache)',
            'id_categoria_requerida': 2,
            'categoria_nombre': 'Caja de Cambios',
            'marca_requerida': 'Toyota',
            'modelo_requerido': 'Hilux',
            'anio_requerido': 2019,
            'precio_acordado': 980000,
            'monto_abonado': 350000,
            'saldo_pendiente': 630000,
            'estado_reserva': 'Confirmada',
          }
        ],
      };

      final res = PaginatedBackordersResponse.fromJson(json);
      expect(res.totalCount, 1);
      expect(res.totalRecaudadoSenas, 350000);
      expect(res.items.length, 1);
      expect(res.items.first.folio, 'RES-5402');
      expect(res.items.first.idCategoriaRequerida, 2);
    });
  });

  group('HU-5.4: Componente BackordersGerenciaView', () {
    testWidgets('Renderiza 3 tarjetas KPI, buscador y filtros en estado inicial', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BackordersGerenciaView(
              idSucursalInicial: null,
            ),
          ),
        ),
      );

      // Esperar primer frame
      await tester.pump();

      // Verificamos presencia de las 3 tarjetas KPI
      expect(find.byType(KpiCardWidget), findsNWidgets(3));
      expect(find.text('TOTAL VENTAS EN VERDE ACTIVAS'), findsOneWidget);
      expect(find.text('CAPITAL RETENIDO EN ABONOS'), findsOneWidget);
      expect(find.text('LISTOS PARA LIQUIDAR'), findsOneWidget);

      // Verificamos presencia del input de búsqueda con su placeholder
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Buscar por Marca, Modelo, Cliente o Vendedor...'), findsOneWidget);

      // Verificamos presencia del selector de estado y botón Limpiar
      expect(find.text('Estado: Todos'), findsOneWidget);
      expect(find.text('Limpiar'), findsOneWidget);

      // En la carga inicial se muestra el indicador de carga
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
