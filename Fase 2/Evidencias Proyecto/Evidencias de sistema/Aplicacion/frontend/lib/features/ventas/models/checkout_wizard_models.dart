/// DTO para la gestión del cliente en el Checkout Wizard CRM (SPEC-HU-05)
class ClienteWizardModel {
  final String idCliente;
  final String rut;
  final String nombres;
  final String apellidos;
  final String? telefono;
  final String? correo;
  final String? comuna;
  final bool consentimientoLegal;
  final String estado;

  const ClienteWizardModel({
    required this.idCliente,
    required this.rut,
    required this.nombres,
    required this.apellidos,
    this.telefono,
    this.correo,
    this.comuna,
    this.consentimientoLegal = true,
    this.estado = 'Activo',
  });

  String get nombreCompleto => '$nombres $apellidos'.trim();

  factory ClienteWizardModel.fromJson(Map<String, dynamic> json) {
    return ClienteWizardModel(
      idCliente: json['id_cliente']?.toString() ?? '',
      rut: json['rut_cliente']?.toString() ?? json['rut']?.toString() ?? '',
      nombres: json['nombres']?.toString() ?? '',
      apellidos: json['apellidos']?.toString() ?? '',
      telefono: json['telefono']?.toString(),
      correo: json['correo']?.toString(),
      comuna: json['comuna']?.toString(),
      consentimientoLegal: json['consentimiento_legal'] == true || json['consentimiento_legal'] == 1,
      estado: json['estado']?.toString() ?? 'Activo',
    );
  }

  Map<String, dynamic> toClienteInputJson() => {
    'rut_cliente': rut,
    'nombres': nombres,
    'apellidos': apellidos,
    if (telefono != null && telefono!.isNotEmpty) 'telefono': telefono,
    if (correo != null && correo!.isNotEmpty) 'correo': correo,
    if (comuna != null && comuna!.isNotEmpty) 'comuna': comuna,
    'consentimiento_legal': consentimientoLegal,
  };
}

/// DTO para registrar características técnicas y comerciales de una Reserva Backorder (Compra en Verde)
class ReservaBackorderModel {
  final int idCategoriaRequerida;
  final String categoriaNombre;
  final String marcaRequerida;
  final String modeloRequerido;
  final int? anioRequerido;
  final String? cilindradaRequerida;
  final String? combustibleRequerido;
  final String? transmisionRequerida;
  final String? notasPreparacion;
  final int precioAcordado;
  final int montoAbonado;

  const ReservaBackorderModel({
    required this.idCategoriaRequerida,
    this.categoriaNombre = 'Repuesto',
    required this.marcaRequerida,
    required this.modeloRequerido,
    this.anioRequerido,
    this.cilindradaRequerida,
    this.combustibleRequerido,
    this.transmisionRequerida,
    this.notasPreparacion,
    required this.precioAcordado,
    this.montoAbonado = 0,
  });

