import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../services/inventario_service.dart';

/// Diálogo de seguridad anti-equivocación para despaletizar un activo y devolverlo
/// al estado "En Desarme" (SPEC-HU-TAREA-23).
///
/// Implementa un temporizador regresivo de 5 segundos, selección obligatoria de motivo
/// con botones táctiles ergonómicos para operarios con guantes en PDA, y aduana Poka-Yoke
/// de justificación mínima de 10 caracteres antes de permitir la confirmación.
class DialogoDespaletizar extends StatefulWidget {
  final String idActivo;
  final String sku;
  final String categoria;
  final String? numeroIngreso;
  final String? ubicacionActual;
  final http.Client? client;
  final int duracionSegundos;
  final String? motivoInicial;
  final String? observacionInicial;

  /// Catálogo táctil ergonómico de motivos para bodega / patio (SPEC-HU-TAREA-23)
  static const List<Map<String, String>> motivosDisponibles = [
    {
      'id': 'Preparación Venta / Despacho Inmediato',
      'label': 'Preparación Venta / Despacho Inmediato',
      'icon': '🏷️',
    },
    {
      'id': 'Merma / Daño Físico Detectado',
      'label': 'Merma / Daño Físico Detectado',
      'icon': '⚠️',
    },
    {
      'id': 'Garantía o Devolución a Revisión Técnica',
      'label': 'Garantía o Devolución a Revisión Técnica',
      'icon': '🔄',
    },
    {
      'id': 'Reubicación a Otro Pasillo o Nivel',
      'label': 'Reubicación a Otro Pasillo o Nivel',
      'icon': '📦',
    },
    {
      'id': 'Otro Motivo Operativo',
      'label': 'Otro Motivo Operativo',
      'icon': '❓',
    },
  ];

  const DialogoDespaletizar({
    super.key,
    required this.idActivo,
    required this.sku,
    required this.categoria,
    this.numeroIngreso,
    this.ubicacionActual,
    this.client,
    this.duracionSegundos = 5,
    this.motivoInicial,
    this.observacionInicial,
  });

  /// Método de utilidad para mostrar el diálogo.
  /// Retorna `true` si el activo fue despaletizado exitosamente.
  static Future<bool?> mostrar(
    BuildContext context, {
    required String idActivo,
    required String sku,
    required String categoria,
    String? numeroIngreso,
    String? ubicacionActual,
    http.Client? client,
    int duracionSegundos = 5,
    String? motivoInicial,
    String? observacionInicial,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DialogoDespaletizar(
        idActivo: idActivo,
        sku: sku,
        categoria: categoria,
        numeroIngreso: numeroIngreso,
        ubicacionActual: ubicacionActual,
        client: client,
        duracionSegundos: duracionSegundos,
        motivoInicial: motivoInicial,
        observacionInicial: observacionInicial,
      ),
    );
  }

  @override
  State<DialogoDespaletizar> createState() => _DialogoDespaletizarState();
}

class _DialogoDespaletizarState extends State<DialogoDespaletizar> {
  late int _segundosRestantes;
  Timer? _timer;
  bool _isLoading = false;

  String? _motivoSeleccionado;
  late final TextEditingController _observacionController;

  @override
  void initState() {
    super.initState();
    _segundosRestantes = widget.duracionSegundos;
    _motivoSeleccionado = widget.motivoInicial;
    _observacionController = TextEditingController(text: widget.observacionInicial ?? '');
    _observacionController.addListener(() {
      if (mounted) setState(() {});
    });

    if (_segundosRestantes > 0) {
      _iniciarCuentaRegresiva();
    }
  }

