// lib/features/ventas/presentation/widgets/cart_item_tile.dart

import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../controllers/cart_controller.dart';
import '../../models/cart_item_model.dart';
import '../screens/catalogo_screen.dart';
import '../../../../core/widgets/glass_snackbar.dart';

/// Tarjeta de ítem individual dentro del Carrito Híbrido (HU-3.3).
/// Diseñada en Flat Design estricto (sin sombras).
/// Permite edición in-line del precio acordado, ajuste de cantidad y eliminación.
class CartItemTile extends StatefulWidget {
  final CartItem item;

  const CartItemTile({
    super.key,
    required this.item,
  });

  @override
  State<CartItemTile> createState() => _CartItemTileState();
}

class _CartItemTileState extends State<CartItemTile> {
  late TextEditingController _precioController;
  final FocusNode _precioFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _precioController = TextEditingController(
      text: CurrencyFormatter.formatNumber(widget.item.precioUnitario),
    );
    _precioFocusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant CartItemTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.precioUnitario != widget.item.precioUnitario &&
        !_precioFocusNode.hasFocus) {
      _precioController.text =
          CurrencyFormatter.formatNumber(widget.item.precioUnitario);
    }
  }

  @override
  void dispose() {
    _precioFocusNode.removeListener(_onFocusChange);
    _precioFocusNode.dispose();
    _precioController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_precioFocusNode.hasFocus) {
      _guardarPrecio();
    }
  }

  void _onPrecioChanged(String val) {
    final nuevoPrecio = CurrencyFormatter.parse(val);
    if (nuevoPrecio != widget.item.precioUnitario) {
      CartController.instance.actualizarPrecio(widget.item.id, nuevoPrecio);
      setState(() {});
    }
  }

  void _guardarPrecio() {
    final nuevoPrecio = CurrencyFormatter.parse(_precioController.text);

    if (nuevoPrecio >= 0 && nuevoPrecio != widget.item.precioUnitario) {
      CartController.instance.actualizarPrecio(widget.item.id, nuevoPrecio);
      _precioController.text = CurrencyFormatter.formatNumber(nuevoPrecio);
    } else {
      _precioController.text =
          CurrencyFormatter.formatNumber(widget.item.precioUnitario);
    }
    setState(() {});
  }

  void _editarNotas(BuildContext context) async {
    final currentNotas = widget.item is InventariadoCartItem
        ? (widget.item as InventariadoCartItem).notasPreparacion ?? ''
        : (widget.item as VentaLibreCartItem).observacion ?? '';

    final controller = TextEditingController(text: currentNotas);

    final resultado = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          widget.item.esInventariado
              ? 'Notas de Preparación'
              : 'Observaciones del Ítem',
          style: AppTypography.title.copyWith(fontSize: 16),
        ),
        content: TextField(
          controller: controller,
          maxLines: 3,
          style: AppTypography.body,
          decoration: InputDecoration(
            hintText: 'Ej. Entregar con soporte, detalle especial...',
            hintStyle: AppTypography.small.copyWith(color: AppPalette.neutral),
            filled: true,
            fillColor: AppPalette.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancelar', style: TextStyle(color: AppPalette.neutral)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.primary,
              foregroundColor: AppPalette.textPrimary,
              elevation: 0,
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (resultado != null) {
      CartController.instance.actualizarNotas(
        widget.item.id,
        resultado.isNotEmpty ? resultado : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isInventario = widget.item.esInventariado;
    final invItem = isInventario && widget.item is InventariadoCartItem
        ? (widget.item as InventariadoCartItem)
        : null;
    final esInvalido = invItem != null && !invItem.esPrecioValido;
    final errorMsg = invItem?.errorRangoPrecio;

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: esInvalido
              ? AppPalette.error
              : (isInventario
                  ? AppPalette.primary.withValues(alpha: 0.2)
                  : AppPalette.secondary.withValues(alpha: 0.25)),
          width: esInvalido ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Fila Superior: Badge Tipo + Botón Eliminar (Touch 48x48) ────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Badge Tipo de Ítem
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                  decoration: BoxDecoration(
                    color: isInventario
                        ? AppPalette.primary.withValues(alpha: 0.15)
                        : AppPalette.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6.0),
                    border: Border.all(
                      color: isInventario ? AppPalette.primary : AppPalette.secondary,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isInventario ? Icons.inventory_2_outlined : Icons.edit_note,
                        size: 13,
                        color: isInventario ? AppPalette.primary : AppPalette.secondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isInventario ? 'Inventario' : 'Venta Libre',
                        style: AppTypography.small.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isInventario ? AppPalette.primary : AppPalette.secondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Botón de Eliminación (Touch Target >= 48x48)
                SizedBox(
                  width: 48,
                  height: 48,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppPalette.error,
                      size: 22,
                    ),
                    onPressed: () {
                      CartController.instance.eliminarItem(widget.item.id);
                      CatalogoScreen.refreshNotifier.value++;
                      GlassSnackbar.mostrar(
                        context,
                        mensaje: '${widget.item.titulo} eliminado del carrito',
                        icono: Icons.delete_outline_rounded,
                        colorIcono: AppPalette.error,
                      );
                    },
                    tooltip: 'Eliminar del carrito',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // ── Título del Ítem ─────────────────────────────────────────────
            Text(
              widget.item.titulo,
              style: AppTypography.cardTitle.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppPalette.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),

            // ── Subtítulo / Detalles ────────────────────────────────────────
            Text(
              widget.item.subtitulo,
              style: AppTypography.small.copyWith(
                color: AppPalette.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            // ── Fila de Notas de Preparación (Solo aplica a ítems inventariados) ─────
            if (widget.item is InventariadoCartItem) ...[
              _buildNotasRow(context),
            ],

            const SizedBox(height: 12),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 12),

            // ── Fila Inferior: Edición de Precio / Cantidad y Subtotal ──────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Columna 1: Precio Acordado / Unitario Editable
                Expanded(
                  flex: isInventario ? 5 : 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PRECIO ACORDADO (CLP):',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.small.copyWith(
                          fontSize: 12,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.bold,
                          color: AppPalette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppPalette.background,
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(
                            color: esInvalido
                                ? AppPalette.error
                                : Colors.white.withValues(alpha: 0.15),
                            width: esInvalido ? 1.5 : 1.0,
                          ),
                        ),
                        child: TextField(
                          controller: _precioController,
                          focusNode: _precioFocusNode,
                          keyboardType: TextInputType.number,
                          inputFormatters: [MilesTextInputFormatter()],
                          textAlignVertical: TextAlignVertical.center,
                          style: AppTypography.body.copyWith(
                            color: esInvalido ? AppPalette.error : AppPalette.secondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: AppPalette.background,
                            prefixText: '\$ ',
                            prefixStyle: AppTypography.body.copyWith(
                              color: esInvalido ? AppPalette.error : AppPalette.secondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            suffixIcon: Icon(
                              esInvalido ? Icons.error_outline : Icons.edit_outlined,
                              size: 16,
                              color: esInvalido ? AppPalette.error : AppPalette.neutral,
                            ),
                            suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 20),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                          onChanged: _onPrecioChanged,
                          onSubmitted: (_) => _guardarPrecio(),
                        ),
                      ),
                      if (invItem != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Rango: ${invItem.rangoPrecioFormateado}',
                          style: AppTypography.small.copyWith(
                            fontSize: 12,
                            color: esInvalido ? AppPalette.error : AppPalette.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (esInvalido && errorMsg != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.warning_amber_rounded, size: 14, color: AppPalette.error),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  errorMsg,
                                  style: AppTypography.small.copyWith(
                                    fontSize: 12,
                                    color: AppPalette.error,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Columna 2 (si es Venta Libre): Selector de Cantidad
                if (!isInventario) ...[
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'CANTIDAD:',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.small.copyWith(
                            fontSize: 12,
                            letterSpacing: 0.5,
                            fontWeight: FontWeight.bold,
                            color: AppPalette.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: AppPalette.background,
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.remove, size: 16),
                                  color: widget.item.cantidad > 1
                                      ? AppPalette.textPrimary
                                      : AppPalette.neutral,
                                  onPressed: () {
                                    CartController.instance.actualizarCantidad(
                                      widget.item.id,
                                      widget.item.cantidad - 1,
                                    );
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: Text(
                                  '${widget.item.cantidad}',
                                  style: AppTypography.title.copyWith(fontSize: 15),
                                ),
                              ),
                              Expanded(
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.add, size: 16),
                                  color: AppPalette.textPrimary,
                                  onPressed: () {
                                    CartController.instance.actualizarCantidad(
                                      widget.item.id,
                                      widget.item.cantidad + 1,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                ],

                // Columna 3: Subtotal
                Expanded(
                  flex: isInventario ? 4 : 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'SUBTOTAL:',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.small.copyWith(
                          fontSize: 12,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.bold,
                          color: AppPalette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 46,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              widget.item.subtotalFormateado,
                              style: AppTypography.headline.copyWith(
                                color: AppPalette.secondary,
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotasRow(BuildContext context) {
    String? notas;
    if (widget.item is InventariadoCartItem) {
      notas = (widget.item as InventariadoCartItem).notasPreparacion;
    } else if (widget.item is VentaLibreCartItem) {
      notas = (widget.item as VentaLibreCartItem).observacion;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _editarNotas(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: AppPalette.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: notas != null && notas.isNotEmpty
                  ? AppPalette.primary.withValues(alpha: 0.3)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.assignment_outlined,
                size: 16,
                color: notas != null && notas.isNotEmpty ? AppPalette.primary : AppPalette.neutral,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  notas != null && notas.isNotEmpty
                      ? 'Nota Bodega: $notas'
                      : 'Agregar nota de preparación para bodega...',
                  style: AppTypography.small.copyWith(
                    fontSize: 13,
                    color: notas != null && notas.isNotEmpty
                        ? AppPalette.textPrimary
                        : AppPalette.textSecondary,
                    fontWeight: notas != null && notas.isNotEmpty
                        ? FontWeight.w600
                        : FontWeight.normal,
                    fontStyle: notas != null && notas.isNotEmpty
                        ? FontStyle.normal
                        : FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.edit_outlined,
                size: 15,
                color: notas != null && notas.isNotEmpty ? AppPalette.primary : AppPalette.neutral,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
