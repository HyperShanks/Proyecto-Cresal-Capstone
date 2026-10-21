import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/cobro_pendiente_model.dart';
import '../../models/cobro_model.dart';
import '../../services/caja_service.dart';
import '../../../../core/services/api_service.dart';
import '../../../ventas/services/ordenes_sync_notifier.dart';

/// Proveedor de estado reactivo para la Bandeja de Cobros y Panel de Cobro de Caja (SPEC-HU-03).
/// Maneja la lista de cobros pendientes, la selección activa Master-Detail,
/// el selector de píldoras, la búsqueda reactiva y la pasarela reactiva de pagos divididos (Split).
class CajaProvider extends ChangeNotifier {
  final ICajaService _cajaService;

  List<CobroPendienteModel> _todosLosCobros = [];
  List<CobroPendienteModel> _cobrosFiltrados = [];
  CobroPendienteModel? _ordenSeleccionada;
  String _filtroTipo = 'VENTA'; // 'VENTA' | 'ABONOS' | 'BACKORDER' | 'TODOS'
  String _terminoBusqueda = '';
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  int _sucursalId = 1;

  Timer? _debounceTimer;

  // ── ESTADO REACTIVO DE COBRO ACTIVO (SPEC-HU-03) ──
  String _modalidad = 'LIQUIDACION'; // 'LIQUIDACION' | 'ABONO'
  String _modalidadPago = 'UNICO'; // 'UNICO' | 'SPLIT'
  int _montoDeclarado = 0;
  List<TransaccionPagoItemModel> _pagosDivididos = [];
  bool _isProcesandoCobro = false;
  RegistrarCobroResponseModel? _ultimoResultadoCobro;

  CajaProvider({
    ICajaService? cajaService,
  }) : _cajaService = cajaService ?? CajaService();

  List<CobroPendienteModel> get cobros => _cobrosFiltrados;
  CobroPendienteModel? get ordenSeleccionada => _ordenSeleccionada;
  String get filtroTipo => _filtroTipo;
  String get terminoBusqueda => _terminoBusqueda;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  String? get errorMessage => _errorMessage;
  int get totalCobros => _todosLosCobros.length;

  int get totalNuevasCount =>
      _todosLosCobros.where((c) => c.abonoPrevio == 0).length;
  int get totalVentasCount =>
      _todosLosCobros.where((c) => c.esVenta && c.abonoPrevio == 0).length;
  int get totalAbonosCount =>
      _todosLosCobros.where((c) => c.abonoPrevio > 0 && c.saldoPendiente > 0).length;
  int get totalBackordersCount =>
      _todosLosCobros.where((c) => c.esBackorder && c.abonoPrevio == 0).length;

  int get montoTotalPendiente =>
      _todosLosCobros.fold(0, (sum, item) => sum + item.montoACobrar);

  // ── GETTERS DE COBRO & CUADRATURA (SPEC-HU-03) ──
  String get modalidad => _modalidad;
  String get modalidadPago => _modalidadPago;
  int get montoDeclarado => _montoDeclarado;
  List<TransaccionPagoItemModel> get pagosDivididos =>
      List.unmodifiable(_pagosDivididos);
  bool get isProcesandoCobro => _isProcesandoCobro;
  RegistrarCobroResponseModel? get ultimoResultadoCobro =>
      _ultimoResultadoCobro;

  int get totalPagosIngresados =>
      _pagosDivididos.fold(0, (sum, p) => sum + p.monto);

  int get diferenciaCuadratura => _montoDeclarado - totalPagosIngresados;

  int get saldoPendienteActual {
    if (_ordenSeleccionada == null) return 0;
    if (_ordenSeleccionada!.saldoPendiente > 0) {
      return _ordenSeleccionada!.saldoPendiente;
    }
    return _ordenSeleccionada!.montoACobrar > 0
        ? _ordenSeleccionada!.montoACobrar
        : _ordenSeleccionada!.totalOperacion;
  }

  bool get esLiquidacionCompleta =>
      _ordenSeleccionada != null && _montoDeclarado >= saldoPendienteActual && saldoPendienteActual > 0;

  bool get esPrimerAbonoInvalido {
    if (_ordenSeleccionada == null) return false;
    if (!_ordenSeleccionada!.esPrimerAbono) return false;
    final piso = _ordenSeleccionada!.pisoPrimerAbono;
    if (piso <= 0) return false;
    // Si el cliente liquida el 100% de una vez, es válido
    return _montoDeclarado < piso && _montoDeclarado < saldoPendienteActual;
  }

