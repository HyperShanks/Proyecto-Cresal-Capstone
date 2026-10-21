import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../services/ordenes_service.dart';
import '../../services/ordenes_sync_notifier.dart';

/// Diálogo modal interactivo para reasignar la titularidad comercial de una orden a otro vendedor.
class DialogoReasignarVendedor extends StatefulWidget {
  final String idOrden;
  final String folio;
  final String? idVendedorActual;
  final String? nombreVendedorActual;
  final http.Client? client;
  final VoidCallback? onReasignadoExitoso;
  final int duracionSegundos;

  const DialogoReasignarVendedor({
    super.key,
    required this.idOrden,
    required this.folio,
    this.idVendedorActual,
    this.nombreVendedorActual,
    this.client,
    this.onReasignadoExitoso,
    this.duracionSegundos = 5,
  });

  static Future<bool?> mostrar(
    BuildContext context, {
    required String idOrden,
    required String folio,
    String? idVendedorActual,
    String? nombreVendedorActual,
    http.Client? client,
    VoidCallback? onReasignadoExitoso,
    int duracionSegundos = 5,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DialogoReasignarVendedor(
        idOrden: idOrden,
        folio: folio,
        idVendedorActual: idVendedorActual,
        nombreVendedorActual: nombreVendedorActual,
        client: client,
        onReasignadoExitoso: onReasignadoExitoso,
        duracionSegundos: duracionSegundos,
      ),
    );
  }

  @override
  State<DialogoReasignarVendedor> createState() =>
      _DialogoReasignarVendedorState();
}

class _DialogoReasignarVendedorState extends State<DialogoReasignarVendedor> {
  List<VendedorModel> _vendedores = [];
  VendedorModel? _vendedorSeleccionado;
  bool _cargandoVendedores = true;
  bool _enviando = false;
  String? _errorMessage;

  late int _segundosRestantes;
  Timer? _timer;
  bool _heLeidoConfirmacion = false;

