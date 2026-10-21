import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/ventas/presentation/widgets/orden_card.dart';
import 'package:frontend/features/ventas/presentation/widgets/orden_detail_sheet.dart';
import 'package:frontend/features/ventas/services/ordenes_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TAREA-24: Venta Referida Limache - Modelos', () {
    test('OrdenHistorialModel deserializa es_asignada_limache correctamente', () {
      final json = {
        'id_orden': '3fa85f64-5717-4562-b3fc-2c963f66afa6',
        'numero_orden': 105,
        'folio': 'ORD-0105',
        'estado_orden': 'Reservada',
        'total_venta': 120000,
        'monto_pendiente': 120000,
        'total_items': 1,
        'id_vendedor_asignado': '8bb974bf-4dc7-4b8a-b9c6-111111111111',
        'es_asignada_limache': true,
        'detalles': [],
      };

      final model = OrdenHistorialModel.fromJson(json);
      expect(model.esAsignadaLimache, isTrue);
      expect(model.idVendedorAsignado, equals('8bb974bf-4dc7-4b8a-b9c6-111111111111'));

      final jsonDefault = {
        'id_orden': '3fa85f64-5717-4562-b3fc-2c963f66afa7',
        'numero_orden': 106,
        'folio': 'ORD-0106',
        'estado_orden': 'Pagada',
        'total_venta': 50000,
        'monto_pendiente': 0,
        'total_items': 1,
        'detalles': [],
      };

      final modelDefault = OrdenHistorialModel.fromJson(jsonDefault);
      expect(modelDefault.esAsignadaLimache, isFalse);
    });

    test('VendedorModel identifica al usuario comercial Limache', () {
      const vendedorLimache = VendedorModel(
        idUsuario: 'limache-uuid',
        nombreCompleto: 'Ventas Limache',
        rut: '77.888.999-4',
        idSucursal: 2,
        correo: 'limache@cresal.cl',
        idRol: 2,
      );

      expect(vendedorLimache.esLimache, isTrue);
      expect(vendedorLimache.etiquetaRol, equals('Ventas Limache'));

      const vendedorComun = VendedorModel(
        idUsuario: 'juan-uuid',
        nombreCompleto: 'Juan Pérez',
        rut: '12.345.678-9',
        idSucursal: 1,
        correo: 'juan@cresal.cl',
        idRol: 2,
      );

      expect(vendedorComun.esLimache, isFalse);
      expect(vendedorComun.etiquetaRol, equals('Vendedor Mesón'));
    });
  });

  group('TAREA-24: Venta Referida Limache - Widgets', () {
    testWidgets('OrdenCard renderiza badge [📍 Asignada a Limache] cuando esAsignadaLimache es true', (tester) async {
      final ordenLimache = OrdenHistorialModel(
        idOrden: 'ord-limache-1',
        folio: 'ORD-5001',
        estadoOrden: 'Reservada',
        totalVenta: 150000,
        montoPendiente: 150000,
        totalItems: 1,
        esAsignadaLimache: true,
        detalles: [
          DetalleOrdenItemModel(
            idDetalle: 'd-1',
            titulo: 'Caja de Cambios Hyundai Accent',
            cantidad: 1,
            precioFinal: 150000,
            subtotal: 150000,
            esInventariado: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrdenCard(orden: ordenLimache),
          ),
        ),
      );

      expect(find.text('Asignada a Limache'), findsOneWidget);
      expect(find.text('📍'), findsOneWidget);
    });

    testWidgets('OrdenCard NO renderiza badge Limache en órdenes estándar', (tester) async {
      final ordenNormal = OrdenHistorialModel(
        idOrden: 'ord-normal-1',
        folio: 'ORD-5002',
        estadoOrden: 'Pagada',
        totalVenta: 80000,
        montoPendiente: 0,
        totalItems: 1,
        esAsignadaLimache: false,
        detalles: [
          DetalleOrdenItemModel(
            idDetalle: 'd-2',
            titulo: 'Alternador Toyota Yaris',
            cantidad: 1,
            precioFinal: 80000,
            subtotal: 80000,
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

      expect(find.text('Asignada a Limache'), findsNothing);
    });

    testWidgets('OrdenDetailSheet muestra banner explicativo de venta asignada a Limache', (tester) async {
      final ordenLimache = OrdenHistorialModel(
        idOrden: 'ord-limache-detail',
        folio: 'ORD-5003',
        estadoOrden: 'Reservada',
        totalVenta: 200000,
        montoPendiente: 200000,
        totalItems: 1,
        esAsignadaLimache: true,
        detalles: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrdenDetailSheet(orden: ordenLimache),
          ),
        ),
      );

      expect(find.text('Venta Asignada a Limache'), findsOneWidget);
      expect(
        find.textContaining('La comisión y métrica comercial están imputadas a Limache'),
        findsOneWidget,
      );
    });
  });
}
