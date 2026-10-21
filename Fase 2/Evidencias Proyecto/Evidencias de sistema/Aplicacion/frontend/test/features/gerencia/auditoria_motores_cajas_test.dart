// frontend/test/features/gerencia/auditoria_motores_cajas_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/caja/models/historial_caja_model.dart';
import 'package:frontend/features/gerencia/presentation/widgets/auditoria_tabla_view.dart';
import 'package:frontend/features/gerencia/presentation/widgets/auditoria_detalle_dialog.dart';

void main() {
  group('SPEC CRES-240: Clasificación y Detección Semántica de Motores y Cajas', () {
    test('1. Piezas Inventariadas: Genera badges con SKU real (MOT-XXXX / CAJ-XXXX) y vehículo origen', () {
      final artMotor = HistorialArticuloModel(
        cantidad: 1,
        tipo: 'INVENTARIADO',
        descripcion: 'Motor 2.0 HDI Diesel',
        sku: 'MOT-1001',
        precio: 850000,
        subtotal: 850000,
        categoria: 'Motores',
        marca: 'Peugeot',
        modelo: '3008',
        anio: 2019,
        detalleTecnico: '2.0 HDI 150cv',
      );

      final artCaja = HistorialArticuloModel(
        cantidad: 1,
        tipo: 'INVENTARIADO',
        descripcion: 'Caja de cambios mecánica 6ta',
        sku: 'CAJ-200',
        precio: 450000,
        subtotal: 450000,
        categoria: 'Cajas de Cambio',
        marca: 'Toyota',
        modelo: 'Hilux',
        anio: 2021,
      );

      final actMotor = artMotor.activoAuditado;
      expect(actMotor, isNotNull);
      expect(actMotor!.tipo, TipoActivoAuditoria.motorInventariado);
      expect(actMotor.label, 'MOT-1001');
      expect(actMotor.esInventariado, true);
      expect(actMotor.vehiculoOrigen, 'Peugeot 3008 2019 - 2.0 HDI 150cv');

      final actCaja = artCaja.activoAuditado;
      expect(actCaja, isNotNull);
      expect(actCaja!.tipo, TipoActivoAuditoria.cajaInventariada);
      expect(actCaja.label, 'CAJ-200');
      expect(actCaja.esInventariado, true);
      expect(actCaja.vehiculoOrigen, 'Toyota Hilux 2021');
    });

    test('2. Misceláneos Válidos: Despliega badges distintivos MOTOR y CAJA sin SKU', () {
      final miscMotor = HistorialArticuloModel(
        cantidad: 1,
        tipo: 'DESARME',
        descripcion: 'Motor armado Nissan Terrano 2.5 TD27',
        sku: null,
        precio: 700000,
        subtotal: 700000,
      );

      final miscCaja = HistorialArticuloModel(
        cantidad: 1,
        tipo: 'DESARME',
        descripcion: 'Transmisión automática 4x4 Mitsubishi Montero',
        sku: null,
        precio: 500000,
        subtotal: 500000,
      );

      final actMotor = miscMotor.activoAuditado;
      expect(actMotor, isNotNull);
      expect(actMotor!.tipo, TipoActivoAuditoria.motorMiscelaneo);
      expect(actMotor.label, 'MOTOR');
      expect(actMotor.esInventariado, false);

      final actCaja = miscCaja.activoAuditado;
      expect(actCaja, isNotNull);
      expect(actCaja!.tipo, TipoActivoAuditoria.cajaMiscelanea);
      expect(actCaja.label, 'CAJA');
      expect(actCaja.esInventariado, false);
    });

    test('3. Validación Negativa (Sin Falsos Positivos): Descarta accesorios y periféricos', () {
      final falsosMotores = [
        'Motor de cremallera electroasistida',
        'Motor de partida 12V',
        'Motor de arranque Chevrolet',
        'Motor limpia parabrisas delantero',
        'Motor limpiaparabrisas trasero',
        'Motor de alzavidrio puerta delantera izquierda',
        'Motor de calefacción / ventilador',
        'Motor electroventilador con aspas',
        'Motor de espejo lateral eléctrico',
        'Motor paso a paso ralentí',
      ];

      for (final desc in falsosMotores) {
        final art = HistorialArticuloModel(
          cantidad: 1,
          tipo: 'DESARME',
          descripcion: desc,
          sku: null,
          precio: 25000,
          subtotal: 25000,
        );
        expect(
          art.activoAuditado,
          isNull,
          reason: 'Descripción "$desc" no debe ser clasificada como motor ni caja',
        );
      }

      final falsasCajas = [
        'Caja de fusibles motor',
        'Caja de dirección hidráulica',
        'Caja filtro de aire completa',
        'Caja evaporadora aire acondicionado',
        'Caja de batería plástica',
        'Caja de termostato con sensor',
        'Caja de mariposa de aceleración',
      ];

      for (final desc in falsasCajas) {
        final art = HistorialArticuloModel(
          cantidad: 1,
          tipo: 'DESARME',
          descripcion: desc,
          sku: null,
          precio: 30000,
          subtotal: 30000,
        );
        expect(
          art.activoAuditado,
          isNull,
          reason: 'Descripción "$desc" no debe ser clasificada como caja de cambios',
        );
      }
    });

    test('4. HistorialOrdenItemModel: tieneMotorOCaja y activosAuditados reflejan coherencia', () {
      // Orden que solo contiene repuestos menores (falsos positivos)
      final ordenFalsa = HistorialOrdenItemModel(
        idOrden: 'ord-falsa',
        folio: 'ORD-001',
        tipoOperacion: 'Venta Mesón',
        emiteQr: true,
        fechaIso: '2026-10-12',
        hora: '14:30',
        fechaHoraFormateada: '14:30 - 12/10/2026',
        clienteNombre: 'Pedro Soto',
        vendedorNombre: 'Juan Vendedor',
        cajeraNombre: 'María Cajera',
        estadoOrden: 'Pagada',
        modalidadPago: 'Efectivo',
        metodosResumen: 'Efectivo',
        totalVenta: 70000,
        abonoPrevio: 0,
        totalLiquidado: 70000,
        desglosePagos: [],
        articulos: [
          HistorialArticuloModel(
            cantidad: 1,
            tipo: 'DESARME',
            descripcion: 'Motor de partida Nissan',
            precio: 35000,
            subtotal: 35000,
          ),
          HistorialArticuloModel(
            cantidad: 1,
            tipo: 'DESARME',
            descripcion: 'Caja de fusibles Toyota',
            precio: 35000,
            subtotal: 35000,
          ),
        ],
        historialMovimientos: [],
      );

      expect(ordenFalsa.tieneMotorOCaja, false);
      expect(ordenFalsa.activosAuditados, isEmpty);

      // Orden que contiene un motor inventariado legítimo
      final ordenLegitima = HistorialOrdenItemModel(
        idOrden: 'ord-legitima',
        folio: 'ORD-002',
        tipoOperacion: 'Venta Mesón',
        emiteQr: true,
        fechaIso: '2026-10-12',
        hora: '15:00',
        fechaHoraFormateada: '15:00 - 12/10/2026',
        clienteNombre: 'Ana Pérez',
        vendedorNombre: 'Juan Vendedor',
        cajeraNombre: 'María Cajera',
        estadoOrden: 'Pagada',
        modalidadPago: 'Efectivo',
        metodosResumen: 'Efectivo',
        totalVenta: 900000,
        abonoPrevio: 0,
        totalLiquidado: 900000,
        desglosePagos: [],
        articulos: [
          HistorialArticuloModel(
            cantidad: 1,
            tipo: 'INVENTARIADO',
            descripcion: 'Motor 1NZ 1.5 Completo',
            sku: 'MOT-550',
            categoria: 'Motores',
            marca: 'Toyota',
            modelo: 'Yaris',
            anio: 2018,
            precio: 900000,
            subtotal: 900000,
          ),
        ],
        historialMovimientos: [],
      );

      expect(ordenLegitima.tieneMotorOCaja, true);
      expect(ordenLegitima.activosAuditados.length, 1);
      expect(ordenLegitima.activosAuditados.first.label, 'MOT-550');
    });

    testWidgets('5. Widgets: AuditoriaTablaView renderiza el SKU real y no "Motor / Caja"', (tester) async {
      final ordenInventariada = HistorialOrdenItemModel(
        idOrden: 'ord-inv',
        folio: 'ORD-999',
        tipoOperacion: 'Venta Mesón',
        emiteQr: true,
        fechaIso: '2026-10-12',
        hora: '10:00',
        fechaHoraFormateada: '10:00 - 12/10/2026',
        clienteNombre: 'Carlos Gomez',
        vendedorNombre: 'Vendedor 1',
        cajeraNombre: 'Cajera 1',
        estadoOrden: 'Pagada',
        modalidadPago: 'Efectivo',
        metodosResumen: 'Efectivo',
        totalVenta: 1200000,
        abonoPrevio: 0,
        totalLiquidado: 1200000,
        desglosePagos: [],
        articulos: [
          HistorialArticuloModel(
            cantidad: 1,
            tipo: 'INVENTARIADO',
            descripcion: 'Motor D4CB 2.5 CRDI',
            sku: 'MOT-8899',
            categoria: 'Motores',
            marca: 'Hyundai',
            modelo: 'H1',
            anio: 2017,
            detalleTecnico: '2.5 CRDi 170cv',
            precio: 1200000,
            subtotal: 1200000,
          ),
        ],
        historialMovimientos: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return AuditoriaTablaView.buildBadgesMotorCaja(
                  ordenInventariada,
                  context: context,
                )!;
              },
            ),
          ),
        ),
      );

      // Verificación de visualización
      expect(find.text('MOT-8899'), findsOneWidget);
      expect(find.text('Motor / Caja'), findsNothing);

      // Verificación de Tooltip con vehículo de origen
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, contains('Hyundai H1 2017'));
      expect(tooltip.message, contains('MOT-8899'));
    });

    testWidgets('6. Widgets: AuditoriaTablaView no renderiza badge si sólo hay falsos positivos', (tester) async {
      final ordenCremallera = HistorialOrdenItemModel(
        idOrden: 'ord-crem',
        folio: 'ORD-777',
        tipoOperacion: 'Venta Mesón',
        emiteQr: true,
        fechaIso: '2026-10-12',
        hora: '11:00',
        fechaHoraFormateada: '11:00 - 12/10/2026',
        clienteNombre: 'Luis Vega',
        vendedorNombre: 'Vendedor 1',
        cajeraNombre: 'Cajera 1',
        estadoOrden: 'Pagada',
        modalidadPago: 'Efectivo',
        metodosResumen: 'Efectivo',
        totalVenta: 55000,
        abonoPrevio: 0,
        totalLiquidado: 55000,
        desglosePagos: [],
        articulos: [
          HistorialArticuloModel(
            cantidad: 1,
            tipo: 'DESARME',
            descripcion: 'Motor de cremallera electroasistida',
            precio: 55000,
            subtotal: 55000,
          ),
        ],
        historialMovimientos: [],
      );

      final widgetBadge = AuditoriaTablaView.buildBadgesMotorCaja(ordenCremallera);
      expect(widgetBadge, isNull);
    });
  });
}