  @override
  void initState() {
    super.initState();
    _segundosRestantes = widget.duracionSegundos;
    if (_segundosRestantes > 0) {
      _iniciarTemporizador();
    }
    _cargarVendedores();
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
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _cargarVendedores() async {
    setState(() {
      _cargandoVendedores = true;
      _errorMessage = null;
    });

    try {
      final list = await OrdenesService.obtenerVendedores(client: widget.client);
      if (!mounted) return;

      // Filtrar al vendedor actual si se proporcionó su ID
      final disponibles = list.where((v) {
        if (widget.idVendedorActual != null &&
            widget.idVendedorActual!.isNotEmpty) {
          return v.idUsuario.toLowerCase() !=
              widget.idVendedorActual!.toLowerCase();
        }
        return true;
      }).toList();

      setState(() {
        _vendedores = disponibles;
        _cargandoVendedores = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoVendedores = false;
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      });
    }
  }

  Future<void> _ejecutarReasignacion() async {
    if (_vendedorSeleccionado == null) {
      setState(() {
        _errorMessage = 'Por favor selecciona al nuevo vendedor titular.';
      });
      return;
    }

    setState(() {
      _enviando = true;
      _errorMessage = null;
    });

    try {
      final res = await OrdenesService.reasignarVendedor(
        idOrden: widget.idOrden,
        idNuevoVendedor: _vendedorSeleccionado!.idUsuario,
        motivo: null,
        client: widget.client,
      );

      if (!mounted) return;

      widget.onReasignadoExitoso?.call();
      OrdenesSyncNotifier.instance.notificarCambio();

      final mensaje = res['mensaje'] as String? ??
          'Venta transferida exitosamente a ${_vendedorSeleccionado!.nombreCompleto}.';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(mensaje)),
            ],
          ),
          backgroundColor: AppPalette.success,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(
          color: AppPalette.secondary.withValues(alpha: 0.3),
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
              color: AppPalette.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.swap_horiz_rounded,
              color: AppPalette.secondary,
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
                  'Reasignar Venta',
                  style: AppTypography.title.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Orden: ${widget.folio}',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.secondary,
                    fontWeight: FontWeight.w600,
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Banner de Advertencia Clara
            Container(
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
                          'ADVERTENCIA: TRASPASO DE TITULARIDAD',
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
                  const SizedBox(height: 6),
                  Text(
                    _vendedorSeleccionado?.esLimache == true
                        ? 'Al reasignar esta orden a Limache, la comisión comercial se atribuirá a dicho perfil, pero la orden PERMANECERÁ en tu listado de "Mis Órdenes" con la etiqueta [📍 Asignada a Limache] para tu seguimiento operativo.'
                        : 'Al transferir esta orden, la titularidad y comisiones pasarán al vendedor seleccionado. Esta venta dejará de figurar en tu listado de "Mis Órdenes".',
                    style: AppTypography.small.copyWith(
                      color: const Color(0xFFFDE68A),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (widget.nombreVendedorActual != null &&
                widget.nombreVendedorActual!.isNotEmpty) ...[
              Text(
                'Vendedor actual: ${widget.nombreVendedorActual}',
                style: AppTypography.small.copyWith(
                  color: AppPalette.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
            ],

            Text(
              'Seleccionar Nuevo Vendedor Titular:',
              style: AppTypography.small.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 6),

            if (_cargandoVendedores)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_vendedores.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppPalette.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'No hay otros vendedores disponibles en la sucursal.',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondary,
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppPalette.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<VendedorModel>(
                    key: const Key('dropdown_reasignar_vendedor'),
                    value: _vendedorSeleccionado,
                    isExpanded: true,
                    dropdownColor: AppPalette.surface,
                    hint: Text(
                      '-- Selecciona vendedor --',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.textSecondary,
                      ),
                    ),
                    items: _vendedores.map((v) {
                      return DropdownMenuItem<VendedorModel>(
                        value: v,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: v.esLimache
                                    ? const Color(0xFFD97706).withValues(alpha: 0.2)
                                    : AppPalette.secondary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                v.etiquetaRol,
                                style: TextStyle(
                                  color: v.esLimache
                                      ? const Color(0xFFF59E0B)
                                      : AppPalette.secondary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                v.nombreCompleto,
                                style: AppTypography.body.copyWith(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: _enviando
                        ? null
                        : (val) {
                            setState(() {
                              _vendedorSeleccionado = val;
                              _errorMessage = null;
                            });
                          },
                  ),
                ),
              ),

            // Casilla de verificación obligatoria (He leído...)
            InkWell(
              key: const Key('check_confirmar_reasignacion_tap'),
              onTap: _enviando
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
                        ? AppPalette.secondary
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
                        key: const Key('check_confirmar_reasignacion'),
                        value: _heLeidoConfirmacion,
                        activeColor: AppPalette.secondary,
                        checkColor: Colors.black,
                        side: const BorderSide(color: Colors.white54, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                        onChanged: _enviando
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
                        'He leído y confirmo el traspaso comercial y de comisiones a este vendedor.',
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
                  border: Border.all(
                    color: AppPalette.error.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: AppPalette.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: AppTypography.small.copyWith(
                          color: AppPalette.error,
                          fontSize: 11.5,
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
        // Botones en columna con ancho completo (Extend) para evitar overflow de píxeles en móviles estrechos (320px)
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(
              builder: (context) {
                final bool tiempoCumplido = _segundosRestantes == 0;
                final bool puedeConfirmar = !_enviando &&
                    !_cargandoVendedores &&
                    tiempoCumplido &&
                    _heLeidoConfirmacion &&
                    _vendedorSeleccionado != null;

                String textoBoton;
                if (_enviando) {
                  textoBoton = 'REASIGNANDO...';
                } else if (!tiempoCumplido) {
                  textoBoton = 'CONFIRMAR (${_segundosRestantes}s)';
                } else {
                  textoBoton = 'CONFIRMAR REASIGNACIÓN';
                }

                return SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    key: const Key('btn_confirmar_reasignacion'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.secondary,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: Colors.white12,
                      disabledForegroundColor: Colors.white38,
                      elevation: puedeConfirmar ? 2 : 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: _enviando
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.black),
                            ),
                          )
                        : (!tiempoCumplido
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppPalette.secondary,
                                ),
                              )
                            : const Icon(Icons.check, size: 18)),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        textoBoton,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    onPressed: puedeConfirmar ? _ejecutarReasignacion : null,
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
                onPressed: _enviando
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Cancelar'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
