import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/checkout_wizard_models.dart';
import '../services/ventas_service.dart';
import 'cart_controller.dart';

/// Controlador reactivo del estado para el Checkout Wizard por Pasos (SPEC-HU-05)
class CheckoutWizardController extends ChangeNotifier {
  int _currentStep = 0;
  bool _isLoading = false;
  String? _errorMessage;

  // Paso 1: Ítems
  final List<Map<String, dynamic>> _itemsInventariados = [];
  final List<ItemManualModel> _itemsManuales = [];
  final List<ReservaBackorderModel> _reservas = [];

  // Paso 2: Cliente
  ClienteWizardModel? _clienteSeleccionado;

  // Paso 3: Logística y Despacho
  String _tipoEntrega = 'Retiro'; // 'Retiro', 'Despacho Domicilio', 'Traslado'
  int _idSucursalActual = 1; // 1: Viña del Mar, 2: Limache
  int _idSucursalDestino = 2; // Por defecto sucursal opuesta
  String? _idVendedorAsignado; // Para vendedor online o responsable en tienda
  String? _idVendedorTitular; // Para venta referida atribuida a otro vendedor (Jefe de Ventas)
  DespachoModel? _datosDespacho;

  // Paso 4: Abonos, Descuentos y Notas
  int _descuento = 0;
  int _abonoAdicional = 0;
  String _notasGenerales = '';

  // Getters
  int get currentStep => _currentStep;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<Map<String, dynamic>> get itemsInventariados => List.unmodifiable(_itemsInventariados);
  List<ItemManualModel> get itemsManuales => List.unmodifiable(_itemsManuales);
  List<ReservaBackorderModel> get reservas => List.unmodifiable(_reservas);

  ClienteWizardModel? get clienteSeleccionado => _clienteSeleccionado;
  String get tipoEntrega => _tipoEntrega;
  int get idSucursalActual => _idSucursalActual;
  int get idSucursalDestino => _idSucursalDestino;
  String? get idVendedorAsignado => _idVendedorAsignado;
  String? get idVendedorTitular => _idVendedorTitular;
  DespachoModel? get datosDespacho => _datosDespacho;
  int get descuento => _descuento;
  int get abonoAdicional => _abonoAdicional;
  String get notasGenerales => _notasGenerales;

  // Cálculos financieros
  int get subtotalInventario => _itemsInventariados.fold<int>(0, (sum, i) => sum + (int.tryParse(i['precio']?.toString() ?? '0') ?? 0));
  int get subtotalManuales => _itemsManuales.fold<int>(0, (sum, m) => sum + m.precioFinal);
  int get subtotalReservas => _reservas.fold<int>(0, (sum, r) => sum + r.precioAcordado);

  int get subtotal => subtotalInventario + subtotalManuales + subtotalReservas;

  int get totalVenta {
    final t = subtotal - _descuento;
    return t < 0 ? 0 : t;
  }

  int get abonoReservas => _reservas.fold<int>(0, (sum, r) => sum + r.montoAbonado);
  int get totalAbonos => abonoReservas + _abonoAdicional;

  int get montoPendiente {
    final saldo = totalVenta - totalAbonos;
    return saldo < 0 ? 0 : saldo;
  }

  int get totalItemsCount =>
      _itemsInventariados.length +
      _itemsManuales.fold<int>(0, (sum, m) => sum + m.cantidad) +
      _reservas.length;

  /// Indica si la orden en curso corresponde a una Venta en Verde (Reserva Backorder)
  bool get tieneVentaEnVerde =>
      _reservas.isNotEmpty ||
      CartController.instance.tieneVentaEnVerde ||
      _itemsManuales.any((m) {
        final d = m.descripcion.toUpperCase();
        return d.contains('VENTA EN VERDE') ||
            d.contains('COMPRA EN VERDE') ||
            d.contains('BACKORDER');
      });

  // ── Gestión de Pasos (0: Ítems, 1: Cliente, 2: Abonos, 3: Confirmación) ───────
  void setStep(int step) {
    if (step >= 0 && step <= 3) {
      _currentStep = step;
      _errorMessage = null;
      notifyListeners();
    }
  }

