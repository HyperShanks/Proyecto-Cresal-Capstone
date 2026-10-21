import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../models/cobro_pendiente_model.dart';
import '../../models/cobro_model.dart';
import '../providers/caja_provider.dart';
import 'cobro_pendiente_card.dart';
import 'confirmacion_liquidacion_dialog.dart';
import 'resultado_cobro_dialog.dart';

/// Panel de Detalle de Cobro con soporte para Pago Único o Dividido (Split Payment).
/// Cumple con la especificación SPEC-HU-03 / CRES-214 (Master-Detail alimentado en memoria).
class PanelDetalleCobro extends StatefulWidget {
  final CajaProvider provider;

  const PanelDetalleCobro({super.key, required this.provider});

  @override
  State<PanelDetalleCobro> createState() => _PanelDetalleCobroState();
}

class _PanelDetalleCobroState extends State<PanelDetalleCobro> {
  final TextEditingController _montoAbonoPersonalizadoController =
      TextEditingController();
  final List<TextEditingController> _montoControllers = [];
  String? _lastIdReferencia;
  int? _lastPagosCount;

  @override
  void initState() {
    super.initState();
    _sincronizarControllers();
  }

  @override
  void didUpdateWidget(covariant PanelDetalleCobro oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sincronizarControllers();
  }

  @override
  void dispose() {
    _montoAbonoPersonalizadoController.dispose();
    for (final c in _montoControllers) {
      c.dispose();
    }
    _montoControllers.clear();
    super.dispose();
  }

  void _sincronizarControllers() {
    final orden = widget.provider.ordenSeleccionada;
    final pagos = widget.provider.pagosDivididos;

    if (orden == null) {
      _lastIdReferencia = null;
      _lastPagosCount = 0;
      return;
    }

    final ordenCambio = _lastIdReferencia != orden.idReferencia;
    final countCambio = _lastPagosCount != pagos.length;

    if (ordenCambio || countCambio) {
      _lastIdReferencia = orden.idReferencia;
      _lastPagosCount = pagos.length;

      // Limpiar controladores existentes
      for (final c in _montoControllers) {
        c.dispose();
      }
      _montoControllers.clear();

      for (int i = 0; i < pagos.length; i++) {
        final ctrl = TextEditingController(
          text: pagos[i].monto > 0
              ? CurrencyFormatter.formatNumber(pagos[i].monto)
              : '',
        );
        _montoControllers.add(ctrl);
      }
    } else {
      // Actualizar valores de controladores si difieren del provider
      for (int i = 0; i < pagos.length && i < _montoControllers.length; i++) {
        final currentTextVal = CurrencyFormatter.parse(
          _montoControllers[i].text,
        );
        if (currentTextVal != pagos[i].monto) {
          _montoControllers[i].text = pagos[i].monto > 0
              ? CurrencyFormatter.formatNumber(pagos[i].monto)
              : '';
        }
      }
    }

    // Sincronizar campo de abono personalizado con montoDeclarado
    final currentCustomVal = CurrencyFormatter.parse(
      _montoAbonoPersonalizadoController.text,
    );
    if (currentCustomVal != widget.provider.montoDeclarado) {
      _montoAbonoPersonalizadoController.text =
          widget.provider.montoDeclarado > 0
          ? CurrencyFormatter.formatNumber(widget.provider.montoDeclarado)
          : '';
    }
  }

  IconData _getIconoMetodo(String metodo) {
    switch (metodo.toLowerCase()) {
      case 'efectivo':
        return Icons.payments_rounded;
      case 'debito':
      case 'débito':
        return Icons.credit_card_rounded;
      case 'credito':
      case 'crédito':
        return Icons.credit_card_rounded;
      case 'transferencia':
        return Icons.swap_horiz_rounded;
      case 'cheque':
        return Symbols.checkbook_rounded;
      default:
        return Icons.account_balance_wallet_rounded;
    }
  }

