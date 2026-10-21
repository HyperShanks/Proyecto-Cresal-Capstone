import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/rut_formatter.dart';
import '../../../../core/utils/rut_validator.dart';
import '../../../auth/services/auth_service.dart';
import '../../controllers/cart_controller.dart';
import '../../models/cart_item_model.dart';
import '../../services/ordenes_service.dart';
import '../../services/carrito_service.dart';
import '../widgets/cart_item_tile.dart';
import '../widgets/venta_libre_dialog.dart';
import '../../../../core/constants/chile_geografia.dart';
import 'catalogo_screen.dart';

/// Pantalla Unificada de Carrito de Ventas y Micro-CRM (HU-3.3 + HU-3.4).
/// Integra el listado reactivo del Carrito Híbrido, formulario de datos de cliente,
/// opción de despacho a domicilio, consentimiento legal (Ley 21.719), notas a bodega
/// y barra fija de derivación a caja.
class CarritoScreen extends StatefulWidget {
  final VoidCallback? onOpenMenuDrawer;
  final VoidCallback? onNavigateToCatalogo;
  final http.Client? httpClient;

  const CarritoScreen({
    super.key,
    this.onOpenMenuDrawer,
    this.onNavigateToCatalogo,
    this.httpClient,
  });

  @override
  State<CarritoScreen> createState() => _CarritoScreenState();
}

