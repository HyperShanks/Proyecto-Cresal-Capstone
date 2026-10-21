// test/timezone_format_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/ventas/services/ordenes_service.dart';
import 'package:frontend/features/ventas/models/pendiente_precio_model.dart';

void main() {
  group('Zona Horaria (UTC vs Local) Formatters Tests', () {
    test('OrdenHistorialModel.fechaFormateada convierte fecha UTC a hora local', () {
      final modelUtc = OrdenHistorialModel(
        idOrden: '11111111-1111-1111-1111-111111111111',
        estadoOrden: 'Pagada',
        totalVenta: 150000,
        montoPendiente: 0,
        fechaCreacion: '2026-08-17T15:30:00Z',
        totalItems: 1,
        detalles: [],
      );

      final dtLocalEsperado = DateTime.parse('2026-08-17T15:30:00Z').toLocal();
      final dia = dtLocalEsperado.day.toString().padLeft(2, '0');
      final mes = dtLocalEsperado.month.toString().padLeft(2, '0');
      final anio = dtLocalEsperado.year;
      final hora = dtLocalEsperado.hour.toString().padLeft(2, '0');
      final min = dtLocalEsperado.minute.toString().padLeft(2, '0');
      final esperado = '$dia/$mes/$anio $hora:$min';

      expect(modelUtc.fechaFormateada, esperado);
    });

    test('EntregaEnvioModel.fechaFormateada convierte fecha ISO a hora local', () {
      const model = EntregaEnvioModel(
        idOrden: '22222222-2222-2222-2222-222222222222',
        folio: 'ORD-DESP-002',
        tipoEntrega: 'Despacho',
        estadoOrden: 'Pagada',
        totalVenta: 200000,
        montoPendiente: 0,
        fechaCreacion: '2026-08-17T18:45:00Z',
        totalItems: 1,
        detalles: [],
        preparacionLista: true,
        todosPreparados: true,
      );

      final dtLocalEsperado = DateTime.parse('2026-08-17T18:45:00Z').toLocal();
      final dia = dtLocalEsperado.day.toString().padLeft(2, '0');
      final mes = dtLocalEsperado.month.toString().padLeft(2, '0');
      final anio = dtLocalEsperado.year;
      final hora = dtLocalEsperado.hour.toString().padLeft(2, '0');
      final min = dtLocalEsperado.minute.toString().padLeft(2, '0');
      final esperado = '$dia/$mes/$anio $hora:$min';

      expect(model.fechaFormateada, esperado);
    });

    test('ActivoPendientePrecioModel parsea fechaCreacion y formatea con hora local', () {
      final json = {
        'id_activo': '33333333-3333-3333-3333-333333333333',
        'sku_qr_fisico': 'MOT-HYU-ACC-001',
        'titulo_repuesto': 'Motor Hyundai',
        'estado_activo': 'En Desarme',
        'fecha_creacion': '2026-08-17T12:00:00Z',
      };

      final model = ActivoPendientePrecioModel.fromJson(json);
      final dtLocalEsperado = DateTime.parse('2026-08-17T12:00:00Z').toLocal();
      final dia = dtLocalEsperado.day.toString().padLeft(2, '0');
      final mes = dtLocalEsperado.month.toString().padLeft(2, '0');
      final anio = dtLocalEsperado.year;
      final hora = dtLocalEsperado.hour.toString().padLeft(2, '0');
      final min = dtLocalEsperado.minute.toString().padLeft(2, '0');
      final esperado = '$dia/$mes/$anio $hora:$min';

      expect(model.fechaCreacionFormateada, esperado);
    });

    test('esDeHoy evalúa correctamente órdenes creadas en horario nocturno local', () {
      final nowUtc = DateTime.now().toUtc();
      final modelHoy = OrdenHistorialModel(
        idOrden: '33333333-3333-3333-3333-333333333333',
        estadoOrden: 'Pagada',
        totalVenta: 100000,
        montoPendiente: 0,
        fechaCreacion: nowUtc.toIso8601String(),
        totalItems: 1,
        detalles: [],
      );

      expect(modelHoy.esDeHoy, isTrue);

      final modelAyer = OrdenHistorialModel(
        idOrden: '44444444-4444-4444-4444-444444444444',
        estadoOrden: 'Pagada',
        totalVenta: 100000,
        montoPendiente: 0,
        fechaCreacion: nowUtc.subtract(const Duration(days: 2)).toIso8601String(),
        totalItems: 1,
        detalles: [],
      );

      expect(modelAyer.esDeHoy, isFalse);
    });
  });
}
