import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/features/ventas/controllers/cart_controller.dart';
import 'package:frontend/features/ventas/models/catalogo_model.dart';
import 'package:frontend/features/ventas/presentation/screens/carrito_screen.dart';
import 'package:frontend/features/ventas/presentation/screens/catalogo_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({
    'access_token': 'dummy-token',
    'user_id_rol': '2',
    'id_sucursal': '1',
  });

  final itemTest1 = CatalogoItem(
    idActivo: '3fa85f64-5717-4562-b3fc-2c963f66afa6',
    skuQrFisico: 'MOT-TOY-YAR-2019-01',
    precioReferencia: 520000,
    idCategoria: 1,
    nombreCategoria: 'Motor',
    idSucursalActual: 1,
    nombreSucursal: 'Viña del Mar',
    marca: 'Toyota',
    modelo: 'Yaris Sport',
    anio: 2019,
    traccion: '4x2',
    cilindrada: '1.5L',
    combustible: 'Gasolina',
    transmisionTipo: 'Manual',
    ubicacionPasillo: 'P-02',
    ubicacionPallet: 'PL-14',
    estadoActivo: 'Disponible',
  );

  setUp(() {
    CartController.instance.vaciarCarrito();
  });

  group('CarritoScreen UI Tests', () {
    testWidgets('Muestra estado vacío interactivo cuando no hay productos', (tester) async {
      bool catalogoPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: CarritoScreen(
            onNavigateToCatalogo: () {
              catalogoPressed = true;
            },
          ),
        ),
      );

      expect(find.text('Carrito de Ventas'), findsOneWidget);
      expect(find.text('Tu carrito está vacío'), findsOneWidget);
      expect(find.byIcon(Icons.remove_shopping_cart_outlined), findsOneWidget);
      expect(find.text('Explorar Catálogo'), findsOneWidget);
      expect(find.text('Venta Libre / Misceláneo'), findsOneWidget);

      // Botón Explorar Catálogo ejecuta callback
      await tester.tap(find.text('Explorar Catálogo'));
      await tester.pump();

      expect(catalogoPressed, isTrue);
    });

    testWidgets('Renderiza vista unificada (Carrito + Micro-CRM) con barra fija', (tester) async {
      CartController.instance.agregarInventariado(itemTest1);
      CartController.instance.agregarVentaLibre(
        descripcion: 'Pernos Culata Especiales',
        monto: 15000,
        cantidad: 2,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: CarritoScreen(),
        ),
      );

      // Encabezado del carrito
      expect(find.text('Carrito de Compras'), findsOneWidget);
      expect(find.text('Revisa tus activos y finaliza la venta'), findsOneWidget);
      expect(find.text('3 Ítems'), findsOneWidget);

      // Badges distintivos
      expect(find.text('Inventario'), findsOneWidget);
      expect(find.text('Venta Libre'), findsOneWidget);

      // Títulos de productos
      expect(find.text('Motor - Toyota Yaris Sport 2019'), findsOneWidget);
      expect(find.text('Pernos Culata Especiales'), findsOneWidget);

      // Botón ancho completo '+ Añadir Ítem No Inventariado / Misceláneo'
      expect(find.text('+ Añadir Ítem No Inventariado / Misceláneo'), findsOneWidget);

      // Tarjetas Micro-CRM
      expect(find.text('DATOS POST-VENTA CLIENTE'), findsOneWidget);
      expect(find.text('MODALIDAD DE ENTREGA'), findsOneWidget);
      expect(find.text('Retiro en Tienda'), findsOneWidget);
      expect(find.text('Despacho a Domicilio'), findsOneWidget);
      expect(find.text('Traslado a otra sucursal'), findsOneWidget);

      // Barra inferior de Checkout
      expect(find.text('TOTAL CARRITO:'), findsOneWidget);
      expect(find.text('\$550.000'), findsOneWidget); // 520.000 + 30.000
      expect(find.text('Derivar a Caja'), findsOneWidget);

      // Botones en AppBar
      expect(find.byTooltip('Agregar ítem manual'), findsOneWidget);
      expect(find.byTooltip('Vaciar carrito'), findsOneWidget);
    });

    testWidgets('Selector de Modalidad de Entrega despliega campos de Despacho y Traslado', (tester) async {
      CartController.instance.agregarInventariado(itemTest1);

      await tester.pumpWidget(
        const MaterialApp(
          home: CarritoScreen(),
        ),
      );

      // Scroll hasta MODALIDAD DE ENTREGA
      await tester.scrollUntilVisible(
        find.text('MODALIDAD DE ENTREGA'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('MODALIDAD DE ENTREGA'), findsOneWidget);

      // Al inicio está en 'Retiro en Tienda' por defecto
      expect(find.text('El cliente retirará los repuestos directamente en el mesón de atención tras completar el pago en caja.'), findsOneWidget);
      expect(find.text('Dirección de Envío *'), findsNothing);
      expect(find.text('SELECCIONA SUCURSAL DESTINO *'), findsNothing);

      // Seleccionar 'Despacho a Domicilio'
      await tester.tap(find.byKey(const Key('chip_entrega_Despacho')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Dirección de Envío *'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Dirección de Envío *'), findsOneWidget);
      expect(find.text('Región Destino *'), findsOneWidget);
      expect(find.text('Comuna Destino *'), findsOneWidget);
      expect(find.text('RUT Receptor *'), findsOneWidget);
      expect(find.text('Nombres Receptor *'), findsOneWidget);
      expect(find.text('Teléfono Receptor *'), findsOneWidget);

      // Seleccionar 'Traslado a otra sucursal'
      await tester.scrollUntilVisible(
        find.byKey(const Key('chip_entrega_Traslado')),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('chip_entrega_Traslado')));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('SELECCIONA SUCURSAL DESTINO *'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('SELECCIONA SUCURSAL DESTINO *'), findsOneWidget);
      expect(find.text('Sucursal de Destino'), findsOneWidget);
      expect(find.textContaining('Viña del Mar'), findsWidgets);
      expect(find.text('Limache'), findsWidgets);
    });

    testWidgets('Edición in-line de precio recalcula subtotal y total en tiempo real', (tester) async {
      CartController.instance.agregarInventariado(itemTest1);

      await tester.pumpWidget(
        const MaterialApp(
          home: CarritoScreen(),
        ),
      );

      expect(find.text('\$520.000'), findsNWidgets(2)); // Subtotal + Total

      // Modificar el precio en el TextField in-line
      final precioField = find.widgetWithText(TextField, '520.000');
      expect(precioField, findsOneWidget);

      await tester.enterText(precioField, '450000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Verificar que el total y subtotal se actualizaron a $450.000
      expect(find.text('\$450.000'), findsNWidgets(2));
      expect(CartController.instance.totalMonto, 450000);
    });

    testWidgets('Selector de cantidad en CartItemTile incrementa/decrementa total', (tester) async {
      CartController.instance.agregarVentaLibre(
        descripcion: 'Aceite 10W40',
        monto: 20000,
        cantidad: 1,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CarritoScreen(),
          ),
        ),
      );

      expect(find.text('1'), findsOneWidget);
      expect(find.text('\$20.000'), findsNWidgets(2)); // Subtotal + Total

      // Presionar botón '+' para subir a 2 en el stepper de CartItemTile
      await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
      expect(find.text('\$40.000'), findsNWidgets(2)); // 20.000 * 2
      expect(CartController.instance.totalMonto, 40000);
    });

    testWidgets('Eliminar ítem mediante botón de basurero actualiza UI y controller', (tester) async {
      CartController.instance.agregarInventariado(itemTest1);

      await tester.pumpWidget(
        const MaterialApp(
          home: CarritoScreen(),
        ),
      );

      expect(find.text('Motor - Toyota Yaris Sport 2019'), findsOneWidget);

      // Tap en icono de basurero
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // Carrito queda vacío y muestra pantalla de estado vacío
      expect(find.text('Tu carrito está vacío'), findsOneWidget);
      expect(CartController.instance.estaVacio, isTrue);
    });

    testWidgets('Validación al presionar Derivar a Caja y flujo de derivación exitoso', (tester) async {
      CartController.instance.agregarInventariado(
        itemTest1,
        notas: 'Entregar con soporte especial',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: CarritoScreen(),
        ),
      );

      // 1. Presionar Derivar a Caja sin llenar datos debe mostrar error
      final btnDerivar = find.widgetWithText(ElevatedButton, 'Derivar a Caja');
      expect(btnDerivar, findsOneWidget);

      await tester.tap(btnDerivar);
      await tester.pump();

      expect(find.text('Campo requerido'), findsWidgets);

      // 2. Llenar campos requeridos (scroll arriba a la sección de datos)
      await tester.scrollUntilVisible(
        find.text('DATOS POST-VENTA CLIENTE'),
        100,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, '12.345.678-9').first,
        '18.765.432-1',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Juan'),
        'Carlos',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Pérez'),
        'González',
      );

      // 3. Presionar Derivar a Caja -> Procesa llamada transaccional sin fricción de consentimiento
      await tester.tap(btnDerivar);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Tras finalizar la petición en entorno de test sin backend, captura el resultado en SnackBar
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('Botón Derivar a Caja está deshabilitado si el monto es 0', (tester) async {
      CartController.instance.agregarVentaLibre(
        descripcion: 'Item Gratuito / Promoción',
        monto: 0,
        cantidad: 1,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: CarritoScreen(),
        ),
      );

      // El botón debe existir pero estar deshabilitado (onPressed == null)
      final btnDerivar = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Derivar a Caja'),
      );
      expect(btnDerivar.onPressed, isNull);
    });

    testWidgets('Switch Consumidor Final / Sin RUT oculta campos personales y muestra banner informativo', (tester) async {
      CartController.instance.agregarInventariado(itemTest1);

      await tester.pumpWidget(
        const MaterialApp(
          home: CarritoScreen(),
        ),
      );

      // El switch de consumidor final existe y por defecto está en false
      final switchFinder = find.byKey(const Key('switch_cliente_anonimo'));
      await tester.scrollUntilVisible(
        switchFinder,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(switchFinder, findsOneWidget);
      expect(find.text('Consumidor Final (Sin RUT)'), findsOneWidget);
      expect(find.text('RUT Cliente *'), findsOneWidget);

      // Activar switch
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Campos personales deben ocultarse y el banner informativo debe ser visible
      expect(find.text('RUT Cliente *'), findsNothing);
      expect(
        find.text('Aviso: El cliente solo podrá pagar y retirar en caja presentando su Número de Orden.'),
        findsOneWidget,
      );

      // Desactivar switch
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Campos personales reaparecen
      expect(find.text('RUT Cliente *'), findsOneWidget);
    });

    testWidgets('Selector de Responsable NO es visible para rol Vendedor (id_rol == 2)', (tester) async {
      const storage = FlutterSecureStorage();
      await storage.write(key: 'access_token', value: 'dummy-token');
      await storage.write(key: 'user_id_rol', value: '2');

      CartController.instance.agregarInventariado(itemTest1);

      await tester.pumpWidget(
        const MaterialApp(
          home: CarritoScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Responsable de Entrega/Despacho en Sucursal'), findsNothing);
    });

    testWidgets('Selector de Responsable ES visible para rol VendedorOnline (id_rol == 7)', (tester) async {
      const storage = FlutterSecureStorage();
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode([
            {
              'id_usuario': '11111111-1111-1111-1111-111111111111',
              'nombre_completo': 'Gastón Zamora',
              'rut': '11.111.111-1',
              'id_sucursal': 1,
              'correo': 'gaston@cresal.cl',
            }
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      await storage.write(key: 'access_token', value: 'dummy-token');
      await storage.write(key: 'user_id_rol', value: '7');

      CartController.instance.agregarInventariado(itemTest1);

      await tester.pumpWidget(
        MaterialApp(
          home: CarritoScreen(httpClient: mockClient),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Responsable de Entrega/Despacho en Sucursal'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Responsable de Entrega/Despacho en Sucursal'), findsOneWidget);
    });

    testWidgets('Botón de vaciar carrito en AppBar muestra diálogo de confirmación y vacía liberando reservas', (tester) async {
      final initialRefreshCount = CatalogoScreen.refreshNotifier.value;
      CartController.instance.agregarInventariado(itemTest1);
      CartController.instance.agregarVentaLibre(descripcion: 'Aceite 10W40', monto: 15000);

      await tester.pumpWidget(
        const MaterialApp(
          home: CarritoScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(CartController.instance.items.length, 2);
      expect(find.byIcon(Icons.delete_sweep_outlined), findsOneWidget);

      // 1. Tocar el icono de vaciar carrito
      await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
      await tester.pumpAndSettle();

      // Verificar diálogo modal
      expect(find.text('Vaciar Carrito'), findsOneWidget);
      expect(find.text('¿Estás seguro de que deseas eliminar todos los productos del carrito?'), findsOneWidget);

      // 2. Presionar "VACIAR"
      await tester.tap(find.text('VACIAR'));
      await tester.pumpAndSettle();

      // El carrito debe estar vacío
      expect(CartController.instance.estaVacio, isTrue);
      expect(find.text('Tu carrito está vacío'), findsOneWidget);
      expect(find.text('Carrito vaciado exitosamente'), findsOneWidget);
      expect(CatalogoScreen.refreshNotifier.value, greaterThan(initialRefreshCount));
    });
  });
}
