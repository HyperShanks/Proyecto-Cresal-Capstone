/// Validador transversal de RUT chileno mediante algoritmo matemático Módulo 11 (HU-12).
class RutValidator {
  RutValidator._();

  /// Limpia cualquier carácter que no sea dígito o K/k, transformando a mayúscula.
  static String clean(String? rut) {
    if (rut == null) return '';
    return rut.replaceAll(RegExp(r'[\.\-\s]'), '').toUpperCase();
  }

  /// Calcula el dígito verificador para un cuerpo numérico de RUT chileno.
  static String? calculateDv(String cuerpo) {
    final cleanCuerpo = cuerpo.replaceAll(RegExp(r'[\.\-\s]'), '').trim();
    if (cleanCuerpo.isEmpty || !RegExp(r'^\d+$').hasMatch(cleanCuerpo)) {
      return null;
    }

    final multiplicadores = [2, 3, 4, 5, 6, 7];
    var suma = 0;
    var idxMult = 0;

    for (var i = cleanCuerpo.length - 1; i >= 0; i--) {
      final digit = int.parse(cleanCuerpo[i]);
      suma += digit * multiplicadores[idxMult];
      idxMult = (idxMult + 1) % multiplicadores.length;
    }

    final resto = suma % 11;
    final resultado = 11 - resto;

    if (resultado == 11) {
      return '0';
    } else if (resultado == 10) {
      return 'K';
    } else {
      return resultado.toString();
    }
  }

  /// Valida matemáticamente un RUT chileno según el algoritmo Módulo 11.
  /// Incluye exención legal para consumidor final genérico (6.666.666-6 / 66666666-6).
  static bool isValid(String? rut) {
    if (rut == null) return false;

    final cleaned = clean(rut);
    if (cleaned.length < 2 || cleaned.length > 10) {
      return false;
    }

    final cuerpo = cleaned.substring(0, cleaned.length - 1);
    final dv = cleaned.substring(cleaned.length - 1);

    if (!RegExp(r'^\d+$').hasMatch(cuerpo) || !RegExp(r'^[0-9K]$').hasMatch(dv)) {
      return false;
    }

    // Exención legal: Consumidor Final genérico para boleta rápida
    if ((cuerpo == '6666666' || cuerpo == '66666666') && dv == '6') {
      return true;
    }

    final expectedDv = calculateDv(cuerpo);
    return expectedDv != null && dv == expectedDv;
  }

  /// Formatea un RUT chileno con puntos y guion (ej. 12.345.678-5).
  static String format(String rut, {bool withDots = true}) {
    final cleaned = clean(rut);
    if (cleaned.length < 2) {
      return rut;
    }

    final cuerpo = cleaned.substring(0, cleaned.length - 1);
    final dv = cleaned.substring(cleaned.length - 1);

    if (!RegExp(r'^\d+$').hasMatch(cuerpo)) {
      return rut;
    }

    if (!withDots) {
      return '$cuerpo-$dv';
    }

    // Agregar puntos separadores de miles
    final formattedCuerpo = cuerpo.replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );

    return '$formattedCuerpo-$dv';
  }
}
