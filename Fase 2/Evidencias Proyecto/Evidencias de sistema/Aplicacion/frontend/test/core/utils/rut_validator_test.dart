import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/utils/rut_formatter.dart';
import 'package:frontend/core/utils/rut_validator.dart';

void main() {
  group('RutValidator - Módulo 11', () {
    test('calculateDv calcula correctamente dígitos conocidos', () {
      expect(RutValidator.calculateDv('11111111'), equals('1'));
      expect(RutValidator.calculateDv('11111112'), equals('K'));
      expect(RutValidator.calculateDv('12345678'), equals('5'));
      expect(RutValidator.calculateDv('18765432'), equals('7'));
    });

    test('calculateDv retorna null para cuerpos no numéricos o vacíos', () {
      expect(RutValidator.calculateDv(''), isNull);
      expect(RutValidator.calculateDv('12A34'), isNull);
    });

    test('isValid retorna true para RUTs chilenos matemáticamente válidos', () {
      expect(RutValidator.isValid('11.111.111-1'), isTrue);
      expect(RutValidator.isValid('11111111-1'), isTrue);
      expect(RutValidator.isValid('111111111'), isTrue);
      expect(RutValidator.isValid('11.111.112-K'), isTrue);
      expect(RutValidator.isValid('11.111.112-k'), isTrue); // 'k' minúscula tolerada
      expect(RutValidator.isValid('11111112k'), isTrue);
      expect(RutValidator.isValid('12.345.678-5'), isTrue);
      expect(RutValidator.isValid('18.765.432-7'), isTrue);
    });

    test('isValid acepta Consumidor Final (6.666.666-6 / 66666666-6) por exención legal', () {
      expect(RutValidator.isValid('6.666.666-6'), isTrue);
      expect(RutValidator.isValid('6666666-6'), isTrue);
      expect(RutValidator.isValid('66666666-6'), isTrue);
    });

    test('isValid retorna false para RUTs inventados o matemáticamente inválidos', () {
      expect(RutValidator.isValid('1.111.111-1'), isFalse); // DV real es 4
      expect(RutValidator.isValid('12.345.678-9'), isFalse); // DV real es 5
      expect(RutValidator.isValid('18.765.432-1'), isFalse); // DV real es 7
      expect(RutValidator.isValid('12345-6'), isFalse);
      expect(RutValidator.isValid(''), isFalse);
      expect(RutValidator.isValid(null), isFalse);
      expect(RutValidator.isValid('abcdefg'), isFalse);
    });

    test('format normaliza con puntos y guion', () {
      expect(RutValidator.format('111111111'), equals('11.111.111-1'));
      expect(RutValidator.format('11111112k'), equals('11.111.112-K'));
      expect(RutValidator.format('123456785'), equals('12.345.678-5'));
      expect(RutValidator.format('111111111', withDots: false), equals('11111111-1'));
    });

    test('clean sanitiza puntos, guiones y espacios', () {
      expect(RutValidator.clean(' 12.345.678-k '), equals('12345678K'));
    });
  });

  group('RutFormatter - TextInputFormatter', () {
    test('convierte "k" minúscula a "K" mayúscula y formatea', () {
      final formatter = RutFormatter();
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(text: '11111112k');

      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, equals('11.111.112-K'));
    });

    test('ignora caracteres no válidos', () {
      final formatter = RutFormatter();
      const oldValue = TextEditingValue.empty;
      const newValue = TextEditingValue(text: '12abc34');

      final result = formatter.formatEditUpdate(oldValue, newValue);
      expect(result.text, equals('123-4'));
    });
  });

  group('Pruebas de Widget - Validación Reactiva y Deshabilitación de Botón', () {
    testWidgets('RUT inválido despliega error visual y deshabilita botón', (WidgetTester tester) async {
      final controller = TextEditingController();
      String? errorText;
      bool isButtonEnabled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                void onRutChanged(String val) {
                  setState(() {
                    if (val.trim().isNotEmpty && !RutValidator.isValid(val)) {
                      errorText = 'RUT inválido. Verifique el número ingresado.';
                      isButtonEnabled = false;
                    } else if (val.trim().isNotEmpty && RutValidator.isValid(val)) {
                      errorText = null;
                      isButtonEnabled = true;
                    } else {
                      errorText = null;
                      isButtonEnabled = false;
                    }
                  });
                }

                return Column(
                  children: [
                    TextField(
                      key: const Key('input_rut_test'),
                      controller: controller,
                      inputFormatters: [RutFormatter()],
                      decoration: InputDecoration(
                        labelText: 'RUT Cliente',
                        errorText: errorText,
                      ),
                      onChanged: onRutChanged,
                    ),
                    ElevatedButton(
                      key: const Key('btn_continuar_test'),
                      onPressed: isButtonEnabled ? () {} : null,
                      child: const Text('Continuar'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      final inputFinder = find.byKey(const Key('input_rut_test'));
      final buttonFinder = find.byKey(const Key('btn_continuar_test'));

      // Inicialmente el botón debe estar deshabilitado
      ElevatedButton btn = tester.widget<ElevatedButton>(buttonFinder);
      expect(btn.onPressed, isNull);

      // Ingresar RUT inválido (12.345.678-9)
      await tester.enterText(inputFinder, '12.345.678-9');
      await tester.pump();

      // Debe mostrarse el mensaje de error estandarizado
      expect(find.text('RUT inválido. Verifique el número ingresado.'), findsOneWidget);

      // El botón debe permanecer deshabilitado
      btn = tester.widget<ElevatedButton>(buttonFinder);
      expect(btn.onPressed, isNull);

      // Ingresar RUT válido (12.345.678-5)
      await tester.enterText(inputFinder, '12.345.678-5');
      await tester.pump();

      // El mensaje de error debe desaparecer
      expect(find.text('RUT inválido. Verifique el número ingresado.'), findsNothing);

      // El botón debe estar habilitado
      btn = tester.widget<ElevatedButton>(buttonFinder);
      expect(btn.onPressed, isNotNull);
    });
  });
}
