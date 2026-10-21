import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../services/ordenes_service.dart';

/// Diálogo interactivo para que el vendedor asigne un activo físico (Disponible o Paletizado)
/// a una Venta en Verde pagada que ha llegado a bodega.
///
/// Optimizado para el Vendedor:
/// • Detección automática de categoría (Motor vs Caja de Cambios) sin selectores manuales redundantes.
/// • Ficha contextual superior destacando la marca, modelo, año y especificaciones solicitadas.
/// • Comparativa visual lado a lado (Solicitado vs Donante) con alertas preventivas no bloqueantes.
/// • Cero bloqueos punitivos: el vendedor valida con criterio profesional y el botón permanece habilitado.
class AsignarActivoVendedorDialog extends StatefulWidget {
  final OrdenHistorialModel orden;
  final VoidCallback onAsignadoExitoso;
  final dynamic httpClient;

  const AsignarActivoVendedorDialog({
    super.key,
    required this.orden,
    required this.onAsignadoExitoso,
    this.httpClient,
  });

  static Future<void> mostrar(
    BuildContext context, {
    required OrdenHistorialModel orden,
    required VoidCallback onAsignadoExitoso,
    dynamic httpClient,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AsignarActivoVendedorDialog(
        orden: orden,
        onAsignadoExitoso: onAsignadoExitoso,
        httpClient: httpClient,
      ),
    );
  }

  @override
  State<AsignarActivoVendedorDialog> createState() =>
      _AsignarActivoVendedorDialogState();
}

