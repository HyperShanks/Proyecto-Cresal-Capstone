// ─────────────────────────────────────────────────────────────────────────────
// TICKET MODEL — Contrato de datos para Tickets de Soporte (HU-06)
//
// Mapea 1:1 con el DTO TicketResponse del backend FastAPI.
// Los campos DateTime se representan como String ISO 8601 porque el backend
// los serializa así para garantizar compatibilidad con json_decode de Dart.
// ─────────────────────────────────────────────────────────────────────────────

class TicketModel {
  final String idTicket;
  final String tipoTicket;
  final String prioridad;
  final String asunto;
  final String descripcion;
  final String idUsuarioCreador;
  final String? idUsuarioResolutor;
  final String? tablaReferencia;
  final String? idReferencia;
  final String estadoTicket;
  final String? observacionCierre;
  final String? fechaCreacion;
  final String? fechaCierre;

  const TicketModel({
    required this.idTicket,
    required this.tipoTicket,
    required this.prioridad,
    required this.asunto,
    required this.descripcion,
    required this.idUsuarioCreador,
    this.idUsuarioResolutor,
    this.tablaReferencia,
    this.idReferencia,
    required this.estadoTicket,
    this.observacionCierre,
    this.fechaCreacion,
    this.fechaCierre,
  });

  /// Folio legible formateado para la interfaz visual (ej: 'TCK-1042' o 'TCK-3FA85F')
  String get folioVisual {
    if (idTicket.startsWith('TCK-')) return idTicket;
    final clean = idTicket.replaceAll('-', '');
    final prefix = clean.length >= 6 ? clean.substring(0, 6) : clean;
    return 'TCK-${prefix.toUpperCase()}';
  }

  // ── Deserialización desde JSON de la API ───────────────────────────────────

  factory TicketModel.fromJson(Map<String, dynamic> json) {
    return TicketModel(
      idTicket: json['id_ticket'] as String,
      tipoTicket: json['tipo_ticket'] as String,
      prioridad: json['prioridad'] as String,
      asunto: json['asunto'] as String,
      descripcion: json['descripcion'] as String,
      idUsuarioCreador: json['id_usuario_creador'] as String,
      idUsuarioResolutor: json['id_usuario_resolutor'] as String?,
      tablaReferencia: json['tabla_referencia'] as String?,
      idReferencia: json['id_referencia'] as String?,
      estadoTicket: json['estado_ticket'] as String,
      observacionCierre: json['observacion_cierre'] as String?,
      fechaCreacion: json['fecha_creacion'] as String?,
      fechaCierre: json['fecha_cierre'] as String?,
    );
  }

  // ── Serialización hacia JSON para peticiones POST ──────────────────────────
  // Nota: Solo se incluyen los campos de TicketCreate (sin id_ticket, fechas ni estado).

  static Map<String, dynamic> toJsonPayload({
    required String tipoTicket,
    required String prioridad,
    required String asunto,
    required String descripcion,
    String? tablaReferencia,
    String? idReferencia,
  }) {
    return {
      'tipo_ticket': tipoTicket,
      'prioridad': prioridad,
      'asunto': asunto,
      'descripcion': descripcion,
      'tabla_referencia': tablaReferencia,
      'id_referencia': idReferencia,
    };
  }

  Map<String, dynamic> toCreateJson({
    required String tipoTicket,
    required String prioridad,
    required String asunto,
    required String descripcion,
    String? tablaReferencia,
    String? idReferencia,
  }) => toJsonPayload(
    tipoTicket: tipoTicket,
    prioridad: prioridad,
    asunto: asunto,
    descripcion: descripcion,
    tablaReferencia: tablaReferencia,
    idReferencia: idReferencia,
  );

  // ── Representación completa como Map (útil para logs y pruebas) ───────────

  Map<String, dynamic> toMap() {
    return {
      'id_ticket': idTicket,
      'tipo_ticket': tipoTicket,
      'prioridad': prioridad,
      'asunto': asunto,
      'descripcion': descripcion,
      'id_usuario_creador': idUsuarioCreador,
      'id_usuario_resolutor': idUsuarioResolutor,
      'tabla_referencia': tablaReferencia,
      'id_referencia': idReferencia,
      'estado_ticket': estadoTicket,
      'observacion_cierre': observacionCierre,
      'fecha_creacion': fechaCreacion,
      'fecha_cierre': fechaCierre,
    };
  }

  @override
  String toString() =>
      'TicketModel(id: $idTicket, asunto: $asunto, estado: $estadoTicket)';
}