  String? get errorMontoAbono {
    if (_ordenSeleccionada == null) return null;
    if (_montoDeclarado <= 0) {
      return 'El monto a pagar debe ser mayor a \$0.';
    }
    if (_montoDeclarado > saldoPendienteActual) {
      final maxFmt = saldoPendienteActual.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
      return 'El monto supera el saldo pendiente de \$$maxFmt.';
    }
    if (esPrimerAbonoInvalido) {
      final pisoFmt = _ordenSeleccionada!.pisoPrimerAbono.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
      return 'El primer abono no puede ser inferior al mínimo acordado de \$$pisoFmt.';
    }
    return null;
  }

  /// Valida que el monto declarado esté dentro del rango permitido.
  bool get esMontoValido => errorMontoAbono == null;

  /// Indica si el monto declarado excede el saldo pendiente de la orden.
  bool get esMontoExcedido =>
      _ordenSeleccionada != null && _montoDeclarado > saldoPendienteActual;

  bool get esCuadraturaValida =>
      diferenciaCuadratura == 0 &&
      esMontoValido &&
      _pagosDivididos.isNotEmpty &&
      _pagosDivididos.every((p) => p.monto > 0);

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Carga la lista de cobros pendientes desde la API.
  Future<void> cargarCobrosPendientes({
    bool refresh = false,
    int? sucursalId,
  }) async {
    if (refresh) {
      _isRefreshing = true;
    } else {
      _isLoading = true;
    }
    _errorMessage = null;
    notifyListeners();

    try {
      if (sucursalId != null) {
        _sucursalId = sucursalId;
      }

      final items = await _cajaService.obtenerCobrosPendientes(
        sucursalId: _sucursalId,
        busqueda: null,
        tipoOperacion: 'TODOS',
      );

      _todosLosCobros = items;
      _aplicarFiltrosLocales();
    } on CustomApiException catch (e) {
      _errorMessage = e.messageUser;
    } catch (e) {
      _errorMessage = ApiService.limpiarMensajeExcepcion(e);
    } finally {
      _isLoading = false;
      _isRefreshing = false;
      notifyListeners();
    }
  }

  /// Consulta periódica en segundo plano sin interrumpir ni mostrar loaders (SPEC-HU-TAREA-21).
  /// Respeta el cobro activo si la cajera está ingresando montos o pagos divididos.
  Future<void> cargarCobrosPendientesSilencioso({int? sucursalId}) async {
    // Si se está procesando un cobro o la cajera ya ingresó pagos divididos, no interrumpir
    if (_isProcesandoCobro || _pagosDivididos.isNotEmpty) {
      debugPrint('[CajaProvider] Polling omitido: Cobro en curso o pagos ingresados.');
      return;
    }

    try {
      if (sucursalId != null) {
        _sucursalId = sucursalId;
      }

      final items = await _cajaService.obtenerCobrosPendientes(
        sucursalId: _sucursalId,
        busqueda: null,
        tipoOperacion: 'TODOS',
      );

      // Reconciliación en memoria: verificar si hubo cambios reales
      final idsActuales = _todosLosCobros.map((c) => '${c.idReferencia}_${c.saldoPendiente}').join(',');
      final idsNuevos = items.map((c) => '${c.idReferencia}_${c.saldoPendiente}').join(',');

      if (idsActuales == idsNuevos) {
        // Cero cambios: no llamamos notifyListeners() para evitar repaints innecesarios
        return;
      }

      _todosLosCobros = items;
      _aplicarFiltrosLocales();
      notifyListeners();
    } catch (e) {
      debugPrint('[CajaProvider] Error en sondeo silencioso (ignorado): $e');
    }
  }

