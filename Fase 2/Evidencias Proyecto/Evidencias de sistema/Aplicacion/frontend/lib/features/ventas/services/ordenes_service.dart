// lib/features/ventas/services/ordenes_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../core/constants/chile_geografia.dart';
import '../../auth/services/auth_service.dart';
import 'ordenes_sync_notifier.dart';

/// DTO de respuesta para la creación y consulta de órdenes de venta.
class OrdenResponseModel {
  final String idOrden;
  final int? numeroOrden;
  final String? folio;
  final String estadoOrden;
  final int totalVenta;
  final int descuento;
  final int montoPendiente;
  final String? qrTransaccionalSalida;
  final String mensaje;
  final String? fechaCreacion;
  final int totalItems;

  const OrdenResponseModel({
    required this.idOrden,
    this.numeroOrden,
    this.folio,
    required this.estadoOrden,
    required this.totalVenta,
    this.descuento = 0,
    required this.montoPendiente,
    this.qrTransaccionalSalida,
    required this.mensaje,
    this.fechaCreacion,
    required this.totalItems,
  });

  factory OrdenResponseModel.fromJson(Map<String, dynamic> json) {
    return OrdenResponseModel(
      idOrden: json['id_orden']?.toString() ?? '',
      numeroOrden: json['numero_orden'] as int?,
      folio: json['folio']?.toString(),
      estadoOrden: json['estado_orden']?.toString() ?? 'Reservada',
      totalVenta: json['total_venta'] as int? ?? 0,
      descuento: json['descuento'] as int? ?? 0,
      montoPendiente: json['monto_pendiente'] as int? ?? 0,
      qrTransaccionalSalida: json['qr_transaccional_salida']?.toString(),
      mensaje: json['mensaje']?.toString() ?? 'Orden generada exitosamente',
      fechaCreacion: json['fecha_creacion']?.toString(),
      totalItems: json['total_items'] as int? ?? 0,
    );
  }

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

  /// Retorna el monto formateado en pesos chilenos (ej: $520.000)
  String get totalVentaFormateado => _formatearMonto(totalVenta);

  /// Indica si la orden cuenta con código QR transaccional emitido para retiro en bodega (HU-3.6).
  bool get tieneQrDisponible =>
      (estadoOrden.toLowerCase() == 'pagada' || estadoOrden.toLowerCase() == 'completada') &&
      qrTransaccionalSalida != null &&
      qrTransaccionalSalida!.trim().isNotEmpty;

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

/// DTO de respuesta para la confirmación de pago y emisión del QR transaccional (HU-3.6).
class OrdenPagoResponseModel {
  final String idOrden;
  final int? numeroOrden;
  final String? folio;
  final String idPago;
  final String estadoOrden;
  final int totalVenta;
  final int montoPagado;
  final int montoPendiente;
  final String metodoPago;
  final String qrTransaccionalSalida;
  final String idCajera;
  final String mensaje;
  final String fechaPago;

  const OrdenPagoResponseModel({
    required this.idOrden,
    this.numeroOrden,
    this.folio,
    required this.idPago,
    required this.estadoOrden,
    required this.totalVenta,
    required this.montoPagado,
    required this.montoPendiente,
    required this.metodoPago,
    required this.qrTransaccionalSalida,
    required this.idCajera,
    required this.mensaje,
    required this.fechaPago,
  });

  factory OrdenPagoResponseModel.fromJson(Map<String, dynamic> json) {
    return OrdenPagoResponseModel(
      idOrden: json['id_orden']?.toString() ?? '',
      numeroOrden: json['numero_orden'] as int?,
      folio: json['folio']?.toString(),
      idPago: json['id_pago']?.toString() ?? '',
      estadoOrden: json['estado_orden']?.toString() ?? 'Pagada',
      totalVenta: json['total_venta'] as int? ?? 0,
      montoPagado: json['monto_pagado'] as int? ?? 0,
      montoPendiente: json['monto_pendiente'] as int? ?? 0,
      metodoPago: json['metodo_pago']?.toString() ?? 'Efectivo',
      qrTransaccionalSalida: json['qr_transaccional_salida']?.toString() ?? '',
      idCajera: json['id_cajera']?.toString() ?? '',
      mensaje: json['mensaje']?.toString() ?? 'Pago registrado exitosamente',
      fechaPago: json['fecha_pago']?.toString() ?? '',
    );
  }

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
}

/// Resumen del cliente asociado a una orden en el historial (HU-3.5).
class ClienteOrdenResumenModel {
  final String rutCliente;
  final String nombres;
  final String apellidos;
  final String? telefono;
  final String? correo;
  final String? comuna;

  const ClienteOrdenResumenModel({
    required this.rutCliente,
    required this.nombres,
    required this.apellidos,
    this.telefono,
    this.correo,
    this.comuna,
  });

  String get nombreCompleto => '$nombres $apellidos'.trim();

  factory ClienteOrdenResumenModel.fromJson(Map<String, dynamic> json) {
    return ClienteOrdenResumenModel(
      rutCliente: json['rut_cliente']?.toString() ?? '',
      nombres: json['nombres']?.toString() ?? '',
      apellidos: json['apellidos']?.toString() ?? '',
      telefono: json['telefono']?.toString(),
      correo: json['correo']?.toString(),
      comuna: json['comuna']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'rut_cliente': rutCliente,
    'nombres': nombres,
    'apellidos': apellidos,
    if (telefono != null) 'telefono': telefono,
    if (correo != null) 'correo': correo,
    if (comuna != null) 'comuna': comuna,
  };
}

/// Resumen del despacho asociado a una orden en el historial (HU-3.5).
class DespachoOrdenResumenModel {
  final String idDespacho;
  final String direccionEnvio;
  final String receptorNombres;
  final String receptorRut;
  final String receptorTelefono;
  final String? empresaTransporte;
  final int costoEnvio;
  final String estadoDespacho;
  final String? comunaDestino;
  final String? numeroSeguimiento;

  const DespachoOrdenResumenModel({
    required this.idDespacho,
    required this.direccionEnvio,
    required this.receptorNombres,
    required this.receptorRut,
    required this.receptorTelefono,
    this.empresaTransporte,
    this.costoEnvio = 0,
    required this.estadoDespacho,
    this.comunaDestino,
    this.numeroSeguimiento,
  });

  String get costoEnvioFormateado {
    if (costoEnvio <= 0) return 'Gratis / Incluido';
    return OrdenResponseModel._formatearMonto(costoEnvio);
  }

