// frontend/lib/core/utils/currency_formatter.dart

import 'package:flutter/services.dart';

/// Utilidad estándar para formateo y parseo de moneda chilena (CLP).
class CurrencyFormatter {
  /// Formatea un valor numérico entero o decimal a Pesos Chilenos (CLP).
  /// Ejemplo: 1250000 -> "$ 1.250.000"
  static String formatCLP(num? valor) {
    if (valor == null) return '\$ 0';
    final intVal = valor.toInt();
    final isNegative = intVal < 0;
    final s = intVal.abs().toString();
    final buffer = StringBuffer();

    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(s[i]);
    }

    final signo = isNegative ? '-' : '';
    return '$signo\$ $buffer';
  }

  /// Formatea un valor numérico a texto con puntos de miles sin signo peso.
  /// Ejemplo: 10000000 -> "10.000.000"
  static String formatNumber(num? valor) {
    if (valor == null) return '0';
    final intVal = valor.toInt();
    final isNegative = intVal < 0;
    final s = intVal.abs().toString();
    final buffer = StringBuffer();

    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(s[i]);
    }

    final signo = isNegative ? '-' : '';
    return '$signo$buffer';
  }

  /// Parsea una cadena de texto (incluso con puntos de miles) a un entero.
  /// Ejemplo: "10.000.000" -> 10000000
  static int parse(String? text) {
    if (text == null) return 0;
    final clean = text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(clean) ?? 0;
  }
}

/// Formateador de entrada de texto (TextInputFormatter) que añade puntos (.)
/// como separador de miles en tiempo real a medida que el usuario escribe.
/// Mantiene la posición del cursor de forma consistente.
/// Ejemplo: al escribir "10000000" formatea a "10.000.000".
class MilesTextInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // 1. Extraer exclusivamente dígitos
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return const TextEditingValue();
    }

    // 2. Contar cuántos dígitos había antes del cursor en el valor nuevo
    int digitsBeforeCursor = 0;
    final rawEnd = newValue.selection.end.clamp(0, newValue.text.length);
    for (int i = 0; i < rawEnd; i++) {
      final code = newValue.text.codeUnitAt(i);
      if (code >= 48 && code <= 57) {
        digitsBeforeCursor++;
      }
    }

    // 3. Formatear dígitos con puntos cada 3 posiciones de derecha a izquierda
    final buffer = StringBuffer();
    int count = 0;
    for (int i = digitsOnly.length - 1; i >= 0; i--) {
      buffer.write(digitsOnly[i]);
      count++;
      if (count % 3 == 0 && i > 0) {
        buffer.write('.');
      }
    }
    final formatted = buffer.toString().split('').reversed.join('');

    // 4. Calcular la nueva posición del cursor manteniendo el conteo de dígitos
    int newOffset = 0;
    int countedDigits = 0;
    for (int i = 0; i < formatted.length; i++) {
      final code = formatted.codeUnitAt(i);
      if (code >= 48 && code <= 57) {
        countedDigits++;
      }
      if (countedDigits == digitsBeforeCursor) {
        newOffset = i + 1;
        break;
      }
    }
    if (digitsBeforeCursor == 0) {
      newOffset = 0;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}