  void _iniciarCuentaRegresiva() {
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

  Future<void> _ejecutarDespaletizado() async {
    setState(() => _isLoading = true);
    try {
      await InventarioService.despaletizarActivo(
        widget.idActivo,
        motivo: _motivoSeleccionado,
        observacion: _observacionController.text.trim(),
        client: widget.client,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceAll('Exception: ', ''),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final folioStr = widget.numeroIngreso != null && widget.numeroIngreso!.isNotEmpty
        ? 'Folio Ingreso: ${widget.numeroIngreso}'
        : 'SKU: ${widget.sku}';

    final int obsLongitud = _observacionController.text.trim().length;
    final bool observacionValida = obsLongitud >= 10;
    final bool motivoValido = _motivoSeleccionado != null && _motivoSeleccionado!.isNotEmpty;
    final bool tiempoCumplido = _segundosRestantes == 0;
    final bool puedeConfirmar = !_isLoading && tiempoCumplido && motivoValido && observacionValida;

    return AlertDialog(
      backgroundColor: AppPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppPalette.error.withValues(alpha: 0.3)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppPalette.error.withValues(alpha: 0.15),
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
              children: [
                Text(
                  'Despaletizar Repuesto',
                  style: AppTypography.title.copyWith(
                    color: AppPalette.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  folioStr,
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Alerta inicial de impacto
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppPalette.error.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, color: AppPalette.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Esta acción devolverá este repuesto (${widget.categoria}) al estado "En Desarme" y alertará a Gerencia.',
                      style: AppTypography.body.copyWith(
                        color: AppPalette.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Trazabilidad de Ubicación Previa en Pantalla
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppPalette.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: AppPalette.warning, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Ubicación que será liberada en WMS:',
                        style: AppTypography.small.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppPalette.warning,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.ubicacionActual ?? 'Galpón / Pasillo / Pallet registrado',
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                      color: AppPalette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '⚠️ Esta pieza quedará sin ubicación fija hasta ser repaletizada.',
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Selector Táctil Ergonómico de Motivo (Gran tamaño para PDA con guantes)
            Text(
              'Seleccione Motivo Operativo *',
              style: AppTypography.small.copyWith(
                color: AppPalette.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Column(
              children: DialogoDespaletizar.motivosDisponibles.map((motivoMap) {
                final id = motivoMap['id']!;
                final label = motivoMap['label']!;
                final icon = motivoMap['icon']!;
                final isSelected = _motivoSeleccionado == id;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: Key('chip_motivo_$id'),
                      onTap: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _motivoSeleccionado = id;
                              });
                            },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 46),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppPalette.primary.withValues(alpha: 0.18)
                              : AppPalette.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? AppPalette.primary : Colors.white12,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(icon, style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                label,
                                style: AppTypography.body.copyWith(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? AppPalette.primary : AppPalette.textPrimary,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle, color: AppPalette.primary, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),

            // Justificación Obligatoria (Poka-Yoke >= 10 chars)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Justificación de Movimiento *',
                  style: AppTypography.small.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppPalette.textPrimary,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '$obsLongitud / 10 mín.',
                  key: const Key('contador_caracteres_despaletizar'),
                  style: AppTypography.small.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: observacionValida
                        ? AppPalette.success
                        : (obsLongitud > 0 ? AppPalette.warning : AppPalette.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              key: const Key('input_observacion_despaletizar'),
              controller: _observacionController,
              enabled: !_isLoading,
              maxLines: 2,
              style: AppTypography.body.copyWith(fontSize: 12.5, color: AppPalette.textPrimary),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: AppPalette.background,
                hintText: 'Detalle el motivo del despaletizado para auditoría y gerencia...',
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

            // Banner del contador de seguridad
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppPalette.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _segundosRestantes > 0
                      ? AppPalette.neutral.withValues(alpha: 0.3)
                      : AppPalette.success.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_segundosRestantes > 0) ...[
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: (5 - _segundosRestantes) / 5.0,
                        color: AppPalette.warning,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Espera $_segundosRestantes s para confirmar...',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.warning,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ] else ...[
                    const Icon(Icons.check_circle_outline, color: AppPalette.success, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Temporizador completado.',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.success,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('btn_cancelar_despaletizado'),
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: Text(
            'CANCELAR',
            style: AppTypography.button.copyWith(color: AppPalette.textSecondary),
          ),
        ),
        ElevatedButton.icon(
          key: const Key('btn_confirmar_despaletizado'),
          onPressed: puedeConfirmar ? _ejecutarDespaletizado : null,
          icon: _isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  Icons.undo_rounded,
                  size: 18,
                  color: puedeConfirmar ? Colors.white : Colors.white38,
                ),
          label: Text(
            _isLoading
                ? 'REVIRTIENDO...'
                : (_segundosRestantes > 0 ? 'CONFIRMAR (${_segundosRestantes}s)' : 'CONFIRMAR DESPALETIZADO'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: puedeConfirmar ? Colors.white : Colors.white38,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppPalette.error,
            disabledBackgroundColor: AppPalette.error.withValues(alpha: 0.25),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }
}
