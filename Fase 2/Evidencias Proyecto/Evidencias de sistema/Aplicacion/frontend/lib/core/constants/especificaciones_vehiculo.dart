// lib/core/constants/especificaciones_vehiculo.dart

/// Opciones estandarizadas para Tipo de Combustible.
class OpcionesCombustible {
  static const String seleccionar = 'Seleccionar';
  static const String otro = 'Otro...';

  static const List<String> lista = [
    'Gasolina',
    'Diésel',
    'Híbrido',
    'Eléctrico',
    otro,
  ];

  static const List<String> listaConSeleccionar = [
    seleccionar,
    'Gasolina',
    'Diésel',
    'Híbrido',
    'Eléctrico',
    otro,
  ];

  static const List<String> listaFiltros = [
    'Todos',
    'Gasolina',
    'Diésel',
    'Híbrido',
    'Eléctrico',
    otro,
  ];
}

/// Opciones estandarizadas para Tipo de Transmisión.
class OpcionesTransmision {
  static const String seleccionar = 'Seleccionar';
  static const String otro = 'Otro...';

  static const List<String> lista = [
    'Mecánica',
    'Automática',
    'Semiautomática',
    otro,
  ];

  static const List<String> listaConSeleccionar = [
    seleccionar,
    'Mecánica',
    'Automática',
    'Semiautomática',
    otro,
  ];

  static const List<String> listaFiltros = [
    'Todas',
    'Mecánica',
    'Automática',
    'Semiautomática',
    otro,
  ];
}

/// Opciones estandarizadas para Tipo de Tracción.
class OpcionesTraccion {
  static const String seleccionar = 'Seleccionar';
  static const String otro = 'Otro...';

  static const List<String> lista = [
    '4x2 Delantera',
    '4x2 Trasera',
    '4x4 Conectable (4WD)',
    '4x4 Permanente (AWD)',
    otro,
  ];

  static const List<String> listaConSeleccionar = [
    seleccionar,
    '4x2 Delantera',
    '4x2 Trasera',
    '4x4 Conectable (4WD)',
    '4x4 Permanente (AWD)',
    otro,
  ];

  static const List<String> listaFiltros = [
    'Todas',
    '4x2 Delantera',
    '4x2 Trasera',
    '4x4 Conectable (4WD)',
    '4x4 Permanente (AWD)',
    otro,
  ];
}

/// Opciones estandarizadas para Ubicaciones en Bodega.
class OpcionesUbicacionBodega {
  /// Galpones numéricos: '1', '2', '3'
  static const List<String> galpones = ['1', '2', '3'];

  /// Pasillos alfabéticos: 'A', 'B', 'C', 'D', 'E', 'F', 'G'
  static const List<String> pasillos = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];
}
