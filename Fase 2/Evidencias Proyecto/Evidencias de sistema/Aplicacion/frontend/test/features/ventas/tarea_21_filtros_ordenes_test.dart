import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/tokens/app_palette.dart';
import 'package:frontend/features/ventas/presentation/screens/historial_screen.dart';
import 'package:frontend/features/ventas/presentation/widgets/historial_filtros_drawer.dart';
import 'package:frontend/features/ventas/presentation/widgets/orden_card.dart';
import 'package:frontend/features/ventas/services/ordenes_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SPEC-HU-TAREA-21: Modelo OrdenHistorialModel', () {
    test('esVentaEnVerde detecta ventas en verde por título, descripción o folio RES-', () {
      final ordenVerdeTitulo = OrdenHistorialModel(
        idOrden: 'ord-v1',
        folio: 'ORD-0001',
        estadoOrden: 'Reservada',
        totalVenta: 100000,
        montoPendiente: 70000,
        totalItems: 1,
        detalles: [
          DetalleOrdenItemModel(
            idDetalle: 'd-1',
            titulo: 'Culata Venta en Verde',
            cantidad: 1,
            precioFinal: 100000,
            subtotal: 100000,
            esInventariado: false,
          ),
        ],
      );
      expect(ordenVerdeTitulo.esVentaEnVerde, isTrue);

      final ordenVerdeDesc = OrdenHistorialModel(
        idOrden: 'ord-v2',
        folio: 'ORD-0002',
        estadoOrden: 'Reservada',
        totalVenta: 50000,
        montoPendiente: 35000,
        totalItems: 1,
        detalles: [
          DetalleOrdenItemModel(
            idDetalle: 'd-2',
            titulo: 'Puerta Derecha',
            descripcionManual: 'Reserva en Verde desde bodega',
            cantidad: 1,
            precioFinal: 50000,
            subtotal: 50000,
            esInventariado: false,
          ),
        ],
      );
      expect(ordenVerdeDesc.esVentaEnVerde, isTrue);

      final ordenVerdeFolio = OrdenHistorialModel(
        idOrden: 'ord-v3',
        folio: 'RES-8821',
        estadoOrden: 'Reservada',
        totalVenta: 80000,
        montoPendiente: 56000,
        totalItems: 1,
        detalles: [
          DetalleOrdenItemModel(
            idDetalle: 'd-3',
            titulo: 'Capó',
            cantidad: 1,
            precioFinal: 80000,
            subtotal: 80000,
            esInventariado: false,
          ),
        ],
      );
      expect(ordenVerdeFolio.esVentaEnVerde, isTrue);

      final ordenNormal = OrdenHistorialModel(
        idOrden: 'ord-norm',
        folio: 'ORD-0004',
        estadoOrden: 'Reservada',
        totalVenta: 30000,
        montoPendiente: 30000,
        totalItems: 1,
        detalles: [
          DetalleOrdenItemModel(
            idDetalle: 'd-4',
            titulo: 'Alternador Corsa',
            cantidad: 1,
            precioFinal: 30000,
            subtotal: 30000,
            esInventariado: true,
          ),
        ],
      );
      expect(ordenNormal.esVentaEnVerde, isFalse);
    });

    test('esAbonada evalúa correctamente pagos parciales con saldo pendiente', () {
      final ordenConAbono = OrdenHistorialModel(
        idOrden: 'ord-abono',
        estadoOrden: 'Reservada',
        totalVenta: 100000,
        montoPendiente: 40000, // Se abonaron 60.000
        totalItems: 1,
        detalles: [],
      );
      expect(ordenConAbono.esAbonada, isTrue);

      final ordenSinAbono = OrdenHistorialModel(
        idOrden: 'ord-cero',
        estadoOrden: 'Reservada',
        totalVenta: 100000,
        montoPendiente: 100000, // No se ha abonado nada
        totalItems: 1,
        detalles: [],
      );
      expect(ordenSinAbono.esAbonada, isFalse);

      final ordenTotalmentePagada = OrdenHistorialModel(
        idOrden: 'ord-pagada',
        estadoOrden: 'Pagada',
        totalVenta: 100000,
        montoPendiente: 0,
        totalItems: 1,
        detalles: [],
      );
      expect(ordenTotalmentePagada.esAbonada, isFalse);
    });
  });

  group('SPEC-HU-TAREA-21: OrdenCard Badges Semánticos', () {
    testWidgets('Venta en verde renderiza badge "Venta en Verde" con icono eco', (tester) async {
      final ordenVerde = OrdenHistorialModel(
        idOrden: 'ord-verde',
        folio: 'RES-0001',
        estadoOrden: 'Reservada',
        totalVenta: 80000,
        montoPendiente: 50000,
        totalItems: 1,
        detalles: [
          DetalleOrdenItemModel(
            idDetalle: 'd-1',
            titulo: 'Parachoques Venta en Verde',
            cantidad: 1,
            precioFinal: 80000,
            subtotal: 80000,
            esInventariado: false,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrdenCard(orden: ordenVerde),
          ),
        ),
      );

      expect(find.text('Venta en Verde'), findsOneWidget);
      expect(find.byIcon(Icons.eco_outlined), findsOneWidget);
      expect(find.text('Reservada'), findsNothing);
    });

    testWidgets('Venta normal reservada renderiza badge "Abonado" con icono de billetera', (tester) async {
      final ordenNormal = OrdenHistorialModel(
        idOrden: 'ord-normal',
        folio: 'ORD-0002',
        estadoOrden: 'Reservada',
        totalVenta: 120000,
        montoPendiente: 60000,
        totalItems: 1,
        detalles: [
          DetalleOrdenItemModel(
            idDetalle: 'd-2',
            titulo: 'Compresor Aire Acondicionado',
            cantidad: 1,
            precioFinal: 120000,
            subtotal: 120000,
            esInventariado: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrdenCard(orden: ordenNormal),
          ),
        ),
      );

      expect(find.text('Abonado'), findsOneWidget);
      expect(find.byIcon(Icons.account_balance_wallet_outlined), findsOneWidget);
      expect(find.text('Reservada'), findsNothing);
    });
  });

  group('SPEC-HU-TAREA-21: HistorialScreen Filtros Avanzados', () {
    final ordenAbonada = OrdenHistorialModel(
      idOrden: 'ord-1-abono',
      folio: 'ORD-001',
      estadoOrden: 'Reservada',
      totalVenta: 100000,
      montoPendiente: 40000,
      fechaCreacion: '2026-09-10T11:00:00',
      totalItems: 1,
      detalles: [
        DetalleOrdenItemModel(
          idDetalle: 'd-1',
          titulo: 'Amortiguador Delantero',
          cantidad: 1,
          precioFinal: 100000,
          subtotal: 100000,
          esInventariado: true,
        ),
      ],
    );

    final ordenSinAbono = OrdenHistorialModel(
      idOrden: 'ord-2-cero',
      folio: 'ORD-002',
      estadoOrden: 'Reservada',
      totalVenta: 50000,
      montoPendiente: 50000,
      fechaCreacion: '2026-09-12T15:30:00',
      totalItems: 1,
      detalles: [
        DetalleOrdenItemModel(
          idDetalle: 'd-2',
          titulo: 'Radiador',
          cantidad: 1,
          precioFinal: 50000,
          subtotal: 50000,
          esInventariado: true,
        ),
      ],
    );

    final ordenAgosto = OrdenHistorialModel(
      idOrden: 'ord-3-agosto',
      folio: 'ORD-003',
      estadoOrden: 'Pagada',
      totalVenta: 200000,
      montoPendiente: 0,
      fechaCreacion: '2026-08-20T10:00:00',
      totalItems: 1,
      detalles: [
        DetalleOrdenItemModel(
          idDetalle: 'd-3',
          titulo: 'Caja de Cambios',
          cantidad: 1,
          precioFinal: 200000,
          subtotal: 200000,
          esInventariado: true,
        ),
      ],
    );

    testWidgets('Filtro rápido "Abonados" filtra solo órdenes con pago parcial', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HistorialScreen(
            initialOrdenes: [ordenAbonada, ordenSinAbono, ordenAgosto],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Abonados'), findsOneWidget);

      // Activar chip "Abonados"
      await tester.tap(find.text('Abonados'));
      await tester.pumpAndSettle();

      // Solo debe aparecer la orden con abono (ORD-001)
      expect(find.text('ORD-001'), findsOneWidget);
      expect(find.text('ORD-002'), findsNothing);
      expect(find.text('ORD-003'), findsNothing);
    });

    testWidgets('Limpiar filtros restablece filtros y vuelve a mostrar órdenes activas', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HistorialScreen(
            initialOrdenes: [ordenAbonada, ordenSinAbono],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Filtrar por un estado que no tenga órdenes para activar el empty state con botón
      await tester.ensureVisible(find.text('Solo Anuladas'));
      await tester.tap(find.text('Solo Anuladas'));
      await tester.pumpAndSettle();

      expect(find.text('Limpiar Filtros'), findsOneWidget);

      // Tocar Limpiar Filtros
      await tester.tap(find.text('Limpiar Filtros'));
      await tester.pumpAndSettle();

      // Vuelven a mostrarse las órdenes activas
      expect(find.text('ORD-001'), findsOneWidget);
      expect(find.text('ORD-002'), findsOneWidget);
    });

    testWidgets('Chips rápidos: Reservadas y Abonados buscan en Historial Completo, y Pagadas/Activas buscan en Ventas de Hoy', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HistorialScreen(
            initialOrdenes: [ordenAbonada, ordenSinAbono, ordenAgosto],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Estado inicial: Ventas del día (Hoy)
      expect(find.text('Ventas del día (Hoy)'), findsOneWidget);

      // 1. Tocar Reservadas -> activa Historial Completo automáticamente
      await tester.tap(find.text('Reservadas'));
      await tester.pumpAndSettle();
      expect(find.text('Filtro: Reservada (Historial)'), findsOneWidget);

      // 2. Tocar Abonados -> activa Historial Completo automáticamente
      await tester.tap(find.text('Abonados'));
      await tester.pumpAndSettle();
      expect(find.text('Filtro: Abonado (Historial)'), findsOneWidget);

      // 3. Tocar Pagadas -> vuelve a Ventas de Hoy
      await tester.tap(find.text('Pagadas'));
      await tester.pumpAndSettle();
      expect(find.text('Filtro: Pagada (Hoy)'), findsOneWidget);

      // 4. Tocar Activas -> vuelve a Ventas del día (Hoy)
      await tester.tap(find.text('Activas'));
      await tester.pumpAndSettle();
      expect(find.text('Ventas del día (Hoy)'), findsOneWidget);
    });

    testWidgets('HistorialFiltrosDrawer incluye selector dinámico de mes y chip Abonados', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HistorialScreen(
            initialOrdenes: [ordenAbonada, ordenAgosto],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Abrir EndDrawer con botón tune
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(HistorialFiltrosDrawer),
          matching: find.text('Abonados'),
        ),
        findsOneWidget,
      );

      // Abrir dropdown de mes y verificar que los meses están disponibles
      await tester.tap(find.byKey(const Key('dropdown_mes_historial')));
      await tester.pumpAndSettle();

      expect(find.text('Septiembre'), findsWidgets);
      expect(find.text('Agosto'), findsWidgets);

      // Seleccionar Agosto
      await tester.tap(find.text('Agosto').last);
      await tester.pumpAndSettle();

      // Aplicar filtros
      await tester.tap(find.text('Aplicar Filtros'));
      await tester.pumpAndSettle();

      // En la lista principal ahora solo debe estar la orden de Agosto (ORD-003)
      expect(find.text('ORD-003'), findsOneWidget);
      expect(find.text('ORD-001'), findsNothing);
    });
  });
}