  /// Aplica los filtros de píldoras y búsqueda sobre la colección en memoria.
  void _aplicarFiltrosLocales() {
    var resultado = List<CobroPendienteModel>.from(_todosLosCobros);

    // Búsqueda global reactiva: si hay término de búsqueda, busca en todo el universo de cobros
    if (_terminoBusqueda.trim().isNotEmpty) {
      final query = _terminoBusqueda.trim().toLowerCase();
      resultado = resultado.where((c) {
        final folio = c.folioDocumento.toLowerCase();
        final cliente = c.clienteNombre.toLowerCase();
        final rut = c.clienteRut.toLowerCase();
        final vendedor = c.vendedorNombre.toLowerCase();
        return folio.contains(query) ||
            cliente.contains(query) ||
            rut.contains(query) ||
            vendedor.contains(query);
      }).toList();
    } else {
      // Si no hay búsqueda activa, se aplica el filtro de la píldora seleccionada
      if (_filtroTipo == 'NUEVAS' || _filtroTipo == 'VENTA') {
        resultado = resultado.where((c) => c.abonoPrevio == 0).toList();
      } else if (_filtroTipo == 'ABONOS' || _filtroTipo == 'ABONO') {
        resultado = resultado.where((c) => c.abonoPrevio > 0 && c.saldoPendiente > 0).toList();
      } else if (_filtroTipo == 'BACKORDER') {
        resultado = resultado.where((c) => c.esBackorder && c.abonoPrevio == 0).toList();
      }
      // Si _filtroTipo == 'TODOS', se preserva el listado completo
    }

    _cobrosFiltrados = resultado;

    // Mantener seleccionada la orden actual si aún existe en la lista filtrada, o resetear
    if (_ordenSeleccionada != null) {
      final encontrada = _cobrosFiltrados
          .where((o) => o.idReferencia == _ordenSeleccionada!.idReferencia);
      if (encontrada.isNotEmpty) {
        _ordenSeleccionada = encontrada.first;
      } else {
        _ordenSeleccionada = null;
        _montoDeclarado = 0;
        _pagosDivididos = [];
      }
    }
  }

  /// Selecciona una orden para desplegar en el panel de detalle derecho (Master-Detail).
  /// Inicializa automáticamente la pasarela en Liquidación total con Efectivo (Pago Único).
  void seleccionarOrden(CobroPendienteModel? orden) {
    if (_ordenSeleccionada?.idReferencia == orden?.idReferencia &&
        orden != null) {
      return;
    }
    _ordenSeleccionada = orden;
    _ultimoResultadoCobro = null;
    if (orden != null) {
      final int abonoInicial =
          orden.abonoRequerido > 0 ? orden.abonoRequerido : orden.montoACobrar;
      final bool tieneAbonoAcordado = orden.esPrimerAbono &&
          abonoInicial > 0 &&
          abonoInicial < orden.totalOperacion &&
          orden.saldoPendiente > 0;

      if (tieneAbonoAcordado) {
        _modalidad = 'ABONO';
        _montoDeclarado = abonoInicial;
      } else if (orden.esPrimerAbono &&
          orden.pisoPrimerAbono > 0 &&
          orden.pisoPrimerAbono < orden.totalOperacion) {
        _modalidad = 'ABONO';
        _montoDeclarado = orden.pisoPrimerAbono;
      } else {
        _modalidad = 'LIQUIDACION';
        _montoDeclarado = orden.saldoPendiente > 0 ? orden.saldoPendiente : orden.totalOperacion;
      }
      _modalidadPago = 'UNICO';
      _pagosDivididos = [
        TransaccionPagoItemModel(metodo: 'Efectivo', monto: _montoDeclarado),
      ];
    } else {
      _modalidad = 'LIQUIDACION';
      _modalidadPago = 'UNICO';
      _montoDeclarado = 0;
      _pagosDivididos = [];
    }
    notifyListeners();
  }

  /// Indica si la orden seleccionada requiere obligatoriamente un abono inicial y tiene bloqueada la liquidación directa en el primer cobro.
  bool get tieneBloqueoLiquidacionInicial {
    if (_ordenSeleccionada == null) return false;
    final o = _ordenSeleccionada!;
    final abonoInicial = o.abonoRequerido > 0
        ? o.abonoRequerido
        : (o.pisoPrimerAbono > 0
            ? o.pisoPrimerAbono
            : (o.montoACobrar > 0 && o.montoACobrar < o.totalOperacion
                ? o.montoACobrar
                : 0));
    return o.esPrimerAbono &&
        abonoInicial > 0 &&
        abonoInicial < o.totalOperacion &&
        o.saldoPendiente > 0;
  }

