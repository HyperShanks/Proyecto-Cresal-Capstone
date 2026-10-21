import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../core/theme/app_components.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../services/ordenes_service.dart';
import 'qr_ticket_dialog.dart';
import 'modal_anular_orden.dart';

/// Modal inferior para visualizar el detalle técnico completo de una orden de venta (HU-3.5).
/// Ofrece acciones condicionales de visualización de QR transaccional (HU-3.6),
/// edición de notas técnicas, entrega en mesón y anulación transaccional si está en estado 'Reservada'.
class OrdenDetailSheet extends StatefulWidget {
  final OrdenHistorialModel orden;
  final VoidCallback? onOrderUpdated;
  final http.Client? client;

  const OrdenDetailSheet({
    super.key,
    required this.orden,
    this.onOrderUpdated,
    this.client,
  });

  @override
  State<OrdenDetailSheet> createState() => _OrdenDetailSheetState();
}

class _OrdenDetailSheetState extends State<OrdenDetailSheet> {
  late OrdenHistorialModel _orden;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _orden = widget.orden;
  }

  Widget _buildStatusBadge() {
    Color bgColor;
    Color borderColor;
    Color textColor;
    IconData icon;
    String label = _orden.estadoOrden;

    if (_orden.esReservada) {
      if (_orden.esVentaEnVerde) {
        bgColor = AppPalette.success.withValues(alpha: 0.15);
        borderColor = AppPalette.success.withValues(alpha: 0.5);
        textColor = AppPalette.success;
        icon = Icons.eco_outlined;
        label = 'Venta en Verde';
      } else if (_orden.esAbonada) {
        bgColor = AppPalette.warning.withValues(alpha: 0.15);
        borderColor = AppPalette.warning.withValues(alpha: 0.5);
        textColor = AppPalette.warning;
        icon = Icons.account_balance_wallet_outlined;
        label = 'Abonado';
      } else {
        bgColor = AppPalette.secondary.withValues(alpha: 0.15);
        borderColor = AppPalette.secondary.withValues(alpha: 0.5);
        textColor = AppPalette.secondary;
        icon = Icons.bookmark_border_rounded;
        label = 'Reservada';
      }
    } else if (_orden.esPagada) {
      bgColor = AppPalette.success.withValues(alpha: 0.15);
      borderColor = AppPalette.success.withValues(alpha: 0.5);
      textColor = AppPalette.success;
      icon = Icons.check_circle_outline;
      label = 'Pagada';
    } else if (_orden.esCompletada) {
      bgColor = AppPalette.primary.withValues(alpha: 0.15);
      borderColor = AppPalette.primary.withValues(alpha: 0.5);
      textColor = AppPalette.primary;
      icon = Icons.verified_outlined;
      label = 'Completada';
    } else if (_orden.esAnulada) {
      bgColor = AppPalette.error.withValues(alpha: 0.15);
      borderColor = AppPalette.error.withValues(alpha: 0.5);
      textColor = AppPalette.error;
      icon = Icons.cancel_outlined;
      label = 'Anulada';
    } else {
      bgColor = AppPalette.neutral.withValues(alpha: 0.15);
      borderColor = AppPalette.neutral.withValues(alpha: 0.5);
      textColor = AppPalette.textSecondary;
      icon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14.0, color: textColor),
          const SizedBox(width: 4.0),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.0,
              fontWeight: FontWeight.w600,
              color: textColor,
              fontFamily: AppTypography.fontFamily,
            ),
          ),
        ],
      ),
    );
  }

  /// Diálogo para editar las instrucciones / notas técnicas para bodega
  Future<void> _dialogEditarInstrucciones() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    // Tomar la primera nota existente como valor inicial sugerido
    final notaActual = _orden.detalles.isNotEmpty
        ? (_orden.detalles.first.notasPreparacion ?? '')
        : '';
    final controller = TextEditingController(text: notaActual);

    final nuevoTexto = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
          side: const BorderSide(color: Colors.white10),
        ),
        title: Row(
          children: [
            const Icon(Icons.edit_note, color: AppPalette.primary, size: 24.0),
            const SizedBox(width: 8.0),
            Text(
              'Instrucciones a Bodega',
              style: AppTypography.title.copyWith(fontSize: 18.0),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Indica requerimientos especiales de desmontaje o preparación técnica para el bodeguero:',
              style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
            ),
            const SizedBox(height: 12.0),
            TextField(
              controller: controller,
              maxLines: 3,
              style: AppTypography.body,
              decoration: InputDecoration(
                hintText: 'Ej. Entregar con poleas y cables intactos...',
                hintStyle: AppTypography.small.copyWith(color: AppPalette.neutral),
                filled: true,
                fillColor: AppPalette.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(
              'Cancelar',
              style: AppTypography.button.copyWith(color: AppPalette.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.primary,
              foregroundColor: AppPalette.textPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
            ),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (nuevoTexto == null || !mounted) return;

    setState(() => _isLoading = true);

    try {
      await OrdenesService.actualizarInstruccionesBodega(
        _orden.idOrden,
        nuevoTexto,
      );

      if (!mounted) return;

      setState(() {
        for (final d in _orden.detalles) {
          d.notasPreparacion = nuevoTexto;
        }
        _isLoading = false;
      });

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 20.0),
              SizedBox(width: 8.0),
              Text('Instrucciones a bodega actualizadas exitosamente.'),
            ],
          ),
          backgroundColor: AppPalette.success,
          behavior: SnackBarBehavior.floating,
        ),
      );

      widget.onOrderUpdated?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error al actualizar instrucciones: $e'),
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Diálogo modal interactivo para anular la orden (SPEC-HU-TAREA-4)
  Future<void> _dialogAnularOrden() async {
    final result = await ModalAnularOrden.mostrar(
      context,
      idOrden: _orden.idOrden,
      folio: _orden.folioDisplay,
      clienteNombre: _orden.cliente?.nombreCompleto,
      totalVenta: _orden.totalVenta,
      montoPagado: _orden.montoPagado,
      client: widget.client,
      onOrdenAnulada: () {
        widget.onOrderUpdated?.call();
      },
    );

    if (result == true && mounted) {
      setState(() {
        _orden.estadoOrden = 'Anulada';
      });
      Navigator.of(context).pop(true); // Cerrar el bottom sheet tras anulación exitosa y retornar a mis órdenes
    }
  }



  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Tirador visual del modal ──────────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: 8.0, bottom: 4.0),
            width: 40.0,
            height: 4.0,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2.0),
            ),
          ),

          // ── Encabezado del BottomSheet ────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                          color: AppPalette.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        child: const Icon(
                          Icons.receipt_long_outlined,
                          size: 20.0,
                          color: AppPalette.primary,
                        ),
                      ),
                      const SizedBox(width: 8.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _orden.folioDisplay,
                              style: AppTypography.title.copyWith(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _orden.fechaFormateada,
                              style: AppTypography.small.copyWith(
                                fontSize: 11.5,
                                color: AppPalette.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6.0),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_orden.esMixta) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 3.0),
                        decoration: BoxDecoration(
                          color: AppPalette.secondary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20.0),
                          border: Border.all(color: AppPalette.secondary.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          'Mixta',
                          style: TextStyle(
                            fontSize: 11.0,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.secondary,
                            fontFamily: AppTypography.fontFamily,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4.0),
                    ],
                    _buildStatusBadge(),
                    const SizedBox(width: 4.0),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppPalette.textSecondary, size: 20.0),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white10, height: 1.0),

          // ── Contenido con Scroll ──────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_orden.esAsignadaLimache) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 14.0),
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD97706).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(
                          color: const Color(0xFFD97706).withValues(alpha: 0.45),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6.0),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD97706).withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              size: 18.0,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                          const SizedBox(width: 10.0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Venta Asignada a Limache',
                                  style: AppTypography.small.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFF59E0B),
                                    fontSize: 13.0,
                                  ),
                                ),
                                const SizedBox(height: 3.0),
                                Text(
                                  'La comisión y métrica comercial están imputadas a Limache. Como emisor en Viña del Mar, mantienes visibilidad operativa para cobro, preparación y entrega.',
                                  style: AppTypography.small.copyWith(
                                    fontSize: 12.0,
                                    color: AppPalette.textSecondary,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Sección 1: Datos del Cliente ───────────────────────
                  Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: AppPalette.background,
                      borderRadius: BorderRadius.circular(10.0),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person, size: 16.0, color: AppPalette.primary),
                            const SizedBox(width: 6.0),
                            Text(
                              'Datos del Cliente',
                              style: AppTypography.small.copyWith(
                                color: AppPalette.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8.0),
                        Text(
                          _orden.cliente != null && _orden.cliente!.nombres.isNotEmpty
                              ? '${_orden.cliente!.nombreCompleto} (${_orden.cliente!.rutCliente})'
                              : 'Cliente General',
                          style: AppTypography.body.copyWith(
                            fontSize: 14.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_orden.cliente?.telefono != null && _orden.cliente!.telefono!.isNotEmpty) ...[
                          const SizedBox(height: 4.0),
                          Text(
                            'Teléfono: ${_orden.cliente!.telefono}',
                            style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                          ),
                        ],
                        if (_orden.cliente?.correo != null && _orden.cliente!.correo!.isNotEmpty) ...[
                          const SizedBox(height: 2.0),
                          Text(
                            'Correo: ${_orden.cliente!.correo}',
                            style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Sección 2: Despacho (si aplica) ────────────────────
                  if (_orden.despacho != null) ...[
                    const SizedBox(height: 12.0),
                    Container(
                      padding: const EdgeInsets.all(12.0),
                      decoration: BoxDecoration(
                        color: AppPalette.background,
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.local_shipping, size: 16.0, color: AppPalette.secondary),
                                  const SizedBox(width: 6.0),
                                  Text(
                                    'Despacho a Domicilio',
                                    style: AppTypography.small.copyWith(
                                      color: AppPalette.secondary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                                decoration: BoxDecoration(
                                  color: AppPalette.success.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6.0),
                                  border: Border.all(
                                    color: AppPalette.success.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  _orden.despacho!.estadoDespacho.toLowerCase() == 'por enviar' ? 'Enviado' : _orden.despacho!.estadoDespacho,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: AppPalette.success,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8.0),
                          Text(
                            'Dirección: ${_orden.despacho!.direccionEnvio}',
                            style: AppTypography.body.copyWith(fontSize: 13.0),
                          ),
                          if (_orden.despacho!.comunaDestino != null && _orden.despacho!.comunaDestino!.isNotEmpty) ...[
                            const SizedBox(height: 2.0),
                            Text(
                              'Comuna: ${_orden.despacho!.comunaDestino}',
                              style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                            ),
                          ],
                          const SizedBox(height: 4.0),
                          Text(
                            'Receptor: ${_orden.despacho!.receptorNombres} (${_orden.despacho!.receptorRut.isNotEmpty ? _orden.despacho!.receptorRut : "S/R"})',
                            style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            'Teléfono: ${_orden.despacho!.receptorTelefono.isNotEmpty ? _orden.despacho!.receptorTelefono : (_orden.cliente?.telefono?.isNotEmpty == true ? _orden.cliente!.telefono! : "No registrado")}',
                            style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                          ),
                          if (_orden.despacho!.empresaTransporte != null && _orden.despacho!.empresaTransporte!.isNotEmpty) ...[
                            const SizedBox(height: 2.0),
                            Text(
                              'Transporte: ${_orden.despacho!.empresaTransporte}',
                              style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                            ),
                          ],
                          const SizedBox(height: 2.0),
                          Text(
                            'Costo Envío: ${_orden.despacho!.costoEnvioFormateado}',
                            style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                          ),
                          const SizedBox(height: 2.0),
                          Text(
                            'Estado Envío: ${_orden.despacho!.estadoDespacho}',
                            style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16.0),

                  // ── Sección 3: Desglose de Repuestos ───────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Desglose de Repuestos',
                        style: AppTypography.title.copyWith(fontSize: 15.0),
                      ),
                      Text(
                        '${_orden.detalles.length} ${_orden.detalles.length == 1 ? 'ítem' : 'ítems'}',
                        style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8.0),

                  ..._orden.detalles.map((detalle) => Container(
                        margin: const EdgeInsets.only(bottom: 10.0),
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: AppPalette.background,
                          borderRadius: BorderRadius.circular(10.0),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6.0),
                                  decoration: BoxDecoration(
                                    color: detalle.esInventariado
                                        ? AppPalette.primary.withValues(alpha: 0.15)
                                        : AppPalette.secondary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6.0),
                                  ),
                                  child: Icon(
                                    detalle.esInventariado
                                        ? Icons.precision_manufacturing_outlined
                                        : Icons.handyman_outlined,
                                    size: 16.0,
                                    color: detalle.esInventariado
                                        ? AppPalette.primary
                                        : AppPalette.secondary,
                                  ),
                                ),
                                const SizedBox(width: 8.0),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        detalle.titulo,
                                        style: AppTypography.body.copyWith(
                                          fontSize: 14.0,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (detalle.skuQrFisico != null) ...[
                                        const SizedBox(height: 2.0),
                                        Text(
                                          'SKU: ${detalle.skuQrFisico}',
                                          style: AppTypography.small.copyWith(
                                            fontSize: 12.0,
                                            color: AppPalette.textSecondary,
                                          ),
                                        ),
                                      ],
                                      if (detalle.descripcionManual != null &&
                                          detalle.descripcionManual!.isNotEmpty &&
                                          detalle.descripcionManual != detalle.titulo) ...[
                                        const SizedBox(height: 2.0),
                                        Text(
                                          detalle.descripcionManual!,
                                          style: AppTypography.small.copyWith(
                                            fontSize: 12.0,
                                            color: AppPalette.neutral,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4.0),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                                        decoration: BoxDecoration(
                                          color: detalle.esMotorOCaja
                                              ? AppPalette.primary.withValues(alpha: 0.12)
                                              : AppPalette.secondary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4.0),
                                          border: Border.all(
                                            color: detalle.esMotorOCaja
                                                ? AppPalette.primary.withValues(alpha: 0.3)
                                                : AppPalette.secondary.withValues(alpha: 0.3),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              detalle.esMotorOCaja
                                                  ? Icons.warehouse_outlined
                                                  : Icons.storefront_outlined,
                                              size: 11.0,
                                              color: detalle.esMotorOCaja
                                                  ? AppPalette.primary
                                                  : AppPalette.secondary,
                                            ),
                                            const SizedBox(width: 4.0),
                                            Flexible(
                                              child: Text(
                                                detalle.esMotorOCaja
                                                    ? 'Retiro en Bodega (Barrera)'
                                                    : 'Entrega Inmediata en Mesón',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: detalle.esMotorOCaja
                                                      ? AppPalette.primary
                                                      : AppPalette.secondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      detalle.subtotalFormateado,
                                      style: AppTypography.body.copyWith(
                                        fontSize: 14.0,
                                        fontWeight: FontWeight.bold,
                                        color: AppPalette.secondary,
                                      ),
                                    ),
                                    Text(
                                      '${detalle.cantidad} x ${detalle.precioFinalFormateado}',
                                      style: AppTypography.small.copyWith(
                                        fontSize: 11.0,
                                        color: AppPalette.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            // Notas de preparación técnica de este ítem (solo activos o motores/cajas, no misceláneos)
                            if (detalle.notasPreparacion != null &&
                                detalle.notasPreparacion!.isNotEmpty &&
                                (detalle.esInventariado || detalle.esMotorOCaja)) ...[
                              const SizedBox(height: 8.0),
                              Container(
                                padding: const EdgeInsets.all(8.0),
                                decoration: BoxDecoration(
                                  color: AppPalette.surface,
                                  borderRadius: BorderRadius.circular(6.0),
                                  border: Border.all(
                                    color: AppPalette.secondary.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.note_alt_outlined,
                                      size: 14.0,
                                      color: AppPalette.secondary,
                                    ),
                                    const SizedBox(width: 6.0),
                                    Expanded(
                                      child: Text(
                                        'Nota: ${detalle.notasPreparacion}',
                                        style: AppTypography.small.copyWith(
                                          fontSize: 12.0,
                                          color: AppPalette.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      )),

                  const SizedBox(height: 12.0),

                  // ── Resumen de Totales ─────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14.0),
                    decoration: BoxDecoration(
                      color: AppPalette.background,
                      borderRadius: BorderRadius.circular(10.0),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      children: [
                        if (_orden.descuento > 0) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Descuento a Favor',
                                style: AppTypography.body.copyWith(
                                  color: const Color(0xFFEF5350),
                                  fontSize: 14.0,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '- ${_orden.descuentoFormateado}',
                                style: AppTypography.title.copyWith(
                                  color: const Color(0xFFEF5350),
                                  fontSize: 15.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8.0),
                          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                          const SizedBox(height: 8.0),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total de la Orden',
                              style: AppTypography.title.copyWith(fontSize: 16.0),
                            ),
                            Text(
                              _orden.totalVentaFormateado,
                              style: AppTypography.headline.copyWith(
                                fontSize: 20.0,
                                color: _orden.esAnulada ? AppPalette.neutral : AppPalette.secondary,
                              ),
                            ),
                          ],
                        ),
                        if (_orden.esAbonada) ...[
                          const SizedBox(height: 8.0),
                          Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                          const SizedBox(height: 8.0),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.check_circle_outline, color: AppPalette.success, size: 16.0),
                                  const SizedBox(width: 6.0),
                                  Text(
                                    'Monto Abonado',
                                    style: AppTypography.body.copyWith(
                                      color: AppPalette.success,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                _orden.montoPagadoFormateado,
                                style: AppTypography.title.copyWith(
                                  fontSize: 16.0,
                                  color: AppPalette.success,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6.0),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.pending_actions_outlined, color: AppPalette.warning, size: 16.0),
                                  const SizedBox(width: 6.0),
                                  Text(
                                    'Saldo Pendiente',
                                    style: AppTypography.body.copyWith(
                                      color: AppPalette.warning,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                _orden.montoPendienteFormateado,
                                style: AppTypography.title.copyWith(
                                  fontSize: 16.0,
                                  color: AppPalette.warning,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ── Sección 4.A.0: Aviso Informativo Orden Mixta (Mesón + Bodega) ──
                  if (_orden.esMixta && _orden.esPagada && !_orden.esCompletada) ...[
                    const SizedBox(height: 16.0),
                    Container(
                      padding: const EdgeInsets.all(14.0),
                      decoration: BoxDecoration(
                        color: AppPalette.secondary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(color: AppPalette.secondary.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.swap_horiz_rounded, color: AppPalette.secondary, size: 22.0),
                          const SizedBox(width: 10.0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Orden Mixta (Mesón + Bodega)',
                                  style: AppTypography.title.copyWith(
                                    color: AppPalette.secondary,
                                    fontSize: 14.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  'Entrega el o los repuestos misceláneos al cliente directamente en mesón. El activo principal (motor/caja) debe ser retirado en bodega con el Ticket QR. La orden pasará a Completada automáticamente al validar la salida en barrera.',
                                  style: AppTypography.small.copyWith(
                                    color: AppPalette.textPrimary,
                                    fontSize: 12.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Sección 4.A: Ticket QR Transaccional (Si tiene motor/caja y QR disponible) ─
                  if (_orden.contieneMotorOCaja && _orden.tieneQrDisponible) ...[
                    const SizedBox(height: 20.0),
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: AppPalette.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(color: AppPalette.success.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8.0),
                                decoration: BoxDecoration(
                                  color: AppPalette.success.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8.0),
                                ),
                                child: const Icon(
                                  Icons.qr_code_2_rounded,
                                  color: AppPalette.success,
                                  size: 28.0,
                                ),
                              ),
                              const SizedBox(width: 12.0),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Ticket Digital Emitido',
                                      style: AppTypography.title.copyWith(
                                        color: AppPalette.success,
                                        fontSize: 15.0,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Orden pagada. Lista para retiro en bodega.',
                                      style: AppTypography.small.copyWith(
                                        color: AppPalette.textSecondary,
                                        fontSize: 12.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14.0),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppPalette.success,
                                foregroundColor: AppPalette.textPrimary,
                                elevation: 0,
                                minimumSize: const Size(double.infinity, 48.0),
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppComponents.defaultBorderRadius),
                                ),
                              ),
                              icon: const Icon(Icons.qr_code, size: 20.0),
                              label: const Text(
                                'MOSTRAR QR DE ENTREGA (BODEGA)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              onPressed: () => QrTicketDialog.mostrar(context, _orden),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Sección 4.B: Confirmación de Entrega (Si está Completada) ─
                  if (_orden.esCompletada) ...[
                    const SizedBox(height: 20.0),
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: AppPalette.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(color: AppPalette.primary.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8.0),
                            decoration: BoxDecoration(
                              color: AppPalette.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8.0),
                            ),
                            child: const Icon(
                              Icons.verified_outlined,
                              color: AppPalette.primary,
                              size: 24.0,
                            ),
                          ),
                          const SizedBox(width: 12.0),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Orden Completada',
                                  style: AppTypography.title.copyWith(
                                    color: AppPalette.primary,
                                    fontSize: 14.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  'Los repuestos fueron validados y entregados exitosamente en barrera de bodega.',
                                  style: AppTypography.small.copyWith(
                                    color: AppPalette.textSecondary,
                                    fontSize: 12.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Sección 5: Acciones de Gestión (Reservada o Pagada, antes de entregarse) ──
                  if (_orden.esAnulable) ...[
                    const SizedBox(height: 20.0),
                    Text(
                      'Acciones de Gestión',
                      style: AppTypography.title.copyWith(fontSize: 15.0),
                    ),
                    const SizedBox(height: 10.0),
                    // Botón Editar Instrucciones a Bodega (solo para órdenes Reservadas con repuestos inventariados)
                    if (_orden.esReservada &&
                        (_orden.contieneMotorOCaja ||
                            _orden.detalles.any((d) => d.esInventariado) ||
                            _orden.detalles.isEmpty)) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 48.0,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppPalette.primary,
                            side: const BorderSide(
                              color: AppPalette.primary,
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.0),
                            ),
                          ),
                          icon: const Icon(Icons.edit_note, size: 20.0),
                          label: const Text(
                            'Editar Instrucciones a Bodega',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onPressed:
                              _isLoading ? null : _dialogEditarInstrucciones,
                        ),
                      ),
                      const SizedBox(height: 10.0),
                    ],

                    // Botón Deshacer / Anular Orden (Extend)
                    SizedBox(
                      width: double.infinity,
                      height: 48.0,
                      child: ElevatedButton.icon(
                        key: const Key('btn_anular_orden_detail'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              AppPalette.error.withValues(alpha: 0.15),
                          foregroundColor: AppPalette.error,
                          elevation: 0,
                          side: BorderSide(
                            color: AppPalette.error.withValues(alpha: 0.6),
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10.0),
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 20.0),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _orden.montoPagado > 0
                                ? 'Anular Orden (Devolver ${_orden.montoPagadoFormateado})'
                                : 'Deshacer Orden (Liberar Stock)',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        onPressed: _isLoading ? null : _dialogAnularOrden,
                      ),
                    ),
                  ],

                  const SizedBox(height: 16.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
