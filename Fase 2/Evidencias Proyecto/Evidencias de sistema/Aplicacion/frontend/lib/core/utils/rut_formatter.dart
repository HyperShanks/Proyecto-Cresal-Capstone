import 'package:flutter/services.dart';
import 'rut_validator.dart';

/// Formateador interactivo de RUT chileno para campos TextFormField.
/// Convierte 'k' a 'K' en tiempo real y formatea con puntos y guion.
class RutFormatter extends TextInputFormatter {
  final bool withDots;

  RutFormatter({this.withDots = true});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    var clean = newValue.text.replaceAll(RegExp(r'[^0-9kK]'), '').toUpperCase();

    if (clean.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Un RUT chileno no excede 10 caracteres (9 dígitos de cuerpo + 1 verificador)
    if (clean.length > 10) {
      clean = clean.substring(0, 10);
    }

    if (clean.length == 1) {
      return TextEditingValue(
        text: clean,
        selection: TextSelection.collapsed(offset: 1),
      );
    }

    final formatted = RutValidator.format(clean, withDots: withDots);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