  Future<void> _handleProcesarCobro() async {
    final orden = widget.provider.ordenSeleccionada;
    if (orden == null) return;

    // Control preventivo: confirmación explícita para liquidar el saldo total en etapas posteriores
    final esLiquidacionPosterior = widget.provider.esLiquidacionCompleta &&
        (orden.abonoPrevio > 0 ||
            orden.historialAbonos.isNotEmpty ||
            !orden.esPrimerAbono ||
            orden.esBackorder);

    if (esLiquidacionPosterior) {
      final confirmado = await ConfirmacionLiquidacionDialog.show(
        context: context,
        orden: orden,
        montoALiquidar: widget.provider.montoDeclarado,
      );
      if (!confirmado) {
        // Cancelación segura: no se procesa cobro y la orden mantiene su saldo intacto
        return;
      }
      if (!mounted) return;
    }

    // Cobro directo (para ventas normales, abonos y ventas en verde)
    // Las ventas en verde se cobran directamente al 100%; la asignación física del motor o caja
    // es realizada exclusivamente por el vendedor desde su apartado "Por Asignar".
    try {
      final res = await widget.provider.procesarCobro();
      if (!mounted) return;

      if (res != null && res.success) {
        await _mostrarResultadoCobro(orden, res);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          content: Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  e.toString().replaceAll('Exception: ', ''),
                  style: AppTypography.body.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _mostrarResultadoCobro(
    CobroPendienteModel orden,
    RegistrarCobroResponseModel res,
  ) async {
    final resumenMetodos = widget.provider.pagosDivididos
        .where((p) => p.monto > 0)
        .map((p) => '${p.metodo}: ${CobroPendienteCard.formatClp(p.monto)}')
        .join(' + ');

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => ResultadoCobroDialog(
        orden: orden,
        resultado: res,
        metodosResumen: resumenMetodos,
        onSiguienteOrden: () {
          Navigator.of(dialogCtx).pop();
          if (res.nuevoSaldoPendiente == 0 || res.qrGenerado != null) {
            // Liquidación completa (con o sin asignación física): orden pagada
            widget.provider.removerOrdenProcesada(orden.idReferencia);
          } else {
            // Abono parcial: recargar bandeja para reflejar saldos actualizados y deseleccionar
            widget.provider.cargarCobrosPendientes(refresh: true);
            widget.provider.seleccionarOrden(null);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.provider,
      builder: (context, _) {
        final orden = widget.provider.ordenSeleccionada;
        if (orden == null) {
          return _buildEmptyState();
        }
        return _buildPanelContent(context, orden);
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      color: AppPalette.backgroundLight,
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppPalette.surfaceLight,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppPalette.neutral.withValues(alpha: 0.2),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                size: 48,
                color: AppPalette.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Seleccione una orden para procesar el cobro',
              style: AppTypography.title.copyWith(
                color: AppPalette.textPrimaryLight,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Haga clic en cualquiera de las tarjetas de la bandeja izquierda para ver los detalles.',
              style: AppTypography.body.copyWith(
                color: AppPalette.textSecondaryLight,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelContent(BuildContext context, CobroPendienteModel orden) {
    final isVenta = orden.esVenta;

    return Container(
      color: AppPalette.backgroundLight,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── 1. ENCABEZADO DE LA ORDEN / FOLIO (ST-F02) ──
          _buildHeaderCard(orden, isVenta),

          const SizedBox(height: 16),

          // ── 2. TARJETA FINANCIERA DESTACADA (AZUL CRESAL ST-F02) ──
          _buildFinancialCard(orden),

          // ── 2.1 HISTORIAL DE ABONOS REGISTRADOS ──
          if (orden.historialAbonos.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildHistorialAbonosSection(orden),
          ],

          const SizedBox(height: 16),

          // ── 3. DESGLOSE ADAPTATIVO (REPUESTOS O BACKORDER) (CA-01) ──
          _buildDesgloseCard(orden, isVenta),

          const SizedBox(height: 16),

          // ── 4. SELECTOR DE MODALIDAD (SALDO COMPLETO VS ABONO PERSONALIZADO) ──
          _buildModalidadCobroSection(orden),

          const SizedBox(height: 16),

          // ── 5. PASARELA DE MÉTODOS DE PAGO (PAGO ÚNICO / SPLIT) (ST-F04 / CA-04) ──
          _buildMetodosPagoSection(),

          const SizedBox(height: 16),

          // ── 6. INDICADOR DE CUADRATURA Y BOTÓN PROCESAR (ST-F05 / CA-05) ──
          _buildCuadraturaYAccion(context, orden),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(CobroPendienteModel orden, bool isVenta) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Folio y Tipo
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      orden.folioDocumento,
                      style: AppTypography.headline.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.primary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (isVenta
                                    ? AppPalette.secondary
                                    : AppPalette.tertiary)
                                .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              (isVenta
                                      ? AppPalette.secondary
                                      : AppPalette.tertiary)
                                  .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isVenta
                                ? Icons.storefront_rounded
                                : Icons.directions_boat_filled_outlined,
                            size: 14,
                            color: isVenta
                                ? AppPalette.warningText
                                : AppPalette.tertiary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isVenta ? 'Venta en Tienda' : 'Ventas en Verde',
                            style: AppTypography.small.copyWith(
                              color: isVenta
                                  ? AppPalette.warningText
                                  : AppPalette.tertiary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (orden.esPrimerAbono &&
                        (orden.abonoRequerido > 0
                                ? orden.abonoRequerido
                                : orden.montoACobrar) >
                            0 &&
                        (orden.abonoRequerido > 0
                                ? orden.abonoRequerido
                                : orden.montoACobrar) <
                            orden.totalOperacion &&
                        orden.saldoPendiente > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E8FF),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFC084FC)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.savings_rounded,
                              size: 14,
                              color: Color(0xFF7E22CE),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Abono Inicial: ${CobroPendienteCard.formatClp(orden.abonoRequerido > 0 ? orden.abonoRequerido : orden.montoACobrar)}',
                              style: AppTypography.small.copyWith(
                                color: const Color(0xFF7E22CE),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Botón Limpiar Selección
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                color: AppPalette.textSecondaryLight,
                tooltip: 'Cerrar detalle',
                onPressed: () {
                  widget.provider.seleccionarOrden(null);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.person_rounded,
                size: 18,
                color: AppPalette.textSecondaryLight,
              ),
              const SizedBox(width: 8),
              Builder(
                builder: (context) {
                  final rutLimpio = orden.clienteRut.replaceAll(
                    RegExp(r'[^0-9kK]'),
                    '',
                  );
                  final esClienteGenerico =
                      rutLimpio.isEmpty ||
                      rutLimpio.startsWith('666666') ||
                      orden.clienteRut == '6.666.666-6' ||
                      orden.clienteNombre.trim().toLowerCase().contains(
                        'consumidor final',
                      );
                  final nombreMostrar =
                      (orden.clienteNombre.trim().isEmpty || esClienteGenerico)
                      ? 'Consumidor Final'
                      : orden.clienteNombre;
                  final textoCliente = esClienteGenerico
                      ? '$nombreMostrar  •  Sin RUT registrado'
                      : '$nombreMostrar  •  RUT: ${orden.clienteRut}';

                  return Expanded(
                    child: Text(
                      textoCliente,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textPrimaryLight,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(
                Icons.badge_rounded,
                size: 18,
                color: AppPalette.textSecondaryLight,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Vendedor: ${orden.vendedorNombre}  •  Emitida el ${orden.fechaEmisionFormateada} a las ${orden.horaEmisionFormateada}',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondaryLight,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialCard(CobroPendienteModel orden) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        color: AppPalette.tertiary,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppPalette.tertiary.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Total Operación (Subtotal Bruto si hay descuento)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      orden.descuento > 0
                          ? 'SUBTOTAL BRUTO'
                          : (orden.esVenta ? 'TOTAL VENTA' : 'PRECIO ACORDADO'),
                      style: AppTypography.small.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CobroPendienteCard.formatClp(orden.totalOperacion),
                      style: AppTypography.title.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              if (orden.descuento > 0) ...[
                Container(
                  height: 36,
                  width: 1,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DESCUENTO',
                          style: AppTypography.small.copyWith(
                            color: const Color(0xFFFFCDD2),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '- ${CobroPendienteCard.formatClp(orden.descuento)}',
                          style: AppTypography.title.copyWith(
                            color: const Color(0xFFFFCDD2),
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              Container(
                height: 36,
                width: 1,
                color: Colors.white.withValues(alpha: 0.25),
              ),
              // Abonos Previos
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        orden.historialAbonos.isNotEmpty
                            ? 'ABONOS (${orden.historialAbonos.length})'
                            : 'ABONOS PREVIOS',
                        style: AppTypography.small.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        CobroPendienteCard.formatClp(orden.abonoPrevio),
                        style: AppTypography.title.copyWith(
                          color: orden.abonoPrevio > 0
                              ? AppPalette.secondary
                              : Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                height: 36,
                width: 1,
                color: Colors.white.withValues(alpha: 0.25),
              ),
              // Saldo Pendiente Actual
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SALDO PENDIENTE',
                        style: AppTypography.small.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        CobroPendienteCard.formatClp(
                          orden.saldoPendiente > 0
                              ? orden.saldoPendiente
                              : orden.totalOperacion,
                        ),
                        style: AppTypography.title.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesgloseCard(CobroPendienteModel orden, bool isVenta) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isVenta ? Icons.assignment_rounded : Icons.info_outline_rounded,
                size: 18,
                color: AppPalette.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isVenta
                    ? 'DETALLE DE REPUESTOS Y ARTÍCULOS'
                    : 'ESPECIFICACIONES DE VENTA EN VERDE',
                style: AppTypography.title.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textSecondaryLight,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (isVenta) ...[
            _buildArticulosList(orden.articulos),
          ] else ...[
            _buildBackorderGrid(orden.especificacionesBackorder),
            if (orden.articulos.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    Icons.widgets_outlined,
                    size: 16,
                    color: AppPalette.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'ARTÍCULOS Y REPUESTOS DE LA ORDEN',
                    style: AppTypography.small.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textSecondaryLight,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildArticulosList(orden.articulos),
            ],
          ],
          if (orden.descuento > 0) ...[
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.confirmation_num_outlined,
                      size: 16,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Descuento a Favor:',
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFEF5350),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                Text(
                  '- ${CobroPendienteCard.formatClp(orden.descuento)}',
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFEF5350),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildArticulosList(List<ArticuloResumenModel> articulos) {
    if (articulos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('Sin artículos asociados a la orden.'),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: articulos.length,
      separatorBuilder: (context, index) =>
          Divider(color: AppPalette.borderLight, height: 14),
      itemBuilder: (context, idx) {
        final art = articulos[idx];
        final tieneSku = art.sku != null && art.sku!.isNotEmpty;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppPalette.backgroundLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppPalette.borderLight),
              ),
              alignment: Alignment.center,
              child: Text(
                '${art.cantidad}x',
                style: AppTypography.small.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppPalette.primary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    art.nombreDisplay,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppPalette.textPrimaryLight,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (tieneSku)
                    Text(
                      'SKU: ${art.sku}',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.textSecondaryLight,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: art.tipo == 'RESERVA'
                            ? const Color(0xFFF3E8FF)
                            : AppPalette.neutral.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: art.tipo == 'RESERVA'
                            ? Border.all(color: const Color(0xFFC084FC), width: 1)
                            : null,
                      ),
                      child: Text(
                        art.tipo == 'RESERVA' ? 'Venta en Verde' : 'Misceláneo',
                        style: AppTypography.small.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: art.tipo == 'RESERVA'
                              ? const Color(0xFF7E22CE)
                              : AppPalette.textSecondaryLight,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              CobroPendienteCard.formatClp(art.subtotal),
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.w800,
                color: AppPalette.textPrimaryLight,
                fontSize: 16,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBackorderGrid(BackorderEspecificacionesModel? bo) {
    if (bo == null) {
      return const Text('Sin especificaciones de venta en verde disponibles.');
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildSpecTile('Marca Requerida', bo.marca)),
            const SizedBox(width: 12),
            Expanded(child: _buildSpecTile('Modelo Requerido', bo.modelo)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildSpecTile('Categoría', bo.categoria)),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSpecTile(
                'Año Requerido',
                bo.anio != null ? bo.anio.toString() : 'No especificado',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildSpecTile(
                'Cilindrada',
                bo.cilindrada != null && bo.cilindrada!.isNotEmpty
                    ? bo.cilindrada!
                    : 'No especificada',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSpecTile(
                'Combustible',
                bo.combustible != null && bo.combustible!.isNotEmpty
                    ? bo.combustible!
                    : 'No especificado',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSpecTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.backgroundLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.small.copyWith(
              color: AppPalette.textSecondaryLight,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTypography.body.copyWith(
              color: AppPalette.textPrimaryLight,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMetodosPagoSection() {
    final modalidadPago = widget.provider.modalidadPago;
    final isUnico = modalidadPago == 'UNICO';
    final pagos = widget.provider.pagosDivididos;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.payment_rounded,
                    size: 18,
                    color: AppPalette.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'MÉTODOS DE PAGO',
                    style: AppTypography.title.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textSecondaryLight,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  final nuevaMod = isUnico ? 'SPLIT' : 'UNICO';
                  widget.provider.setModalidadPago(nuevaMod);
                  _sincronizarControllers();
                },
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isUnico
                            ? Icons.call_split_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 16,
                        color: AppPalette.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isUnico ? 'Dividir Pago' : 'Pago Único (100%)',
                        style: AppTypography.small.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Título del selector de métodos (idéntico al prototipo)
          Text(
            'SELECCIONA EL MÉTODO',
            style: AppTypography.small.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppPalette.textSecondaryLight,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),

          // Grid de 5 Botones de Métodos (Borde constante de 1.5px y altura uniforme)
          _buildMetodosGrid(),
          const SizedBox(height: 14),

          // Detalle de distribución según modalidad
          if (isUnico)
            _buildPagoUnicoResumen(pagos)
          else
            _buildPagoDivididoInputs(pagos),
        ],
      ),
    );
  }

  Widget _buildMetodosGrid() {
    const metodosConfig = [
      {
        'nombre': 'Efectivo',
        'label': 'EFECTIVO',
        'icon': Icons.payments_rounded,
      },
      {
        'nombre': 'Debito',
        'label': 'DÉBITO',
        'icon': Icons.credit_card_rounded,
      },
      {
        'nombre': 'Credito',
        'label': 'CRÉDITO',
        'icon': Icons.credit_card_rounded,
      },
      {
        'nombre': 'Transferencia',
        'label': 'TRANSFERENCIA',
        'icon': Icons.swap_horiz_rounded,
      },
      {
        'nombre': 'Cheque',
        'label': 'CHEQUE',
        'icon': Symbols.checkbook_rounded,
      },
    ];

    return Row(
      children: metodosConfig.map((cfg) {
        final nombre = cfg['nombre'] as String;
        final label = cfg['label'] as String;
        final icon = cfg['icon'] as IconData;
        final isActive = widget.provider.esMetodoActivo(nombre);

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () {
                widget.provider.toggleMetodoPago(nombre);
                _sincronizarControllers();
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 2,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppPalette.tertiary
                      : AppPalette.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isActive
                        ? AppPalette.tertiary
                        : AppPalette.borderLight,
                    width: 1.5,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppPalette.tertiary.withValues(alpha: 0.25),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: isActive
                          ? Colors.white
                          : AppPalette.textSecondaryLight,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: AppTypography.small.copyWith(
                        color: isActive
                            ? Colors.white
                            : AppPalette.textPrimaryLight,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: 0.4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPagoUnicoResumen(List<TransaccionPagoItemModel> pagos) {
    final metodoNombre = pagos.isNotEmpty ? pagos.first.metodo : 'Efectivo';
    final monto = widget.provider.montoDeclarado;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppPalette.backgroundLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.borderLight),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppPalette.tertiary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getIconoMetodo(metodoNombre),
                    size: 20,
                    color: AppPalette.tertiary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Canal Activo: $metodoNombre',
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppPalette.textPrimaryLight,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Cubre el 100% del monto acordado',
                        style: AppTypography.small.copyWith(
                          fontSize: 13,
                          color: AppPalette.textSecondaryLight,
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
          const SizedBox(width: 8),
          Text(
            CobroPendienteCard.formatClp(monto),
            style: AppTypography.title.copyWith(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppPalette.tertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagoDivididoInputs(List<TransaccionPagoItemModel> pagos) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.backgroundLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DISTRIBUCIÓN DE MONTOS',
                style: AppTypography.small.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: AppPalette.textSecondaryLight,
                  letterSpacing: 0.5,
                ),
              ),
              if (widget.provider.diferenciaCuadratura > 0 && pagos.length > 1)
                InkWell(
                  onTap: () {
                    widget.provider.autoRellenarRestante(pagos.length - 1);
                    _sincronizarControllers();
                  },
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_fix_high_rounded,
                        size: 14,
                        color: AppPalette.tertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Auto-rellenar restante',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.tertiary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Inputs dinámicos para los métodos seleccionados
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pagos.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, idx) {
              final pago = pagos[idx];
              final ctrl = idx < _montoControllers.length
                  ? _montoControllers[idx]
                  : null;

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppPalette.surfaceLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppPalette.borderLight),
                ),
                child: Row(
                  children: [
                    // Badge del método con ancho uniforme (140px) para alinear todos los inputs
                    Container(
                      width: 140,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.tertiary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getIconoMetodo(pago.metodo),
                            size: 16,
                            color: AppPalette.tertiary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              pago.metodo,
                              style: AppTypography.body.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: AppPalette.tertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Input de monto
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [MilesTextInputFormatter()],
                        style: AppTypography.body.copyWith(
                          color: AppPalette.textPrimaryLight,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          prefixText: '\$ ',
                          prefixStyle: AppTypography.body.copyWith(
                            color: AppPalette.textPrimaryLight,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          hintText: '0',
                          hintStyle: AppTypography.body.copyWith(
                            color: AppPalette.textSecondaryLight.withValues(
                              alpha: 0.6,
                            ),
                            fontSize: 14,
                          ),
                          isDense: true,
                          filled: true,
                          fillColor: AppPalette.backgroundLight,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppPalette.borderLight,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: AppPalette.tertiary,
                              width: 2,
                            ),
                          ),
                        ),
                        onChanged: (val) {
                          final valInt = CurrencyFormatter.parse(val);
                          widget.provider.actualizarMontoMetodo(idx, valInt);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Botón Auto-rellenar
                    Tooltip(
                      message: 'Auto-rellenar este método',
                      child: IconButton(
                        icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                        color: AppPalette.tertiary,
                        style: IconButton.styleFrom(
                          backgroundColor: AppPalette.tertiary.withValues(
                            alpha: 0.1,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(8),
                        ),
                        onPressed: () {
                          widget.provider.autoRellenarRestante(idx);
                          _sincronizarControllers();
                        },
                      ),
                    ),

                    // Botón Eliminar si hay > 1 método
                    if (pagos.length > 1) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: 'Eliminar método',
                        child: IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          color: AppPalette.error,
                          style: IconButton.styleFrom(
                            backgroundColor: AppPalette.error.withValues(
                              alpha: 0.08,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.all(8),
                          ),
                          onPressed: () {
                            widget.provider.removerMetodoPago(idx);
                            _sincronizarControllers();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCuadraturaYAccion(
    BuildContext context,
    CobroPendienteModel orden,
  ) {
    final montoDeclarado = widget.provider.montoDeclarado;
    final diferencia = widget.provider.diferenciaCuadratura;
    final esValida = widget.provider.esCuadraturaValida;
    final isProcesando = widget.provider.isProcesandoCobro;

    final bool montoExcedido = widget.provider.esMontoExcedido;
    final bool montoInvalido = widget.provider.errorMontoAbono != null;
    final esLiquidacionTotal = widget.provider.esLiquidacionCompleta;
    final puedeProcesar = esValida && !montoExcedido && !montoInvalido;

    final bool operacionValida = esValida && !montoExcedido && !montoInvalido;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: operacionValida
              ? AppPalette.successBorder
              : AppPalette.errorBorder,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: (operacionValida ? AppPalette.success : AppPalette.error)
                .withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Resumen Financiero y Deducción Matemática
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.backgroundLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppPalette.borderLight),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Subtotal Bruto:',
                      style: AppTypography.small.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textSecondaryLight,
                      ),
                    ),
                    Text(
                      CobroPendienteCard.formatClp(orden.totalOperacion),
                      style: AppTypography.small.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textPrimaryLight,
                      ),
                    ),
                  ],
                ),
                if (orden.descuento > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Descuento a Favor:',
                        style: AppTypography.small.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFEF5350),
                        ),
                      ),
                      Text(
                        '- ${CobroPendienteCard.formatClp(orden.descuento)}',
                        style: AppTypography.small.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFEF5350),
                        ),
                      ),
                    ],
                  ),
                ],
                if (orden.abonoPrevio > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Abonos Previos Realizados:',
                        style: AppTypography.small.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: const Color.fromARGB(255, 253, 143, 0),
                        ),
                      ),
                      Text(
                        '- ${CobroPendienteCard.formatClp(orden.abonoPrevio)}',
                        style: AppTypography.small.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color.fromARGB(255, 253, 143, 0),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Divider(color: AppPalette.borderLight, height: 1),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      esLiquidacionTotal
                          ? 'TOTAL NETO A COBRAR:'
                          : 'ABONO A PROCESAR AHORA:',
                      style: AppTypography.small.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textPrimaryLight,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      CobroPendienteCard.formatClp(montoDeclarado),
                      style: AppTypography.title.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Píldora de Estado de Cuadratura
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: operacionValida
                  ? AppPalette.successBg
                  : AppPalette.errorBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  operacionValida
                      ? Icons.check_circle_rounded
                      : Icons.info_outline_rounded,
                  size: 16,
                  color: operacionValida
                      ? AppPalette.successText
                      : AppPalette.errorText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isProcesando
                        ? 'Registrando el cobro en el sistema...'
                        : montoExcedido
                        ? 'El monto a cobrar supera el saldo pendiente de la orden.'
                        : montoInvalido
                        ? (widget.provider.errorMontoAbono ??
                              'Monto de abono inválido.')
                        : esValida
                        ? (orden.esBackorder && esLiquidacionTotal
                              ? 'Cuadratura perfecta. Salda el 100% de la venta en verde (el vendedor asignará el activo físico).'
                              : (esLiquidacionTotal
                                    ? 'Cuadratura perfecta. Este cobro salda el 100% de la orden.'
                                    : 'Cuadratura perfecta para registrar este abono parcial.'))
                        : (diferencia > 0
                              ? 'Faltan ${CobroPendienteCard.formatClp(diferencia)} para cubrir el monto a cobrar.'
                              : 'Se han ingresado ${CobroPendienteCard.formatClp(diferencia.abs())} de más.'),
                    style: AppTypography.small.copyWith(
                      color: operacionValida
                          ? AppPalette.successText
                          : AppPalette.errorText,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Botón de Acción "Procesar Cobro"
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: operacionValida
                    ? AppPalette.success
                    : AppPalette.disabled,
                foregroundColor: operacionValida
                    ? AppPalette.textPrimary
                    : AppPalette.disabledText,
                disabledBackgroundColor: AppPalette.disabled,
                disabledForegroundColor: AppPalette.disabledText,
                elevation: operacionValida ? 2 : 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: isProcesando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(
                      operacionValida
                          ? Icons.check_circle_rounded
                          : Icons.lock_rounded,
                      size: 22,
                    ),
              label: Text(
                isProcesando
                    ? 'PROCESANDO PAGO...'
                    : montoExcedido
                    ? 'MONTO SUPERA EL SALDO PENDIENTE'
                    : montoInvalido
                    ? (widget.provider.errorMontoAbono?.toUpperCase() ??
                          'MONTO DE ABONO INVÁLIDO')
                    : !esValida
                    ? 'PAGO BLOQUEADO (DESCUADRE)'
                    : !esLiquidacionTotal
                    ? 'REGISTRAR ABONO PARCIAL'
                    : 'CONFIRMAR Y PROCESAR COBRO',
                style: AppTypography.button.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
              onPressed: (puedeProcesar && !isProcesando)
                  ? () => _handleProcesarCobro()
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorialAbonosSection(CobroPendienteModel orden) {
    if (orden.historialAbonos.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppPalette.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 18,
                    color: AppPalette.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'HISTORIAL DE ABONOS REGISTRADOS (${orden.historialAbonos.length})',
                    style: AppTypography.title.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textSecondaryLight,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Text(
                'Acumulado: ${CobroPendienteCard.formatClp(orden.abonoPrevio)}',
                style: AppTypography.small.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppPalette.primary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: orden.historialAbonos.length,
            separatorBuilder: (context, index) => Divider(
              color: AppPalette.borderLight.withValues(alpha: 0.6),
              height: 12,
            ),
            itemBuilder: (context, idx) {
              final abono = orden.historialAbonos[idx];
              final numAbono = idx + 1;

              return Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppPalette.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#$numAbono',
                      style: AppTypography.small.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppPalette.primary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    _getIconoMetodo(abono.metodoPago),
                    size: 16,
                    color: AppPalette.textSecondaryLight,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    abono.metodoPago,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: AppPalette.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '•  ${abono.fechaPagoFormateada} ${abono.horaPagoFormateada}',
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textSecondaryLight,
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '+${CobroPendienteCard.formatClp(abono.monto)}',
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppPalette.successText,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModalidadCobroSection(CobroPendienteModel orden) {
    final modalidad = widget.provider.modalidad;
    final isLiquidacion = modalidad == 'LIQUIDACION';
    final error = widget.provider.errorMontoAbono;
    final bool bloqueoLiquidacion = widget.provider.tieneBloqueoLiquidacionInicial;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: error != null
              ? AppPalette.errorBorder
              : AppPalette.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.tune_rounded,
                size: 18,
                color: AppPalette.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'MODALIDAD DE COBRO',
                style: AppTypography.title.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textSecondaryLight,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          if (bloqueoLiquidacion) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E8FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFDDD6FE)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 18,
                    color: Color(0xFF7E22CE),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Esta orden requiere un abono inicial acordado de ${CobroPendienteCard.formatClp(orden.abonoRequerido > 0 ? orden.abonoRequerido : (orden.pisoPrimerAbono > 0 ? orden.pisoPrimerAbono : orden.montoACobrar))}. La liquidación total no está permitida en este primer pago.',
                      style: AppTypography.small.copyWith(
                        color: const Color(0xFF6B21A8),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Selector Segmentado: Liquidar Saldo vs Abono Personalizado
          Row(
            children: [
              Expanded(
                child: bloqueoLiquidacion
                    ? Tooltip(
                        message:
                            'Esta orden requiere un abono inicial obligatorio. Liquidación total no permitida en el primer pago.',
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppPalette.backgroundLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppPalette.borderLight,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.lock_outline_rounded,
                                size: 16,
                                color: AppPalette.textSecondaryLight,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Liquidación Total',
                                  style: AppTypography.body.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: AppPalette.textSecondaryLight,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : InkWell(
                        onTap: () {
                          widget.provider.setModalidad('LIQUIDACION');
                          _sincronizarControllers();
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isLiquidacion
                                ? AppPalette.primary
                                : AppPalette.backgroundLight,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isLiquidacion
                                  ? AppPalette.primary
                                  : AppPalette.borderLight,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 16,
                                color: isLiquidacion
                                    ? Colors.white
                                    : AppPalette.textSecondaryLight,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Liquidación Total',
                                  style: AppTypography.body.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: isLiquidacion
                                        ? Colors.white
                                        : AppPalette.textPrimaryLight,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () {
                    widget.provider.setModalidad('ABONO');
                    _sincronizarControllers();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 10,
                    ),
                    decoration: BoxDecoration(
                      color: !isLiquidacion
                          ? AppPalette.tertiary
                          : AppPalette.backgroundLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: !isLiquidacion
                            ? AppPalette.tertiary
                            : AppPalette.borderLight,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.savings_rounded,
                          size: 16,
                          color: !isLiquidacion
                              ? Colors.white
                              : AppPalette.textSecondaryLight,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Abono Personalizado',
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: !isLiquidacion
                                  ? Colors.white
                                  : AppPalette.textPrimaryLight,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (!bloqueoLiquidacion && isLiquidacion && orden.abonoPrevio > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppPalette.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppPalette.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppPalette.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Se liquidará el saldo pendiente de ${CobroPendienteCard.formatClp(orden.saldoPendiente > 0 ? orden.saldoPendiente : orden.totalOperacion)}. Se solicitará confirmación al procesar el pago.',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Si es Abono Personalizado, desplegamos input para el monto
          if (!isLiquidacion) ...[
            const SizedBox(height: 16),
            Text(
              'MONTO A COBRAR',
              style: AppTypography.small.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppPalette.textSecondaryLight,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _montoAbonoPersonalizadoController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [MilesTextInputFormatter()],
                    style: AppTypography.title.copyWith(
                      color: error != null
                          ? AppPalette.error
                          : AppPalette.textPrimaryLight,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                    decoration: InputDecoration(
                      prefixText: '\$ ',
                      prefixStyle: AppTypography.title.copyWith(
                        color: error != null
                            ? AppPalette.error
                            : AppPalette.textPrimaryLight,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                      hintText: 'Ej: 50.000',
                      hintStyle: AppTypography.title.copyWith(
                        color: AppPalette.textSecondaryLight.withValues(
                          alpha: 0.5,
                        ),
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      filled: true,
                      fillColor: AppPalette.backgroundLight,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: error != null
                              ? AppPalette.errorBorder
                              : AppPalette.borderLight,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: error != null
                              ? AppPalette.error
                              : AppPalette.tertiary,
                          width: 2,
                        ),
                      ),
                    ),
                    onChanged: (val) {
                      final valInt = CurrencyFormatter.parse(val);
                      widget.provider.setMontoDeclarado(valInt);
                      _sincronizarControllers();
                    },
                  ),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 14,
                    color: AppPalette.error,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error,
                      style: AppTypography.small.copyWith(
                        color: AppPalette.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (orden.esPrimerAbono && orden.pisoPrimerAbono > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: AppPalette.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Piso comercial acordado para primer abono: ${CobroPendienteCard.formatClp(orden.pisoPrimerAbono)}',
                    style: AppTypography.small.copyWith(
                      color: AppPalette.tertiary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
