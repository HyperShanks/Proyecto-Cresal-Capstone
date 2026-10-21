// test/features/inventario/detalle_activo_ui_test.dart
// Pruebas de widgets para SPEC-HU-TAREA-17:
// Visualización Compartida de Atributos Técnicos entre Motor y Caja de Cambios

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/inventario/presentation/screens/detalle_activo_screen.dart';

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

  group('SPEC-HU-TAREA-17 - DetalleActivoScreen UI Tests', () {
    testWidgets(
        'Caja de Cambios: renderiza atributos compartidos y NO renderiza Número de Motor',
        (tester) async {
      final mockCaja = {
        'id_activo': 'caj-001',
        'id_categoria': 2,
        'categoria': 'Caja de Cambios',
        'marca': 'Toyota',
        'modelo': 'Hilux',
        'sku': 'CAJ-8801',
        'estado': 'DISPONIBLE',
        'numero_ingreso': 'ING-8801',
        'cilindrada': '2.8L',
        'combustible': 'Diesel',
        'transmision': 'Manual 6V',
        'traccion': '4x4',
        'numero_motor': '1GD-998877', // Aunque venga en payload, debe omitirse
        'ubicacion': 'P-01 - PAL-11',
        'pasillo': 'P-01',
        'pallet': 'PAL-11',
        'galpon': 'G-1',
        'qr_impreso': false,
        'imagenes': [],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: DetalleActivoScreen(activo: mockCaja),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Tarea 4: Especificaciones técnicas compartidas deben renderizarse
      expect(find.text('CILINDRADA'), findsOneWidget);
      expect(find.text('2.8L'), findsOneWidget);

      expect(find.text('COMBUSTIBLE'), findsOneWidget);
      expect(find.text('Diesel'), findsOneWidget);

      expect(find.text('TRANSMISIÓN'), findsOneWidget);
      expect(find.text('Manual 6V'), findsOneWidget);

      expect(find.text('TRACCIÓN'), findsOneWidget);
      expect(find.text('4x4'), findsOneWidget);

      // 2. Tarea 5 y Tarea 6: Exclusividad de Número de Motor
      // La etiqueta y el valor del número de motor NO deben existir en el árbol de widgets
      expect(find.text('Número de Motor'), findsNothing);
      expect(find.text('NÚMERO DE MOTOR'), findsNothing);
      expect(find.text('1GD-998877'), findsNothing);
      expect(find.byKey(const Key('spec_card_número_de_motor')), findsNothing);
    });

    testWidgets(
        'Motor: renderiza Número de Motor junto a todas las especificaciones técnicas',
        (tester) async {
      final mockMotor = {
        'id_activo': 'mot-001',
        'id_categoria': 1,
        'categoria': 'Motor',
        'marca': 'Toyota',
        'modelo': 'Hilux',
        'sku': 'MOT-8801',
        'estado': 'DISPONIBLE',
        'numero_ingreso': 'ING-8801',
        'cilindrada': '2.8L',
        'combustible': 'Diesel',
        'transmision': 'Manual',
        'traccion': '4x4',
        'numero_motor': '1GD-998877',
        'ubicacion': 'P-01 - PAL-10',
        'pasillo': 'P-01',
        'pallet': 'PAL-10',
        'galpon': 'G-1',
        'qr_impreso': false,
        'imagenes': [],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: DetalleActivoScreen(activo: mockMotor),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Número de motor SÍ debe renderizarse para Motor
      expect(find.text('Número de Motor'), findsOneWidget);
      expect(find.text('1GD-998877'), findsOneWidget);

      // 2. Especificaciones técnicas compartidas
      expect(find.text('CILINDRADA'), findsOneWidget);
      expect(find.text('2.8L'), findsOneWidget);

      expect(find.text('COMBUSTIBLE'), findsOneWidget);
      expect(find.text('Diesel'), findsOneWidget);

      expect(find.text('TRANSMISIÓN'), findsOneWidget);
      expect(find.text('Manual'), findsOneWidget);

      expect(find.text('TRACCIÓN'), findsOneWidget);
      expect(find.text('4x4'), findsOneWidget);
    });

    testWidgets(
        'Motor sin número de motor asignado: no renderiza la tarjeta vacía',
        (tester) async {
      final mockMotorSinNum = {
        'id_activo': 'mot-002',
        'id_categoria': 1,
        'categoria': 'Motor',
        'marca': 'Nissan',
        'modelo': 'Versa',
        'sku': 'MOT-8802',
        'estado': 'DISPONIBLE',
        'numero_ingreso': 'ING-8802',
        'cilindrada': '1.6L',
        'combustible': 'Bencina',
        'transmision': 'Automática',
        'traccion': '4x2',
        'numero_motor': null,
        'ubicacion': 'P-02 - PAL-03',
        'pasillo': 'P-02',
        'pallet': 'PAL-03',
        'qr_impreso': false,
        'imagenes': [],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: DetalleActivoScreen(activo: mockMotorSinNum),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Número de Motor'), findsNothing);
      expect(find.text('1.6L'), findsOneWidget);
      expect(find.text('Bencina'), findsOneWidget);
    });
  });
}
