// frontend/test/features/ventas/checkout_wizard_test.dart
// Tests automatizados para el Checkout Wizard por Pasos y Backorders (SPEC-HU-05)

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter/services.dart';
import 'package:frontend/features/ventas/models/checkout_wizard_models.dart';
import 'package:frontend/features/ventas/controllers/checkout_wizard_controller.dart';
import 'package:frontend/features/ventas/services/ventas_service.dart';
import 'package:frontend/features/ventas/presentation/screens/checkout_wizard_screen.dart';
import 'package:frontend/features/ventas/presentation/widgets/modal_backorder_form.dart';
import 'package:frontend/features/ventas/presentation/widgets/dialogo_advertencia_consumidor_final.dart';

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
  group('SPEC-HU-05: CheckoutWizardController - Pruebas Unitarias de Estado', () {
    late CheckoutWizardController controller;

    setUp(() {
      controller = CheckoutWizardController();
    });

    test('Estado inicial está en el Paso 0 con totales en 0', () {
      expect(controller.currentStep, equals(0));
      expect(controller.totalItemsCount, equals(0));
      expect(controller.totalVenta, equals(0));
      expect(controller.montoPendiente, equals(0));
      expect(controller.tipoEntrega, equals('Retiro'));
    });

    test(
      'Agregar repuestos inventariados, manuales y backorders calcula subtotales correctamente',
      () {
        // 1. Activo inventariado
        controller.addItemInventariado(
          idActivo: 'act-001',
          sku: 'MOT-TOY-001',
          descripcion: 'Motor Toyota Corolla 1.8',
          precio: 650000,
          pasillo: 'P-02',
          pallet: 'PAL-05',
        );
        expect(controller.subtotalInventario, equals(650000));

        // 2. Ítem manual
        controller.addItemManual(
          const ItemManualModel(
            descripcion: 'Aceite 5W30 Sintético',
            cantidad: 2,
            precioUnitario: 25000,
            precioFinal: 50000,
          ),
        );
        expect(controller.subtotalManuales, equals(50000));

        // 3. Reserva Backorder con abono
        controller.addReservaBackorder(
          const ReservaBackorderModel(
            idCategoriaRequerida: 2,
            categoriaNombre: 'Caja de Cambios',
            marcaRequerida: 'Toyota',
            modeloRequerido: 'Corolla',
            anioRequerido: 2021,
            precioAcordado: 400000,
            montoAbonado: 150000,
          ),
        );
        expect(controller.subtotalReservas, equals(400000));

        // Totales: 1 inventariado + 2 unidades manuales + 1 reserva = 4
        expect(controller.totalItemsCount, equals(4));
        expect(
          controller.totalVenta,
          equals(1100000),
        ); // 650.000 + 50.000 + 400.000
        expect(controller.abonoReservas, equals(150000));
        expect(
          controller.montoPendiente,
          equals(950000),
        ); // 1.100.000 - 150.000
      },
    );

    test(
      'Descuento por Vale a Favor descuenta del totalVenta y recalcula montoPendiente',
      () {
        controller.addItemInventariado(
          idActivo: 'act-001',
          sku: 'MOT-TOY-001',
          descripcion: 'Motor Toyota Corolla 1.8',
          precio: 100000,
        );
        expect(controller.subtotal, equals(100000));
        expect(controller.totalVenta, equals(100000));

        // Aplicar descuento por vale a favor
        controller.setDescuento(20000);
        expect(controller.descuento, equals(20000));
        expect(controller.totalVenta, equals(80000));
        expect(controller.montoPendiente, equals(80000));

        // Agregar abono adicional
        controller.setAbonoAdicional(30000);
        expect(controller.montoPendiente, equals(50000));

        // Descuento mayor al subtotal se ajusta a 0 (nunca negativo)
        controller.setDescuento(150000);
        expect(controller.totalVenta, equals(0));
        expect(controller.montoPendiente, equals(0));
      },
    );

    test('Validación de paso impide avanzar sin ítems (Paso 0 -> Paso 1)', () {
      expect(controller.nextStep(), isFalse);
      expect(controller.currentStep, equals(0));
      expect(controller.errorMessage, contains('al menos un artículo'));

      controller.addItemInventariado(
        idActivo: 'act-001',
        sku: 'SKU-1',
        descripcion: 'Alternador',
        precio: 80000,
      );

      expect(controller.nextStep(), isTrue);
      expect(controller.currentStep, equals(1));
    });

    test(
      'Validación de paso impide avanzar sin cliente asignado (Paso 1 -> Paso 2)',
      () {
        controller.addItemInventariado(
          idActivo: 'act-001',
          sku: 'SKU-1',
          descripcion: 'Alternador',
          precio: 80000,
        );
        controller.nextStep(); // A paso 1

        expect(controller.nextStep(), isFalse);
        expect(controller.currentStep, equals(1));
        expect(controller.errorMessage, contains('cliente'));

        controller.setCliente(
          const ClienteWizardModel(
            idCliente: 'cli-001',
            rut: '19.888.777-6',
            nombres: 'Roberto',
            apellidos: 'López',
            telefono: '+56911223344',
            consentimientoLegal: true,
            estado: 'Activo',
          ),
        );

        expect(controller.nextStep(), isTrue);
        expect(controller.currentStep, equals(2));
      },
    );

    test('Retroceder pasos preserva los datos ingresados', () {
      controller.addItemInventariado(
        idActivo: 'act-001',
        sku: 'SKU-1',
        descripcion: 'Alternador',
        precio: 80000,
      );
      controller.setCliente(
        const ClienteWizardModel(
          idCliente: 'cli-001',
          rut: '19.888.777-6',
          nombres: 'Roberto',
          apellidos: 'López',
          consentimientoLegal: true,
          estado: 'Activo',
        ),
      );

      controller.nextStep(); // A paso 1
      controller.nextStep(); // A paso 2
      expect(controller.currentStep, equals(2));

      // Retroceder a Paso 0
      controller.previousStep();
      controller.previousStep();
      expect(controller.currentStep, equals(0));

      // Los datos siguen intactos
      expect(controller.itemsInventariados.length, equals(1));
      expect(controller.clienteSeleccionado?.nombres, equals('Roberto'));
    });

    test(
      'Validación de abonos impide ingresar un monto mayor al total de la venta (Paso 2 -> Paso 3)',
      () {
        controller.addItemInventariado(
          idActivo: 'act-001',
          sku: 'SKU-1',
          descripcion: 'Alternador',
          precio: 80000,
        );
        controller.setCliente(
          const ClienteWizardModel(
            idCliente: 'cli-001',
            rut: '19.888.777-6',
            nombres: 'Roberto',
            apellidos: 'López',
            consentimientoLegal: true,
            estado: 'Activo',
          ),
        );
        controller.nextStep(); // A paso 1
        controller.nextStep(); // A paso 2 (Abonos)
        expect(controller.currentStep, equals(2));

        // Asignar abono mayor al total de la venta
        controller.setAbonoAdicional(100000);
        expect(controller.validateStep3(), isFalse);
        expect(controller.nextStep(), isFalse);
        expect(
          controller.errorMessage,
          contains('monto de abono no puede ser superior'),
        );

        // Ajustar abono válido
        controller.setAbonoAdicional(50000);
        expect(controller.validateStep3(), isTrue);
        expect(controller.nextStep(), isTrue);
        expect(controller.currentStep, equals(3));
      },
    );
  });

  group('SPEC-HU-05: VentasService.processCheckoutWizard - HTTP Mock', () {
    test(
      'Envía payload consolidado y deserializa respuesta 201 Created',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.url.path, contains('/checkout-wizard'));
          expect(request.method, equals('POST'));

          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['total_venta'], equals(500000));
          expect(body['tipo_entrega'], equals('Retiro'));

          return http.Response(
            jsonEncode({
              'id_orden': 'a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d',
              'estado': 'Reservada',
              'total_venta': 500000,
              'monto_pendiente': 350000,
              'abono_requerido': 150000,
              'reservas_generadas': 1,
              'activos_reservados': 0,
              'despacho_generado': false,
              'msg': 'Orden generada exitosamente.',
            }),
            201,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });

        const req = CheckoutWizardRequestModel(
          idCliente: 'cli-001',
          tipoEntrega: 'Retiro',
          totalVenta: 500000,
          montoPendiente: 350000,
          reservas: [
            ReservaBackorderModel(
              idCategoriaRequerida: 1,
              marcaRequerida: 'Nissan',
              modeloRequerido: 'Sentra',
              precioAcordado: 500000,
              montoAbonado: 150000,
            ),
          ],
        );

        final response = await VentasService.processCheckoutWizard(
          req,
          client: mockClient,
        );
        expect(
          response.idOrden,
          equals('a1b2c3d4-e5f6-7a8b-9c0d-1e2f3a4b5c6d'),
        );
        expect(response.estado, equals('Reservada'));
        expect(response.reservasGeneradas, equals(1));
        expect(response.montoPendiente, equals(350000));
        expect(response.abonoRequerido, equals(150000));
      },
    );
  });

  group('SPEC-HU-05: ModalBackorderForm & CheckoutWizardScreen Widget Tests', () {
    testWidgets(
      'ModalBackorderForm renderiza campos y valida entradas obligatorias',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => ModalBackorderForm.mostrar(context),
                  child: const Text('Abrir Modal'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir Modal'));
        await tester.pumpAndSettle();

        expect(find.text('Venta en Verde'), findsOneWidget);
        expect(find.text('AÑADIR RESERVA'), findsOneWidget);

        // Intentar guardar con campos vacíos -> Valida campos requeridos
        await tester.tap(find.text('AÑADIR RESERVA'));
        await tester.pumpAndSettle();

        expect(find.text('Requerido'), findsWidgets);
      },
    );

    testWidgets(
      'ModalBackorderForm selector de categorías solo contiene Motor y Caja de Cambios',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => ModalBackorderForm.mostrar(context),
                  child: const Text('Abrir Modal'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir Modal'));
        await tester.pumpAndSettle();

        // Abrir el dropdown de categorías
        await tester.tap(find.text('Motor').first);
        await tester.pumpAndSettle();

        // Verificar que están disponibles únicamente Motor y Caja de Cambios
        expect(find.text('Motor'), findsWidgets);
        expect(find.text('Caja de Cambios'), findsWidgets);

        // Verificar que NO existen opciones adicionales descartadas
        expect(find.text('Culata'), findsNothing);
        expect(find.text('Alternador'), findsNothing);
        expect(find.text('Diferencial'), findsNothing);
        expect(find.text('Motor de Arranque'), findsNothing);
        expect(find.text('Computador ECU'), findsNothing);
      },
    );

    testWidgets(
      'ModalBackorderForm no renderiza campo de abono porque reside en Paso 4',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => ModalBackorderForm.mostrar(context),
                  child: const Text('Abrir Modal'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir Modal'));
        await tester.pumpAndSettle();

        // Debe mostrar Precio Acordado
        expect(find.text('Precio Acordado (\$) *'), findsOneWidget);

        // NO debe existir campo de Monto a Abonar en este formulario
        expect(find.text('Monto a Abonar (\$) *'), findsNothing);
        expect(find.textContaining('Monto a Abonar'), findsNothing);

        // Texto de información orienta al usuario hacia el Paso 4
        expect(find.textContaining('Paso 4'), findsOneWidget);
      },
    );

    testWidgets('CheckoutWizardScreen renderiza el Stepper de 5 pasos', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: CheckoutWizardScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Checkout Transaccional'), findsOneWidget);
      expect(find.text('Ítems'), findsOneWidget);
      expect(find.text('Cliente'), findsOneWidget);
      expect(find.text('Abonos'), findsOneWidget);
      expect(find.text('Confirmar'), findsOneWidget);
      expect(find.text('Venta en Verde'), findsOneWidget);
      expect(find.text('Venta libre'), findsOneWidget);
      expect(find.byKey(const Key('btn_siguiente_wizard')), findsNothing);
    });

    testWidgets(
      'CheckoutWizardScreen permite activar Consumidor Final y avanzar de paso a Abonos',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: CheckoutWizardScreen(
              initialInventario: [
                {
                  'id_activo': 'act-101',
                  'sku': 'SKU-101',
                  'descripcion': 'Alternador',
                  'precio': 120000,
                },
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Avanzar de Paso 0 a Paso 1 (Cliente CRM)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        expect(find.text('2. Datos del Cliente (Micro-CRM)'), findsOneWidget);
        expect(find.byKey(const Key('switch_cliente_anonimo')), findsOneWidget);

        // Activar Switch Consumidor Final -> Abre diálogo de advertencia de 3 segundos
        await tester.tap(find.byKey(const Key('switch_cliente_anonimo')));
        await tester.pumpAndSettle();

        expect(find.byType(DialogoAdvertenciaConsumidorFinal), findsOneWidget);
        expect(
          find.text(
            'Es vital para la empresa los datos del cliente, ¿estás seguro que quieres continuar?',
          ),
          findsOneWidget,
        );

        // Avanzar temporizador de 3 segundos en virtual time
        await tester.pump(const Duration(seconds: 3));
        await tester.tap(
          find.byKey(const Key('btn_confirmar_consumidor_final')),
        );
        await tester.pumpAndSettle();

        expect(find.textContaining('RUT 6.666.666-6'), findsOneWidget);

        // Avanzar a Paso 2 (Abonos)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        expect(
          find.text('3. Condiciones Comerciales y Abonos'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'CheckoutWizardScreen botón Venta libre abre VentaLibreDialog, agrega ítem y oculta botón Siguiente si está vacío',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: CheckoutWizardScreen()),
        );
        await tester.pumpAndSettle();

        // Cuando el carrito está vacío, el botón Siguiente NO aparece en pantalla
        expect(find.byKey(const Key('btn_siguiente_wizard')), findsNothing);

        // Abrir modal Venta libre
        await tester.tap(find.text('Venta libre'));
        await tester.pumpAndSettle();

        expect(find.text('Venta Libre'), findsOneWidget);
        expect(
          find.text('DESCRIPCIÓN DEL ARTÍCULO / SERVICIO *'),
          findsOneWidget,
        );
        expect(find.text('MONTO UNITARIO (CLP) *'), findsOneWidget);
        expect(find.text('CANTIDAD'), findsOneWidget);
        expect(find.text('Agregar al Carrito'), findsOneWidget);

        // Ingresar ítem de venta libre
        await tester.enterText(
          find.widgetWithText(
            TextFormField,
            'Ej. Perno culata especial, Mano de obra, etc.',
          ),
          'Aceite Motor 1L',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, '0'),
          '15000',
        );
        await tester.tap(find.text('Agregar al Carrito'));
        await tester.pumpAndSettle();

        expect(find.text('Aceite Motor 1L'), findsOneWidget);
        expect(find.textContaining('Cantidad: 1'), findsOneWidget);

        // Ahora que hay un artículo, el botón Siguiente aparece
        expect(find.byKey(const Key('btn_siguiente_wizard')), findsOneWidget);
      },
    );

    testWidgets(
      'CheckoutWizardScreen flujo completo de 4 pasos (Ítems -> Cliente -> Abonos -> Confirmar)',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: CheckoutWizardScreen(
              initialInventario: [
                {
                  'id_activo': 'act-101',
                  'sku': 'SKU-101',
                  'descripcion': 'Alternador',
                  'precio': 120000,
                },
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Paso 0 -> Paso 1 (Cliente)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        // Consumidor Final -> Abre modal y confirma tras 3 segundos
        await tester.tap(find.byKey(const Key('switch_cliente_anonimo')));
        await tester.pumpAndSettle();

        expect(find.byType(DialogoAdvertenciaConsumidorFinal), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        await tester.tap(
          find.byKey(const Key('btn_confirmar_consumidor_final')),
        );
        await tester.pumpAndSettle();

        // Paso 1 -> Paso 2 (Abonos)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        expect(
          find.text('3. Condiciones Comerciales y Abonos'),
          findsOneWidget,
        );

        // Paso 2 -> Paso 3 (Confirmar)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        expect(
          find.text('4. Revisión Final y Emisión de Orden'),
          findsOneWidget,
        );
        expect(
          find.text('Modalidad: Retiro en Mesón / Bodega'),
          findsOneWidget,
        );
        expect(find.text('TOTAL DE LA VENTA:'), findsOneWidget);
        // En venta convencional sin abono no se muestran filas de abono ni saldos
        expect(find.text('Abono a Pagar Hoy en Caja:'), findsNothing);
        expect(find.text('Saldo Pendiente:'), findsNothing);
        expect(find.text('CONFIRMAR Y EMITIR ORDEN'), findsOneWidget);
      },
    );

    testWidgets(
      'CheckoutWizardScreen flujo con Abono muestra Abono a Pagar Hoy en Caja, Saldo Pendiente y banner',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: CheckoutWizardScreen(
              initialInventario: [
                {
                  'id_activo': 'act-202',
                  'sku': 'SKU-202',
                  'descripcion': 'Compresor Aire',
                  'precio': 100000,
                },
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Paso 0 -> Paso 1 (Cliente)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        // Consumidor Final
        await tester.tap(find.byKey(const Key('switch_cliente_anonimo')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 3));
        await tester.tap(find.byKey(const Key('btn_confirmar_consumidor_final')));
        await tester.pumpAndSettle();

        // Paso 1 -> Paso 2 (Abonos)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        // Ingresar abono de 30.000
        final inputAbono = find.widgetWithText(TextField, 'Ej: 50.000 (0 para pagar total en caja)');
        await tester.enterText(inputAbono, '30000');
        await tester.pumpAndSettle();

        // En Paso 3 debe verse Abono Inicial Acordado y Saldo Pendiente
        expect(find.text('Abono Inicial Acordado:'), findsOneWidget);
        expect(find.text('Saldo Pendiente:'), findsOneWidget);

        // Paso 2 -> Paso 3 (Confirmar)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        expect(find.text('4. Revisión Final y Emisión de Orden'), findsOneWidget);
        expect(find.text('TOTAL DE LA VENTA:'), findsOneWidget);
        // Debe mostrar Abono a Pagar Hoy en Caja y Saldo Pendiente
        expect(find.text('Abono a Pagar Hoy en Caja:'), findsOneWidget);
        expect(find.text('Saldo Pendiente:'), findsOneWidget);
        expect(find.byKey(const Key('banner_instruccion_abono_step4')), findsOneWidget);
        // NO debe existir el rótulo confuso antiguo 'Saldo a Pagar en Caja:'
        expect(find.text('Saldo a Pagar en Caja:'), findsNothing);
      },
    );

    testWidgets(
      'DialogoAdvertenciaConsumidorFinal bloquea confirmación hasta agotar los 3s y permite cancelar',
      (tester) async {
        bool? resultado;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  resultado = await DialogoAdvertenciaConsumidorFinal.mostrar(
                    context,
                  );
                },
                child: const Text('ABRIR'),
              ),
            ),
          ),
        );

        // Abrir diálogo
        await tester.tap(find.text('ABRIR'));
        await tester.pump(); // Inicia diálogo

        expect(find.byType(DialogoAdvertenciaConsumidorFinal), findsOneWidget);
        expect(
          find.text(
            'Es vital para la empresa los datos del cliente, ¿estás seguro que quieres continuar?',
          ),
          findsOneWidget,
        );

        // Botón confirmar está deshabilitado con contador inicial (3s)
        final btnInicial = tester.widget<ElevatedButton>(
          find.byKey(const Key('btn_confirmar_consumidor_final')),
        );
        expect(btnInicial.onPressed, isNull);
        expect(find.textContaining('(3s)'), findsOneWidget);

        // Avanzar 1 segundo: debe mostrar (2s) y seguir deshabilitado
        await tester.pump(const Duration(seconds: 1));
        expect(find.textContaining('(2s)'), findsOneWidget);
        final btnMitad = tester.widget<ElevatedButton>(
          find.byKey(const Key('btn_confirmar_consumidor_final')),
        );
        expect(btnMitad.onPressed, isNull);

        // Avanzar los 2 segundos restantes (total 3s)
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('CONTINUAR'), findsOneWidget);
        final btnHabilitado = tester.widget<ElevatedButton>(
          find.byKey(const Key('btn_confirmar_consumidor_final')),
        );
        expect(btnHabilitado.onPressed, isNotNull);

        // Presionar confirmar
        await tester.tap(
          find.byKey(const Key('btn_confirmar_consumidor_final')),
        );
        await tester.pumpAndSettle();

        expect(resultado, isTrue);
      },
    );

    testWidgets(
      'DialogoAdvertenciaConsumidorFinal botón Volver y pedir datos cierra con false de inmediato',
      (tester) async {
        bool? resultado;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  resultado = await DialogoAdvertenciaConsumidorFinal.mostrar(
                    context,
                  );
                },
                child: const Text('ABRIR'),
              ),
            ),
          ),
        );

        await tester.tap(find.text('ABRIR'));
        await tester.pump();

        // Cancelar inmediatamente sin esperar los 10 segundos
        await tester.tap(
          find.byKey(const Key('btn_cancelar_consumidor_final')),
        );
        await tester.pumpAndSettle();

        expect(resultado, isFalse);
        expect(find.byType(DialogoAdvertenciaConsumidorFinal), findsNothing);
      },
    );

    testWidgets(
      'CheckoutWizardScreen cancelar modal de Consumidor Final NO activa switch',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: CheckoutWizardScreen(
              initialInventario: [
                {
                  'id_activo': 'act-1',
                  'sku': 'SKU-1',
                  'descripcion': 'Faro',
                  'precio': 50000,
                },
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Ir a Paso 1 (Cliente)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        // Tocar switch
        await tester.tap(find.byKey(const Key('switch_cliente_anonimo')));
        await tester.pumpAndSettle();

        expect(find.byType(DialogoAdvertenciaConsumidorFinal), findsOneWidget);

        // Cancelar en el diálogo
        await tester.tap(
          find.byKey(const Key('btn_cancelar_consumidor_final')),
        );
        await tester.pumpAndSettle();

        // Diálogo cerrado y campos vacíos sin RUT 6.666.666-6
        expect(find.byType(DialogoAdvertenciaConsumidorFinal), findsNothing);
        expect(find.textContaining('RUT 6.666.666-6'), findsNothing);
      },
    );

    testWidgets(
      'CheckoutWizardScreen selector de Responsable ES visible para rol Vendedor Online (id_rol == 7)',
      (tester) async {
        mockStorage['user_id_rol'] = '7';
        addTearDown(() => mockStorage.remove('user_id_rol'));

        await tester.pumpWidget(
          const MaterialApp(
            home: CheckoutWizardScreen(
              initialInventario: [
                {
                  'id_activo': 'act-1',
                  'sku': 'SKU-1',
                  'descripcion': 'Faro',
                  'precio': 50000,
                },
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Ir a Paso 1 (Cliente)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        // Debe aparecer la tarjeta de RESPONSABLE DE ENTREGA EN SUCURSAL
        expect(find.text('RESPONSABLE DE ENTREGA EN SUCURSAL'), findsOneWidget);
        expect(
          find.byKey(const Key('dropdown_responsable_entrega')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'CheckoutWizardScreen para Vendedor Online incluye opción Mesón General y permite emitir orden',
      (tester) async {
        mockStorage['user_id_rol'] = '7';
        addTearDown(() => mockStorage.remove('user_id_rol'));

        await tester.pumpWidget(
          const MaterialApp(
            home: CheckoutWizardScreen(
              initialInventario: [
                {
                  'id_activo': 'act-1',
                  'sku': 'SKU-1',
                  'descripcion': 'Faro',
                  'precio': 50000,
                },
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Ir a Paso 1 (Cliente)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        // Consumidor Final -> abre modal y confirma tras 3s
        await tester.ensureVisible(
          find.byKey(const Key('switch_cliente_anonimo')),
        );
        await tester.tap(find.byKey(const Key('switch_cliente_anonimo')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 3));
        await tester.tap(
          find.byKey(const Key('btn_confirmar_consumidor_final')),
        );
        await tester.pumpAndSettle();

        // Verificar que el dropdown de responsable tiene la opción Mesón General
        await tester.ensureVisible(
          find.byKey(const Key('dropdown_responsable_entrega')),
        );
        await tester.tap(find.byKey(const Key('dropdown_responsable_entrega')));
        await tester.pumpAndSettle();
        expect(find.text('Mesón General (Todos los vendedores)'), findsWidgets);
        // Seleccionar Mesón General
        await tester.tap(
          find.text('Mesón General (Todos los vendedores)').last,
        );
        await tester.pumpAndSettle();

        // Paso 1 -> Paso 2 (Abonos)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        // Paso 2 -> Paso 3 (Revisión)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        // En Paso 4 debe mostrar Responsable Entrega: Mesón General y botón habilitado
        expect(
          find.textContaining(
            'Responsable Entrega: Mesón General (Todos los vendedores)',
          ),
          findsOneWidget,
        );
        expect(find.text('CONFIRMAR Y EMITIR ORDEN'), findsOneWidget);

        final btnConfirmar = tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, 'CONFIRMAR Y EMITIR ORDEN'),
        );
        expect(btnConfirmar.onPressed, isNotNull);
      },
    );

    testWidgets(
      'CheckoutWizardScreen switch de Venta Referida ES visible en Paso 1 para rol Jefe de Ventas (id_rol == 6)',
      (tester) async {
        mockStorage['user_id_rol'] = '6';
        mockStorage['enrolled_user_id'] = 'user-jefe-123';
        addTearDown(() {
          mockStorage.remove('user_id_rol');
          mockStorage.remove('enrolled_user_id');
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: CheckoutWizardScreen(
              initialInventario: [
                {
                  'id_activo': 'act-1',
                  'sku': 'SKU-1',
                  'descripcion': 'Faro',
                  'precio': 50000,
                },
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Debe aparecer la tarjeta de VENTA REFERIDA / ATRIBUCIÓN en el Paso 1 (debajo de Venta en Verde y Venta libre)
        expect(find.text('VENTA REFERIDA / ATRIBUCIÓN'), findsOneWidget);
        expect(find.byKey(const Key('switch_venta_referida')), findsOneWidget);
        // NO debe aparecer la tarjeta de asignación obligatoria del online
        expect(
          find.byKey(const Key('dropdown_responsable_entrega')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'CheckoutWizardScreen switch de Venta Referida ES visible en Paso 1 para rol Vendedor Mesón (id_rol == 2)',
      (tester) async {
        mockStorage['user_id_rol'] = '2';
        mockStorage['enrolled_user_id'] = 'user-vendedor-456';
        addTearDown(() {
          mockStorage.remove('user_id_rol');
          mockStorage.remove('enrolled_user_id');
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: CheckoutWizardScreen(
              initialInventario: [
                {
                  'id_activo': 'act-1',
                  'sku': 'SKU-1',
                  'descripcion': 'Faro',
                  'precio': 50000,
                },
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // SÍ debe ser visible en Paso 1 para vendedor de mesón
        expect(find.text('VENTA REFERIDA / ATRIBUCIÓN'), findsOneWidget);
        expect(find.byKey(const Key('switch_venta_referida')), findsOneWidget);
        expect(
          find.byKey(const Key('dropdown_responsable_entrega')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'CheckoutWizardScreen switch de Venta Referida NO es visible para rol Vendedora Online (id_rol == 7)',
      (tester) async {
        mockStorage['user_id_rol'] = '7';
        mockStorage['enrolled_user_id'] = 'user-online-789';
        addTearDown(() {
          mockStorage.remove('user_id_rol');
          mockStorage.remove('enrolled_user_id');
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: CheckoutWizardScreen(
              initialInventario: [
                {
                  'id_activo': 'act-1',
                  'sku': 'SKU-1',
                  'descripcion': 'Faro',
                  'precio': 50000,
                },
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // En Paso 1 no debe verse venta referida
        expect(find.byKey(const Key('switch_venta_referida')), findsNothing);
      },
    );

    testWidgets(
      'CheckoutWizardScreen Vendedor activa Venta Referida en Paso 1 y muestra selector de titular y texto adecuado',
      (tester) async {
        mockStorage['user_id_rol'] = '2';
        mockStorage['enrolled_user_id'] = 'user-vendedor-456';
        addTearDown(() {
          mockStorage.remove('user_id_rol');
          mockStorage.remove('enrolled_user_id');
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: CheckoutWizardScreen(
              initialInventario: [
                {
                  'id_activo': 'act-1',
                  'sku': 'SKU-1',
                  'descripcion': 'Faro',
                  'precio': 50000,
                },
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Asegurar visibilidad del switch en Paso 1 y activarlo
        await tester.ensureVisible(
          find.byKey(const Key('switch_venta_referida')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('switch_venta_referida')));
        await tester.pumpAndSettle();

        // Dropdown de vendedor titular debe aparecer
        expect(
          find.byKey(const Key('dropdown_vendedor_titular')),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Tú (Vendedor) quedarás registrado para entregar físicamente',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'CheckoutWizardScreen Venta Referida activada muestra banner llamativo en Paso 4',
      (tester) async {
        mockStorage['user_id_rol'] = '2';
        mockStorage['enrolled_user_id'] = 'user-vendedor-456';
        addTearDown(() {
          mockStorage.remove('user_id_rol');
          mockStorage.remove('enrolled_user_id');
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: CheckoutWizardScreen(
              initialInventario: [
                {
                  'id_activo': 'act-1',
                  'sku': 'SKU-1',
                  'descripcion': 'Faro',
                  'precio': 50000,
                },
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Paso 1: Activar Venta Referida
        await tester.ensureVisible(
          find.byKey(const Key('switch_venta_referida')),
        );
        await tester.tap(find.byKey(const Key('switch_venta_referida')));
        await tester.pumpAndSettle();

        // Ir a Paso 2 (Cliente)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        // Activar consumidor final para poder continuar
        await tester.ensureVisible(
          find.byKey(const Key('switch_cliente_anonimo')),
        );
        await tester.tap(find.byKey(const Key('switch_cliente_anonimo')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 10));
        await tester.tap(
          find.byKey(const Key('btn_confirmar_consumidor_final')),
        );
        await tester.pumpAndSettle();

        // Ir a Paso 3 (Abonos)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        // Ir a Paso 4 (Confirmación)
        await tester.tap(find.byKey(const Key('btn_siguiente_wizard')));
        await tester.pumpAndSettle();

        // Debe mostrar la tarjeta llamativa con VENTA DESIGNADA
        expect(
          find.byKey(const Key('resumen_venta_asignada_step4')),
          findsOneWidget,
        );
        expect(find.text('VENTA DESIGNADA'), findsOneWidget);
        expect(
          find.textContaining('Responsable de Entrega Física: Tú (Vendedor)'),
          findsOneWidget,
        );
      },
    );
  });
}
