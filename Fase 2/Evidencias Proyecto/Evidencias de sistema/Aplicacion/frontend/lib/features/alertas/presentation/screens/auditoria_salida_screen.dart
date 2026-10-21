import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/widgets/custom_error_snackbar.dart';
import '../../models/tarea_alerta.dart';
import '../../services/logistica_service.dart';
import '../widgets/resultado_salida_dialog.dart';

/// Pantalla operativa para el Bodeguero: Escaneo y Handshake de Auditoría de Salida (HU-3.6).
/// Implementa la regla 'Cero-Clics' con Flujo Guiado (1. QR Vendedor -> 2. Pieza Física),
/// validación de Doble Llave (Dual-Scan) y respuesta háptica en entornos industriales.
class AuditoriaSalidaScreen extends StatefulWidget {
  final TareaAlerta? tarea;
  final http.Client? httpClient;

  const AuditoriaSalidaScreen({super.key, this.tarea, this.httpClient});

  @override
  State<AuditoriaSalidaScreen> createState() => _AuditoriaSalidaScreenState();
}

class _AuditoriaSalidaScreenState extends State<AuditoriaSalidaScreen>
    with SingleTickerProviderStateMixin {
  String? _qrTransaccionalSalida;
  VerificarQrSalidaResponseModel? _ordenVerificada;
  final List<String> _skusEscaneados = [];
  bool _isProcessing = false;
  bool _isVerificandoOrden = false;
  EscanearSalidaResponseModel? _resultadoExitoso;

  // Controlador de entrada para captura silenciosa del escáner láser PDA
  final TextEditingController _simuladorController = TextEditingController();
  final FocusNode _simuladorFocus = FocusNode();

  // Animación del láser escáner industrial
  late AnimationController _laserAnimController;

  @override
  void initState() {
    super.initState();
    _laserAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _simuladorFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _laserAnimController.dispose();
    _simuladorController.dispose();
    _simuladorFocus.dispose();
    super.dispose();
  }

  /// Procesa cualquier código capturado por el escáner láser PDA o simulador
  Future<void> _procesarCodigoLeido(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty ||
        _isProcessing ||
        _isVerificandoOrden ||
        _resultadoExitoso != null) {
      return;
    }

    _simuladorController.clear();
    _simuladorFocus.requestFocus();

    if (code.toUpperCase().startsWith('TX-QR-')) {
      await _verificarYAsignarOrden(code);
    } else {
      _procesarSkuFisico(code.toUpperCase());
    }
  }

  /// Paso 1: Valida y carga la orden desde el código del vendedor
  Future<void> _verificarYAsignarOrden(String token) async {
    setState(() => _isVerificandoOrden = true);
    try {
      final orden = await LogisticaService.verificarQrSalida(
        qrTransaccionalSalida: token,
        client: widget.httpClient,
      );
      if (!mounted) return;

      HapticFeedback.mediumImpact();
      setState(() {
        _qrTransaccionalSalida = token;
        _ordenVerificada = orden;
        _skusEscaneados.clear();
        _isVerificandoOrden = false;
      });

      debugPrint(
        '📱 [AUDITORIA] Orden verificada: ${orden.folio} con ${orden.itemsRequeridos.length} items',
      );
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() => _isVerificandoOrden = false);

      String rawError = e.toString().replaceFirst('Exception: ', '').trim();
      String mensajeSanitizado =
          rawError.contains('404') ||
              rawError.toLowerCase().contains('no encontrado')
          ? 'El código QR escaneado no pertenece a ninguna orden activa.'
          : rawError;

      CustomErrorSnackbar.mostrar(
        context,
        mensaje: mensajeSanitizado,
        codigoError: 'ORDEN_NO_ENCONTRADA',
      );
    }
  }

  /// Total de repuestos físicos inventariados que requieren validación por QR en barrera
  int get _totalActivosRequeridos {
    if (_ordenVerificada == null) return 1;
    final activos = _ordenVerificada!.itemsRequeridos
        .where((it) => it.esInventariado)
        .toList();
    if (activos.isNotEmpty) return activos.length;
    return _ordenVerificada!.totalItemsFisicos > 0
        ? _ordenVerificada!.totalItemsFisicos
        : 1;
  }

  /// Paso 2: Valida que la pieza física pertenezca a la orden ya cargada
  void _procesarSkuFisico(String sku) {
    if (_qrTransaccionalSalida == null) {
      HapticFeedback.selectionClick();
      CustomErrorSnackbar.mostrar(
        context,
        mensaje:
            'Por favor, escanee primero el QR del Vendedor para cargar la orden.',
        codigoError: 'ORDEN_REQUERIDA',
      );
      return;
    }

    // Solo se exigen y validan repuestos inventariados (activos físicos)
    final itemsInventariados = (_ordenVerificada?.itemsRequeridos ?? [])
        .where((it) => it.esInventariado)
        .toList();

    if (itemsInventariados.isNotEmpty) {
      ItemSalidaInfoModel? itemCoincidente;
      for (final it in itemsInventariados) {
        if (it.skuQrFisico != null && it.skuQrFisico!.toUpperCase() == sku) {
          itemCoincidente = it;
          break;
        }
      }

      if (itemCoincidente == null) {
        HapticFeedback.heavyImpact();
        final primer = itemsInventariados.first;
        final detalleEsperado = primer.skuQrFisico != null
            ? '\nDebe entregar: ${primer.titulo} (${primer.skuQrFisico}) en ${primer.ubicacion}.'
            : '';
        CustomErrorSnackbar.mostrar(
          context,
          mensaje:
              'Cuidado: La pieza escaneada ($sku) no pertenece a la orden ${_ordenVerificada?.folio ?? ""}.$detalleEsperado',
          codigoError: 'PIEZA_MISMATCH',
        );
        return;
      }

      if (!itemCoincidente.qrImpreso) {
        HapticFeedback.heavyImpact();
        CustomErrorSnackbar.mostrar(
          context,
          mensaje:
              'La pieza ($sku) no registra impresión de etiqueta QR. Debe imprimir la etiqueta antes de autorizar la salida.',
          codigoError: 'QR_NO_IMPRESO',
        );
        return;
      }
    }

    if (_skusEscaneados.contains(sku)) {
      CustomErrorSnackbar.mostrar(
        context,
        mensaje: 'La pieza ya fue escaneada y registrada previamente.',
        codigoError: 'PIEZA_DUPLICADA',
      );
      return;
    }

    setState(() {
      _skusEscaneados.add(sku);
      debugPrint(
        '📦 [AUDITORIA] SKU Físico de pieza capturado: $sku (Total: ${_skusEscaneados.length})',
      );
    });

    final totalRequeridos = _totalActivosRequeridos;
    if (_skusEscaneados.length >= totalRequeridos) {
      _ejecutarDualScanMatch();
    } else {
      HapticFeedback.mediumImpact();
      final proxItem = itemsInventariados.firstWhere(
        (it) => !_skusEscaneados.contains(it.skuQrFisico?.toUpperCase()),
        orElse: () => itemsInventariados.first,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Pieza verificada (${_skusEscaneados.length}/$totalRequeridos). Escanee ahora: ${proxItem.titulo} (${proxItem.skuQrFisico ?? ""})',
          ),
          backgroundColor: AppPalette.success,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Ejecuta la llamada transaccional atómica al backend sin intervención manual
  Future<void> _ejecutarDualScanMatch() async {
    if (_isProcessing ||
        _qrTransaccionalSalida == null ||
        _skusEscaneados.isEmpty) {
      return;
    }

    setState(() => _isProcessing = true);

    try {
      debugPrint(
        '🚀 [AUDITORIA] Auto-Trigger Cero-Clics activado. Validando Dual-Scan en backend...',
      );

      final response = await LogisticaService.escanearSalida(
        qrTransaccionalSalida: _qrTransaccionalSalida!,
        skusEscaneados: _skusEscaneados,
        client: widget.httpClient,
      );

      if (!mounted) return;

      // Feedback háptico de éxito para entorno ruidoso de bodega
      HapticFeedback.heavyImpact();

      setState(() {
        _resultadoExitoso = response;
        _isProcessing = false;
      });

      // Despliegue de Diálogo Modal Pop-up centrado con temporizador de 5s
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => ResultadoSalidaDialog(
          resultado: response,
          ordenVerificada: _ordenVerificada,
          onFinalizar: () {
            Navigator.of(dialogCtx).pop();
            if (mounted) {
              Navigator.of(context).pop(true);
            }
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;

      // Feedback háptico de alerta
      HapticFeedback.mediumImpact();

      String rawError = e.toString().replaceFirst('Exception: ', '').trim();
      String mensajeSanitizado = rawError;
      String codigoError = 'BARRERA_ERROR';

      if (rawError.toLowerCase().contains('no encontrado') ||
          rawError.toLowerCase().contains('404')) {
        mensajeSanitizado =
            'El código escaneado no pertenece a ninguna orden activa.';
        codigoError = 'SCAN_NO_ENCONTRADO';
      } else if (rawError.toLowerCase().contains(
            'no pertenecen a esta orden',
          ) ||
          rawError.toLowerCase().contains('otra orden')) {
        mensajeSanitizado =
            'Cuidado, la pieza escaneada pertenece a otra orden.';
        codigoError = 'ORDEN_MISMATCH';
      }

      debugPrint('❌ [AUDITORIA] Error en barrera: $mensajeSanitizado');

      setState(() {
        _isProcessing = false;
        // Preserva _skusEscaneados para no perder el progreso del bodeguero ante errores de red o reintentos
      });

      CustomErrorSnackbar.mostrar(
        context,
        mensaje: mensajeSanitizado,
        codigoError: codigoError,
        onReintentar: () => _ejecutarDualScanMatch(),
      );
    }
  }

  void _limpiarEscaneos() {
    setState(() {
      _qrTransaccionalSalida = null;
      _ordenVerificada = null;
      _skusEscaneados.clear();
      _resultadoExitoso = null;
      _isProcessing = false;
      _isVerificandoOrden = false;
    });
    _simuladorController.clear();
    _simuladorFocus.requestFocus();
  }

  /// Abre diálogo de contingencia manual en caso de que la etiqueta esté rota o dañada
  Future<void> _abrirDialogoContingencia() async {
    final resultado = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => _DialogoContingenciaManual(
        necesitaToken: _qrTransaccionalSalida == null,
      ),
    );

    if (resultado != null && resultado.isNotEmpty && mounted) {
      await _procesarCodigoLeido(resultado);
    }
  }

  String _formatearNombreRepuesto(String titulo) {
    return titulo.replaceAll(RegExp(r'\s*\(\d{2,4}\)'), '').trim();
  }

  String _formatearUbicacion(String ubicacionRaw) {
    final u = ubicacionRaw.trim();
    if (u.isEmpty || u == 'N/A' || u == 'Venta Libre') return u;

    if (u.toLowerCase().contains('pasillo:') ||
        u.toLowerCase().contains('pallet:') ||
        u.toLowerCase().contains('galpón:') ||
        u.toLowerCase().contains('galpon:')) {
      return u;
    }

    if (u.contains(' - ')) {
      final partes = u.split(' - ');
      final pasillo = partes[0]
          .replaceFirst(RegExp(r'^pasillo:?\s*', caseSensitive: false), '')
          .trim();
      final pallet = partes
          .sublist(1)
          .join(' - ')
          .replaceFirst(RegExp(r'^pallet:?\s*', caseSensitive: false), '')
          .trim();
      return 'Pasillo: $pasillo, Pallet: $pallet';
    }

    return u;
  }

  @override
  Widget build(BuildContext context) {
    final tienePieza = _skusEscaneados.isNotEmpty;
    final tieneToken = _qrTransaccionalSalida != null;
    final totalRequeridos = _totalActivosRequeridos;
    final todosEscaneados = _skusEscaneados.length >= totalRequeridos && totalRequeridos > 0;

    Widget? customBodyPaso2;
    if (tieneToken && (_ordenVerificada?.itemsRequeridos.isNotEmpty ?? false)) {
      customBodyPaso2 = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _ordenVerificada!.itemsRequeridos.map((item) {
          if (!item.esInventariado) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8.0),
              padding: const EdgeInsets.all(10.0),
              decoration: BoxDecoration(
                color: AppPalette.secondary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(
                  color: AppPalette.secondary.withValues(alpha: 0.3),
                  width: 1.0,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatearNombreRepuesto(item.titulo),
                          style: AppTypography.small.copyWith(
                            color: AppPalette.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 3.0),
                        Row(
                          children: [
                            const Icon(
                              Icons.storefront_outlined,
                              size: 13.0,
                              color: AppPalette.secondary,
                            ),
                            const SizedBox(width: 4.0),
                            Expanded(
                              child: Text(
                                'Entrega en mesón (No requiere QR físico)',
                                style: AppTypography.small.copyWith(
                                  color: AppPalette.secondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11.0,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 3.0,
                    ),
                    decoration: BoxDecoration(
                      color: AppPalette.secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4.0),
                      border: Border.all(
                        color: AppPalette.secondary.withValues(alpha: 0.5),
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      'MISCELÁNEO',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.secondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 10.0,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final sinImprimir = !item.qrImpreso;
          final isEscaneado = item.skuQrFisico != null &&
              _skusEscaneados.contains(item.skuQrFisico!.toUpperCase());
          return Container(
            margin: const EdgeInsets.only(bottom: 8.0),
            padding: const EdgeInsets.all(10.0),
            decoration: BoxDecoration(
              color: isEscaneado
                  ? AppPalette.success.withValues(alpha: 0.12)
                  : (sinImprimir
                      ? AppPalette.error.withValues(alpha: 0.08)
                      : AppPalette.background),
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(
                color: isEscaneado
                    ? AppPalette.success
                    : (sinImprimir
                        ? AppPalette.error.withValues(alpha: 0.5)
                        : Colors.white12),
                width: isEscaneado ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatearNombreRepuesto(item.titulo),
                            style: AppTypography.small.copyWith(
                              color: AppPalette.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                          if (item.skuQrFisico != null) ...[
                            const SizedBox(height: 2.0),
                            Text(
                              'SKU: ${item.skuQrFisico}',
                              style: AppTypography.small.copyWith(
                                color: isEscaneado
                                    ? AppPalette.success
                                    : const Color(0xFF00A3FF),
                                fontWeight: FontWeight.w600,
                                fontSize: 11.0,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isEscaneado)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 3.0,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.success.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4.0),
                          border: Border.all(
                            color: AppPalette.success,
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 13.0,
                              color: AppPalette.success,
                            ),
                            const SizedBox(width: 4.0),
                            Text(
                              'VERIFICADO',
                              style: AppTypography.small.copyWith(
                                color: AppPalette.success,
                                fontWeight: FontWeight.bold,
                                fontSize: 10.0,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (sinImprimir)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6.0,
                          vertical: 2.0,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.error.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4.0),
                          border: Border.all(
                            color: AppPalette.error,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          'SIN QR',
                          style: AppTypography.small.copyWith(
                            color: AppPalette.error,
                            fontWeight: FontWeight.bold,
                            fontSize: 10.0,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6.0),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 3.0,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4.0),
                        border: Border.all(
                          color: AppPalette.primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 13.0,
                            color: AppPalette.primary,
                          ),
                          const SizedBox(width: 4.0),
                          Flexible(
                            child: Text(
                              _formatearUbicacion(item.ubicacion),
                              style: AppTypography.small.copyWith(
                                color: AppPalette.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 11.0,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (!isEscaneado && sinImprimir && item.etiquetaData != null) ...[
                  const SizedBox(height: 10.0),
                  SizedBox(
                    width: double.infinity,
                    height: 38.0,
                    child: ElevatedButton.icon(
                      key: Key('btn_imprimir_salida_${item.idDetalle}'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final resultado = await Navigator.pushNamed(
                          context,
                          '/etiqueta-preview',
                          arguments: item.etiquetaData,
                        );
                        if (!mounted) return;
                        if (resultado == true) {
                          setState(() {
                            item.qrImpreso = true;
                          });
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                '✅ Etiqueta impresa y registrada. Ahora proceda a escanear el código QR físico.',
                              ),
                              backgroundColor: AppPalette.success,
                              duration: Duration(seconds: 3),
                            ),
                          );
                        }
                      },
                      icon: const Icon(
                        Icons.print,
                        size: 16.0,
                        color: Colors.white,
                      ),
                      label: Text(
                        'IMPRIMIR ETIQUETA QR AHORA',
                        style: AppTypography.button.copyWith(
                          fontSize: 11.5,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppPalette.error,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6.0),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      );
    }

    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        title: Text(
          'AUDITORÍA DE SALIDA',
          style: AppTypography.headline.copyWith(
            color: AppPalette.textPrimary,
            fontSize: 18.0,
            letterSpacing: 1.2,
          ),
        ),
        backgroundColor: AppPalette.surface,
        iconTheme: const IconThemeData(color: AppPalette.primary),
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => _simuladorFocus.requestFocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header Informativo ─────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(14.0),
                  decoration: BoxDecoration(
                    color: AppPalette.surface,
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        color: AppPalette.secondary,
                        size: 22.0,
                      ),
                      const SizedBox(width: 10.0),
                      Expanded(
                        child: Text(
                          'Doble Llave de Salida: Escanee primero el QR del vendedor para cargar la orden y luego el QR de la pieza física.',
                          style: AppTypography.small.copyWith(
                            color: AppPalette.textPrimary,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16.0),

                // ── Tarjeta 1: Escaneo de QR del Vendedor (Paso 1) ─────────────
                _buildScanCard(
                  titulo: tieneToken
                      ? '1. Ticket del Vendedor: ${_ordenVerificada?.folio ?? _qrTransaccionalSalida}'
                      : '1. Escanee QR del Vendedor',
                  subtitulo: _isVerificandoOrden
                      ? 'Consultando orden en el sistema...'
                      : (tieneToken
                            ? 'Orden validada • $totalRequeridos repuesto(s) físico(s) a despachar'
                            : 'Apunta a la pantalla del vendedor'),
                  icono: Icons.qr_code_2_rounded,
                  isCompleted: tieneToken,
                  isActive: !tieneToken,
                  chips: const [],
                ),

                const SizedBox(height: 12.0),

                // ── Tarjeta 2: Escaneo de Pieza Física (Paso 2) ────────────────
                _buildScanCard(
                  titulo: todosEscaneados
                      ? '2. Todos los Repuestos Físicos Validados (${_skusEscaneados.length}/$totalRequeridos)'
                      : (_skusEscaneados.isNotEmpty
                            ? '2. Escaneando Repuestos Físicos (${_skusEscaneados.length}/$totalRequeridos)'
                            : '2. Escanee QR de la Pieza Física'),
                  subtitulo: !tieneToken
                      ? 'Escanee primero el QR del vendedor para cargar los datos de la orden'
                      : (todosEscaneados
                            ? 'Todos los repuestos físicos verificados correctamente'
                            : (_skusEscaneados.isNotEmpty
                                  ? 'Faltan ${totalRequeridos - _skusEscaneados.length} repuesto(s) físico(s) por escanear'
                                  : 'Apunte el escáner a cualquiera de las piezas físicas requeridas')),
                  icono: Icons.precision_manufacturing_outlined,
                  isCompleted: todosEscaneados,
                  isActive: tieneToken && !todosEscaneados,
                  chips: _skusEscaneados,
                  customBody: customBodyPaso2,
                ),

                const SizedBox(height: 20.0),

                // ── Visor de Cámara y Retícula Láser Industrial ───────────────
                _buildViewfinder(),

                const SizedBox(height: 16.0),

                // ── Feedback de Carga ─────────────────────────────────────────
                if (_isProcessing || _isVerificandoOrden) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: AppPalette.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12.0),
                      border: Border.all(color: AppPalette.primary),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20.0,
                          height: 20.0,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppPalette.primary,
                          ),
                        ),
                        const SizedBox(width: 12.0),
                        Text(
                          _isVerificandoOrden
                              ? 'Consultando orden en el sistema...'
                              : 'Verificando Handshake en Barrera...',
                          style: const TextStyle(
                            color: AppPalette.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16.0),

                // ── Input Láser Silencioso en Background ──────────────────────
                // Permite captura instantánea del lector PDA sin mostrar campo de texto llenándose
                SizedBox(
                  width: 1,
                  height: 1,
                  child: Opacity(
                    opacity: 0.0,
                    child: TextField(
                      controller: _simuladorController,
                      focusNode: _simuladorFocus,
                      autofocus: true,
                      keyboardType: TextInputType.none,
                      showCursor: false,
                      enableInteractiveSelection: false,
                      onSubmitted: (val) {
                        _procesarCodigoLeido(val);
                      },
                    ),
                  ),
                ),

                // ── Barra de Contingencia Manual y Limpieza ───────────────────
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _abrirDialogoContingencia,
                        icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                        label: const Text('Ingreso manual'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppPalette.textSecondary,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    if (tieneToken || tienePieza) ...[
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _limpiarEscaneos,
                        icon: const Icon(
                          Icons.refresh,
                          size: 18,
                          color: AppPalette.error,
                        ),
                        label: const Text(
                          'Limpiar',
                          style: TextStyle(color: AppPalette.error),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: AppPalette.error.withValues(alpha: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 20.0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tarjeta de estado de escaneo para cada una de las llaves
  Widget _buildScanCard({
    required String titulo,
    required String subtitulo,
    required IconData icono,
    required bool isCompleted,
    required bool isActive,
    List<String> chips = const [],
    Widget? customBody,
  }) {
    Color borderColor;
    Color iconColor;

    if (isCompleted) {
      borderColor = AppPalette.success;
      iconColor = AppPalette.success;
    } else if (isActive) {
      borderColor = AppPalette.primary;
      iconColor = AppPalette.primary;
    } else {
      borderColor = Colors.white10;
      iconColor = AppPalette.textSecondary;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: borderColor,
          width: isCompleted || isActive ? 1.5 : 1.0,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppPalette.primary.withValues(alpha: 0.15),
                  blurRadius: 10.0,
                  spreadRadius: 1.0,
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Icon(
              isCompleted ? Icons.check_circle : icono,
              color: iconColor,
              size: 22.0,
            ),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        titulo,
                        style: AppTypography.cardTitle.copyWith(
                          fontSize: 14.0,
                          fontWeight: FontWeight.bold,
                          color: isCompleted
                              ? AppPalette.success
                              : AppPalette.textPrimary,
                        ),
                      ),
                    ),
                    if (isCompleted)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 2.0,
                        ),
                        decoration: BoxDecoration(
                          color: AppPalette.success.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Text(
                          'LISTO',
                          style: AppTypography.small.copyWith(
                            color: AppPalette.success,
                            fontWeight: FontWeight.bold,
                            fontSize: 11.0,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4.0),
                if (customBody != null)
                  customBody
                else
                  Text(
                    subtitulo,
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textSecondary,
                      fontSize: 12.0,
                    ),
                  ),
                if (chips.isNotEmpty) ...[
                  const SizedBox(height: 8.0),
                  Wrap(
                    spacing: 6.0,
                    runSpacing: 4.0,
                    children: chips.map((chip) {
                      return Chip(
                        label: Text(
                          chip,
                          style: AppTypography.small.copyWith(
                            fontSize: 11.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        backgroundColor: AppPalette.background,
                        side: const BorderSide(color: Colors.white12),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Visor animado con retícula láser de escáner industrial
  Widget _buildViewfinder() {
    return Container(
      width: double.infinity,
      height: 180.0,
      decoration: BoxDecoration(
        color: AppPalette.background,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: AppPalette.primary.withValues(alpha: 0.3)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.0),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Rejilla de fondo industrial
            CustomPaint(
              size: const Size(double.infinity, 180.0),
              painter: _GridBackgroundPainter(),
            ),

            // Marco central de enfoque
            Container(
              width: 140.0,
              height: 140.0,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppPalette.primary.withValues(alpha: 0.6),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: const Center(
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 56.0,
                  color: Colors.white24,
                ),
              ),
            ),

            // Línea láser animada
            AnimatedBuilder(
              animation: _laserAnimController,
              builder: (context, child) {
                return Positioned(
                  top: 20.0 + (_laserAnimController.value * 140.0),
                  left: 30.0,
                  right: 30.0,
                  child: Container(
                    height: 2.0,
                    decoration: BoxDecoration(
                      color: AppPalette.primary,
                      boxShadow: [
                        BoxShadow(
                          color: AppPalette.primary.withValues(alpha: 0.8),
                          blurRadius: 8.0,
                          spreadRadius: 2.0,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // Etiqueta flotante inferior
            Positioned(
              bottom: 10.0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10.0,
                  vertical: 4.0,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Text(
                  _qrTransaccionalSalida == null
                      ? 'Apunta al Ticket del Vendedor (Paso 1)'
                      : 'Apunta al QR de la Pieza Física (Paso 2)',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondary,
                    fontSize: 11.0,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// Painter decorativo para simular retícula de escáner industrial
class _GridBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 1.0;

    const step = 20.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Diálogo de contingencia manual con ciclo de vida seguro y limpio
class _DialogoContingenciaManual extends StatefulWidget {
  final bool necesitaToken;

  const _DialogoContingenciaManual({required this.necesitaToken});

  @override
  State<_DialogoContingenciaManual> createState() =>
      _DialogoContingenciaManualState();
}

class _DialogoContingenciaManualState
    extends State<_DialogoContingenciaManual> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _enviar() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      Navigator.of(context).pop(text);
    } else {
      Navigator.of(context).pop(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: const BorderSide(color: Colors.white12),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppPalette.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.keyboard_alt_outlined,
              color: AppPalette.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Ingreso Manual',
              style: AppTypography.title.copyWith(fontSize: 17),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.necesitaToken
                ? 'Ingrese el código TX-QR del Vendedor:'
                : 'Ingrese el SKU físico del repuesto (ej: MOT-...):',
            style: AppTypography.small.copyWith(
              color: AppPalette.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            style: AppTypography.body,
            decoration: InputDecoration(
              hintText: widget.necesitaToken ? 'TX-QR-...' : 'SKU...',
              hintStyle: AppTypography.small.copyWith(
                color: AppPalette.neutral,
              ),
              filled: true,
              fillColor: AppPalette.background,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white24),
              ),
            ),
            onSubmitted: (_) => _enviar(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text(
            'Cancelar',
            style: TextStyle(color: AppPalette.textSecondary),
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppPalette.primary,
            foregroundColor: AppPalette.textPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: _enviar,
          child: const Text('Capturar'),
        ),
      ],
    );
  }
}
