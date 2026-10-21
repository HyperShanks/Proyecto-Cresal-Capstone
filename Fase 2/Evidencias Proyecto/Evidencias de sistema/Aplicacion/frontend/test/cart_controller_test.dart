// test/cart_controller_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/ventas/controllers/cart_controller.dart';
import 'package:frontend/features/ventas/models/cart_item_model.dart';
import 'package:frontend/features/ventas/models/catalogo_model.dart';
import 'package:frontend/features/ventas/presentation/widgets/venta_libre_dialog.dart';

void main() {
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

  final itemTest2 = CatalogoItem(
    idActivo: '4ab95f64-5717-4562-b3fc-2c963f66afb7',
    skuQrFisico: 'CAJ-HYU-ACC-2018-03',
    precioReferencia: 380000,
    idCategoria: 2,
    nombreCategoria: 'Caja de Cambios',
    idSucursalActual: 2,
    nombreSucursal: 'Limache',
    marca: 'Hyundai',
    modelo: 'Accent',
    anio: 2018,
    traccion: '4x2',
    transmisionTipo: 'Manual 6 Vel',
    ubicacionPasillo: 'P-04',
    ubicacionPallet: 'PL-22',
    estadoActivo: 'Disponible',
  );

  setUp(() {
    CartController.instance.vaciarCarrito();
  });

  group('CartController Logic Tests', () {
    test('Carrito inicia vacío', () {
      final cart = CartController.instance;
      expect(cart.estaVacio, isTrue);
      expect(cart.totalItems, 0);
      expect(cart.totalMonto, 0);
      expect(cart.totalMontoFormateado, '\$0');
    });

    test('Agregar activo inventariado calcula montos correctamente', () {
      final cart = CartController.instance;
      final agregado = cart.agregarInventariado(itemTest1);

      expect(agregado, isTrue);
      expect(cart.estaVacio, isFalse);
      expect(cart.totalItems, 1);
      expect(cart.totalMonto, 520000);
      expect(cart.totalMontoFormateado, '\$520.000');
      expect(cart.estaEnCarrito(itemTest1.idActivo), isTrue);

      final item = cart.items.first as InventariadoCartItem;
      expect(item.esInventariado, isTrue);
      expect(item.cantidad, 1);
      expect(item.precioFinal, 520000);
      expect(item.subtotal, 520000);
      expect(item.sku, 'MOT-TOY-YAR-2019-01');
    });

    test('Previene duplicar el mismo activo físico inventariado', () {
      final cart = CartController.instance;
      final primerIntento = cart.agregarInventariado(itemTest1);
      final segundoIntento = cart.agregarInventariado(itemTest1);

      expect(primerIntento, isTrue);
      expect(segundoIntento, isFalse);
      expect(cart.totalItems, 1);
    });

    test('Permite negociar/modificar precio de un activo inventariado', () {
      final cart = CartController.instance;
      cart.agregarInventariado(itemTest1);

      // Vendedor negocia y baja el precio de 520.000 a 480.000
      cart.actualizarPrecio(itemTest1.idActivo, 480000);

      expect(cart.totalMonto, 480000);
      expect(cart.totalMontoFormateado, '\$480.000');

      final item = cart.items.first as InventariadoCartItem;
      expect(item.precioFinal, 480000);
      expect(item.subtotal, 480000);
    });

    test('Permite agregar y modificar notas de preparación', () {
      final cart = CartController.instance;
      cart.agregarInventariado(itemTest1, notas: 'Entregar con poleas instaladas');

      final item = cart.items.first as InventariadoCartItem;
      expect(item.notasPreparacion, 'Entregar con poleas instaladas');

      cart.actualizarNotas(itemTest1.idActivo, 'Entregar motor pelado sin accesorios');
      expect(item.notasPreparacion, 'Entregar motor pelado sin accesorios');
    });

    test('Agregar artículo de Venta Libre / Misceláneo', () {
      final cart = CartController.instance;
      cart.agregarVentaLibre(
        descripcion: 'Pernos Culata Especiales',
        monto: 15000,
        cantidad: 4,
        observacion: 'Para culata Toyota Yaris',
      );

      expect(cart.totalItems, 4);
      expect(cart.totalMonto, 60000); // 15.000 * 4
      expect(cart.totalMontoFormateado, '\$60.000');

      final item = cart.items.first as VentaLibreCartItem;
      expect(item.esInventariado, isFalse);
      expect(item.descripcion, 'Pernos Culata Especiales');
      expect(item.monto, 15000);
      expect(item.cantidad, 4);
      expect(item.subtotal, 60000);
      expect(item.subtitulo, 'Para culata Toyota Yaris');
    });

    test('Carrito Híbrido: Combina inventariado y venta libre correctamente', () {
      final cart = CartController.instance;

      // 1. Activo inventariado ($520.000)
      cart.agregarInventariado(itemTest1);

      // 2. Otro activo inventariado ($380.000)
      cart.agregarInventariado(itemTest2);

      // 3. Venta libre ($25.000 x 2 = $50.000)
      cart.agregarVentaLibre(
        descripcion: 'Líquido de Frenos DOT4',
        monto: 25000,
        cantidad: 2,
      );

      // Total items: 1 + 1 + 2 = 4
      expect(cart.totalItems, 4);
      // Total monto: 520.000 + 380.000 + 50.000 = 950.000
      expect(cart.totalMonto, 950000);
      expect(cart.totalMontoFormateado, '\$950.000');
    });

    test('Actualizar cantidad de venta libre y eliminación con cantidad <= 0', () {
      final cart = CartController.instance;
      cart.agregarVentaLibre(
        descripcion: 'Mano de obra desmontaje',
        monto: 30000,
        cantidad: 1,
      );

      final itemId = cart.items.first.id;
      cart.actualizarCantidad(itemId, 3);
      expect(cart.totalItems, 3);
      expect(cart.totalMonto, 90000);

      // Reducir a 0 debe eliminarlo del carrito
      cart.actualizarCantidad(itemId, 0);
      expect(cart.estaVacio, isTrue);
      expect(cart.totalItems, 0);
    });

    test('Eliminar ítem específico y vaciar carrito', () {
      final cart = CartController.instance;
      cart.agregarInventariado(itemTest1);
      cart.agregarInventariado(itemTest2);

      expect(cart.items.length, 2);

      cart.eliminarItem(itemTest1.idActivo);
      expect(cart.items.length, 1);
      expect(cart.estaEnCarrito(itemTest1.idActivo), isFalse);
      expect(cart.estaEnCarrito(itemTest2.idActivo), isTrue);

      cart.vaciarCarrito();
      expect(cart.estaVacio, isTrue);
    });

    test('Serialización toJson genera estructura adecuada para backend', () {
      final cart = CartController.instance;
      cart.agregarInventariado(itemTest1, precioFinal: 500000, notas: 'Revisado');
      cart.agregarVentaLibre(descripcion: 'Aceite 10W40', monto: 35000, cantidad: 1);

      final jsonInventariado = cart.items[0].toJson();
      expect(jsonInventariado['tipo'], 'inventariado');
      expect(jsonInventariado['id_activo'], itemTest1.idActivo);
      expect(jsonInventariado['precio_final'], 500000);
      expect(jsonInventariado['notas_preparacion'], 'Revisado');

      final jsonVentaLibre = cart.items[1].toJson();
      expect(jsonVentaLibre['tipo'], 'venta_libre');
      expect(jsonVentaLibre['descripcion'], 'Aceite 10W40');
      expect(jsonVentaLibre['monto_unitario'], 35000);
      expect(jsonVentaLibre['subtotal'], 35000);
    });
  });

  group('VentaLibreDialog Widget Tests', () {
    testWidgets('Renderiza formulario y valida campos requeridos', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VentaLibreDialog(),
          ),
        ),
      );

      expect(find.text('Venta Libre'), findsOneWidget);
      expect(find.text('DESCRIPCIÓN DEL ARTÍCULO / SERVICIO *'), findsOneWidget);
      expect(find.text('MONTO UNITARIO (CLP) *'), findsOneWidget);
      expect(find.text('CANTIDAD'), findsOneWidget);
      expect(find.text('Agregar al Carrito'), findsOneWidget);

      // Intentar enviar sin datos debe mostrar validación
      await tester.tap(find.text('Agregar al Carrito'));
      await tester.pump();

      expect(find.text('Ingresa una descripción para el ítem'), findsOneWidget);
    });

    testWidgets('Ingresa datos válidos e inserta en CartController', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VentaLibreDialog(),
          ),
        ),
      );

      // Escribir descripción
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ej. Perno culata especial, Mano de obra, etc.'),
        'Mano de Obra Desarme',
      );

      // Escribir monto
      await tester.enterText(
        find.widgetWithText(TextFormField, '0'),
        '45000',
      );

      // Incrementar cantidad a 2 con el botón '+'
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(find.text('2'), findsOneWidget);

      // Presionar Agregar al Carrito
      await tester.tap(find.text('Agregar al Carrito'));
      await tester.pump();

      // Verificar inserción en CartController
      expect(CartController.instance.totalItems, 2);
      expect(CartController.instance.totalMonto, 90000); // 45.000 * 2
      expect(CartController.instance.items.first.titulo, 'Mano de Obra Desarme');
    });

    testWidgets('VentaLibreDialog muestra error y rechaza ítem si el carrito contiene Venta en Verde', (tester) async {
      // 1. Configurar carrito con un Backorder
      final okBo = CartController.instance.agregarReservaBackorder(
        idCategoria: 1,
        categoriaNombre: 'Motor',
        marca: 'Subaru',
        modelo: 'Impreza',
        precioAcordado: 800000,
      );
      expect(okBo, isTrue);
      expect(CartController.instance.tieneVentaEnVerde, isTrue);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VentaLibreDialog(),
          ),
        ),
      );

      // Llenar formulario
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ej. Perno culata especial, Mano de obra, etc.'),
        'Filtro de Aceite',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, '0'),
        '10000',
      );

      // Presionar Agregar al Carrito
      await tester.tap(find.text('Agregar al Carrito'));
      await tester.pump();

      // Debe mostrar error indicando que las ventas en verde van solas
      expect(find.text('No se pudo agregar el ítem manual. El pedido contiene una Venta en Verde (las ventas en verde van solas).'), findsOneWidget);

      // El carrito sigue teniendo únicamente la venta en verde (1 ítem)
      expect(CartController.instance.items.length, 1);
      expect(CartController.instance.items.first, isA<ReservaBackorderCartItem>());
    });

    test('Reglas de Exclusividad: Venta en Verde y repuestos regulares no pueden combinarse', () {
      final cart = CartController.instance;

      // Caso A: Carrito con producto regular no permite Venta en Verde
      cart.agregarVentaLibre(descripcion: 'Bujía', monto: 5000);
      expect(cart.tieneItemsRegulares, isTrue);
      expect(cart.puedeAgregarVentaEnVerde, isFalse);

      final intentoVentaVerde = cart.agregarReservaBackorder(
        idCategoria: 1,
        categoriaNombre: 'Motor',
        marca: 'Toyota',
        modelo: 'Corolla',
        precioAcordado: 900000,
      );
      expect(intentoVentaVerde, isFalse);
      expect(cart.items.length, 1);

      // Vaciar
      cart.vaciarCarrito();

      // Caso B: Carrito con Venta en Verde no permite agregar inventariado ni manual
      final okBo = cart.agregarReservaBackorder(
        idCategoria: 2,
        categoriaNombre: 'Caja de Cambios',
        marca: 'Nissan',
        modelo: 'Navara',
        precioAcordado: 600000,
      );
      expect(okBo, isTrue);
      expect(cart.tieneVentaEnVerde, isTrue);
      expect(cart.puedeAgregarItemRegular, isFalse);

      final intentoManual = cart.agregarVentaLibre(descripcion: 'Golilla', monto: 1000);
      expect(intentoManual, isFalse);

      final intentoInv = cart.agregarInventariado(itemTest1);
      expect(intentoInv, isFalse);

      expect(cart.items.length, 1);
      expect(cart.items.first, isA<ReservaBackorderCartItem>());
    });
  });
}