  factory DespachoOrdenResumenModel.fromJson(Map<String, dynamic> json) {
    return DespachoOrdenResumenModel(
      idDespacho: json['id_despacho']?.toString() ?? '',
      direccionEnvio: json['direccion_envio']?.toString() ?? '',
      receptorNombres: json['receptor_nombres']?.toString() ?? '',
      receptorRut: json['receptor_rut']?.toString() ?? '',
      receptorTelefono: json['receptor_telefono']?.toString() ?? '',
      empresaTransporte: json['empresa_transporte']?.toString(),
      costoEnvio: json['costo_envio'] as int? ?? 0,
      estadoDespacho: json['estado_despacho']?.toString() ?? 'Enviado',
      comunaDestino: json['comuna_destino']?.toString(),
      numeroSeguimiento: json['numero_seguimiento']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id_despacho': idDespacho,
    'direccion_envio': direccionEnvio,
    'receptor_nombres': receptorNombres,
    'receptor_rut': receptorRut,
    'receptor_telefono': receptorTelefono,
    if (empresaTransporte != null) 'empresa_transporte': empresaTransporte,
    'costo_envio': costoEnvio,
    'estado_despacho': estadoDespacho,
    if (comunaDestino != null) 'comuna_destino': comunaDestino,
    if (numeroSeguimiento != null) 'numero_seguimiento': numeroSeguimiento,
  };
}

/// Línea de detalle de producto en el historial de órdenes (HU-3.5).
class DetalleOrdenItemModel {
  final String idDetalle;
  final String? idActivo;
  final int? idCategoria;
  final String? nombreCategoria;
  final String titulo;
  final String? skuQrFisico;
  final String? descripcionManual;
  String? notasPreparacion;
  final int cantidad;
  final int? precioUnitario;
  final int precioFinal;
  final int subtotal;
  final bool esInventariado;
  final bool preparacionLista;
  final String? estadoPreparacion;

  DetalleOrdenItemModel({
    required this.idDetalle,
    this.idActivo,
    this.idCategoria,
    this.nombreCategoria,
    required this.titulo,
    this.skuQrFisico,
    this.descripcionManual,
    this.notasPreparacion,
    required this.cantidad,
    this.precioUnitario,
    required this.precioFinal,
    required this.subtotal,
    required this.esInventariado,
    this.preparacionLista = false,
    this.estadoPreparacion = 'Pendiente',
  });

  String get precioFinalFormateado => OrdenResponseModel._formatearMonto(precioFinal);
  String get subtotalFormateado => OrdenResponseModel._formatearMonto(subtotal);
  String get tituloDisplay => titulo.isNotEmpty ? titulo : (descripcionManual ?? 'Repuesto Misceláneo');

  bool get esMotorOCaja {
    final cat = (nombreCategoria ?? '').trim().toLowerCase();
    if (cat.contains('motor') || cat.contains('caja')) return true;
    if (idCategoria == 1 || idCategoria == 2) return true;
    final t = tituloDisplay.toLowerCase();
    if (t.contains('motor') ||
        t.contains('caja de cambio') ||
        t.contains('cajas de cambio') ||
        t.contains('caja de cambios') ||
        t.contains('cajas de cambios') ||
        t.startsWith('caja ') ||
        t == 'caja' ||
        t.contains('caja transmision') ||
        t.contains('caja manual') ||
        t.contains('caja automatica') ||
        t.contains('caja automática')) {
      return true;
    }
    return false;
  }

  String get tipoEntregaLabel => esMotorOCaja ? 'Retiro en Bodega' : 'Entrega en Mesón';

  factory DetalleOrdenItemModel.fromJson(Map<String, dynamic> json) {
    final cant = json['cantidad'] as int? ?? 1;
    final pFinal = json['precio_final'] as int? ?? 0;
    final sub = json['subtotal'] as int? ?? (pFinal * cant);

    return DetalleOrdenItemModel(
      idDetalle: json['id_detalle']?.toString() ?? '',
      idActivo: json['id_activo']?.toString(),
      idCategoria: json['id_categoria'] as int?,
      nombreCategoria: json['nombre_categoria']?.toString(),
      titulo: json['titulo']?.toString() ?? 'Repuesto',
      skuQrFisico: json['sku_qr_fisico']?.toString(),
      descripcionManual: json['descripcion_manual']?.toString(),
      notasPreparacion: json['notas_preparacion']?.toString(),
      cantidad: cant,
      precioUnitario: json['precio_unitario'] as int?,
      precioFinal: pFinal,
      subtotal: sub,
      esInventariado: json['es_inventariado'] as bool? ?? (json['id_activo'] != null),
      preparacionLista: json['preparacion_lista'] as bool? ?? false,
      estadoPreparacion: json['estado_preparacion']?.toString() ?? 'Pendiente',
    );
  }

  Map<String, dynamic> toJson() => {
    'id_detalle': idDetalle,
    if (idActivo != null) 'id_activo': idActivo,
    if (idCategoria != null) 'id_categoria': idCategoria,
    if (nombreCategoria != null) 'nombre_categoria': nombreCategoria,
    'titulo': titulo,
    if (skuQrFisico != null) 'sku_qr_fisico': skuQrFisico,
    if (descripcionManual != null) 'descripcion_manual': descripcionManual,
    if (notasPreparacion != null) 'notas_preparacion': notasPreparacion,
    'cantidad': cantidad,
    if (precioUnitario != null) 'precio_unitario': precioUnitario,
    'precio_final': precioFinal,
    'subtotal': subtotal,
    'es_inventariado': esInventariado,
    'preparacion_lista': preparacionLista,
    if (estadoPreparacion != null) 'estado_preparacion': estadoPreparacion,
  };
}

/// DTO completo de orden de venta para el historial del vendedor (HU-3.5).
class OrdenHistorialModel {
  final String idOrden;
  final int? numeroOrden;
  final String? folio;
  String estadoOrden;
  final int totalVenta;
  final int descuento;
  final int montoPendiente;
  final String? qrTransaccionalSalida;
  final String? fechaCreacion;
  final String? fechaActualizacion;
  final int totalItems;
  final ClienteOrdenResumenModel? cliente;
  final DespachoOrdenResumenModel? despacho;
  final List<DetalleOrdenItemModel> detalles;
  final String? idVendedorAsignado;
  final bool esAsignadaLimache;

  OrdenHistorialModel({
    required this.idOrden,
    this.numeroOrden,
    this.folio,
    required this.estadoOrden,
    required this.totalVenta,
    this.descuento = 0,
    required this.montoPendiente,
    this.qrTransaccionalSalida,
    this.fechaCreacion,
    this.fechaActualizacion,
    required this.totalItems,
    this.cliente,
    this.despacho,
    required this.detalles,
    this.idVendedorAsignado,
    this.esAsignadaLimache = false,
  });

  bool get esReservada => estadoOrden.toLowerCase() == 'reservada';
  bool get esPagada => estadoOrden.toLowerCase() == 'pagada';
  bool get esCompletada => estadoOrden.toLowerCase() == 'completada';
  bool get esAnulada => estadoOrden.toLowerCase() == 'anulada';
  bool get esVentaEnVerde =>
      (folio != null && folio!.toUpperCase().startsWith('RES-')) ||
      detalles.any((d) =>
          d.titulo.toUpperCase().contains('RESERVA EN VERDE') ||
          d.titulo.toUpperCase().contains('VENTA EN VERDE') ||
          (d.descripcionManual != null &&
              (d.descripcionManual!.toUpperCase().contains('RESERVA EN VERDE') ||
               d.descripcionManual!.toUpperCase().contains('VENTA EN VERDE'))));
  bool get esAbonada => montoPendiente > 0 && totalVenta > montoPendiente;
  bool get contieneMotorOCaja => detalles.any((d) => d.esMotorOCaja);
  bool get contieneMiscelaneos => detalles.any((d) => !d.esMotorOCaja);
  bool get esMixta => contieneMotorOCaja && contieneMiscelaneos;

