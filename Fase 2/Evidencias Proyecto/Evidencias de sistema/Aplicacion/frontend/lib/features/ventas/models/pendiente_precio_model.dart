// lib/features/ventas/models/pendiente_precio_model.dart

/// Modelo de datos para un repuesto ingresado por bodega pendiente de asignación de precio (HU-3.8).
class ActivoPendientePrecioModel {
  final String idActivo;
  final String skuQrFisico;
  final int idCategoria;
  final String nombreCategoria;
  final int idSucursalActual;
  final String nombreSucursal;
  final String? ubicacionGalpon;
  final String? ubicacionPasillo;
  final String? ubicacionPallet;
  final String? idVehiculo;
  final String? numeroIngreso;
  final String? marca;
  final String? modelo;
  final int? anio;
  final String? traccion;
  final String? cilindrada;
  final String? combustible;
  final String? transmisionTipo;
  final String tituloRepuesto;
  final String estadoActivo;
  final DateTime? fechaCreacion;
  final List<String> fotografias;
  final int? precioReferencia;
  final int? precioMinimo;
  final int? precioMaximo;
  final String? observacionEstado;

  const ActivoPendientePrecioModel({
    required this.idActivo,
    required this.skuQrFisico,
    required this.idCategoria,
    required this.nombreCategoria,
    required this.idSucursalActual,
    required this.nombreSucursal,
    this.ubicacionGalpon,
    this.ubicacionPasillo,
    this.ubicacionPallet,
    this.idVehiculo,
    this.numeroIngreso,
    this.marca,
    this.modelo,
    this.anio,
    this.traccion,
    this.cilindrada,
    this.combustible,
    this.transmisionTipo,
    required this.tituloRepuesto,
    required this.estadoActivo,
    this.fechaCreacion,
    this.fotografias = const [],
    this.precioReferencia,
    this.precioMinimo,
    this.precioMaximo,
    this.observacionEstado,
  });

  factory ActivoPendientePrecioModel.fromJson(Map<String, dynamic> json) {
    DateTime? fecha;
    if (json['fecha_creacion'] != null) {
      try {
        final raw = json['fecha_creacion'].toString().trim();
        final formattedIso = raw.contains('Z') || raw.contains('+')
            ? raw
            : '${raw.replaceAll(' ', 'T')}Z';
        fecha = DateTime.parse(formattedIso).toLocal();
      } catch (_) {
        try {
          fecha = DateTime.parse(json['fecha_creacion'].toString()).toLocal();
        } catch (_) {}
      }
    }

    final rawFotos = json['fotografias'];
    final List<String> fotosList = [];
    if (rawFotos is List) {
      for (final item in rawFotos) {
        if (item != null && item.toString().trim().isNotEmpty) {
          fotosList.add(item.toString().trim());
        }
      }
    }

    return ActivoPendientePrecioModel(
      idActivo: json['id_activo']?.toString() ?? '',
      skuQrFisico: json['sku_qr_fisico']?.toString() ?? '',
      idCategoria: (json['id_categoria'] as num?)?.toInt() ?? 0,
      nombreCategoria: json['nombre_categoria']?.toString() ?? 'Repuesto',
      idSucursalActual: (json['id_sucursal_actual'] as num?)?.toInt() ?? 0,
      nombreSucursal: json['nombre_sucursal']?.toString() ?? 'Casa Matriz',
      ubicacionGalpon: json['ubicacion_galpon']?.toString(),
      ubicacionPasillo: json['ubicacion_pasillo']?.toString(),
      ubicacionPallet: json['ubicacion_pallet']?.toString(),
      idVehiculo: json['id_vehiculo']?.toString(),
      numeroIngreso: json['numero_ingreso']?.toString(),
      marca: json['marca']?.toString(),
      modelo: json['modelo']?.toString(),
      anio: (json['anio'] as num?)?.toInt(),
      traccion: json['traccion']?.toString(),
      cilindrada: json['cilindrada']?.toString(),
      combustible: json['combustible']?.toString(),
      transmisionTipo: json['transmision_tipo']?.toString(),
      tituloRepuesto: json['titulo_repuesto']?.toString() ?? 'Repuesto Sin Título',
      estadoActivo: json['estado_activo']?.toString() ?? 'En Desarme',
      fechaCreacion: fecha,
      fotografias: fotosList,
      precioReferencia: (json['precio_referencia'] as num?)?.toInt(),
      precioMinimo: (json['precio_minimo'] as num?)?.toInt(),
      precioMaximo: (json['precio_maximo'] as num?)?.toInt(),
      observacionEstado: json['observacion_estado']?.toString() ?? json['observacion']?.toString(),
    );
  }

  // ── Getters Utilitarios para la UI ──────────────────────────────────────────

