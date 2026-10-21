// frontend/test/core/utils/currency_formatter_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/utils/currency_formatter.dart';

void main() {
  group('CurrencyFormatter Tests', () {
    test('formatCLP formatea montos a Pesos Chilenos con puntos', () {
      expect(CurrencyFormatter.formatCLP(null), '\$ 0');
      expect(CurrencyFormatter.formatCLP(0), '\$ 0');
      expect(CurrencyFormatter.formatCLP(100), '\$ 100');
      expect(CurrencyFormatter.formatCLP(1000), '\$ 1.000');
      expect(CurrencyFormatter.formatCLP(50000), '\$ 50.000');
      expect(CurrencyFormatter.formatCLP(450000), '\$ 450.000');
      expect(CurrencyFormatter.formatCLP(10000000), '\$ 10.000.000');
      expect(CurrencyFormatter.formatCLP(-50000), '-\$ 50.000');
    });

    test('formatNumber formatea números a cadena con puntos sin signo peso', () {
      expect(CurrencyFormatter.formatNumber(null), '0');
      expect(CurrencyFormatter.formatNumber(0), '0');
      expect(CurrencyFormatter.formatNumber(500), '500');
      expect(CurrencyFormatter.formatNumber(1000), '1.000');
      expect(CurrencyFormatter.formatNumber(15000), '15.000');
      expect(CurrencyFormatter.formatNumber(520000), '520.000');
      expect(CurrencyFormatter.formatNumber(10000000), '10.000.000');
      expect(CurrencyFormatter.formatNumber(-100000), '-100.000');
    });

    test('parse extrae el valor entero correctamente eliminando puntos y símbolos', () {
      expect(CurrencyFormatter.parse(null), 0);
      expect(CurrencyFormatter.parse(''), 0);
      expect(CurrencyFormatter.parse('0'), 0);
      expect(CurrencyFormatter.parse('500'), 500);
      expect(CurrencyFormatter.parse('1.000'), 1000);
      expect(CurrencyFormatter.parse('10.000.000'), 10000000);
      expect(CurrencyFormatter.parse('\$ 10.000.000'), 10000000);
      expect(CurrencyFormatter.parse('  520.000  '), 520000);
      expect(CurrencyFormatter.parse('sin numeros'), 0);
    });
  });

  group('MilesTextInputFormatter Tests', () {
    final formatter = MilesTextInputFormatter();

    test('agrega puntos automáticamente al escribir dígitos secuencialmente', () {
      // 1 -> 1
      var res = formatter.formatEditUpdate(
        const TextEditingValue(text: ''),
        const TextEditingValue(text: '1', selection: TextSelection.collapsed(offset: 1)),
      );
      expect(res.text, '1');
      expect(res.selection.baseOffset, 1);

      // 10 -> 10
      res = formatter.formatEditUpdate(
        const TextEditingValue(text: '1'),
        const TextEditingValue(text: '10', selection: TextSelection.collapsed(offset: 2)),
      );
      expect(res.text, '10');
      expect(res.selection.baseOffset, 2);

      // 100 -> 100
      res = formatter.formatEditUpdate(
        const TextEditingValue(text: '10'),
        const TextEditingValue(text: '100', selection: TextSelection.collapsed(offset: 3)),
      );
      expect(res.text, '100');
      expect(res.selection.baseOffset, 3);

      // 1000 -> 1.000
      res = formatter.formatEditUpdate(
        const TextEditingValue(text: '100'),
        const TextEditingValue(text: '1000', selection: TextSelection.collapsed(offset: 4)),
      );
      expect(res.text, '1.000');
      expect(res.selection.baseOffset, 5); // offset includes the newly inserted dot

      // 1.000 + 0 -> 10.000
      res = formatter.formatEditUpdate(
        const TextEditingValue(text: '1.000'),
        const TextEditingValue(text: '1.0000', selection: TextSelection.collapsed(offset: 6)),
      );
      expect(res.text, '10.000');
      expect(res.selection.baseOffset, 6);

      // 10000000 -> 10.000.000 (requisito explícito del usuario)
      res = formatter.formatEditUpdate(
        const TextEditingValue(text: '1000000'),
        const TextEditingValue(text: '10000000', selection: TextSelection.collapsed(offset: 8)),
      );
      expect(res.text, '10.000.000');
      expect(res.selection.baseOffset, 10);
    });

    test('maneja borrado con backspace correctamente', () {
      // 1.000 borrando el último 0 -> 100
      final res = formatter.formatEditUpdate(
        const TextEditingValue(text: '1.000'),
        const TextEditingValue(text: '1.00', selection: TextSelection.collapsed(offset: 4)),
      );
      expect(res.text, '100');
      expect(res.selection.baseOffset, 3);
    });

    test('maneja edición intermedia sin perder posición del cursor', () {
      // 10.000 insertando 5 entre el 10 y el . -> '105.000'
      final res = formatter.formatEditUpdate(
        const TextEditingValue(text: '10.000', selection: TextSelection.collapsed(offset: 2)),
        const TextEditingValue(text: '105.000', selection: TextSelection.collapsed(offset: 3)),
      );
      expect(res.text, '105.000');
      expect(res.selection.baseOffset, 3);
    });

    test('retorna vacío cuando se limpia el texto', () {
      final res = formatter.formatEditUpdate(
        const TextEditingValue(text: '1'),
        const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0)),
      );
      expect(res.text, '');
      expect(res.selection.baseOffset, 0);
    });
  });
}
