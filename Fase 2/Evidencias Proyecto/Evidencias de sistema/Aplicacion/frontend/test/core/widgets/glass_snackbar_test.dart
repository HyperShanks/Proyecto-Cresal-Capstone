import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/widgets/glass_snackbar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GlassSnackbar Widget Tests', () {
    testWidgets('Renderiza mensaje, icono y botón de cerrar "X"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  GlassSnackbar.mostrar(
                    ctx,
                    mensaje: 'Motor V8 agregado al carrito',
                    icono: Icons.check_circle_outline_rounded,
                  );
                },
                child: const Text('Mostrar Notificación'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mostrar Notificación'));
      await tester.pump(); // Inicia animación del SnackBar

      expect(find.text('Motor V8 agregado al carrito'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byKey(const Key('btn_cerrar_snackbar')), findsOneWidget);
    });

    testWidgets('Presionar el botón "X" cierra el SnackBar inmediatamente', (tester) async {
      bool cerradoCustom = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  GlassSnackbar.mostrar(
                    ctx,
                    mensaje: 'Caja de cambios eliminada del carrito',
                    icono: Icons.delete_outline_rounded,
                    onCerrar: () {
                      cerradoCustom = true;
                      ScaffoldMessenger.of(ctx).hideCurrentSnackBar();
                    },
                  );
                },
                child: const Text('Mostrar Notificación Eliminado'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mostrar Notificación Eliminado'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // Esperar entrada completa de la animación

      expect(find.text('Caja de cambios eliminada del carrito'), findsOneWidget);
      expect(find.byKey(const Key('btn_cerrar_snackbar')), findsOneWidget);

      // Tocar el botón de cerrar X
      await tester.tap(find.byKey(const Key('btn_cerrar_snackbar')));
      await tester.pumpAndSettle();

      expect(cerradoCustom, isTrue);
      expect(find.text('Caja de cambios eliminada del carrito'), findsNothing);
    });

    testWidgets('Presionar "X" sin callback custom cierra el SnackBar por defecto', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  GlassSnackbar.mostrar(
                    ctx,
                    mensaje: 'Amortiguador añadido al carrito',
                  );
                },
                child: const Text('Mostrar'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mostrar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Amortiguador añadido al carrito'), findsOneWidget);
      expect(find.byKey(const Key('btn_cerrar_snackbar')), findsOneWidget);

      await tester.tap(find.byKey(const Key('btn_cerrar_snackbar')));
      await tester.pumpAndSettle();

      expect(find.text('Amortiguador añadido al carrito'), findsNothing);
    });
  });
}
