// lib/features/paletizado/services/print_service.dart
//
// Módulo de Impresión Industrial para Honeywell PC42E-T vía Sockets TCP (Puerto Raw 9100).
//
// ARQUITECTURA: Clean Architecture / Feature-First
// Soporte Multi-Network Routing nativo en Android (Wi-Fi local + Datos Móviles simultáneos)
// y fallback por Sockets TCP estándar dart:io para pruebas en otras plataformas.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../domain/exceptions/printer_exceptions.dart';
import '../domain/models/etiqueta_data.dart';
import 'zpl_builder.dart';

/// Servicio de infraestructura para comunicación directa TCP con impresora térmica industrial.
class PrintService {
  // Configuración de red por defecto (IP Estática en Router Huawei y Puerto Raw JetDirect)
  static const String defaultPrinterIp = '192.168.8.50';
  static const int defaultPrinterPort = 9100;
  static const Duration timeoutConexion = Duration(milliseconds: 2500);
  static const Duration timeoutDiagnostico = Duration(milliseconds: 2000);

  // Canal nativo para Multi-Network Socket Routing en Android
  static const MethodChannel _channel = MethodChannel('cl.cresal/printer_channel');

  /// Valida de forma nativa si el dispositivo tiene interfaces de red activas (fallback dart:io).
  static Future<void> _verificarConexionRed() async {
    debugPrint('📌 [PRINT_SERVICE] 📶 Verificando interfaces de red locales...');
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      if (interfaces.isEmpty) {
        debugPrint('📌 [PRINT_SERVICE] ❌ No se detectaron interfaces de red activas.');
        throw const PrinterNetworkException();
      }

      debugPrint(
        '📌 [PRINT_SERVICE] 📶 Red disponible. Interfaces activas: ${interfaces.map((i) => i.name).join(", ")}',
      );
    } on SocketException catch (e) {
      debugPrint('📌 [PRINT_SERVICE] ❌ Fallo al consultar interfaces de red: $e');
      throw PrinterNetworkException('Fallo al validar conexión de red local.', e);
    }
  }

  /// Intenta abrir un Socket TCP directo hacia la impresora (fallback dart:io).
  static Future<Socket> _conectarSocket(String ip, int port) async {
    debugPrint('📌 [PRINT_SERVICE] 🔌 Intentando conectar a la impresora en $ip:$port (Timeout: ${timeoutConexion.inSeconds}s)...');
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: timeoutConexion,
      );
      debugPrint('📌 [PRINT_SERVICE] 🟢 Conexión TCP establecida exitosamente con $ip:$port');
      return socket;
    } on SocketException catch (e) {
      debugPrint('📌 [PRINT_SERVICE] ❌ SocketException al conectar con $ip:$port -> $e');
      throw PrinterTimeoutException(
        ip,
        port,
        'No se pudo conectar con la impresora Honeywell PC42E-T. Verifique que esté encendida y conectada al router.',
        e,
      );
    } on TimeoutException catch (e) {
      debugPrint('📌 [PRINT_SERVICE] ⏳ TimeoutException (${timeoutConexion.inSeconds}s) agotado con $ip:$port -> $e');
      throw PrinterTimeoutException(
        ip,
        port,
        'Tiempo de espera agotado al conectar con la impresora térmica Honeywell PC42E-T.',
        e,
      );
    } catch (e) {
      debugPrint('📌 [PRINT_SERVICE] ❌ Error inesperado al abrir socket TCP -> $e');
      throw PrinterCommunicationException(
        'Error inesperado al conectar con la impresora térmica.',
        e,
      );
    }
  }

  /// Decodifica las banderas físicas devueltas por el comando ZPL ~HS (Host Status).
  ///
  /// Lanza [PrinterPaperOutException] si detecta falta de papel.
  /// Lanza [PrinterHeadOpenException] si el cabezal está abierto.
  /// Lanza [PrinterRibbonOutException] si falta ribbon de resina.
  /// Lanza [PrinterPausedException] si la máquina está pausada.
  /// Lanza [PrinterOverheatException] si el cabezal está sobrecalentado.
  static void _decodificarBanderasHs(String rawResponse) {
    debugPrint('📌 [PRINT_SERVICE] 🩺 [FASE 2] Trama cruda devuelta por la máquina (~HS):\n$rawResponse');

    if (rawResponse.trim().isEmpty) {
      debugPrint('📌 [PRINT_SERVICE] ⚠️ Impresora no devolvió respuesta a ~HS. Se continuará con precaución.');
      return;
    }

    // ── Parser Defensivo ZPL II ──
    // Limpiamos caracteres STX (0x02), ETX (0x03) y retornos de carro
    final lineas = rawResponse
        .replaceAll('\x02', '') // STX
        .replaceAll('\x03', '') // ETX
        .replaceAll('\r', '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    debugPrint('📌 [PRINT_SERVICE] 🩺 Líneas parseadas de ~HS: $lineas');

    // ── Evaluación Línea 1: <STX>aaa,b,c,dddd,e,f,g,h,iii,j,k,l<ETX> ──
    if (lineas.isNotEmpty) {
      final camposLinea1 = lineas[0].split(',');
      // Bandera 'b' (Posición 1): Paper Out (0=OK, 1=Sin Papel)
      if (camposLinea1.length > 1) {
        final paperOutFlag = camposLinea1[1].trim();
        if (paperOutFlag == '1') {
          debugPrint('📌 [PRINT_SERVICE] ❌ Alerta física detectada: Paper Out (b=1).');
          throw const PrinterPaperOutException();
        }
      }
      // Bandera 'c' (Posición 2): Pause (0=Normal, 1=Pausada)
      if (camposLinea1.length > 2) {
        final pauseFlag = camposLinea1[2].trim();
        if (pauseFlag == '1') {
          debugPrint('📌 [PRINT_SERVICE] ⚠️ Alerta física detectada: Impresora Pausada (c=1).');
          throw const PrinterPausedException();
        }
      }
      // Bandera 'l' (Posición 11): Over Temperature (0=OK, 1=Sobrecalentamiento)
      if (camposLinea1.length > 11) {
        final overheatFlag = camposLinea1[11].trim();
        if (overheatFlag == '1') {
          debugPrint('📌 [PRINT_SERVICE] 🛑 Alerta física detectada: Head Overheat (l=1).');
          throw const PrinterOverheatException();
        }
      }
    }

    // ── Evaluación Línea 2: <STX>mmm,n,o,p,q,r,s,t,uuuu,v,www<ETX> ──
    if (lineas.length > 1) {
      final camposLinea2 = lineas[1].split(',');
      // Bandera 'o' (Posición 2): Head Open (0=Cerrado, 1=Abierto)
      if (camposLinea2.length > 2) {
        final headOpenFlag = camposLinea2[2].trim();
        if (headOpenFlag == '1') {
          debugPrint('📌 [PRINT_SERVICE] ❌ Alerta física detectada: Head Open / Tapa abierta (o=1).');
          throw const PrinterHeadOpenException();
        }
      }
      // Bandera 'p' (Posición 3): Ribbon Out (0=OK, 1=Sin Cinta / Resina)
      if (camposLinea2.length > 3) {
        final ribbonOutFlag = camposLinea2[3].trim();
        if (ribbonOutFlag == '1') {
          debugPrint('📌 [PRINT_SERVICE] ❌ Alerta física detectada: Ribbon Out (p=1).');
          throw const PrinterRibbonOutException();
        }
      }
    }

    debugPrint('📌 [PRINT_SERVICE] 🟢 [FASE 2] Diagnóstico físico OK: Papel, resina y cabezal en estado correcto.');
  }

  /// Ejecución de Health Check para sockets estándar dart:io.
  static Future<void> _verificarEstadoFisicoSocket(Socket socket) async {
    debugPrint('📌 [PRINT_SERVICE] 🩺 [FASE 2] Enviando comando de diagnóstico (~HS)...');

    final completer = Completer<String>();
    final buffer = StringBuffer();
    StreamSubscription<Uint8List>? subscription;

    final timer = Timer(timeoutDiagnostico, () {
      if (!completer.isCompleted) {
        debugPrint('📌 [PRINT_SERVICE] ⏱️ Timeout esperando respuesta de ~HS. Continuando con buffer acumulado...');
        completer.complete(buffer.toString());
      }
    });

    try {
      subscription = socket.listen(
        (data) {
          final chunk = utf8.decode(data, allowMalformed: true);
          buffer.write(chunk);

          final rawContent = buffer.toString();
          if (rawContent.contains('\x03') || rawContent.split('\n').length >= 3) {
            if (!completer.isCompleted) {
              timer.cancel();
              completer.complete(rawContent);
            }
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            timer.cancel();
            completer.completeError(
              PrinterCommunicationException('Error en socket al leer estado físico (~HS)', error),
            );
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            timer.cancel();
            completer.complete(buffer.toString());
          }
        },
        cancelOnError: true,
      );

      socket.write('~HS\r\n');
      await socket.flush();

      final rawResponse = await completer.future;
      timer.cancel();
      _decodificarBanderasHs(rawResponse);
    } finally {
      await subscription?.cancel();
    }
  }

  /// Enrutamiento nativo Android: conecta por Wi-Fi local mediante bindSocket nativo
  /// sin alterar la conexión principal de Datos Móviles (4G/5G).
  static Future<bool> _imprimirEnAndroid(
    EtiquetaData data, {
    required String printerIp,
    required int printerPort,
  }) async {
    debugPrint('📌 [PRINT_SERVICE] 🤖 [ANDROID NATIVO] Iniciando protocolo Multi-Network Routing...');

    // 1. Health Check físico (~HS) a través del canal nativo vinculado a Wi-Fi
    try {
      debugPrint('📌 [PRINT_SERVICE] 🩺 [ANDROID NATIVO] Solicitando diagnóstico ~HS vía socket Wi-Fi...');
      final rawHs = await _channel.invokeMethod<String>(
        'consultarEstadoFisico',
        {
          'ip': printerIp,
          'port': printerPort,
          'timeoutMs': timeoutDiagnostico.inMilliseconds,
        },
      );

      if (rawHs != null) {
        _decodificarBanderasHs(rawHs);
      }
    } on PlatformException catch (e) {
      debugPrint('📌 [PRINT_SERVICE] ❌ Error en canal nativo Android: ${e.code} - ${e.message}');
      if (e.code == 'NO_WIFI') {
        throw const PrinterNetworkException();
      } else if (e.code == 'TIMEOUT' || e.code == 'CONNECT_ERROR') {
        throw PrinterTimeoutException(
          printerIp,
          printerPort,
          'No se pudo conectar con la impresora Honeywell PC42E-T. Verifique que esté encendida y conectada al router.',
        );
      } else {
        throw PrinterCommunicationException(
          'Error de comunicación con la impresora térmica.',
          e,
        );
      }
    }

    // 2. Ensamblaje ZPL Dinámico (Fase 3)
    debugPrint('📌 [PRINT_SERVICE] 🏗️ [FASE 3] Ensamblando plantilla ZPL para SKU: ${data.skuQrFisico}...');
    final tramaZpl = ZplBuilder.buildEtiquetaActivo(data);
    debugPrint('📌 [PRINT_SERVICE] 📄 Vista previa ZPL generado:\n$tramaZpl');

    // 3. Transmisión de bytes ZPL vía socket enlazado a Wi-Fi
    try {
      debugPrint('📌 [PRINT_SERVICE] ⚡ [ANDROID NATIVO] Transmitiendo ZPL al búfer de la Honeywell...');
      final exito = await _channel.invokeMethod<bool>(
        'transmitirZpl',
        {
          'ip': printerIp,
          'port': printerPort,
          'zpl': tramaZpl,
          'timeoutMs': 3000,
        },
      );

      if (exito == true) {
        debugPrint('📌 [PRINT_SERVICE] ✅ [ANDROID NATIVO] Etiqueta transmitida con éxito. Impresión física en curso.');
        return true;
      } else {
        throw const PrinterCommunicationException('Fallo en la confirmación de transmisión hacia la impresora.');
      }
    } on PlatformException catch (e) {
      debugPrint('📌 [PRINT_SERVICE] ❌ Error al transmitir ZPL: ${e.code} - ${e.message}');
      if (e.code == 'NO_WIFI') {
        throw const PrinterNetworkException();
      } else if (e.code == 'TIMEOUT' || e.code == 'CONNECT_ERROR') {
        throw PrinterTimeoutException(
          printerIp,
          printerPort,
          'Tiempo de espera agotado al transmitir datos a la impresora térmica.',
        );
      } else {
        throw PrinterCommunicationException(
          'Error al enviar la etiqueta a la impresora térmica.',
          e,
        );
      }
    }
  }

  /// Flujo estándar mediante Sockets dart:io (para Desktop, Pruebas o iOS).
  static Future<bool> _imprimirEnSocketStandard(
    EtiquetaData data, {
    required String printerIp,
    required int printerPort,
  }) async {
    Socket? socket;
    try {
      await _verificarConexionRed();
      socket = await _conectarSocket(printerIp, printerPort);
      await _verificarEstadoFisicoSocket(socket);

      debugPrint('📌 [PRINT_SERVICE] 🏗️ [FASE 3] Ensamblando plantilla ZPL para SKU: ${data.skuQrFisico}...');
      final tramaZpl = ZplBuilder.buildEtiquetaActivo(data);
      debugPrint('📌 [PRINT_SERVICE] 📄 Vista previa ZPL generado:\n$tramaZpl');

      debugPrint('📌 [PRINT_SERVICE] ⚡ [FASE 3] Transmitiendo bytes UTF-8 al búfer de la Honeywell...');
      socket.add(utf8.encode(tramaZpl));
      await socket.flush();

      debugPrint('📌 [PRINT_SERVICE] ✅ [FASE 3] Etiqueta transmitida con éxito. Impresión física en curso.');
      return true;
    } finally {
      if (socket != null) {
        try {
          await socket.flush();
          await socket.close();
          socket.destroy();
        } catch (e) {
          debugPrint('📌 [PRINT_SERVICE] ⚠️ Error al cerrar socket: $e');
        }
      }
    }
  }

  /// Ejecuta la secuencia de impresión térmica para el activo proporcionado en [data].
  ///
  /// En Android conmuta automáticamente a [MethodChannel] con Multi-Network Routing,
  /// permitiendo imprimir vía Wi-Fi local sin perder la conexión 4G/5G a Supabase/Render.
  static Future<bool> imprimirEtiqueta(
    EtiquetaData data, {
    String printerIp = defaultPrinterIp,
    int printerPort = defaultPrinterPort,
  }) async {
    debugPrint('📌 [PRINT_SERVICE] 🖨️ [FASE 3] Iniciando secuencia de impresión industrial...');
    debugPrint(
      '📌 [PRINT_SERVICE] 📦 Activo: ${data.skuQrFisico} | Folio: ${data.numeroIngreso}',
    );
    debugPrint(
      '📌 [PRINT_SERVICE] 📍 Ubicación: G:${data.galpon} / P:${data.pasillo} / Pa:${data.pallet}',
    );

    try {
      if (!kIsWeb && Platform.isAndroid) {
        return await _imprimirEnAndroid(
          data,
          printerIp: printerIp,
          printerPort: printerPort,
        );
      } else {
        return await _imprimirEnSocketStandard(
          data,
          printerIp: printerIp,
          printerPort: printerPort,
        );
      }
    } on PrinterException catch (e) {
      debugPrint('📌 [PRINT_SERVICE] ❌ Excepción de dominio capturada: $e');
      rethrow;
    } catch (e) {
      debugPrint('📌 [PRINT_SERVICE] ❌ Excepción imprevista en servicio: $e');
      throw PrinterCommunicationException('Error general en el proceso de impresión', e);
    }
  }
}