  /// Indica si la orden cuenta con código QR transaccional emitido para entrega en bodega (HU-3.6).
  bool get tieneQrDisponible =>
      esPagada &&
      qrTransaccionalSalida != null &&
      qrTransaccionalSalida!.trim().isNotEmpty;

  static const Object _sentinel = Object();

  OrdenHistorialModel copyWith({
    String? idOrden,
    int? numeroOrden,
    String? folio,
    String? estadoOrden,
    int? totalVenta,
    int? descuento,
    int? montoPendiente,
    Object? qrTransaccionalSalida = _sentinel,
    String? fechaCreacion,
    String? fechaActualizacion,
    int? totalItems,
    ClienteOrdenResumenModel? cliente,
    DespachoOrdenResumenModel? despacho,
    List<DetalleOrdenItemModel>? detalles,
    String? idVendedorAsignado,
    bool? esAsignadaLimache,
  }) {
    return OrdenHistorialModel(
      idOrden: idOrden ?? this.idOrden,
      numeroOrden: numeroOrden ?? this.numeroOrden,
      folio: folio ?? this.folio,
      estadoOrden: estadoOrden ?? this.estadoOrden,
      totalVenta: totalVenta ?? this.totalVenta,
      descuento: descuento ?? this.descuento,
      montoPendiente: montoPendiente ?? this.montoPendiente,
      qrTransaccionalSalida: identical(qrTransaccionalSalida, _sentinel)
          ? this.qrTransaccionalSalida
          : qrTransaccionalSalida as String?,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
      fechaActualizacion: fechaActualizacion ?? this.fechaActualizacion,
      totalItems: totalItems ?? this.totalItems,
      cliente: cliente ?? this.cliente,
      despacho: despacho ?? this.despacho,
      detalles: detalles ?? this.detalles,
      idVendedorAsignado: idVendedorAsignado ?? this.idVendedorAsignado,
      esAsignadaLimache: esAsignadaLimache ?? this.esAsignadaLimache,
    );
  }

  String get totalVentaFormateado => OrdenResponseModel._formatearMonto(totalVenta);
  String get descuentoFormateado => OrdenResponseModel._formatearMonto(descuento);
  String get montoPendienteFormateado => OrdenResponseModel._formatearMonto(montoPendiente);
  String get montoPagadoFormateado => OrdenResponseModel._formatearMonto(montoPagado);

  bool get esAnulable => (esReservada || esPagada) && !esCompletada && !esAnulada;
  int get montoPagado {
    final pagado = totalVenta - montoPendiente;
    return pagado < 0 ? 0 : pagado;
  }
  bool get tienePagosRegistrados => montoPagado > 0;

  String get folioDisplay {
    if (folio != null && folio!.isNotEmpty && !folio!.startsWith('TX-QR-')) {
      return folio!;
    }
    if (numeroOrden != null) {
      return 'ORD-${numeroOrden.toString().padLeft(4, '0')}';
    }
    if (qrTransaccionalSalida != null &&
        qrTransaccionalSalida!.startsWith('ORD-')) {
      return qrTransaccionalSalida!;
    }
    if (idOrden.length >= 8) {
      return 'ORD-${idOrden.substring(0, 8).toUpperCase()}';
    }
    return 'ORD-$idOrden';
  }

  DateTime? get fechaLocal {
    if (fechaCreacion == null || fechaCreacion!.trim().isEmpty) return null;
    try {
      final raw = fechaCreacion!.trim();
      final formattedIso = raw.contains('Z') || raw.contains('+')
          ? raw
          : '${raw.replaceAll(' ', 'T')}Z';
      return DateTime.parse(formattedIso).toLocal();
    } catch (_) {
      try {
        return DateTime.parse(fechaCreacion!).toLocal();
      } catch (_) {
        return null;
      }
    }
  }

  bool get esDeHoy {
    final local = fechaLocal;
    if (local == null) return false;
    final now = DateTime.now();
    return local.year == now.year && local.month == now.month && local.day == now.day;
  }

  String get fechaFormateada {
    final dt = fechaLocal;
    if (dt == null) return fechaCreacion ?? '--:--';
    final dia = dt.day.toString().padLeft(2, '0');
    final mes = dt.month.toString().padLeft(2, '0');
    final anio = dt.year;
    final hora = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dia/$mes/$anio $hora:$min';
  }