class _AsignarActivoVendedorDialogState
    extends State<AsignarActivoVendedorDialog> {
  final TextEditingController _skuController = TextEditingController();
  late final bool _esCaja;
  late final String _prefijoCategoria;
  late final String _nombreCategoria;

  bool _isValidando = false;
  bool _isAsignando = false;

  Map<String, dynamic>? _resultadoValidacion;
  String? _errorValidacion;

  @override
  void initState() {
    super.initState();
    final detalleBo = _obtenerDetalleBackorder();
    _esCaja = (detalleBo.idCategoria == 2) ||
        (detalleBo.nombreCategoria?.toLowerCase().contains('caja') ?? false) ||
        (detalleBo.titulo.toLowerCase().contains('caja'));
    _prefijoCategoria = _esCaja ? 'CAJ-' : 'MOT-';
    _nombreCategoria = _esCaja ? 'Caja de Cambios' : 'Motor';

    debugPrint(
      '📦 [ASIGNAR-BACKORDER] Modal abierto para orden ${widget.orden.folioDisplay}. '
      'Categoría detectada: $_nombreCategoria (Prefijo: $_prefijoCategoria)',
    );
  }

  DetalleOrdenItemModel _obtenerDetalleBackorder() {
    return widget.orden.detalles.firstWhere(
      (d) => !d.esInventariado,
      orElse: () => widget.orden.detalles.first,
    );
  }

  String _obtenerSkuCompleto() {
    String texto = _skuController.text.trim().toUpperCase();
    if (texto.isEmpty) return '';
    if (texto.startsWith('MOT-') || texto.startsWith('CAJ-')) {
      return texto;
    }
    return '$_prefijoCategoria$texto';
  }

  @override
  void dispose() {
    _skuController.dispose();
    super.dispose();
  }

  Future<void> _validarSku() async {
    final sku = _obtenerSkuCompleto();
    if (sku.isEmpty) return;

    debugPrint(
      '🔍 [ASIGNAR-BACKORDER] Validando para orden ${widget.orden.folioDisplay} | '
      'Input: "${_skuController.text.trim()}" -> SKU enviado: "$sku"',
    );

    setState(() {
      _isValidando = true;
      _errorValidacion = null;
      _resultadoValidacion = null;
    });

    try {
      final res = await OrdenesService.validarActivoBackorder(
        widget.orden.idOrden,
        sku,
        client: widget.httpClient,
      );
      if (!mounted) return;

      final bool coincide = res['coincide'] == true;
      final List<dynamic> discrepancias =
          res['discrepancias'] as List<dynamic>? ?? [];

      debugPrint(
        '📊 [ASIGNAR-BACKORDER] Validación exitosa para $sku: '
        'Coincide=$coincide, Discrepancias=${discrepancias.length}',
      );

      setState(() {
        _resultadoValidacion = res;
        _isValidando = false;
      });
    } catch (e) {
      if (!mounted) return;
      final rawError = e.toString().replaceAll('Exception: ', '').trim();
      debugPrint('⚠️ [ASIGNAR-BACKORDER] Error al validar $sku: $rawError');
      setState(() {
        _errorValidacion = rawError;
        _isValidando = false;
      });
    }
  }

  Future<void> _asignarActivo() async {
    final sku = _obtenerSkuCompleto();
    if (sku.isEmpty) return;

    final bool coincide = _resultadoValidacion?['coincide'] == true;
    final bool forzar = !coincide;

    debugPrint(
      '🚀 [ASIGNAR-BACKORDER] Ejecutando asignación de $sku a orden ${widget.orden.folioDisplay} '
      '(Forzar compatibilidad por criterio comercial: $forzar)...',
    );

    setState(() {
      _isAsignando = true;
    });

    try {
      final res = await OrdenesService.asignarActivoBackorder(
        widget.orden.idOrden,
        sku,
        forzar: forzar,
        client: widget.httpClient,
      );

      if (!mounted) return;
      debugPrint(
        '✅ [ASIGNAR-BACKORDER] Asignación completada exitosamente. '
        'QR emitido: ${res["qr_transaccional_salida"]}',
      );

      Navigator.of(context).pop();
      widget.onAsignadoExitoso();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppPalette.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '¡Activo ${res["sku_asignado"] ?? sku} asignado exitosamente! '
                  'QR de salida generado. La orden ya está lista para entrega en Bodega.',
                  style: AppTypography.body.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAsignando = false;
      });
      final rawError = e.toString().replaceAll("Exception: ", "").trim();
      debugPrint('❌ [ASIGNAR-BACKORDER] Fallo en asignación de $sku: $rawError');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Text(
            'Error al asignar activo: $rawError',
            style: AppTypography.body.copyWith(color: Colors.white),
          ),
        ),
      );
    }
  }

  /// Extrae datos limpios para la ficha solicitada usando datos del backend o fallback inteligente
  Map<String, String> _extraerDatosSolicitados(DetalleOrdenItemModel detalleBo) {
    final Map<String, dynamic>? solicitadoDetalle =
        _resultadoValidacion?['solicitado_detalle'] as Map<String, dynamic>?;

    if (solicitadoDetalle != null) {
      return {
        'categoria': solicitadoDetalle['categoria']?.toString() ?? _nombreCategoria,
        'marca': solicitadoDetalle['marca']?.toString() ?? 'N/A',
        'modelo': solicitadoDetalle['modelo']?.toString() ?? 'N/A',
        'anio': solicitadoDetalle['anio']?.toString() ?? 'N/A',
        'cilindrada': solicitadoDetalle['cilindrada']?.toString() ?? '',
        'combustible': solicitadoDetalle['combustible']?.toString() ?? '',
        'transmision': solicitadoDetalle['transmision']?.toString() ?? '',
        'notas': solicitadoDetalle['notas']?.toString() ?? (detalleBo.notasPreparacion ?? ''),
      };
    }

    // Fallback inicial a partir del título concatenado de la orden
    String tituloLimpio = detalleBo.titulo
        .replaceAll('[VENTA EN VERDE]', '')
        .replaceAll('[RESERVA EN VERDE]', '')
        .trim();
    if (tituloLimpio.toLowerCase().startsWith('motor -')) {
      tituloLimpio = tituloLimpio.substring(7).trim();
    } else if (tituloLimpio.toLowerCase().startsWith('motor:')) {
      tituloLimpio = tituloLimpio.substring(6).trim();
    } else if (tituloLimpio.toLowerCase().startsWith('caja -') ||
        tituloLimpio.toLowerCase().startsWith('caja:')) {
      tituloLimpio = tituloLimpio.substring(6).trim();
    }

    // Buscar año entre paréntesis ej: (2018)
    String anio = 'N/A';
    final matchAnio = RegExp(r'\((\d{4})\)').firstMatch(tituloLimpio);
    if (matchAnio != null) {
      anio = matchAnio.group(1) ?? 'N/A';
      tituloLimpio = tituloLimpio.replaceAll(matchAnio.group(0)!, '').trim();
    }

    final partes = tituloLimpio.split(RegExp(r'\s+'));
    String marca = partes.isNotEmpty ? partes[0] : 'N/A';
    String modelo = partes.length > 1 ? partes.sublist(1).join(' ') : 'N/A';

    return {
      'categoria': _nombreCategoria,
      'marca': marca,
      'modelo': modelo,
      'anio': anio,
      'cilindrada': '',
      'combustible': '',
      'transmision': '',
      'notas': detalleBo.notasPreparacion ?? '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final detalleBo = _obtenerDetalleBackorder();
    final datosSolicitados = _extraerDatosSolicitados(detalleBo);

    final bool coincide = _resultadoValidacion?['coincide'] == true;
    final List<dynamic> discrepancias =
        _resultadoValidacion?['discrepancias'] as List<dynamic>? ?? [];
    final Map<String, dynamic>? detalleActivo =
        _resultadoValidacion?['activo_detalle'] as Map<String, dynamic>?;

    // El botón se habilita en cuanto se encuentra un activo válido,
    // dejando la decisión técnica al criterio del vendedor
    final bool puedeConfirmar = detalleActivo != null &&
        !_isValidando &&
        !_isAsignando &&
        _skuController.text.trim().isNotEmpty;

    return Dialog(
      backgroundColor: AppPalette.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white12),
      ),
      elevation: 16,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Encabezado Principal ────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppPalette.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            _esCaja
                                ? Icons.settings_input_component_rounded
                                : Icons.precision_manufacturing_rounded,
                            size: 26,
                            color: AppPalette.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Asignar $_nombreCategoria a Orden',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.headline.copyWith(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: AppPalette.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Orden ${widget.orden.folioDisplay} • Venta en Verde Pagada',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.small.copyWith(
                                  color: AppPalette.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isAsignando ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppPalette.textSecondary),
                    tooltip: 'Cerrar',
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 16),

              // ── Ficha Contextual Superior (Lo Solicitado por el Cliente) ──
              _buildFichaContextualSuperior(datosSolicitados),

              const SizedBox(height: 20),

              // ── Campo de Entrada por Folio de Ingreso ────────────────
              _buildInputFolioIngreso(),

              // ── Error Bloqueante Real (404 no existe / 409 vendido) ──
              if (_errorValidacion != null) ...[
                const SizedBox(height: 14),
                _buildErrorAlerta(_errorValidacion!),
              ],

              // ── Comparativa Visual Lado a Lado ──────────────────────
              if (_resultadoValidacion != null && detalleActivo != null) ...[
                const SizedBox(height: 16),
                _buildComparativaVisual(
                  datosSolicitados: datosSolicitados,
                  detalleActivo: detalleActivo,
                  coincide: coincide,
                  discrepancias: discrepancias,
                ),
              ],

              const SizedBox(height: 24),

              // ── Botones de Acción ───────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppPalette.textSecondary,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: _isAsignando ? null : () => Navigator.of(context).pop(),
                      child: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Cancelar',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      key: const Key('btn_confirmar_asignacion_backorder'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppPalette.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white12,
                        disabledForegroundColor: Colors.white38,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                      icon: _isAsignando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.check_circle_rounded, size: 18),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _resultadoValidacion != null
                              ? 'Confirmar Asignación y Generar QR'
                              : 'Validar e Ingresar',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                      onPressed: puedeConfirmar ? _asignarActivo : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Ficha contextual en la parte superior que exhibe lo solicitado por el cliente
  Widget _buildFichaContextualSuperior(Map<String, String> datos) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppPalette.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _esCaja ? Icons.settings : Icons.build_circle,
                      size: 13,
                      color: AppPalette.primary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _nombreCategoria.toUpperCase(),
                      style: AppTypography.small.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppPalette.secondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'SOLICITADO POR EL CLIENTE',
                  style: AppTypography.small.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.secondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${datos['marca']} ${datos['modelo']}',
                style: AppTypography.title.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppPalette.textPrimary,
                ),
              ),
              if (datos['anio'] != 'N/A')
                Text(
                  '(${datos['anio']})',
                  style: AppTypography.title.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.person_outline, size: 15, color: AppPalette.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${widget.orden.cliente?.nombreCompleto ?? "Cliente General"} • RUT: ${widget.orden.cliente?.rutCliente ?? "N/A"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (datos['notas'] != null && datos['notas']!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.notes_rounded, size: 15, color: AppPalette.secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    datos['notas']!,
                    style: AppTypography.small.copyWith(
                      color: AppPalette.secondary,
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Campo de entrada de número de ingreso con prefijo automático bloqueado
  Widget _buildInputFolioIngreso() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Número de Ingreso del Vehículo Donante',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppPalette.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Filtro: $_prefijoCategoria',
                style: AppTypography.small.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppPalette.primary,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Prefijo Automático No Editable
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppPalette.background,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                _prefijoCategoria,
                style: const TextStyle(
                  color: AppPalette.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Expanded(
              child: TextField(
                key: const Key('input_numero_ingreso_backorder'),
                controller: _skuController,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textPrimary,
                  letterSpacing: 0.5,
                ),
                textCapitalization: TextCapitalization.characters,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  hintText: 'Número de ingreso (ej: 1000)',
                  hintStyle: AppTypography.body.copyWith(
                    color: AppPalette.textSecondary.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: AppPalette.background,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                    borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
                  ),
                ),
                onSubmitted: (_) => _validarSku(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                key: const Key('btn_validar_ingreso_backorder'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                icon: _isValidando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.search, size: 18),
                label: const Text(
                  'Validar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: _isValidando ? null : _validarSku,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Alerta de error real (ej: 404 no existe / 409 vendido)
  Widget _buildErrorAlerta(String mensaje) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.errorBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.errorBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppPalette.errorText, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No se pudo encontrar el repuesto',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.errorText,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  mensaje,
                  style: AppTypography.small.copyWith(
                    color: AppPalette.errorText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Comparativa visual lado a lado con advertencias preventivas no bloqueantes
  Widget _buildComparativaVisual({
    required Map<String, String> datosSolicitados,
    required Map<String, dynamic> detalleActivo,
    required bool coincide,
    required List<dynamic> discrepancias,
  }) {
    final marcaDonante = detalleActivo['marca']?.toString() ?? 'N/A';
    final modeloDonante = detalleActivo['modelo']?.toString() ?? 'N/A';
    final anioDonante = detalleActivo['anio']?.toString() ?? 'N/A';
    final cilindradaDonante = detalleActivo['cilindrada']?.toString() ?? '';
    final transmisionDonante = detalleActivo['transmision']?.toString() ?? '';
    final numMotorDonante = detalleActivo['numero_motor']?.toString() ?? '';
    final estadoDonante = detalleActivo['estado_conservacion']?.toString() ?? 'Disponible';
    final ubicacionDonante = detalleActivo['ubicacion']?.toString() ?? 'En bodega';

    return Container(
      decoration: BoxDecoration(
        color: AppPalette.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: coincide
              ? AppPalette.success.withValues(alpha: 0.5)
              : AppPalette.warning.withValues(alpha: 0.6),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner de Estado Informativo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: coincide ? AppPalette.successBg : AppPalette.warningBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(
                bottom: BorderSide(
                  color: coincide ? AppPalette.successBorder : AppPalette.warningBorder,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  coincide ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                  color: coincide ? AppPalette.successText : AppPalette.warningText,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    coincide
                        ? 'Compatibilidad Exacta: Todos los datos coinciden con la orden solicitada.'
                        : 'Aviso de Compatibilidad: Se detectaron diferencias técnicas. Revisa la comparativa a continuación y confirma si la pieza física es compatible.',
                    style: AppTypography.small.copyWith(
                      color: coincide ? AppPalette.successText : AppPalette.warningText,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Resumen de discrepancias si existen
          if (!coincide && discrepancias.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: discrepancias.map((d) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '• ',
                          style: TextStyle(
                            color: AppPalette.warning,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            d.toString(),
                            style: AppTypography.small.copyWith(
                              color: AppPalette.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Tabla Comparativa Lado a Lado
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              children: [
                // Header de Columnas
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppPalette.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'ATRIBUTO',
                          style: AppTypography.small.copyWith(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          'SOLICITADO',
                          style: AppTypography.small.copyWith(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 5,
                        child: Text(
                          'VEHÍCULO DONANTE (${detalleActivo["sku"] ?? ""})',
                          style: AppTypography.small.copyWith(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.primary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),

                // Filas de Comparación
                _buildFilaComparativa(
                  label: 'Categoría',
                  solicitado: _nombreCategoria,
                  donante: detalleActivo['categoria']?.toString() ?? _nombreCategoria,
                ),
                _buildFilaComparativa(
                  label: 'Marca',
                  solicitado: datosSolicitados['marca'] ?? 'N/A',
                  donante: marcaDonante,
                ),
                _buildFilaComparativa(
                  label: 'Modelo',
                  solicitado: datosSolicitados['modelo'] ?? 'N/A',
                  donante: modeloDonante,
                ),
                _buildFilaComparativa(
                  label: 'Año',
                  solicitado: datosSolicitados['anio'] ?? 'N/A',
                  donante: anioDonante,
                ),
                if (cilindradaDonante.isNotEmpty || datosSolicitados['cilindrada']!.isNotEmpty)
                  _buildFilaComparativa(
                    label: 'Cilindrada',
                    solicitado: datosSolicitados['cilindrada']!.isNotEmpty
                        ? datosSolicitados['cilindrada']!
                        : 'No especificada',
                    donante: cilindradaDonante.isNotEmpty ? cilindradaDonante : 'N/A',
                  ),
                if (transmisionDonante.isNotEmpty || datosSolicitados['transmision']!.isNotEmpty)
                  _buildFilaComparativa(
                    label: 'Transmisión',
                    solicitado: datosSolicitados['transmision']!.isNotEmpty
                        ? datosSolicitados['transmision']!
                        : 'No especificada',
                    donante: transmisionDonante.isNotEmpty ? transmisionDonante : 'N/A',
                  ),
                if (numMotorDonante.isNotEmpty && numMotorDonante != 'S/A')
                  _buildFilaComparativa(
                    label: 'N° Motor Donante',
                    solicitado: '—',
                    donante: numMotorDonante,
                  ),
                _buildFilaComparativa(
                  label: 'Estado y Ubicación',
                  solicitado: '—',
                  donante: '$estadoDonante • $ubicacionDonante',
                  esInformativo: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Fila comparativa individual que detecta si los valores difieren
  Widget _buildFilaComparativa({
    required String label,
    required String solicitado,
    required String donante,
    bool esInformativo = false,
  }) {
    final bool coincideTexto = esInformativo ||
        (solicitado.trim().toLowerCase() == donante.trim().toLowerCase()) ||
        solicitado == '—';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: !coincideTexto ? AppPalette.warning.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: AppTypography.small.copyWith(
                color: AppPalette.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              solicitado,
              style: AppTypography.small.copyWith(
                color: AppPalette.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Row(
              children: [
                if (!esInformativo) ...[
                  Icon(
                    coincideTexto ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                    size: 14,
                    color: coincideTexto ? AppPalette.success : AppPalette.warning,
                  ),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    donante,
                    style: AppTypography.small.copyWith(
                      color: !coincideTexto ? AppPalette.warning : AppPalette.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
