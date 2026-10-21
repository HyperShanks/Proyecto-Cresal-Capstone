import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/constants/chile_geografia.dart';
import 'package:frontend/features/ventas/controllers/checkout_wizard_controller.dart';

void main() {
  group('Pruebas de Integración Geografía BD y Mapeo Dinámico', () {
    test('ChileGeografia prioriza los IDs reales provenientes de la Base de Datos', () {
      // Simular respuesta del backend donde Villa Alemana tiene ID 381 y Viña del Mar 371
      final mockGeografia = {
        'Valparaíso': ['Viña del Mar', 'Villa Alemana', 'Limache', 'Nueva Comuna Test'],
      };
      final mockIdMap = {
        'Viña del Mar': 371,
        'Villa Alemana': 381,
        'Limache': 365,
        'Nueva Comuna Test': 999,
      };

      ChileGeografia.registrarGeografiaDesdeBD(mockGeografia, mockIdMap);

      // Verificar que retorna el ID dinámico de la BD y no el estático por defecto
      expect(ChileGeografia.obtenerIdComuna('Villa Alemana'), equals(381));
      expect(ChileGeografia.obtenerIdComuna('Viña del Mar'), equals(371));
      expect(ChileGeografia.obtenerIdComuna('Limache'), equals(365));
      expect(ChileGeografia.obtenerIdComuna('Nueva Comuna Test'), equals(999));

      // Verificar que obtenerComunas incluye comunas de la BD
      final comunas = ChileGeografia.obtenerComunas('Valparaíso');
      expect(comunas, contains('Nueva Comuna Test'));
      expect(comunas, contains('Villa Alemana'));

      // Case insensitive & trim lookup
      expect(ChileGeografia.obtenerIdComuna('  villa alemana  '), equals(381));
      expect(ChileGeografia.obtenerRegionDeComuna('villa alemana'), equals('Valparaíso'));
    });

    test('CheckoutWizardController limpia abonos e instrucciones al llamar clearAll', () {
      final controller = CheckoutWizardController();
      controller.setAbonoAdicional(50000);
      controller.setNotasGenerales('Instrucción de prueba para bodega');

      expect(controller.abonoAdicional, equals(50000));
      expect(controller.notasGenerales, equals('Instrucción de prueba para bodega'));

      controller.clearAll();

      expect(controller.abonoAdicional, equals(0));
      expect(controller.notasGenerales.isEmpty, isTrue);
      expect(controller.totalAbonos, equals(0));
      expect(controller.totalItemsCount, equals(0));
    });
  });
}
