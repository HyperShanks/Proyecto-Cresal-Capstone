import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../services/ventas_service.dart';
import '../../services/ordenes_sync_notifier.dart';
import 'dialogo_devolucion_dinero.dart';

/// Modal dialog interactivo para anulación de órdenes en Mesón de Ventas (SPEC-HU-TAREA-4 & SPEC-HU-TAREA-23)
class ModalAnularOrden extends StatefulWidget {
  final String idOrden;
  final String folio;
  final String? clienteNombre;
  final int? totalVenta;
  final int montoPagado;
  final VoidCallback? onOrdenAnulada;
  final http.Client? client;
  final int duracionSegundos;
  final String? motivoInicial;
  final String? observacionInicial;

  /// Catálogo tipificado de motivos de anulación (SPEC-HU-TAREA-23)
  static const List<String> motivosDisponibles = [
    'Desistimiento voluntario del cliente',
    'Error en digitación o repuesto erróneo',
    'Quiebre de stock físico o pieza defectuosa',
    'Duplicidad de orden',
    'Anulación administrativa autorizada',
  ];

  const ModalAnularOrden({
    super.key,
    required this.idOrden,
    required this.folio,
    this.clienteNombre,
    this.totalVenta,
    this.montoPagado = 0,
    this.onOrdenAnulada,
    this.client,
    this.duracionSegundos = 5,
    this.motivoInicial,
    this.observacionInicial,
  });

  /// Helper estático para abrir el diálogo fácilmente
  static Future<bool?> mostrar(
    BuildContext context, {
    required String idOrden,
    required String folio,
    String? clienteNombre,
    int? totalVenta,
    int montoPagado = 0,
    VoidCallback? onOrdenAnulada,
    http.Client? client,
    int duracionSegundos = 5,
    String? motivoInicial,
    String? observacionInicial,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ModalAnularOrden(
        idOrden: idOrden,
        folio: folio,
        clienteNombre: clienteNombre,
        totalVenta: totalVenta,
        montoPagado: montoPagado,
        onOrdenAnulada: onOrdenAnulada,
        client: client,
        duracionSegundos: duracionSegundos,
        motivoInicial: motivoInicial,
        observacionInicial: observacionInicial,
      ),
    );
  }

  @override
  State<ModalAnularOrden> createState() => _ModalAnularOrdenState();
}

class _ModalAnularOrdenState extends State<ModalAnularOrden> {
  bool _isLoading = false;
  String? _errorMessage;

  late int _segundosRestantes;
  Timer? _timer;
  bool _heLeidoConfirmacion = false;

  String? _motivoSeleccionado;
  late final TextEditingController _observacionController;

  @override
  void initState() {
    super.initState();
    _segundosRestantes = widget.duracionSegundos;
    _motivoSeleccionado = widget.motivoInicial ?? ModalAnularOrden.motivosDisponibles.first;
    _observacionController = TextEditingController(text: widget.observacionInicial ?? '');
    _observacionController.addListener(() {
      if (mounted) setState(() {});
    });

    if (_segundosRestantes > 0) {
      _iniciarTemporizador();
    }
  }

