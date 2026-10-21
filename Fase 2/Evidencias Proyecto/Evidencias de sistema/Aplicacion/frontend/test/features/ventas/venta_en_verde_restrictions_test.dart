// frontend/test/features/ventas/venta_en_verde_restrictions_test.dart
// Tests automatizados para verificar las restricciones de Venta en Verde (Consumidor Final bloqueado y datos obligatorios)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/ventas/controllers/cart_controller.dart';
import 'package:frontend/features/ventas/controllers/checkout_wizard_controller.dart';
import 'package:frontend/features/ventas/models/checkout_wizard_models.dart';
import 'package:frontend/features/ventas/presentation/screens/checkout_wizard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockStorage = {};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'read') {
          final key = (methodCall.arguments as Map?)?['key'] as String?;
          if (key != null && mockStorage.containsKey(key)) {
            return mockStorage[key];
          }
          if (key == 'access_token') return 'fake-test-jwt-token';
          return null;
        }
        if (methodCall.method == 'write') {
          final key = (methodCall.arguments as Map?)?['key'] as String?;
          final value = (methodCall.arguments as Map?)?['value'] as String?;
          if (key != null && value != null) {
            mockStorage[key] = value;
          }
          return null;
        }
        return null;
      },
    );
  });

  setUp(() {
    CartController.instance.vaciarCarrito();
  });

  tearDown(() {
    CartController.instance.vaciarCarrito();
  });

  group('CheckoutWizardController - Restricciones Venta en Verde', () {
    late CheckoutWizardController controller;

    setUp(() {
      controller = CheckoutWizardController();
    });

    test('tieneVentaEnVerde detecta reservas por encargo', () {
      expect(controller.tieneVentaEnVerde, isFalse);

      controller.addReservaBackorder(
        const ReservaBackorderModel(
          idCategoriaRequerida: 1,
          categoriaNombre: 'Motor',
          marcaRequerida: 'Toyota',
          modeloRequerido: 'Yaris',
          anioRequerido: 2020,
          precioAcordado: 1200000,
          montoAbonado: 600000,
        ),
      );

      expect(controller.tieneVentaEnVerde, isTrue);
    });

    test('validateStep2 rechaza Consumidor Final (RUT 6.666.666-6) si hay Venta en Verde', () {
      controller.addReservaBackorder(
        const ReservaBackorderModel(
          idCategoriaRequerida: 1,
          categoriaNombre: 'Motor',
          marcaRequerida: 'Toyota',
          modeloRequerido: 'Yaris',
          precioAcordado: 1000000,
        ),
      );

      controller.setCliente(
        const ClienteWizardModel(
          idCliente: 'cli-cf',
          rut: '6.666.666-6',
          nombres: 'Consumidor',
          apellidos: 'Final',
          telefono: '+56912345678',
          correo: 'consumidor@final.cl',
        ),
      );

      expect(controller.validateStep2(), isFalse);
    });

    test('validateStep2 aprueba cliente sin teléfono ni correo en Venta en Verde', () {
      controller.addReservaBackorder(
        const ReservaBackorderModel(
          idCategoriaRequerida: 1,
          categoriaNombre: 'Motor',
          marcaRequerida: 'Nissan',
          modeloRequerido: 'Versa',
          precioAcordado: 800000,
        ),
      );

      // Teléfono y correo vacíos (son opcionales)
      controller.setCliente(
        const ClienteWizardModel(
          idCliente: 'cli-1',
          rut: '18.111.222-3',
          nombres: 'Carlos',
          apellidos: 'Pérez',
          telefono: '',
          correo: '',
        ),
      );
      expect(controller.validateStep2(), isTrue);
    });

    test('validateStep2 rechaza teléfono inválido menor a 8 dígitos si se ingresa en Venta en Verde', () {
      controller.addReservaBackorder(
        const ReservaBackorderModel(
          idCategoriaRequerida: 1,
          categoriaNombre: 'Motor',
          marcaRequerida: 'Nissan',
          modeloRequerido: 'Versa',
          precioAcordado: 800000,
        ),
      );

      // Teléfono menor a 8 dígitos cuando no está vacío
      controller.setCliente(
        const ClienteWizardModel(
          idCliente: 'cli-1',
          rut: '18.111.222-3',
          nombres: 'Carlos',
          apellidos: 'Pérez',
          telefono: '12345',
          correo: '',
        ),
      );
      expect(controller.validateStep2(), isFalse);
    });

    test('validateStep2 rechaza correo electrónico inválido si se ingresa en Venta en Verde', () {
      controller.addReservaBackorder(
        const ReservaBackorderModel(
          idCategoriaRequerida: 1,
          categoriaNombre: 'Motor',
          marcaRequerida: 'Nissan',
          modeloRequerido: 'Versa',
          precioAcordado: 800000,
        ),
      );

      controller.setCliente(
        const ClienteWizardModel(
          idCliente: 'cli-1',
          rut: '18.111.222-3',
          nombres: 'Carlos',
          apellidos: 'Pérez',
          telefono: '+56912345678',
          correo: 'correo_invalido',
        ),
      );
      expect(controller.validateStep2(), isFalse);
    });

    test('validateStep2 aprueba cliente con todos sus datos completos en Venta en Verde', () {
      controller.addReservaBackorder(
        const ReservaBackorderModel(
          idCategoriaRequerida: 1,
          categoriaNombre: 'Motor',
          marcaRequerida: 'Nissan',
          modeloRequerido: 'Versa',
          precioAcordado: 800000,
        ),
      );

      controller.setCliente(
        const ClienteWizardModel(
          idCliente: 'cli-1',
          rut: '18.111.222-3',
          nombres: 'Carlos',
          apellidos: 'Pérez',
          telefono: '+56912345678',
          correo: 'carlos.perez@test.cl',
        ),
      );
      expect(controller.validateStep2(), isTrue);
    });

    test('nextStep() muestra mensaje de error explicativo para Venta en Verde', () {
      controller.addReservaBackorder(
        const ReservaBackorderModel(
          idCategoriaRequerida: 1,
          categoriaNombre: 'Motor',
          marcaRequerida: 'Nissan',
          modeloRequerido: 'Versa',
          precioAcordado: 800000,
        ),
      );

      // Avanzar a paso 1 (Cliente)
      expect(controller.nextStep(), isTrue);
      expect(controller.currentStep, equals(1));

      // Intentar avanzar a paso 2 sin cliente
      expect(controller.nextStep(), isFalse);
      expect(controller.errorMessage, contains('Las compras en verde requieren obligatoriamente registrar los datos del cliente'));
    });
  });

  group('CheckoutWizardScreen - UI Restricciones Venta en Verde', () {
    testWidgets('Muestra banner verde y bloquea activación de Consumidor Final con SnackBar', (tester) async {
      // 1. Agregar Backorder a CartController
      CartController.instance.agregarReservaBackorder(
        idCategoria: 1,
        categoriaNombre: 'Motor',
        marca: 'Toyota',
        modelo: 'Hilux',
        anio: 2021,
        precioAcordado: 2500000,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: CheckoutWizardScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // En Paso 0 (Artículos), avanzar a Paso 1 (Cliente)
      final btnSiguiente = find.byKey(const Key('btn_siguiente_wizard'));
      expect(btnSiguiente, findsOneWidget);
      await tester.tap(btnSiguiente);
      await tester.pumpAndSettle();

      // Verificar que el banner de Venta en Verde está presente
      expect(find.textContaining('Venta en Verde activa:'), findsOneWidget);
      expect(find.textContaining('obligatorio registrar al cliente titular'), findsOneWidget);

      // Verificar subtítulo informativo en la opción de Consumidor Final
      expect(find.text('No disponible en Venta en Verde (se requiere cliente identificado con RUT)'), findsOneWidget);

      // Intentar tocar el switch o contenedor de Consumidor Final
      final switchFinder = find.byKey(const Key('switch_cliente_anonimo'));
      expect(switchFinder, findsOneWidget);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      // Debe mostrar SnackBar con advertencia
      expect(
        find.text('Las compras en verde requieren obligatoriamente registrar a un cliente identificado con RUT, nombre y apellido.'),
        findsOneWidget,
      );

      // El campo RUT NO debe haberse autocompletado con 6.666.666-6
      expect(find.text('6.666.666-6'), findsNothing);
    });
  });
}
