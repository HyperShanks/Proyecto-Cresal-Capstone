import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/features/inventario/services/inventario_service.dart';
import 'package:frontend/features/inventario/presentation/widgets/dialogo_despaletizar.dart';

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

  group('InventarioService.despaletizarActivo - Unit Tests', () {
    test('despaletizarActivo envía POST con motivo y observación y retorna respuesta exitosa', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, contains('/api/v1/inventario/act-123/despaletizar'));
        expect(request.headers['Authorization'], 'Bearer fake-test-jwt-token');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['motivo'], 'Merma / Daño Físico Detectado');
        expect(body['observacion'], 'Se detectó fisura en el soporte');

        return http.Response(
          jsonEncode({
            'id_activo': 'act-123',
            'sku_qr_fisico': 'MOT-2686',
            'id_estado': 5,
            'mensaje': 'Activo despaletizado exitosamente.',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final res = await InventarioService.despaletizarActivo(
        'act-123',
        motivo: 'Merma / Daño Físico Detectado',
        observacion: 'Se detectó fisura en el soporte',
        client: mockClient,
      );
      expect(res['id_estado'], 5);
      expect(res['sku_qr_fisico'], 'MOT-2686');
      expect(res['mensaje'], contains('despaletizado exitosamente'));
    });

    test('despaletizarActivo propaga error de repuesto vendido o inválido', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'No es posible despaletizar un repuesto en estado Vendido.',
          }),
          400,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      expect(
        () async => await InventarioService.despaletizarActivo('act-vendido', client: mockClient),
        throwsA(
          predicate((e) => e.toString().contains('No es posible despaletizar')),
        ),
      );
    });
  });

  group('DialogoDespaletizar - Widget & Timer Tests', () {
    testWidgets('Botón de confirmación inicia deshabilitado con contador de 5s y se habilita con datos válidos', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DialogoDespaletizar(
              idActivo: 'act-999',
              sku: 'MOT-2686',
              categoria: 'Motor',
              numeroIngreso: '2686',
              ubicacionActual: 'Galpón 1 | Pasillo B | Pallet 04',
              motivoInicial: 'Merma / Daño Físico Detectado',
              observacionInicial: 'Fisura detectada al manipular pallet.',
            ),
          ),
        ),
      );

      // Estado inicial (0 segundos transcurridos):
      expect(find.text('Despaletizar Repuesto'), findsOneWidget);
      expect(find.text('Folio Ingreso: 2686'), findsOneWidget);
      expect(find.textContaining('Galpón 1 | Pasillo B | Pallet 04'), findsOneWidget);
      expect(find.text('CONFIRMAR (5s)'), findsOneWidget);

      final confirmBtn = tester.widget<ElevatedButton>(
        find.byKey(const Key('btn_confirmar_despaletizado')),
      );
      expect(confirmBtn.onPressed, isNull, reason: 'El botón debe estar deshabilitado al inicio');

      // Avanzar 1 segundo:
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('CONFIRMAR (4s)'), findsOneWidget);
      final confirmBtn1s = tester.widget<ElevatedButton>(
        find.byKey(const Key('btn_confirmar_despaletizado')),
      );
      expect(confirmBtn1s.onPressed, isNull);

      // Avanzar los 4 segundos restantes (total 5s):
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('CONFIRMAR DESPALETIZADO'), findsOneWidget);
      expect(find.text('Temporizador completado.'), findsOneWidget);

      final confirmBtn5s = tester.widget<ElevatedButton>(
        find.byKey(const Key('btn_confirmar_despaletizado')),
      );
      expect(confirmBtn5s.onPressed, isNotNull, reason: 'El botón debe habilitarse tras 5 segundos');
    });

    testWidgets('Poka-Yoke: DialogoDespaletizar bloquea botón si falta motivo o si la observación tiene < 10 caracteres', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DialogoDespaletizar(
              idActivo: 'act-poka',
              sku: 'ALT-100',
              categoria: 'Alternador',
              duracionSegundos: 0, // timer ya completado
            ),
          ),
        ),
      );

      // 1. Inicialmente sin motivo ni observación -> Botón bloqueado
      final btnInicial = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_despaletizado')));
      expect(btnInicial.onPressed, isNull);

      // 2. Seleccionar motivo mediante chip táctil
      await tester.tap(find.byKey(const Key('chip_motivo_Reubicación a Otro Pasillo o Nivel')));
      await tester.pump();

      // Sigue bloqueado porque observación está vacía
      final btnConMotivo = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_despaletizado')));
      expect(btnConMotivo.onPressed, isNull);

      // 3. Escribir espacios en blanco (trim() < 10)
      await tester.enterText(find.byKey(const Key('input_observacion_despaletizar')), '         ');
      await tester.pump();
      final btnEspacios = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_despaletizado')));
      expect(btnEspacios.onPressed, isNull);

      // 4. Escribir 9 caracteres
      await tester.enterText(find.byKey(const Key('input_observacion_despaletizar')), '123456789');
      await tester.pump();
      expect(find.textContaining('Faltan 1 caracteres'), findsOneWidget);
      final btnNueve = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_despaletizado')));
      expect(btnNueve.onPressed, isNull);

      // 5. Escribir 10 caracteres útiles
      await tester.enterText(find.byKey(const Key('input_observacion_despaletizar')), 'Reubicado a pasillo C');
      await tester.pump();
      final btnHabilitado = tester.widget<ElevatedButton>(find.byKey(const Key('btn_confirmar_despaletizado')));
      expect(btnHabilitado.onPressed, isNotNull);
    });

    testWidgets('DialogoDespaletizar envía motivo táctil y justificación al confirmar', (tester) async {
      String? motivoCapturado;
      String? observacionCapturada;

      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        motivoCapturado = body['motivo'];
        observacionCapturada = body['observacion'];

        return http.Response(
          jsonEncode({
            'id_activo': 'act-success',
            'sku_qr_fisico': 'ALT-200',
            'id_estado': 5,
            'mensaje': 'Activo despaletizado exitosamente.',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      bool? resultado;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  resultado = await DialogoDespaletizar.mostrar(
                    context,
                    idActivo: 'act-success',
                    sku: 'ALT-200',
                    categoria: 'Alternador',
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

      // Seleccionar motivo
      await tester.tap(find.byKey(const Key('chip_motivo_Preparación Venta / Despacho Inmediato')));
      await tester.pump();

      // Ingresar observación
      await tester.enterText(
        find.byKey(const Key('input_observacion_despaletizar')),
        'Preparando despacho urgente para cliente.',
      );
      await tester.pump();

      // Confirmar
      await tester.tap(find.byKey(const Key('btn_confirmar_despaletizado')));
      await tester.pumpAndSettle();

      expect(motivoCapturado, 'Preparación Venta / Despacho Inmediato');
      expect(observacionCapturada, 'Preparando despacho urgente para cliente.');
      expect(resultado, isTrue);
    });

    testWidgets('Botón Cancelar siempre está disponible y cierra el diálogo', (tester) async {
      bool? resultado;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  resultado = await DialogoDespaletizar.mostrar(
                    context,
                    idActivo: 'act-999',
                    sku: 'MOT-2686',
                    categoria: 'Motor',
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

      expect(find.text('CANCELAR'), findsOneWidget);

      // Cancelar de inmediato mientras está en cuenta regresiva
      await tester.tap(find.byKey(const Key('btn_cancelar_despaletizado')));
      await tester.pumpAndSettle();

      expect(find.text('Despaletizar Repuesto'), findsNothing);
      expect(resultado, isFalse);
    });
  });
}

