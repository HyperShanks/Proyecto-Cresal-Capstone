// lib/features/ventas/presentation/widgets/venta_libre_dialog.dart

import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../controllers/cart_controller.dart';
import '../../../../core/widgets/glass_snackbar.dart';

/// Modal Bottom Sheet para registrar un artículo de Venta Libre / Misceláneo (HU-3.3).
/// Permite inyectar al Carrito Híbrido repuestos o servicios no catalogados en base de datos.
class VentaLibreDialog extends StatefulWidget {
  const VentaLibreDialog({super.key});

  static Future<void> show(BuildContext context) {
    if (CartController.instance.tieneVentaEnVerde) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'No se pueden agregar ítems manuales a un pedido con Venta en Verde. Las ventas en verde van solas.',
          ),
        ),
      );
      return Future.value();
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (ctx) => const VentaLibreDialog(),
    );
  }

  @override
  State<VentaLibreDialog> createState() => _VentaLibreDialogState();
}

class _VentaLibreDialogState extends State<VentaLibreDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _montoController = TextEditingController();
  int _cantidad = 1;

  @override
  void dispose() {
    _descController.dispose();
    _montoController.dispose();
    super.dispose();
  }

  void _incrementarCantidad() {
    setState(() {
      _cantidad++;
    });
  }

  void _decrementarCantidad() {
    if (_cantidad > 1) {
      setState(() {
        _cantidad--;
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final monto = CurrencyFormatter.parse(_montoController.text);

    if (monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppPalette.surface,
          content: Text(
            'El monto debe ser mayor a \$0',
            style: TextStyle(color: AppPalette.error),
          ),
        ),
      );
      return;
    }

    final agregado = CartController.instance.agregarVentaLibre(
      descripcion: _descController.text.trim(),
      monto: monto,
      cantidad: _cantidad,
    );

    if (!agregado) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'No se pudo agregar el ítem manual. El pedido contiene una Venta en Verde (las ventas en verde van solas).',
          ),
        ),
      );
      return;
    }

    Navigator.of(context).pop();

    GlassSnackbar.mostrar(
      context,
      mensaje: '${_descController.text.trim()} agregado al carrito',
      icono: Icons.check_circle_outline_rounded,
      colorIcono: AppPalette.primary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 20.0 + bottomInset),
      decoration: const BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(12.0)),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Tirador visual superior ───────────────────────────────────
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppPalette.neutral.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Encabezado: Título + Botón Cerrar (48x48) ───────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppPalette.secondary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.add_shopping_cart,
                          color: AppPalette.secondary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Venta Libre',
                        style: AppTypography.title.copyWith(fontSize: 16),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: AppPalette.textPrimary),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Cerrar',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Campo: Descripción del Artículo ───────────────────────────
              Text(
                'DESCRIPCIÓN DEL ARTÍCULO / SERVICIO *',
                style: AppTypography.small.copyWith(
                  fontSize: 11,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.bold,
                  color: AppPalette.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descController,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 3,
                style: AppTypography.body.copyWith(color: AppPalette.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Ej. Perno culata especial, Mano de obra, etc.',
                  hintStyle: AppTypography.small.copyWith(color: AppPalette.neutral),
                  filled: true,
                  fillColor: AppPalette.background,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Ingresa una descripción para el ítem';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // ── Fila: Monto Unitario y Cantidad ───────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Monto Unitario (CLP)
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MONTO UNITARIO (CLP) *',
                          style: AppTypography.small.copyWith(
                            fontSize: 11,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.bold,
                            color: AppPalette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _montoController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [MilesTextInputFormatter()],
                          style: AppTypography.body.copyWith(
                            color: AppPalette.secondary,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            prefixText: '\$ ',
                            prefixStyle: AppTypography.body.copyWith(
                              color: AppPalette.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                            hintText: '0',
                            hintStyle: AppTypography.small.copyWith(color: AppPalette.neutral),
                            filled: true,
                            fillColor: AppPalette.background,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Ingresa un monto';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Selector de Cantidad
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CANTIDAD',
                          style: AppTypography.small.copyWith(
                            fontSize: 11,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.bold,
                            color: AppPalette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: AppPalette.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              SizedBox(
                                width: 36,
                                height: 48,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.remove, size: 18),
                                  color: _cantidad > 1
                                      ? AppPalette.textPrimary
                                      : AppPalette.neutral,
                                  onPressed: _decrementarCantidad,
                                ),
                              ),
                              Text(
                                '$_cantidad',
                                style: AppTypography.title.copyWith(fontSize: 15),
                              ),
                              SizedBox(
                                width: 36,
                                height: 48,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.add, size: 18),
                                  color: AppPalette.textPrimary,
                                  onPressed: _incrementarCantidad,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Botón de Acción Principal (Touch Target >= 48px) ───────────
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.add_shopping_cart, size: 20),
                  label: Text(
                    'Agregar al Carrito',
                    style: AppTypography.button.copyWith(
                      color: AppPalette.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.primary,
                    foregroundColor: AppPalette.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