  factory OrdenHistorialModel.fromJson(Map<String, dynamic> json) {
    return OrdenHistorialModel(
      idOrden: json['id_orden']?.toString() ?? '',
      numeroOrden: json['numero_orden'] as int?,
      folio: json['folio']?.toString(),
      estadoOrden: json['estado_orden']?.toString() ?? 'Reservada',
      totalVenta: json['total_venta'] as int? ?? 0,
      descuento: json['descuento'] as int? ?? 0,
      montoPendiente: json['monto_pendiente'] as int? ?? 0,
      qrTransaccionalSalida: json['qr_transaccional_salida']?.toString(),
      fechaCreacion: json['fecha_creacion']?.toString(),
      fechaActualizacion: json['fecha_actualizacion']?.toString(),
      totalItems: json['total_items'] as int? ?? 0,
      cliente: json['cliente'] != null
          ? ClienteOrdenResumenModel.fromJson(json['cliente'] as Map<String, dynamic>)
          : null,
      despacho: json['despacho'] != null
          ? DespachoOrdenResumenModel.fromJson(json['despacho'] as Map<String, dynamic>)
          : null,
      detalles: (json['detalles'] as List<dynamic>?)
              ?.map((d) => DetalleOrdenItemModel.fromJson(d as Map<String, dynamic>))
              .toList() ??
          [],
      idVendedorAsignado: json['id_vendedor_asignado']?.toString(),
      esAsignadaLimache: json['es_asignada_limache'] as bool? ?? false,
    );
  }
}

/// Servicio HTTP para la gestión de órdenes de venta en FastAPI (HU-3.4 & HU-3.5).
class OrdenesService {
  /// Sanitiza cualquier error o excepción técnica para evitar la exposición de datos sensibles
  /// (como IPs, dominios de Render, códigos de socket o trazas del sistema) y presentar al
  /// personal de mesón y caja un mensaje claro, amigable y comprensible.
  static String sanitizarMensajeError(dynamic error) {
    if (error == null) {
      return 'No pudimos cargar el historial en este momento. Revisa tu conexión a internet o intenta nuevamente.';
    }

    final raw = error is Exception
        ? error.toString().replaceFirst(RegExp(r'^[A-Za-z0-9_]*Exception:\s*'), '')
        : error.toString();
    final lower = raw.toLowerCase();

    // 1. Detección de Timeout / Tiempo de espera
    if (lower.contains('timeout') ||
        lower.contains('tiempo de espera') ||
        lower.contains('timed out') ||
        lower.contains('deadline')) {
      return 'El servidor tardó demasiado en responder. Por favor, reintenta en unos instantes.';
    }

    // 2. Detección de fallos de red / Socket / Handshake / Sin conexión
    if (lower.contains('socket') ||
        lower.contains('clientexception') ||
        lower.contains('connection failed') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('connection closed') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('network error') ||
        lower.contains('handshake') ||
        lower.contains('errno') ||
        lower.contains('os error') ||
        lower.contains('sin conexión') ||
        lower.contains('no route to host') ||
        lower.contains('address =') ||
        lower.contains('port =')) {
      return 'No pudimos conectar con el servidor. Revisa tu conexión a internet o intenta nuevamente.';
    }

    // 3. Detección de infraestructura técnica / Render / Cloud / IPs / Trazas internas
    final contieneIp = RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b').hasMatch(raw);
    final contieneHostTecnico = lower.contains('onrender.com') ||
        lower.contains('render') ||
        lower.contains('supabase') ||
        lower.contains('localhost') ||
        lower.contains('http://') ||
        lower.contains('https://') ||
        lower.contains('traceback') ||
        lower.contains('stack trace') ||
        lower.contains('fastapi') ||
        lower.contains('uvicorn') ||
        lower.contains('sqlalchemy') ||
        lower.contains('internal server error') ||
        lower.contains('bad gateway') ||
        lower.contains('service unavailable') ||
        lower.contains('502') ||
        lower.contains('503') ||
        lower.contains('504') ||
        lower.contains('500');

    if (contieneIp || contieneHostTecnico) {
      return 'El servicio de órdenes no se encuentra disponible temporalmente. Revisa tu conexión o intenta nuevamente en unos momentos.';
    }

    // 4. Sesión expirada o no autorizada
    if (lower.contains('sesión expirada') ||
        lower.contains('unauthorized') ||
        lower.contains('token inválido') ||
        lower.contains('401')) {
      return 'Sesión expirada. Por favor vuelve a iniciar sesión.';
    }

    // 5. Permisos
    if (lower.contains('permiso') || lower.contains('403') || lower.contains('forbidden')) {
      return 'No cuentas con los permisos requeridos para realizar esta acción.';
    }

    // 6. Mensaje de negocio limpio (sin IPs, URLs ni trazas técnicas)
    final limpio = raw
        .replaceAll(RegExp(r'^[A-Za-z0-9_]*Exception:\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'^[A-Za-z0-9_]*Error:\s*', caseSensitive: false), '')
        .trim();

    if (limpio.isNotEmpty &&
        limpio.length <= 150 &&
        !limpio.contains('{') &&
        !limpio.contains('}') &&
        !limpio.contains('File "') &&
        !limpio.contains('.dart') &&
        !limpio.contains('.py')) {
      return limpio;
    }

    return 'No pudimos cargar el historial en este momento. Revisa tu conexión a internet o intenta nuevamente.';
  }

  /// Crea una nueva orden de venta transaccional en el backend.
  static Future<OrdenResponseModel> crearOrden(
    Map<String, dynamic> payload, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();

    try {
      final uri = Uri.parse(ApiConstants.ordenesEndpoint);
      final token = await AuthService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await httpClient
          .post(
            uri,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception(
              'Tiempo de espera agotado al comunicarse con el servidor.',
            ),
          );

      dynamic decodedBody;
      try {
        decodedBody = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        try {
          decodedBody = jsonDecode(response.body);
        } catch (_) {
          decodedBody = null;
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (decodedBody is Map<String, dynamic>) {
          final orden = OrdenResponseModel.fromJson(decodedBody);
          OrdenesSyncNotifier.instance.notificarCambio();
          return orden;
        }
        throw Exception('Formato de respuesta no válido del servidor.');
      } else if (response.statusCode == 409) {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        throw Exception(
          detail?.toString() ??
              'Conflicto de stock: Uno o más repuestos ya no se encuentran disponibles.',
        );
      } else if (response.statusCode == 400) {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        throw Exception(
          detail?.toString() ?? 'Datos de la orden inválidos. Revisa el formulario.',
        );
      } else if (response.statusCode == 401) {
        if (kDebugMode) {
          debugPrint('🌐 [ORDENES] HTTP 401 Unauthorized en crearOrden');
        }
        await AuthService.manejarSesionExpirada();
        throw Exception('Sesión expirada. Por favor vuelve a iniciar sesión.');
      } else if (response.statusCode == 404) {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        throw Exception(
          detail?.toString() ?? 'Recurso o repuesto no encontrado en el sistema.',
        );
      } else {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        throw Exception(
          detail?.toString() ??
              'Error en el servidor al procesar la orden (${response.statusCode}).',
        );
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error inesperado al generar la orden: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Busca un cliente en el backend por su RUT para autocompletar el formulario de Micro-CRM.
  static Future<Map<String, dynamic>?> buscarClientePorRut(
    String rut, {
    http.Client? client,
  }) async {
    final cleanRut = rut.trim();
    if (cleanRut.isEmpty) return null;

    final httpClient = client ?? http.Client();

    try {
      final encodedRut = Uri.encodeComponent(cleanRut);
      final uri = Uri.parse('${ApiConstants.clientesEndpoint}/$encodedRut');
      final token = await AuthService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await httpClient
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        dynamic decoded;
        try {
          decoded = jsonDecode(utf8.decode(response.bodyBytes));
        } catch (_) {
          decoded = jsonDecode(response.body);
        }
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Consulta el historial de órdenes generadas por el vendedor actual (HU-3.5).
  /// Soporta segmentación por sección: 'normal' u 'por_asignar'.
  static Future<List<OrdenHistorialModel>> obtenerMisVentas({
    String? fecha,
    bool todas = false,
    String? estado,
    bool incluirAnuladas = false,
    String seccion = 'normal',
    int? limit,
    int? offset,
    int? mes,
    int? anio,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();

    try {
      final queryParams = <String, String>{
        if (todas) 'todas': 'true',
        if (fecha != null && fecha.isNotEmpty) 'fecha': fecha,
        if (estado != null && estado.isNotEmpty) 'estado': estado,
        if (estado == null && !incluirAnuladas) 'incluir_anuladas': 'false',
        if (seccion.isNotEmpty) 'seccion': seccion,
        if (limit != null) 'limit': limit.toString(),
        if (offset != null) 'offset': offset.toString(),
        if (mes != null) 'mes': mes.toString(),
        if (anio != null) 'anio': anio.toString(),
      };

      final uri = Uri.parse('${ApiConstants.ordenesEndpoint}/mis-ventas')
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final token = await AuthService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await httpClient
          .get(uri, headers: headers)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Tiempo de espera agotado al consultar órdenes.'),
          );

      dynamic decodedBody;
      try {
        decodedBody = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        try {
          decodedBody = jsonDecode(response.body);
        } catch (_) {
          decodedBody = null;
        }
      }

      if (response.statusCode == 200) {
        if (decodedBody is List) {
          return decodedBody
              .map((item) => OrdenHistorialModel.fromJson(item as Map<String, dynamic>))
              .toList();
        }
        return [];
      } else if (response.statusCode == 401) {
        if (kDebugMode) {
          debugPrint('🌐 [ORDENES] HTTP 401 Unauthorized en obtenerOrdenes');
        }
        await AuthService.manejarSesionExpirada();
        throw Exception('Sesión expirada. Por favor vuelve a iniciar sesión.');
      } else {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        final rawMsg = detail?.toString() ??
            'Error al consultar el historial de órdenes (${response.statusCode}).';
        throw Exception(sanitizarMensajeError(rawMsg));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [ORDENES-SERVICE] Error en obtenerMisVentas: $e');
      }
      throw Exception(sanitizarMensajeError(e));
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Valida que el activo ingresado sea compatible con la venta en verde de la orden.
  static Future<Map<String, dynamic>> validarActivoBackorder(
    String idOrden,
    String skuActivo, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final uri = Uri.parse('${ApiConstants.ordenesEndpoint}/$idOrden/validar-activo-backorder');
      final token = await AuthService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await httpClient
          .post(
            uri,
            headers: headers,
            body: jsonEncode({'sku_activo': skuActivo.trim()}),
          )
          .timeout(const Duration(seconds: 15));

      dynamic decodedBody;
      try {
        decodedBody = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        decodedBody = jsonDecode(response.body);
      }

      if (response.statusCode == 200 && decodedBody is Map<String, dynamic>) {
        return decodedBody;
      } else {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        throw Exception(detail?.toString() ?? 'Error al validar activo (${response.statusCode})');
      }
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Asigna un activo físico (Disponible o Paletizado) a una venta en verde pagada.
  /// Emite el código QR transaccional para la Barrera de Salida.
  static Future<Map<String, dynamic>> asignarActivoBackorder(
    String idOrden,
    String skuActivo, {
    bool forzar = false,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final uri = Uri.parse('${ApiConstants.ordenesEndpoint}/$idOrden/asignar-activo-backorder');
      final token = await AuthService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await httpClient
          .post(
            uri,
            headers: headers,
            body: jsonEncode({
              'sku_activo': skuActivo.trim(),
              'forzar_atribucion': forzar,
            }),
          )
          .timeout(const Duration(seconds: 15));

      dynamic decodedBody;
      try {
        decodedBody = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        decodedBody = jsonDecode(response.body);
      }

      if (response.statusCode == 200 && decodedBody is Map<String, dynamic>) {
        OrdenesSyncNotifier.instance.notificarCambio();
        return decodedBody;
      } else {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        throw Exception(detail?.toString() ?? 'Error al asignar activo físico (${response.statusCode})');
      }
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Anula una orden en el mesón de ventas, reversando cobros y generando logística inversa (SPEC-HU-TAREA-4).
  static Future<Map<String, dynamic>> anularOrden(
    String idOrden, {
    String? motivoAnulacion,
    String? observacionAnulacion,
    bool usePost = false,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();

    try {
      final uri = Uri.parse('${ApiConstants.ordenesEndpoint}/$idOrden/anular');
      final token = await AuthService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final body = jsonEncode({
        if (motivoAnulacion != null && motivoAnulacion.isNotEmpty) ...{
          'motivo': motivoAnulacion,
          'motivo_anulacion': motivoAnulacion,
        },
        if (observacionAnulacion != null && observacionAnulacion.isNotEmpty) ...{
          'observacion': observacionAnulacion,
          'observacion_anulacion': observacionAnulacion,
        },
      });

      final response = (usePost || motivoAnulacion != null)
          ? await httpClient
              .post(uri, headers: headers, body: body)
              .timeout(
                const Duration(seconds: 15),
                onTimeout: () => throw Exception('Tiempo de espera agotado al anular la orden.'),
              )
          : await httpClient
              .patch(uri, headers: headers, body: body)
              .timeout(
                const Duration(seconds: 15),
                onTimeout: () => throw Exception('Tiempo de espera agotado al anular la orden.'),
              );

      dynamic decodedBody;
      try {
        decodedBody = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        try {
          decodedBody = jsonDecode(response.body);
        } catch (_) {
          decodedBody = null;
        }
      }

      if (response.statusCode == 200) {
        if (decodedBody is Map<String, dynamic>) {
          return decodedBody;
        }
        return {'mensaje': 'Orden anulada exitosamente.'};
      } else if (response.statusCode == 400) {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        throw Exception(detail?.toString() ?? 'No es posible anular la orden en su estado actual.');
      } else if (response.statusCode == 404) {
        throw Exception('La orden especificada no fue encontrada.');
      } else if (response.statusCode == 401) {
        if (kDebugMode) {
          debugPrint('🌐 [ORDENES] HTTP 401 Unauthorized en anularOrden');
        }
        await AuthService.manejarSesionExpirada();
        throw Exception('Sesión expirada. Por favor vuelve a iniciar sesión.');
      } else {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        final rawMsg = detail?.toString() ?? 'Error al anular la orden (${response.statusCode}).';
        throw Exception(sanitizarMensajeError(rawMsg));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [ORDENES-SERVICE] Error en anularOrden: $e');
      }
      throw Exception(sanitizarMensajeError(e));
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Actualiza las instrucciones/notas técnicas dirigidas a bodega para una orden (HU-3.5).
  static Future<Map<String, dynamic>> actualizarInstruccionesBodega(
    String idOrden,
    String notasPreparacion, {
    String? idDetalle,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();

    try {
      final uri = Uri.parse('${ApiConstants.ordenesEndpoint}/$idOrden/instrucciones');
      final token = await AuthService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final payload = {
        'notas_preparacion': notasPreparacion.trim(),
        if (idDetalle != null && idDetalle.isNotEmpty) 'id_detalle': idDetalle,
      };

      final response = await httpClient
          .patch(
            uri,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Tiempo de espera agotado al actualizar instrucciones.'),
          );

      dynamic decodedBody;
      try {
        decodedBody = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        try {
          decodedBody = jsonDecode(response.body);
        } catch (_) {
          decodedBody = null;
        }
      }

      if (response.statusCode == 200) {
        if (decodedBody is Map<String, dynamic>) {
          return decodedBody;
        }
        return {'mensaje': 'Instrucciones actualizadas exitosamente.'};
      } else if (response.statusCode == 400) {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        throw Exception(detail?.toString() ?? 'No se pueden modificar instrucciones de esta orden.');
      } else if (response.statusCode == 404) {
        throw Exception('Orden o detalle no encontrado.');
      } else if (response.statusCode == 401) {
        if (kDebugMode) {
          debugPrint('🌐 [ORDENES] HTTP 401 Unauthorized en actualizarInstruccionesBodega');
        }
        await AuthService.manejarSesionExpirada();
        throw Exception('Sesión expirada. Por favor vuelve a iniciar sesión.');
      } else {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        final rawMsg = detail?.toString() ?? 'Error al actualizar instrucciones (${response.statusCode}).';
        throw Exception(sanitizarMensajeError(rawMsg));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [ORDENES-SERVICE] Error en actualizarInstruccionesBodega: $e');
      }
      throw Exception(sanitizarMensajeError(e));
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Reasigna la titularidad comercial de una orden a otro vendedor activo.
  static Future<Map<String, dynamic>> reasignarVendedor({
    required String idOrden,
    required String idNuevoVendedor,
    String? motivo,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();

    try {
      final uri = Uri.parse('${ApiConstants.ordenesEndpoint}/$idOrden/reasignar-vendedor');
      final token = await AuthService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final payload = {
        'id_nuevo_vendedor': idNuevoVendedor,
        if (motivo != null && motivo.trim().isNotEmpty) 'motivo': motivo.trim(),
      };

      final response = await httpClient
          .patch(
            uri,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Tiempo de espera agotado al reasignar la orden.'),
          );

      dynamic decodedBody;
      try {
        decodedBody = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        try {
          decodedBody = jsonDecode(response.body);
        } catch (_) {
          decodedBody = null;
        }
      }

      if (response.statusCode == 200) {
        if (decodedBody is Map<String, dynamic>) {
          return decodedBody;
        }
        return {'mensaje': 'Orden reasignada exitosamente.'};
      } else if (response.statusCode == 400 || response.statusCode == 403 || response.statusCode == 404) {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        throw Exception(detail?.toString() ?? 'Error al reasignar la orden (${response.statusCode}).');
      } else if (response.statusCode == 401) {
        if (kDebugMode) {
          debugPrint('🌐 [ORDENES] HTTP 401 Unauthorized en reasignarVendedor');
        }
        await AuthService.manejarSesionExpirada();
        throw Exception('Sesión expirada. Por favor vuelve a iniciar sesión.');
      } else {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        final rawMsg = detail?.toString() ?? 'Error al reasignar orden (${response.statusCode}).';
        throw Exception(sanitizarMensajeError(rawMsg));
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [ORDENES-SERVICE] Error en reasignarVendedor: $e');
      }
      throw Exception(sanitizarMensajeError(e));
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// [DEPRECATED] Endpoint legado de demostración (HU-3.6).
  /// En el flujo operativo oficial, los pagos deben procesarse exclusivamente a través de [CajaService.registrarCobro].
  @Deprecated('Los pagos deben ser registrados exclusivamente por el módulo de Caja a través de CajaService.registrarCobro')
  static Future<OrdenPagoResponseModel> pagarOrden(
    String idOrden, {
    String metodoPago = 'Efectivo',
    int? monto,
    String? observaciones,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();

    try {
      final uri = Uri.parse('${ApiConstants.ordenesEndpoint}/$idOrden/pagar');
      final token = await AuthService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final payload = {
        'metodo_pago': metodoPago,
        'monto': ?monto,
        if (observaciones != null && observaciones.isNotEmpty) 'observaciones': observaciones,
      };

      debugPrint('💳 [SERVICE] Enviando confirmación de pago para orden ID: $idOrden ($metodoPago)');

      final response = await httpClient
          .post(
            uri,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Tiempo de espera agotado al procesar el pago.'),
          );

      dynamic decodedBody;
      try {
        decodedBody = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        try {
          decodedBody = jsonDecode(response.body);
        } catch (_) {
          decodedBody = null;
        }
      }

      if (response.statusCode == 200) {
        if (decodedBody is Map<String, dynamic>) {
          debugPrint('✅ [SERVICE] Pago exitoso recibido. QR: ${decodedBody['qr_transaccional_salida']}');
          return OrdenPagoResponseModel.fromJson(decodedBody);
        }
        throw Exception('Respuesta del servidor no válida al procesar el pago.');
      } else if (response.statusCode == 400) {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        throw Exception(detail?.toString() ?? 'No es posible registrar el pago para esta orden.');
      } else if (response.statusCode == 404) {
        throw Exception('La orden especificada no fue encontrada.');
      } else if (response.statusCode == 401) {
        if (kDebugMode) {
          debugPrint('🌐 [ORDENES] HTTP 401 Unauthorized en pagarOrden');
        }
        await AuthService.manejarSesionExpirada();
        throw Exception('Sesión expirada. Por favor vuelve a iniciar sesión.');
      } else {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        throw Exception(detail?.toString() ?? 'Error al procesar el pago (${response.statusCode}).');
      }
    } catch (e) {
      debugPrint('💥 [SERVICE] Error en pagarOrden: $e');
      if (e is Exception) rethrow;
      throw Exception('Error inesperado al procesar el pago: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Obtiene los vendedores activos de una sucursal para asignación.
  static Future<List<VendedorModel>> obtenerVendedores({
    int? sucursalId,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final sucursal = sucursalId ?? await AuthService.getSucursalId() ?? 1;
      final uri = Uri.parse('${ApiConstants.ordenesEndpoint}/vendedores')
          .replace(queryParameters: {'sucursal_id': sucursal.toString()});
      final token = await AuthService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await httpClient.get(uri, headers: headers).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Tiempo de espera agotado.'),
          );

      if (response.statusCode == 200) {
        dynamic decoded;
        try {
          decoded = jsonDecode(utf8.decode(response.bodyBytes));
        } catch (_) {
          decoded = jsonDecode(response.body);
        }
        final List<dynamic> body = decoded as List<dynamic>;
        return body
            .map((v) => VendedorModel.fromJson(v as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Error al obtener lista de vendedores (${response.statusCode})');
      }
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Consulta el listado colaborativo de entregas en tienda y despachos externos.
  static Future<List<EntregaEnvioModel>> obtenerEntregasEnvios({
    int? sucursalId,
    String? tipo,
    String? busquedaCliente,
    String? busquedaVendedor,
    String? busqueda,
    String? estadoPago,
    bool soloActivas = true,
    int? limit,
    int? offset,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final sucursal = sucursalId ?? await AuthService.getSucursalId() ?? 1;
      final queryParams = <String, String>{
        'sucursal_id': sucursal.toString(),
        if (tipo != null && tipo.isNotEmpty) 'tipo': tipo,
        if (busquedaCliente != null && busquedaCliente.isNotEmpty)
          'busqueda_cliente': busquedaCliente,
        if (busquedaVendedor != null && busquedaVendedor.isNotEmpty)
          'busqueda_vendedor': busquedaVendedor,
        if (busqueda != null && busqueda.isNotEmpty) 'busqueda': busqueda,
        if (estadoPago != null && estadoPago.isNotEmpty)
          'estado_pago': estadoPago,
        'solo_activas': soloActivas.toString(),
        if (limit != null) 'limit': limit.toString(),
        if (offset != null) 'offset': offset.toString(),
      };

      final uri = Uri.parse('${ApiConstants.ordenesEndpoint}/entregas-envios')
          .replace(queryParameters: queryParams);
      final token = await AuthService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await httpClient.get(uri, headers: headers).timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw Exception(
              'Tiempo de espera agotado al consultar entregas.',
            ),
          );

      if (response.statusCode == 200) {
        final List<dynamic> body =
            jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        return body
            .map((item) =>
                EntregaEnvioModel.fromJson(item as Map<String, dynamic>))
            .toList();
      } else {
        throw Exception('Error al consultar entregas: ${response.statusCode}');
      }
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// [DEPRECATED] Bypass legado para confirmar entregas (SPEC-HU-TAREA-19).
  /// En el flujo operativo oficial, la entrega presencial se realiza obligatoriamente mediante el Dual-Scan en Barrera de Bodega.
  @Deprecated('Las entregas deben ser procesadas exclusivamente en la Barrera de Salida de Bodega')
  static Future<bool> confirmarEntregaTienda(
    String idOrden, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final uri = Uri.parse('${ApiConstants.ordenesEndpoint}/$idOrden/entregar');
      final token = await AuthService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await httpClient.patch(uri, headers: headers).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Tiempo de espera agotado.'),
          );

      if (response.statusCode == 200) {
        OrdenesSyncNotifier.instance.notificarCambio();
        return true;
      } else {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        final detail = body is Map ? body['detail'] : 'Error al confirmar entrega';
        throw Exception(detail);
      }
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Marca un despacho externo como enviado (cierre de ciclo).
  static Future<bool> marcarDespachoEnviado(
    String idDespacho, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final uri =
          Uri.parse('${ApiConstants.baseUrl}/api/v1/despachos/$idDespacho/enviar');
      final token = await AuthService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await httpClient.patch(uri, headers: headers).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Tiempo de espera agotado.'),
          );

      if (response.statusCode == 200) {
        OrdenesSyncNotifier.instance.notificarCambio();
        return true;
      } else {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        final detail =
            body is Map ? body['detail'] : 'Error al marcar despacho enviado';
        throw Exception(detail);
      }
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Actualiza exclusivamente el estado del despacho ('Por Enviar' o 'Enviado')
  /// sin alterar el estado de la orden ni liberar activos en bodega.
  static Future<bool> actualizarEstadoDespacho(
    String idDespacho,
    String nuevoEstado, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final uri =
          Uri.parse('${ApiConstants.baseUrl}/api/v1/despachos/$idDespacho/estado');
      final token = await AuthService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final body = jsonEncode({'nuevo_estado': nuevoEstado});

      final response = await httpClient.patch(uri, headers: headers, body: body).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw Exception('Tiempo de espera agotado.'),
          );

      if (response.statusCode == 200) {
        OrdenesSyncNotifier.instance.notificarCambio();
        return true;
      } else {
        final resBody = jsonDecode(utf8.decode(response.bodyBytes));
        final detail =
            resBody is Map ? resBody['detail'] : 'Error al actualizar estado del despacho';
        throw Exception(detail);
      }
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static Map<String, List<ComunaItemModel>>? _geografiaCache;

  /// Obtiene la lista de regiones y comunas dinámicas desde la Base de Datos.
  static Future<Map<String, List<ComunaItemModel>>> obtenerGeografia({http.Client? client}) async {
    if (_geografiaCache != null && _geografiaCache!.isNotEmpty) {
      return _geografiaCache!;
    }

    final httpClient = client ?? http.Client();
    try {
      final uri = Uri.parse('${ApiConstants.ordenesEndpoint}/comunas');
      final token = await AuthService.getToken();
      final headers = {
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final response = await httpClient.get(uri, headers: headers).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        final regionesJson = data['regiones'] as List<dynamic>? ?? [];
        final Map<String, List<ComunaItemModel>> resultado = {};
        final Map<String, int> idMapDinamico = {};
        final Map<String, List<String>> geoStringMap = {};

        for (final reg in regionesJson) {
          final nombreReg = reg['nombre_region']?.toString() ?? '';
          final comunasJson = reg['comunas'] as List<dynamic>? ?? [];
          final listaComunas = comunasJson
              .map((c) => ComunaItemModel.fromJson(c as Map<String, dynamic>))
              .toList();
          resultado[nombreReg] = listaComunas;
          geoStringMap[nombreReg] = listaComunas.map((c) => c.nombreComuna).toList();
          for (final c in listaComunas) {
            idMapDinamico[c.nombreComuna] = c.idComuna;
          }
        }

        ChileGeografia.registrarGeografiaDesdeBD(geoStringMap, idMapDinamico);
        _geografiaCache = resultado;
        return resultado;
      }
    } catch (e) {
      debugPrint('⚠️ Error obteniendo geografía de la BD: $e');
    } finally {
      if (client == null) httpClient.close();
    }

    return {};
  }
}

/// DTO para una comuna obtenida dinámicamente de la Base de Datos.
class ComunaItemModel {
  final int idComuna;
  final String nombreComuna;
  final int idRegion;

  const ComunaItemModel({
    required this.idComuna,
    required this.nombreComuna,
    required this.idRegion,
  });

  factory ComunaItemModel.fromJson(Map<String, dynamic> json) {
    return ComunaItemModel(
      idComuna: json['id_comuna'] as int? ?? 1,
      nombreComuna: json['nombre_comuna']?.toString() ?? '',
      idRegion: json['id_region'] as int? ?? 1,
    );
  }
}

/// DTO de resumen de vendedor para asignación.
class VendedorModel {
  final String idUsuario;
  final String nombreCompleto;
  final String rut;
  final int idSucursal;
  final String? correo;
  final int? idRol;
  final String? rolNombre;

  const VendedorModel({
    required this.idUsuario,
    required this.nombreCompleto,
    required this.rut,
    required this.idSucursal,
    this.correo,
    this.idRol,
    this.rolNombre,
  });

  bool get esLimache =>
      (correo != null && correo!.toLowerCase() == 'limache@cresal.cl') ||
      nombreCompleto.toLowerCase().contains('limache');

  bool get esJefeDeVentas =>
      idRol == 6 ||
      (rolNombre != null && rolNombre!.toLowerCase().contains('jefe')) ||
      nombreCompleto.toLowerCase().contains('jefe') ||
      nombreCompleto.toLowerCase().contains('zamora');

  bool get esVendedoraOnline =>
      idRol == 7 ||
      (rolNombre != null && rolNombre!.toLowerCase().contains('online')) ||
      nombreCompleto.toLowerCase().contains('online');

  String get etiquetaRol {
    if (esLimache) return 'Ventas Limache';
    if (esJefeDeVentas) return 'Jefe de Ventas';
    if (esVendedoraOnline) return 'Vendedora Online';
    return 'Vendedor Mesón';
  }

  factory VendedorModel.fromJson(Map<String, dynamic> json) {
    return VendedorModel(
      idUsuario: json['id_usuario']?.toString() ?? '',
      nombreCompleto: json['nombre_completo']?.toString() ?? '',
      rut: json['rut']?.toString() ?? '',
      idSucursal: json['id_sucursal'] as int? ?? 1,
      correo: json['correo']?.toString(),
      idRol: json['id_rol'] as int?,
      rolNombre: json['rol_nombre']?.toString(),
    );
  }
}

/// DTO para la vista de Entregas en Tienda y Despachos Externos.
class EntregaEnvioModel {
  final String idOrden;
  final int? numeroOrden;
  final String folio;
  final String tipoEntrega; // 'Retiro' o 'Despacho'
  final String estadoOrden;
  final int totalVenta;
  final int montoPendiente;
  final String? qrTransaccionalSalida;
  final String? fechaCreacion;
  final String? fechaActualizacion;
  final int totalItems;
  final ClienteOrdenResumenModel? cliente;
  final DespachoOrdenResumenModel? despacho;
  final List<DetalleOrdenItemModel> detalles;
  final String? vendedorNombre;
  final String? idVendedorAsignado;
  final String? vendedorAsignadoNombre;
  final bool preparacionLista;
  final bool todosPreparados;

  const EntregaEnvioModel({
    required this.idOrden,
    this.numeroOrden,
    required this.folio,
    required this.tipoEntrega,
    required this.estadoOrden,
    required this.totalVenta,
    required this.montoPendiente,
    this.qrTransaccionalSalida,
    this.fechaCreacion,
    this.fechaActualizacion,
    required this.totalItems,
    this.cliente,
    this.despacho,
    required this.detalles,
    this.vendedorNombre,
    this.idVendedorAsignado,
    this.vendedorAsignadoNombre,
    required this.preparacionLista,
    required this.todosPreparados,
  });

  bool get estaPagada => montoPendiente == 0;
  bool get tieneSaldoPendiente => montoPendiente > 0;
  bool get esReservada => estadoOrden.toLowerCase() == 'reservada';
  bool get esPagada => estadoOrden.toLowerCase() == 'pagada';
  bool get esCompletada => estadoOrden.toLowerCase() == 'completada';
  bool get esAnulada => estadoOrden.toLowerCase() == 'anulada';
  bool get contieneMotorOCaja => detalles.any((d) => d.esMotorOCaja);
  bool get contieneMiscelaneos => detalles.any((d) => !d.esMotorOCaja);
  bool get esMixta => contieneMotorOCaja && contieneMiscelaneos;
  bool get esDespacho => tipoEntrega.toLowerCase() == 'despacho' || despacho != null;
  bool get esRetiro => !esDespacho;
  bool get esVentaEnVerde => detalles.any((d) =>
      d.titulo.toUpperCase().contains('RESERVA EN VERDE') ||
      d.titulo.toUpperCase().contains('VENTA EN VERDE') ||
      (d.descripcionManual != null &&
          (d.descripcionManual!.toUpperCase().contains('RESERVA EN VERDE') ||
           d.descripcionManual!.toUpperCase().contains('VENTA EN VERDE'))));
  bool get tieneQrDisponible =>
      esPagada &&
      qrTransaccionalSalida != null &&
      qrTransaccionalSalida!.trim().isNotEmpty;
  String get totalVentaFormateado => OrdenResponseModel._formatearMonto(totalVenta);
  String get montoPendienteFormateado =>
      OrdenResponseModel._formatearMonto(montoPendiente);

  String get folioDisplay {
    if (folio.isNotEmpty && !folio.startsWith('TX-QR-')) return folio;
    if (numeroOrden != null) {
      return 'ORD-${numeroOrden.toString().padLeft(4, '0')}';
    }
    if (qrTransaccionalSalida != null &&
        qrTransaccionalSalida!.startsWith('ORD-')) {
      return qrTransaccionalSalida!;
    }
    return idOrden.length >= 8
        ? 'ORD-${idOrden.substring(0, 8).toUpperCase()}'
        : 'ORD-$idOrden';
  }

  bool get esConsumidorFinal {
    final rut = cliente?.rutCliente.trim() ?? '';
    final nombre = cliente?.nombres.trim().toLowerCase() ?? '';
    final apellido = cliente?.apellidos.trim().toLowerCase() ?? '';
    return rut == '6.666.666-6' ||
        rut == '66666666' ||
        rut == '66666666-6' ||
        nombre == 'consumidor' ||
        nombre == 'cliente mostrador sin rut' ||
        (nombre.isEmpty && apellido.isEmpty);
  }

  String get clienteDisplay {
    if (esConsumidorFinal) {
      return 'Orden: #$folioDisplay';
    }
    final nombre = '${cliente?.nombres ?? ""} ${cliente?.apellidos ?? ""}'.trim();
    return nombre.isNotEmpty ? nombre : 'Orden: #$folioDisplay';
  }

  DateTime? get fechaLocal {
    if (fechaCreacion == null || fechaCreacion!.trim().isEmpty) return null;
    try {
      final raw = fechaCreacion!.trim();
      final formattedIso = raw.contains('Z') || raw.contains('+')
          ? raw
          : '${raw.replaceAll(' ', 'T')}Z';
      return DateTime.parse(formattedIso).toLocal();
    } catch (_) {
      try {
        return DateTime.parse(fechaCreacion!).toLocal();
      } catch (_) {
        return null;
      }
    }
  }

  bool get esDeHoy {
    final local = fechaLocal;
    if (local == null) return false;
    final now = DateTime.now();
    return local.year == now.year && local.month == now.month && local.day == now.day;
  }

  String get fechaFormateada {
    final dt = fechaLocal;
    if (dt == null) return fechaCreacion ?? '--:--';
    final dia = dt.day.toString().padLeft(2, '0');
    final mes = dt.month.toString().padLeft(2, '0');
    final anio = dt.year;
    final hora = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dia/$mes/$anio $hora:$min';
  }

  OrdenHistorialModel toHistorialModel() {
    return OrdenHistorialModel(
      idOrden: idOrden,
      numeroOrden: numeroOrden,
      folio: folioDisplay,
      estadoOrden: estadoOrden,
      totalVenta: totalVenta,
      montoPendiente: montoPendiente,
      qrTransaccionalSalida: qrTransaccionalSalida,
      fechaCreacion: fechaCreacion,
      fechaActualizacion: fechaActualizacion,
      totalItems: totalItems,
      cliente: cliente,
      despacho: despacho,
      detalles: detalles,
    );
  }

  factory EntregaEnvioModel.fromJson(Map<String, dynamic> json) {
    return EntregaEnvioModel(
      idOrden: json['id_orden']?.toString() ?? '',
      numeroOrden: json['numero_orden'] as int?,
      folio: json['folio']?.toString() ?? '',
      tipoEntrega: json['tipo_entrega']?.toString() ?? 'Retiro',
      estadoOrden: json['estado_orden']?.toString() ?? 'Reservada',
      totalVenta: json['total_venta'] as int? ?? 0,
      montoPendiente: json['monto_pendiente'] as int? ?? 0,
      qrTransaccionalSalida: json['qr_transaccional_salida']?.toString(),
      fechaCreacion: json['fecha_creacion']?.toString(),
      fechaActualizacion: json['fecha_actualizacion']?.toString(),
      totalItems: json['total_items'] as int? ?? 0,
      cliente: json['cliente'] != null
          ? ClienteOrdenResumenModel.fromJson(
              json['cliente'] as Map<String, dynamic>)
          : null,
      despacho: json['despacho'] != null
          ? DespachoOrdenResumenModel.fromJson(
              json['despacho'] as Map<String, dynamic>)
          : null,
      detalles: (json['detalles'] as List<dynamic>?)
              ?.map((d) =>
                  DetalleOrdenItemModel.fromJson(d as Map<String, dynamic>))
              .toList() ??
          [],
      vendedorNombre: json['vendedor_nombre']?.toString(),
      idVendedorAsignado: json['id_vendedor_asignado']?.toString(),
      vendedorAsignadoNombre: json['vendedor_asignado_nombre']?.toString(),
      preparacionLista: json['preparacion_lista'] as bool? ?? false,
      todosPreparados: json['todos_preparados'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id_orden': idOrden,
    if (numeroOrden != null) 'numero_orden': numeroOrden,
    'folio': folio,
    'tipo_entrega': tipoEntrega,
    'estado_orden': estadoOrden,
    'total_venta': totalVenta,
    'monto_pendiente': montoPendiente,
    if (qrTransaccionalSalida != null) 'qr_transaccional_salida': qrTransaccionalSalida,
    if (fechaCreacion != null) 'fecha_creacion': fechaCreacion,
    if (fechaActualizacion != null) 'fecha_actualizacion': fechaActualizacion,
    'total_items': totalItems,
    if (cliente != null) 'cliente': cliente!.toJson(),
    if (despacho != null) 'despacho': despacho!.toJson(),
    'detalles': detalles.map((d) => d.toJson()).toList(),
    if (vendedorNombre != null) 'vendedor_nombre': vendedorNombre,
    if (idVendedorAsignado != null) 'id_vendedor_asignado': idVendedorAsignado,
    if (vendedorAsignadoNombre != null) 'vendedor_asignado_nombre': vendedorAsignadoNombre,
    'preparacion_lista': preparacionLista,
    'todos_preparados': todosPreparados,
  };
}
