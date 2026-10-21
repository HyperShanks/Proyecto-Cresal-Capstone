import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/api_constants.dart';
import '../../auth/services/auth_service.dart';
import '../models/checkout_wizard_models.dart';
import 'ordenes_service.dart';
import 'ordenes_sync_notifier.dart';

/// Servicio de alto nivel para el módulo de Ventas, Mesón y Checkout
class VentasService {
  /// Procesa una orden consolidada desde el Checkout Wizard con transaccionalidad ACID (SPEC-HU-05).
  static Future<CheckoutWizardResponseModel> processCheckoutWizard(
    CheckoutWizardRequestModel request, {
    String? token,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();

    try {
      final uri = Uri.parse('${ApiConstants.ordenesEndpoint}/checkout-wizard');
      final jwtToken = token ?? await AuthService.getToken();

      final headers = {
        'Content-Type': 'application/json',
        if (jwtToken != null && jwtToken.isNotEmpty) 'Authorization': 'Bearer $jwtToken',
      };

      final body = jsonEncode(request.toJson());

      final response = await httpClient
          .post(uri, headers: headers, body: body)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Tiempo de espera agotado al emitir la orden.'),
          );

      if (kDebugMode) {
        debugPrint('🌐 [VENTAS] HTTP ${response.statusCode} ${(response.statusCode == 200 || response.statusCode == 201) ? "OK" : response.statusCode == 401 ? "Unauthorized" : ""} en checkout-wizard');
      }

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
        OrdenesSyncNotifier.instance.notificarCambio();
        if (decodedBody is Map<String, dynamic>) {
          return CheckoutWizardResponseModel.fromJson(decodedBody);
        }
        return const CheckoutWizardResponseModel(
          idOrden: '',
          estado: 'Reservada',
          totalVenta: 0,
          montoPendiente: 0,
          mensaje: 'Orden generada exitosamente.',
        );
      } else if (response.statusCode == 400 || response.statusCode == 404 || response.statusCode == 403) {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        throw Exception(detail?.toString() ?? 'Error al procesar checkout (${response.statusCode}).');
      } else if (response.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
        throw Exception('Sesión expirada. Por favor vuelve a iniciar sesión.');
      } else {
        final detail = decodedBody is Map ? decodedBody['detail'] : null;
        throw Exception(detail?.toString() ?? 'Error del servidor al emitir orden (${response.statusCode}).');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Error inesperado al emitir la orden: $e');
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// Ejecuta la anulación de una orden en el Mesón de Ventas con motivo y reversa de pagos (SPEC-HU-TAREA-4).
  static Future<Map<String, dynamic>> anularOrden(
    String idOrden, {
    String? motivoAnulacion,
    String? observacionAnulacion,
    http.Client? client,
  }) async {
    return OrdenesService.anularOrden(
      idOrden,
      motivoAnulacion: motivoAnulacion,
      observacionAnulacion: observacionAnulacion,
      usePost: true,
      client: client,
    );
  }

  /// Reasigna la titularidad comercial de una orden a otro vendedor activo.
  static Future<Map<String, dynamic>> reasignarVendedor({
    required String idOrden,
    required String idNuevoVendedor,
    String? motivo,
    http.Client? client,
  }) async {
    return OrdenesService.reasignarVendedor(
      idOrden: idOrden,
      idNuevoVendedor: idNuevoVendedor,
      motivo: motivo,
      client: client,
    );
  }
}
