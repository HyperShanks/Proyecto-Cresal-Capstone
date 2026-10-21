/// DTOs tipados para el registro y confirmación de cobros en Caja (SPEC-HU-03).
library;

class TransaccionPagoItemModel {
  final String metodo;
  final int monto;

  TransaccionPagoItemModel({
    required this.metodo,
    required this.monto,
  });

  factory TransaccionPagoItemModel.fromJson(Map<String, dynamic> json) =>
      TransaccionPagoItemModel(
        metodo: json['metodo'] as String? ?? 'Efectivo',
        monto: json['monto'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'metodo': metodo,
        'monto': monto,
      };

  TransaccionPagoItemModel copyWith({
    String? metodo,
    int? monto,
  }) {
    return TransaccionPagoItemModel(
      metodo: metodo ?? this.metodo,
      monto: monto ?? this.monto,
    );
  }
}

class RegistrarCobroRequestModel {
  final String tipoOperacion;
  final String idDocumento;
  final String modalidad;
  final int montoDeclarado;
  final List<TransaccionPagoItemModel> pagos;
  final String? skuActivoAtribuido;
  final bool? forzarAtribucion;

  RegistrarCobroRequestModel({
    required this.tipoOperacion,
    required this.idDocumento,
    required this.modalidad,
    required this.montoDeclarado,
    required this.pagos,
    this.skuActivoAtribuido,
    this.forzarAtribucion,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'tipo_operacion': tipoOperacion,
      'id_documento': idDocumento,
      'modalidad': modalidad,
      'monto_declarado': montoDeclarado,
      'pagos': pagos.map((p) => p.toJson()).toList(),
    };
    if (skuActivoAtribuido != null) {
      map['sku_activo_atribuido'] = skuActivoAtribuido;
    }
    if (forzarAtribucion != null) {
      map['forzar_atribucion'] = forzarAtribucion;
    }
    return map;
  }
}

class ValidarActivoBackorderRequestModel {
  final String idDocumento;
  final String skuActivo;

  ValidarActivoBackorderRequestModel({
    required this.idDocumento,
    required this.skuActivo,
  });

  Map<String, dynamic> toJson() => {
        'id_documento': idDocumento,
        'sku_activo': skuActivo,
      };
}

class ActivoDetalleBackorderModel {
  final String sku;
  final String? categoria;
  final String? marca;
  final String? modelo;
  final int? anio;
  final String? cilindrada;
  final String? combustible;
  final String? transmision;
  final String? patente;
  final String? vin;
  final String? ubicacion;
  final int? precioReferencia;
  final String? estadoConservacion;

  ActivoDetalleBackorderModel({
    required this.sku,
    this.categoria,
    this.marca,
    this.modelo,
    this.anio,
    this.cilindrada,
    this.combustible,
    this.transmision,
    this.patente,
    this.vin,
    this.ubicacion,
    this.precioReferencia,
    this.estadoConservacion,
  });

  factory ActivoDetalleBackorderModel.fromJson(Map<String, dynamic> json) =>
      ActivoDetalleBackorderModel(
        sku: json['sku'] as String? ?? '',
        categoria: json['categoria'] as String?,
        marca: json['marca'] as String?,
        modelo: json['modelo'] as String?,
        anio: json['anio'] as int?,
        cilindrada: json['cilindrada'] as String?,
        combustible: json['combustible'] as String?,
        transmision: json['transmision'] as String?,
        patente: json['patente'] as String?,
        vin: json['vin'] as String?,
        ubicacion: json['ubicacion'] as String?,
        precioReferencia: json['precio_referencia'] as int?,
        estadoConservacion: json['estado_conservacion'] as String?,
      );
}

class ValidarActivoBackorderResponseModel {
  final bool coincide;
  final List<String> discrepancias;
  final String mensaje;
  final ActivoDetalleBackorderModel? activoDetalle;

  ValidarActivoBackorderResponseModel({
    required this.coincide,
    required this.discrepancias,
    required this.mensaje,
    this.activoDetalle,
  });

  factory ValidarActivoBackorderResponseModel.fromJson(Map<String, dynamic> json) =>
      ValidarActivoBackorderResponseModel(
        coincide: json['coincide'] as bool? ?? false,
        discrepancias: (json['discrepancias'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        mensaje: json['mensaje'] as String? ?? '',
        activoDetalle: json['activo_detalle'] != null
            ? ActivoDetalleBackorderModel.fromJson(
                json['activo_detalle'] as Map<String, dynamic>)
            : null,
      );
}

class RegistrarCobroResponseModel {
  final bool success;
  final String mensaje;
  final String folio;
  final int montoCobrado;
  final int nuevoSaldoPendiente;
  final String estadoActualizado;
  final List<String> transaccionesIds;
  final String? qrGenerado;

  RegistrarCobroResponseModel({
    required this.success,
    required this.mensaje,
    required this.folio,
    required this.montoCobrado,
    required this.nuevoSaldoPendiente,
    required this.estadoActualizado,
    required this.transaccionesIds,
    this.qrGenerado,
  });

  factory RegistrarCobroResponseModel.fromJson(Map<String, dynamic> json) =>
      RegistrarCobroResponseModel(
        success: json['success'] as bool? ?? false,
        mensaje: json['mensaje'] as String? ?? '',
        folio: json['folio'] as String? ?? '',
        montoCobrado: json['monto_cobrado'] as int? ?? 0,
        nuevoSaldoPendiente: json['nuevo_saldo_pendiente'] as int? ?? 0,
        estadoActualizado: json['estado_actualizado'] as String? ?? '',
        transaccionesIds: (json['transacciones_ids'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [],
        qrGenerado: json['qr_generado'] as String?,
      );
}
