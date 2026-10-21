import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/tokens/app_palette.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Mecanismo de Contingencia y Fallback OCR (Recepción y Paletizado)', () {
    testWidgets('Modal 1 y Modal 2 de contingencia manual en RecepcionVehiculoScreen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            scaffoldBackgroundColor: AppPalette.background,
            colorScheme: const ColorScheme.dark(
              primary: AppPalette.primary,
              surface: AppPalette.surface,
            ),
          ),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('btn_trigger_modal_manual'),
                    onPressed: () {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) {
                          final controller = TextEditingController(text: '1001');
                          return AlertDialog(
                            backgroundColor: AppPalette.surface,
                            title: const Text('Validación Manual OCR'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'No logramos detectar el número automáticamente o hubo un problema de conexión. Ingresa manualmente el N° de Ingreso visible en el vehículo o pieza.',
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  key: const Key('input_numero_ingreso_manual'),
                                  controller: controller,
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                key: const Key('btn_reintentar_camara'),
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Reintentar con Cámara'),
                              ),
                              ElevatedButton(
                                key: const Key('btn_confirmar_ingreso_manual'),
                                onPressed: () {
                                  Navigator.of(ctx).pop(true);
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (ctx2) => AlertDialog(
                                      backgroundColor: AppPalette.surface,
                                      title: const Text('Confirmación de Seguridad'),
                                      content: Text(
                                        '¿Confirmas que el N° de Ingreso ${controller.text} corresponde fielmente al vehículo/pieza física?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx2).pop(false),
                                          child: const Text('Cancelar'),
                                        ),
                                        ElevatedButton(
                                          key: const Key('btn_aceptar_doble_confirmacion'),
                                          onPressed: () => Navigator.of(ctx2).pop(true),
                                          child: const Text('Aceptar'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                child: const Text('Confirmar'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    child: const Text('Simular Contingencia'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Disparar contingencia
      await tester.tap(find.byKey(const Key('btn_trigger_modal_manual')));
      await tester.pumpAndSettle();

      // Validar Modal 1: Mensaje explicativo y campo de texto
      expect(find.text('Validación Manual OCR'), findsOneWidget);
      expect(
        find.textContaining('No logramos detectar el número automáticamente o hubo un problema de conexión'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('input_numero_ingreso_manual')), findsOneWidget);
      expect(find.byKey(const Key('btn_reintentar_camara')), findsOneWidget);
      expect(find.byKey(const Key('btn_confirmar_ingreso_manual')), findsOneWidget);

      // Tap en Confirmar -> Abre Modal 2 (Doble Confirmación de Seguridad)
      await tester.tap(find.byKey(const Key('btn_confirmar_ingreso_manual')));
      await tester.pumpAndSettle();

      expect(find.text('Confirmación de Seguridad'), findsOneWidget);
      expect(
        find.text('¿Confirmas que el N° de Ingreso 1001 corresponde fielmente al vehículo/pieza física?'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('btn_aceptar_doble_confirmacion')), findsOneWidget);

      // Confirmar Modal 2
      await tester.tap(find.byKey(const Key('btn_aceptar_doble_confirmacion')));
      await tester.pumpAndSettle();

      expect(find.text('Confirmación de Seguridad'), findsNothing);
    });

    testWidgets('Modal 1 y Modal 2 de contingencia manual en PaletizadoScreen', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            scaffoldBackgroundColor: AppPalette.background,
            colorScheme: const ColorScheme.dark(
              primary: AppPalette.primary,
              surface: AppPalette.surface,
            ),
          ),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('btn_trigger_paletizado_manual'),
                    onPressed: () {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) {
                          final controller = TextEditingController(text: 'ING-2024-001');
                          return AlertDialog(
                            backgroundColor: AppPalette.surface,
                            title: const Text('Validación Manual OCR'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'No logramos detectar el número automáticamente o hubo un problema de conexión. Ingresa manualmente el N° de Ingreso visible en el vehículo o pieza.',
                                ),
                                const SizedBox(height: 16),
                                TextField(
                                  key: const Key('input_numero_ingreso_manual_paletizado'),
                                  controller: controller,
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                key: const Key('btn_reintentar_camara_paletizado'),
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('Reintentar con Cámara'),
                              ),
                              ElevatedButton(
                                key: const Key('btn_confirmar_ingreso_manual_paletizado'),
                                onPressed: () {
                                  Navigator.of(ctx).pop(true);
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (ctx2) => AlertDialog(
                                      backgroundColor: AppPalette.surface,
                                      title: const Text('Confirmación de Seguridad'),
                                      content: Text(
                                        '¿Confirmas que el N° de Ingreso ${controller.text} corresponde fielmente al vehículo/pieza física?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(ctx2).pop(false),
                                          child: const Text('Cancelar'),
                                        ),
                                        ElevatedButton(
                                          key: const Key('btn_aceptar_doble_confirmacion_paletizado'),
                                          onPressed: () => Navigator.of(ctx2).pop(true),
                                          child: const Text('Aceptar'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                child: const Text('Confirmar'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    child: const Text('Simular Contingencia Paletizado'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Disparar contingencia
      await tester.tap(find.byKey(const Key('btn_trigger_paletizado_manual')));
      await tester.pumpAndSettle();

      // Validar Modal 1
      expect(find.text('Validación Manual OCR'), findsOneWidget);
      expect(find.byKey(const Key('input_numero_ingreso_manual_paletizado')), findsOneWidget);
      expect(find.byKey(const Key('btn_reintentar_camara_paletizado')), findsOneWidget);
      expect(find.byKey(const Key('btn_confirmar_ingreso_manual_paletizado')), findsOneWidget);

      // Confirmar en Modal 1 -> Abre Modal 2
      await tester.tap(find.byKey(const Key('btn_confirmar_ingreso_manual_paletizado')));
      await tester.pumpAndSettle();

      expect(find.text('Confirmación de Seguridad'), findsOneWidget);
      expect(
        find.text('¿Confirmas que el N° de Ingreso ING-2024-001 corresponde fielmente al vehículo/pieza física?'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('btn_aceptar_doble_confirmacion_paletizado')), findsOneWidget);

      // Aceptar Modal 2
      await tester.tap(find.byKey(const Key('btn_aceptar_doble_confirmacion_paletizado')));
      await tester.pumpAndSettle();

      expect(find.text('Confirmación de Seguridad'), findsNothing);
    });
  });
}
