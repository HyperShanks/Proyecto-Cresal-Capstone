// lib/features/paletizado/presentation/widgets/etiqueta_termica_widget.dart
//
// Renderizador Gemelo 1:1 (ZPL Mirror) para Impresora Térmica Industrial Honeywell PC42E-T.
//
// Formato físico idéntico: 100 mm de ancho x 70 mm de alto (800 x 560 dots @ 203 DPI / 8 dpmm).
// Dibuja con absoluta fidelidad las mismas coordenadas, tipografías y líneas que zpl_builder.dart,
// garantizando que la previsualización en la PDA coincida con la etiqueta física impresa.

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../domain/models/etiqueta_data.dart';
import '../../services/zpl_builder.dart';

class EtiquetaTermicaWidget extends StatelessWidget {
  final EtiquetaData data;

  const EtiquetaTermicaWidget({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final isMotor = data.skuQrFisico.toUpperCase().startsWith('MOT');
    final String badgeTexto = isMotor ? 'MOTOR' : 'CAJAS DE CAMBIO';

    // Canvas nativo en proporción 800 x 560 dots (100x70 mm a 203 DPI)
    return Container(
      width: 800,
      height: 560,
      color: Colors.white,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── 1. MARCO EXTERIOR Y LÍNEAS ESTRUCTURALES (^FO20,15^GB760,530,3) ──
          Positioned(
            left: 20,
            top: 15,
            width: 760,
            height: 530,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 3),
              ),
            ),
          ),

          // Línea separadora Header (^FO20,95^GB760,0,3)
          Positioned(
            left: 20,
            top: 95,
            width: 760,
            child: Container(height: 3, color: Colors.black),
          ),

          // Línea separadora Footer (^FO20,455^GB760,0,3)
          Positioned(
            left: 20,
            top: 455,
            width: 760,
            child: Container(height: 3, color: Colors.black),
          ),

          // Línea vertical divisoria entre QR y Datos técnicos (^FO360,95^GB0,360,3)
          Positioned(
            left: 360,
            top: 95,
            height: 360,
            child: Container(width: 3, color: Colors.black),
          ),

          // ── 2. HEADER: LOGO CRESAL Y BADGE DEL ACTIVO ──
          // ^FO40,25^A0N,32,32^FDCRESAL^FS
          const Positioned(
            left: 40,
            top: 22,
            child: Text(
              'CRESAL',
              style: TextStyle(
                color: Colors.black,
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                height: 1.0,
              ),
            ),
          ),

          // ^FO40,62^A0N,20,20^FDDesarme . Vehiculos . Repuestos^FS
          const Positioned(
            left: 40,
            top: 60,
            child: Text(
              'Desarme . Vehiculos . Repuestos',
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                height: 1.0,
              ),
            ),
          ),

          // Caja negra de Badge (^FO500,25^GB260,55,55 + ^FO500,40...^FD$badgeTexto) - Esquinas 100% rectas ZPL
          Positioned(
            left: 500,
            top: 25,
            width: 260,
            height: 55,
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  badgeTexto,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ),

          // ── 3. PANEL IZQUIERDO: CÓDIGO QR, SKU Y UBICACIÓN ──
          // Código QR Factor 8 centrado (^FO100,120^BQN,2,8 con nivel Q)
          Positioned(
            left: 90,
            top: 115,
            width: 200,
            height: 200,
            child: QrImageView(
              data: ZplBuilder.sanitize(data.skuQrFisico),
              version: QrVersions.auto,
              size: 200,
              padding: EdgeInsets.zero,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.Q,
            ),
          ),

          // SKU centrado (^FO35,342^A0N,26,26^FB310,1,0,C)
          Positioned(
            left: 35,
            top: 334,
            width: 310,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                ZplBuilder.sanitize(data.skuQrFisico),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  height: 1.0,
                ),
              ),
            ),
          ),

          // Caja negra de Ubicación (^FO35,384^GB310,50,50 + ^FO35,398...^FD$ubicacion) - Esquinas 100% rectas ZPL
          Positioned(
            left: 35,
            top: 380,
            width: 310,
            height: 50,
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  ZplBuilder.formatearUbicacion(data),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ),

          // ── 4. PANEL DERECHO: 7 CARACTERÍSTICAS TÉCNICAS UNIFORMES (^A0N,25,25) ──
          // Utiliza los mismos límites seguros de caracteres (maxLength) que ZplBuilder
          _buildFilaZpl(
            top: 118,
            label: 'MARCA',
            valor: data.marca,
            maxLength: 20,
          ),
          _buildFilaZpl(
            top: 164,
            label: 'MODELO',
            valor: data.modelo,
            maxLength: 20,
          ),
          _buildFilaZpl(
            top: 210,
            label: 'AÑO',
            valor: data.anio > 0 ? data.anio.toString() : 'N/A',
            maxLength: 4,
          ),
          _buildFilaZpl(
            top: 256,
            label: 'CILINDRADA',
            valor: data.cilindrada,
            maxLength: 14,
          ),
          _buildFilaZpl(
            top: 302,
            label: 'COMBUSTIBLE',
            valor: data.combustible,
            maxLength: 14,
          ),
          _buildFilaZpl(
            top: 348,
            label: 'TRANSMISION',
            valor: data.transmision,
            maxLength: 14,
          ),
          _buildFilaZpl(
            top: 394,
            label: 'TRACCION',
            valor: data.traccion,
            maxLength: 15,
          ),

          // ── 5. FOOTER: NRO MOTOR Y NRO INGRESO ──
          if (isMotor) ...[
            // Motor: NRO MOTOR a la izquierda (^FO35,485) y NRO INGRESO a la derecha (^FO430,485)
            Positioned(
              left: 35,
              top: 480,
              width: 380,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'NRO MOTOR: ${ZplBuilder.sanitize(data.numeroMotor, maxLength: 16)}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 430,
              top: 480,
              width: 340,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'NRO INGRESO: ${ZplBuilder.sanitize(data.numeroIngreso, maxLength: 14)}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ] else ...[
            // Caja de Cambios u otros activos: NRO INGRESO a lo ancho iniciando a la izquierda (^FO40,485)
            Positioned(
              left: 40,
              top: 476,
              width: 730,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'NRO INGRESO: ${ZplBuilder.sanitize(data.numeroIngreso, maxLength: 14)}',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Helper para filas técnicas derechas (idénticas a ^FO385,Y^A0N,25,25^FDLABEL: VALOR^FS) ──
  Widget _buildFilaZpl({
    required double top,
    required String label,
    required String? valor,
    int? maxLength,
  }) {
    final valorLimpio = ZplBuilder.sanitize(valor, maxLength: maxLength);
    return Positioned(
      left: 385,
      top: top,
      width: 380,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              TextSpan(
                text: valorLimpio,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
