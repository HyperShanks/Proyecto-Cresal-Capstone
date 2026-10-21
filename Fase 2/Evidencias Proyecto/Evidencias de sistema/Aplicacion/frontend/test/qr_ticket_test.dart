// test/qr_ticket_test.dart
// Suite de pruebas automatizadas para HU-3.6 (Fase 2): Frontend Vendedor - Visualizador del Ticket Digital QR.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:frontend/features/ventas/services/ordenes_service.dart';
import 'package:frontend/features/ventas/presentation/widgets/qr_ticket_dialog.dart';
import 'package:frontend/features/ventas/presentation/widgets/orden_card.dart';
import 'package:frontend/features/ventas/presentation/widgets/orden_detail_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'read') {
          return 'fake-test-jwt-token';
        }
        return null;
      },
    );
  });

  final ordenPagadaMock = OrdenHistorialModel(
    idOrden: '3fa85f64-5717-4562-b3fc-2c963f66afa6',
    estadoOrden: 'Pagada',
    totalVenta: 450000,
    montoPendiente: 0,
    qrTransaccionalSalida: 'TX-QR-3FA85F64-ABC123DEF456',
    fechaCreacion: '2026-08-14T15:30:00',
    totalItems: 1,
    cliente: const ClienteOrdenResumenModel(
      rutCliente: '19.876.543-2',
      nombres: 'Pedro',
      apellidos: 'Pascal',
      telefono: '+56999887766',
      correo: 'pedro@correo.cl',
      comuna: 'Viña del Mar',
    ),
    detalles: [
      DetalleOrdenItemModel(
        idDetalle: 'det-001',
        idActivo: 'act-001',
        titulo: 'Motor - Hyundai Accent 2020',
        skuQrFisico: 'MOT-HYU-ACC-001',
        notasPreparacion: 'Revisar compresión',
        cantidad: 1,
        precioUnitario: 450000,
        precioFinal: 450000,
        subtotal: 450000,
        esInventariado: true,
      ),
    ],
  );

  final ordenReservadaMock = OrdenHistorialModel(
    idOrden: '11111111-2222-3333-4444-555555555555',
    estadoOrden: 'Reservada',
    totalVenta: 300000,
    montoPendiente: 300000,
    qrTransaccionalSalida: null,
    fechaCreacion: '2026-08-14T16:00:00',
    totalItems: 1,
    cliente: const ClienteOrdenResumenModel(
      rutCliente: '12.345.678-9',
      nombres: 'Juan',
      apellidos: 'Pérez',
    ),
    detalles: [],
  );

  // ===========================================================================
  // 1. PRUEBAS UNITARIAS DE MODELO Y SERVICIO (HU-3.6)
  // ===========================================================================
  group('HU-3.6 Model & Service Tests', () {
    test('OrdenHistorialModel.tieneQrDisponible evalúa correctamente según estado y token', () {
      expect(ordenPagadaMock.tieneQrDisponible, isTrue);

      // Si es reservada, aunque tenga token no debe estar disponible para entrega
      final ordenReservadaConToken = ordenPagadaMock.copyWith(estadoOrden: 'Reservada');
      expect(ordenReservadaConToken.tieneQrDisponible, isFalse);

      // Si es pagada pero token es null o vacío
      final ordenPagadaSinToken = ordenPagadaMock.copyWith(qrTransaccionalSalida: null);
      expect(ordenPagadaSinToken.tieneQrDisponible, isFalse);

      final ordenPagadaTokenVacio = ordenPagadaMock.copyWith(qrTransaccionalSalida: '   ');
      expect(ordenPagadaTokenVacio.tieneQrDisponible, isFalse);
    });

    test('OrdenHistorialModel con estado Completada evalúa esCompletada=true, esPagada=false y tieneQrDisponible=false', () {
      final ordenCompletada = ordenPagadaMock.copyWith(estadoOrden: 'Completada');
      expect(ordenCompletada.esCompletada, isTrue);
      expect(ordenCompletada.esPagada, isFalse);
      expect(ordenCompletada.tieneQrDisponible, isFalse);
    });

    test('OrdenResponseModel.tieneQrDisponible evalúa correctamente', () {
      const respPagada = OrdenResponseModel(
        idOrden: 'ord-01',
        estadoOrden: 'Pagada',
        totalVenta: 100000,
        montoPendiente: 0,
        qrTransaccionalSalida: 'TX-QR-ORD01-TOKEN',
        mensaje: 'Ok',
        totalItems: 1,
      );
      expect(respPagada.tieneQrDisponible, isTrue);

      const respReservada = OrdenResponseModel(
        idOrden: 'ord-02',
        estadoOrden: 'Reservada',
        totalVenta: 100000,
        montoPendiente: 100000,
        qrTransaccionalSalida: null,
        mensaje: 'Ok',
        totalItems: 1,
      );
      expect(respReservada.tieneQrDisponible, isFalse);
    });

    test('OrdenHistorialModel.copyWith copia propiedades correctamente', () {
      final clonada = ordenReservadaMock.copyWith(
        estadoOrden: 'Pagada',
        montoPendiente: 0,
        qrTransaccionalSalida: 'TX-QR-NEW-123',
      );

      expect(clonada.idOrden, equals(ordenReservadaMock.idOrden));
      expect(clonada.estadoOrden, equals('Pagada'));
      expect(clonada.montoPendiente, equals(0));
      expect(clonada.qrTransaccionalSalida, equals('TX-QR-NEW-123'));
      expect(clonada.tieneQrDisponible, isTrue);
    });

    test('OrdenesService.pagarOrden ejecuta POST exitosamente y retorna OrdenPagoResponseModel', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(request.url.path, contains('/pagar'));
        expect(request.headers['Authorization'], equals('Bearer fake-test-jwt-token'));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['metodo_pago'], equals('Efectivo'));

        return http.Response(
          jsonEncode({
            'id_orden': '3fa85f64-5717-4562-b3fc-2c963f66afa6',
            'id_pago': 'pago-uuid-123',
            'estado_orden': 'Pagada',
            'total_venta': 450000,
            'monto_pagado': 450000,
            'monto_pendiente': 0,
            'metodo_pago': 'Efectivo',
            'qr_transaccional_salida': 'TX-QR-3FA85F64-ABC123DEF456',
            'id_cajera': 'cajera-uuid-001',
            'mensaje': 'Pago registrado exitosamente.',
            'fecha_pago': '2026-08-14T15:35:00',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final resp = await OrdenesService.pagarOrden(
        '3fa85f64-5717-4562-b3fc-2c963f66afa6',
        metodoPago: 'Efectivo',
        client: mockClient,
      );

      expect(resp.idOrden, equals('3fa85f64-5717-4562-b3fc-2c963f66afa6'));
      expect(resp.estadoOrden, equals('Pagada'));
      expect(resp.montoPendiente, equals(0));
      expect(resp.qrTransaccionalSalida, equals('TX-QR-3FA85F64-ABC123DEF456'));
    });
  });

  // ===========================================================================
  // 2. PRUEBAS DE WIDGET: QrTicketDialog (HU-3.6)
  // ===========================================================================
  group('QrTicketDialog Widget Tests', () {
    testWidgets('Renderiza correctamente el diálogo con QrImageView y datos de cliente', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => QrTicketDialog.mostrar(context, ordenPagadaMock),
                child: const Text('Abrir QR'),
              ),
            ),
          ),
        ),
      );

      // Abrir el diálogo
      await tester.tap(find.text('Abrir QR'));
      await tester.pumpAndSettle();

      // Validar elementos clave en el Ticket Digital
      expect(find.text('TICKET DE SALIDA'), findsOneWidget);
      expect(find.text('PAGO CONFIRMADO EN CAJA'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('ORD-3FA85F64'), findsOneWidget);
      expect(find.text('TX-QR-3FA85F64-ABC123DEF456'), findsOneWidget);
      expect(find.text('Pedro Pascal'), findsOneWidget);
      expect(find.text('19.876.543-2'), findsOneWidget);
      expect(find.text('\$450.000'), findsOneWidget);
      // Cerrar el diálogo usando el botón de cerrar en el encabezado
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('TICKET DE SALIDA'), findsNothing);
    });

    testWidgets('Bloquea visualmente el QR si la orden está Reservada y muestra aviso de pago pendiente', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => QrTicketDialog.mostrar(context, ordenReservadaMock),
                child: const Text('Abrir QR Reservada'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir QR Reservada'));
      await tester.pumpAndSettle();

      // No debe existir QrImageView
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('TICKET BLOQUEADO'), findsOneWidget);
      expect(find.text('ORDEN RESERVADA - PAGO PENDIENTE'), findsOneWidget);
      expect(find.text('CÓDIGO QR BLOQUEADO'), findsOneWidget);
      expect(find.textContaining('Saldo pendiente:'), findsOneWidget);
      expect(find.text('\$300.000'), findsWidgets);

      // Cerrar con botón cerrar del header
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('TICKET BLOQUEADO'), findsNothing);
    });

    testWidgets('Muestra estado Sin Retiro PDA si la orden está Pagada pero no tiene activos inventariados', (tester) async {
      final ordenServiciosPagada = ordenPagadaMock.copyWith(qrTransaccionalSalida: null);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => QrTicketDialog.mostrar(context, ordenServiciosPagada),
                child: const Text('Abrir QR Servicios'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir QR Servicios'));
      await tester.pumpAndSettle();

      // No debe existir QrImageView
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('COMPROBANTE DE VENTA'), findsOneWidget);
      expect(find.text('PAGO CONFIRMADO - SIN RETIRO PDA'), findsOneWidget);
      expect(find.text('SIN RETIRO FÍSICO PDA'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('COMPROBANTE DE VENTA'), findsNothing);
    });
  });

  // ===========================================================================
  // 3. PRUEBAS DE WIDGET: OrdenDetailSheet (HU-3.6)
  // ===========================================================================
  group('OrdenDetailSheet QR Actions Tests', () {
    testWidgets('Muestra banner y botón de QR cuando la orden está Pagada', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrdenDetailSheet(orden: ordenPagadaMock),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Ticket Digital Emitido'), findsOneWidget);
      expect(find.text('MOSTRAR QR DE ENTREGA (BODEGA)'), findsOneWidget);
      // No debe mostrar botón de simular pago ni de anular
      expect(find.text('💳 Simular Pago en Caja (Demo)'), findsNothing);
      expect(find.text('Deshacer Orden (Liberar Stock)'), findsNothing);

      // Al presionar el botón debe abrir el Ticket Digital QR
      await tester.ensureVisible(find.text('MOSTRAR QR DE ENTREGA (BODEGA)'));
      await tester.tap(find.text('MOSTRAR QR DE ENTREGA (BODEGA)'));
      await tester.pumpAndSettle();

      expect(find.byType(QrTicketDialog), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('Muestra acciones de gestión cuando la orden está Reservada', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrdenDetailSheet(orden: ordenReservadaMock),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Acciones de Gestión'), findsOneWidget);
      expect(find.text('Editar Instrucciones a Bodega'), findsOneWidget);
      expect(find.text('Deshacer Orden (Liberar Stock)'), findsOneWidget);
      // No debe mostrar botón de QR aún
      expect(find.text('MOSTRAR QR DE ENTREGA (BODEGA)'), findsNothing);
    });

    testWidgets('Muestra badge Completada y confirmación de entrega en barrera de bodega', (tester) async {
      final ordenCompletada = ordenPagadaMock.copyWith(estadoOrden: 'Completada');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrdenDetailSheet(orden: ordenCompletada),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Completada'), findsOneWidget);
      expect(find.text('Orden Completada'), findsOneWidget);
      expect(
        find.text('Los repuestos fueron validados y entregados exitosamente en barrera de bodega.'),
        findsOneWidget,
      );
      // No debe mostrar botón de QR ni de pago
      expect(find.text('MOSTRAR QR DE ENTREGA (BODEGA)'), findsNothing);
      expect(find.text('💳 Simular Pago en Caja (Demo)'), findsNothing);
    });
  });

  // ===========================================================================
  // 4. PRUEBAS DE WIDGET: OrdenCard (HU-3.6)
  // ===========================================================================
  group('OrdenCard Quick QR Button Tests', () {
    testWidgets('Muestra botón rápido "Ver QR" solo cuando la orden tiene QR disponible', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                OrdenCard(orden: ordenPagadaMock),
                OrdenCard(orden: ordenReservadaMock),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Debe haber exactamente 1 botón 'Ver QR' (correspondiente a la orden pagada)
      expect(find.text('Ver QR'), findsOneWidget);

      // Al presionar el botón 'Ver QR' debe abrir directamente el QrTicketDialog
      await tester.tap(find.text('Ver QR'));
      await tester.pumpAndSettle();

      expect(find.byType(QrTicketDialog), findsOneWidget);
      expect(find.text('PAGO CONFIRMADO EN CAJA'), findsOneWidget);
    });

    testWidgets('Orden con estado Completada muestra badge Completada y oculta botón Ver QR', (tester) async {
      final ordenCompletada = ordenPagadaMock.copyWith(estadoOrden: 'Completada');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrdenCard(orden: ordenCompletada),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Completada'), findsOneWidget);
      expect(find.text('Ver QR'), findsNothing);
    });
  });
}
