import '../../paletizado/domain/models/etiqueta_data.dart';

class TareaAlerta {
  final String idTarea;
  final String tipoAlerta; // 'IMPRESION', 'PREPARACION', 'LIBERADA', 'TRASLADO'
  final String? ordenRef;
  final String? folio;
  final String tituloPieza;
  final String ubicacion;
  final String? notaEspecial;
  final String? estadoBloqueo;
  final String accionRequerida;
  final EtiquetaData? etiquetaData;
  final String? idDetalle;
  final String? idActivo;
  final int? idSucursalOrigen;
  final int? idSucursalDestino;
  final bool esTraslado;
  final String? estadoPreparacion;
  final String? categoria;
  final String? tipoRepuesto;
  final String? idOrden;
  final String? skuQrFisico;
  final String? motivoAnulacion;
  final String? ubicacionPasillo;
  final String? ubicacionPallet;
  final String? ubicacionGalpon;
  final bool? qrImpreso;

  const TareaAlerta({
    required this.idTarea,
    required this.tipoAlerta,
    this.ordenRef,
    this.folio,
    required this.tituloPieza,
    required this.ubicacion,
    this.notaEspecial,
    this.estadoBloqueo,
    required this.accionRequerida,
    this.etiquetaData,
    this.idDetalle,
    this.idActivo,
    this.idSucursalOrigen,
    this.idSucursalDestino,
    this.esTraslado = false,
    this.estadoPreparacion,
    this.categoria,
    this.tipoRepuesto,
    this.idOrden,
    this.skuQrFisico,
    this.motivoAnulacion,
    this.ubicacionPasillo,
    this.ubicacionPallet,
    this.ubicacionGalpon,
    this.qrImpreso,
  });

  factory TareaAlerta.fromJson(Map<String, dynamic> json) {
    final cat = json['categoria']?.toString() ?? json['tipo_repuesto']?.toString();
    final folioVal = json['folio']?.toString() ?? json['orden_ref']?.toString();
    return TareaAlerta(
      idTarea: json['id_tarea'] ?? '',
      tipoAlerta: json['tipo_alerta'] ?? '',
      ordenRef: json['orden_ref'] ?? folioVal,
      folio: folioVal,
      tituloPieza: json['titulo_pieza'] ?? 'Pieza Desconocida',
      ubicacion: json['ubicacion'] ?? 'Ubicación Pendiente',
      notaEspecial: json['nota_especial'],
      estadoBloqueo: json['estado_bloqueo'],
      accionRequerida: json['accion_requerida'] ?? '',
      etiquetaData: json['etiqueta_data'] != null
          ? EtiquetaData.fromJson(json['etiqueta_data'])
          : null,
      idDetalle: json['id_detalle']?.toString(),
      idActivo: json['id_activo']?.toString(),
      idSucursalOrigen: json['id_sucursal_origen'] as int?,
      idSucursalDestino: json['id_sucursal_destino'] as int?,
      esTraslado: json['es_traslado'] == true,
      estadoPreparacion: json['estado_preparacion']?.toString(),
      categoria: cat,
      tipoRepuesto: json['tipo_repuesto']?.toString() ?? cat,
      idOrden: json['id_orden']?.toString(),
      skuQrFisico: json['sku_qr_fisico']?.toString(),
      motivoAnulacion: json['motivo_anulacion']?.toString(),
      ubicacionPasillo: json['ubicacion_pasillo']?.toString(),
      ubicacionPallet: json['ubicacion_pallet']?.toString(),
      ubicacionGalpon: json['ubicacion_galpon']?.toString(),
      qrImpreso: json['qr_impreso'] as bool?,
    );
  }
}