  factory ReservaBackorderModel.fromJson(Map<String, dynamic> json) {
    return ReservaBackorderModel(
      idCategoriaRequerida: json['id_categoria_requerida'] is int
          ? json['id_categoria_requerida']
          : int.tryParse(json['id_categoria_requerida']?.toString() ?? '1') ?? 1,
      categoriaNombre: json['categoria_nombre']?.toString() ?? 'Repuesto',
      marcaRequerida: json['marca_requerida']?.toString() ?? '',
      modeloRequerido: json['modelo_requerido']?.toString() ?? '',
      anioRequerido: json['anio_requerido'] != null ? int.tryParse(json['anio_requerido'].toString()) : null,
      cilindradaRequerida: json['cilindrada_requerida']?.toString(),
      combustibleRequerido: json['combustible_requerido']?.toString(),
      transmisionRequerida: json['transmision_requerida']?.toString(),
      notasPreparacion: json['notas_preparacion']?.toString(),
      precioAcordado: json['precio_acordado'] is int
          ? json['precio_acordado']
          : int.tryParse(json['precio_acordado']?.toString() ?? '0') ?? 0,
      montoAbonado: json['monto_abonado'] is int
          ? json['monto_abonado']
          : int.tryParse(json['monto_abonado']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id_categoria_requerida': idCategoriaRequerida,
    'marca_requerida': marcaRequerida,
    'modelo_requerido': modeloRequerido,
    if (anioRequerido != null) 'anio_requerido': anioRequerido,
    if (cilindradaRequerida != null) 'cilindrada_requerida': cilindradaRequerida,
    if (combustibleRequerido != null) 'combustible_requerido': combustibleRequerido,
    if (transmisionRequerida != null) 'transmision_requerida': transmisionRequerida,
    if (notasPreparacion != null) 'notas_preparacion': notasPreparacion,
    'precio_acordado': precioAcordado,
    'monto_abonado': montoAbonado,
  };
}

/// DTO para datos de Despacho y Entrega a Domicilio o Traslado
class DespachoModel {
  final String direccionEnvio;
  final String receptorNombres;
  final String receptorRut;
  final String receptorTelefono;
  final int idComunaDestino;
  final String? comunaNombre;
  final String? empresaTransporte;
  final String? tipoEntrega;
  final int? idSucursalDestino;

  const DespachoModel({
    required this.direccionEnvio,
    required this.receptorNombres,
    required this.receptorRut,
    required this.receptorTelefono,
    required this.idComunaDestino,
    this.comunaNombre,
    this.empresaTransporte,
    this.tipoEntrega,
    this.idSucursalDestino,
  });

  factory DespachoModel.fromJson(Map<String, dynamic> json) {
    return DespachoModel(
      direccionEnvio: json['direccion_envio']?.toString() ?? '',
      receptorNombres: json['receptor_nombres']?.toString() ?? '',
      receptorRut: json['receptor_rut']?.toString() ?? '',
      receptorTelefono: json['receptor_telefono']?.toString() ?? '',
      idComunaDestino: json['id_comuna_destino'] is int
          ? json['id_comuna_destino']
          : int.tryParse(json['id_comuna_destino']?.toString() ?? '1') ?? 1,
      comunaNombre: json['comuna_nombre']?.toString(),
      empresaTransporte: json['empresa_transporte']?.toString(),
      tipoEntrega: json['tipo_entrega']?.toString(),
      idSucursalDestino: json['id_sucursal_destino'] != null ? int.tryParse(json['id_sucursal_destino'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'direccion_envio': direccionEnvio,
    'receptor_nombres': receptorNombres,
    'receptor_rut': receptorRut,
    'receptor_telefono': receptorTelefono,
    'id_comuna_destino': idComunaDestino,
    if (empresaTransporte != null) 'empresa_transporte': empresaTransporte,
    if (tipoEntrega != null) 'tipo_entrega': tipoEntrega,
    if (idSucursalDestino != null) 'id_sucursal_destino': idSucursalDestino,
  };
}

/// DTO para ítems manuales o ventas rápidas
class ItemManualModel {
  final String descripcion;
  final int cantidad;
  final int precioUnitario;
  final int precioFinal;
  final String? notasPreparacion;

  const ItemManualModel({
    required this.descripcion,
    this.cantidad = 1,
    required this.precioUnitario,
    required this.precioFinal,
    this.notasPreparacion,
  });

  factory ItemManualModel.fromJson(Map<String, dynamic> json) {
    final cant = json['cantidad'] is int ? json['cantidad'] : int.tryParse(json['cantidad']?.toString() ?? '1') ?? 1;
    final pUnit = json['precio_unitario'] is int ? json['precio_unitario'] : int.tryParse(json['precio_unitario']?.toString() ?? '0') ?? 0;
    final pFin = json['precio_final'] is int ? json['precio_final'] : pUnit * cant;

    return ItemManualModel(
      descripcion: json['descripcion']?.toString() ?? 'Ítem Manual',
      cantidad: cant,
      precioUnitario: pUnit,
      precioFinal: pFin,
      notasPreparacion: json['notas_preparacion']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'descripcion': descripcion,
    'cantidad': cantidad,
    'precio_unitario': precioUnitario,
    'precio_final': precioFinal,
    if (notasPreparacion != null) 'notas_preparacion': notasPreparacion,
  };
}

/// Payload unificado para emisión de órdenes vía Checkout Wizard (SPEC-HU-05)
class CheckoutWizardRequestModel {
  final String? idCliente;
  final ClienteWizardModel? cliente;
  final String tipoEntrega; // 'Retiro', 'Despacho Domicilio', 'Traslado'
  final int? idSucursalDestino;
  final String? idVendedorAsignado;
  final String? idVendedorTitular;
  final int totalVenta;
  final int montoPendiente;
  final int? montoAbono;
  final String? instruccionesBodega;
  final List<dynamic> itemsInventariados;
  final List<ItemManualModel> itemsManuales;
  final List<ReservaBackorderModel> reservas;
  final DespachoModel? datosDespacho;
  final int? descuento;

  const CheckoutWizardRequestModel({
    this.idCliente,
    this.cliente,
    this.tipoEntrega = 'Retiro',
    this.idSucursalDestino,
    this.idVendedorAsignado,
    this.idVendedorTitular,
    required this.totalVenta,
    required this.montoPendiente,
    this.montoAbono,
    this.descuento,
    this.instruccionesBodega,
    this.itemsInventariados = const [],
    this.itemsManuales = const [],
    this.reservas = const [],
    this.datosDespacho,
  });

  Map<String, dynamic> toJson() => {
    if (idCliente != null && !idCliente!.startsWith('cli-')) 'id_cliente': idCliente,
    if (cliente != null) 'cliente': cliente!.toClienteInputJson(),
    'tipo_entrega': tipoEntrega,
    if (idSucursalDestino != null) 'id_sucursal_destino': idSucursalDestino,
    if (idVendedorAsignado != null) 'id_vendedor_asignado': idVendedorAsignado,
    if (idVendedorTitular != null) 'id_vendedor_titular': idVendedorTitular,
    'total_venta': totalVenta,
    'monto_pendiente': montoPendiente,
    if (montoAbono != null) 'monto_abono': montoAbono,
    if (descuento != null && descuento! > 0) 'descuento': descuento,
    if (instruccionesBodega != null) 'instrucciones_bodega': instruccionesBodega,
    'items_inventariados': itemsInventariados.map((i) {
      if (i is Map) return i;
      if (i is String) return i;
      return i.toString();
    }).toList(),
    'items_manuales': itemsManuales.map((m) => m.toJson()).toList(),
    if (reservas.isNotEmpty) 'reservas': reservas.map((r) => r.toJson()).toList(),
    if (datosDespacho != null) 'datos_despacho': datosDespacho!.toJson(),
  };
}

/// DTO de respuesta transaccional tras procesar el Checkout Wizard
class CheckoutWizardResponseModel {
  final String idOrden;
  final int? numeroOrden;
  final String? folio;
  final String estado;
  final int totalVenta;
  final int descuento;
  final int montoPendiente;
  final int abonoRequerido;
  final int reservasGeneradas;
  final int activosReservados;
  final bool despachoGenerado;
  final String mensaje;

  const CheckoutWizardResponseModel({
    required this.idOrden,
    this.numeroOrden,
    this.folio,
    required this.estado,
    required this.totalVenta,
    this.descuento = 0,
    required this.montoPendiente,
    this.abonoRequerido = 0,
    this.reservasGeneradas = 0,
    this.activosReservados = 0,
    this.despachoGenerado = false,
    required this.mensaje,
  });

  String get folioDisplay {
    if (folio != null && folio!.isNotEmpty && !folio!.startsWith('TX-QR-')) {
      return folio!;
    }
    if (numeroOrden != null) {
      return 'ORD-${numeroOrden.toString().padLeft(4, '0')}';
    }
    if (idOrden.length >= 8) {
      return 'ORD-${idOrden.substring(0, 8).toUpperCase()}';
    }
    return 'ORD-$idOrden';
  }

  factory CheckoutWizardResponseModel.fromJson(Map<String, dynamic> json) {
    return CheckoutWizardResponseModel(
      idOrden: json['id_orden']?.toString() ?? '',
      numeroOrden: json['numero_orden'] as int?,
      folio: json['folio']?.toString(),
      estado: json['estado']?.toString() ?? json['estado_orden']?.toString() ?? 'Reservada',
      totalVenta: json['total_venta'] is int ? json['total_venta'] : int.tryParse(json['total_venta']?.toString() ?? '0') ?? 0,
      descuento: json['descuento'] is int ? json['descuento'] : int.tryParse(json['descuento']?.toString() ?? '0') ?? 0,
      montoPendiente: json['monto_pendiente'] is int ? json['monto_pendiente'] : int.tryParse(json['monto_pendiente']?.toString() ?? '0') ?? 0,
      abonoRequerido: json['abono_requerido'] is int ? json['abono_requerido'] : int.tryParse(json['abono_requerido']?.toString() ?? '0') ?? 0,
      reservasGeneradas: json['reservas_generadas'] is int ? json['reservas_generadas'] : int.tryParse(json['reservas_generadas']?.toString() ?? '0') ?? 0,
      activosReservados: json['activos_reservados'] is int ? json['activos_reservados'] : int.tryParse(json['activos_reservados']?.toString() ?? '0') ?? 0,
      despachoGenerado: json['despacho_generado'] == true,
      mensaje: json['mensaje']?.toString() ?? json['msg']?.toString() ?? 'Orden generada exitosamente.',
    );
  }
}