  void _iniciarTemporizador() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_segundosRestantes > 1) {
        setState(() {
          _segundosRestantes--;
        });
      } else {
        setState(() {
          _segundosRestantes = 0;
        });
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _observacionController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _ejecutarAnulacion() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      await VentasService.anularOrden(
        widget.idOrden,
        motivoAnulacion: _motivoSeleccionado,
        observacionAnulacion: _observacionController.text.trim(),
        client: widget.client,
      );

      if (!mounted) return;

      widget.onOrdenAnulada?.call();

      // Si el cliente ya había pagado o abonado dinero, lanzar el modal de devolución persistente con 5s de timeout
      // ANTES de cerrar el diálogo para mantener el contexto montado y el orden correcto del stack de navegación.
      if (widget.montoPagado > 0) {
        await DialogoDevolucionDinero.mostrar(
          context,
          folio: widget.folio,
          montoADevolver: widget.montoPagado,
          clienteNombre: widget.clienteNombre,
        );
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 20.0),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text('Orden ${widget.folio} anulada exitosamente. Stock liberado a bodega.'),
                ),
              ],
            ),
            backgroundColor: AppPalette.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      OrdenesSyncNotifier.instance.notificarCambio();

      // Cerrar modal de confirmación tras haber completado todo el flujo
      if (mounted) {
        navigator.pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool tieneDineroPagado = widget.montoPagado > 0;
    final montoFormateado = CurrencyFormatter.formatCLP(widget.montoPagado);

    final int obsLongitud = _observacionController.text.trim().length;
    final bool observacionValida = obsLongitud >= 10;
    final bool motivoValido = _motivoSeleccionado != null && _motivoSeleccionado!.isNotEmpty;
    final bool tiempoCumplido = _segundosRestantes == 0;
    final bool puedeConfirmar = !_isLoading &&
        tiempoCumplido &&
        _heLeidoConfirmacion &&
        motivoValido &&
        observacionValida;

    return AlertDialog(
      backgroundColor: AppPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(
          color: tieneDineroPagado
              ? AppPalette.error.withValues(alpha: 0.6)
              : Colors.white12,
          width: 1.2,
        ),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppPalette.error.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppPalette.error,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tieneDineroPagado
                      ? '⚠️ PELIGRO: CLIENTE YA PAGÓ'
                      : '¿Deshacer esta Orden?',
                  style: AppTypography.title.copyWith(
                    fontSize: 16,
                    color: tieneDineroPagado
                        ? AppPalette.error
                        : AppPalette.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Folio: ${widget.folio}',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Alerta de Peligro si ya se registró pago o abono
            if (tieneDineroPagado) ...[
              Container(
                key: const Key('alerta_peligro_cliente_pago'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppPalette.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppPalette.error.withValues(alpha: 0.5),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.report_problem_rounded,
                          color: AppPalette.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'EL CLIENTE YA TIENE DINERO PAGADO',
                            style: AppTypography.small.copyWith(
                              color: AppPalette.error,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textPrimary,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                        children: [
                          const TextSpan(text: 'El cliente registra un pago/abono de '),
                          TextSpan(
                            text: montoFormateado,
                            style: const TextStyle(
                              color: AppPalette.error,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                            ),
                          ),
                          const TextSpan(
                            text: '. Si confirmas la anulación, será ',
                          ),
                          const TextSpan(
                            text: 'OBLIGATORIO DEVOLVERLE ESTE DINERO ',
                            style: TextStyle(
                              color: AppPalette.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const TextSpan(
                            text: 'en Caja o Mesón de inmediato. ¿Estás seguro que quieres anular?',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              // Advertencia preventiva para órdenes sin pago
              Container(
                key: const Key('alerta_advertencia_anular_sin_pago'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFF59E0B),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'ADVERTENCIA: ANULACIÓN IRREVERSIBLE',
                            style: AppTypography.small.copyWith(
                              color: const Color(0xFFF59E0B),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Esta acción cancelará la orden de inmediato. Todo el stock reservado se liberará al catálogo general y quedará registrada la baja en auditoría para Gerencia.',
                      style: AppTypography.small.copyWith(
                        color: const Color(0xFFFDE68A),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (widget.clienteNombre != null &&
                widget.clienteNombre!.trim().isNotEmpty) ...[
              Text(
                'Cliente: ${widget.clienteNombre}',
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
            ],

            // 1. Selector de Motivo Tipificado (Auditoría Gerencia)
            Text(
              'Motivo de Anulación *',
              style: AppTypography.small.copyWith(
                fontWeight: FontWeight.bold,
                color: AppPalette.textPrimary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              key: const Key('select_motivo_anulacion'),
              initialValue: _motivoSeleccionado,
              dropdownColor: AppPalette.surface,
              isExpanded: true,
              style: AppTypography.body.copyWith(fontSize: 13, color: AppPalette.textPrimary),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: AppPalette.background,
                hintText: 'Seleccione un motivo tipificado...',
                hintStyle: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
                ),
              ),
              selectedItemBuilder: (BuildContext context) {
                return ModalAnularOrden.motivosDisponibles.map<Widget>((String item) {
                  return Text(
                    item,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  );
                }).toList();
              },
              items: ModalAnularOrden.motivosDisponibles.map((motivo) {
                return DropdownMenuItem<String>(
                  value: motivo,
                  child: Text(
                    motivo,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                );
              }).toList(),
              onChanged: _isLoading
                  ? null
                  : (val) {
                      setState(() {
                        _motivoSeleccionado = val;
                      });
                    },
            ),
            const SizedBox(height: 12),

            // 2. Justificación / Observación Detallada (Poka-Yoke >= 10 chars)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Justificación de Auditoría *',
                    style: AppTypography.small.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppPalette.textPrimary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$obsLongitud / 10 mín.',
                  key: const Key('contador_caracteres_anulacion'),
                  style: AppTypography.small.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: observacionValida ? AppPalette.success : (obsLongitud > 0 ? AppPalette.warning : AppPalette.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              key: const Key('input_observacion_anulacion'),
              controller: _observacionController,
              enabled: !_isLoading,
              maxLines: 3,
              minLines: 2,
              style: AppTypography.body.copyWith(fontSize: 12.5, color: AppPalette.textPrimary),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: AppPalette.background,
                hintText: 'Detalle el motivo exacto de la cancelación para la bitácora de auditoría y gerencia...',
                hintStyle: AppTypography.small.copyWith(color: AppPalette.textSecondary, fontSize: 11.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: obsLongitud > 0 && !observacionValida ? AppPalette.error : Colors.white24,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: obsLongitud > 0 && !observacionValida ? AppPalette.error : Colors.white24,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: observacionValida ? AppPalette.success : AppPalette.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            if (obsLongitud > 0 && !observacionValida) ...[
              const SizedBox(height: 4),
              Text(
                'Faltan ${10 - obsLongitud} caracteres mínimos explicativos.',
                style: AppTypography.small.copyWith(
                  color: AppPalette.error,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 12),

            // Casilla de verificación obligatoria (He leído...)
            InkWell(
              key: const Key('check_confirmar_anulacion_tap'),
              onTap: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _heLeidoConfirmacion = !_heLeidoConfirmacion;
                      });
                    },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppPalette.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _heLeidoConfirmacion
                        ? (tieneDineroPagado ? AppPalette.warning : AppPalette.error)
                        : Colors.white24,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        key: const Key('check_confirmar_anulacion'),
                        value: _heLeidoConfirmacion,
                        activeColor: tieneDineroPagado
                            ? AppPalette.warning
                            : AppPalette.error,
                        checkColor: Colors.black,
                        side: const BorderSide(color: Colors.white54, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        onChanged: _isLoading
                            ? null
                            : (val) {
                                setState(() {
                                  _heLeidoConfirmacion = val ?? false;
                                });
                              },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tieneDineroPagado
                            ? 'He leído y comprendo que se anulará la orden y es obligatorio devolver el dinero al cliente.'
                            : 'He leído y comprendo las consecuencias de la anulación irreversible de esta orden.',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppPalette.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppPalette.error,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppPalette.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        // Botones en columna con ancho completo (Extend) para evitar overflow de píxeles
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(
              builder: (context) {
                String textoBoton;
                if (_isLoading) {
                  textoBoton = 'Anulando...';
                } else if (!tiempoCumplido) {
                  textoBoton = 'Confirmar Anulación (${_segundosRestantes}s)';
                } else {
                  textoBoton = 'Confirmar Anulación';
                }

                return SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    key: const Key('btn_confirmar_anulacion_orden'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.error,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white12,
                      disabledForegroundColor: Colors.white38,
                      elevation: puedeConfirmar ? 2 : 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : (!tiempoCumplido
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppPalette.error,
                                ),
                              )
                            : const Icon(Icons.delete_forever, size: 18)),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        textoBoton,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    onPressed: puedeConfirmar ? _ejecutarAnulacion : null,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.textSecondary,
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
                onPressed: _isLoading
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Volver'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}