  bool nextStep() {
    _errorMessage = null;
    if (_currentStep == 0 && !validateStep1()) {
      _errorMessage = CartController.instance.hayPreciosInvalidos
          ? 'Hay repuestos con precio acordado fuera del rango de tasación permitido. Modifícalos dentro de su rango para continuar.'
          : 'Debes agregar al menos un artículo o servicio para proceder.';
      notifyListeners();
      return false;
    }
    if (_currentStep == 1 && !validateStep2()) {
      _errorMessage = tieneVentaEnVerde
          ? 'Las compras en verde requieren obligatoriamente registrar los datos del cliente (RUT, nombre y apellido válidos).'
          : 'Falta identificar al cliente. Por favor, ingresa un RUT válido antes de proceder con la reserva de estos activos.';
      notifyListeners();
      return false;
    }
    if (_currentStep == 2 && !validateStep3()) {
      _errorMessage = 'El monto de abono no puede ser superior al total de la venta.';
      notifyListeners();
      return false;
    }

    if (_currentStep < 3) {
      _currentStep++;
      notifyListeners();
      return true;
    }
    return true;
  }

  void previousStep() {
    if (_currentStep > 0) {
      _currentStep--;
      _errorMessage = null;
      notifyListeners();
    }
  }

  bool validateStep1() =>
      totalItemsCount > 0 && !CartController.instance.hayPreciosInvalidos;

  bool validateStep2() {
    if (_clienteSeleccionado == null) return false;
    final rut = _clienteSeleccionado!.rut.trim();
    if (rut.isEmpty) return false;

    if (tieneVentaEnVerde) {
      final rutNorm = rut.replaceAll('.', '').replaceAll('-', '').toUpperCase();
      final esConsumidorFinal = rutNorm == '66666666' ||
          rutNorm == '6666666' ||
          rutNorm == '666666666' ||
          _clienteSeleccionado!.nombres.trim().toUpperCase() == 'CONSUMIDOR';
      if (esConsumidorFinal) return false;

      final nom = _clienteSeleccionado!.nombres.trim();
      final ape = _clienteSeleccionado!.apellidos.trim();
      if (nom.isEmpty || ape.isEmpty) return false;

      // Teléfono es opcional: si se ingresó, debe tener al menos 8 dígitos numéricos
      final tel = _clienteSeleccionado!.telefono?.trim() ?? '';
      if (tel.isNotEmpty && tel.replaceAll(RegExp(r'\D'), '').length < 8) {
        return false;
      }

      // Correo es opcional: si se ingresó, debe tener formato válido
      final email = _clienteSeleccionado!.correo?.trim() ?? '';
      final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
      if (email.isNotEmpty && !emailRegex.hasMatch(email)) {
        return false;
      }

      return true;
    }

    return true;
  }

  bool validateStep3() => totalAbonos <= totalVenta;
  bool validateStep4() => totalAbonos <= totalVenta; // Compatibilidad legacy

  // ── Modificadores de Estado ───────────────────────────────────────────────
  void clearErrorMessage() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  bool _limpiarErrorStep1SiAplica() {
    if (_errorMessage == 'Debes agregar al menos un artículo o servicio para proceder.' && totalItemsCount > 0) {
      _errorMessage = null;
      return true;
    }
    return false;
  }

