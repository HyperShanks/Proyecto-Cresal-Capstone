// lib/features/ventas/presentation/widgets/asignar_precio_dialog.dart

import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../models/pendiente_precio_model.dart';
import '../../services/inventario_service.dart';
import '../screens/catalogo_screen.dart';
import 'galeria_activo_widget.dart';

/// Diálogo modal interactivo para fijar el precio de referencia de un repuesto (HU-3.8).
class AsignarPrecioDialog extends StatefulWidget {
  final ActivoPendientePrecioModel activo;
  final VoidCallback onPrecioAsignado;

  const AsignarPrecioDialog({
    super.key,
    required this.activo,
    required this.onPrecioAsignado,
  });

  static Future<void> show(
    BuildContext context, {
    required ActivoPendientePrecioModel activo,
    required VoidCallback onPrecioAsignado,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AsignarPrecioDialog(
        activo: activo,
        onPrecioAsignado: onPrecioAsignado,
      ),
    );
  }

  @override
  State<AsignarPrecioDialog> createState() => _AsignarPrecioDialogState();
}

class _AsignarPrecioDialogState extends State<AsignarPrecioDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _precioMinimoController;
  late final TextEditingController _precioMaximoController;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final minInicial = widget.activo.precioMinimo;
    final maxInicial = widget.activo.precioMaximo ?? widget.activo.precioReferencia;

    _precioMinimoController = TextEditingController(
      text: minInicial != null && minInicial > 0 ? CurrencyFormatter.formatNumber(minInicial) : '',
    );
    _precioMaximoController = TextEditingController(
      text: maxInicial != null && maxInicial > 0 ? CurrencyFormatter.formatNumber(maxInicial) : '',
    );

    _precioMinimoController.addListener(() => setState(() {}));
    _precioMaximoController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _precioMinimoController.dispose();
    _precioMaximoController.dispose();
    super.dispose();
  }

  int _obtenerMontoLimpio(String text) {
    final clean = text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(clean) ?? 0;
  }

  Future<void> _guardarPrecio() async {
    if (!_formKey.currentState!.validate()) return;

    final min = _obtenerMontoLimpio(_precioMinimoController.text);
    final max = _obtenerMontoLimpio(_precioMaximoController.text);

    if (min <= 0 || max <= 0) {
      setState(() {
        _errorMessage = 'Ambos precios deben ser mayores a \$0.';
      });
      return;
    }

    if (min > max) {
      setState(() {
        _errorMessage = 'El precio mínimo no puede ser superior al precio máximo.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await InventarioService.asignarPrecio(
        widget.activo.idActivo,
        precioMinimo: min,
        precioMaximo: max,
        precioReferencia: max,
      );

      if (!mounted) return;

      Navigator.of(context).pop(); // Cierra el diálogo
      CatalogoScreen.refreshNotifier.value++;
      widget.onPrecioAsignado();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppPalette.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${response.mensaje} (${response.rangoFormateado})',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppPalette.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: const BorderSide(color: Colors.white12, width: 1.0),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: AppPalette.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: const Icon(
              Icons.price_change_outlined,
              color: AppPalette.primary,
              size: 22.0,
            ),
          ),
          const SizedBox(width: 12.0),
          Expanded(
            child: Text(
              'Fijar Precio de Referencia',
              style: AppTypography.title.copyWith(fontSize: 17.0),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480.0,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Resumen del repuesto
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: AppPalette.background,
                    borderRadius: BorderRadius.circular(10.0),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.activo.tituloVehiculo,
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 14.0,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        'SKU: ${widget.activo.skuQrFisico} • ${widget.activo.fichaVehiculoDisplay}',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.secondary,
                          fontSize: 12.0,
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        widget.activo.especificacionesDisplay,
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textSecondary,
                          fontSize: 11.0,
                        ),
                      ),
                      if (widget.activo.observacionEstado != null &&
                          widget.activo.observacionEstado!.trim().isNotEmpty &&
                          widget.activo.observacionEstado!.trim().toLowerCase() != 'null' &&
                          widget.activo.observacionEstado!.trim() != 'Sin observaciones registradas.') ...[
                        const SizedBox(height: 8.0),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                          decoration: BoxDecoration(
                            color: AppPalette.secondary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(
                              color: AppPalette.secondary.withValues(alpha: 0.3),
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.sticky_note_2_outlined, size: 16.0, color: AppPalette.secondary),
                              const SizedBox(width: 8.0),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: AppTypography.small.copyWith(
                                      color: AppPalette.textPrimary,
                                      fontSize: 12.0,
                                    ),
                                    children: [
                                      const TextSpan(
                                        text: 'Obs. Bodega: ',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppPalette.secondary,
                                        ),
                                      ),
                                      TextSpan(
                                        text: widget.activo.observacionEstado!.trim(),
                                      ),
                                    ],
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

                const SizedBox(height: 14.0),

                // Galería de Fotografías del Activo (SPEC-HU-TAREA-15)
                GaleriaActivoWidget(
                  fotografias: widget.activo.fotografias,
                  height: 190.0,
                ),

                const SizedBox(height: 16.0),

                // Campo 1: Precio Mínimo (Piso de negociación)
                Text(
                  'PRECIO MÍNIMO (PISO DE NEGOCIACIÓN CLP)',
                  style: AppTypography.small.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 11.0,
                    letterSpacing: 0.8,
                    color: AppPalette.textSecondary,
                  ),
                ),
                const SizedBox(height: 8.0),
                TextFormField(
                  controller: _precioMinimoController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    MilesTextInputFormatter(),
                  ],
                  style: AppTypography.title.copyWith(
                    fontSize: 18.0,
                    color: AppPalette.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: AppTypography.title.copyWith(
                      fontSize: 18.0,
                      color: AppPalette.warning,
                      fontWeight: FontWeight.bold,
                    ),
                    hintText: 'Ej. 380.000',
                    hintStyle: AppTypography.body.copyWith(color: AppPalette.textSecondary),
                    filled: true,
                    fillColor: AppPalette.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Ingresa el precio mínimo piso';
                    }
                    final numVal = _obtenerMontoLimpio(val);
                    if (numVal <= 0) {
                      return 'El precio mínimo debe ser mayor a \$0';
                    }
                    final maxVal = _obtenerMontoLimpio(_precioMaximoController.text);
                    if (maxVal > 0 && numVal > maxVal) {
                      return 'No puede ser mayor al precio máximo';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16.0),

                // Campo 2: Precio Máximo (Sugerido / Lista)
                Text(
                  'PRECIO MÁXIMO (PRECIO SUGERIDO / LISTA CLP)',
                  style: AppTypography.small.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 11.0,
                    letterSpacing: 0.8,
                    color: AppPalette.textSecondary,
                  ),
                ),
                const SizedBox(height: 8.0),
                TextFormField(
                  controller: _precioMaximoController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    MilesTextInputFormatter(),
                  ],
                  style: AppTypography.title.copyWith(
                    fontSize: 18.0,
                    color: AppPalette.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: AppTypography.title.copyWith(
                      fontSize: 18.0,
                      color: AppPalette.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    hintText: 'Ej. 450.000',
                    hintStyle: AppTypography.body.copyWith(color: AppPalette.textSecondary),
                    filled: true,
                    fillColor: AppPalette.background,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Ingresa el precio máximo sugerido';
                    }
                    final numVal = _obtenerMontoLimpio(val);
                    if (numVal <= 0) {
                      return 'El precio máximo debe ser mayor a \$0';
                    }
                    final minVal = _obtenerMontoLimpio(_precioMinimoController.text);
                    if (minVal > 0 && numVal < minVal) {
                      return 'No puede ser menor al precio mínimo';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 14.0),

                // Previsualización del Rango de Negociación
                Builder(
                  builder: (context) {
                    final min = _obtenerMontoLimpio(_precioMinimoController.text);
                    final max = _obtenerMontoLimpio(_precioMaximoController.text);
                    if (min > 0 && max > 0 && min <= max) {
                      final margen = max - min;
                      return Container(
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: AppPalette.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(color: AppPalette.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.swap_horiz_rounded, color: AppPalette.primary, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Rango Permitido en Carrito:',
                                    style: AppTypography.small.copyWith(
                                      color: AppPalette.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    '\$${CurrencyFormatter.formatNumber(min)}  →  \$${CurrencyFormatter.formatNumber(max)}'
                                    '${margen > 0 ? ' (Margen: \$${CurrencyFormatter.formatNumber(margen)})' : ''}',
                                    style: AppTypography.small.copyWith(
                                      color: AppPalette.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12.0),
                Container(
                  padding: const EdgeInsets.all(10.0),
                  decoration: BoxDecoration(
                    color: AppPalette.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: AppPalette.error.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 18.0, color: AppPalette.error),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: AppTypography.small.copyWith(
                            color: AppPalette.error,
                            fontSize: 12.0,
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
      ),
    ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 48.0,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppPalette.textSecondary,
                    disabledForegroundColor: AppPalette.textSecondary.withValues(alpha: 0.5),
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            const SizedBox(width: 12.0),
            Expanded(
              flex: 3,
              child: SizedBox(
                height: 48.0,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.primary,
                    foregroundColor: AppPalette.textPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: _isLoading ? null : _guardarPrecio,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppPalette.textPrimary,
                          ),
                        )
                      : const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Confirmar Tasación',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
