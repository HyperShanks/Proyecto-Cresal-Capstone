/// Modelos de datos para el Historial de Órdenes y Auditoría de Caja (SPEC-HU-4.5 / CRES-217).
library;

class HistorialPagoDetalleModel {
  final String? idTransaccion;
  final String metodoPago;
  final int monto;
  final DateTime? fechaPago;

  HistorialPagoDetalleModel({
    this.idTransaccion,
    required this.metodoPago,
    required this.monto,
    this.fechaPago,
  });

  factory HistorialPagoDetalleModel.fromJson(Map<String, dynamic> json) =>
      HistorialPagoDetalleModel(
        idTransaccion: json['id_transaccion'] as String?,
        metodoPago: json['metodo_pago'] as String? ?? 'Efectivo',
        monto: json['monto'] as int? ?? 0,
        fechaPago: json['fecha_pago'] != null
            ? DateTime.tryParse(json['fecha_pago'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id_transaccion': idTransaccion,
        'metodo_pago': metodoPago,
        'monto': monto,
        'fecha_pago': fechaPago?.toIso8601String(),
      };
}

enum TipoActivoAuditoria {
  motorInventariado,
  cajaInventariada,
  motorMiscelaneo,
  cajaMiscelanea,
  ninguno,
}

class ActivoAuditoriaItem {
  final TipoActivoAuditoria tipo;
  final String label; // ej: MOT-1001, CAJ-200, MOTOR, CAJA
  final bool esInventariado;
  final String? sku;
  final String? vehiculoOrigen;
  final String descripcion;

  const ActivoAuditoriaItem({
    required this.tipo,
    required this.label,
    required this.esInventariado,
    this.sku,
    this.vehiculoOrigen,
    required this.descripcion,
  });

  bool get esMotor =>
      tipo == TipoActivoAuditoria.motorInventariado ||
      tipo == TipoActivoAuditoria.motorMiscelaneo;

  bool get esCaja =>
      tipo == TipoActivoAuditoria.cajaInventariada ||
      tipo == TipoActivoAuditoria.cajaMiscelanea;
}

class HistorialArticuloModel {
  final int cantidad;
  final String tipo;
  final String descripcion;
  final String? sku;
  final int precio;
  final int subtotal;
  final String? categoria;
  final String? marca;
  final String? modelo;
  final int? anio;
  final String? detalleTecnico;

  HistorialArticuloModel({
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

  /// Términos de exclusión para motores (accesorios electromecánicos y periféricos secundarios).
  /// Si la descripción contiene alguno de estos términos, NO debe recibir la insignia de MOTOR.
  static final List<String> exclusionesMotor = [
    'cremallera',
    'partida',
    'arranque',
    'limpia parabrisas',
    'limpiaparabrisas',
    'limpia parabrisa',
    'limpiaparabrisa',
    'limpiavidrio',
    'limpiavidrios',
    'limpia vidrio',
    'limpia vidrios',
    'alzavidrio',
    'alzavidrios',
    'alza vidrio',
    'alza vidrios',
    'calefaccion',
    'calefacción',
    'ventilador',
    'electroventilador',
    'electro ventilador',
    'electro-ventilador',
    'soplador',
    'blower',
    'espejo',
    'espejos',
    'antena',
    'bomba',
    'paso a paso',
    'ralenti',
    'ralentí',
    'sunroof',
    'techo',
    'actuador',
    'regulador',
    'fusible',
    'fusibles',
    'fusilera',
  ];

  /// Términos de exclusión para cajas (elementos auxiliares ajenos a la transmisión).
  /// Si la descripción contiene alguno de estos términos, NO debe recibir la insignia de CAJA.
  static final List<String> exclusionesCaja = [
    'fusible',
    'fusibles',
    'fusilera',
    'direccion',
    'dirección',
    'filtro',
    'filtro de aire',
    'filtro aire',
    'evaporador',
    'evaporadora',
    'bateria',
    'batería',
    'rele',
    'relé',
    'relay',
    'mariposa',
    'termostato',
    'herramienta',
    'herramientas',
    'sonido',
    'parlante',
  ];

  /// Retorna la cadena descriptiva del vehículo de origen si está disponible
  String? get vehiculoOrigenDisplay {
    final partes = <String>[];
    if (marca != null && marca!.trim().isNotEmpty) partes.add(marca!.trim());
    if (modelo != null && modelo!.trim().isNotEmpty) partes.add(modelo!.trim());
    if (anio != null) partes.add(anio.toString());

    if (partes.isEmpty) return null;
    final veh = partes.join(' ');
    if (detalleTecnico != null && detalleTecnico!.trim().isNotEmpty) {
      return '$veh - ${detalleTecnico!.trim()}';
    }
    return veh;
  }

  /// Clasifica el artículo como Motor o Caja de cambios (inventariado o misceláneo),
  /// aplicando estrictamente el filtro de exclusión semántica para evitar falsos positivos.
  ActivoAuditoriaItem? get activoAuditado {
    final skuNorm = (sku ?? '').trim().toUpperCase();
    final catNorm = (categoria ?? '').trim().toLowerCase();
    final descNorm = descripcion.toLowerCase();

    // 1. Detección para Piezas Inventariadas con SKU formal
    if (skuNorm.isNotEmpty || esInventariado) {
      if (skuNorm.startsWith('MOT') || catNorm.contains('motor')) {
        return ActivoAuditoriaItem(
          tipo: TipoActivoAuditoria.motorInventariado,
          label: skuNorm.isNotEmpty ? skuNorm : 'MOTOR',
          esInventariado: true,
          sku: skuNorm.isNotEmpty ? skuNorm : null,
          vehiculoOrigen: vehiculoOrigenDisplay,
          descripcion: descripcion,
        );
      }
      if (skuNorm.startsWith('CAJ') ||
          catNorm.contains('caja') ||
          catNorm.contains('transmisi')) {
        return ActivoAuditoriaItem(
          tipo: TipoActivoAuditoria.cajaInventariada,
          label: skuNorm.isNotEmpty ? skuNorm : 'CAJA',
          esInventariado: true,
          sku: skuNorm.isNotEmpty ? skuNorm : null,
          vehiculoOrigen: vehiculoOrigenDisplay,
          descripcion: descripcion,
        );
      }
    }

    // 2. Detección y Clasificación para Ítems Misceláneos (Texto libre de mesón sin SKU)
    // A. Regla Semántica para Motores
    final contienePalabraMotor = descNorm.contains('motor') ||
        descNorm.contains('block') ||
        ((descNorm.contains('verde') || descNorm.contains('backorder')) &&
            descNorm.contains('motor'));

    if (contienePalabraMotor) {
      // Verificación estricta de exclusiones de motor y componentes de caja ajenos
      final esFalsoPositivoMotor = exclusionesMotor.any((exc) => descNorm.contains(exc)) ||
          (descNorm.contains('caja') && exclusionesCaja.any((exc) => descNorm.contains(exc)));
      if (!esFalsoPositivoMotor) {
        return ActivoAuditoriaItem(
          tipo: TipoActivoAuditoria.motorMiscelaneo,
          label: 'MOTOR',
          esInventariado: false,
          sku: null,
          vehiculoOrigen: vehiculoOrigenDisplay,
          descripcion: descripcion,
        );
      }
    }

    // B. Regla Semántica para Cajas de Cambios / Transmisiones
    final contienePalabraCaja = descNorm.contains('caja') ||
        descNorm.contains('transmision') ||
        descNorm.contains('transmisión');

    if (contienePalabraCaja) {
      // Verificación estricta de exclusiones de caja
      final esFalsoPositivoCaja = exclusionesCaja.any((exc) => descNorm.contains(exc)) ||
          (descNorm.contains('motor') && exclusionesMotor.any((exc) => descNorm.contains(exc)));
      if (!esFalsoPositivoCaja) {
        // Asegurar que sea transmisión o caja de cambio
        final esTransmisionValida = descNorm.contains('transmisi') ||
            descNorm.contains('cambio') ||
            descNorm.contains('manual') ||
            descNorm.contains('mecanica') ||
            descNorm.contains('mecánica') ||
            descNorm.contains('automatica') ||
            descNorm.contains('automática') ||
            descNorm.contains('cvt') ||
            descNorm.contains('secuencial') ||
            descNorm.contains('caja');

        if (esTransmisionValida) {
          return ActivoAuditoriaItem(
            tipo: TipoActivoAuditoria.cajaMiscelanea,
            label: 'CAJA',
            esInventariado: false,
            sku: null,
            vehiculoOrigen: vehiculoOrigenDisplay,
            descripcion: descripcion,
          );
        }
      }
    }

    return null;
  }

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

  factory HistorialArticuloModel.fromJson(Map<String, dynamic> json) =>
      HistorialArticuloModel(
        cantidad: json['cantidad'] as int? ?? 1,
        tipo: json['tipo'] as String? ?? 'INVENTARIADO',
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

class HistorialMovimientoModel {
  final String hora;
  final String evento;

  HistorialMovimientoModel({
    required this.hora,
    required this.evento,
  });

  factory HistorialMovimientoModel.fromJson(Map<String, dynamic> json) =>
      HistorialMovimientoModel(
        hora: json['hora'] as String? ?? '',
        evento: json['evento'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'hora': hora,
        'evento': evento,
      };
}

class ResumenCuadreCajaModel {
  final int totalRecaudado;
  final int totalOrdenesPagadas;
  final int totalEfectivo;
  final int totalPos;
  final int totalDebito;
  final int totalCredito;
  final int totalTransferencia;
  final int totalCheque;

  ResumenCuadreCajaModel({
    required this.totalRecaudado,
    required this.totalOrdenesPagadas,
    required this.totalEfectivo,
    required this.totalPos,
    required this.totalDebito,
    required this.totalCredito,
    required this.totalTransferencia,
    required this.totalCheque,
  });

  factory ResumenCuadreCajaModel.empty() => ResumenCuadreCajaModel(
        totalRecaudado: 0,
        totalOrdenesPagadas: 0,
        totalEfectivo: 0,
        totalPos: 0,
        totalDebito: 0,
        totalCredito: 0,
        totalTransferencia: 0,
        totalCheque: 0,
      );

  factory ResumenCuadreCajaModel.fromJson(Map<String, dynamic> json) =>
      ResumenCuadreCajaModel(
        totalRecaudado: json['total_recaudado'] as int? ?? 0,
        totalOrdenesPagadas: json['total_ordenes_pagadas'] as int? ?? 0,
        totalEfectivo: json['total_efectivo'] as int? ?? 0,
        totalPos: json['total_pos'] as int? ?? 0,
        totalDebito: json['total_debito'] as int? ?? 0,
        totalCredito: json['total_credito'] as int? ?? 0,
        totalTransferencia: json['total_transferencia'] as int? ?? 0,
        totalCheque: json['total_cheque'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'total_recaudado': totalRecaudado,
        'total_ordenes_pagadas': totalOrdenesPagadas,
        'total_efectivo': totalEfectivo,
        'total_pos': totalPos,
        'total_debito': totalDebito,
        'total_credito': totalCredito,
        'total_transferencia': totalTransferencia,
        'total_cheque': totalCheque,
      };
}

class HistorialOrdenItemModel {
  final String idOrden;
  final String folio;
  final String tipoOperacion;
  final bool emiteQr;
  final String fechaIso;
  final String hora;
  final String fechaHoraFormateada;
  final String? fechaCreacionFormateada;
  final String clienteNombre;
  final String? clienteRut;
  final String vendedorNombre;
  final String cajeraNombre;
  final String estadoOrden;
  final String modalidadPago;
  final String metodosResumen;
  final int totalVenta;
  final int descuento;
  final int abonoPrevio;
  final int totalLiquidado;
  final int montoPendiente;
  final int? idSucursal;
  final String sucursalNombre;
  final List<HistorialPagoDetalleModel> desglosePagos;
  final List<HistorialArticuloModel> articulos;
  final List<HistorialMovimientoModel> historialMovimientos;

  HistorialOrdenItemModel({
    required this.idOrden,
    required this.folio,
    required this.tipoOperacion,
    required this.emiteQr,
    required this.fechaIso,
    required this.hora,
    required this.fechaHoraFormateada,
    required this.clienteNombre,
    this.clienteRut,
    required this.vendedorNombre,
    required this.cajeraNombre,
    required this.estadoOrden,
    required this.modalidadPago,
    required this.metodosResumen,
    required this.totalVenta,
    this.descuento = 0,
    required this.abonoPrevio,
    required this.totalLiquidado,
    this.montoPendiente = 0,
    this.idSucursal,
    this.sucursalNombre = '',
    this.fechaCreacionFormateada,
    required this.desglosePagos,
    required this.articulos,
    required this.historialMovimientos,
  });

  bool get esPagada => estadoOrden == 'Pagada';
  bool get esDespachada => estadoOrden == 'Despachada';
  bool get esAnulada => estadoOrden == 'Anulada';
  bool get esSplit => modalidadPago.toLowerCase() == 'split';

  /// Lista de activos (Motores y Cajas de Cambio) clasificados según su origen,
  /// excluyendo estrictamente repuestos secundarios y falsos positivos electromecánicos.
  List<ActivoAuditoriaItem> get activosAuditados {
    final auditados = <ActivoAuditoriaItem>[];
    for (final art in articulos) {
      final act = art.activoAuditado;
      if (act != null) {
        auditados.add(act);
      }
    }

    // Si la orden es una operación en verde o backorder sin artículos específicos catalogados
    if (auditados.isEmpty) {
      final op = tipoOperacion.toUpperCase();
      if (op.contains('VERDE') || op.contains('BACKORDER')) {
        auditados.add(
          ActivoAuditoriaItem(
            tipo: TipoActivoAuditoria.motorMiscelaneo,
            label: 'MOTOR',
            esInventariado: false,
            sku: null,
            vehiculoOrigen: null,
            descripcion: 'Venta en Verde / Backorder',
          ),
        );
      }
    }

    return auditados;
  }

  /// Retorna true si la orden incluye un Motor o Caja de cambios válido
  /// (inventariado o misceláneo calificado), excluyendo falsos positivos como
  /// motor de partida, motor de alzavidrio, motor de cremallera o caja de fusibles.
  bool get tieneMotorOCaja => activosAuditados.isNotEmpty;

  /// Retorna true si la orden tiene al menos un activo físico inventariado con SKU/QR
  bool get tieneInventariados =>
      articulos.any((a) => a.esInventariado || (a.sku != null && a.sku!.isNotEmpty));

  /// Retorna true si todos los ítems de la orden son activos inventariados
  bool get soloInventariados =>
      articulos.isNotEmpty &&
      articulos.every((a) => a.esInventariado || (a.sku != null && a.sku!.isNotEmpty));

  /// Retorna true si la orden contiene tanto ítems inventariados como piezas de desarme/mesón
  bool get esMixta =>
      articulos.any((a) => a.esInventariado || (a.sku != null && a.sku!.isNotEmpty)) &&
      articulos.any((a) => !a.esInventariado && (a.sku == null || a.sku!.isEmpty));

  String get folioDisplay {
    if (folio.isNotEmpty && !folio.startsWith('TX-QR-') && !folio.startsWith('TX-')) {
      return folio;
    }
    if (folio.startsWith('TX-QR-')) {
      final sinPrefijo = folio.replaceFirst('TX-QR-', '').replaceAll('-', '');
      if (sinPrefijo.length >= 4) {
        final sub = sinPrefijo.length >= 8 ? sinPrefijo.substring(0, 8) : sinPrefijo;
        return 'ORD-${sub.toUpperCase()}';
      }
    }
    if (idOrden.length >= 8) {
      final clean = idOrden.replaceAll('-', '');
      final sub = clean.length >= 8 ? clean.substring(0, 8) : clean;
      return 'ORD-${sub.toUpperCase()}';
    }
    return folio.isNotEmpty ? folio : 'ORD-0000';
  }

  factory HistorialOrdenItemModel.fromJson(Map<String, dynamic> json) =>
      HistorialOrdenItemModel(
        idOrden: json['id_orden'] as String? ?? '',
        folio: json['folio'] as String? ?? '',
        tipoOperacion: json['tipo_operacion'] as String? ?? 'VENTA',
        emiteQr: json['emite_qr'] as bool? ?? false,
        fechaIso: json['fecha_iso'] as String? ?? '',
        hora: json['hora'] as String? ?? '',
        fechaHoraFormateada: json['fecha_hora_formateada'] as String? ?? '',
        fechaCreacionFormateada: json['fecha_creacion_formateada'] as String?,
        clienteNombre: json['cliente_nombre'] as String? ?? 'Cliente Mostrador',
        clienteRut: json['cliente_rut'] as String?,
        vendedorNombre: json['vendedor_nombre'] as String? ?? '',
        cajeraNombre: json['cajera_nombre'] as String? ?? 'Caja 01',
        estadoOrden: json['estado_orden'] as String? ?? 'Pagada',
        modalidadPago: json['modalidad_pago'] as String? ?? 'unico',
        metodosResumen: json['metodos_resumen'] as String? ?? '',
        totalVenta: json['total_venta'] as int? ?? 0,
        descuento: json['descuento'] as int? ?? 0,
        abonoPrevio: json['abono_previo'] as int? ?? 0,
        totalLiquidado: json['total_liquidado'] as int? ?? 0,
        montoPendiente: json['monto_pendiente'] as int? ?? 0,
        idSucursal: json['id_sucursal'] as int?,
        sucursalNombre: json['sucursal_nombre'] as String? ?? '',
        desglosePagos: (json['desglose_pagos'] as List<dynamic>?)
                ?.map((e) =>
                    HistorialPagoDetalleModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        articulos: (json['articulos'] as List<dynamic>?)
                ?.map((e) =>
                    HistorialArticuloModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        historialMovimientos: (json['historial_movimientos'] as List<dynamic>?)
                ?.map((e) =>
                    HistorialMovimientoModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'id_orden': idOrden,
        'folio': folio,
        'tipo_operacion': tipoOperacion,
        'emite_qr': emiteQr,
        'fecha_iso': fechaIso,
        'hora': hora,
        'fecha_hora_formateada': fechaHoraFormateada,
        'fecha_creacion_formateada': fechaCreacionFormateada,
        'cliente_nombre': clienteNombre,
        'cliente_rut': clienteRut,
        'vendedor_nombre': vendedorNombre,
        'cajera_nombre': cajeraNombre,
        'estado_orden': estadoOrden,
        'modalidad_pago': modalidadPago,
        'metodos_resumen': metodosResumen,
        'total_venta': totalVenta,
        'descuento': descuento,
        'abono_previo': abonoPrevio,
        'total_liquidado': totalLiquidado,
        'monto_pendiente': montoPendiente,
        'id_sucursal': idSucursal,
        'sucursal_nombre': sucursalNombre,
        'desglose_pagos': desglosePagos.map((e) => e.toJson()).toList(),
        'articulos': articulos.map((e) => e.toJson()).toList(),
        'historial_movimientos':
            historialMovimientos.map((e) => e.toJson()).toList(),
      };
}

class HistorialCajaResponseModel {
  final int totalRegistros;
  final int paginaActual;
  final int limitePorPagina;
  final int totalPaginas;
  final int totalMontoConsolidado;
  final ResumenCuadreCajaModel resumenCuadre;
  final List<HistorialOrdenItemModel> items;

  HistorialCajaResponseModel({
    required this.totalRegistros,
    required this.paginaActual,
    required this.limitePorPagina,
    required this.totalPaginas,
    this.totalMontoConsolidado = 0,
    required this.resumenCuadre,
    required this.items,
  });

  factory HistorialCajaResponseModel.empty() => HistorialCajaResponseModel(
        totalRegistros: 0,
        paginaActual: 1,
        limitePorPagina: 20,
        totalPaginas: 1,
        totalMontoConsolidado: 0,
        resumenCuadre: ResumenCuadreCajaModel.empty(),
        items: [],
      );

  factory HistorialCajaResponseModel.fromJson(Map<String, dynamic> json) =>
      HistorialCajaResponseModel(
        totalRegistros: json['total_registros'] as int? ?? 0,
        paginaActual: json['pagina_actual'] as int? ?? 1,
        limitePorPagina: json['limite_por_pagina'] as int? ?? 20,
        totalPaginas: json['total_paginas'] as int? ?? 1,
        totalMontoConsolidado: json['total_monto_consolidado'] as int? ?? 0,
        resumenCuadre: json['resumen_cuadre'] != null
            ? ResumenCuadreCajaModel.fromJson(
                json['resumen_cuadre'] as Map<String, dynamic>)
            : ResumenCuadreCajaModel.empty(),
        items: (json['items'] as List<dynamic>?)
                ?.map((e) =>
                    HistorialOrdenItemModel.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  Map<String, dynamic> toJson() => {
        'total_registros': totalRegistros,
        'pagina_actual': paginaActual,
        'limite_por_pagina': limitePorPagina,
        'total_paginas': totalPaginas,
        'total_monto_consolidado': totalMontoConsolidado,
        'resumen_cuadre': resumenCuadre.toJson(),
        'items': items.map((e) => e.toJson()).toList(),
      };
}
