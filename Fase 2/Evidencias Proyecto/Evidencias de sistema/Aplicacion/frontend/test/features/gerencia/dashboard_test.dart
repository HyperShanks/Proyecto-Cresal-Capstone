// frontend/test/features/gerencia/dashboard_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/gerencia/models/gerencia_models.dart';
import 'package:frontend/features/gerencia/presentation/screens/dashboard_gerencia_view.dart';
import 'package:frontend/features/gerencia/presentation/widgets/kpi_card_widget.dart';
import 'package:frontend/features/gerencia/presentation/widgets/metodos_pago_chart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'mock-valid-token',
      'user_rol': 'Gerente General',
      'user_id_rol': '4',
      'user_sucursal_id': '1',
      'user_sucursal_nombre': 'Casa Matriz (Viña)',
      'user_nombre_completo': 'Roberto Silva',
    });
  });

  group('1. Modelos de Datos de Gerencia (Unit Tests)', () {
    test('KpiFinancieroModel deserializa correctamente desde JSON', () {
      final jsonMap = {
        'ventas_del_dia': 1850000,
        'transacciones_hoy': 5,
        'acumulado_mensual_mtd': 42500000,
        'ticket_promedio': 370000.0,
        'margen_bruto': 64.8,
      };

      final model = KpiFinancieroModel.fromJson(jsonMap);

      expect(model.ventasDelDia, 1850000);
      expect(model.transaccionesHoy, 5);
      expect(model.acumuladoMensualMtd, 42500000);
      expect(model.ticketPromedio, 370000.0);
      expect(model.margenBruto, 64.8);
      expect(model.toJson()['ventas_del_dia'], 1850000);
    });

    test('ResumenPagosModel calcula totalRecaudado y deserializa desglose', () {
      final jsonMap = {
        'efectivo_fisico': 750000,
        'canales_electronicos': 2450000,
        'desglose': [
          {
            'metodo_pago': 'Transferencia',
            'monto_total': 1850000,
            'porcentaje': 57.8,
          },
          {
            'metodo_pago': 'Débito',
            'monto_total': 600000,
            'porcentaje': 18.75,
          },
          {
            'metodo_pago': 'Efectivo',
            'monto_total': 750000,
            'porcentaje': 23.45,
          },
        ],
      };

      final model = ResumenPagosModel.fromJson(jsonMap);

      expect(model.efectivoFisico, 750000);
      expect(model.canalesElectronicos, 2450000);
      expect(model.totalRecaudado, 3200000);
      expect(model.desglose.length, 3);
      expect(model.desglose.first.metodoPago, 'Transferencia');
    });

    test('FlujoOperativoModel mapea correctamente las 5 etapas operativas', () {
      final jsonMap = {
        'en_preparacion': 3,
        'listos_mostrador': 2,
        'enviados_courier': 4,
        'alertas_saldo_pendiente': 1,
        'cuellos_botella_paletizados': 2,
      };

      final model = FlujoOperativoModel.fromJson(jsonMap);

      expect(model.enPreparacion, 3);
      expect(model.listosMostrador, 2);
      expect(model.enviadosCourier, 4);
      expect(model.alertasSaldoPendiente, 1);
      expect(model.cuellosBotellaPaletizados, 2);
    });
  });

  group('2. KpiCardWidget (Widget Tests)', () {
    testWidgets('Renderiza título, valor formateado, badge y subtítulo',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: KpiCardWidget(
              titulo: 'Facturación Hoy',
              valor: '\$ 1.850.000',
              badgeTexto: '+14.2%',
              badgeColor: Colors.green,
              subtitulo: 'Meta Diaria: \$5.0M',
              icono: Icons.payments,
            ),
          ),
        ),
      );

      expect(find.text('FACTURACIÓN HOY'), findsOneWidget);
      expect(find.text('\$ 1.850.000'), findsOneWidget);
      expect(find.text('+14.2%'), findsOneWidget);
      expect(find.text('Meta Diaria: \$5.0M'), findsOneWidget);
      expect(find.byIcon(Icons.payments), findsOneWidget);
    });
  });

  group('3. MetodosPagoChart (Widget Tests)', () {
    testWidgets('Muestra estado vacío cuando total recaudado es 0',
        (tester) async {
      const resumenVacio = ResumenPagosModel(
        efectivoFisico: 0,
        canalesElectronicos: 0,
        desglose: [],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              width: 500,
              child: MetodosPagoChart(resumen: resumenVacio),
            ),
          ),
        ),
      );

      expect(find.text('Medios de Pago'), findsOneWidget);
      expect(find.text('Sin pagos registrados hoy'), findsOneWidget);
    });

    testWidgets('Muestra gráfico, toggle y conciliación cuando existen pagos',
        (tester) async {
      const resumenConData = ResumenPagosModel(
        efectivoFisico: 300000,
        canalesElectronicos: 700000,
        totalTransacciones: 2,
        desglose: [
          DesglosePagoModel(
            metodoPago: 'Débito',
            montoTotal: 700000,
            porcentaje: 70.0,
            cantidad: 1,
            porcentajeCantidad: 50.0,
          ),
          DesglosePagoModel(
            metodoPago: 'Efectivo',
            montoTotal: 300000,
            porcentaje: 30.0,
            cantidad: 1,
            porcentajeCantidad: 50.0,
          ),
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              width: 600,
              child: MetodosPagoChart(resumen: resumenConData),
            ),
          ),
        ),
      );

      expect(find.text('Medios de Pago'), findsOneWidget);
      expect(find.text(r'$ Monto'), findsOneWidget);
      expect(find.text('# Cant'), findsOneWidget);
      expect(find.text('Transbank & Webpay'), findsNothing);
      expect(find.text('Conciliado'), findsNothing);
      expect(find.text('Débito'), findsOneWidget);
      expect(find.text('Efectivo'), findsOneWidget);
      expect(find.text('70%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);

      // Probamos alternar al modo cantidad # Cant
      await tester.tap(find.text('# Cant'));
      await tester.pumpAndSettle();
      expect(find.text('2 uds'), findsOneWidget);
      expect(find.text('1 uds'), findsNWidgets(2));
      expect(find.text('70%'), findsNothing);
      expect(find.text('30%'), findsNothing);
    });
  });

  group('4. DashboardGerenciaView (Integración y Resiliencia de Red)', () {
    testWidgets(
        'Renderiza estado de error y botón Reintentar si falla la consulta',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: DashboardGerenciaView(),
        ),
      );

      // Avanzamos el reloj para resolver la petición asíncrona que falla por timeout
      await tester.pump();
      await tester.pump(const Duration(seconds: 13));

      // Verificamos presencia de componentes de la vista
      expect(find.text('CRESAL GERENCIA'), findsOneWidget);
      expect(find.text('Actualizar'), findsOneWidget);
      expect(find.text('Reintentar'), findsWidgets);
    });

    testWidgets('Renderiza Topbar con selector de sucursal y branding oficial',
        (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DashboardGerenciaView(sucursalInicial: 1),
          ),
        ),
      );

      await tester.pump();

      expect(find.text('CRESAL GERENCIA'), findsOneWidget);
      expect(find.text('Dashboard Ejecutivo y Pulso Operativo'), findsOneWidget);
      expect(find.text('Viña del Mar (Casa Matriz)'), findsOneWidget);
      expect(find.text('Actualizar'), findsOneWidget);
    });
  });
}