  /// Retorna el título limpio del vehículo donante sin prefijo redundante de categoría
  /// para evitar repetir "Motor" o "Caja de cambios" cuando ya existe el badge/icono.
  String get tituloVehiculo {
    final parts = [marca, modelo, anio?.toString()].where((p) => p != null && p.isNotEmpty).toList();
    if (parts.isNotEmpty) {
      final joined = parts.join(' ');
      final prefijoCat = '${nombreCategoria.toLowerCase()} - ';
      if (joined.toLowerCase().startsWith(prefijoCat)) {
        return joined.substring(prefijoCat.length).trim();
      }
      return joined;
    }
    final prefijo = '$nombreCategoria - ';
    if (tituloRepuesto.toLowerCase().startsWith(prefijo.toLowerCase())) {
      return tituloRepuesto.substring(prefijo.length).trim();
    }
    return tituloRepuesto;
  }

  /// Retorna la ubicación física en bodega formateada (ej. "Galpón 1 • Pasillo 3 • Pallet 10")
  String get ubicacionDisplay {
    final partes = <String>[];
    final galpon = (ubicacionGalpon ?? '').trim();
    if (galpon.isNotEmpty && galpon != 'S/G') {
      partes.add(galpon.toLowerCase().startsWith('galpón') || galpon.toLowerCase().startsWith('galpon')
          ? galpon
          : 'Galpón: $galpon');
    }
    final pasillo = (ubicacionPasillo ?? '').trim();
    final pasilloVal = pasillo.isNotEmpty ? pasillo : 'S/P';
    partes.add(pasilloVal.toLowerCase().startsWith('pasillo') ? pasilloVal : 'Pasillo: $pasilloVal');

    final pallet = (ubicacionPallet ?? '').trim();
    final palletVal = pallet.isNotEmpty ? pallet : 'S/P';
    partes.add(palletVal.toLowerCase().startsWith('pallet') ? palletVal : 'Pallet: $palletVal');

    return partes.join(' • ');
  }

  /// Retorna la información del vehículo de origen formateada (ej. "Hyundai Accent 2020")
  String get fichaVehiculoDisplay {
    final parts = [marca, modelo, anio?.toString()].where((p) => p != null && p.isNotEmpty).toList();
    return parts.isNotEmpty ? parts.join(' ') : 'Vehículo no especificado';
  }

  /// Retorna las especificaciones mecánicas del repuesto (ej. "1.4L • Gasolina • Manual")
  String get especificacionesDisplay {
    final specs = [cilindrada, combustible, transmisionTipo, traccion]
        .where((s) => s != null && s.isNotEmpty && s != 'N/A')
        .toList();
    return specs.isNotEmpty ? specs.join(' • ') : 'Sin especificaciones técnicas';
  }

  /// Retorna la fecha de ingreso formateada en formato "dd/MM/yyyy HH:mm"
  String get fechaCreacionFormateada {
    if (fechaCreacion == null) return 'Fecha no registrada';
    final dt = fechaCreacion!.toLocal();
    final dia = dt.day.toString().padLeft(2, '0');
    final mes = dt.month.toString().padLeft(2, '0');
    final anio = dt.year;
    final hora = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dia/$mes/$anio $hora:$min';
  }
}

/// DTO de respuesta tras asignar precio de referencia a un activo.
class AsignarPrecioResponseModel {
  final String idActivo;
  final String skuQrFisico;
  final int precioMinimo;
  final int precioMaximo;
  final int precioReferencia;
  final String estadoActivo;
  final String mensaje;

  const AsignarPrecioResponseModel({
    required this.idActivo,
    required this.skuQrFisico,
    required this.precioMinimo,
    required this.precioMaximo,
    required this.precioReferencia,
    required this.estadoActivo,
    required this.mensaje,
  });

  factory AsignarPrecioResponseModel.fromJson(Map<String, dynamic> json) {
    final maxP = (json['precio_maximo'] as num?)?.toInt() ?? (json['precio_referencia'] as num?)?.toInt() ?? 0;
    final minP = (json['precio_minimo'] as num?)?.toInt() ?? maxP;
    return AsignarPrecioResponseModel(
      idActivo: json['id_activo']?.toString() ?? '',
      skuQrFisico: json['sku_qr_fisico']?.toString() ?? '',
      precioMinimo: minP,
      precioMaximo: maxP,
      precioReferencia: (json['precio_referencia'] as num?)?.toInt() ?? maxP,
      estadoActivo: json['estado_activo']?.toString() ?? 'Disponible',
      mensaje: json['mensaje']?.toString() ?? 'Precio asignado exitosamente.',
    );
  }

  String get precioFormateado => _formatearMonto(precioReferencia);
  String get precioMinimoFormateado => _formatearMonto(precioMinimo);
  String get precioMaximoFormateado => _formatearMonto(precioMaximo);
  String get rangoFormateado => precioMinimo == precioMaximo
      ? _formatearMonto(precioMinimo)
      : '${_formatearMonto(precioMinimo)} - ${_formatearMonto(precioMaximo)}';

  static String _formatearMonto(int monto) {
    final str = monto.toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      buffer.write(str[i]);
      count++;
      if (count % 3 == 0 && i > 0) {
        buffer.write('.');
      }
    }
    return '\$${buffer.toString().split('').reversed.join('')}';
  }
}
