import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:crypto/crypto.dart'; // ⚠️ NUEVO: Para el cifrado HMAC-SHA256
import 'package:html/parser.dart' as html_parser; // ⚠️ NUEVO: Para leer el HTML

import '../../../core/constants/api_constants.dart';
import '../../../core/services/api_service.dart';
import '../../auth/services/auth_service.dart';
class VehiculoService {

  // ==========================================
  // 1. GET: Siguiente Ingreso (Se mantiene)
  // ==========================================
  Future<String> obtenerSiguienteIngreso() async {
    try {
      final uri = Uri.parse('${ApiConstants.vehiculosEndpoint}/siguiente-ingreso');
      final response = await ApiService.get(uri);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['siguiente_ingreso']?.toString() ?? '1';
      }
      if (response.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
      }
      return "ERROR";
    } catch (e) {
      debugPrint("Error de conexión: $e");
      return "ERROR";
    }
  }

  // ==========================================
  // 2. EL NUEVO SCRAPING NATIVO EN FLUTTER
  // ==========================================
  // Replicamos la función Python para generar la firma HMAC-SHA256
  String _cifrarData(String mensaje) {
    const secret =
        "b708574124a2742b5eecab4993a7f3e91528b8a99d38e1a663b2fcbe92e38a8c";
    final key = utf8.encode(secret);
    final bytes = utf8.encode(mensaje);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);
    return digest.toString();
  }

  Future<Map<String, dynamic>?> buscarDatosPorPatente(String patente) async {
    try {
      final patenteLimpia = patente
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
          .toUpperCase();

      // Headers estándar de navegador web moderno para evitar bloqueos por User-Agent
      final Map<String, String> headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Accept-Language': 'es-CL,es;q=0.9,en;q=0.8',
        'Sec-Ch-Ua':
            '"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"',
        'Sec-Ch-Ua-Mobile': '?0',
        'Sec-Ch-Ua-Platform': '"Windows"',
      };

      // PASO 1: Obtener las Cookies iniciales
      const homeUrl = 'https://www.patentechile.com/';
      final homeRes = await http.get(
        Uri.parse(homeUrl),
        headers: headers,
      );

      debugPrint('=== [SCRAPING DEBUG - PASO 1: HOME] ===');
      debugPrint('URL consultada: $homeUrl');
      debugPrint('Status Code: ${homeRes.statusCode}');
      debugPrint('Headers: ${homeRes.headers}');
      debugPrint(
          'Body preview (primeros 1000 chars): ${homeRes.body.substring(0, homeRes.body.length > 1000 ? 1000 : homeRes.body.length)}');
      debugPrint('========================');

      final rawCookie = homeRes.headers['set-cookie'];
      if (rawCookie != null) {
        // Extraemos solo la primera parte de la cookie de sesión
        headers['cookie'] = rawCookie.split(';')[0];
      }

      headers['Origin'] = 'https://www.patentechile.com';
      headers['Referer'] = 'https://www.patentechile.com/';
      headers['Content-Type'] = 'application/json';

      // PASO 2: Generar Payload y solicitar Token JWT
      final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
          .toString();
      final valor = 'vehiculo|$patenteLimpia|$timestamp';
      final valorCifrado = _cifrarData(valor);

      final payload = {
        "opt": "vehiculo",
        "valor": patenteLimpia,
        "x": valor,
        "z": valorCifrado,
      };

      const tokenUrl = 'https://www.patentechile.com/v3/token';
      final tokenRes = await http.post(
        Uri.parse(tokenUrl),
        headers: headers,
        body: jsonEncode(payload),
      );

      debugPrint('=== [SCRAPING DEBUG - PASO 2: TOKEN] ===');
      debugPrint('URL consultada: $tokenUrl');
      debugPrint('Status Code: ${tokenRes.statusCode}');
      debugPrint('Headers: ${tokenRes.headers}');
      debugPrint(
          'Body preview (primeros 1000 chars): ${tokenRes.body.substring(0, tokenRes.body.length > 1000 ? 1000 : tokenRes.body.length)}');
      debugPrint('========================');

      if (tokenRes.statusCode == 200) {
        final rpta = jsonDecode(tokenRes.body);

        if (rpta['status'] == true && rpta['jwt'] != null) {
          final token = rpta['jwt'];
          headers['Content-Type'] = 'application/x-www-form-urlencoded';
          final payloadToken = 'q=$token';

          // PASO 3: Obtener el HTML con los resultados reales
          const dataUrl = 'https://www.patentechile.com/resultados/';
          final dataRes = await http.post(
            Uri.parse(dataUrl),
            headers: headers,
            body: payloadToken,
          );

          debugPrint('=== [SCRAPING DEBUG] ===');
          debugPrint('URL consultada: $dataUrl');
          debugPrint('Status Code: ${dataRes.statusCode}');
          debugPrint('Headers: ${dataRes.headers}');
          debugPrint(
              'Body preview (primeros 1000 chars): ${dataRes.body.substring(0, dataRes.body.length > 1000 ? 1000 : dataRes.body.length)}');
          debugPrint('========================');

          if (dataRes.statusCode == 200) {
            try {
              // Analizamos el HTML como lo hacía BeautifulSoup en Python
              final document = html_parser.parse(dataRes.body);
              final filas = document.querySelectorAll('tr');

              Map<String, dynamic> datosVehiculo = {
                "marca": "",
                "modelo": "",
                "anio": "",
                "cilindrada": "",
                "numero_motor": "",
              };

              for (var fila in filas) {
                final celdas = fila.querySelectorAll('th, td');
                if (celdas.length >= 2) {
                  final etiqueta = celdas[0].text.trim().toLowerCase();
                  final valorCelda = celdas[1].text.trim();

                  if (etiqueta.contains('marca')) {
                    datosVehiculo['marca'] = valorCelda;
                  } else if (etiqueta.contains('modelo')) {
                    datosVehiculo['modelo'] = valorCelda;
                    // Extraemos la cilindrada usando Regex (Ej: "1.6" de "PEUGEOT 208 1.6")
                    final match = RegExp(r'(\d\.\d)').firstMatch(valorCelda);
                    if (match != null) {
                      datosVehiculo['cilindrada'] = match.group(1);
                    }
                  } else if (etiqueta.contains('año') ||
                      etiqueta.contains('ano')) {
                    datosVehiculo['anio'] = valorCelda;
                  } else if (etiqueta.contains('motor')) {
                    datosVehiculo['numero_motor'] = valorCelda;
                  }
                }
              }

              debugPrint('=== [SCRAPING PARSING RESULT] ===');
              debugPrint('Datos parseados: $datosVehiculo');
              debugPrint('================================');

              // Si encontró al menos la marca, consideramos que el scraping fue exitoso
              if (datosVehiculo['marca'] != "") {
                return datosVehiculo;
              }
            } catch (e, stackTrace) {
              debugPrint('=== [SCRAPING HTML PARSING ERROR] ===');
              debugPrint('Error al procesar selectores HTML: $e');
              debugPrint('StackTrace: $stackTrace');
              debugPrint('=====================================');
            }
          }
        }
      }
      return null;
    } catch (e, stackTrace) {
      debugPrint("=== [SCRAPING ERROR GENERAL] ===");
      debugPrint("Error en scraping nativo: $e");
      debugPrint("StackTrace: $stackTrace");
      debugPrint("================================");
      return null;
    }
  }

  // ==========================================
  // 3. POST MULTIPART: Guardar (Se mantiene)
  // ==========================================
  Future<Map<String, dynamic>> guardarIngresoConRespuesta(
    Map<String, dynamic> datosVehiculo,
    XFile foto,
  ) async {
    try {
      var uri = Uri.parse('${ApiConstants.vehiculosEndpoint}/');
      var request = http.MultipartRequest('POST', uri);
      final token = await AuthService.getToken();
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.fields['datos'] = jsonEncode(datosVehiculo);

      var bytes = await foto.readAsBytes();
      var multipartFile = http.MultipartFile.fromBytes(
        'foto',
        bytes,
        filename: foto.name,
      );
      request.files.add(multipartFile);

      var streamedResponse = await ApiService.send(request);
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
        return {
          'exito': false,
          'mensaje': 'Tu sesión ha expirado. Ingresa tu PIN nuevamente.',
        };
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'exito': true, 'mensaje': 'Guardado exitoso'};
      } else {
        final errorBody = jsonDecode(response.body);
        final mensajeDetail =
            errorBody['detail'] ?? errorBody['message_user'] ?? 'Error al guardar el ingreso';
        return {'exito': false, 'mensaje': mensajeDetail};
      }
    } catch (e) {
      return {'exito': false, 'mensaje': 'Error de conexión: $e'};
    }
  }

  // ==========================================
  // 4. REGISTRO MANUAL DE CONTINGENCIA (Fallback)
  // ==========================================
  Future<Map<String, dynamic>> guardarIngresoManual(
    Map<String, dynamic> datosVehiculo,
  ) async {
    try {
      final uri = Uri.parse('${ApiConstants.vehiculosEndpoint}/registro-manual');
      final response = await ApiService.post(
        uri,
        body: jsonEncode(datosVehiculo),
      );

      if (response.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
        return {
          'exito': false,
          'mensaje': 'Tu sesión ha expirado. Ingresa tu PIN nuevamente.',
        };
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'exito': true, 'mensaje': 'Guardado exitoso'};
      } else {
        final errorBody = jsonDecode(response.body);
        final mensajeDetail =
            errorBody['detail'] ?? errorBody['message_user'] ?? 'Error al registrar vehículo manual';
        return {'exito': false, 'mensaje': mensajeDetail};
      }
    } catch (e) {
      return {'exito': false, 'mensaje': 'Error de conexión: $e'};
    }
  }
}