class _CarritoScreenState extends State<CarritoScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controladores de Datos de Cliente
  final TextEditingController _rutController = TextEditingController();
  final TextEditingController _nombresController = TextEditingController();
  final TextEditingController _apellidosController = TextEditingController();
  final TextEditingController _telefonoController = TextEditingController();
  final FocusNode _rutFocusNode = FocusNode();

  // Controladores de Despacho y Entrega
  final TextEditingController _direccionDespachoController = TextEditingController();
  final TextEditingController _rutReceptorController = TextEditingController();
  final TextEditingController _nombresReceptorController = TextEditingController();
  final TextEditingController _telefonoReceptorController = TextEditingController();
  final TextEditingController _empresaTransporteController = TextEditingController(text: 'Chilexpress');
  final TextEditingController _montoAbonoController = TextEditingController();

  // Variables de Selección y Switches
  bool _esClienteAnonimo = false;
  String? _regionCliente;
  String? _comunaCliente;
  String? _regionDespacho;
  String? _comunaDespacho;
  String _tipoEntrega = 'Retiro'; // 'Retiro', 'Despacho', 'Traslado'
  int _idSucursalActual = 1; // 1: Viña del Mar, 2: Limache
  int _idSucursalDestino = 2; // 1: Viña del Mar, 2: Limache
  bool get _requiereDespacho => _tipoEntrega != 'Retiro';
  bool _isSubmitting = false;
  bool _isSearchingClient = false;
  int? _userRolId;
  bool get _esVendedorOnline => _userRolId == 7;
  List<VendedorModel> _vendedoresDisponibles = [];
  String? _idVendedorAsignado; // null => Mesón General (Todos)

  // Temporizadores para Reserva Concurrente (HU-03)
  Timer? _countdownTimer;
  Timer? _heartbeatTimer;
  int _segundosRestantes = 900; // 15 minutos base
  bool _isExtendingTime = false;

  @override
  void initState() {
    super.initState();
    _rutFocusNode.addListener(_onRutFocusChange);
    CartController.instance.addListener(_onCartChanged);
    _cargarVendedores();
    _cargarGeografiaDesdeBD();
    _iniciarCountdown();
  }

  Future<void> _cargarGeografiaDesdeBD() async {
    try {
      await OrdenesService.obtenerGeografia(client: widget.httpClient);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _cargarVendedores() async {
    try {
      final rolId = await AuthService.getIdRol();
      final sucursalId = await AuthService.getSucursalId();
      if (mounted) {
        setState(() {
          _userRolId = rolId;
          if (sucursalId != null && (sucursalId == 1 || sucursalId == 2)) {
            _idSucursalActual = sucursalId;
            _idSucursalDestino = (_idSucursalActual == 1) ? 2 : 1;
          }
        });
      }
      if (_esVendedorOnline) {
        final vends = await OrdenesService.obtenerVendedores(client: widget.httpClient);
        if (mounted) {
          setState(() {
            _vendedoresDisponibles = vends;
          });
        }
      }
    } catch (_) {}
  }

  void _onCartChanged() {
    final tieneInventariados = CartController.instance.items.any((i) => i.esInventariado);
    if (tieneInventariados) {
      if (_countdownTimer == null || !_countdownTimer!.isActive) {
        _iniciarCountdown();
      }
    } else {
      _countdownTimer?.cancel();
      _heartbeatTimer?.cancel();
    }
    if (CartController.instance.items.isEmpty) {
      _limpiarFormulario();
    }
  }

  void _iniciarCountdown() {
    _countdownTimer?.cancel();
    _heartbeatTimer?.cancel();

    final tieneInventariados = CartController.instance.items.any((i) => i.esInventariado);
    if (!tieneInventariados) {
      _segundosRestantes = 900;
      return;
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_segundosRestantes > 1) {
        setState(() {
          _segundosRestantes--;
        });
      } else {
        timer.cancel();
        _onReservaExpirada();
      }
    });

    // Heartbeat automático cada 3 minutos si hay repuestos en reserva
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _enviarHeartbeatSilencioso();
    });
  }

  void _enviarHeartbeatSilencioso() async {
    final tieneInventariados = CartController.instance.items.any((i) => i.esInventariado);
    if (!tieneInventariados) return;
    try {
      await CarritoService.heartbeat(client: widget.httpClient);
    } catch (_) {}
  }

  Future<void> _extenderTiempoReserva() async {
    setState(() {
      _isExtendingTime = true;
    });

    try {
      await CarritoService.heartbeat(client: widget.httpClient);
      if (!mounted) return;

      setState(() {
        _segundosRestantes = 900;
        _isExtendingTime = false;
      });

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppPalette.surface,
          duration: const Duration(seconds: 2),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: AppPalette.primary, size: 20),
              const SizedBox(width: 10),
              Text(
                'Tiempo de reserva extendido por 15 minutos más.',
                style: AppTypography.small.copyWith(color: AppPalette.textPrimary),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isExtendingTime = false;
      });
    }
  }

  void _onReservaExpirada() {
    _countdownTimer?.cancel();
    _heartbeatTimer?.cancel();

    // Vaciar el carrito y liberar reservas en backend
    CartController.instance.vaciarCarrito(liberarEnBackend: true);
    _limpiarFormulario();

    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppPalette.surface,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            const Icon(Icons.alarm_off, color: AppPalette.error, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tu tiempo de reserva ha finalizado por inactividad. Los artículos han sido devueltos al catálogo general.',
                style: AppTypography.small.copyWith(
                  color: AppPalette.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _heartbeatTimer?.cancel();
    CartController.instance.removeListener(_onCartChanged);
    _rutFocusNode.removeListener(_onRutFocusChange);
    _rutFocusNode.dispose();
    _rutController.dispose();
    _nombresController.dispose();
    _apellidosController.dispose();
    _telefonoController.dispose();
    _direccionDespachoController.dispose();
    _rutReceptorController.dispose();
    _nombresReceptorController.dispose();
    _telefonoReceptorController.dispose();
    _empresaTransporteController.dispose();
    _montoAbonoController.dispose();
    super.dispose();
  }

  /// Búsqueda y Autocompletado de Cliente por RUT al desenfocar el campo (Micro-CRM)
  void _onRutFocusChange() async {
    if (!_rutFocusNode.hasFocus) {
      final rut = _rutController.text.trim();
      if (rut.length >= 7) {
        setState(() {
          _isSearchingClient = true;
        });

        final cliente = await OrdenesService.buscarClientePorRut(rut, client: widget.httpClient);

        if (!mounted) return;

        setState(() {
          _isSearchingClient = false;
        });

        if (cliente != null) {
          setState(() {
            _nombresController.text = cliente['nombres']?.toString() ?? '';
            _apellidosController.text = cliente['apellidos']?.toString() ?? '';
            if (cliente['telefono'] != null && cliente['telefono'].toString().isNotEmpty) {
              _telefonoController.text = cliente['telefono'].toString();
            }
            final comuna = cliente['comuna']?.toString();
            if (comuna != null && comuna.isNotEmpty) {
              final reg = ChileGeografia.obtenerRegionDeComuna(comuna);
              if (reg != null) {
                _regionCliente = reg;
                _comunaCliente = comuna;
              } else {
                _comunaCliente = comuna;
              }
            }
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppPalette.surface,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              content: Row(
                children: [
                  const Icon(Icons.person_pin, color: AppPalette.secondary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cliente frecuente encontrado: ${cliente['nombres']} ${cliente['apellidos']}',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.secondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    }
  }

  void _limpiarFormulario() {
    _rutController.clear();
    _nombresController.clear();
    _apellidosController.clear();
    _telefonoController.clear();
    _direccionDespachoController.clear();
    _rutReceptorController.clear();
    _nombresReceptorController.clear();
    _telefonoReceptorController.clear();
    _empresaTransporteController.text = 'Chilexpress';
    _montoAbonoController.clear();
    setState(() {
      _esClienteAnonimo = false;
      _regionCliente = null;
      _comunaCliente = null;
      _regionDespacho = null;
      _comunaDespacho = null;
      _tipoEntrega = 'Retiro';
      _idSucursalDestino = (_idSucursalActual == 1 ? 2 : 1);
    });
  }

  void _confirmarVaciarCarrito(BuildContext context) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Vaciar Carrito', style: AppTypography.title),
        content: const Text(
          '¿Estás seguro de que deseas eliminar todos los productos del carrito?',
          style: AppTypography.small,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: AppTypography.button.copyWith(color: AppPalette.neutral),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'VACIAR',
              style: AppTypography.button.copyWith(color: AppPalette.error),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      CartController.instance.vaciarCarrito(liberarEnBackend: true);
      _limpiarFormulario();
      CatalogoScreen.refreshNotifier.value++;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppPalette.surface,
          content: Text('Carrito vaciado exitosamente'),
        ),
      );
    }
  }

  void _onDerivarACaja(BuildContext context) async {
    if (_isSubmitting) return;

    final cart = CartController.instance;

    // 1. Validar que el carrito no esté vacío
    if (cart.estaVacio || cart.totalMonto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppPalette.surface,
          content: Text(
            'El carrito debe contener al menos un producto con monto mayor a \$0',
            style: TextStyle(color: AppPalette.error),
          ),
        ),
      );
      return;
    }

    // 1.1. Validar que no existan repuestos con precios fuera de rango de tasación
    if (cart.hayPreciosInvalidos) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppPalette.surface,
          content: Text(
            'Hay repuestos con precio acordado fuera del rango permitido de tasación. Corrige los montos antes de derivar.',
            style: TextStyle(color: AppPalette.error),
          ),
        ),
      );
      return;
    }

    // 2. Validar Formulario
    if (_esClienteAnonimo || _rutController.text.trim() == '6.666.666-6' || _rutController.text.trim() == '66666666-6') {
      _rutController.text = '6.666.666-6';
      _nombresController.text = 'Consumidor';
      _apellidosController.text = 'Final';
      _regionCliente ??= 'Valparaíso';
      _comunaCliente ??= 'Viña del Mar';
    }

    final formValido = _esClienteAnonimo ? true : (_formKey.currentState?.validate() ?? false);

    if (!formValido) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppPalette.surface,
          content: Text(
            'Por favor completa todos los campos requeridos (*)',
            style: TextStyle(color: AppPalette.error),
          ),
        ),
      );
      return;
    }

    if (!_esClienteAnonimo && (_comunaCliente == null || _comunaCliente!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppPalette.surface,
          content: Text(
            'Por favor selecciona la Región y Comuna del cliente (*)',
            style: TextStyle(color: AppPalette.error),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      // 4. Mapear ítems al esquema OrdenCreateRequest
      final itemsPayload = cart.items.map((item) {
        if (item is InventariadoCartItem) {
          return <String, dynamic>{
            'id_activo': item.catalogoItem.idActivo,
            'notas_preparacion': item.notasPreparacion,
            'cantidad': item.cantidad,
            'precio_unitario': item.catalogoItem.precioReferencia,
            'precio_final': item.precioFinal,
          };
        } else if (item is VentaLibreCartItem) {
          return <String, dynamic>{
            'descripcion_manual': item.descripcion,
            'notas_preparacion': item.observacion,
            'cantidad': item.cantidad,
            'precio_unitario': item.monto,
            'precio_final': item.monto,
          };
        }
        return <String, dynamic>{};
      }).toList();

      // Validar datos de Despacho si aplica
      if (_tipoEntrega == 'Despacho') {
        if (_direccionDespachoController.text.trim().isEmpty ||
            _comunaDespacho == null ||
            _comunaDespacho!.trim().isEmpty ||
            _rutReceptorController.text.trim().isEmpty ||
            _nombresReceptorController.text.trim().isEmpty ||
            _telefonoReceptorController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppPalette.surface,
              content: Text(
                'Por favor completa todos los datos obligatorios del despacho (incluyendo Comuna) (*)',
                style: TextStyle(color: AppPalette.error),
              ),
            ),
          );
          return;
        }
      }

      int? abonoNum;
      if (_tipoEntrega == 'Retiro' && _montoAbonoController.text.trim().isNotEmpty) {
        abonoNum = CurrencyFormatter.parse(_montoAbonoController.text.trim());
      }

      Map<String, dynamic>? despachoPayload;
      if (_tipoEntrega == 'Despacho') {
        final idComuna = ChileGeografia.obtenerIdComuna(_comunaDespacho);
        despachoPayload = {
          'direccion_envio': _direccionDespachoController.text.trim(),
          'comuna_destino': _comunaDespacho,
          'id_comuna_destino': idComuna,
          'receptor_rut': _rutReceptorController.text.trim(),
          'receptor_nombres': _nombresReceptorController.text.trim(),
          'receptor_telefono': _telefonoReceptorController.text.trim(),
          'empresa_transporte': _empresaTransporteController.text.trim().isNotEmpty
              ? _empresaTransporteController.text.trim()
              : 'Chilexpress',
          'tipo_entrega': 'Despacho',
          'costo_envio': 0,
        };
      } else if (_tipoEntrega == 'Traslado') {
        final nombreDestino = _idSucursalDestino == 1 ? 'Viña del Mar' : 'Limache';
        final receptorRut = _rutReceptorController.text.trim().isNotEmpty
            ? _rutReceptorController.text.trim()
            : _rutController.text.trim();
        final receptorNom = _nombresReceptorController.text.trim().isNotEmpty
            ? _nombresReceptorController.text.trim()
            : '${_nombresController.text.trim()} ${_apellidosController.text.trim()}'.trim();
        final receptorTel = _telefonoReceptorController.text.trim().isNotEmpty
            ? _telefonoReceptorController.text.trim()
            : _telefonoController.text.trim();

        despachoPayload = {
          'direccion_envio': 'Traslado a Sucursal $nombreDestino',
          'comuna_destino': nombreDestino,
          'receptor_rut': receptorRut.isNotEmpty ? receptorRut : 'S/R',
          'receptor_nombres': receptorNom.isNotEmpty ? receptorNom : 'Cliente',
          'receptor_telefono': receptorTel.isNotEmpty ? receptorTel : '+56900000000',
          'tipo_entrega': 'Traslado',
          'id_sucursal_destino': _idSucursalDestino,
          'costo_envio': 0,
        };
      }

      final payload = <String, dynamic>{
        'cliente': {
          'rut_cliente': _rutController.text.trim(),
          'nombres': _nombresController.text.trim(),
          'apellidos': _apellidosController.text.trim(),
          'telefono': _telefonoController.text.trim().isNotEmpty
              ? _telefonoController.text.trim()
              : null,
          'comuna': _comunaCliente,
          'consentimiento_legal': true,
        },
        'requiere_despacho': _requiereDespacho,
        'tipo_entrega': _tipoEntrega,
        if (_esVendedorOnline && _idVendedorAsignado != null)
          'id_vendedor_asignado': _idVendedorAsignado,
        if (abonoNum != null && abonoNum > 0)
          'monto_abono': abonoNum,
        if (_tipoEntrega == 'Traslado')
          'id_sucursal_destino': _idSucursalDestino,
        'despacho': ?despachoPayload,
        'consentimiento_legal': true,
        'items': itemsPayload,
      };

      // 5. Enviar al Backend Transaccional FastAPI
      final ordenCreada = await OrdenesService.crearOrden(payload, client: widget.httpClient);

      if (!context.mounted) return;

      // 6. Modal de Éxito y Limpieza
      await _mostrarModalExito(context, ordenCreada);

      CartController.instance.vaciarCarrito();
      _limpiarFormulario();
      widget.onNavigateToCatalogo?.call();

    } catch (e) {
      if (!context.mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          content: Text(
            msg,
            style: AppTypography.small.copyWith(
              color: AppPalette.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _mostrarModalExito(BuildContext context, OrdenResponseModel orden) async {
    final folio = orden.folioDisplay;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icono de Éxito
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppPalette.success.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppPalette.success.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.task_alt,
                  size: 42,
                  color: AppPalette.success,
                ),
              ),
              const SizedBox(height: 18),

              // Folio de Orden
              Text(
                '¡ORDEN GENERADA!',
                style: AppTypography.headline.copyWith(
                  fontSize: 20,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppPalette.secondary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppPalette.secondary.withValues(alpha: 0.5)),
                ),
                child: Text(
                  'Folio: $folio',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.secondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Contenedor de Detalle de Cobro y Alerta
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppPalette.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    Text(
                      'Total a Pagar en Caja',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      orden.totalVentaFormateado,
                      style: AppTypography.headline.copyWith(
                        color: AppPalette.secondary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 16),
                    Text(
                      'Derive al cliente a la caja para realizar el pago. Se ha emitido la alerta de preparación a bodega.',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.textPrimary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(ctx).pop(),
              icon: const Icon(Icons.storefront, size: 20),
              label: Text(
                'Continuar al Catálogo',
                style: AppTypography.button.copyWith(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CartController.instance,
      builder: (context, _) {
        final cart = CartController.instance;

        return Scaffold(
          backgroundColor: AppPalette.background,
          appBar: AppBar(
            backgroundColor: AppPalette.background,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.menu, color: AppPalette.textPrimary),
              onPressed: widget.onOpenMenuDrawer,
              tooltip: 'Menú principal',
            ),
            title: Text('Carrito de Ventas', style: AppTypography.title),
            actions: [
              if (!cart.estaVacio) ...[
                if (!cart.tieneVentaEnVerde)
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: AppPalette.secondary),
                    onPressed: () => VentaLibreDialog.show(context),
                    tooltip: 'Agregar ítem manual',
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, color: AppPalette.error),
                  onPressed: () => _confirmarVaciarCarrito(context),
                  tooltip: 'Vaciar carrito',
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
          body: cart.estaVacio
              ? _buildEmptyState(context)
              : _buildUnifiedBody(context, cart),
          bottomNavigationBar: cart.estaVacio
              ? null
              : _buildCheckoutBar(context, cart),
        );
      },
    );
  }

  /// Vista de Estado Vacío
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppPalette.surface,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: const Icon(
                Icons.remove_shopping_cart_outlined,
                size: 42,
                color: AppPalette.neutral,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Tu carrito está vacío',
              style: AppTypography.headline.copyWith(fontSize: 22),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Agrega repuestos desde el catálogo o genera una venta libre de artículos misceláneos.',
              style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // Botón 1: Ir al Catálogo
            SizedBox(
              width: 220,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: widget.onNavigateToCatalogo,
                icon: const Icon(Icons.storefront, size: 20),
                label: const Text('Explorar Catálogo'),
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
            const SizedBox(height: 12),

            // Botón 2: Venta Libre
            SizedBox(
              width: 220,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => VentaLibreDialog.show(context),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Venta Libre / Misceláneo'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.secondary,
                  side: const BorderSide(color: AppPalette.secondary, width: 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Banner de Countdown de Reserva Temporal (HU-03)
  Widget _buildReservationCountdownBanner(CartController cart) {
    final tieneInventariados = cart.items.any((i) => i.esInventariado);
    if (!tieneInventariados) return const SizedBox.shrink();

    final minutos = _segundosRestantes ~/ 60;
    final segundos = _segundosRestantes % 60;
    final tiempoStr = '${minutos.toString().padLeft(2, '0')}:${segundos.toString().padLeft(2, '0')}';

    final bool esUrgente = _segundosRestantes < 180; // Menos de 3 minutos
    final Color colorBanner = esUrgente ? AppPalette.error : AppPalette.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: colorBanner.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10.0),
        border: Border.all(
          color: colorBanner.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            esUrgente ? Icons.hourglass_bottom_rounded : Icons.timer_outlined,
            color: colorBanner,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Reserva Temporal Activa',
                  style: AppTypography.small.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorBanner,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'Expira en: $tiempoStr minutos',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _isExtendingTime ? null : _extenderTiempoReserva,
            icon: _isExtendingTime
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh, size: 16),
            label: const Text('Extender'),
            style: TextButton.styleFrom(
              foregroundColor: colorBanner,
              textStyle: AppTypography.small.copyWith(fontWeight: FontWeight.bold),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            ),
          ),
        ],
      ),
    );
  }

  /// Cuerpo Continuo: Lista de Carrito + Formulario Micro-CRM
  Widget _buildUnifiedBody(BuildContext context, CartController cart) {
    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 40.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. Encabezado del Carrito ───────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Carrito de Compras',
                        style: AppTypography.headline.copyWith(fontSize: 20),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Revisa tus activos y finaliza la venta',
                        style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                  decoration: BoxDecoration(
                    color: AppPalette.surface,
                    borderRadius: BorderRadius.circular(20.0),
                    border: Border.all(
                      color: AppPalette.primary.withValues(alpha: 0.4),
                      width: 1.0,
                    ),
                  ),
                  child: Text(
                    '${cart.totalItems} ${cart.totalItems == 1 ? 'Ítem' : 'Ítems'}',
                    style: AppTypography.small.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppPalette.primary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Banner de Countdown de Reserva Temporal (HU-03) ───────────────
            _buildReservationCountdownBanner(cart),
            const SizedBox(height: 8),

            // ── 2. Lista de Productos (shrinkWrap: true) ────────────────────
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cart.items.length,
              itemBuilder: (ctx, index) {
                final item = cart.items[index];
                return CartItemTile(
                  key: ValueKey(item.id),
                  item: item,
                );
              },
            ),
            const SizedBox(height: 8),

            // ── 3. Botón de Ancho Completo: Añadir Ítem No Inventariado / Banner Venta en Verde ─────
            if (!cart.tieneVentaEnVerde) ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => VentaLibreDialog.show(context),
                  icon: const Icon(Icons.add, color: AppPalette.secondary, size: 20),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '+ Añadir Ítem No Inventariado / Misceláneo',
                      style: AppTypography.button.copyWith(
                        color: AppPalette.secondary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppPalette.secondary.withValues(alpha: 0.4),
                      width: 1.2,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    backgroundColor: AppPalette.surface.withValues(alpha: 0.4),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppPalette.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppPalette.secondary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bookmark_added, color: AppPalette.secondary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Pedido con Venta en Verde (Reserva por encargo). Las compras en verde se tramitan de forma exclusiva e individual sin otros repuestos.',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textPrimary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── 4. Tarjeta 1: DATOS POST-VENTA CLIENTE ──────────────────────
            _buildCardContainer(
              icon: Icons.person_outline,
              title: 'DATOS POST-VENTA CLIENTE',
              children: [
                // Switch / Acción Rápida: Consumidor Final (Sin RUT)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
                  decoration: BoxDecoration(
                    color: AppPalette.background,
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.no_accounts_outlined,
                              size: 20,
                              color: _esClienteAnonimo ? AppPalette.secondary : AppPalette.textSecondary,
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                'Consumidor Final (Sin RUT)',
                                style: AppTypography.body.copyWith(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _esClienteAnonimo ? AppPalette.secondary : AppPalette.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        key: const Key('switch_cliente_anonimo'),
                        value: _esClienteAnonimo,
                        activeThumbColor: AppPalette.secondary,
                        onChanged: (val) {
                          setState(() {
                            _esClienteAnonimo = val;
                            if (val) {
                              _rutController.text = '6.666.666-6';
                              _nombresController.text = 'Consumidor';
                              _apellidosController.text = 'Final';
                              _telefonoController.clear();
                              _regionCliente = 'Valparaíso';
                              _comunaCliente = 'Viña del Mar';
                            } else {
                              _rutController.clear();
                              _nombresController.clear();
                              _apellidosController.clear();
                              _telefonoController.clear();
                              _regionCliente = null;
                              _comunaCliente = null;
                            }
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                if (_esClienteAnonimo) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: AppPalette.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(
                        color: AppPalette.secondary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: AppPalette.secondary,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Aviso: El cliente solo podrá pagar y retirar en caja presentando su Número de Orden.',
                            style: AppTypography.small.copyWith(
                              color: AppPalette.secondary,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  _buildTextField(
                    controller: _rutController,
                    focusNode: _rutFocusNode,
                    label: 'RUT Cliente *',
                    hint: '12.345.678-9',
                    isRequired: !_esClienteAnonimo,
                    keyboardType: TextInputType.text,
                    inputFormatters: [RutFormatter()],
                    validator: (val) {
                      if (!_esClienteAnonimo) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Campo requerido';
                        }
                        if (!RutValidator.isValid(val)) {
                          return 'RUT inválido. Verifique el número ingresado.';
                        }
                      }
                      return null;
                    },
                    suffixIcon: _isSearchingClient
                        ? const Padding(
                            padding: EdgeInsets.all(12.0),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppPalette.secondary,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _nombresController,
                          label: 'Nombres *',
                          hint: 'Juan',
                          isRequired: !_esClienteAnonimo,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _apellidosController,
                          label: 'Apellidos *',
                          hint: 'Pérez',
                          isRequired: !_esClienteAnonimo,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _telefonoController,
                    label: 'Teléfono',
                    hint: '+56 9 1234 5678',
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdown(
                          label: 'Región Cliente *',
                          value: _regionCliente,
                          hint: 'Seleccione Región...',
                          items: ChileGeografia.regiones,
                          onChanged: (val) {
                            setState(() {
                              _regionCliente = val;
                              _comunaCliente = null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildDropdown(
                          label: 'Comuna Cliente *',
                          value: _comunaCliente,
                          hint: (_regionCliente != null && _regionCliente!.isNotEmpty)
                              ? 'Seleccione Comuna...'
                              : 'Seleccione región primero',
                          enabled: _regionCliente != null && _regionCliente!.isNotEmpty,
                          items: (_regionCliente != null && _regionCliente!.isNotEmpty)
                              ? ChileGeografia.obtenerComunas(_regionCliente)
                              : const [],
                          onChanged: (val) {
                            setState(() => _comunaCliente = val);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // ── 5. Tarjeta 2: MODALIDAD DE ENTREGA / DESPACHO ───────────────
            _buildCardContainer(
              icon: Icons.local_shipping_outlined,
              title: 'MODALIDAD DE ENTREGA',
              children: [
                // Selector de 3 Opciones: Retiro, Despacho, Traslado
                Row(
                  children: [
                    _buildDeliveryOptionChip('Retiro en Tienda', 'Retiro', Icons.storefront_outlined),
                    const SizedBox(width: 8),
                    _buildDeliveryOptionChip('Despacho a Domicilio', 'Despacho', Icons.local_shipping_outlined),
                    const SizedBox(width: 8),
                    _buildDeliveryOptionChip('Traslado a otra sucursal', 'Traslado', Icons.sync_alt_outlined),
                  ],
                ),
                const SizedBox(height: 16),

                if (_tipoEntrega == 'Retiro') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: AppPalette.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18, color: AppPalette.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'El cliente retirará los repuestos directamente en el mesón de atención tras completar el pago en caja.',
                            style: AppTypography.small.copyWith(
                              color: AppPalette.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _montoAbonoController,
                    label: 'Monto de Abono / Anticipo (Opcional)',
                    hint: 'Ej: 50.000 (Dejar vacío si liquidará el 100% en caja)',
                    keyboardType: TextInputType.number,
                    inputFormatters: [MilesTextInputFormatter()],
                  ),
                ] else if (_tipoEntrega == 'Despacho') ...[
                  const Divider(color: Colors.white10, height: 16),
                  _buildTextField(
                    controller: _direccionDespachoController,
                    label: 'Dirección de Envío *',
                    hint: 'Av. Libertad 1234, Depto 402',
                    isRequired: true,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdown(
                          label: 'Región Destino *',
                          value: _regionDespacho,
                          hint: 'Seleccione Región...',
                          items: ChileGeografia.regiones,
                          onChanged: (val) {
                            setState(() {
                              _regionDespacho = val;
                              _comunaDespacho = null;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildDropdown(
                          label: 'Comuna Destino *',
                          value: _comunaDespacho,
                          hint: (_regionDespacho != null && _regionDespacho!.isNotEmpty)
                              ? 'Seleccione Comuna...'
                              : 'Seleccione región primero',
                          enabled: _regionDespacho != null && _regionDespacho!.isNotEmpty,
                          items: (_regionDespacho != null && _regionDespacho!.isNotEmpty)
                              ? ChileGeografia.obtenerComunas(_regionDespacho)
                              : const [],
                          onChanged: (val) {
                            setState(() => _comunaDespacho = val);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _empresaTransporteController,
                    label: 'Empresa de Transporte *',
                    hint: 'Chilexpress / Starken',
                    isRequired: true,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _rutReceptorController,
                          label: 'RUT Receptor *',
                          hint: '12.345.678-9',
                          isRequired: true,
                          inputFormatters: [RutFormatter()],
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Campo requerido';
                            }
                            if (!RutValidator.isValid(val)) {
                              return 'RUT inválido. Verifique el número ingresado.';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _nombresReceptorController,
                          label: 'Nombres Receptor *',
                          hint: 'Pedro González',
                          isRequired: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _telefonoReceptorController,
                    label: 'Teléfono Receptor *',
                    hint: '+56 9 8765 4321',
                    isRequired: true,
                    keyboardType: TextInputType.phone,
                  ),
                ] else if (_tipoEntrega == 'Traslado') ...[
                  const Divider(color: Colors.white10, height: 16),
                  // Selector de Sucursal Destino (Viña del Mar / Limache)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14.0),
                    decoration: BoxDecoration(
                      color: AppPalette.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppPalette.secondary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.swap_horiz, size: 18, color: AppPalette.secondary),
                            const SizedBox(width: 8),
                            Text(
                              'SELECCIONA SUCURSAL DESTINO *',
                              style: AppTypography.small.copyWith(
                                color: AppPalette.secondary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppPalette.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppPalette.primary.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.storefront_outlined, size: 16, color: AppPalette.primary),
                              const SizedBox(width: 6),
                              Text(
                                'Sucursal actual (Origen): ${_idSucursalActual == 1 ? "Viña del Mar" : "Limache"}',
                                style: AppTypography.small.copyWith(color: AppPalette.primary, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildDropdown(
                          label: 'Sucursal de Destino',
                          value: _idSucursalDestino == 1 ? 'Viña del Mar' : 'Limache',
                          hint: 'Seleccionar sucursal de destino',
                          items: [_idSucursalActual == 1 ? 'Limache' : 'Viña del Mar'],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _idSucursalDestino = val == 'Viña del Mar' ? 1 : 2;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'ℹ️ Se generará la tarea de traslado logístico asignada a bodega para el envío desde ${_idSucursalActual == 1 ? "Viña del Mar" : "Limache"} hacia ${_idSucursalDestino == 1 ? "Viña del Mar" : "Limache"}.',
                          style: AppTypography.small.copyWith(
                            color: AppPalette.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _rutReceptorController,
                          label: 'RUT Quien Retira en Destino',
                          hint: '11.222.333-4',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _nombresReceptorController,
                          label: 'Nombre Quien Retira',
                          hint: 'Ej: Juan Pérez',
                        ),
                      ),
                    ],
                  ),
                ],
                if (_esVendedorOnline) ...[
                  const SizedBox(height: 14),
                  // Selector de Responsable de Entrega / Despacho (Solo VendedorOnline)
                  Text(
                    'Responsable de Entrega/Despacho en Sucursal',
                    style: AppTypography.small.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppPalette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppPalette.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _idVendedorAsignado,
                        dropdownColor: AppPalette.surface,
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_drop_down, color: AppPalette.primary),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Mesón General (Todos los vendedores)'),
                          ),
                          ..._vendedoresDisponibles.map(
                            (v) => DropdownMenuItem<String?>(
                              value: v.idUsuario,
                              child: Text('Vendedor: ${v.nombreCompleto} (${v.rut})'),
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _idVendedorAsignado = val;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Contenedor Modular Flat Design para Tarjetas
  Widget _buildCardContainer({
    required IconData icon,
    required String title,
    Widget? trailing,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppPalette.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.cardTitle.copyWith(
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  /// Chip interactivo para selección de Modalidad de Entrega (Retiro, Despacho, Traslado)
  Widget _buildDeliveryOptionChip(String label, String value, IconData icon) {
    final bool isSelected = _tipoEntrega == value;
    return Expanded(
      child: Material(
        color: isSelected
            ? AppPalette.primary.withValues(alpha: 0.15)
            : AppPalette.background,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: Key('chip_entrega_$value'),
          onTap: () {
            setState(() {
              _tipoEntrega = value;
              if (value == 'Traslado') {
                if (_idSucursalDestino == _idSucursalActual) {
                  _idSucursalDestino = (_idSucursalActual == 1 ? 2 : 1);
                }
              }
            });
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(minHeight: 68),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? AppPalette.primary : Colors.white10,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? AppPalette.primary : AppPalette.textSecondary,
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppTypography.small.copyWith(
                      color: isSelected ? AppPalette.primary : AppPalette.textSecondary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Campo de Texto Minimalista
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool isRequired = false,
    TextInputType keyboardType = TextInputType.text,
    FocusNode? focusNode,
    Widget? suffixIcon,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.body.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: AppTypography.body.copyWith(fontSize: 14.5, color: Colors.white),
          validator: validator ??
              (isRequired
                  ? (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Campo requerido';
                      }
                      return null;
                    }
                  : null),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 14,
            ),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: AppPalette.background,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: const BorderSide(
                color: Color(0xFF334155),
                width: 1.0,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: const BorderSide(
                color: Color(0xFF334155),
                width: 1.0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: const BorderSide(
                color: AppPalette.primary,
                width: 1.5,
              ),
            ),
            errorStyle: const TextStyle(color: AppPalette.error, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  /// Dropdown Minimalista con soporte para deshabilitado y selección condicional
  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String? hint,
    bool enabled = true,
  }) {
    final effectiveValue = items.contains(value) ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.body.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: enabled
                ? Colors.white
                : Colors.white38,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: effectiveValue,
          hint: hint != null
              ? Text(
                  hint,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                    fontSize: 14,
                  ),
                )
              : null,
          dropdownColor: AppPalette.surface,
          style: AppTypography.body.copyWith(
            fontSize: 14,
            color: enabled ? Colors.white : Colors.white38,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: enabled
                ? AppPalette.background
                : AppPalette.background.withValues(alpha: 0.4),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: const BorderSide(
                color: Color(0xFF334155),
                width: 1.0,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: const BorderSide(
                color: Color(0xFF334155),
                width: 1.0,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),
          items: enabled
              ? items.map((item) {
                  return DropdownMenuItem(
                    value: item,
                    child: Text(
                      item,
                      style: AppTypography.body.copyWith(fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList()
              : const [],
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }

  /// Barra Inferior Fija (Derivar a Caja)
  Widget _buildCheckoutBar(BuildContext context, CartController cart) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20.0, 12.0, 20.0, 16.0),
      decoration: const BoxDecoration(
        color: AppPalette.surface,
        border: Border(
          top: BorderSide(
            color: Colors.white10,
            width: 1.0,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cart.hayPreciosInvalidos) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppPalette.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppPalette.error.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: AppPalette.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Corrige los precios fuera de rango para continuar',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.error,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              children: [
                // Total Carrito
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'TOTAL CARRITO:',
                        style: AppTypography.small.copyWith(
                          fontSize: 10,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.bold,
                          color: AppPalette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          cart.totalMontoFormateado,
                          style: AppTypography.headline.copyWith(
                            color: AppPalette.secondary,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Botón Derivar a Caja (>= 48px, Verde corporativo)
                Flexible(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: (!_isSubmitting && cart.totalMonto > 0 && !cart.hayPreciosInvalidos)
                          ? () => _onDerivarACaja(context)
                          : null,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppPalette.textPrimary,
                          ),
                        )
                      : const Icon(
                          Icons.send,
                          size: 18,
                          color: AppPalette.textPrimary,
                        ),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _isSubmitting ? 'Procesando...' : 'Derivar a Caja',
                      style: AppTypography.button.copyWith(
                        color: AppPalette.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.success,
                    foregroundColor: AppPalette.textPrimary,
                    disabledBackgroundColor: AppPalette.surface,
                    disabledForegroundColor: AppPalette.neutral,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  ),
);
  }
}