  void addItemInventariado({
    required String idActivo,
    required String sku,
    required String descripcion,
    required int precio,
    String? pasillo,
    String? pallet,
    int? precioMinimo,
    int? precioMaximo,
    String? notasPreparacion,
  }) {
    final idx = _itemsInventariados.indexWhere((i) => i['id_activo'] == idActivo);
    if (idx != -1) {
      final prev = _itemsInventariados[idx];
      bool cambio = false;
      if (prev['precio'] != precio) {
        prev['precio'] = precio;
        cambio = true;
      }
      if (precioMinimo != null && prev['precio_minimo'] != precioMinimo) {
        prev['precio_minimo'] = precioMinimo;
        cambio = true;
      }
      if (precioMaximo != null && prev['precio_maximo'] != precioMaximo) {
        prev['precio_maximo'] = precioMaximo;
        cambio = true;
      }
      if (notasPreparacion != null && prev['notas_preparacion'] != notasPreparacion) {
        prev['notas_preparacion'] = notasPreparacion;
        cambio = true;
      }
      if (cambio) {
        notifyListeners();
      }
    } else {
      _itemsInventariados.add({
        'id_activo': idActivo,
        'sku': sku,
        'descripcion': descripcion,
        'precio': precio,
        'pasillo': pasillo,
        'pallet': pallet,
        'precio_minimo': precioMinimo,
        'precio_maximo': precioMaximo,
        'notas_preparacion': notasPreparacion,
      });
      _limpiarErrorStep1SiAplica();
      notifyListeners();
    }
  }

  void updateItemInventariadoPrecio(String idActivo, int nuevoPrecio) {
    final idx = _itemsInventariados.indexWhere((i) => i['id_activo'] == idActivo);
    if (idx != -1) {
      if (_itemsInventariados[idx]['precio'] != nuevoPrecio) {
        _itemsInventariados[idx]['precio'] = nuevoPrecio;
        notifyListeners();
      }
    }
  }

  void updateItemInventariadoNotas(String idActivo, String? notas) {
    final idx = _itemsInventariados.indexWhere((i) => i['id_activo'] == idActivo);
    if (idx != -1) {
      if (_itemsInventariados[idx]['notas_preparacion'] != notas) {
        _itemsInventariados[idx]['notas_preparacion'] = notas;
        notifyListeners();
      }
    }
  }

  List<String> get resumenNotasPreparacion {
    final List<String> list = [];
    for (final i in _itemsInventariados) {
      final n = i['notas_preparacion']?.toString().trim();
      if (n != null && n.isNotEmpty) {
        list.add('${i['descripcion']} (${i['sku']}): $n');
      }
    }
    for (final r in _reservas) {
      final n = r.notasPreparacion?.trim();
      if (n != null && n.isNotEmpty) {
        list.add('${r.categoriaNombre} (${r.marcaRequerida} ${r.modeloRequerido}): $n');
      }
    }
    return list;
  }

  bool get tieneNotasPreparacion => resumenNotasPreparacion.isNotEmpty;

  void removeItemInventariado(String idActivo) {
    _itemsInventariados.removeWhere((i) => i['id_activo'] == idActivo);
    notifyListeners();
  }

  void addItemManual(ItemManualModel item) {
    _itemsManuales.add(item);
    _limpiarErrorStep1SiAplica();
    notifyListeners();
  }

  void removeItemManual(int index) {
    if (index >= 0 && index < _itemsManuales.length) {
      _itemsManuales.removeAt(index);
      notifyListeners();
    }
  }

  void addReservaBackorder(ReservaBackorderModel reserva) {
    _reservas.add(reserva);
    _limpiarErrorStep1SiAplica();
    notifyListeners();
  }

  void removeReservaBackorder(int index) {
    if (index >= 0 && index < _reservas.length) {
      _reservas.removeAt(index);
      notifyListeners();
    }
  }

  void setCliente(ClienteWizardModel? cliente) {
    _clienteSeleccionado = cliente;
    _errorMessage = null;
    notifyListeners();
  }

  void setTipoEntrega(String tipo) {
    _tipoEntrega = tipo;
    if (_errorMessage == 'Complete todos los campos obligatorios para el despacho a domicilio.' && validateStep3()) {
      _errorMessage = null;
    }
    notifyListeners();
  }

  void setIdSucursalActual(int sucursalId) {
    _idSucursalActual = sucursalId;
    if (_idSucursalDestino == _idSucursalActual) {
      _idSucursalDestino = (_idSucursalActual == 1) ? 2 : 1;
    }
    notifyListeners();
  }

