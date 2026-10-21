// lib/features/ventas/models/catalogo_model.dart

class CatalogoItem {
  final String idActivo;
  final String skuQrFisico;
  final int? precioReferencia;
  final int? precioMinimo;
  final int? precioMaximo;
  final int idCategoria;
  final String nombreCategoria;
  final int idSucursalActual;
  final String nombreSucursal;
  final String? idVehiculo;
  final String? marca;
  final String? modelo;
  final int? anio;
  final String? traccion;
  final String? cilindrada;
  final String? combustible;
  final String? transmisionTipo;
  final String? ubicacionPasillo;
  final String? ubicacionGalpon;
  final String? ubicacionPallet;
  final String? observacionEstado;
  final String? estadoActivo;
  final String? numeroMotor;
  final List<String> imagenes;
  final int versionLock;
  final int? idEstado;
  final String? reservadoPor;

  const CatalogoItem({
    required this.idActivo,
    required this.skuQrFisico,
    this.precioReferencia,
    this.precioMinimo,
    this.precioMaximo,
    required this.idCategoria,
    required this.nombreCategoria,
    required this.idSucursalActual,
    required this.nombreSucursal,
    this.idVehiculo,
    this.marca,
    this.modelo,
    this.anio,
    this.traccion,
    this.cilindrada,
    this.combustible,
    this.transmisionTipo,
    this.ubicacionPasillo,
    this.ubicacionGalpon,
    this.ubicacionPallet,
    this.observacionEstado,
    this.estadoActivo,
    this.numeroMotor,
    this.imagenes = const [],
    this.versionLock = 1,
    this.idEstado,
    this.reservadoPor,
  });

  bool get esReservado => idEstado == 2 || estadoActivo?.toLowerCase() == 'reservado';

  CatalogoItem copyWith({
    String? idActivo,
    String? skuQrFisico,
    int? precioReferencia,
    int? precioMinimo,
    int? precioMaximo,
    int? idCategoria,
    String? nombreCategoria,
    int? idSucursalActual,
    String? nombreSucursal,
    String? idVehiculo,
    String? marca,
    String? modelo,
    int? anio,
    String? traccion,
    String? cilindrada,
    String? combustible,
    String? transmisionTipo,
    String? ubicacionPasillo,
    String? ubicacionGalpon,
    String? ubicacionPallet,
    String? observacionEstado,
    String? estadoActivo,
    String? numeroMotor,
    List<String>? imagenes,
    int? versionLock,
    int? idEstado,
    String? reservadoPor,
  }) {
    return CatalogoItem(
      idActivo: idActivo ?? this.idActivo,
      skuQrFisico: skuQrFisico ?? this.skuQrFisico,
      precioReferencia: precioReferencia ?? this.precioReferencia,
      precioMinimo: precioMinimo ?? this.precioMinimo,
      precioMaximo: precioMaximo ?? this.precioMaximo,
      idCategoria: idCategoria ?? this.idCategoria,
      nombreCategoria: nombreCategoria ?? this.nombreCategoria,
      idSucursalActual: idSucursalActual ?? this.idSucursalActual,
      nombreSucursal: nombreSucursal ?? this.nombreSucursal,
      idVehiculo: idVehiculo ?? this.idVehiculo,
      marca: marca ?? this.marca,
      modelo: modelo ?? this.modelo,
      anio: anio ?? this.anio,
      traccion: traccion ?? this.traccion,
      cilindrada: cilindrada ?? this.cilindrada,
      combustible: combustible ?? this.combustible,
      transmisionTipo: transmisionTipo ?? this.transmisionTipo,
      ubicacionPasillo: ubicacionPasillo ?? this.ubicacionPasillo,
      ubicacionGalpon: ubicacionGalpon ?? this.ubicacionGalpon,
      ubicacionPallet: ubicacionPallet ?? this.ubicacionPallet,
      observacionEstado: observacionEstado ?? this.observacionEstado,
      estadoActivo: estadoActivo ?? this.estadoActivo,
      numeroMotor: numeroMotor ?? this.numeroMotor,
      imagenes: imagenes ?? this.imagenes,
      versionLock: versionLock ?? this.versionLock,
      idEstado: idEstado ?? this.idEstado,
      reservadoPor: reservadoPor ?? this.reservadoPor,
    );
  }

