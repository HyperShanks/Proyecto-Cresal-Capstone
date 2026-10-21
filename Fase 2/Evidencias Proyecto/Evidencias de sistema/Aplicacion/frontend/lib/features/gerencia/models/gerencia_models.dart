// frontend/lib/features/gerencia/models/gerencia_models.dart
// Modelos de datos para el módulo de Gerencia y Dashboard Ejecutivo (HU-5.1).
// Diseñé estas estructuras inmutables para deserializar de forma segura
// las respuestas analíticas del backend.

class KpiFinancieroModel {
  final int ventasDelDia;
  final int transaccionesHoy;
  final int acumuladoMensualMtd;
  final double ticketPromedio;
  final double? margenBruto;

  const KpiFinancieroModel({
    required this.ventasDelDia,
    required this.transaccionesHoy,
    required this.acumuladoMensualMtd,
    required this.ticketPromedio,
    this.margenBruto,
  });

  factory KpiFinancieroModel.fromJson(Map<String, dynamic> json) {
    return KpiFinancieroModel(
      ventasDelDia: (json['ventas_del_dia'] as num?)?.toInt() ?? 0,
      transaccionesHoy: (json['transacciones_hoy'] as num?)?.toInt() ?? 0,
      acumuladoMensualMtd: (json['acumulado_mensual_mtd'] as num?)?.toInt() ?? 0,
      ticketPromedio: (json['ticket_promedio'] as num?)?.toDouble() ?? 0.0,
      margenBruto: (json['margen_bruto'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ventas_del_dia': ventasDelDia,
      'transacciones_hoy': transaccionesHoy,
      'acumulado_mensual_mtd': acumuladoMensualMtd,
      'ticket_promedio': ticketPromedio,
      'margen_bruto': margenBruto,
    };
  }
}

class DesglosePagoModel {
  final String metodoPago;
  final int montoTotal;
  final double porcentaje;
  final int cantidad;
  final double porcentajeCantidad;

  const DesglosePagoModel({
    required this.metodoPago,
    required this.montoTotal,
    required this.porcentaje,
    this.cantidad = 1,
    this.porcentajeCantidad = 0.0,
  });

  factory DesglosePagoModel.fromJson(Map<String, dynamic> json) {
    final pctMonto = (json['porcentaje'] as num?)?.toDouble() ?? 0.0;
    return DesglosePagoModel(
      metodoPago: json['metodo_pago']?.toString() ?? 'Desconocido',
      montoTotal: (json['monto_total'] as num?)?.toInt() ?? 0,
      porcentaje: pctMonto,
      cantidad: (json['cantidad'] as num?)?.toInt() ?? 1,
      porcentajeCantidad:
          (json['porcentaje_cantidad'] as num?)?.toDouble() ?? pctMonto,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'metodo_pago': metodoPago,
      'monto_total': montoTotal,
      'porcentaje': porcentaje,
      'cantidad': cantidad,
      'porcentaje_cantidad': porcentajeCantidad,
    };
  }
}

class ResumenPagosModel {
  final int efectivoFisico;
  final int canalesElectronicos;
  final int totalTransacciones;
  final List<DesglosePagoModel> desglose;

  const ResumenPagosModel({
    required this.efectivoFisico,
    required this.canalesElectronicos,
    this.totalTransacciones = 0,
    required this.desglose,
  });

  int get totalRecaudado => efectivoFisico + canalesElectronicos;

  int get transaccionesCalculadas =>
      totalTransacciones > 0
          ? totalTransacciones
          : desglose.fold<int>(0, (acc, item) => acc + item.cantidad);

  factory ResumenPagosModel.fromJson(Map<String, dynamic> json) {
    final rawDesglose = json['desglose'] as List<dynamic>? ?? [];
    final desgloseList = rawDesglose
        .map((e) => DesglosePagoModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final transCount = (json['total_transacciones'] as num?)?.toInt() ??
        desgloseList.fold<int>(0, (acc, item) => acc + item.cantidad);

    return ResumenPagosModel(
      efectivoFisico: (json['efectivo_fisico'] as num?)?.toInt() ?? 0,
      canalesElectronicos:
          (json['canales_electronicos'] as num?)?.toInt() ?? 0,
      totalTransacciones: transCount,
      desglose: desgloseList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'efectivo_fisico': efectivoFisico,
      'canales_electronicos': canalesElectronicos,
      'total_transacciones': totalTransacciones,
      'desglose': desglose.map((e) => e.toJson()).toList(),
    };
  }
}

class FlujoOperativoModel {
  final int enPreparacion;
  final int listosMostrador;
  final int enviadosCourier;
  final int alertasSaldoPendiente;
  final int cuellosBotellaPaletizados;

  const FlujoOperativoModel({
    required this.enPreparacion,
    required this.listosMostrador,
    required this.enviadosCourier,
    required this.alertasSaldoPendiente,
    required this.cuellosBotellaPaletizados,
  });

  factory FlujoOperativoModel.fromJson(Map<String, dynamic> json) {
    return FlujoOperativoModel(
      enPreparacion: (json['en_preparacion'] as num?)?.toInt() ?? 0,
      listosMostrador: (json['listos_mostrador'] as num?)?.toInt() ?? 0,
      enviadosCourier: (json['enviados_courier'] as num?)?.toInt() ?? 0,
      alertasSaldoPendiente:
          (json['alertas_saldo_pendiente'] as num?)?.toInt() ?? 0,
      cuellosBotellaPaletizados:
          (json['cuellos_botella_paletizados'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'en_preparacion': enPreparacion,
      'listos_mostrador': listosMostrador,
      'enviados_courier': enviadosCourier,
      'alertas_saldo_pendiente': alertasSaldoPendiente,
      'cuellos_botella_paletizados': cuellosBotellaPaletizados,
    };
  }
}

/// Modelo de Sucursal para el selector dinámico del módulo de Gerencia.
class SucursalGerenciaModel {
  final int idSucursal;
  final String nombreSucursal;
  final bool esCasaMatriz;

  const SucursalGerenciaModel({
    required this.idSucursal,
    required this.nombreSucursal,
    this.esCasaMatriz = false,
  });

  factory SucursalGerenciaModel.fromJson(Map<String, dynamic> json) {
    return SucursalGerenciaModel(
      idSucursal: (json['id_sucursal'] as num?)?.toInt() ?? 0,
      nombreSucursal: json['nombre_sucursal']?.toString() ?? '',
      esCasaMatriz: json['es_casa_matriz'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_sucursal': idSucursal,
      'nombre_sucursal': nombreSucursal,
      'es_casa_matriz': esCasaMatriz,
    };
  }

  /// Título limpio para el selector respetando la identidad de Casa Matriz
  String get tituloDisplay {
    if (esCasaMatriz) {
      if (nombreSucursal.toLowerCase().contains('matriz')) {
        return nombreSucursal;
      }
      return '$nombreSucursal (Casa Matriz)';
    }
    return nombreSucursal;
  }

  /// Subtítulo descriptivo simple sin calles ni exclusividades erróneas
  String get subtituloDisplay {
    if (esCasaMatriz) {
      return 'Casa Matriz';
    }
    return 'Sucursal';
  }
}