  /// Cambia la modalidad de cobro ('LIQUIDACION' | 'ABONO').
  void setModalidad(String nuevaModalidad) {
    final modNorm = nuevaModalidad.toUpperCase();
    if (_modalidad == modNorm) return;

    if (modNorm == 'LIQUIDACION' && tieneBloqueoLiquidacionInicial) {
      // Bloqueo preventivo: orden con abono inicial obligatorio no permite liquidación en el primer cobro
      return;
    }

    _modalidad = modNorm;

    if (_ordenSeleccionada != null) {
      final saldo = _ordenSeleccionada!.saldoPendiente > 0
          ? _ordenSeleccionada!.saldoPendiente
          : _ordenSeleccionada!.totalOperacion;

      if (_modalidad == 'LIQUIDACION') {
        _montoDeclarado = saldo;
      } else if (_modalidad == 'ABONO') {
        final abonoAcordado = _ordenSeleccionada!.abonoRequerido > 0
            ? _ordenSeleccionada!.abonoRequerido
            : (_ordenSeleccionada!.montoACobrar > 0 && _ordenSeleccionada!.montoACobrar < saldo
                ? _ordenSeleccionada!.montoACobrar
                : 0);

        if (abonoAcordado > 0 && _ordenSeleccionada!.esPrimerAbono) {
          _montoDeclarado = abonoAcordado;
        } else if (_ordenSeleccionada!.esPrimerAbono && _ordenSeleccionada!.pisoPrimerAbono > 0) {
          _montoDeclarado = _ordenSeleccionada!.pisoPrimerAbono;
        } else {
          final sugerido = (saldo * 0.5).round();
          _montoDeclarado = sugerido > 0 ? sugerido : saldo;
        }
      }
      _sincronizarMontoConMetodos();
    }
    notifyListeners();
  }

  /// Actualiza directamente el monto declarado (por ejemplo al ingresar un Abono Personalizado).
  void setMontoDeclarado(int nuevoMonto) {
    _montoDeclarado = nuevoMonto;
    _sincronizarMontoConMetodos();
    notifyListeners();
  }

  void _sincronizarMontoConMetodos() {
    if (_modalidadPago == 'UNICO' || _pagosDivididos.length <= 1) {
      final metodoActual = _pagosDivididos.isNotEmpty ? _pagosDivididos.first.metodo : 'Efectivo';
      _pagosDivididos = [
        TransaccionPagoItemModel(metodo: metodoActual, monto: _montoDeclarado),
      ];
    }
  }

  /// Cambia la modalidad de la pasarela ('UNICO' | 'SPLIT').
  void setModalidadPago(String nuevaModalidad) {
    final modNorm = nuevaModalidad.toUpperCase();
    if (_modalidadPago == modNorm) return;
    _modalidadPago = modNorm;

    if (_modalidadPago == 'UNICO') {
      final primerMetodo = _pagosDivididos.isNotEmpty ? _pagosDivididos.first.metodo : 'Efectivo';
      _pagosDivididos = [
        TransaccionPagoItemModel(metodo: primerMetodo, monto: _montoDeclarado),
      ];
    }
    notifyListeners();
  }

  /// Comprueba si un canal de pago se encuentra activo en la pasarela.
  bool esMetodoActivo(String metodo) {
    final mNorm = metodo.toLowerCase().replaceAll('é', 'e');
    return _pagosDivididos.any(
      (p) => p.metodo.toLowerCase().replaceAll('é', 'e') == mNorm,
    );
  }

  /// Alterna o selecciona un método de pago desde el grid de 5 botones.
  void toggleMetodoPago(String metodo) {
    final mNorm = metodo.toLowerCase().replaceAll('é', 'e');

    if (_modalidadPago == 'UNICO') {
      // En modo único, el método seleccionado cubre el 100% de inmediato
      _pagosDivididos = [
        TransaccionPagoItemModel(metodo: metodo, monto: _montoDeclarado),
      ];
      notifyListeners();
      return;
    }

    // En modo dividido (SPLIT)
    final index = _pagosDivididos.indexWhere(
      (p) => p.metodo.toLowerCase().replaceAll('é', 'e') == mNorm,
    );

    if (index >= 0) {
      if (_pagosDivididos.length > 1) {
        _pagosDivididos.removeAt(index);
      }
    } else {
      final restante = diferenciaCuadratura > 0 ? diferenciaCuadratura : 0;
      _pagosDivididos.add(
        TransaccionPagoItemModel(metodo: metodo, monto: restante),
      );
    }
    notifyListeners();
  }

  /// Agrega un nuevo canal de método de pago a la pasarela (Split payment).
  void agregarMetodoPago({String metodo = 'Debito', int monto = 0}) {
    _pagosDivididos.add(
      TransaccionPagoItemModel(metodo: metodo, monto: monto),
    );
    notifyListeners();
  }

  /// Remueve un canal de pago por su índice (mínimo debe haber 1).
  void removerMetodoPago(int index) {
    if (_pagosDivididos.length > 1 &&
        index >= 0 &&
        index < _pagosDivididos.length) {
      _pagosDivididos.removeAt(index);
      notifyListeners();
    }
  }