  void setIdSucursalDestino(int sucursalId) {
    _idSucursalDestino = sucursalId;
    notifyListeners();
  }

  void setIdVendedorAsignado(String? vendedorId) {
    _idVendedorAsignado = vendedorId;
    notifyListeners();
  }

  void setIdVendedorTitular(String? vendedorId) {
    _idVendedorTitular = vendedorId;
    notifyListeners();
  }

  void setDatosDespacho(DespachoModel? despacho) {
    _datosDespacho = despacho;
    if (_errorMessage == 'Complete todos los campos obligatorios para el despacho a domicilio.' && validateStep3()) {
      _errorMessage = null;
    }
    notifyListeners();
  }

  void setDescuento(int valor) {
    _descuento = valor < 0 ? 0 : valor;
    if (_descuento > subtotal) {
      _descuento = subtotal;
    }
    notifyListeners();
  }

  void setAbonoAdicional(int abono) {
    _abonoAdicional = abono < 0 ? 0 : abono;
    if (_errorMessage == 'El monto de abono no puede ser superior al total de la venta.' && validateStep4()) {
      _errorMessage = null;
    }
    notifyListeners();
  }

  void setNotasGenerales(String notas) {
    _notasGenerales = notas;
    notifyListeners();
  }

  void clearAll() {
    _currentStep = 0;
    _isLoading = false;
    _errorMessage = null;
    _itemsInventariados.clear();
    _itemsManuales.clear();
    _reservas.clear();
    _clienteSeleccionado = null;
    _tipoEntrega = 'Retiro';
    _idSucursalDestino = 1;
    _idVendedorAsignado = null;
    _idVendedorTitular = null;
    _datosDespacho = null;
    _descuento = 0;
    _abonoAdicional = 0;
    _notasGenerales = '';
    notifyListeners();
  }

  // ── Emisión Transaccional (ACID) ──────────────────────────────────────────
  Future<CheckoutWizardResponseModel?> submitOrder({http.Client? client}) async {
    if (!validateStep1() || !validateStep2() || !validateStep3() || !validateStep4()) {
      _errorMessage = (tieneVentaEnVerde && !validateStep2())
          ? 'Las compras en verde requieren obligatoriamente registrar los datos del cliente (RUT, nombre, apellido, teléfono y correo válido).'
          : 'Por favor complete todos los datos requeridos antes de emitir la orden.';
      notifyListeners();
      return null;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Consolidar notas de preparación de todos los ítems para bodega
      final String bodegaNotas = resumenNotasPreparacion.isNotEmpty
          ? resumenNotasPreparacion.join(' • ')
          : _notasGenerales;

      final int abonoFinal = (totalAbonos >= totalVenta) ? 0 : totalAbonos;
      final int saldoFinal = (totalAbonos >= totalVenta) ? totalVenta : montoPendiente;

      final request = CheckoutWizardRequestModel(
        idCliente: _clienteSeleccionado!.idCliente,
        cliente: _clienteSeleccionado,
        tipoEntrega: 'Retiro',
        idSucursalDestino: null,
        idVendedorAsignado: _idVendedorAsignado,
        idVendedorTitular: _idVendedorTitular,
        totalVenta: totalVenta,
        descuento: _descuento,
        montoPendiente: saldoFinal,
        montoAbono: abonoFinal,
        instruccionesBodega: bodegaNotas,
        itemsInventariados: _itemsInventariados.map((i) => {
          'id_activo': i['id_activo'].toString(),
          'precio_final': int.tryParse(i['precio']?.toString() ?? '0') ?? 0,
          if (i['notas_preparacion'] != null && i['notas_preparacion'].toString().isNotEmpty)
            'notas_preparacion': i['notas_preparacion'].toString(),
        }).toList(),
        itemsManuales: _itemsManuales,
        reservas: _reservas,
        datosDespacho: null,
      );

      final response = await VentasService.processCheckoutWizard(request, client: client);

      _isLoading = false;
      notifyListeners();
      return response;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      notifyListeners();
      return null;
    }
  }
}
