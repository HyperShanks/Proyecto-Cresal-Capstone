// frontend/test/features/ventas/correcciones_tasacion_carrito_test.dart
// Tests automatizados para verificar:
// 1. Limpieza de duplicidad en títulos de tasación (tituloVehiculo).
// 2. Incorporación de galpón en ubicación física de tasación (ubicacionDisplay).
// 3. Ciclo de vida de misceláneos sin resurrección de ítems eliminados.
// 4. Preservación y sincronización de pasillo y pallet en ítems inventariados.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:frontend/features/ventas/models/pendiente_precio_model.dart';
import 'package:frontend/features/ventas/controllers/cart_controller.dart';
import 'package:frontend/features/ventas/controllers/checkout_wizard_controller.dart';
import 'package:frontend/features/ventas/models/checkout_wizard_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  group('Corrección 1: Modelo de Tasación (ActivoPendientePrecioModel)', () {
    test('tituloVehiculo elimina la duplicidad de la categoría en el título', () {
      final itemMotor = ActivoPendientePrecioModel(
        idActivo: 'act-1',
        skuQrFisico: 'SKU-M-01',
        idCategoria: 1,
        nombreCategoria: 'Motor',
        idSucursalActual: 1,
        nombreSucursal: 'Casa Matriz',
        marca: 'Toyota',
        modelo: 'Yaris',
        anio: 2020,
        tituloRepuesto: 'Motor - Toyota Yaris 2020',
        estadoActivo: 'Paletizado',
      );

      // Debe retornar el vehículo limpio sin repetir "Motor"
      expect(itemMotor.tituloVehiculo, equals('Toyota Yaris 2020'));

      final itemCaja = ActivoPendientePrecioModel(
        idActivo: 'act-2',
        skuQrFisico: 'SKU-C-01',
        idCategoria: 2,
        nombreCategoria: 'Caja de cambios',
        idSucursalActual: 1,
        nombreSucursal: 'Casa Matriz',
        marca: 'Hyundai',
        modelo: 'Accent',
        anio: 2019,
        tituloRepuesto: 'Caja de cambios - Hyundai Accent 2019',
        estadoActivo: 'Paletizado',
      );

      expect(itemCaja.tituloVehiculo, equals('Hyundai Accent 2019'));
    });

    test('ubicacionDisplay incluye Galpón, Pasillo y Pallet formateados', () {
      final item = ActivoPendientePrecioModel(
        idActivo: 'act-3',
        skuQrFisico: 'SKU-03',
        idCategoria: 1,
        nombreCategoria: 'Motor',
        idSucursalActual: 1,
        nombreSucursal: 'Casa Matriz',
        ubicacionGalpon: 'G1',
        ubicacionPasillo: 'P-02',
        ubicacionPallet: 'PL-05',
        tituloRepuesto: 'Motor - Nissan Navara 2018',
        estadoActivo: 'Paletizado',
      );

      expect(item.ubicacionDisplay, contains('Galpón: G1'));
      expect(item.ubicacionDisplay, contains('Pasillo: P-02'));
      expect(item.ubicacionDisplay, contains('Pallet: PL-05'));
    });

    test('fromJson deserializa ubicacion_galpon correctamente', () {
      final json = {
        'id_activo': 'act-4',
        'sku_qr_fisico': 'SKU-04',
        'id_categoria': 1,
        'nombre_categoria': 'Motor',
        'id_sucursal_actual': 1,
        'nombre_sucursal': 'Casa Matriz',
        'ubicacion_galpon': 'Galpón 3',
        'ubicacion_pasillo': 'Pasillo 4',
        'ubicacion_pallet': 'Pallet 12',
        'titulo_repuesto': 'Motor - Chevrolet Sail 2017',
        'estado_activo': 'Paletizado',
      };

      final model = ActivoPendientePrecioModel.fromJson(json);
      expect(model.ubicacionGalpon, equals('Galpón 3'));
      expect(model.ubicacionDisplay, equals('Galpón 3 • Pasillo 4 • Pallet 12'));
    });
  });

  group('Corrección 2: Misceláneos en Carrito - Eliminación y no resurrección', () {
    late CartController cart;

    setUp(() {
      cart = CartController.instance;
      cart.vaciarCarrito();
    });

    test('Eliminar un ítem misceláneo lo remueve de forma definitiva', () {
      // 1. Agregar misceláneo A
      cart.agregarVentaLibre(
        descripcion: 'Aceite 10W40',
        monto: 25000,
        cantidad: 1,
      );
      expect(cart.items.length, equals(1));
      expect(cart.items.first.titulo, equals('Aceite 10W40'));

      final idPrimerItem = cart.items.first.id;

      // 2. Eliminar misceláneo A
      cart.eliminarItem(idPrimerItem);
      expect(cart.items.isEmpty, isTrue);

      // 3. Agregar misceláneo B
      cart.agregarVentaLibre(
        descripcion: 'Líquido de Frenos DOT4',
        monto: 8000,
        cantidad: 2,
      );

      // El ítem A NO debe reaparecer; solo debe existir el ítem B
      expect(cart.items.length, equals(1));
      expect(cart.items.first.titulo, equals('Líquido de Frenos DOT4'));
      expect(cart.items.any((i) => i.titulo == 'Aceite 10W40'), isFalse);
    });
  });

  group('Corrección 3: Pasillo y Pallet en CheckoutWizardController', () {
    late CheckoutWizardController wizardCtrl;

    setUp(() {
      wizardCtrl = CheckoutWizardController();
    });

    test('addItemInventariado almacena correctamente pasillo y pallet sin dejarlos en null', () {
      wizardCtrl.addItemInventariado(
        idActivo: 'act-10',
        sku: 'SKU-MOT-10',
        descripcion: 'Motor Suzuki Swift 1.2',
        precio: 850000,
        pasillo: 'P-03',
        pallet: 'PL-08',
      );

      expect(wizardCtrl.itemsInventariados.length, equals(1));
      final item = wizardCtrl.itemsInventariados.first;
      expect(item['pasillo'], equals('P-03'));
      expect(item['pallet'], equals('PL-08'));
    });
  });

  group('Corrección 4: Reactividad del mensaje de error en carrito al agregar items', () {
    late CheckoutWizardController wizardCtrl;

    setUp(() {
      wizardCtrl = CheckoutWizardController();
    });

    test('Error al presionar Siguiente sin items desaparece reactivamente al agregar item inventariado', () {
      // 1. Intentar avanzar con carrito vacío
      final avanzo = wizardCtrl.nextStep();
      expect(avanzo, isFalse);
      expect(wizardCtrl.errorMessage, equals('Debes agregar al menos un artículo o servicio para proceder.'));

      // 2. Agregar un ítem inventariado
      wizardCtrl.addItemInventariado(
        idActivo: 'act-20',
        sku: 'SKU-ALT-20',
        descripcion: 'Alternador Bosch',
        precio: 95000,
      );

      // 3. El mensaje DEBE desaparecer inmediatamente (reactivo) sin requerir otra acción
      expect(wizardCtrl.errorMessage, isNull);
      expect(wizardCtrl.totalItemsCount, equals(1));
    });

    test('Error desaparece reactivamente al agregar item manual', () {
      final avanzo = wizardCtrl.nextStep();
      expect(avanzo, isFalse);
      expect(wizardCtrl.errorMessage, equals('Debes agregar al menos un artículo o servicio para proceder.'));

      wizardCtrl.addItemManual(
        const ItemManualModel(
          descripcion: 'Filtro de Aceite Mann',
          cantidad: 1,
          precioUnitario: 12000,
          precioFinal: 12000,
        ),
      );

      expect(wizardCtrl.errorMessage, isNull);
      expect(wizardCtrl.totalItemsCount, equals(1));
    });

    test('Error desaparece reactivamente al agregar reserva backorder', () {
      final avanzo = wizardCtrl.nextStep();
      expect(avanzo, isFalse);
      expect(wizardCtrl.errorMessage, equals('Debes agregar al menos un artículo o servicio para proceder.'));

      wizardCtrl.addReservaBackorder(
        const ReservaBackorderModel(
          idCategoriaRequerida: 1,
          categoriaNombre: 'Motor',
          marcaRequerida: 'Nissan',
          modeloRequerido: 'Navara',
          anioRequerido: 2018,
          precioAcordado: 1200000,
          montoAbonado: 300000,
        ),
      );

      expect(wizardCtrl.errorMessage, isNull);
      expect(wizardCtrl.totalItemsCount, equals(1));
    });
  });
}

