import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/rut_formatter.dart';
import '../../../../core/utils/rut_validator.dart';
import '../../../auth/services/auth_service.dart';
import '../../controllers/cart_controller.dart';
import '../../models/cart_item_model.dart';
import '../../models/checkout_wizard_models.dart';
import '../../controllers/checkout_wizard_controller.dart';
import '../../services/ordenes_service.dart';
import '../../services/ordenes_sync_notifier.dart';
import '../widgets/modal_backorder_form.dart';
import '../widgets/cart_item_tile.dart';
import '../widgets/venta_libre_dialog.dart';
import '../../../../core/constants/chile_geografia.dart';
import 'catalogo_screen.dart';
import '../widgets/dialogo_advertencia_consumidor_final.dart';
import '../../../../core/widgets/glass_snackbar.dart';

/// Pantalla Principal del Checkout Wizard por 5 Pasos Secuenciales (SPEC-HU-05)
/// Integra Carrito Híbrido, Micro-CRM con Consumidor Final, Logística (Retiro/Despacho/Traslado) y Abonos.
class CheckoutWizardScreen extends StatefulWidget {
  final VoidCallback? onOpenMenuDrawer;
  final VoidCallback? onNavigateToCatalogo;
  final List<Map<String, dynamic>>? initialInventario;
  final List<ItemManualModel>? initialManuales;

  const CheckoutWizardScreen({
    super.key,
    this.onOpenMenuDrawer,
    this.onNavigateToCatalogo,
    this.initialInventario,
    this.initialManuales,
  });

  @override
  State<CheckoutWizardScreen> createState() => _CheckoutWizardScreenState();
}

class _CheckoutWizardScreenState extends State<CheckoutWizardScreen> {
  final CheckoutWizardController _controller = CheckoutWizardController();

  // Controladores Paso 2 (Micro-CRM)
  final _rutController = TextEditingController();
  final _clienteNombresController = TextEditingController();
  final _clienteApellidosController = TextEditingController();
  final _clienteTelefonoController = TextEditingController();
  final _clienteEmailController = TextEditingController();
  final FocusNode _rutFocusNode = FocusNode();
  bool _isSearchingCliente = false;
  bool _esClienteAnonimo = false;
  String? _regionCliente;
  String? _comunaCliente;

  // Controladores Paso 3 (Logística & Despacho / Traslado)
  final _direccionController = TextEditingController();
  final _receptorNombresController = TextEditingController();
  final _receptorRutController = TextEditingController();
  final _receptorTelefonoController = TextEditingController();
  final _empresaTransporteController = TextEditingController(
    text: 'Chilexpress',
  );
  String? _comunaDespacho;
  int _idSucursalActual = 1; // 1: Viña del Mar, 2: Limache
  int _idSucursalDestino = 2; // Por defecto a la otra sucursal
  int? _userRolId;
  String? _currentUserId;
  bool get _esVendedorOnline => _userRolId == 7;
  bool get _esJefeDeVentas =>
      _userRolId == 6 || _userRolId == 1 || _userRolId == 5;
  bool get _esVendedor => _userRolId == 2;
  bool get _puedeAsignarVenta =>
      (_esJefeDeVentas || _esVendedor) && !_esVendedorOnline;
  List<VendedorModel> _vendedoresDisponibles = [];
  String? _idVendedorAsignado;
  bool _esVentaReferida = false;
  String? _idVendedorTitular;

  bool get _tieneVentaEnVerde => _controller.tieneVentaEnVerde;

  void _verificarYDesmarcarConsumidorFinalSiAplica() {
    if (_tieneVentaEnVerde && _esClienteAnonimo) {
      _esClienteAnonimo = false;
      if (_rutController.text.trim() == '6.666.666-6' ||
          _clienteNombresController.text.trim().toUpperCase() == 'CONSUMIDOR') {
        _rutController.clear();
        _clienteNombresController.clear();
        _clienteApellidosController.clear();
        _clienteTelefonoController.clear();
        _clienteEmailController.clear();
        _regionCliente = null;
        _comunaCliente = null;
        _controller.setCliente(null);
      }
    }
  }

