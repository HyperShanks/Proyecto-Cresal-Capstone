// frontend/lib/features/gerencia/services/gerencia_service.dart
import 'dart:convert';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../models/gerencia_models.dart';
import '../models/backorder_gerencia_models.dart';
import '../../caja/models/historial_caja_model.dart';
import '../../ventas/models/catalogo_model.dart';

/// Servicio de integración para el módulo de Gerencia (HU-5.1).
/// Implementé métodos asíncronos para consultar los 3 endpoints analíticos,
/// capturando posibles fallas de red y extrayendo mensajes sanitizados.
class GerenciaService {
  /// Consulto las métricas financieras (Ventas hoy, MTD, Ticket promedio, Margen).
  static Future<KpiFinancieroModel> obtenerKpis({int? idSucursal}) async {
    try {
      final queryParam =
          idSucursal != null ? '?id_sucursal=$idSucursal' : '';
      final url =
          Uri.parse('${ApiConstants.gerenciaEndpoint}/dashboard/kpis$queryParam');

      final response = await ApiService.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return KpiFinancieroModel.fromJson(data);
      } else {
        final msg = ApiService.extraerMensajeError(
          response,
          fallback: 'No fue posible cargar los KPIs financieros.',
        );
        throw CustomApiException(
          messageUser: msg,
          errorCode: 'GERENCIA_DATA_ERROR',
          statusCode: response.statusCode,
        );
      }
    } on CustomApiException {
      rethrow;
    } catch (e) {
      throw CustomApiException(
        messageUser:
            'No fue posible cargar las métricas gerenciales. Reintentando...',
        errorCode: 'GERENCIA_NETWORK_ERROR',
        messageDev: e.toString(),
      );
    }
  }

  /// Consulto el desglose de métodos de pago y comparativa efectivo vs electrónico.
  static Future<ResumenPagosModel> obtenerResumenPagos({int? idSucursal}) async {
    try {
      final queryParam =
          idSucursal != null ? '?id_sucursal=$idSucursal' : '';
      final url =
          Uri.parse('${ApiConstants.gerenciaEndpoint}/dashboard/pagos$queryParam');

      final response = await ApiService.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ResumenPagosModel.fromJson(data);
      } else {
        final msg = ApiService.extraerMensajeError(
          response,
          fallback: 'No fue posible cargar el resumen de medios de pago.',
        );
        throw CustomApiException(
          messageUser: msg,
          errorCode: 'GERENCIA_DATA_ERROR',
          statusCode: response.statusCode,
        );
      }
    } on CustomApiException {
      rethrow;
    } catch (e) {
      throw CustomApiException(
        messageUser:
            'Error al consultar la distribución de pagos. Reintentando...',
        errorCode: 'GERENCIA_NETWORK_ERROR',
        messageDev: e.toString(),
      );
    }
  }

  /// Consulto el flujo operativo de bodega, cuellos de botella y saldos pendientes.
  static Future<FlujoOperativoModel> obtenerFlujoOperativo(
      {int? idSucursal}) async {
    try {
      final queryParam =
          idSucursal != null ? '?id_sucursal=$idSucursal' : '';
      final url = Uri.parse(
          '${ApiConstants.gerenciaEndpoint}/dashboard/operativa$queryParam');

      final response = await ApiService.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return FlujoOperativoModel.fromJson(data);
      } else {
        final msg = ApiService.extraerMensajeError(
          response,
          fallback: 'No fue posible cargar el flujo operativo de bodega.',
        );
        throw CustomApiException(
          messageUser: msg,
          errorCode: 'GERENCIA_DATA_ERROR',
          statusCode: response.statusCode,
        );
      }
    } on CustomApiException {
      rethrow;
    } catch (e) {
      throw CustomApiException(
        messageUser:
            'Error de conexión con el pulso de bodega. Reintentando...',
        errorCode: 'GERENCIA_NETWORK_ERROR',
        messageDev: e.toString(),
      );
    }
  }

  /// Consulto el listado histórico y auditoría de órdenes de venta (HU-5.2).
  /// Permite filtros multidimensionales por sucursal, estado oficial, periodo temporal,
  /// método de pago, búsqueda predictiva y paginación.
  static Future<HistorialCajaResponseModel> obtenerHistorialOrdenes({
    int? idSucursal,
    String? estado,
    String? periodo,
    String? fechaInicio,
    String? fechaFin,
    String? metodoPago,
    String? tipoActivo,
    String? busqueda,
    int pagina = 1,
    int limite = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'pagina': pagina.toString(),
        'limite': limite.toString(),
      };
      if (idSucursal != null) {
        queryParams['id_sucursal'] = idSucursal.toString();
      }
      if (estado != null &&
          estado.isNotEmpty &&
          estado.toLowerCase() != 'todos') {
        queryParams['estado'] = estado;
      }
      if (periodo != null && periodo.isNotEmpty) {
        queryParams['periodo'] = periodo;
      }
      if (fechaInicio != null && fechaInicio.isNotEmpty) {
        queryParams['fecha_inicio'] = fechaInicio;
      }
      if (fechaFin != null && fechaFin.isNotEmpty) {
        queryParams['fecha_fin'] = fechaFin;
      }
      if (metodoPago != null &&
          metodoPago.isNotEmpty &&
          metodoPago.toLowerCase() != 'todos') {
        queryParams['metodo_pago'] = metodoPago;
      }
      if (tipoActivo != null &&
          tipoActivo.isNotEmpty &&
          tipoActivo.toLowerCase() != 'todos') {
        queryParams['tipo_activo'] = tipoActivo;
      }
      if (busqueda != null && busqueda.trim().isNotEmpty) {
        queryParams['search'] = busqueda.trim();
      }

      final uri = Uri.parse(ApiConstants.ordenesEndpoint)
          .replace(queryParameters: queryParams);
      final response = await ApiService.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return HistorialCajaResponseModel.fromJson(data);
      } else {
        final msg = ApiService.extraerMensajeError(
          response,
          fallback: 'No fue posible consultar el historial de órdenes.',
        );
        throw CustomApiException(
          messageUser: msg,
          errorCode: 'ORDEN_AUDITORIA_DATA_ERROR',
          statusCode: response.statusCode,
        );
      }
    } on CustomApiException {
      rethrow;
    } catch (e) {
      throw CustomApiException(
        messageUser: 'Error de red al consultar el historial de órdenes.',
        errorCode: 'ORDEN_AUDITORIA_NETWORK_ERROR',
        messageDev: e.toString(),
      );
    }
  }

  /// Consulto el detalle jerárquico 360° de una orden para auditoría forense (HU-5.2).
  static Future<Map<String, dynamic>> obtenerDetalleOrden(
      String idOrden) async {
    try {
      final uri = Uri.parse('${ApiConstants.ordenesEndpoint}/$idOrden');
      final response = await ApiService.get(uri);

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        final msg = ApiService.extraerMensajeError(
          response,
          fallback: 'No se encontró la orden especificada.',
        );
        throw CustomApiException(
          messageUser: msg,
          errorCode: 'ORDEN_AUDITORIA_NOT_FOUND',
          statusCode: response.statusCode,
        );
      }
    } on CustomApiException {
      rethrow;
    } catch (e) {
      throw CustomApiException(
        messageUser: 'Error al cargar el detalle de la orden.',
        errorCode: 'ORDEN_AUDITORIA_NETWORK_ERROR',
        messageDev: e.toString(),
      );
    }
  }

  /// Consulta el Maestro de Inventario Global multi-sucursal con filtros avanzados (HU-5.3).
  static Future<PaginatedCatalogoResponse> obtenerMaestroInventario({
    int? idSucursal,
    int? idCategoria,
    int? idEstado,
    String? estado,
    String? combustible,
    String? transmision,
    String? ubicacion,
    String? galpon,
    String? pasillo,
    String? pallet,
    bool soloSinTasar = false,
    String? busqueda,
    int limite = 15,
    int offset = 0,
  }) async {
    try {
      final queryParams = <String, String>{
        'limit': limite.toString(),
        'offset': offset.toString(),
      };
      if (idSucursal != null) queryParams['id_sucursal'] = idSucursal.toString();
      if (idCategoria != null) queryParams['id_categoria'] = idCategoria.toString();
      if (idEstado != null) queryParams['id_estado'] = idEstado.toString();
      if (estado != null && estado != 'todos') queryParams['estado'] = estado;
      if (combustible != null && combustible != 'todos') queryParams['combustible'] = combustible;
      if (transmision != null && transmision != 'todas') queryParams['transmision'] = transmision;
      if (ubicacion != null && ubicacion != 'todas') queryParams['ubicacion'] = ubicacion;
      if (galpon != null && galpon != 'todas' && galpon != 'todos') queryParams['galpon'] = galpon;
      if (pasillo != null && pasillo != 'todas' && pasillo != 'todos') queryParams['pasillo'] = pasillo;
      if (pallet != null && pallet != 'todas' && pallet != 'todos') queryParams['pallet'] = pallet;
      if (soloSinTasar) queryParams['solo_sin_tasar'] = 'true';
      if (busqueda != null && busqueda.trim().isNotEmpty) queryParams['q'] = busqueda.trim();

      final uri = Uri.parse('${ApiConstants.inventarioEndpoint}/maestro').replace(queryParameters: queryParams);
      final response = await ApiService.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return PaginatedCatalogoResponse.fromJson(data);
      } else {
        final msg = ApiService.extraerMensajeError(
          response,
          fallback: 'No fue posible cargar el inventario maestro.',
        );
        throw CustomApiException(
          messageUser: msg,
          errorCode: 'INVENTARIO_MAESTRO_DATA_ERROR',
          statusCode: response.statusCode,
        );
      }
    } on CustomApiException {
      rethrow;
    } catch (e) {
      throw CustomApiException(
        messageUser: 'Error de red al consultar el inventario maestro.',
        errorCode: 'INVENTARIO_MAESTRO_NETWORK_ERROR',
        messageDev: e.toString(),
      );
    }
  }

  /// Fija o actualiza el rango de tasación comercial de un repuesto (HU-5.3).
  static Future<Map<String, dynamic>> tasarActivo({
    required String idActivo,
    required int precioMinimo,
    required int precioMaximo,
    int? precioReferencia,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.inventarioEndpoint}/$idActivo/precio');
      final response = await ApiService.patch(
        uri,
        body: jsonEncode({
          'precio_minimo': precioMinimo,
          'precio_maximo': precioMaximo,
          'precio_referencia': precioReferencia ?? precioMaximo,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      } else {
        final msg = ApiService.extraerMensajeError(
          response,
          fallback: 'No fue posible fijar el precio de tasación.',
        );
        throw CustomApiException(
          messageUser: msg,
          errorCode: 'TASACION_ERROR',
          statusCode: response.statusCode,
        );
      }
    } on CustomApiException {
      rethrow;
    } catch (e) {
      throw CustomApiException(
        messageUser: 'Error de conexión al procesar la tasación comercial.',
        errorCode: 'TASACION_NETWORK_ERROR',
        messageDev: e.toString(),
      );
    }
  }

  /// Consulta los encargos de compra por encargo (Backorders) para el visor de supervisión de gerencia (HU-5.4).
  static Future<PaginatedBackordersResponse> obtenerBackorders({
    int? idSucursal,
    String? estado,
    String? busqueda,
    int pagina = 1,
    int limite = 20,
  }) async {
    try {
      final queryParameters = <String, String>{
        'limit': limite.toString(),
        'offset': ((pagina - 1) * limite).toString(),
      };
      if (idSucursal != null) {
        queryParameters['id_sucursal'] = idSucursal.toString();
      }
      if (estado != null && estado.isNotEmpty && estado != 'todos') {
        queryParameters['estado'] = estado;
      }
      if (busqueda != null && busqueda.trim().isNotEmpty) {
        queryParameters['q'] = busqueda.trim();
      }

      final uri = Uri.parse('${ApiConstants.gerenciaEndpoint}/backorders')
          .replace(queryParameters: queryParameters);

      final response = await ApiService.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return PaginatedBackordersResponse.fromJson(data);
      } else {
        final msg = ApiService.extraerMensajeError(
          response,
          fallback: 'No fue posible cargar la lista de backorders.',
        );
        throw CustomApiException(
          messageUser: msg,
          errorCode: 'BACKORDERS_DATA_ERROR',
          statusCode: response.statusCode,
        );
      }
    } on CustomApiException {
      rethrow;
    } catch (e) {
      throw CustomApiException(
        messageUser: 'Error de red al consultar el panel de backorders.',
        errorCode: 'BACKORDERS_NETWORK_ERROR',
        messageDev: e.toString(),
      );
    }
  }

  /// Consulta los KPIs consolidados de backorders (HU-5.4).
  static Future<BackordersKpisModel> obtenerBackordersKpis({int? idSucursal}) async {
    try {
      final queryParam = idSucursal != null ? '?id_sucursal=$idSucursal' : '';
      final uri = Uri.parse('${ApiConstants.gerenciaEndpoint}/backorders/kpis$queryParam');

      final response = await ApiService.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return BackordersKpisModel.fromJson(data);
      } else {
        final msg = ApiService.extraerMensajeError(
          response,
          fallback: 'No fue posible cargar las métricas de backorders.',
        );
        throw CustomApiException(
          messageUser: msg,
          errorCode: 'BACKORDERS_KPIS_ERROR',
          statusCode: response.statusCode,
        );
      }
    } on CustomApiException {
      rethrow;
    } catch (e) {
      throw CustomApiException(
        messageUser: 'Error de conexión al obtener los KPIs de backorders.',
        errorCode: 'BACKORDERS_KPIS_NETWORK_ERROR',
        messageDev: e.toString(),
      );
    }
  }

  /// Consulta el listado dinámico de sucursales activas en la base de datos (Supabase).
  static Future<List<SucursalGerenciaModel>> obtenerSucursales() async {
    try {
      final uri = Uri.parse('${ApiConstants.gerenciaEndpoint}/sucursales');
      final response = await ApiService.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> data =
            jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        return data
            .map(
              (item) => SucursalGerenciaModel.fromJson(
                item as Map<String, dynamic>,
              ),
            )
            .toList();
      }
    } catch (e) {
      // Ignoramos silenciosamente y recurrimos al fallback resiliente
    }

    // Fallback defensivo con las sucursales registradas en Supabase
    return const [
      SucursalGerenciaModel(
        idSucursal: 1,
        nombreSucursal: 'Viña del Mar',
        esCasaMatriz: true,
      ),
      SucursalGerenciaModel(
        idSucursal: 2,
        nombreSucursal: 'Limache',
        esCasaMatriz: false,
      ),
    ];
  }
}

