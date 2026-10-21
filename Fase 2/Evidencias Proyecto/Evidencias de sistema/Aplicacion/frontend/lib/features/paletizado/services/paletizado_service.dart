// lib/features/paletizado/services/paletizado_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../../core/constants/api_constants.dart';
import '../../auth/services/auth_service.dart';
class ConsultaIngresoResult {
  final bool exitoso;
  final int? statusCode;
  final String? mensajeError;
  final Map<String, dynamic>? datos;

  ConsultaIngresoResult.success(this.datos)
      : exitoso = true,
        statusCode = 200,
        mensajeError = null;

  ConsultaIngresoResult.error(this.statusCode, this.mensajeError)
      : exitoso = false,
        datos = null;
}

class PaletizadoService {

  /// SPEC-HU-TAREA-14: Consulta directa por N° de ingreso contra GET /api/v1/inventario/ingreso/{numero_ingreso}
  Future<ConsultaIngresoResult> consultarIngresoParaPaletizado(
    String numeroIngreso, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final folio = numeroIngreso.trim();
      if (folio.isEmpty) {
        return ConsultaIngresoResult.error(400, 'El número de ingreso no puede estar vacío.');
      }
      final url = Uri.parse('${ApiConstants.inventarioEndpoint}/ingreso/$folio');
      final token = await AuthService.getToken();
      final headers = {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response = await httpClient.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        return ConsultaIngresoResult.success(data);
      } else if (response.statusCode == 404) {
        return ConsultaIngresoResult.error(
          404,
          'Número de ingreso no encontrado en la base de datos.',
        );
      } else if (response.statusCode == 400) {
        return ConsultaIngresoResult.error(
          400,
          'El activo asociado a este número ya fue paletizado previamente o no requiere este flujo.',
        );
      } else {
        return ConsultaIngresoResult.error(
          response.statusCode,
          'Error del servidor al consultar ingreso (${response.statusCode}).',
        );
      }
    } catch (e) {
      debugPrint("📌 [PALETIZADO_SERVICE] ❌ Error de conexión al consultar ingreso: $e");
      return ConsultaIngresoResult.error(
        -1,
        'Error de conexión. Reintentando la búsqueda...',
      );
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  Future<Map<String, dynamic>?> buscarVehiculoPorIngreso(
    String numeroIngreso,
  ) async {
    try {
      debugPrint('📌 [PALETIZADO_SERVICE] 🔍 Buscando folio: $numeroIngreso');
      final url = Uri.parse('${ApiConstants.vehiculosEndpoint}/buscar/$numeroIngreso');
      final token = await AuthService.getToken();
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint("📌 [PALETIZADO_SERVICE] ❌ Error de conexión: $e");
      return null;
    }
  }

  /// Busca un vehículo y su folio a partir del número de serie grabado del motor.
  Future<Map<String, dynamic>?> buscarVehiculoPorNumeroMotor(
    String numeroMotor,
  ) async {
    try {
      debugPrint('📌 [PALETIZADO_SERVICE] 🔍 Buscando por N° Motor: $numeroMotor');
      final motorEncoded = Uri.encodeComponent(numeroMotor.trim());
      final url = Uri.parse('${ApiConstants.vehiculosEndpoint}/buscar-motor/$motorEncoded');
      final token = await AuthService.getToken();
      final headers = {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response = await http.get(url, headers: headers).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Tiempo de espera agotado'),
      );

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint("📌 [PALETIZADO_SERVICE] ❌ Error al buscar por N° Motor: $e");
      return null;
    }
  }

  Future<Map<String, dynamic>?> validarOCRPieza(
    String numeroIngreso,
    File imagenPosca,
  ) async {
    // ... (Mantén este método exactamente como lo tenías, solo agrégale los debugPrint si deseas)
    try {
      debugPrint('📌 [PALETIZADO_SERVICE] 🤖 Iniciando validación OCR...');
      final url = Uri.parse('${ApiConstants.vehiculosEndpoint}/validar-ocr-pieza');
      var request = http.MultipartRequest('POST', url);
      final token = await AuthService.getToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.fields['numero_ingreso'] = numeroIngreso;
      request.files.add(
        await http.MultipartFile.fromPath('imagen_posca', imagenPosca.path),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint("📌 [PALETIZADO_SERVICE] ❌ Error OCR: $e");
      return null;
    }
  }

  /// Envía los datos logísticos y recibe la respuesta enriquecida para la etiqueta.
  Future<Map<String, dynamic>?> guardarPaletizadoDefinitivo({
    required String folio,
    required String tipoRepuesto,
    required String galpon,
    required String pasillo,
    required String pallet,
    String? observaciones,
    String? cilindrada,
    String? combustible,
    String? transmisionTipo,
    String? numeroMotor,
    String? traccion,
    required List<File> fotos,
  }) async {
    try {
      debugPrint(
        '📌 [PALETIZADO_SERVICE] 🚀 Enviando paletizado para Folio $folio...',
      );
      final url = Uri.parse('${ApiConstants.vehiculosEndpoint}/guardar-paletizado');
      var request = http.MultipartRequest('POST', url);
      final token = await AuthService.getToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.fields['numero_ingreso'] = folio;
      request.fields['tipo_repuesto'] = tipoRepuesto;
      request.fields['galpon'] = galpon;
      request.fields['pasillo'] = pasillo;
      request.fields['pallet'] = pallet;

      if (observaciones != null && observaciones.isNotEmpty) {
        request.fields['observaciones'] = observaciones;
      }
      if (cilindrada != null && cilindrada.isNotEmpty) {
        request.fields['cilindrada'] = cilindrada;
      }
      if (combustible != null && combustible.isNotEmpty) {
        request.fields['combustible'] = combustible;
      }
      if (transmisionTipo != null && transmisionTipo.isNotEmpty) {
        request.fields['transmision_tipo'] = transmisionTipo;
      }
      if (numeroMotor != null && numeroMotor.isNotEmpty) {
        request.fields['numero_motor'] = numeroMotor;
      }
      if (traccion != null && traccion.isNotEmpty) {
        request.fields['traccion'] = traccion;
      }

      for (var foto in fotos) {
        request.files.add(
          await http.MultipartFile.fromPath('fotos_comerciales', foto.path),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint(
          '📌 [PALETIZADO_SERVICE] ✅ Éxito. Payload recibido con SKU: ${payload["sku_qr_fisico"]}',
        );
        return payload;
      } else {
        debugPrint(
          "📌 [PALETIZADO_SERVICE] ❌ Error ${response.statusCode}: ${response.body}",
        );
        return null;
      }
    } catch (e) {
      debugPrint("📌 [PALETIZADO_SERVICE] ❌ Error crítico de red: $e");
      return null;
    }
  }

  /// Confirma en el backend que el activo fue impreso físicamente.
  ///
  /// Ejecuta PATCH /api/v1/vehiculos/inventario/{idActivo}/impreso.
  /// Retorna true si el backend confirmó el cambio, false ante cualquier error.
  Future<bool> confirmarQrImpreso(String idActivo) async {
    try {
      debugPrint(
        '📌 [PALETIZADO_SERVICE] 🖨️ Confirmando qr_impreso=true para activo: $idActivo',
      );
      final url = Uri.parse(
        '${ApiConstants.vehiculosEndpoint}/inventario/$idActivo/impreso',
      );
      final token = await AuthService.getToken();
      final response = await http.patch(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: '{"qr_impreso": true}',
      );

      if (response.statusCode == 200) {
        debugPrint(
          '📌 [PALETIZADO_SERVICE] ✅ qr_impreso confirmado en BD para activo: $idActivo',
        );
        return true;
      } else {
        debugPrint(
          '📌 [PALETIZADO_SERVICE] ❌ Error ${response.statusCode} al confirmar qr_impreso: ${response.body}',
        );
        return false;
      }
    } catch (e) {
      debugPrint(
        '📌 [PALETIZADO_SERVICE] ❌ Excepción al confirmar qr_impreso: $e',
      );
      return false;
    }
  }

  Future<Map<String, dynamic>?> obtenerSiguienteParaForzar() async {
    try {
      debugPrint('📌 [PALETIZADO_SERVICE] 🔍 Buscando vehículo para forzar ingreso...');
      final url = Uri.parse('${ApiConstants.vehiculosEndpoint}/siguiente-para-forzar');
      final token = await AuthService.getToken();
      final headers = {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      } else if (response.statusCode == 404) {
        debugPrint('📌 [PALETIZADO_SERVICE] ⚠️ No hay vehículos vírgenes disponibles.');
        return null;
      }
      return null;
    } catch (e) {
      debugPrint("📌 [PALETIZADO_SERVICE] ❌ Error al buscar vehículo para forzar: $e");
      return null;
    }
  }

  Future<bool> forzarIngresoVehiculo(String idVehiculo, Map<String, dynamic> payload) async {
    try {
      debugPrint('📌 [PALETIZADO_SERVICE] 🚀 Enviando payload forzado para $idVehiculo');
      final url = Uri.parse('${ApiConstants.vehiculosEndpoint}/forzar/$idVehiculo');
      final token = await AuthService.getToken();
      final headers = {
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response = await http.put(url, headers: headers, body: jsonEncode(payload));

      if (response.statusCode == 200) {
        debugPrint('📌 [PALETIZADO_SERVICE] ✅ Vehículo $idVehiculo forzado exitosamente.');
        return true;
      } else {
        debugPrint('📌 [PALETIZADO_SERVICE] ❌ Error al forzar: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint("📌 [PALETIZADO_SERVICE] ❌ Error crítico de red al forzar: $e");
      return false;
    }
  }

  /// Consulta la lista de piezas pendientes de paletizado en bodega
  Future<List<dynamic>> obtenerPendientesPaletizado({int? sucursalId}) async {
    try {
      final sucursal = sucursalId ?? await AuthService.getSucursalId();
      final url = sucursal != null
          ? Uri.parse(
              '${ApiConstants.vehiculosEndpoint}/pendientes-paletizado?sucursal_id=$sucursal',
            )
          : Uri.parse(
              '${ApiConstants.vehiculosEndpoint}/pendientes-paletizado',
            );
      final token = await AuthService.getToken();
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
      } else {
        debugPrint(
          '📌 [PALETIZADO_SERVICE] ❌ Error ${response.statusCode} al obtener pendientes: ${response.body}',
        );
        return [];
      }
    } catch (e) {
      debugPrint('📌 [PALETIZADO_SERVICE] ❌ Excepción al obtener pendientes: $e');
      return [];
    }
  }
}