  factory CatalogoItem.fromJson(Map<String, dynamic> json) {
    return CatalogoItem(
      idActivo: json['id_activo']?.toString() ?? '',
      skuQrFisico: json['sku_qr_fisico']?.toString() ?? '',
      precioReferencia: json['precio_referencia'] as int?,
      precioMinimo: json['precio_minimo'] as int?,
      precioMaximo: json['precio_maximo'] as int?,
      idCategoria: json['id_categoria'] as int? ?? 0,
      nombreCategoria: json['nombre_categoria']?.toString() ?? 'Sin categoría',
      idSucursalActual: json['id_sucursal_actual'] as int? ?? 0,
      nombreSucursal: json['nombre_sucursal']?.toString() ?? 'Sucursal no especificada',
      idVehiculo: json['id_vehiculo']?.toString(),
      marca: json['marca']?.toString(),
      modelo: json['modelo']?.toString(),
      anio: json['anio'] as int?,
      traccion: json['traccion']?.toString(),
      cilindrada: json['cilindrada']?.toString(),
      combustible: json['combustible']?.toString(),
      transmisionTipo: json['transmision_tipo']?.toString(),
      ubicacionPasillo: json['ubicacion_pasillo']?.toString(),
      ubicacionGalpon: json['ubicacion_galpon']?.toString(),
      ubicacionPallet: json['ubicacion_pallet']?.toString(),
      observacionEstado: json['observacion_estado']?.toString(),
      estadoActivo: json['estado_activo']?.toString(),
      numeroMotor: json['numero_motor']?.toString() ?? json['numeroMotor']?.toString(),
      imagenes: (json['imagenes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      versionLock: json['version_lock'] as int? ?? 1,
      idEstado: json['id_estado'] as int?,
      reservadoPor: json['reservado_por']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_activo': idActivo,
      'sku_qr_fisico': skuQrFisico,
      'precio_referencia': precioReferencia,
      'precio_minimo': precioMinimo,
      'precio_maximo': precioMaximo,
      'id_categoria': idCategoria,
      'nombre_categoria': nombreCategoria,
      'id_sucursal_actual': idSucursalActual,
      'nombre_sucursal': nombreSucursal,
      'id_vehiculo': idVehiculo,
      'marca': marca,
      'modelo': modelo,
      'anio': anio,
      'traccion': traccion,
      'cilindrada': cilindrada,
      'combustible': combustible,
      'transmision_tipo': transmisionTipo,
      'ubicacion_pasillo': ubicacionPasillo,
      'ubicacion_galpon': ubicacionGalpon,
      'ubicacion_pallet': ubicacionPallet,
      'observacion_estado': observacionEstado,
      'estado_activo': estadoActivo,
      'numero_motor': numeroMotor,
      'imagenes': imagenes,
      'version_lock': versionLock,
      'id_estado': idEstado,
      'reservado_por': reservadoPor,
    };
  }

  /// Título compuesto para la tarjeta de producto (ej: "Motor - Toyota Yaris 2018")
  String get tituloRepuesto {
    final vehiculoParts = <String>[];
    if (marca != null && marca!.isNotEmpty) vehiculoParts.add(marca!);
    if (modelo != null && modelo!.isNotEmpty) vehiculoParts.add(modelo!);
    if (anio != null) vehiculoParts.add(anio.toString());

    if (vehiculoParts.isNotEmpty) {
      return '$nombreCategoria - ${vehiculoParts.join(' ')}';
    }
    return nombreCategoria;
  }

  /// Título limpio del vehículo donante sin prefijo redundante de categoría (ej: "DODGE RAM QUAD CAB 4X4 5.9 2008")
  String get tituloVehiculo {
    final vehiculoParts = <String>[];
    if (marca != null && marca!.isNotEmpty) vehiculoParts.add(marca!);
    if (modelo != null && modelo!.isNotEmpty) vehiculoParts.add(modelo!);
    if (anio != null) vehiculoParts.add(anio.toString());

    if (vehiculoParts.isNotEmpty) {
      final joined = vehiculoParts.join(' ');
      final prefijoCat = '${nombreCategoria.toLowerCase()} - ';
      if (joined.toLowerCase().startsWith(prefijoCat)) {
        return joined.substring(prefijoCat.length).trim();
      }
      return joined;
    }
    return nombreCategoria;
  }

  /// Ubicación física en bodega formateada con el mismo método de las tareas de bodega (separada con punto)
  String get ubicacionFormateada {
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

  /// Formato de monto en pesos chilenos
  static String formatMonto(int? monto) {
    if (monto == null) return '\$0';
    final valor = monto.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
    return '\$$valor';
  }

  /// Formato de moneda chilena (CLP) con separadores de miles
  String get precioFormateado {
    if (precioReferencia == null) return 'Consultar precio';
    return formatMonto(precioReferencia);
  }

  /// Precio sugerido / lista (precioMaximo o precioReferencia)
  int? get precioSugerido => precioMaximo ?? precioReferencia;
  String get precioSugeridoFormateado => formatMonto(precioSugerido);

  /// Rango de precios formateado (ej. "$80.000 - $120.000")
  String get rangoPrecioFormateado {
    if (precioMinimo != null && precioMaximo != null) {
      if (precioMinimo == precioMaximo) {
        return formatMonto(precioMinimo);
      }
      return '${formatMonto(precioMinimo)} - ${formatMonto(precioMaximo)}';
    }
    if (precioReferencia != null) {
      return formatMonto(precioReferencia);
    }
    return 'Consultar precio';
  }
}

class PaginatedCatalogoResponse {
  final List<CatalogoItem> items;
  final int totalCount;
  final int limit;
  final int offset;
  final int pendientesTasacionCount;

  const PaginatedCatalogoResponse({
    required this.items,
    required this.totalCount,
    required this.limit,
    required this.offset,
    this.pendientesTasacionCount = 0,
  });

  factory PaginatedCatalogoResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    final items = rawItems
        .map((item) => CatalogoItem.fromJson(item as Map<String, dynamic>))
        .toList();

    return PaginatedCatalogoResponse(
      items: items,
      totalCount: json['total_count'] as int? ?? 0,
      limit: json['limit'] as int? ?? 15,
      offset: json['offset'] as int? ?? 0,
      pendientesTasacionCount: json['pendientes_tasacion_count'] as int? ?? 0,
    );
  }
}
