/// Resultado del parseo inteligente de la descripción/modelo de un vehículo.
class InferenciaVehiculoResult {
  final String? cilindrada;
  final String transmision;
  final String combustible;
  final String traccion;

  const InferenciaVehiculoResult({
    this.cilindrada,
    required this.transmision,
    required this.combustible,
    required this.traccion,
  });
}

/// Utilidad para inferir y auto-completar especificaciones técnicas (cilindrada,
/// transmisión, combustible, tracción) a partir del texto ingresado en Marca y Modelo.
/// Basado en los patrones reales de la Matriz Central de Los Pinos (Cresal).
class VehiculoParserUtil {
  /// Extrae la cilindrada en formato estándar (ej: "1.6", "2.0", "2.4").
  static String? extraerCilindrada(String modelo) {
    if (modelo.trim().isEmpty) return null;

    // 1. Patrón decimal estándar con punto o coma (ej: 1.4, 2,4, 1.6L, 1.6I, 2.0i, 3.8 AUT)
    final matchDecimal = RegExp(r'\b([0-9][.,][0-9])(?:[a-zA-Z\s])?\b').firstMatch(modelo);
    if (matchDecimal != null) {
      return matchDecimal.group(1)!.replaceAll(',', '.');
    }

    // 2. Formato centímetros cúbicos (ej: 1600cc, 2000 cc, 2400)
    final matchCc = RegExp(r'\b(1[0-9]{3}|2[0-9]{3}|3[0-9]{3})\s*(?:cc)?\b', caseSensitive: false).firstMatch(modelo);
    if (matchCc != null) {
      final ccVal = int.tryParse(matchCc.group(1)!);
      if (ccVal != null) {
        return (ccVal / 1000).toStringAsFixed(1);
      }
    }

    return null;
  }

  /// Determina si la transmisión es 'Automática' o 'Mecánica'.
  static String extraerTransmision(String modelo) {
    final upper = modelo.toUpperCase();
    final esAutomatica = RegExp(r'\b(AUT|AUTOMATICA|AUTOMATICO|AT|A/T|CVT|TIPTRONIC|DSG)\b').hasMatch(upper);
    return esAutomatica ? 'Automática' : 'Mecánica';
  }

  /// Determina el combustible: 'Gasolina', 'Diésel' o 'Híbrido'.
  static String extraerCombustible(String modelo, [String? marca]) {
    final upper = '${marca ?? ""} $modelo'.toUpperCase();

    // 1. Detección de Híbridos
    if (RegExp(r'\b(HIBRIDO|HYBRID|PRIUS|HEV|PHEV)\b').hasMatch(upper)) {
      return 'Híbrido';
    }

    // 2. Nomenclaturas técnicas directas de motores Diésel
    if (RegExp(r'\b(DIESEL|PETROLEO|PETROLERO|HDI|CRDI|TDI|D-4D|TD|TURBO DIESEL|CDI|DCI|TDCI|D4HA|4D56|YD25)\b').hasMatch(upper)) {
      return 'Diésel';
    }

    // 3. Camionetas / Utilitarios de trabajo en Chile que son históricamente diésel
    const utilitariosDiesel = [
      'DMAX', 'D-MAX', 'HILUX', 'ACTYON', 'L200', 'L-200', 'NAVARA',
      'NP300', 'AMAROK', 'RANGER', 'BT-50', 'BT50', 'TERRANO',
      'BOXER', 'DUCATO', 'PORTER', 'CANTER', 'WINGLE'
    ];
    for (final tag in utilitariosDiesel) {
      if (upper.contains(tag)) return 'Diésel';
    }

    // 4. Automóviles de pasajeros convencionales
    return 'Gasolina';
  }

  /// Determina la tracción estandarizada:
  /// - '4x4 Permanente (AWD)'
  /// - '4x4 Conectable (4WD)'
  /// - '4x2 Trasera'
  /// - '4x2 Delantera'
  static String extraerTraccion(String modelo, [String? marca]) {
    final upperMarca = (marca ?? '').toUpperCase();
    final upperTexto = '$upperMarca $modelo'.toUpperCase();

    // 1. 4x4 Permanente (AWD) - Gama Subaru o siglas AWD/4Motion/Quattro/4Matic
    if (upperMarca.contains('SUBARU') ||
        RegExp(r'\b(AWD|4MOTION|ALL GRIP|QUATTRO|4MATIC|PERMANENTE)\b').hasMatch(upperTexto)) {
      return '4x4 Permanente (AWD)';
    }

    // 2. 4x4 Conectable (4WD) - Camionetas y todoterrenos con 4x4 / 4WD
    if (RegExp(r'\b(4X4|4WD|CONECTABLE)\b').hasMatch(upperTexto)) {
      return '4x4 Conectable (4WD)';
    }

    // 3. 4x2 Trasera - Pickups 4x2, camiones medianos, furgones pesados (H1, Porter, Canter) o BMW/Mercedes sedan
    const pickupsTrasera = [
      'DMAX', 'D-MAX', 'HILUX', 'L200', 'L-200', 'NAVARA', 'NP300', 'AMAROK',
      'RANGER', 'BT-50', 'TERRANO', 'PORTER', 'H-1', 'H1', 'CANTER', 'NPR',
      'NKR', 'D100', 'C-10', 'SILVERADO', 'F150', 'F-150', 'WINGLE'
    ];
    for (final p in pickupsTrasera) {
      if (upperTexto.contains(p)) return '4x2 Trasera';
    }
    if ((upperMarca.contains('BMW') || upperMarca.contains('MERCEDES')) &&
        !upperTexto.contains('A-CLASS') &&
        !upperTexto.contains('CLASE A') &&
        !upperTexto.contains('B-CLASS') &&
        !upperTexto.contains('CLASE B')) {
      return '4x2 Trasera';
    }

    // 4. 4x2 Delantera - Automóviles comunes de tracción delantera (FWD)
    return '4x2 Delantera';
  }

  /// Ejecuta todas las inferencias y retorna el resultado unificado.
  static InferenciaVehiculoResult inferir({
    required String modelo,
    String? marca,
  }) {
    return InferenciaVehiculoResult(
      cilindrada: extraerCilindrada(modelo),
      transmision: extraerTransmision(modelo),
      combustible: extraerCombustible(modelo, marca),
      traccion: extraerTraccion(modelo, marca),
    );
  }
}
