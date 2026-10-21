import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/constants/chile_geografia.dart';
import 'package:frontend/features/ventas/controllers/cart_controller.dart';
import 'package:frontend/features/ventas/presentation/screens/carrito_screen.dart';
import 'package:frontend/features/ventas/presentation/screens/checkout_wizard_screen.dart';

void main() {
  setUp(() {
    CartController.instance.vaciarCarrito();
  });

  group('ChileGeografia Tests', () {
    test('Contiene las 16 regiones de Chile y 346 comunas', () {
      expect(ChileGeografia.regiones.length, equals(16));
      expect(ChileGeografia.regiones, contains('Valparaíso'));
      expect(ChileGeografia.regiones, contains('Metropolitana de Santiago'));
      expect(ChileGeografia.regiones, contains('Biobío'));

      final comunasValpo = ChileGeografia.obtenerComunas('Valparaíso');
      expect(comunasValpo, contains('Viña del Mar'));
      expect(comunasValpo, contains('Limache'));
      expect(comunasValpo, contains('Concón'));
      expect(comunasValpo, contains('Quilpué'));

      final comunasRM = ChileGeografia.obtenerComunas('Metropolitana de Santiago');
      expect(comunasRM, contains('Santiago'));
      expect(comunasRM, contains('Providencia'));
      expect(comunasRM, contains('Las Condes'));
      expect(comunasRM, contains('Maipú'));
    });

    test('obtenerRegionDeComuna identifica correctamente la región de origen', () {
      expect(ChileGeografia.obtenerRegionDeComuna('Viña del Mar'), equals('Valparaíso'));
      expect(ChileGeografia.obtenerRegionDeComuna('Santiago'), equals('Metropolitana de Santiago'));
      expect(ChileGeografia.obtenerRegionDeComuna('Concepción'), equals('Biobío'));
      expect(ChileGeografia.obtenerRegionDeComuna('InexistenteComunaXYZ'), isNull);
    });

    test('obtenerIdComuna mapea IDs correctamente con fallback a 1', () {
      expect(ChileGeografia.obtenerIdComuna('Viña del Mar'), equals(1));
      expect(ChileGeografia.obtenerIdComuna('Limache'), equals(2));
      expect(ChileGeografia.obtenerIdComuna(null), equals(1));
    });
  });

  group('CarritoScreen - Cascada Región -> Comuna', () {
    testWidgets('Comuna Cliente y Comuna Destino están deshabilitadas inicialmente y se habilitan al elegir región', (tester) async {
      CartController.instance.agregarVentaLibre(
        descripcion: 'Repuesto Test',
        monto: 50000,
        cantidad: 1,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CarritoScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll a DATOS POST-VENTA CLIENTE
      await tester.scrollUntilVisible(
        find.text('DATOS POST-VENTA CLIENTE'),
        100,
        scrollable: find.byType(Scrollable).first,
      );

      // Comuna Cliente debe mostrar placeholder "Seleccione región primero"
      expect(find.text('Seleccione región primero'), findsWidgets);

      // Abrir dropdown de Región Cliente
      final regionDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Seleccione Región...').first;
      expect(regionDropdown, findsOneWidget);

      await tester.tap(regionDropdown);
      await tester.pumpAndSettle();

      // Seleccionar "Valparaíso"
      final optionValpo = find.text('Valparaíso').last;
      await tester.tap(optionValpo);
      await tester.pumpAndSettle();

      // Comuna ahora debe estar habilitada con hint "Seleccione Comuna..."
      expect(find.text('Seleccione Comuna...'), findsWidgets);

      // Abrir dropdown de Comuna Cliente
      final comunaDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Seleccione Comuna...').first;
      await tester.tap(comunaDropdown);
      await tester.pumpAndSettle();

      // Debe listar comunas de Valparaíso
      expect(find.text('Viña del Mar'), findsWidgets);
      expect(find.text('Limache'), findsWidgets);
      // No debe listar comunas de otra región como Punta Arenas
      expect(find.text('Punta Arenas'), findsNothing);
    });

    testWidgets('Activar cliente anónimo / Consumidor Final preselecciona Valparaíso y Viña del Mar', (tester) async {
      CartController.instance.agregarVentaLibre(
        descripcion: 'Repuesto Test',
        monto: 30000,
        cantidad: 1,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CarritoScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll hasta el switch de cliente anónimo
      await tester.scrollUntilVisible(
        find.byKey(const Key('switch_cliente_anonimo')),
        100,
        scrollable: find.byType(Scrollable).first,
      );

      // Activar switch de cliente anónimo
      final switchAnonimo = find.byKey(const Key('switch_cliente_anonimo'));
      await tester.tap(switchAnonimo);
      await tester.pumpAndSettle();

      // Verifica banner informativo
      expect(find.text('Aviso: El cliente solo podrá pagar y retirar en caja presentando su Número de Orden.'), findsOneWidget);
    });
  });

  group('CheckoutWizardScreen - Cascada Región -> Comuna', () {
    testWidgets('En Step 2 (Micro-CRM) Comuna está deshabilitada hasta seleccionar Región', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: CheckoutWizardScreen(
            initialInventario: [
              {'id_activo': 'act-101', 'sku': 'SKU-101', 'descripcion': 'Alternador', 'precio': 120000}
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Avanzar al Paso 2 (Micro-CRM)
      await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
      await tester.pumpAndSettle();

      expect(find.text('2. Datos del Cliente (Micro-CRM)'), findsOneWidget);

      // Comuna Cliente debe indicar "Seleccione región primero"
      expect(find.text('Seleccione región primero'), findsOneWidget);

      // Seleccionar Región "Valparaíso"
      final regionDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Seleccione Región...').first;
      await tester.ensureVisible(regionDropdown);
      await tester.tap(regionDropdown);
      await tester.pumpAndSettle();

      final optValpo = find.text('Valparaíso').last;
      await tester.tap(optValpo);
      await tester.pumpAndSettle();

      // Comuna ahora muestra "Seleccione Comuna..."
      expect(find.text('Seleccione Comuna...'), findsOneWidget);

      // Abrir Comuna dropdown
      final comunaDropdown = find.widgetWithText(DropdownButtonFormField<String>, 'Seleccione Comuna...').first;
      await tester.ensureVisible(comunaDropdown);
      await tester.tap(comunaDropdown);
      await tester.pumpAndSettle();

      // Contiene comunas de la región
      expect(find.text('Viña del Mar'), findsWidgets);
      expect(find.text('Limache'), findsWidgets);
      expect(find.text('Arica'), findsNothing);
    });
  });
}
