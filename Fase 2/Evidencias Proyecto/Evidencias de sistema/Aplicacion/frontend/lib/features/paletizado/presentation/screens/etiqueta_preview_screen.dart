// lib/features/paletizado/presentation/screens/etiqueta_preview_screen.dart

import 'package:flutter/material.dart';
import '../../domain/exceptions/printer_exceptions.dart';
import '../../domain/models/etiqueta_data.dart';
import '../widgets/etiqueta_termica_widget.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../widgets/dialogo_falla_impresora.dart';
import '../../services/print_service.dart';
import '../../services/paletizado_service.dart';

class EtiquetaPreviewScreen extends StatefulWidget {
  const EtiquetaPreviewScreen({super.key});

  @override
  State<EtiquetaPreviewScreen> createState() => _EtiquetaPreviewScreenState();
}

class _EtiquetaPreviewScreenState extends State<EtiquetaPreviewScreen> {
  bool _isImprimiendo = false;
  final PaletizadoService _paletizadoService = PaletizadoService();

  Future<void> _iniciarImpresion(EtiquetaData data) async {
    debugPrint(
      '📌 [PREVIEW_SCREEN] 🔘 Botón de impresión presionado para SKU: ${data.skuQrFisico}',
    );

    bool exitoImpresion = false;

    while (!exitoImpresion && mounted) {
      setState(() => _isImprimiendo = true);
      try {
        exitoImpresion = await PrintService.imprimirEtiqueta(data);
      } on PrinterException catch (e) {
        debugPrint(
          '📌 [PREVIEW_SCREEN] ❌ Error de dominio de impresora: ${e.mensaje}',
        );
        if (!mounted) break;
        setState(() => _isImprimiendo = false);

        // Mostrar diálogo modal interactivo con instrucciones de resolución física
        final reintentar = await DialogoFallaImpresora.mostrar(context, e);
        if (!reintentar || !mounted) {
          return;
        }
        // Operador pulsó "REINTENTAR": el bucle while vuelve a intentar imprimir
        continue;
      } catch (e) {
        debugPrint('📌 [PREVIEW_SCREEN] ❌ Excepción no controlada: $e');
        if (!mounted) break;
        setState(() => _isImprimiendo = false);

        final reintentar = await DialogoFallaImpresora.mostrar(
          context,
          PrinterCommunicationException(
            'Error inesperado de comunicación con la impresora térmica.',
            e,
          ),
        );
        if (!reintentar || !mounted) {
          return;
        }
        continue;
      } finally {
        if (mounted && !exitoImpresion) {
          setState(() => _isImprimiendo = false);
        }
      }
    }

    if (!mounted || !exitoImpresion) return;

    // Fase 4: Confirmar en backend (PATCH qr_impreso = true)
    debugPrint(
      '📌 [PREVIEW_SCREEN] 📡 Impresión física exitosa. Confirmando en backend...',
    );
    final exitoPatch = await _paletizadoService.confirmarQrImpreso(
      data.idActivo,
    );

    if (!mounted) return;

    if (exitoPatch) {
      debugPrint(
        '📌 [PREVIEW_SCREEN] ✅ Ciclo completo: etiqueta impresa y registrada en BD.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Etiqueta impresa y registrada. SKU: ${data.skuQrFisico}',
          ),
          backgroundColor: AppPalette.success,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      debugPrint(
        '📌 [PREVIEW_SCREEN] ⚠️ Etiqueta impresa pero no se pudo confirmar en backend.',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Etiqueta impresa físicamente. No se pudo confirmar en el sistema (sin conexión).',
          ),
          backgroundColor: AppPalette.secondary,
          duration: Duration(seconds: 4),
        ),
      );
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final rawArgs = ModalRoute.of(context)?.settings.arguments;
    EtiquetaData? data;
    if (rawArgs is EtiquetaData) {
      data = rawArgs;
    } else if (rawArgs is Map) {
      data = EtiquetaData.fromJson(Map<String, dynamic>.from(rawArgs));
    }

    if (data == null) {
      debugPrint(
        '📌 [PREVIEW_SCREEN] ⚠️ Pantalla iniciada sin EtiquetaData (Arguments Null)',
      );
      return Scaffold(
        backgroundColor: AppPalette.background,
        appBar: AppBar(title: const Text('Error')),
        body: const Center(
          child: Text(
            'Error: No se recibieron datos.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final EtiquetaData etiqueta = data;

    debugPrint(
      '📌 [PREVIEW_SCREEN] 📄 Renderizando vista previa para Folio: ${etiqueta.numeroIngreso}',
    );

    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        backgroundColor: AppPalette.background,
        foregroundColor: AppPalette.textPrimary,
        iconTheme: const IconThemeData(color: AppPalette.textPrimary),
        elevation: 0,
        title: const Text('Vista Previa', style: AppTypography.title),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          // ── Contenedor responsivo para visualizar la etiqueta ──
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: EtiquetaTermicaWidget(data: etiqueta),
                ),
              ),
            ),
          ),

          // ── Botón de Impresión ──
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isImprimiendo
                    ? null
                    : () => _iniciarImpresion(etiqueta),
                icon: _isImprimiendo
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.print, color: Colors.white),
                label: Text(
                  _isImprimiendo ? 'ENVIANDO...' : 'CONFIRMAR E IMPRIMIR',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
