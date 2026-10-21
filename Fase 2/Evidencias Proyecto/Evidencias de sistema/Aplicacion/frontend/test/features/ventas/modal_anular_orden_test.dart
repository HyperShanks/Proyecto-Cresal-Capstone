import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/features/ventas/services/ventas_service.dart';
import 'package:frontend/features/ventas/services/ordenes_service.dart';
import 'package:frontend/features/ventas/presentation/widgets/modal_anular_orden.dart';
import 'package:frontend/features/ventas/presentation/widgets/dialogo_devolucion_dinero.dart';
import 'package:frontend/features/ventas/presentation/widgets/orden_detail_sheet.dart';

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

  group('VentasService - Anulación ACID Unit Tests', () {
    test('anularOrden envía POST con motivo_anulacion y parsea 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, contains('/anular'));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['motivo_anulacion'], 'Cliente solicitó desistimiento');

        return http.Response(
          jsonEncode({
            'id_orden': 'ord-123',
            'estado_orden': 'Anulada',
            'mensaje': 'Orden anulada, pagos reversados y tareas de reingreso generadas',
            'activos_liberados': 2,
            'pagos_reversados': 1,
            'motivo_anulacion': 'Cliente solicitó desistimiento',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final res = await VentasService.anularOrden(
        'ord-123',
        motivoAnulacion: 'Cliente solicitó desistimiento',
        client: mockClient,
      );

      expect(res['estado_orden'], 'Anulada');
      expect(res['pagos_reversados'], 1);
      expect(res['activos_liberados'], 2);
    });

    test('anularOrden lanza excepción descriptiva ante error 400', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'La orden ya se encuentra anulada.'}),
          400,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      expect(
        () => VentasService.anularOrden('ord-123', client: mockClient),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ModalAnularOrden - Widget Tests', () {
    testWidgets('Renderiza elementos de advertencia, folio y campos para orden sin pago (\$0)', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    ModalAnularOrden.mostrar(
                      context,
                      idOrden: 'ord-abc-123',
                      folio: 'ORD-ABC12345',
                      clienteNombre: 'Juan Pérez',
                      montoPagado: 0,
                    );
                  },
                  child: const Text('Abrir Modal'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Modal'));
      await tester.pumpAndSettle();

      expect(find.text('¿Deshacer esta Orden?'), findsOneWidget);
      expect(find.text('Folio: ORD-ABC12345'), findsOneWidget);
      expect(find.text('Cliente: Juan Pérez'), findsOneWidget);
      expect(find.text('Confirmar Anulación'), findsOneWidget);
      expect(find.text('Volver'), findsOneWidget);
      // Debe mostrar la alerta de advertencia preventiva para órdenes sin pago
      expect(find.byKey(const Key('alerta_advertencia_anular_sin_pago')), findsOneWidget);
      expect(find.text('ADVERTENCIA: ANULACIÓN IRREVERSIBLE'), findsOneWidget);
      // No debe mostrar la alerta de peligro de dinero
      expect(find.byKey(const Key('alerta_peligro_cliente_pago')), findsNothing);
    });

    testWidgets('Muestra alerta de PELIGRO destacada cuando la orden tiene pagos o abonos (montoPagado > 0)', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    ModalAnularOrden.mostrar(
                      context,
                      idOrden: 'ord-paid-456',
                      folio: 'ORD-PAID456',
                      clienteNombre: 'Carlos Santana',
                      totalVenta: 120000,
                      montoPagado: 60000,
                    );
                  },
                  child: const Text('Abrir Modal Pagada'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Modal Pagada'));
      await tester.pumpAndSettle();

      // Debe mostrar el título de PELIGRO
      expect(find.text('⚠️ PELIGRO: CLIENTE YA PAGÓ'), findsOneWidget);
      // Debe contener la tarjeta de alerta de peligro con el monto formateado
      expect(find.byKey(const Key('alerta_peligro_cliente_pago')), findsOneWidget);
      expect(find.textContaining('60.000'), findsOneWidget);
      expect(find.textContaining('OBLIGATORIO DEVOLVERLE ESTE DINERO'), findsOneWidget);
    });

    testWidgets('DialogoDevolucionDinero bloquea botón aceptar por 5 segundos y muestra cuenta regresiva', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    DialogoDevolucionDinero.mostrar(
                      context,
                      folio: 'ORD-DEV123',
                      montoADevolver: 85000,
                      clienteNombre: 'Marcela Soto',
                    );
                  },
                  child: const Text('Abrir Devolución'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Devolución'));
      await tester.pump(); // Inicia el diálogo

      expect(find.byType(DialogoDevolucionDinero), findsOneWidget);
      expect(find.text('DEVOLUCIÓN DE DINERO'), findsOneWidget);
      expect(find.textContaining('85.000'), findsOneWidget);
      expect(find.textContaining('Cliente: Marcela Soto'), findsOneWidget);

      // Botón inicialmente deshabilitado mostrando (5s)
      final btnInicial = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_devolucion_dinero')));
      expect(btnInicial.onPressed, isNull);
      expect(find.textContaining('(5s)'), findsOneWidget);

      // Avanzar 2 segundos: debe mostrar (3s) y seguir bloqueado
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('(3s)'), findsOneWidget);
      final btnMitad = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_devolucion_dinero')));
      expect(btnMitad.onPressed, isNull);

      // Avanzar los 3 segundos restantes (total 5s)
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('ENTENDIDO, DINERO DEVUELTO'), findsOneWidget);
      final btnHabilitado = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_devolucion_dinero')));
      expect(btnHabilitado.onPressed, isNotNull);

      // Presionar el botón para cerrar el diálogo
      await tester.tap(find.byKey(const Key('btn_confirmar_devolucion_dinero')));
      await tester.pumpAndSettle();

      expect(find.byType(DialogoDevolucionDinero), findsNothing);
    });

    testWidgets('ModalAnularOrden bloquea el botón por 5 segundos y exige marcar casilla He leído y redactar >= 10 caracteres para confirmar', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    ModalAnularOrden.mostrar(
                      context,
                      idOrden: 'ord-timer-test',
                      folio: 'ORD-TIMER-001',
                      montoPagado: 0,
                    );
                  },
                  child: const Text('Abrir Modal Timer'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Modal Timer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(ModalAnularOrden), findsOneWidget);
      expect(find.byKey(const Key('check_confirmar_anulacion')), findsOneWidget);
      expect(find.byKey(const Key('select_motivo_anulacion')), findsOneWidget);
      expect(find.byKey(const Key('input_observacion_anulacion')), findsOneWidget);

      // 1. Inicialmente deshabilitado con contador (5s)
      final btnInicial = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_anulacion_orden')));
      expect(btnInicial.onPressed, isNull);
      expect(find.textContaining('(5s)'), findsOneWidget);

      // 2. Avanzar 2 segundos: muestra (3s) y sigue bloqueado
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('(3s)'), findsOneWidget);
      final btnMitad = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_anulacion_orden')));
      expect(btnMitad.onPressed, isNull);

      // 3. Avanzar 3 segundos más (5s total completados)
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Confirmar Anulación'), findsOneWidget);

      // Sigue bloqueado porque falta marcar la casilla He leído y la observación está vacía
      final btnSinCheck = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_anulacion_orden')));
      expect(btnSinCheck.onPressed, isNull);

      // 4. Marcar casilla obligatoria (pero sin observación aún)
      await tester.tap(find.byKey(const Key('check_confirmar_anulacion_tap')));
      await tester.pump();

      // Debe seguir deshabilitado (Poka-Yoke: 0 < 10 caracteres)
      final btnSinTexto = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_anulacion_orden')));
      expect(btnSinTexto.onPressed, isNull);

      // 5. Ingresar texto insuficiente (< 10 caracteres)
      await tester.enterText(find.byKey(const Key('input_observacion_anulacion')), 'Error');
      await tester.pump();
      expect(find.textContaining('Faltan 5 caracteres'), findsOneWidget);
      final btnTextoCorto = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_anulacion_orden')));
      expect(btnTextoCorto.onPressed, isNull);

      // 6. Ingresar justificación completa válida (>= 10 caracteres)
      await tester.enterText(find.byKey(const Key('input_observacion_anulacion')), 'Cliente desiste formalmente de la compra.');
      await tester.pump();

      // 7. Ahora sí está habilitado
      final btnHabilitado = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_anulacion_orden')));
      expect(btnHabilitado.onPressed, isNotNull);

      // 8. Si desmarcamos la casilla, se vuelve a inhabilitar
      await tester.tap(find.byKey(const Key('check_confirmar_anulacion_tap')));
      await tester.pump();
      final btnDesmarcado = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_anulacion_orden')));
      expect(btnDesmarcado.onPressed, isNull);
    });

    testWidgets('Permite cerrar el modal con botón Volver', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    ModalAnularOrden.mostrar(
                      context,
                      idOrden: 'ord-abc-123',
                      folio: 'ORD-ABC12345',
                    );
                  },
                  child: const Text('Abrir Modal'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Modal'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Volver'));
      await tester.pumpAndSettle();

      expect(find.text('¿Deshacer esta Orden?'), findsNothing);
    });

    testWidgets('Flujo encadenado: Confirmar anulación con dinero pagado abre DialogoDevolucionDinero', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id_orden': 'ord-chain-789',
            'estado_orden': 'Anulada',
            'mensaje': 'Orden anulada, pagos reversados y tareas de reingreso generadas',
            'activos_liberados': 1,
            'pagos_reversados': 1,
            'monto_reversado': 50000,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      bool ordenAnuladaCallbackLlamado = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    ModalAnularOrden.mostrar(
                      context,
                      idOrden: 'ord-chain-789',
                      folio: 'ORD-CHAIN789',
                      clienteNombre: 'Roberto Gómez',
                      montoPagado: 50000,
                      client: mockClient,
                      onOrdenAnulada: () {
                        ordenAnuladaCallbackLlamado = true;
                      },
                    );
                  },
                  child: const Text('Abrir Modal Chained'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Modal Chained'));
      await tester.pumpAndSettle();

      // Debe mostrar la advertencia de peligro
      expect(find.text('⚠️ PELIGRO: CLIENTE YA PAGÓ'), findsOneWidget);
      expect(find.textContaining('50.000'), findsOneWidget);

      // Marcar casilla obligatoria y avanzar el temporizador de 5 segundos
      await tester.tap(find.byKey(const Key('check_confirmar_anulacion_tap')));
      await tester.pump(const Duration(seconds: 5));

      // Ingresar justificación obligatoria de al menos 10 caracteres
      await tester.enterText(
        find.byKey(const Key('input_observacion_anulacion')),
        'Cliente solicitó devolución formal de su dinero.',
      );
      await tester.pump();

      // Confirmar la anulación
      await tester.tap(find.byKey(const Key('btn_confirmar_anulacion_orden')));
      await tester.pump(); // Inicia la petición
      await tester.pump(const Duration(milliseconds: 100)); // Completa la petición y muestra DialogoDevolucionDinero

      expect(ordenAnuladaCallbackLlamado, isTrue);

      // El modal de confirmación ya cerró y ahora está en pantalla el DialogoDevolucionDinero
      expect(find.byType(DialogoDevolucionDinero), findsOneWidget);
      expect(find.text('DEVOLUCIÓN DE DINERO'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(DialogoDevolucionDinero),
          matching: find.textContaining('50.000'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(DialogoDevolucionDinero),
          matching: find.textContaining('Roberto Gómez'),
        ),
        findsOneWidget,
      );

      // Botón debe estar bloqueado inicialmente con contador
      final btnDevolucion = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_devolucion_dinero')));
      expect(btnDevolucion.onPressed, isNull);
      expect(find.textContaining('(5s)'), findsOneWidget);

      // Avanzar los 5 segundos
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('ENTENDIDO, DINERO DEVUELTO'), findsOneWidget);

      // Presionar para cerrar el diálogo
      await tester.tap(find.byKey(const Key('btn_confirmar_devolucion_dinero')));
      await tester.pumpAndSettle();

      expect(find.byType(DialogoDevolucionDinero), findsNothing);
    });

    testWidgets('Garantía Responsive (Extend): No hay pixel overflow en pantalla móvil estrecha (320px)', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    ModalAnularOrden.mostrar(
                      context,
                      idOrden: 'ord-narrow-123',
                      folio: 'ORD-NARROW-999',
                      clienteNombre: 'Cliente Con Nombre Muy Largo Para Probar Desbordes',
                      montoPagado: 999999,
                    );
                  },
                  child: const Text('Abrir Estrecho'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Estrecho'));
      await tester.pumpAndSettle();

      // Verificar que no se lanzó ninguna excepción de RenderFlex overflow
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('btn_confirmar_anulacion_orden')), findsOneWidget);
      expect(find.text('Volver'), findsOneWidget);
    });

    testWidgets('Poka-Yoke: Observación con solo espacios en blanco o menos de 10 caracteres impide confirmación', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ModalAnularOrden.mostrar(
                    context,
                    idOrden: 'ord-pokayoke',
                    folio: 'ORD-POKA-01',
                    duracionSegundos: 0, // timer ya completado
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      // Marcar checkbox
      await tester.tap(find.byKey(const Key('check_confirmar_anulacion_tap')));
      await tester.pump();

      // Caso 1: Vacío
      final btnVacio = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_anulacion_orden')));
      expect(btnVacio.onPressed, isNull);

      // Caso 2: Solo espacios en blanco (trim() < 10)
      await tester.enterText(find.byKey(const Key('input_observacion_anulacion')), '            ');
      await tester.pump();
      final btnEspacios = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_anulacion_orden')));
      expect(btnEspacios.onPressed, isNull);

      // Caso 3: 9 caracteres útiles
      await tester.enterText(find.byKey(const Key('input_observacion_anulacion')), '123456789');
      await tester.pump();
      expect(find.textContaining('Faltan 1 caracteres'), findsOneWidget);
      final btnNueve = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_anulacion_orden')));
      expect(btnNueve.onPressed, isNull);

      // Caso 4: 10 caracteres exactos útiles
      await tester.enterText(find.byKey(const Key('input_observacion_anulacion')), '1234567890');
      await tester.pump();
      expect(find.textContaining('10 / 10 mín.'), findsOneWidget);
      final btnDiez = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_anulacion_orden')));
      expect(btnDiez.onPressed, isNotNull);
    });

    testWidgets('ModalAnularOrden envía motivo tipificado y observación al endpoint de anulación', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? motivoRecibido;
      String? obsRecibida;

      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        motivoRecibido = body['motivo'] ?? body['motivo_anulacion'];
        obsRecibida = body['observacion'] ?? body['observacion_anulacion'];

        return http.Response(
          jsonEncode({
            'id_orden': 'ord-test-audit',
            'estado_orden': 'Anulada',
            'mensaje': 'Orden anulada',
            'activos_liberados': 1,
            'pagos_reversados': 0,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  ModalAnularOrden.mostrar(
                    context,
                    idOrden: 'ord-test-audit',
                    folio: 'ORD-AUDIT-01',
                    client: mockClient,
                    duracionSegundos: 0,
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();

      // Cambiar motivo en el dropdown
      await tester.tap(find.byKey(const Key('select_motivo_anulacion')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quiebre de stock físico o pieza defectuosa').last);
      await tester.pumpAndSettle();

      // Ingresar observación
      await tester.enterText(
        find.byKey(const Key('input_observacion_anulacion')),
        'Pieza con fisura no reportada en la bodega.',
      );
      await tester.pump();

      // Marcar checkbox
      await tester.tap(find.byKey(const Key('check_confirmar_anulacion_tap')));
      await tester.pump();

      // Confirmar
      await tester.tap(find.byKey(const Key('btn_confirmar_anulacion_orden')));
      await tester.pumpAndSettle();

      expect(motivoRecibido, 'Quiebre de stock físico o pieza defectuosa');
      expect(obsRecibida, 'Pieza con fisura no reportada en la bodega.');
    });
  });

  group('OrdenDetailSheet - Anulación en Mis Órdenes Tests', () {
    testWidgets('Muestra botón anular con monto formateado para orden Pagada (montoPagado > 0)', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final ordenPagada = OrdenHistorialModel(
        idOrden: 'ord-pagada-100',
        estadoOrden: 'Pagada',
        totalVenta: 120000,
        montoPendiente: 0,
        totalItems: 1,
        fechaCreacion: '2026-09-22T10:00:00Z',
        detalles: [
          DetalleOrdenItemModel(
            idDetalle: 'det-1',
            idCategoria: 1,
            nombreCategoria: 'Repuestos',
            titulo: 'Alternador',
            cantidad: 1,
            precioFinal: 120000,
            subtotal: 120000,
            esInventariado: true,
          ),
        ],
      );

      expect(ordenPagada.esAnulable, isTrue);
      expect(ordenPagada.montoPagado, 120000);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrdenDetailSheet(
              orden: ordenPagada,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_anular_orden_detail')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('btn_anular_orden_detail')),
          matching: find.textContaining('120.000'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('No muestra botón anular para orden Completada', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final ordenCompletada = OrdenHistorialModel(
        idOrden: 'ord-comp-200',
        estadoOrden: 'Completada',
        totalVenta: 75000,
        montoPendiente: 0,
        totalItems: 1,
        fechaCreacion: '2026-09-22T09:00:00Z',
        detalles: [],
      );

      expect(ordenCompletada.esAnulable, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrdenDetailSheet(
              orden: ordenCompletada,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_anular_orden_detail')), findsNothing);
      expect(find.text('Orden Completada'), findsWidgets);
    });

    testWidgets('Al anular orden desde OrdenDetailSheet, se cierra el bottom sheet y vuelve a la vista anterior', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id_orden': 'ord-auto-close-1',
            'estado_orden': 'Anulada',
            'mensaje': 'Orden anulada exitosamente',
            'activos_liberados': 1,
            'pagos_reversados': 0,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final ordenReservada = OrdenHistorialModel(
        idOrden: 'ord-auto-close-1',
        estadoOrden: 'Reservada',
        totalVenta: 50000,
        montoPendiente: 50000,
        totalItems: 1,
        fechaCreacion: '2026-09-22T11:00:00Z',
        detalles: [],
      );

      bool bottomSheetCerrado = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    final res = await showModalBottomSheet(
                      context: context,
                      builder: (ctx) => OrdenDetailSheet(
                        orden: ordenReservada,
                        client: mockClient,
                      ),
                    );
                    if (res == true) {
                      bottomSheetCerrado = true;
                    }
                  },
                  child: const Text('Abrir Sheet'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Abrir Sheet'));
      await tester.pumpAndSettle();

      expect(find.byType(OrdenDetailSheet), findsOneWidget);

      // Tocar botón anular en el sheet
      await tester.tap(find.byKey(const Key('btn_anular_orden_detail')));
      await tester.pumpAndSettle();

      // Modal de anulación abierto
      expect(find.byType(ModalAnularOrden), findsOneWidget);

      // Marcar casilla obligatoria y avanzar el temporizador de 5 segundos
      await tester.tap(find.byKey(const Key('check_confirmar_anulacion_tap')));
      await tester.pump(const Duration(seconds: 5));

      // Ingresar justificación obligatoria de al menos 10 caracteres
      await tester.enterText(
        find.byKey(const Key('input_observacion_anulacion')),
        'Cancelación confirmada desde el detalle de la orden.',
      );
      await tester.pump();

      // Confirmar anulación (montoPagado es 0, no abre DialogoDevolucionDinero)
      await tester.tap(find.byKey(const Key('btn_confirmar_anulacion_orden')));
      await tester.pump();
      await tester.pumpAndSettle();

      // Debe haber cerrado tanto el modal como el bottom sheet
      expect(find.byType(ModalAnularOrden), findsNothing);
      expect(find.byType(OrdenDetailSheet), findsNothing);
      expect(bottomSheetCerrado, isTrue);
    });
  });
}
