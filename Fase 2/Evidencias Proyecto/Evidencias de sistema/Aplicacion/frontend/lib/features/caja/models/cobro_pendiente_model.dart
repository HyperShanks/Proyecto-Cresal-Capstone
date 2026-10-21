/// DTOs tipados para la Bandeja de Órdenes Pendientes y Cobros de Caja (SPEC-HU-4.2 / CRES-214).
library;

class ArticuloResumenModel {
  final int cantidad;
  final String tipo; // 'INVENTARIADO' | 'MISCELANEO' | 'DESARME' | 'RESERVA'
  final String descripcion;
  final String? sku;
  final int precio;
  final int subtotal;
  final String? categoria;
  final String? marca;
  final String? modelo;
  final int? anio;
  final String? detalleTecnico;

  ArticuloResumenModel({
    required this.cantidad,
    required this.tipo,
    required this.descripcion,
    this.sku,
    required this.precio,
    required this.subtotal,
    this.categoria,
    this.marca,
    this.modelo,
    this.anio,
    this.detalleTecnico,
  });

  bool get esInventariado => tipo == 'INVENTARIADO';

  /// Nombre técnico identificable del producto: Categoría - Marca Modelo Año (Detalle Técnico)
  String get nombreDisplay {
    if (marca != null || modelo != null || anio != null) {
      final vehiculoParts = <String>[];
      if (marca != null && marca!.isNotEmpty) vehiculoParts.add(marca!);
      if (modelo != null && modelo!.isNotEmpty) vehiculoParts.add(modelo!);
      if (anio != null) vehiculoParts.add(anio.toString());

      final cat = (categoria != null && categoria!.isNotEmpty)
          ? categoria!
          : (descripcion.contains(' - ') ? descripcion.split(' - ').first : descripcion);

      final tec = (detalleTecnico != null && detalleTecnico!.isNotEmpty)
          ? ' ($detalleTecnico)'
          : '';

      if (vehiculoParts.isNotEmpty) {
        return '$cat - ${vehiculoParts.join(' ')}$tec';
      }
    }
    return descripcion;
  }

  factory ArticuloResumenModel.fromJson(Map<String, dynamic> json) =>
      ArticuloResumenModel(
        cantidad: json['cantidad'] as int? ?? 1,
        tipo: json['tipo'] as String? ?? 'DESARME',
        descripcion: json['descripcion'] as String? ?? '',
        sku: json['sku'] as String?,
        precio: json['precio'] as int? ?? 0,
        subtotal: json['subtotal'] as int? ?? 0,
        categoria: json['categoria'] as String?,
        marca: json['marca'] as String?,
        modelo: json['modelo'] as String?,
        anio: json['anio'] as int?,
        detalleTecnico: json['detalle_tecnico'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'cantidad': cantidad,
        'tipo': tipo,
        'descripcion': descripcion,
        'sku': sku,
        'precio': precio,
        'subtotal': subtotal,
        'categoria': categoria,
        'marca': marca,
        'modelo': modelo,
        'anio': anio,
        'detalle_tecnico': detalleTecnico,
      };
}

class BackorderEspecificacionesModel {
  final String marca;
  final String modelo;
  final int? anio;
  final String categoria;
  final String? cilindrada;
  final String? combustible;
  final String transito;

  BackorderEspecificacionesModel({
    required this.marca,
    required this.modelo,
    this.anio,
    required this.categoria,
    this.cilindrada,
    this.combustible,
    required this.transito,
  });

  factory BackorderEspecificacionesModel.fromJson(Map<String, dynamic> json) =>
      BackorderEspecificacionesModel(
        marca: json['marca'] as String? ?? '',
        modelo: json['modelo'] as String? ?? '',
        anio: json['anio'] as int?,
        categoria: json['categoria'] as String? ?? '',
        cilindrada: json['cilindrada'] as String?,
        combustible: json['combustible'] as String?,
        transito: json['transito'] as String? ?? 'En Tránsito',
      );

  Map<String, dynamic> toJson() => {
        'marca': marca,
        'modelo': modelo,
        'anio': anio,
        'categoria': categoria,
        'cilindrada': cilindrada,
        'combustible': combustible,
        'transito': transito,
      };
}

class HistorialAbonoItemModel {
  final String idPago;
  final int monto;
  final String metodoPago;
  final DateTime fechaPago;
  final String fechaPagoFormateada;
  final String horaPagoFormateada;
  final String estadoPago;

  HistorialAbonoItemModel({
    required this.idPago,
    required this.monto,
    required this.metodoPago,
    required this.fechaPago,
    required this.fechaPagoFormateada,
    required this.horaPagoFormateada,
    this.estadoPago = 'Procesado',
  });

  factory HistorialAbonoItemModel.fromJson(Map<String, dynamic> json) =>
      HistorialAbonoItemModel(
        idPago: json['id_pago']?.toString() ?? '',
        monto: json['monto'] as int? ?? 0,
        metodoPago: json['metodo_pago'] as String? ?? 'Efectivo',
        fechaPago: json['fecha_pago'] != null
            ? DateTime.tryParse(json['fecha_pago'] as String) ?? DateTime.now()
            : DateTime.now(),
        fechaPagoFormateada: json['fecha_pago_formateada'] as String? ?? '',
        horaPagoFormateada: json['hora_pago_formateada'] as String? ?? '',
        estadoPago: json['estado_pago'] as String? ?? 'Procesado',
      );

