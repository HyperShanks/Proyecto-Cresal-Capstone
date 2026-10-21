// lib/features/paletizado/domain/exceptions/printer_exceptions.dart
//
// Excepciones de dominio para el subsistema de impresión industrial (Honeywell PC42E-T).

import 'package:flutter/material.dart';

/// Clase base para todas las excepciones del dominio de impresión térmica.
abstract class PrinterException implements Exception {
  final String mensaje;
  final String titulo;
  final String instruccionOperativa;
  final IconData icono;
  final dynamic originalError;

  const PrinterException(
    this.mensaje, {
    this.titulo = 'Error de Impresora',
    this.instruccionOperativa =
        'Revise la conexión y el estado de la impresora térmica.',
    this.icono = Icons.print_disabled_rounded,
    this.originalError,
  });

  @override
  String toString() =>
      '$runtimeType: $mensaje${originalError != null ? " (Causa: $originalError)" : ""}';
}

/// Lanzada cuando el dispositivo móvil (Sunmi L3) no cuenta con conexión a la red local (Wi-Fi).
class PrinterNetworkException extends PrinterException {
  const PrinterNetworkException([
    super.mensaje = 'El dispositivo no cuenta con interfaces de red activas.',
    dynamic originalError,
  ]) : super(
         titulo: 'Sin Conexión Wi-Fi',
         instruccionOperativa:
             'Active el Wi-Fi en la PDA y conéctese a la red del router de bodega.',
         icono: Icons.wifi_off_rounded,
         originalError: originalError,
       );
}

/// Lanzada cuando la impresora no responde dentro del tiempo límite,
/// indicando que está apagada, fuera de red o con cable desconectado.
class PrinterTimeoutException extends PrinterException {
  final String ip;
  final int port;

  const PrinterTimeoutException(
    this.ip,
    this.port, [
    super.mensaje = 'No se pudo conectar con la impresora Honeywell PC42E-T.',
    dynamic originalError,
  ]) : super(
         titulo: 'Impresora Inaccesible',
         instruccionOperativa:
             '1. Verifique que la impresora esté encendida con la luz LED frontal en verde fijo.\n2. Asegúrese de que el cable de red esté firmemente conectado al router.\n3. Confirme que la PDA esté conectada al Wi-Fi.',
         icono: Icons.cloud_off_rounded,
         originalError: originalError,
       );

  @override
  String toString() =>
      '$runtimeType: $mensaje [$ip:$port]${originalError != null ? " (Causa: $originalError)" : ""}';
}

/// Lanzada cuando el sensor óptico indica falta de papel o rollo de etiquetas agotado (Paper Out).
class PrinterPaperOutException extends PrinterException {
  const PrinterPaperOutException([
    super.mensaje = 'La impresora no tiene papel térmico.',
    dynamic originalError,
  ]) : super(
         titulo: 'Rollo de Etiquetas Agotado',
         instruccionOperativa:
             'Abra la tapa, coloque un nuevo rollo de etiquetas de 100x70 mm (4x2 pulgadas) y ajuste las guías plásticas verdes.',
         icono: Icons.layers_clear_rounded,
         originalError: originalError,
       );
}

/// Lanzada cuando el sensor de ribbon detecta falta de cinta térmica o resina agotada (Ribbon Out).
class PrinterRibbonOutException extends PrinterException {
  const PrinterRibbonOutException([
    super.mensaje = 'Falta de cinta térmica (Ribbon / Resina) en la impresora.',
    dynamic originalError,
  ]) : super(
         titulo: 'Falta Cinta / Resina (Ribbon)',
         instruccionOperativa:
             'Instale un nuevo rollo de ribbon de resina, enganche el extremo en el carrete recolector y ténselo girando el engranaje.',
         icono: Icons.album_outlined,
         originalError: originalError,
       );
}

/// Lanzada cuando el microswitch de la tapa detecta cabezal abierto (Head Open).
class PrinterHeadOpenException extends PrinterException {
  const PrinterHeadOpenException([
    super.mensaje =
        'La tapa o cabezal térmico de la impresora se encuentra abierto.',
    dynamic originalError,
  ]) : super(
         titulo: 'Cabezal / Tapa Abierta',
         instruccionOperativa:
             'Baje la tapa superior y presione ambos lados firmemente hacia abajo hasta escuchar el clic de bloqueo.',
         icono: Icons.lock_open_rounded,
         originalError: originalError,
       );
}

/// Lanzada cuando la impresora se encuentra en modo Pausa.
class PrinterPausedException extends PrinterException {
  const PrinterPausedException([
    super.mensaje = 'La impresora se encuentra en estado de pausa.',
    dynamic originalError,
  ]) : super(
         titulo: 'Impresora Pausada',
         instruccionOperativa:
             'Presione el botón frontal de alimentación (Feed) hasta que la luz LED quede en verde fijo para reanudar.',
         icono: Icons.pause_circle_outline_rounded,
         originalError: originalError,
       );
}

/// Lanzada cuando el cabezal térmico alcanza una temperatura fuera de límite seguro.
class PrinterOverheatException extends PrinterException {
  const PrinterOverheatException([
    super.mensaje = 'El cabezal térmico ha alcanzado una temperatura crítica.',
    dynamic originalError,
  ]) : super(
         titulo: 'Cabezal Sobrecalentado',
         instruccionOperativa:
             'Deje reposar la impresora encendida durante 60 segundos hasta que la luz LED se normalice en verde fijo.',
         icono: Icons.local_fire_department_rounded,
         originalError: originalError,
       );
}

/// Lanzada ante cualquier error general de socket TCP o fallo en la transmisión de datos.
class PrinterCommunicationException extends PrinterException {
  const PrinterCommunicationException([
    super.mensaje = 'Fallo de comunicación con la impresora térmica.',
    dynamic originalError,
  ]) : super(
         titulo: 'Fallo de Comunicación',
         instruccionOperativa:
             'Ocurrió un error al transferir los datos a la impresora térmica. Presione REINTENTAR.',
         icono: Icons.error_outline_rounded,
         originalError: originalError,
       );
}