  // Controladores Paso 4 (Comercial / Abonos / Descuentos)
  final _montoAbonoController = TextEditingController();
  final _descuentoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerUpdate);
    CartController.instance.addListener(_sincronizarDesdeCartController);
    _rutFocusNode.addListener(_onRutFocusChange);

    _sincronizarDesdeCartController();
    _cargarRolYVendedores();
    _cargarGeografiaDesdeBD();

    // Cargar ítems iniciales directos si se pasan por parámetro
    if (widget.initialInventario != null) {
      for (final item in widget.initialInventario!) {
        _controller.addItemInventariado(
          idActivo: item['id_activo']?.toString() ?? '',
          sku:
              item['sku']?.toString() ??
              item['sku_qr_fisico']?.toString() ??
              'SKU-00',
          descripcion: item['descripcion']?.toString() ?? 'Repuesto',
          precio: int.tryParse(item['precio']?.toString() ?? '0') ?? 0,
          pasillo:
              item['pasillo']?.toString() ??
              item['ubicacion_pasillo']?.toString(),
          pallet:
              item['pallet']?.toString() ??
              item['ubicacion_pallet']?.toString(),
          precioMinimo: int.tryParse(item['precio_minimo']?.toString() ?? ''),
          precioMaximo: int.tryParse(item['precio_maximo']?.toString() ?? ''),
        );
      }
    }

    if (widget.initialManuales != null) {
      for (final m in widget.initialManuales!) {
        _controller.addItemManual(m);
      }
    }
  }

  Future<void> _cargarGeografiaDesdeBD() async {
    try {
      await OrdenesService.obtenerGeografia();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _limpiarFormularioCompleto() {
    _rutController.clear();
    _clienteNombresController.clear();
    _clienteApellidosController.clear();
    _clienteTelefonoController.clear();
    _clienteEmailController.clear();
    _direccionController.clear();
    _receptorNombresController.clear();
    _receptorRutController.clear();
    _receptorTelefonoController.clear();
    _empresaTransporteController.text = 'Chilexpress';
    _montoAbonoController.clear();
    _descuentoController.clear();
    if (mounted) {
      setState(() {
        _esClienteAnonimo = false;
        _regionCliente = null;
        _comunaCliente = null;
        _comunaDespacho = null;
        _idSucursalDestino = (_idSucursalActual == 1 ? 2 : 1);
        _esVentaReferida = false;
        _idVendedorTitular = null;
        _idVendedorAsignado = null;
        _controller.setIdVendedorAsignado(null);
      });
    }
    _controller.clearAll();
  }

  Future<void> _cargarRolYVendedores() async {
    try {
      final rolId = await AuthService.getIdRol();
      final sucursalId = await AuthService.getSucursalId();
      final currentUserId = await AuthService.getEnrolledUserId();
      if (mounted) {
        setState(() {
          _userRolId = rolId;
          _currentUserId = currentUserId;
          if (sucursalId != null && (sucursalId == 1 || sucursalId == 2)) {
            _idSucursalActual = sucursalId;
            _idSucursalDestino = (_idSucursalActual == 1) ? 2 : 1;
            _controller.setIdSucursalActual(_idSucursalActual);
            _controller.setIdSucursalDestino(_idSucursalDestino);
          }
        });
      }
      if (rolId == 7 || rolId == 6 || rolId == 1 || rolId == 5 || rolId == 2) {
        final vends = await OrdenesService.obtenerVendedores();
        if (mounted) {
          // Filtrar roles: Para Vendedora Online solo 6 (Jefe) y 2 (Mesón).
          // Para Jefe de Ventas: 7 (Online), 6 (Jefe) y 2 (Mesón).
          final filtrados = vends.where((v) {
            if (rolId == 7) {
              return v.idRol == null || v.idRol == 6 || v.idRol == 2;
            }
            return v.idRol == null ||
                v.idRol == 6 ||
                v.idRol == 2 ||
                v.idRol == 7;
          }).toList();

          filtrados.sort((a, b) {
            if (a.esJefeDeVentas && !b.esJefeDeVentas) return -1;
            if (!a.esJefeDeVentas && b.esJefeDeVentas) return 1;
            if (a.esVendedoraOnline && !b.esVendedoraOnline) return -1;
            if (!a.esVendedoraOnline && b.esVendedoraOnline) return 1;
            return a.nombreCompleto.compareTo(b.nombreCompleto);
          });

          if (rolId == 7) {
            // Predeterminado para Venta Online: Mesón General (null), visible para toda la sucursal
            setState(() {
              _vendedoresDisponibles = filtrados;
              _idVendedorAsignado = null;
              _controller.setIdVendedorAsignado(null);
            });
          } else {
            setState(() {
              _vendedoresDisponibles = filtrados;
            });
          }
        }
      }
    } catch (_) {}
  }

  void _sincronizarDesdeCartController() {
    final cartItems = CartController.instance.items;

    if (cartItems.isEmpty) {
      _controller.clearAll();
      _montoAbonoController.clear();
      _descuentoController.clear();
      _controller.setDescuento(0);
      _controller.setAbonoAdicional(0);
      _controller.setNotasGenerales('');
      return;
    }

    // 1. Reconciliar y sincronizar ítems inventariados
    final idsEnCart = cartItems
        .whereType<InventariadoCartItem>()
        .map((i) => i.id)
        .toSet();
    final aEliminarInventario = _controller.itemsInventariados
        .where((i) => !idsEnCart.contains(i['id_activo']))
        .map((i) => i['id_activo'].toString())
        .toList();
    for (final id in aEliminarInventario) {
      _controller.removeItemInventariado(id);
    }
    for (final item in cartItems.whereType<InventariadoCartItem>()) {
      _controller.addItemInventariado(
        idActivo: item.id,
        sku: item.sku,
        descripcion: item.titulo,
        precio: item.precioFinal,
        pasillo: item.catalogoItem.ubicacionPasillo,
        pallet: item.catalogoItem.ubicacionPallet,
        precioMinimo: item.precioMinimo,
        precioMaximo: item.precioMaximo,
        notasPreparacion: item.notasPreparacion,
      );
    }

    // 2. Reconciliar y sincronizar ítems manuales / misceláneos
    final manualesEnCart = cartItems.whereType<VentaLibreCartItem>().toList();
    for (int i = _controller.itemsManuales.length - 1; i >= 0; i--) {
      final m = _controller.itemsManuales[i];
      final sigueEnCart = manualesEnCart.any(
        (c) => c.descripcion == m.descripcion && c.monto == m.precioUnitario,
      );
      if (!sigueEnCart) {
        _controller.removeItemManual(i);
      }
    }
    for (final item in manualesEnCart) {
      if (!_controller.itemsManuales.any(
        (m) =>
            m.descripcion == item.descripcion && m.precioUnitario == item.monto,
      )) {
        _controller.addItemManual(
          ItemManualModel(
            descripcion: item.descripcion,
            cantidad: item.cantidad,
            precioUnitario: item.monto,
            precioFinal: item.subtotal,
            notasPreparacion: item.observacion,
          ),
        );
      }
    }

    // 3. Reconciliar y sincronizar reservas backorder
    final reservasEnCart = cartItems
        .whereType<ReservaBackorderCartItem>()
        .toList();
    for (int i = _controller.reservas.length - 1; i >= 0; i--) {
      final r = _controller.reservas[i];
      final sigueEnCart = reservasEnCart.any(
        (c) =>
            c.idCategoria == r.idCategoriaRequerida &&
            c.marca == r.marcaRequerida &&
            c.modelo == r.modeloRequerido,
      );
      if (!sigueEnCart) {
        _controller.removeReservaBackorder(i);
      }
    }
    for (final item in reservasEnCart) {
      if (!_controller.reservas.any(
        (r) =>
            r.marcaRequerida == item.marca &&
            r.modeloRequerido == item.modelo &&
            r.idCategoriaRequerida == item.idCategoria,
      )) {
        _controller.addReservaBackorder(
          ReservaBackorderModel(
            idCategoriaRequerida: item.idCategoria,
            categoriaNombre: item.categoriaNombre,
            marcaRequerida: item.marca,
            modeloRequerido: item.modelo,
            anioRequerido: item.anio,
            precioAcordado: item.precioAcordado,
            montoAbonado: item.montoAbonado,
            notasPreparacion: item.notas,
          ),
        );
      }
    }

    if (_controller.totalItemsCount > 0 &&
        _controller.errorMessage ==
            'Debes agregar al menos un artículo o servicio para proceder.') {
      _controller.clearErrorMessage();
    }
    _verificarYDesmarcarConsumidorFinalSiAplica();
  }

  void _onControllerUpdate() {
    _verificarYDesmarcarConsumidorFinalSiAplica();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    CartController.instance.removeListener(_sincronizarDesdeCartController);
    _rutFocusNode.removeListener(_onRutFocusChange);
    _rutFocusNode.dispose();
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    _rutController.dispose();
    _clienteNombresController.dispose();
    _clienteApellidosController.dispose();
    _clienteTelefonoController.dispose();
    _clienteEmailController.dispose();
    _direccionController.dispose();
    _receptorNombresController.dispose();
    _receptorRutController.dispose();
    _receptorTelefonoController.dispose();
    _empresaTransporteController.dispose();
    _montoAbonoController.dispose();
    _descuentoController.dispose();
    super.dispose();
  }

  // ── Búsqueda y Autocompletado Reactivo por RUT ────────────────────────────
  void _onRutFocusChange() {
    if (!_rutFocusNode.hasFocus && !_esClienteAnonimo) {
      _buscarClientePorRut();
    }
  }

  Future<void> _buscarClientePorRut() async {
    final rut = _rutController.text.trim();
    if (rut.length < 7 || _esClienteAnonimo) return;

    setState(() => _isSearchingCliente = true);
    try {
      final res = await OrdenesService.buscarClientePorRut(rut);
      if (!mounted) return;

      setState(() {
        _isSearchingCliente = false;
        if (res != null) {
          _clienteNombresController.text = res['nombres']?.toString() ?? '';
          _clienteApellidosController.text = res['apellidos']?.toString() ?? '';
          if (res['telefono'] != null) {
            _clienteTelefonoController.text = res['telefono'].toString();
          }
          if (res['correo'] != null) {
            _clienteEmailController.text = res['correo'].toString();
          }
          final com = res['comuna']?.toString();
          if (com != null && com.isNotEmpty) {
            final reg = ChileGeografia.obtenerRegionDeComuna(com);
            if (reg != null) {
              _regionCliente = reg;
              _comunaCliente = com;
            } else {
              _comunaCliente = com;
            }
          }

          final cliente = ClienteWizardModel(
            idCliente:
                res['id_cliente']?.toString() ??
                'cli-${DateTime.now().millisecondsSinceEpoch}',
            rut: rut,
            nombres: _clienteNombresController.text,
            apellidos: _clienteApellidosController.text,
            telefono: _clienteTelefonoController.text,
            correo: _clienteEmailController.text,
            comuna: _comunaCliente,
            consentimientoLegal: true,
            estado: 'Activo',
          );
          _controller.setCliente(cliente);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppPalette.surface,
              duration: const Duration(seconds: 2),
              content: Text(
                'Cliente frecuente encontrado: ${cliente.nombreCompleto}',
                style: AppTypography.small.copyWith(
                  color: AppPalette.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        } else {
          _actualizarClienteLocal();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSearchingCliente = false);
      _actualizarClienteLocal();
    }
  }

  void _actualizarClienteLocal() {
    final rut = _rutController.text.trim();
    final nom = _clienteNombresController.text.trim();
    final ape = _clienteApellidosController.text.trim();

    if (rut.isNotEmpty && nom.isNotEmpty) {
      final cliente = ClienteWizardModel(
        idCliente:
            _controller.clienteSeleccionado?.idCliente ??
            'cli-${DateTime.now().millisecondsSinceEpoch}',
        rut: rut,
        nombres: nom,
        apellidos: ape.isNotEmpty ? ape : 'S/A',
        telefono: _clienteTelefonoController.text.trim(),
        correo: _clienteEmailController.text.trim(),
        comuna: _comunaCliente,
        consentimientoLegal: true,
        estado: 'Activo',
      );
      _controller.setCliente(cliente);
    }
  }

  Future<void> _toggleClienteAnonimo(bool valor) async {
    if (_tieneVentaEnVerde) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppPalette.error,
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Las compras en verde requieren obligatoriamente registrar a un cliente identificado con RUT, nombre y apellido.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
      return;
    }

    if (valor) {
      final bool? confirmado = await DialogoAdvertenciaConsumidorFinal.mostrar(
        context,
      );
      if (confirmado != true) {
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _esClienteAnonimo = valor;
      if (valor) {
        _rutController.text = '6.666.666-6';
        _clienteNombresController.text = 'Consumidor';
        _clienteApellidosController.text = 'Final';
        _clienteTelefonoController.clear();
        _clienteEmailController.clear();
        _regionCliente = 'Valparaíso';
        _comunaCliente = 'Viña del Mar';

        _controller.setCliente(
          const ClienteWizardModel(
            idCliente: 'cli-cf',
            rut: '6.666.666-6',
            nombres: 'Consumidor',
            apellidos: 'Final',
            comuna: 'Viña del Mar',
            consentimientoLegal: true,
            estado: 'Activo',
          ),
        );
      } else {
        _rutController.clear();
        _clienteNombresController.clear();
        _clienteApellidosController.clear();
        _clienteTelefonoController.clear();
        _clienteEmailController.clear();
        _regionCliente = null;
        _comunaCliente = null;
        _controller.setCliente(null);
      }
    });
  }

  // ── Sincronización y Emisión Transaccional (ACID) ─────────────────────────
  void _actualizarDatosDespachoLocal() {
    if (_controller.tipoEntrega == 'Despacho Domicilio' ||
        _controller.tipoEntrega == 'Despacho') {
      final d = DespachoModel(
        direccionEnvio: _direccionController.text.trim(),
        receptorNombres: _receptorNombresController.text.trim(),
        receptorRut: _receptorRutController.text.trim(),
        receptorTelefono: _receptorTelefonoController.text.trim(),
        idComunaDestino: ChileGeografia.obtenerIdComuna(_comunaDespacho),
        comunaNombre: _comunaDespacho,
        empresaTransporte: _empresaTransporteController.text.trim().isNotEmpty
            ? _empresaTransporteController.text.trim()
            : 'Chilexpress',
        tipoEntrega: 'Despacho',
      );
      _controller.setDatosDespacho(d);
    } else if (_controller.tipoEntrega == 'Traslado') {
      final nomDest = _idSucursalDestino == 1 ? 'Viña del Mar' : 'Limache';
      final d = DespachoModel(
        direccionEnvio: 'Traslado a Sucursal $nomDest',
        receptorNombres: _receptorNombresController.text.trim().isNotEmpty
            ? _receptorNombresController.text.trim()
            : (_controller.clienteSeleccionado?.nombreCompleto ?? 'Cliente'),
        receptorRut: _receptorRutController.text.trim().isNotEmpty
            ? _receptorRutController.text.trim()
            : (_controller.clienteSeleccionado?.rut ?? 'S/R'),
        receptorTelefono: _receptorTelefonoController.text.trim().isNotEmpty
            ? _receptorTelefonoController.text.trim()
            : '+56900000000',
        idComunaDestino: _idSucursalDestino,
        comunaNombre: nomDest,
        empresaTransporte: 'Interno',
        tipoEntrega: 'Traslado',
        idSucursalDestino: _idSucursalDestino,
      );
      _controller.setDatosDespacho(d);
      _controller.setIdSucursalDestino(_idSucursalDestino);
    } else {
      _controller.setDatosDespacho(null);
    }

    if (_esVendedorOnline) {
      _controller.setIdVendedorAsignado(_idVendedorAsignado);
    } else if (_puedeAsignarVenta && _esVentaReferida) {
      _controller.setIdVendedorTitular(_idVendedorTitular);
      _controller.setIdVendedorAsignado(_currentUserId);
    } else {
      _controller.setIdVendedorTitular(null);
    }
  }

  void _prellenarDatosDespachoSiAplica() {
    final cli = _controller.clienteSeleccionado;
    if (cli != null) {
      if (_receptorNombresController.text.trim().isEmpty) {
        _receptorNombresController.text = cli.nombreCompleto;
      }
      if (_receptorRutController.text.trim().isEmpty) {
        _receptorRutController.text = cli.rut;
      }
      if (_receptorTelefonoController.text.trim().isEmpty &&
          cli.telefono != null) {
        _receptorTelefonoController.text = cli.telefono!;
      }
      if (_comunaDespacho == null &&
          cli.comuna != null &&
          cli.comuna!.isNotEmpty) {
        final reg = ChileGeografia.obtenerRegionDeComuna(cli.comuna!);
        if (reg != null) {
          _comunaDespacho = cli.comuna;
        }
      }
      _actualizarDatosDespachoLocal();
    }
  }

  Future<void> _confirmarYEnviarOrden() async {
    if (_puedeAsignarVenta &&
        _esVentaReferida &&
        (_idVendedorTitular == null || _idVendedorTitular!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Debes seleccionar al vendedor al cual se atribuirá la venta antes de confirmar la orden.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_tieneVentaEnVerde &&
        (_esClienteAnonimo ||
            _controller.clienteSeleccionado == null ||
            _rutController.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Las órdenes con Venta en Verde requieren registrar obligatoriamente los datos de contacto del cliente.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _actualizarDatosDespachoLocal();

    final res = await _controller.submitOrder();
    if (!mounted) return;

    if (res != null) {
      OrdenesSyncNotifier.instance.notificarCambio();
      CartController.instance.vaciarCarrito();
      _limpiarFormularioCompleto();

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppPalette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppPalette.success),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AppPalette.success,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                '¡Orden Generada!',
                style: AppTypography.title.copyWith(fontSize: 18),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Folio: ${res.folioDisplay}',
                style: AppTypography.small.copyWith(
                  color: AppPalette.secondary,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (res.abonoRequerido > 0) ...[
                Text(
                  'Total Venta: ${CurrencyFormatter.formatCLP(res.totalVenta)}',
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Abono a Pagar Hoy en Caja: ${CurrencyFormatter.formatCLP(res.abonoRequerido)}',
                  style: AppTypography.body.copyWith(
                    color: AppPalette.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (res.totalVenta - res.abonoRequerido > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Saldo Pendiente: ${CurrencyFormatter.formatCLP(res.totalVenta - res.abonoRequerido)}',
                    style: AppTypography.body.copyWith(
                      color: const Color(0xFFFFA726),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ] else ...[
                Text(
                  'Total a Pagar en Caja: ${CurrencyFormatter.formatCLP(res.totalVenta)}',
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppPalette.primary,
                  ),
                ),
              ],
              if (res.reservasGeneradas > 0) ...[
                const SizedBox(height: 6),
                Text(
                  '• ${res.reservasGeneradas} venta(s) en verde generadas por encargo.',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.success,
                  ),
                ),
              ],
              if (res.despachoGenerado) ...[
                const SizedBox(height: 4),
                Text(
                  '• Solicitud de despacho / traslado registrada.',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.primary,
              ),
              onPressed: () {
                _limpiarFormularioCompleto();
                Navigator.of(ctx).pop();
                if (widget.onNavigateToCatalogo != null) {
                  widget.onNavigateToCatalogo!();
                } else if (Navigator.canPop(context)) {
                  Navigator.of(context).pop(true);
                }
              },
              child: const Text('FINALIZAR Y VOLVER'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: mediaQuery.textScaler.clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 1.15,
        ),
      ),
      child: Scaffold(
        backgroundColor: AppPalette.background,
        appBar: AppBar(
          backgroundColor: AppPalette.surface,
          foregroundColor: AppPalette.textPrimary,
          elevation: 0,
          leading: widget.onOpenMenuDrawer != null
              ? IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: widget.onOpenMenuDrawer,
                  tooltip: 'Abrir Menú',
                )
              : (Navigator.canPop(context) ? const BackButton() : null),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Checkout Transaccional',
                style: AppTypography.title.copyWith(fontSize: 20),
              ),
              Text(
                'Flujo Secuencial de 4 Pasos • Retiro en Tienda',
                style: AppTypography.small.copyWith(
                  color: AppPalette.secondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          actions: [
            if (_controller.totalItemsCount > 0) ...[
              IconButton(
                icon: const Icon(
                  Icons.delete_sweep_outlined,
                  color: AppPalette.error,
                ),
                tooltip: 'Vaciar Carrito',
                onPressed: () {
                  CartController.instance.vaciarCarrito(liberarEnBackend: true);
                  _limpiarFormularioCompleto();
                  CatalogoScreen.refreshNotifier.value++;
                },
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
        body: Column(
          children: [
            // Barra superior de progreso de pasos
            _buildStepProgressBar(),

            if (_controller.errorMessage != null)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
                        _controller.errorMessage!,
                        style: const TextStyle(
                          color: AppPalette.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: Builder(
                builder: (context) {
                  final bottomPadding = MediaQuery.paddingOf(context).bottom;
                  final hasBottomNavBar = widget.onOpenMenuDrawer != null;

                  // Altura de la barra de navegación flotante inferior (FloatingGlassNavBar) más márgenes y safe area:
                  final navBarHeight = hasBottomNavBar
                      ? (70.0 +
                            14.0 +
                            (bottomPadding > 0 ? bottomPadding + 4.0 : 0.0))
                      : 0.0;

                  // Ubicamos los botones de siguiente/anterior flotando limpiamente por encima del navbar:
                  final buttonsBottom = hasBottomNavBar
                      ? (navBarHeight + 12.0)
                      : (16.0 + (bottomPadding > 0 ? bottomPadding : 0.0));

                  // Padding inferior dinámico para que el contenido no quede tapado tras los botones:
                  final scrollBottomPadding = buttonsBottom + 52.0 + 16.0;

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            16,
                            16,
                            scrollBottomPadding,
                          ),
                          child: _buildCurrentStepContent(),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: buttonsBottom,
                        child: _buildBottomNavigationButtons(),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Stepper Bar (4 Pasos) ──────────────────────────────────────────────────
  Widget _buildStepProgressBar() {
    final stepLabels = ['Ítems', 'Cliente', 'Abonos', 'Confirmar'];

    return Container(
      color: AppPalette.surface,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: List.generate(4, (index) {
          final isCompleted = index < _controller.currentStep;
          final isCurrent = index == _controller.currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCurrent
                              ? AppPalette.primary
                              : isCompleted
                              ? AppPalette.success
                              : AppPalette.background,
                          border: Border.all(
                            color: isCurrent
                                ? AppPalette.primary
                                : isCompleted
                                ? AppPalette.success
                                : Colors.white24,
                          ),
                        ),
                        child: Center(
                          child: isCompleted
                              ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isCurrent
                                        ? AppPalette.textPrimary
                                        : AppPalette.textSecondary,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          stepLabels[index],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isCurrent
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isCurrent
                                ? AppPalette.primary
                                : AppPalette.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < 3)
                  Container(
                    width: 20,
                    height: 2,
                    color: isCompleted ? AppPalette.success : Colors.white12,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStepContent() {
    switch (_controller.currentStep) {
      case 0:
        return _buildStep1Items();
      case 1:
        return _buildStep2Cliente();
      case 2:
        return _buildStep3Condiciones();
      case 3:
      default:
        return _buildStep4Confirmacion();
    }
  }

  // ── PASO 1: ÍTEMS & RESERVAS ──────────────────────────────────────────────
  Widget _buildStep1Items() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                '1. Artículos y Encargos',
                style: AppTypography.title.copyWith(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${_controller.totalItemsCount} artículos (${CurrencyFormatter.formatCLP(_controller.totalVenta)})',
                style: AppTypography.small.copyWith(
                  color: AppPalette.secondary,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.secondary,
                  foregroundColor: AppPalette.background,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.bookmark_add, size: 20),
                label: const Text(
                  'Venta en Verde',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () async {
                  if (CartController.instance.items.isNotEmpty ||
                      _controller.totalItemsCount > 0) {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        backgroundColor: AppPalette.error,
                        behavior: SnackBarBehavior.floating,
                        content: Text(
                          'No se pueden agregar ventas en verde porque el pedido ya contiene productos. Las ventas en verde van solas.',
                        ),
                      ),
                    );
                    return;
                  }
                  final reserva = await ModalBackorderForm.mostrar(context);
                  if (reserva != null) {
                    _controller.addReservaBackorder(reserva);
                    CartController.instance.agregarReservaBackorder(
                      idCategoria: reserva.idCategoriaRequerida,
                      categoriaNombre: reserva.categoriaNombre,
                      marca: reserva.marcaRequerida,
                      modelo: reserva.modeloRequerido,
                      anio: reserva.anioRequerido,
                      precioAcordado: reserva.precioAcordado,
                      montoAbonado: reserva.montoAbonado,
                      notas: reserva.notasPreparacion,
                    );
                    if (mounted) {
                      GlassSnackbar.mostrar(
                        context,
                        mensaje: 'Venta en verde agregada al carrito',
                        icono: Icons.check_circle_outline_rounded,
                        colorIcono: AppPalette.primary,
                      );
                    }
                  }
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.primary,
                  side: const BorderSide(color: AppPalette.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.add_shopping_cart, size: 20),
                label: const Text(
                  'Venta libre',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () {
                  if (CartController.instance.tieneVentaEnVerde ||
                      _controller.reservas.isNotEmpty) {
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
                    return;
                  }
                  VentaLibreDialog.show(context);
                },
              ),
            ),
          ],
        ),
        if (_puedeAsignarVenta) ...[
          const SizedBox(height: 14),
          _buildCardVentaReferida(),
        ],
        const SizedBox(height: 16),

        if (_controller.totalItemsCount == 0)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppPalette.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.shopping_cart_outlined,
                  color: AppPalette.textSecondary,
                  size: 48,
                ),
                const SizedBox(height: 10),
                Text(
                  'El carrito está actualmente vacío',
                  style: AppTypography.title.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  'Añada productos desde el Catálogo, cargue ítems manuales o cree una Reserva por Encargo (Compra en Verde).',
                  style: AppTypography.body.copyWith(
                    color: AppPalette.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (widget.onNavigateToCatalogo != null)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.primary,
                      foregroundColor: AppPalette.textPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.storefront, size: 20),
                    label: const Text(
                      'Ir al Catálogo',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    onPressed: widget.onNavigateToCatalogo,
                  ),
              ],
            ),
          )
        else ...[
          if (_controller.itemsInventariados.isNotEmpty) ...[
            Text(
              'REPUESTOS EN INVENTARIO (${_controller.itemsInventariados.length})',
              style: AppTypography.small.copyWith(
                color: AppPalette.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            ..._controller.itemsInventariados.map((item) {
              final idActivo = item['id_activo']?.toString() ?? '';
              final cartItem = CartController.instance.items
                  .whereType<InventariadoCartItem>()
                  .cast<InventariadoCartItem?>()
                  .firstWhere((ci) => ci?.id == idActivo, orElse: () => null);
              if (cartItem != null) {
                return CartItemTile(
                  key: ValueKey('cart_inv_${cartItem.id}'),
                  item: cartItem,
                );
              }
              return _buildFallbackItemInventariadoTile(item);
            }),
            const SizedBox(height: 12),
          ],

          if (_controller.reservas.isNotEmpty) ...[
            Text(
              'VENTAS EN VERDE (${_controller.reservas.length})',
              style: AppTypography.small.copyWith(
                color: AppPalette.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            ..._controller.reservas.asMap().entries.map((entry) {
              final idx = entry.key;
              final r = entry.value;
              return Card(
                color: AppPalette.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: AppPalette.secondary, width: 1),
                ),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(
                    Icons.bookmark_added_rounded,
                    color: AppPalette.secondary,
                  ),
                  title: Text(
                    '${r.categoriaNombre} - ${r.marcaRequerida} ${r.modeloRequerido}',
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Precio: ${CurrencyFormatter.formatCLP(r.precioAcordado)} • Abono: ${CurrencyFormatter.formatCLP(r.montoAbonado)}',
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textSecondary,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppPalette.error,
                      size: 20,
                    ),
                    onPressed: () {
                      final r = _controller.reservas[idx];
                      _controller.removeReservaBackorder(idx);
                      final cartIdx = CartController.instance.items.indexWhere(
                        (item) =>
                            item is ReservaBackorderCartItem &&
                            item.idCategoria == r.idCategoriaRequerida &&
                            item.marca == r.marcaRequerida &&
                            item.modelo == r.modeloRequerido,
                      );
                      if (cartIdx != -1) {
                        CartController.instance.eliminarItem(
                          CartController.instance.items[cartIdx].id,
                        );
                      }
                      if (context.mounted) {
                        GlassSnackbar.mostrar(
                          context,
                          mensaje:
                              '${r.marcaRequerida} ${r.modeloRequerido} eliminado del carrito',
                          icono: Icons.delete_outline_rounded,
                          colorIcono: AppPalette.error,
                        );
                      }
                    },
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
          ],

          if (_controller.itemsManuales.isNotEmpty) ...[
            Text(
              'ÍTEMS MANUALES (${_controller.itemsManuales.length})',
              style: AppTypography.small.copyWith(
                color: AppPalette.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            ..._controller.itemsManuales.asMap().entries.map((entry) {
              final idx = entry.key;
              final m = entry.value;
              return Card(
                color: AppPalette.surface,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(
                    Icons.edit_note,
                    color: Colors.white70,
                    size: 24,
                  ),
                  title: Text(
                    m.descripcion,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  subtitle: Text(
                    'Cantidad: ${m.cantidad}  •  Unitario: ${CurrencyFormatter.formatCLP(m.precioUnitario)}',
                    style: AppTypography.body.copyWith(
                      color: const Color(0xFFCBD5E1),
                      fontSize: 13,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        CurrencyFormatter.formatCLP(m.precioFinal),
                        style: AppTypography.body.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppPalette.primary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppPalette.error,
                          size: 22,
                        ),
                        tooltip: 'Eliminar ítem',
                        onPressed: () {
                          final m = _controller.itemsManuales[idx];
                          _controller.removeItemManual(idx);
                          final cartIdx = CartController.instance.items
                              .indexWhere(
                                (item) =>
                                    item is VentaLibreCartItem &&
                                    item.descripcion == m.descripcion &&
                                    item.precioUnitario == m.precioUnitario,
                              );
                          if (cartIdx != -1) {
                            CartController.instance.eliminarItem(
                              CartController.instance.items[cartIdx].id,
                            );
                          }
                          if (context.mounted) {
                            GlassSnackbar.mostrar(
                              context,
                              mensaje: '${m.descripcion} eliminado del carrito',
                              icono: Icons.delete_outline_rounded,
                              colorIcono: AppPalette.error,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],

          if (CartController.instance.hayPreciosInvalidos) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppPalette.error.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: AppPalette.error,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Hay repuestos con precio acordado fuera del rango de tasación permitido. Modifícalos dentro de su rango para continuar.',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildFallbackItemInventariadoTile(Map<String, dynamic> item) {
    final idActivo = item['id_activo']?.toString() ?? '';
    final precio = item['precio'] is int
        ? item['precio'] as int
        : int.tryParse(item['precio']?.toString() ?? '0') ?? 0;
    final min = item['precio_minimo'] is int
        ? item['precio_minimo'] as int
        : int.tryParse(item['precio_minimo']?.toString() ?? '');
    final max = item['precio_maximo'] is int
        ? item['precio_maximo'] as int
        : int.tryParse(item['precio_maximo']?.toString() ?? '');
    final bool esInvalido =
        (min != null && precio < min) || (max != null && precio > max);

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: esInvalido
              ? AppPalette.error
              : AppPalette.primary.withValues(alpha: 0.2),
          width: esInvalido ? 1.5 : 1.0,
        ),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 3.0,
                ),
                decoration: BoxDecoration(
                  color: AppPalette.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6.0),
                  border: Border.all(color: AppPalette.primary, width: 1.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 13,
                      color: AppPalette.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Inventario',
                      style: AppTypography.small.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppPalette.primary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: AppPalette.error,
                  size: 20,
                ),
                onPressed: () {
                  _controller.removeItemInventariado(idActivo);
                  CartController.instance.eliminarItem(idActivo);
                  CatalogoScreen.refreshNotifier.value++;
                  GlassSnackbar.mostrar(
                    context,
                    mensaje:
                        '${item['descripcion'] ?? 'Repuesto'} eliminado del carrito',
                    icono: Icons.delete_outline_rounded,
                    colorIcono: AppPalette.error,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            item['descripcion'] ?? 'Repuesto',
            style: AppTypography.cardTitle.copyWith(fontSize: 16),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'SKU: ${item['sku']} • Pasillo: ${item['pasillo'] ?? 'S/P'}${item['pallet'] != null && item['pallet'].toString().isNotEmpty && item['pallet'] != 'S/P' ? " • Pallet: ${item['pallet']}" : ""}',
            style: AppTypography.small.copyWith(
              color: AppPalette.textSecondary,
              fontSize: 13,
            ),
          ),
          if (item['notas_preparacion'] != null &&
              item['notas_preparacion'].toString().trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppPalette.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.assignment_outlined,
                    size: 14,
                    color: AppPalette.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Preparación: ${item['notas_preparacion']}',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PRECIO ACORDADO (CLP):',
                      style: AppTypography.small.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppPalette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      initialValue: CurrencyFormatter.formatNumber(precio),
                      keyboardType: TextInputType.number,
                      inputFormatters: [MilesTextInputFormatter()],
                      style: AppTypography.body.copyWith(
                        color: esInvalido
                            ? AppPalette.error
                            : AppPalette.secondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        prefixText: '\$ ',
                        prefixStyle: TextStyle(
                          color: esInvalido
                              ? AppPalette.error
                              : AppPalette.secondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: AppPalette.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: esInvalido
                                ? AppPalette.error
                                : Colors.white12,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: esInvalido
                                ? AppPalette.error
                                : Colors.white12,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: esInvalido
                                ? AppPalette.error
                                : AppPalette.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                      onChanged: (val) {
                        final nuevo = CurrencyFormatter.parse(val);
                        _controller.updateItemInventariadoPrecio(
                          idActivo,
                          nuevo,
                        );
                        CartController.instance.actualizarPrecio(
                          idActivo,
                          nuevo,
                        );
                      },
                    ),
                    if (min != null && max != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Rango: ${CurrencyFormatter.formatCLP(min)} - ${CurrencyFormatter.formatCLP(max)}',
                        style: AppTypography.small.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: esInvalido
                              ? AppPalette.error
                              : AppPalette.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── PASO 2: CLIENTE CRM UNIFICADO CON CONSUMIDOR FINAL ────────────────────
  // ── PASO 2: CLIENTE CRM UNIFICADO CON CONSUMIDOR FINAL ────────────────────
  Widget _buildStep2Cliente() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '2. Datos del Cliente (Micro-CRM)',
          style: AppTypography.title.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 12),

        if (_tieneVentaEnVerde) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10.0),
              border: Border.all(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.eco_rounded, size: 22, color: Color(0xFF81C784)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Venta en Verde activa: Por trazabilidad y reserva formal, es obligatorio registrar al cliente titular (RUT, nombre y apellido). Teléfono y correo son opcionales para coordinación.',
                    style: AppTypography.small.copyWith(
                      color: const Color(0xFFC8E6C9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Botón Interactivo Consumidor Final (Sin RUT) - Clickable en toda el área
        Material(
          color: _tieneVentaEnVerde
              ? AppPalette.surface.withValues(alpha: 0.5)
              : _esClienteAnonimo
                  ? AppPalette.secondary.withValues(alpha: 0.15)
                  : AppPalette.surface,
          borderRadius: BorderRadius.circular(10.0),
          child: InkWell(
            borderRadius: BorderRadius.circular(10.0),
            onTap: () => _toggleClienteAnonimo(!_esClienteAnonimo),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14.0,
                vertical: 10.0,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(
                  color: _tieneVentaEnVerde
                      ? Colors.white10
                      : _esClienteAnonimo
                          ? AppPalette.secondary
                          : Colors.white12,
                  width: _esClienteAnonimo && !_tieneVentaEnVerde ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          Icons.no_accounts_outlined,
                          size: 22,
                          color: _tieneVentaEnVerde
                              ? AppPalette.textSecondary.withValues(alpha: 0.5)
                              : _esClienteAnonimo
                                  ? AppPalette.secondary
                                  : AppPalette.textSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Consumidor Final (Sin RUT)',
                                style: AppTypography.body.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _tieneVentaEnVerde
                                      ? AppPalette.textSecondary.withValues(alpha: 0.6)
                                      : _esClienteAnonimo
                                          ? AppPalette.secondary
                                          : AppPalette.textPrimary,
                                ),
                              ),
                              Text(
                                _tieneVentaEnVerde
                                    ? 'No disponible en Venta en Verde (se requiere cliente identificado con RUT)'
                                    : 'Toca aquí para venta rápida sin registrar datos',
                                style: AppTypography.small.copyWith(
                                  color: _tieneVentaEnVerde
                                      ? AppPalette.error.withValues(alpha: 0.8)
                                      : AppPalette.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    key: const Key('switch_cliente_anonimo'),
                    value: !_tieneVentaEnVerde && _esClienteAnonimo,
                    activeThumbColor: AppPalette.secondary,
                    onChanged: _tieneVentaEnVerde
                        ? (_) => _toggleClienteAnonimo(true)
                        : (val) => _toggleClienteAnonimo(val),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        if (_esClienteAnonimo) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14.0),
            decoration: BoxDecoration(
              color: AppPalette.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10.0),
              border: Border.all(
                color: AppPalette.secondary.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: AppPalette.secondary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Aviso: La orden se asignará al cliente Consumidor Final (RUT 6.666.666-6). El cliente solo podrá pagar y retirar en caja presentando su Número de Orden.',
                    style: AppTypography.body.copyWith(
                      color: const Color(0xFFF1F5F9),
                      fontWeight: FontWeight.w500,
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // Formulario Unificado de Cliente
          Builder(
            builder: (context) {
              final rutText = _rutController.text.trim();
              final bool rutInvalido =
                  !_esClienteAnonimo &&
                  rutText.isNotEmpty &&
                  !RutValidator.isValid(rutText);
              final String? rutError = rutInvalido
                  ? 'RUT inválido. Verifique el número ingresado.'
                  : null;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldHeader(
                      'RUT Cliente *',
                      icon: Icons.badge_outlined,
                    ),
                    TextField(
                      key: const Key('input_rut_cliente'),
                      controller: _rutController,
                      focusNode: _rutFocusNode,
                      style: AppTypography.body.copyWith(
                        color: Colors.white,
                        fontSize: 14.5,
                      ),
                      inputFormatters: [RutFormatter()],
                      decoration: _inputDeco(
                        hint: 'Ej: 12.345.678-9',
                        errorText: rutError,
                        suffix: _isSearchingCliente
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppPalette.primary,
                                ),
                              )
                            : IconButton(
                                icon: const Icon(
                                  Icons.search,
                                  color: AppPalette.primary,
                                  size: 20,
                                ),
                                tooltip: 'Buscar por RUT',
                                onPressed: _buscarClientePorRut,
                              ),
                      ),
                      onChanged: (val) {
                        setState(() {});
                        _actualizarClienteLocal();
                      },
                    ),
                    const SizedBox(height: 14),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldHeader(
                                'Nombres *',
                                icon: Icons.person,
                              ),
                              TextField(
                                key: const Key('input_cliente_nombres'),
                                controller: _clienteNombresController,
                                style: AppTypography.body.copyWith(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                ),
                                decoration: _inputDeco(hint: 'Ej: Juan'),
                                onChanged: (val) {
                                  setState(() {});
                                  _actualizarClienteLocal();
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldHeader(
                                'Apellidos *',
                                icon: Icons.person_outline,
                              ),
                              TextField(
                                key: const Key('input_cliente_apellidos'),
                                controller: _clienteApellidosController,
                                style: AppTypography.body.copyWith(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                ),
                                decoration: _inputDeco(hint: 'Ej: Pérez'),
                                onChanged: (val) => _actualizarClienteLocal(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldHeader(
                                'Teléfono (Opcional)',
                                icon: Icons.phone,
                              ),
                              TextField(
                                controller: _clienteTelefonoController,
                                style: AppTypography.body.copyWith(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                ),
                                keyboardType: TextInputType.phone,
                                decoration: _inputDeco(
                                  hint: 'Ej: +56 9 1234 5678',
                                ),
                                onChanged: (val) => _actualizarClienteLocal(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldHeader(
                                'Correo(Opcional)',
                                icon: Icons.email_outlined,
                              ),
                              TextField(
                                controller: _clienteEmailController,
                                style: AppTypography.body.copyWith(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                ),
                                keyboardType: TextInputType.emailAddress,
                                decoration: _inputDeco(
                                  hint: 'Ej: cliente@correo.com',
                                ),
                                onChanged: (val) => _actualizarClienteLocal(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldHeader(
                                'Región (Opcional)',
                                icon: Icons.map_outlined,
                              ),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _regionCliente,
                                dropdownColor: AppPalette.surface,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                                icon: const Icon(
                                  Icons.arrow_drop_down,
                                  color: Color(0xFF94A3B8),
                                ),
                                decoration: _inputDeco(
                                  hint: 'Seleccione Región...',
                                ),
                                hint: const Text(
                                  'Seleccione Región...',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 14,
                                  ),
                                ),
                                items: ChileGeografia.regiones
                                    .map(
                                      (r) => DropdownMenuItem(
                                        value: r,
                                        child: Text(
                                          r,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  setState(() {
                                    _regionCliente = val;
                                    _comunaCliente = null;
                                    _actualizarClienteLocal();
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildFieldHeader(
                                'Comuna (Opcional)',
                                icon: Icons.location_city,
                              ),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                value:
                                    (ChileGeografia.obtenerComunas(
                                      _regionCliente,
                                    ).contains(_comunaCliente))
                                    ? _comunaCliente
                                    : null,
                                dropdownColor: AppPalette.surface,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                                icon: const Icon(
                                  Icons.arrow_drop_down,
                                  color: Color(0xFF94A3B8),
                                ),
                                decoration:
                                    _inputDeco(
                                      hint: 'Seleccione Comuna...',
                                    ).copyWith(
                                      enabled:
                                          _regionCliente != null &&
                                          _regionCliente!.isNotEmpty,
                                    ),
                                hint: Text(
                                  _regionCliente != null &&
                                          _regionCliente!.isNotEmpty
                                      ? 'Seleccione Comuna...'
                                      : 'Seleccione región primero',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        _regionCliente != null &&
                                            _regionCliente!.isNotEmpty
                                        ? const Color(0xFF94A3B8)
                                        : const Color(0xFF64748B),
                                    fontSize: 14,
                                  ),
                                ),
                                items:
                                    (_regionCliente != null &&
                                        _regionCliente!.isNotEmpty)
                                    ? ChileGeografia.obtenerComunas(
                                            _regionCliente,
                                          )
                                          .map(
                                            (c) => DropdownMenuItem(
                                              value: c,
                                              child: Text(
                                                c,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList()
                                    : const [],
                                onChanged:
                                    (_regionCliente != null &&
                                        _regionCliente!.isNotEmpty)
                                    ? (val) {
                                        setState(() {
                                          _comunaCliente = val;
                                          _actualizarClienteLocal();
                                        });
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
        if (_esVendedorOnline) ...[
          const SizedBox(height: 16),
          _buildCardResponsableEntrega(),
        ],
      ],
    );
  }

  // ── PASO 3: CONDICIONES COMERCIALES & ABONOS ──────────────────────────────
  Widget _buildStep3Condiciones() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '3. Condiciones Comerciales y Abonos',
          style: AppTypography.title.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 14),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppPalette.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              if (_controller.subtotalInventario > 0)
                _buildResumenRow(
                  'Subtotal Repuestos Inventario:',
                  CurrencyFormatter.formatCLP(_controller.subtotalInventario),
                ),
              if (_controller.subtotalManuales > 0)
                _buildResumenRow(
                  'Subtotal Ítems Manuales:',
                  CurrencyFormatter.formatCLP(_controller.subtotalManuales),
                ),
              if (_controller.subtotalReservas > 0)
                _buildResumenRow(
                  'Subtotal Ventas en Verde:',
                  CurrencyFormatter.formatCLP(_controller.subtotalReservas),
                ),
              if (_controller.descuento > 0)
                _buildResumenRow(
                  'Descuento a Favor:',
                  '- ${CurrencyFormatter.formatCLP(_controller.descuento)}',
                  color: const Color(0xFFEF5350),
                ),
              const Divider(color: Colors.white24, height: 20),
              _buildResumenRow(
                'TOTAL DE LA VENTA:',
                CurrencyFormatter.formatCLP(_controller.totalVenta),
                isBold: true,
                color: AppPalette.primary,
              ),
              if (_controller.totalAbonos > 0) ...[
                const SizedBox(height: 8),
                _buildResumenRow(
                  'Abono Inicial Acordado:',
                  CurrencyFormatter.formatCLP(_controller.totalAbonos),
                  color: AppPalette.textSecondary,
                ),
                if (_controller.montoPendiente > 0)
                  _buildResumenRow(
                    'Saldo Pendiente:',
                    CurrencyFormatter.formatCLP(_controller.montoPendiente),
                    isBold: true,
                    color: const Color(0xFFFFA726),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Campo de Descuento por Vale a Favor (Sincronizado)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppPalette.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.confirmation_number_outlined,
                    size: 18,
                    color: AppPalette.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Descuento por Vale a Favor (\$):',
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descuentoController,
                keyboardType: TextInputType.number,
                inputFormatters: [MilesTextInputFormatter()],
                style: AppTypography.body.copyWith(color: Colors.white),
                decoration: _inputDeco(hint: 'Ej: 50.000'),
                onChanged: (val) {
                  final desc = CurrencyFormatter.parse(val);
                  _controller.setDescuento(desc);
                },
              ),
              if (_controller.descuento > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Descuento aplicado: - ${CurrencyFormatter.formatCLP(_controller.descuento)}',
                  style: AppTypography.small.copyWith(
                    color: const Color(0xFFEF5350),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Campo de Abono / Anticipo Editable
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppPalette.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.payments_outlined,
                    size: 18,
                    color: AppPalette.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _controller.reservas.isNotEmpty
                        ? 'Abono / Anticipo Venta en Verde (\$):'
                        : 'Abono / Anticipo Inicial (\$):',
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              if (_controller.reservas.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Ingrese aquí el monto de abono acordado para la venta en verde (o \$0 para que el cliente pague el total en caja).',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _montoAbonoController,
                keyboardType: TextInputType.number,
                inputFormatters: [MilesTextInputFormatter()],
                style: AppTypography.body.copyWith(color: Colors.white),
                decoration: _inputDeco(
                  hint: 'Ej: 50.000 (0 para pagar total en caja)',
                ),
                onChanged: (val) {
                  final ab = CurrencyFormatter.parse(val);
                  _controller.setAbonoAdicional(ab);
                },
              ),
              if (_controller.totalAbonos > 0) ...[
                const SizedBox(height: 6),
                Text(
                  _controller.montoPendiente > 0
                      ? 'El cliente abonará ${CurrencyFormatter.formatCLP(_controller.totalAbonos)} hoy en Caja. Quedará un saldo pendiente de ${CurrencyFormatter.formatCLP(_controller.montoPendiente)}.'
                      : 'El cliente abonará el total de ${CurrencyFormatter.formatCLP(_controller.totalAbonos)} hoy en Caja.',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.secondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_controller.tieneNotasPreparacion) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppPalette.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.assignment_outlined,
                      size: 16,
                      color: AppPalette.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Notas de Preparación para Bodega:',
                      style: AppTypography.small.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppPalette.primary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._controller.resumenNotasPreparacion.map(
                  (nota) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '• $nota',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.textPrimary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── PASO 4: REVISIÓN FINAL & EMISIÓN (ACID) ──────────────────────────────
  Widget _buildStep4Confirmacion() {
    final cli = _controller.clienteSeleccionado;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '4. Revisión Final y Emisión de Orden',
          style: AppTypography.title.copyWith(fontSize: 16),
        ),
        const SizedBox(height: 14),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppPalette.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RESUMEN DE CLIENTE & ENTREGA',
                style: AppTypography.small.copyWith(
                  color: AppPalette.textSecondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Cliente: ${cli?.nombreCompleto ?? "Consumidor Final"} (${cli?.rut ?? "6.666.666-6"})',
                style: AppTypography.body.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                'Modalidad: Retiro en Mesón / Bodega',
                style: AppTypography.small.copyWith(
                  color: AppPalette.textSecondary,
                ),
              ),
              if (_esVendedorOnline) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppPalette.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppPalette.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.badge_outlined,
                        size: 18,
                        color: AppPalette.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Responsable Entrega: $_nombreResponsableSeleccionado',
                          style: AppTypography.small.copyWith(
                            color: AppPalette.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      InkWell(
                        key: const Key('btn_cambiar_responsable_resumen'),
                        onTap: () => _mostrarDialogoCambioResponsable(),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppPalette.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppPalette.primary.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            'Cambiar',
                            style: AppTypography.small.copyWith(
                              color: AppPalette.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_puedeAsignarVenta && _esVentaReferida) ...[
                const SizedBox(height: 10),
                Container(
                  key: const Key('resumen_venta_asignada_step4'),
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2E1A00), Color(0xFF1A2226)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color:
                          (_idVendedorTitular == null ||
                              _idVendedorTitular!.trim().isEmpty)
                          ? AppPalette.error
                          : AppPalette.secondary,
                      width: 1.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_idVendedorTitular == null ||
                                _idVendedorTitular!.trim().isEmpty)
                            ? AppPalette.error.withValues(alpha: 0.25)
                            : AppPalette.secondary.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (_idVendedorTitular == null ||
                                      _idVendedorTitular!.trim().isEmpty)
                                  ? AppPalette.error
                                  : AppPalette.secondary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.assignment_ind,
                                  size: 15,
                                  color:
                                      (_idVendedorTitular == null ||
                                          _idVendedorTitular!.trim().isEmpty)
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'VENTA DESIGNADA',
                                  style: TextStyle(
                                    color:
                                        (_idVendedorTitular == null ||
                                            _idVendedorTitular!.trim().isEmpty)
                                        ? Colors.white
                                        : Colors.black,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            'Comisión & Orden Externa',
                            style: TextStyle(
                              color: AppPalette.secondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Venta a nombre de:',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _nombreVendedorTitularSeleccionado,
                        style: TextStyle(
                          color:
                              (_idVendedorTitular == null ||
                                  _idVendedorTitular!.trim().isEmpty)
                              ? AppPalette.error
                              : AppPalette.secondary,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.storefront_outlined,
                              size: 16,
                              color: AppPalette.primary,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                'Responsable de Entrega Física: Tú (${_esJefeDeVentas ? "Jefe de Ventas" : "Vendedor"})',
                                style: AppTypography.small.copyWith(
                                  color: AppPalette.textPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Divider(color: Colors.white24, height: 20),

              Text(
                'DETALLE COMERCIAL',
                style: AppTypography.small.copyWith(
                  color: AppPalette.textSecondary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              _buildResumenRow(
                'Total Artículos:',
                '${_controller.totalItemsCount}',
              ),
              if (_controller.subtotalInventario > 0)
                _buildResumenRow(
                  'Subtotal Repuestos Inventario:',
                  CurrencyFormatter.formatCLP(_controller.subtotalInventario),
                ),
              if (_controller.subtotalManuales > 0)
                _buildResumenRow(
                  'Subtotal Ítems Manuales:',
                  CurrencyFormatter.formatCLP(_controller.subtotalManuales),
                ),
              if (_controller.subtotalReservas > 0)
                _buildResumenRow(
                  'Subtotal Ventas en Verde:',
                  CurrencyFormatter.formatCLP(_controller.subtotalReservas),
                ),
              if (_controller.descuento > 0)
                _buildResumenRow(
                  'Descuento a Favor:',
                  '- ${CurrencyFormatter.formatCLP(_controller.descuento)}',
                  color: const Color(0xFFEF5350),
                ),
              const Divider(color: Colors.white24, height: 20),
              _buildResumenRow(
                'TOTAL DE LA VENTA:',
                CurrencyFormatter.formatCLP(_controller.totalVenta),
                isBold: true,
                color: AppPalette.primary,
              ),
              if (_controller.totalAbonos > 0) ...[
                const SizedBox(height: 6),
                _buildResumenRow(
                  'Abono a Pagar Hoy en Caja:',
                  CurrencyFormatter.formatCLP(_controller.totalAbonos),
                  isBold: true,
                  color: AppPalette.primary,
                ),
                if (_controller.montoPendiente > 0)
                  _buildResumenRow(
                    'Saldo Pendiente:',
                    CurrencyFormatter.formatCLP(_controller.montoPendiente),
                    isBold: true,
                    color: const Color(0xFFFFA726),
                  ),
              ],
            ],
          ),
        ),
        if (_controller.totalAbonos > 0) ...[
          const SizedBox(height: 12),
          Container(
            key: const Key('banner_instruccion_abono_step4'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppPalette.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppPalette.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppPalette.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _controller.montoPendiente > 0
                        ? 'El cliente debe pagar un abono de ${CurrencyFormatter.formatCLP(_controller.totalAbonos)} en caja para formalizar la reserva. Saldo pendiente: ${CurrencyFormatter.formatCLP(_controller.montoPendiente)}.'
                        : 'El cliente debe cancelar el total de ${CurrencyFormatter.formatCLP(_controller.totalAbonos)} en caja.',
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),

        if (_puedeAsignarVenta &&
            _esVentaReferida &&
            (_idVendedorTitular == null ||
                _idVendedorTitular!.trim().isEmpty)) ...[
          Container(
            key: const Key('alerta_titular_requerido'),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppPalette.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppPalette.error.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppPalette.error,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Debes seleccionar al vendedor titular para atribuir la venta antes de confirmar la orden.',
                    style: AppTypography.small.copyWith(
                      color: AppPalette.error,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.success,
              disabledBackgroundColor: AppPalette.success.withValues(
                alpha: 0.25,
              ),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: _controller.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline, size: 22),
            label: Text(
              _controller.isLoading
                  ? 'Emitiendo Orden...'
                  : (_puedeAsignarVenta &&
                            _esVentaReferida &&
                            (_idVendedorTitular == null ||
                                _idVendedorTitular!.trim().isEmpty)
                        ? 'SELECCIONA VENDEDOR TITULAR PARA CONTINUAR'
                        : 'CONFIRMAR Y EMITIR ORDEN'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed:
                (_controller.isLoading ||
                    (_puedeAsignarVenta &&
                        _esVentaReferida &&
                        (_idVendedorTitular == null ||
                            _idVendedorTitular!.trim().isEmpty)))
                ? null
                : _confirmarYEnviarOrden,
          ),
        ),
      ],
    );
  }

  Widget _buildResumenRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                fontSize: isBold ? 15.5 : 14.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: color ?? Colors.white,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                fontSize: isBold ? 16.5 : 14.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationButtons() {
    if (_controller.currentStep == 0 && _controller.totalItemsCount == 0) {
      return const SizedBox.shrink();
    }

    final bool puedeAvanzar;
    if (_controller.currentStep == 0) {
      puedeAvanzar =
          _controller.totalItemsCount > 0 &&
          !CartController.instance.hayPreciosInvalidos;
    } else if (_controller.currentStep == 1) {
      if (_esClienteAnonimo) {
        puedeAvanzar = true;
      } else {
        final rut = _rutController.text.trim();
        final nom = _clienteNombresController.text.trim();
        puedeAvanzar =
            rut.isNotEmpty && nom.isNotEmpty && RutValidator.isValid(rut);
      }
    } else if (_controller.currentStep == 2) {
      puedeAvanzar = _controller.totalAbonos <= _controller.totalVenta;
    } else {
      puedeAvanzar = true;
    }

    final bool mostrarAnterior = _controller.currentStep > 0;
    final bool mostrarSiguiente = _controller.currentStep < 3;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double availableWidth = constraints.maxWidth;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (mostrarAnterior)
              _buildBotonAnteriorAnimado(availableWidth)
            else
              const SizedBox.shrink(),

            if (mostrarSiguiente)
              _buildBotonSiguienteAnimado(availableWidth, puedeAvanzar)
            else
              const SizedBox.shrink(),
          ],
        );
      },
    );
  }

  Widget _buildBotonAnteriorAnimado(double availableWidth) {
    final bool isExpanded = (_controller.currentStep == 3);
    final double targetWidth = isExpanded ? (availableWidth * 0.4) : 52.0;
    final double targetRadius = isExpanded ? 12.0 : 26.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      width: targetWidth,
      height: 52,
      child: ElevatedButton(
        key: const Key('btn_anterior_wizard'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.surface,
          foregroundColor: AppPalette.textPrimary,
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.5),
          side: const BorderSide(color: Colors.white24, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(targetRadius),
          ),
          padding: EdgeInsets.zero,
        ),
        onPressed: _controller.isLoading ? null : _controller.previousStep,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: isExpanded
              ? const SingleChildScrollView(
                  key: ValueKey('expanded_anterior'),
                  scrollDirection: Axis.horizontal,
                  physics: NeverScrollableScrollPhysics(),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'Anterior',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : const Icon(
                  key: ValueKey('collapsed_anterior'),
                  Icons.arrow_back,
                  size: 24,
                ),
        ),
      ),
    );
  }

  Widget _buildBotonSiguienteAnimado(double availableWidth, bool puedeAvanzar) {
    final bool isExpanded = (_controller.currentStep == 0);
    final double targetWidth = isExpanded ? (availableWidth * 0.4) : 52.0;
    final double targetRadius = isExpanded ? 12.0 : 26.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      width: targetWidth,
      height: 52,
      child: ElevatedButton(
        key: const Key('btn_siguiente_wizard'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.primary,
          foregroundColor: AppPalette.textPrimary,
          disabledBackgroundColor: AppPalette.surface.withValues(alpha: 0.6),
          disabledForegroundColor: AppPalette.textSecondary.withValues(
            alpha: 0.6,
          ),
          elevation: puedeAvanzar ? 6 : 0,
          shadowColor: Colors.black.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(targetRadius),
          ),
          padding: EdgeInsets.zero,
        ),
        onPressed: puedeAvanzar ? _ejecutarAvanzarPaso : null,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: isExpanded
              ? const SingleChildScrollView(
                  key: ValueKey('expanded_siguiente'),
                  scrollDirection: Axis.horizontal,
                  physics: NeverScrollableScrollPhysics(),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Siguiente',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward, size: 18),
                    ],
                  ),
                )
              : const Icon(
                  key: ValueKey('collapsed_siguiente'),
                  Icons.arrow_forward,
                  size: 24,
                ),
        ),
      ),
    );
  }

  void _ejecutarAvanzarPaso() {
    if (_controller.currentStep == 1) {
      if (_esClienteAnonimo) {
        _controller.setCliente(
          const ClienteWizardModel(
            idCliente: 'cli-cf',
            rut: '6.666.666-6',
            nombres: 'Consumidor',
            apellidos: 'Final',
            comuna: 'Viña del Mar',
            consentimientoLegal: true,
            estado: 'Activo',
          ),
        );
      } else {
        _actualizarClienteLocal();
      }
      _prellenarDatosDespachoSiAplica();
    } else if (_controller.currentStep == 2) {
      _actualizarDatosDespachoLocal();
    }
    _controller.nextStep();
  }

  // ── Helpers Asignación de Responsable en Tienda (Vendedor Online) ───────────
  String get _nombreResponsableSeleccionado {
    if (_idVendedorAsignado == null || _idVendedorAsignado!.trim().isEmpty) {
      return 'Mesón General (Todos los vendedores)';
    }
    final v = _vendedoresDisponibles.cast<VendedorModel?>().firstWhere(
      (v) => v?.idUsuario == _idVendedorAsignado,
      orElse: () => null,
    );
    return v != null
        ? '[${v.etiquetaRol}] ${v.nombreCompleto}'
        : 'Responsable Asignado';
  }

  // ── Helpers Atribución de Venta (Jefe de Ventas) ───────────────────────────
  String get _nombreVendedorTitularSeleccionado {
    if (_idVendedorTitular == null || _idVendedorTitular!.trim().isEmpty) {
      return 'Sin Seleccionar (Obligatorio)';
    }
    final v = _vendedoresDisponibles.cast<VendedorModel?>().firstWhere(
      (v) => v?.idUsuario == _idVendedorTitular,
      orElse: () => null,
    );
    return v != null
        ? '[${v.etiquetaRol}] ${v.nombreCompleto}'
        : 'Vendedor Titular Seleccionado';
  }

  Widget _buildCardVentaReferida() {
    return Container(
      key: const Key('card_venta_referida'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surface, // Fondo gris oscuro
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _esVentaReferida
              ? AppPalette.primary.withValues(alpha: 0.6)
              : Colors.white12,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppPalette.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.person_pin_outlined,
                  size: 20,
                  color: AppPalette.primary, // Icono celeste
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'VENTA REFERIDA / ATRIBUCIÓN',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.primary, // Letras celestes
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Switch(
                key: const Key('switch_venta_referida'),
                value: _esVentaReferida,
                activeThumbColor: AppPalette.primary,
                activeTrackColor: AppPalette.primary.withValues(alpha: 0.3),
                inactiveThumbColor: Colors.white54,
                inactiveTrackColor: Colors.white12,
                onChanged: (val) {
                  setState(() {
                    _esVentaReferida = val;
                    if (val) {
                      // Predeterminar a la Vendedora Online si existe en la lista
                      final online = _vendedoresDisponibles
                          .cast<VendedorModel?>()
                          .firstWhere(
                            (v) => v != null && v.esVendedoraOnline,
                            orElse: () => null,
                          );
                      final titularId =
                          online?.idUsuario ??
                          (_vendedoresDisponibles.isNotEmpty
                              ? _vendedoresDisponibles.first.idUsuario
                              : null);
                      _idVendedorTitular = titularId;
                      _controller.setIdVendedorTitular(titularId);
                      if (_currentUserId != null) {
                        _idVendedorAsignado = _currentUserId;
                        _controller.setIdVendedorAsignado(_currentUserId);
                      }
                    } else {
                      _idVendedorTitular = null;
                      _controller.setIdVendedorTitular(null);
                    }
                  });
                },
              ),
            ],
          ),
          if (_esVentaReferida) ...[
            const SizedBox(height: 14),
            Text(
              'Asignar comisión y métricas de venta a:',
              style: AppTypography.small.copyWith(
                color: AppPalette.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppPalette.background, // Fondo gris
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppPalette.primary.withValues(
                    alpha: 0.5,
                  ), // Borde celeste
                  width: 1.2,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  key: const Key('dropdown_vendedor_titular'),
                  value: _idVendedorTitular,
                  dropdownColor: AppPalette.surface,
                  isExpanded: true,
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    color: AppPalette.primary,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        '-- Selecciona Vendedor Titular --',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    ..._vendedoresDisponibles.map(
                      (v) => DropdownMenuItem<String?>(
                        value: v.idUsuario,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: v.esLimache
                                    ? const Color(0xFFD97706).withValues(alpha: 0.25)
                                    : (v.esVendedoraOnline
                                        ? Colors.purple.withValues(alpha: 0.25)
                                        : (v.esJefeDeVentas
                                            ? AppPalette.primary.withValues(alpha: 0.2)
                                            : Colors.white.withValues(alpha: 0.08))),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: v.esLimache
                                      ? const Color(0xFFF59E0B)
                                      : (v.esVendedoraOnline
                                          ? Colors.purpleAccent
                                          : (v.esJefeDeVentas
                                              ? AppPalette.primary
                                              : Colors.white24)),
                                ),
                              ),
                              child: Text(
                                v.etiquetaRol.toUpperCase(),
                                style: TextStyle(
                                  color: v.esLimache
                                      ? const Color(0xFFF59E0B)
                                      : (v.esVendedoraOnline
                                          ? Colors.purpleAccent
                                          : (v.esJefeDeVentas
                                              ? AppPalette.primary
                                              : Colors.white70)),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${v.nombreCompleto} (${v.rut})',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppPalette.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _idVendedorTitular = val;
                    });
                    _controller.setIdVendedorTitular(val);
                    if (_currentUserId != null) {
                      _idVendedorAsignado = _currentUserId;
                      _controller.setIdVendedorAsignado(_currentUserId);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: AppPalette.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Tú (${_esJefeDeVentas ? "Jefe de Ventas" : "Vendedor"}) quedarás registrado para entregar físicamente los repuestos en sucursal.',
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardResponsableEntrega() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surface, // Fondo gris oscuro
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppPalette.primary.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppPalette.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.badge_outlined,
                  size: 20,
                  color: AppPalette.primary, // Icono celeste
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RESPONSABLE DE ENTREGA EN SUCURSAL',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.primary, // Letras celestes
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      'Designa al Jefe de Ventas o Vendedor de Mesón que entregará el pedido y mostrará el QR a bodega',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppPalette.background, // Fondo gris
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppPalette.primary.withValues(
                  alpha: 0.5,
                ), // Borde celeste
                width: 1.2,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                key: const Key('dropdown_responsable_entrega'),
                value: _idVendedorAsignado,
                dropdownColor: AppPalette.surface, // Fondo gris de opciones
                isExpanded: true,
                icon: const Icon(
                  Icons.arrow_drop_down,
                  color: AppPalette.primary, // Flecha celeste
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppPalette.secondary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppPalette.secondary),
                          ),
                          child: const Text(
                            'MESÓN',
                            style: TextStyle(
                              color: AppPalette.secondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Mesón General (Todos los vendedores)',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppPalette.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  ..._vendedoresDisponibles.map(
                    (v) => DropdownMenuItem<String?>(
                      value: v.idUsuario,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: v.esJefeDeVentas
                                  ? AppPalette.primary.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: v.esJefeDeVentas
                                    ? AppPalette.primary
                                    : Colors.white24,
                              ),
                            ),
                            child: Text(
                              v.etiquetaRol.toUpperCase(),
                              style: TextStyle(
                                color: v.esJefeDeVentas
                                    ? AppPalette.primary
                                    : Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${v.nombreCompleto} (${v.rut})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppPalette.primary, // Letras celestes
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                onChanged: (val) {
                  setState(() {
                    _idVendedorAsignado = val;
                  });
                  _controller.setIdVendedorAsignado(val);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoCambioResponsable() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            backgroundColor: AppPalette.surface, // Fondo gris
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: AppPalette.primary.withValues(alpha: 0.4),
              ),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.badge_outlined,
                  color: AppPalette.primary, // Icono celeste
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Asignar Responsable',
                  style: AppTypography.title.copyWith(
                    fontSize: 16,
                    color: AppPalette.primary, // Letras celestes
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selecciona al Jefe de Ventas o Vendedor de Mesón responsable de entregar este pedido en sucursal:',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppPalette.background, // Fondo gris
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppPalette.primary.withValues(
                        alpha: 0.5,
                      ), // Borde celeste
                      width: 1.2,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      key: const Key('dropdown_responsable_dialog'),
                      value: _idVendedorAsignado,
                      dropdownColor: AppPalette.surface,
                      isExpanded: true,
                      icon: const Icon(
                        Icons.arrow_drop_down,
                        color: AppPalette.primary,
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: AppPalette.secondary.withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: AppPalette.secondary,
                                  ),
                                ),
                                child: const Text(
                                  'MESÓN',
                                  style: TextStyle(
                                    color: AppPalette.secondary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Mesón General (Todos los vendedores)',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppPalette.primary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ..._vendedoresDisponibles.map(
                          (v) => DropdownMenuItem<String?>(
                            value: v.idUsuario,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: v.esJefeDeVentas
                                        ? AppPalette.primary.withValues(
                                            alpha: 0.2,
                                          )
                                        : Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: v.esJefeDeVentas
                                          ? AppPalette.primary
                                          : Colors.white24,
                                    ),
                                  ),
                                  child: Text(
                                    v.etiquetaRol.toUpperCase(),
                                    style: TextStyle(
                                      color: v.esJefeDeVentas
                                          ? AppPalette.primary
                                          : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${v.nombreCompleto} (${v.rut})',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color:
                                          AppPalette.primary, // Letras celestes
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        setModalState(() {});
                        setState(() {
                          _idVendedorAsignado = val;
                        });
                        _controller.setIdVendedorAsignado(val);
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'CERRAR',
                  style: TextStyle(color: AppPalette.primary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFieldHeader(String title, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Icon(icon, size: 15, color: AppPalette.primary),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title,
              style: AppTypography.body.copyWith(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                height: 1.25,
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco({
    String? hint,
    Widget? suffix,
    String? errorText,
  }) {
    return InputDecoration(
      isDense: true,
      labelText: null,
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
      suffixIcon: suffix,
      errorText: errorText,
      errorStyle: const TextStyle(
        color: AppPalette.error,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
      filled: true,
      fillColor: AppPalette.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF334155), width: 1.0),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF334155), width: 1.0),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppPalette.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppPalette.error, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
      ),
    );
  }
}