  Map<String, dynamic> toJson() => {
        'id_pago': idPago,
        'monto': monto,
        'metodo_pago': metodoPago,
        'fecha_pago': fechaPago.toIso8601String(),
        'fecha_pago_formateada': fechaPagoFormateada,
        'hora_pago_formateada': horaPagoFormateada,
        'estado_pago': estadoPago,
      };
}

class CobroPendienteModel {
  final String idReferencia;
  final String folioDocumento;
  final String tipoOperacion; // 'VENTA' | 'BACKORDER'
  final String estadoDocumento;
  final String clienteNombre;
  final String clienteRut;
  final String vendedorNombre;
  final DateTime fechaEmision;
  final String fechaEmisionFormateada;
  final String horaEmisionFormateada;
  final int totalOperacion;
  final int descuento;
  final int abonoPrevio;
  final int abonoRequerido;
  final int saldoPendiente;
  final int montoACobrar;
  final List<HistorialAbonoItemModel> historialAbonos;
  final List<ArticuloResumenModel> articulos;
  final BackorderEspecificacionesModel? especificacionesBackorder;

  CobroPendienteModel({
    required this.idReferencia,
    required this.folioDocumento,
    required this.tipoOperacion,
    required this.estadoDocumento,
    required this.clienteNombre,
    required this.clienteRut,
    required this.vendedorNombre,
    required this.fechaEmision,
    required this.fechaEmisionFormateada,
    required this.horaEmisionFormateada,
    required this.totalOperacion,
    this.descuento = 0,
    required this.abonoPrevio,
    this.abonoRequerido = 0,
    this.saldoPendiente = 0,
    required this.montoACobrar,
    this.historialAbonos = const [],
    required this.articulos,
    this.especificacionesBackorder,
  });

  bool get esVenta => tipoOperacion == 'VENTA';
  bool get esBackorder => tipoOperacion == 'BACKORDER';
  bool get esPrimerAbono => abonoPrevio == 0;
  int get pisoPrimerAbono => esPrimerAbono ? abonoRequerido : 0;

  factory CobroPendienteModel.fromJson(Map<String, dynamic> json) {
    final totalOp = json['total_operacion'] as int? ?? 0;
    final desc = json['descuento'] as int? ?? 0;
    final abonoPrev = json['abono_previo'] as int? ?? 0;
    final saldoPen = json['saldo_pendiente'] as int? ?? (totalOp - abonoPrev);

    return CobroPendienteModel(
      idReferencia: json['id_referencia']?.toString() ?? '',
      folioDocumento: json['folio_documento'] as String? ?? '',
      tipoOperacion: (json['tipo_operacion'] as String? ?? 'VENTA').toUpperCase(),
      estadoDocumento: json['estado_documento'] as String? ?? 'Pendiente',
      clienteNombre: json['cliente_nombre'] as String? ?? 'Cliente',
      clienteRut: json['cliente_rut'] as String? ?? '',
      vendedorNombre: json['vendedor_nombre'] as String? ?? 'Vendedor',
      fechaEmision: json['fecha_emision'] != null
          ? DateTime.tryParse(json['fecha_emision'] as String) ?? DateTime.now()
          : DateTime.now(),
      fechaEmisionFormateada: json['fecha_emision_formateada'] as String? ?? '',
      horaEmisionFormateada: json['hora_emision_formateada'] as String? ?? '',
      totalOperacion: totalOp,
      descuento: desc,
      abonoPrevio: abonoPrev,
      abonoRequerido: json['abono_requerido'] as int? ?? 0,
      saldoPendiente: saldoPen,
      montoACobrar: json['monto_a_cobrar'] as int? ?? 0,
      historialAbonos: (json['historial_abonos'] as List<dynamic>?)
              ?.map((e) =>
                  HistorialAbonoItemModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      articulos: (json['articulos'] as List<dynamic>?)
              ?.map((e) =>
                  ArticuloResumenModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      especificacionesBackorder: json['especificaciones_backorder'] != null
          ? BackorderEspecificacionesModel.fromJson(
              json['especificaciones_backorder'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id_referencia': idReferencia,
        'folio_documento': folioDocumento,
        'tipo_operacion': tipoOperacion,
        'estado_documento': estadoDocumento,
        'cliente_nombre': clienteNombre,
        'cliente_rut': clienteRut,
        'vendedor_nombre': vendedorNombre,
        'fecha_emision': fechaEmision.toIso8601String(),
        'fecha_emision_formateada': fechaEmisionFormateada,
        'hora_emision_formateada': horaEmisionFormateada,
        'total_operacion': totalOperacion,
        'abono_previo': abonoPrevio,
        'abono_requerido': abonoRequerido,
        'saldo_pendiente': saldoPendiente,
        'monto_a_cobrar': montoACobrar,
        'historial_abonos': historialAbonos.map((e) => e.toJson()).toList(),
        'articulos': articulos.map((e) => e.toJson()).toList(),
        'especificaciones_backorder': especificacionesBackorder?.toJson(),
      };
}
