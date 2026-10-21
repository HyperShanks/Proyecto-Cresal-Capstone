import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';
import '../../auth/services/auth_service.dart';
import '../models/ticket_model.dart';

// Clave de almacenamiento seguro donde se guarda el JWT (igual que AuthService)
const String _tokenKey = 'access_token';

// ─────────────────────────────────────────────────────────────────────────────
// RESULTADOS DE OPERACIÓN (evita acoplar lógica HTTP a los widgets)
// ─────────────────────────────────────────────────────────────────────────────

class TicketResult {
  final bool success;
  final String? errorMessage;
  final TicketModel? ticket;

  bool get isOk => success;

  const TicketResult.ok(this.ticket)
      : success = true,
        errorMessage = null;

  const TicketResult.fail(this.errorMessage)
      : success = false,
        ticket = null;
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICIO DE TICKETS
// ─────────────────────────────────────────────────────────────────────────────

class TicketService {
  static const _storage = FlutterSecureStorage();

  // ── Helper interno para construir headers con Bearer token ─────────────────
  static Future<Map<String, String>> _buildAuthHeaders() async {
    final token = await _storage.read(key: _tokenKey);
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // ── POST /api/v1/tickets/ (Crear nuevo ticket) ──────────────────────────────
  static Future<TicketResult> crearTicket({
    required String tipoTicket,
    required String prioridad,
    required String asunto,
    required String descripcion,
    String? tablaReferencia,
    String? idReferencia,
  }) async {
    try {
      final headers = await _buildAuthHeaders();
      final uri = Uri.parse(ApiConstants.ticketsEndpoint);

      final body = jsonEncode(
        TicketModel.toJsonPayload(
          tipoTicket: tipoTicket,
          prioridad: prioridad,
          asunto: asunto,
          descripcion: descripcion,
          tablaReferencia: tablaReferencia,
          idReferencia: idReferencia,
        ),
      );

      final response = await http
          .post(uri, headers: headers, body: body)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Tiempo de espera agotado'),
          );

      if (response.statusCode == 201) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final ticket = TicketModel.fromJson(json);
        return TicketResult.ok(ticket);
      }

      // Manejo de errores HTTP (401, 422, etc.)
      try {
        final errorBody = jsonDecode(response.body);
        final detail = errorBody['detail'];
        if (detail is String) return TicketResult.fail(detail);
        if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          final msg = first['msg'] ?? 'Datos inválidos';
          return TicketResult.fail(msg.toString());
        }
      } catch (_) {}

      return TicketResult.fail('Error del servidor (${response.statusCode})');
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      return TicketResult.fail(msg);
    }
  }

  // ── GET /api/v1/tickets/mis-tickets (Historial de tickets propios) ──────────
  static Future<List<TicketModel>> obtenerMisTickets() async {
    try {
      final headers = await _buildAuthHeaders();
      final uri = Uri.parse('${ApiConstants.ticketsEndpoint}/mis-tickets');

      final response = await http
          .get(uri, headers: headers)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw Exception('Tiempo de espera agotado al consultar tickets'),
          );

      if (kDebugMode) {
        debugPrint('🌐 [TICKETS] HTTP ${response.statusCode} ${response.statusCode == 200 ? "OK" : response.statusCode == 401 ? "Unauthorized" : ""}');
      }

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        return list
            .map((item) => TicketModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }

      if (response.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
        throw Exception('Sesión expirada. Por favor inicie sesión nuevamente.');
      }

      throw Exception('Error al cargar tickets (${response.statusCode})');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception(e.toString());
    }
  }
}
