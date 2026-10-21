// frontend/test/core/widgets/error_snackbar_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/api_service.dart';
import 'package:frontend/core/widgets/custom_error_snackbar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomErrorSnackbar - Widget Tests (SPEC-HU-07)', () {
    testWidgets('Muestra mensaje de error y código correctamente', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: ApiService.scaffoldMessengerKey,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  CustomErrorSnackbar.mostrar(
                    ctx,
                    mensaje: 'Problemas de conexión con el servidor. Reintentando...',
                    codigoError: 'NETWORK_TIMEOUT',
                  );
                },
                child: const Text('Disparar Error'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Disparar Error'));
      await tester.pump(); // Inicia animación del SnackBar

      expect(find.text('NETWORK_TIMEOUT'), findsOneWidget);
      expect(
        find.text('Problemas de conexión con el servidor. Reintentando...'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('Muestra botón de reintentar y dispara callback al presionarlo', (tester) async {
      bool reintentarPresionado = false;

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: ApiService.scaffoldMessengerKey,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  CustomErrorSnackbar.mostrar(
                    ctx,
                    mensaje: 'Fallo al procesar cobro',
                    onReintentar: () {
                      reintentarPresionado = true;
                    },
                    textoAccion: 'Reintentar',
                  );
                },
                child: const Text('Disparar Error Reintento'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('Disparar Error Reintento'));
      await tester.pumpAndSettle();

      expect(find.text('Reintentar'), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_reintentar_snackbar')));
      await tester.pumpAndSettle();

      expect(reintentarPresionado, isTrue);
    });

    testWidgets('mostrarGlobal funciona utilizando scaffoldMessengerKey sin BuildContext', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: ApiService.scaffoldMessengerKey,
          home: const Scaffold(
            body: Text('Vista Global Mock'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      CustomErrorSnackbar.mostrarGlobal(
        mensaje: 'PIN incorrecto para este terminal.',
        codigoError: 'AUTH_PIN_INVALID',
      );

      await tester.pump();

      expect(find.text('PIN incorrecto para este terminal.'), findsOneWidget);
      expect(find.text('AUTH_PIN_INVALID'), findsOneWidget);
    });
  });
}
