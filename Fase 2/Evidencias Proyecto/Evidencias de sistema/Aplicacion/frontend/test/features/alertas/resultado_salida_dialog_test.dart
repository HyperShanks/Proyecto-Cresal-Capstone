import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/alertas/presentation/widgets/resultado_salida_dialog.dart';
import 'package:frontend/features/alertas/services/logistica_service.dart';

void main() {
  group('ResultadoSalidaDialog - Modal Pop-up de Salida en Barrera', () {
    final sampleResponse = EscanearSalidaResponseModel(
      idOrden: 'ord-1234-uuid',
      folio: 'ORDEN #1024',
      estadoOrden: 'Completada',
      idBodeguero: 'bod-01',
      bodegueroNombre: 'Martín Bodeguero',
      fechaEntrega: DateTime.now().toIso8601String(),
      activosEntregados: ['MOT-1000', 'CAJ-1001'],
      totalEntregados: 2,
      mensaje: 'Entrega autorizada',
    );

    final sampleVerificada = VerificarQrSalidaResponseModel(
      idOrden: 'ord-1234-uuid',
      folio: 'ORDEN #1024',
      estadoOrden: 'Pagada',
      totalVenta: 1500000,
      montoPendiente: 0,
      idSucursal: 1,
      clienteNombre: 'Juan Pérez',
      clienteRut: '12.345.678-9',
      clienteTelefono: '+56911223344',
      itemsRequeridos: [
        ItemSalidaInfoModel(
          idDetalle: 'det-01',
          idActivo: 'act-01',
          titulo: 'Motor - Nissan Sentra',
          skuQrFisico: 'MOT-1000',
          ubicacion: 'Galpón 1 - Pasillo 03',
          qrImpreso: true,
          esInventariado: true,
          cantidad: 1,
          precioFinal: 750000,
        ),
        ItemSalidaInfoModel(
          idDetalle: 'det-02',
          idActivo: 'act-02',
          titulo: 'Caja de Cambios - Nissan Sentra',
          skuQrFisico: 'CAJ-1001',
          ubicacion: 'Galpón 1 - Pasillo 04',
          qrImpreso: true,
          esInventariado: true,
          cantidad: 1,
          precioFinal: 750000,
        ),
      ],
      totalItemsFisicos: 2,
      qrTransaccionalSalida: 'TX-QR-1024',
    );

    testWidgets('Renderiza correctamente estado autorizado, folio, cliente y repuestos', (tester) async {
      bool finalizado = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultadoSalidaDialog(
              resultado: sampleResponse,
              ordenVerificada: sampleVerificada,
              onFinalizar: () => finalizado = true,
            ),
          ),
        ),
      );

      // Verificación de elementos centrales
      expect(find.text('¡SALIDA AUTORIZADA!'), findsOneWidget);
      expect(find.text('ORDEN #1024'), findsOneWidget);
      expect(find.text('Cliente: Juan Pérez'), findsOneWidget);
      expect(find.text('Auditor: Martín Bodeguero'), findsOneWidget);
      expect(find.text('REPUESTOS DESPACHADOS (2):'), findsOneWidget);
      expect(find.text('Motor - Nissan Sentra'), findsOneWidget);
      expect(find.text('MOT-1000'), findsOneWidget);
      expect(find.text('Caja de Cambios - Nissan Sentra'), findsOneWidget);
      expect(find.text('CAJ-1001'), findsOneWidget);

      // Botón con temporizador
      expect(find.text('FINALIZAR ENTREGA (5s)'), findsOneWidget);

      // Tap en el botón finaliza inmediatamente
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(finalizado, isTrue);
    });

    testWidgets('Temporizador de 5 segundos descuenta y ejecuta onFinalizar automáticamente', (tester) async {
      bool finalizado = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultadoSalidaDialog(
              resultado: sampleResponse,
              ordenVerificada: sampleVerificada,
              onFinalizar: () => finalizado = true,
            ),
          ),
        ),
      );

      expect(find.text('FINALIZAR ENTREGA (5s)'), findsOneWidget);

      // Avanza 1 segundo -> 4s
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('FINALIZAR ENTREGA (4s)'), findsOneWidget);
      expect(finalizado, isFalse);

      // Avanza 1 segundo -> 3s
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('FINALIZAR ENTREGA (3s)'), findsOneWidget);
      expect(finalizado, isFalse);

      // Avanza 1 segundo -> 2s
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('FINALIZAR ENTREGA (2s)'), findsOneWidget);
      expect(finalizado, isFalse);

      // Avanza 1 segundo -> 1s
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('FINALIZAR ENTREGA (1s)'), findsOneWidget);
      expect(finalizado, isFalse);

      // Avanza 1 segundo -> 0s / finaliza
      await tester.pump(const Duration(seconds: 1));
      expect(finalizado, isTrue);
    });

    testWidgets('Muestra badge [MESÓN] para ítems no inventariados (misceláneos)', (tester) async {
      final verificadaConMiscelaneo = VerificarQrSalidaResponseModel(
        idOrden: 'ord-mix-uuid',
        folio: 'ORDEN #1025',
        estadoOrden: 'Pagada',
        totalVenta: 800000,
        montoPendiente: 0,
        idSucursal: 1,
        clienteNombre: 'Juan Pérez',
        clienteRut: '12.345.678-9',
        itemsRequeridos: [
          ItemSalidaInfoModel(
            idDetalle: 'det-01',
            idActivo: 'act-01',
            titulo: 'Motor - Nissan Sentra',
            skuQrFisico: 'MOT-1000',
            ubicacion: 'Galpón 1 - Pasillo 03',
            qrImpreso: true,
            esInventariado: true,
            cantidad: 1,
            precioFinal: 750000,
          ),
          ItemSalidaInfoModel(
            idDetalle: 'det-02',
            idActivo: null,
            titulo: 'Líquido Refrigerante (5L)',
            skuQrFisico: null,
            ubicacion: 'Mostrador',
            qrImpreso: true,
            esInventariado: false,
            cantidad: 1,
            precioFinal: 50000,
          ),
        ],
        totalItemsFisicos: 1,
        qrTransaccionalSalida: 'TX-QR-1025',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultadoSalidaDialog(
              resultado: sampleResponse,
              ordenVerificada: verificadaConMiscelaneo,
              onFinalizar: () {},
            ),
          ),
        ),
      );

      expect(find.text('Motor - Nissan Sentra'), findsOneWidget);
      expect(find.text('MOT-1000'), findsOneWidget);
      expect(find.text('Líquido Refrigerante (5L)'), findsOneWidget);
      expect(find.text('MESÓN'), findsOneWidget);
    });
  });
}
