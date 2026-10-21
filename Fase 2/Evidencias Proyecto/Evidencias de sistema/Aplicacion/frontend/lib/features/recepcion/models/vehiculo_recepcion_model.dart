/// Modelo de datos para recepción vehicular en patio (SPEC-22).
/// Alineado exactamente con las 13 columnas (A a M) de la Matriz Central de Los Pinos.
class VehiculoRecepcionModel {
  final String idVehiculo;
  final String numeroIngreso;
  final String? patente;
  final String? factura;
  final DateTime? fechaIngreso;
  final String? origen;
  final String marca;
  final String modelo;
  final int? anio;
  final String? color;
  final String? numeroMotor;
  final String destino;
  final String? grua;
  final String? observaciones;
  final String? traccion;
  final String? estado;
  final DateTime? fechaCreacion;

  const VehiculoRecepcionModel({
    required this.idVehiculo,
    required this.numeroIngreso,
    this.patente,
    this.factura,
    this.fechaIngreso,
    this.origen,
    required this.marca,
    required this.modelo,
    this.anio,
    this.color,
    this.numeroMotor,
    this.destino = 'DESARME',
    this.grua,
    this.observaciones,
    this.traccion,
    this.estado = 'Activo',
    this.fechaCreacion,
  });

  bool get esSppu => patente == null || patente!.startsWith('SPPU-') || patente == 'S/PPU';

  String get fechaIngresoFormateada {
    if (fechaIngreso == null) return 'S/I';
    return '${fechaIngreso!.day.toString().padLeft(2, '0')}/${fechaIngreso!.month.toString().padLeft(2, '0')}/${fechaIngreso!.year}';
  }

  factory VehiculoRecepcionModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseFecha(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return null;
      }
    }

    return VehiculoRecepcionModel(
      idVehiculo: (json['id_vehiculo'] ?? '').toString(),
      numeroIngreso: (json['numero_ingreso'] ?? '').toString(),
      patente: json['patente']?.toString(),
      factura: json['factura']?.toString(),
      fechaIngreso: parseFecha(json['fecha_ingreso']),
      origen: json['origen']?.toString(),
      marca: (json['marca'] ?? 'DESCONOCIDA').toString(),
      modelo: (json['modelo'] ?? 'DESCONOCIDO').toString(),
      anio: json['anio'] is int
          ? json['anio'] as int
          : int.tryParse(json['anio']?.toString() ?? ''),
      color: json['color']?.toString(),
      numeroMotor: json['numero_motor']?.toString(),
      destino: (json['destino'] ?? 'DESARME').toString(),
      grua: json['grua']?.toString(),
      observaciones: json['observaciones']?.toString(),
      traccion: json['traccion']?.toString(),
      estado: (json['estado'] ?? 'Activo').toString(),
      fechaCreacion: parseFecha(json['fecha_creacion']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id_vehiculo': idVehiculo,
        'numero_ingreso': numeroIngreso,
        'patente': patente,
        'factura': factura,
        'fecha_ingreso': fechaIngreso?.toIso8601String().substring(0, 10),
        'origen': origen,
        'marca': marca,
        'modelo': modelo,
        'anio': anio,
        'color': color,
        'numero_motor': numeroMotor,
        'destino': destino,
        'grua': grua,
        'observaciones': observaciones,
        'traccion': traccion,
        'estado': estado,
      };

  /// Genera una fila en formato TSV (Tab-Separated Values) compatible con pegado directo en Excel (Columnas A a M).
  String toTsvRow() {
    final fechaStr = fechaIngreso != null
        ? '${fechaIngreso!.year}-${fechaIngreso!.month.toString().padLeft(2, '0')}-${fechaIngreso!.day.toString().padLeft(2, '0')}'
        : '';
    final obsLimpia = (observaciones ?? '').replaceAll('\t', ' ').replaceAll('\n', ' ');
    return [
      numeroIngreso,
      patente ?? '',
      factura ?? '',
      fechaStr,
      origen ?? '',
      marca,
      modelo,
      anio?.toString() ?? '',
      color ?? '',
      numeroMotor ?? '',
      destino,
      grua ?? '',
      obsLimpia,
    ].join('\t');
  }

  /// Retorna un texto formateado con todos los campos y sus valores para el portapapeles.
  String toTextoCamposValores() {
    final fechaStr = fechaIngreso != null
        ? '${fechaIngreso!.year}-${fechaIngreso!.month.toString().padLeft(2, '0')}-${fechaIngreso!.day.toString().padLeft(2, '0')}'
        : 'S/I';
    return [
      'N° Ingreso: $numeroIngreso',
      'Patente: ${patente ?? "S/PPU"}',
      'Factura: ${factura ?? "S/I"}',
      'Fecha Ingreso: $fechaStr',
      'Origen: ${origen ?? "S/I"}',
      'Marca: $marca',
      'Modelo: $modelo',
      'Año: ${anio?.toString() ?? "S/I"}',
      'Color: ${color ?? "S/I"}',
      'N° Motor: ${numeroMotor ?? "S/I"}',
      'Destino: $destino',
      'Grúa: ${grua ?? "S/I"}',
      'Observaciones: ${observaciones ?? "Sin observaciones"}',
    ].join('\n');
  }

  static String tsvHeaders() {
    return [
      'N° Ingreso',
      'Patente',
      'Factura',
      'Fecha ingreso',
      'Origen',
      'Marca',
      'Modelo',
      'Año',
      'Color',
      'N° Motor',
      'Destino',
      'GRUA',
      'OBSERVACIONES',
    ].join('\t');
  }
}
