// test/especificaciones_vehiculo_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/constants/especificaciones_vehiculo.dart';
import 'package:frontend/features/recepcion/presentation/screens/recepcion_vehiculo_screen.dart';
import 'package:frontend/features/paletizado/presentation/screens/paletizado_screen.dart';

void main() {
  group('Especificaciones Vehículo - Constantes Estandarizadas', () {
    test('OpcionesCombustible contiene los valores requeridos', () {
      expect(OpcionesCombustible.seleccionar, 'Seleccionar');
      expect(OpcionesCombustible.otro, 'Otro...');
      expect(OpcionesCombustible.lista, [
        'Gasolina',
        'Diésel',
        'Híbrido',
        'Eléctrico',
        'Otro...',
      ]);
      expect(OpcionesCombustible.listaConSeleccionar, [
        'Seleccionar',
        'Gasolina',
        'Diésel',
        'Híbrido',
        'Eléctrico',
        'Otro...',
      ]);
      expect(OpcionesCombustible.listaFiltros, [
        'Todos',
        'Gasolina',
        'Diésel',
        'Híbrido',
        'Eléctrico',
        'Otro...',
      ]);
    });

    test('OpcionesTransmision contiene los valores requeridos', () {
      expect(OpcionesTransmision.seleccionar, 'Seleccionar');
      expect(OpcionesTransmision.otro, 'Otro...');
      expect(OpcionesTransmision.lista, [
        'Mecánica',
        'Automática',
        'Semiautomática',
        'Otro...',
      ]);
      expect(OpcionesTransmision.listaConSeleccionar, [
        'Seleccionar',
        'Mecánica',
        'Automática',
        'Semiautomática',
        'Otro...',
      ]);
      expect(OpcionesTransmision.listaFiltros, [
        'Todas',
        'Mecánica',
        'Automática',
        'Semiautomática',
        'Otro...',
      ]);
    });

    test('OpcionesTraccion contiene las 4 tracciones requeridas y Otro...', () {
      expect(OpcionesTraccion.seleccionar, 'Seleccionar');
      expect(OpcionesTraccion.otro, 'Otro...');
      expect(OpcionesTraccion.lista, [
        '4x2 Delantera',
        '4x2 Trasera',
        '4x4 Conectable (4WD)',
        '4x4 Permanente (AWD)',
        'Otro...',
      ]);
      expect(OpcionesTraccion.listaConSeleccionar, [
        'Seleccionar',
        '4x2 Delantera',
        '4x2 Trasera',
        '4x4 Conectable (4WD)',
        '4x4 Permanente (AWD)',
        'Otro...',
      ]);
      expect(OpcionesTraccion.listaFiltros, [
        'Todas',
        '4x2 Delantera',
        '4x2 Trasera',
        '4x4 Conectable (4WD)',
        '4x4 Permanente (AWD)',
        'Otro...',
      ]);
    });

    test('OpcionesUbicacionBodega define Galpones 1..3 y Pasillos A..G', () {
      expect(OpcionesUbicacionBodega.galpones, ['1', '2', '3']);
      expect(OpcionesUbicacionBodega.pasillos, ['A', 'B', 'C', 'D', 'E', 'F', 'G']);
    });
  });

  group('Recepción Vehículo - Selectores Estandarizados & Dinámicos', () {
    testWidgets('RecepcionVehiculoScreen renderiza selectores con Seleccionar inicial', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RecepcionVehiculoScreen(),
        ),
      );
      await tester.pump();

      expect(find.text('Recepción de Vehículo'), findsOneWidget);
      expect(find.text('Tracción'), findsOneWidget);
      expect(find.text('Transmisión'), findsOneWidget);
      expect(find.text('Combustible'), findsOneWidget);
      // Muestra Seleccionar en los selectores
      expect(find.text('Seleccionar'), findsWidgets);
    });
  });

  group('Paletizado Bodega - Ubicaciones Estandarizadas', () {
    testWidgets('PaletizadoScreen renderiza buscador y estructura inicial', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PaletizadoScreen(),
        ),
      );
      await tester.pump();

      expect(find.text('Paletizado y Enriquecimiento'), findsOneWidget);
      expect(find.text('Buscar N° Ingreso...'), findsOneWidget);
    });
  });
}