  /// Actualiza el monto numérico de un canal de pago.
  void actualizarMontoMetodo(int index, int monto) {
    if (index >= 0 && index < _pagosDivididos.length) {
      _pagosDivididos[index] = _pagosDivididos[index].copyWith(monto: monto);
      notifyListeners();
    }
  }

  /// Actualiza el tipo de método de pago (Efectivo, Débito, etc.) de un canal.
  void actualizarTipoMetodo(int index, String metodo) {
    if (index >= 0 && index < _pagosDivididos.length) {
      _pagosDivididos[index] = _pagosDivididos[index].copyWith(metodo: metodo);
      notifyListeners();
    }
  }

  /// Función "Auto-rellenar restante" (CA-04):
  /// Calcula la diferencia matemática restante y la asigna a la casilla activa.
  void autoRellenarRestante(int index) {
    if (index < 0 || index >= _pagosDivididos.length) return;

    int otrosMontos = 0;
    for (int i = 0; i < _pagosDivididos.length; i++) {
      if (i != index) {
        otrosMontos += _pagosDivididos[i].monto;
      }
    }

    final restante = _montoDeclarado - otrosMontos;
    if (restante >= 0) {
      _pagosDivididos[index] = _pagosDivididos[index].copyWith(monto: restante);
      notifyListeners();
    }
  }

  /// Reinicia la configuración de cobro al estado por defecto.
  void reiniciarCobro() {
    if (_ordenSeleccionada != null) {
      _modalidad = 'LIQUIDACION';
      _modalidadPago = 'UNICO';
      _montoDeclarado = _ordenSeleccionada!.montoACobrar;
      _pagosDivididos = [
        TransaccionPagoItemModel(
          metodo: 'Efectivo',
          monto: _ordenSeleccionada!.montoACobrar,
        ),
      ];
      notifyListeners();
    }
  }

  /// Procesa el cobro enviando la petición atómica al Backend (FastAPI).
  Future<RegistrarCobroResponseModel?> procesarCobro() async {
    if (_ordenSeleccionada == null || !esCuadraturaValida) return null;

    _isProcesandoCobro = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final request = RegistrarCobroRequestModel(
        tipoOperacion: _ordenSeleccionada!.esVenta ? 'ORDEN' : 'BACKORDER',
        idDocumento: _ordenSeleccionada!.idReferencia,
        modalidad: _modalidad,
        montoDeclarado: _montoDeclarado,
        pagos: _pagosDivididos,
        skuActivoAtribuido: null,
        forzarAtribucion: false,
      );

      final resultado = await _cajaService.registrarCobro(request);
      _ultimoResultadoCobro = resultado;
      OrdenesSyncNotifier.instance.notificarCambio();

      return resultado;
    } on CustomApiException catch (e) {
      _errorMessage = e.messageUser;
      rethrow;
    } catch (e) {
      _errorMessage = ApiService.limpiarMensajeExcepcion(e);
      rethrow;
    } finally {
      _isProcesandoCobro = false;
      notifyListeners();
    }
  }

  /// Remueve la orden procesada de la lista en memoria y limpia el panel lateral (SPEC-HU-04 / CA-06).
  void removerOrdenProcesada(String idDocumento) {
    _todosLosCobros.removeWhere((c) => c.idReferencia == idDocumento);
    _aplicarFiltrosLocales();
    _ordenSeleccionada = null;
    _montoDeclarado = 0;
    _pagosDivididos = [];
    _modalidad = 'LIQUIDACION';
    notifyListeners();
  }

  /// Cambia el filtro de píldoras ('TODOS', 'VENTA', 'BACKORDER') de forma instantánea sin resetear contadores.
  void setFiltroTipo(String nuevoTipo) {
    final tipoNorm = nuevoTipo.toUpperCase();
    if (_filtroTipo == tipoNorm) return;
    _filtroTipo = tipoNorm;
    _aplicarFiltrosLocales();
    notifyListeners();
  }

  /// Ejecuta búsqueda con debounce de 150 ms sobre la colección en memoria.
  void buscar(String query) {
    _debounceTimer?.cancel();
    _terminoBusqueda = query;

    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      _aplicarFiltrosLocales();
      notifyListeners();
    });
  }

  /// Limpia el campo de búsqueda inmediatamente.
  void limpiarBusqueda() {
    _debounceTimer?.cancel();
    if (_terminoBusqueda.isEmpty) return;
    _terminoBusqueda = '';
    _aplicarFiltrosLocales();
    notifyListeners();
  }
}

