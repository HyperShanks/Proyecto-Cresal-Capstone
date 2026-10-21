import 'dart:convert';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../models/cobro_pendiente_model.dart';
import '../models/cobro_model.dart';
import '../models/historial_caja_model.dart';

abstract class ICajaService {
  Future<List<CobroPendienteModel>> obtenerCobrosPendientes({
    required int sucursalId,
    String? busqueda,
    String? tipoOperacion,
  });

  Future<RegistrarCobroResponseModel> registrarCobro(
    RegistrarCobroRequestModel request,
  );

  Future<ValidarActivoBackorderResponseModel> validarActivoBackorder(
    ValidarActivoBackorderRequestModel request,
  );

  Future<HistorialCajaResponseModel> obtenerHistorialCaja({
    required int sucursalId,
    String periodo = 'HOY',
    String? fechaDesde,
    String? fechaHasta,
    String estadoOrden = 'TODOS',
    String metodoPago = 'TODOS',
    String? busqueda,
    int? montoMin,
    int? montoMax,
    String? idCajera,
    String? idVendedor,
    int pagina = 1,
    int limite = 20,
  });
}

class CajaService implements ICajaService {
  final String _endpoint;

  CajaService({String? endpoint})
      : _endpoint = endpoint ?? ApiConstants.cajaEndpoint;

  @override
  Future<List<CobroPendienteModel>> obtenerCobrosPendientes({
    required int sucursalId,
    String? busqueda,
    String? tipoOperacion,
  }) async {
    final queryParams = <String, String>{
      'sucursal_id': sucursalId.toString(),
    };

    if (busqueda != null && busqueda.trim().isNotEmpty) {
      queryParams['busqueda'] = busqueda.trim();
    }

    if (tipoOperacion != null && tipoOperacion.trim().isNotEmpty) {
      queryParams['tipo_operacion'] = tipoOperacion.trim().toUpperCase();
    }

    final uri = Uri.parse('$_endpoint/pendientes').replace(
      queryParameters: queryParams,
    );

    final response = await ApiService.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final itemsRaw = data['items'] as List<dynamic>? ?? [];
      return itemsRaw
          .map((e) => CobroPendienteModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      String mensaje = 'Error al obtener cobros pendientes (${response.statusCode})';
      try {
        final errJson = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        if (errJson.containsKey('detail')) {
          mensaje = errJson['detail'].toString();
        }
      } catch (_) {}
      throw Exception(mensaje);
    }
  }

  @override
  Future<RegistrarCobroResponseModel> registrarCobro(
    RegistrarCobroRequestModel request,
  ) async {
    final uri = Uri.parse('$_endpoint/cobros/registrar');

    final response = await ApiService.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(request.toJson()),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return RegistrarCobroResponseModel.fromJson(data);
    } else {
      String mensaje = 'Error al registrar cobro (${response.statusCode})';
      try {
        final errJson = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        if (errJson.containsKey('detail')) {
          mensaje = errJson['detail'].toString();
        }
      } catch (_) {}
      throw Exception(mensaje);
    }
  }

  @override
  Future<ValidarActivoBackorderResponseModel> validarActivoBackorder(
    ValidarActivoBackorderRequestModel request,
  ) async {
    final uri = Uri.parse('$_endpoint/cobros/validar-activo-backorder');

    final response = await ApiService.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(request.toJson()),
    );

    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return ValidarActivoBackorderResponseModel.fromJson(data);
    } else {
      String mensaje = 'Error al validar activo (${response.statusCode})';
      try {
        final errJson = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        if (errJson.containsKey('detail')) {
          mensaje = errJson['detail'].toString();
        }
      } catch (_) {}
      throw Exception(mensaje);
    }
  }

  @override
  Future<HistorialCajaResponseModel> obtenerHistorialCaja({
    required int sucursalId,
    String periodo = 'HOY',
    String? fechaDesde,
    String? fechaHasta,
    String estadoOrden = 'TODOS',
    String metodoPago = 'TODOS',
    String? busqueda,
    int? montoMin,
    int? montoMax,
    String? idCajera,
    String? idVendedor,
    int pagina = 1,
    int limite = 20,
  }) async {
    final queryParams = <String, String>{
      'sucursal_id': sucursalId.toString(),
      'periodo': periodo,
      'estado_orden': estadoOrden,
      'metodo_pago': metodoPago,
      'pagina': pagina.toString(),
      'limite': limite.toString(),
    };

    if (fechaDesde != null && fechaDesde.trim().isNotEmpty) {
      queryParams['fecha_desde'] = fechaDesde.trim();
    }

    if (fechaHasta != null && fechaHasta.trim().isNotEmpty) {
      queryParams['fecha_hasta'] = fechaHasta.trim();
    }

    if (busqueda != null && busqueda.trim().isNotEmpty) {
      queryParams['busqueda'] = busqueda.trim();
    }

    if (montoMin != null) {
      queryParams['monto_min'] = montoMin.toString();
    }

    if (montoMax != null) {
      queryParams['monto_max'] = montoMax.toString();
    }

    if (idCajera != null && idCajera.trim().isNotEmpty) {
      queryParams['id_cajera'] = idCajera.trim();
    }

    if (idVendedor != null && idVendedor.trim().isNotEmpty) {
      queryParams['id_vendedor'] = idVendedor.trim();
    }

    final uri = Uri.parse('$_endpoint/historial').replace(
      queryParameters: queryParams,
    );

    final response = await ApiService.get(uri);

    if (response.statusCode == 200) {
      final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return HistorialCajaResponseModel.fromJson(data);
    } else {
      String mensaje = 'Error al obtener historial de auditoría (${response.statusCode})';
      try {
        final errJson = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        if (errJson.containsKey('detail')) {
          mensaje = errJson['detail'].toString();
        }
      } catch (_) {}
      throw Exception(mensaje);
    }
  }
}
