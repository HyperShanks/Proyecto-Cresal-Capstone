import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/historial_caja_model.dart';
import '../../services/caja_service.dart';

enum PeriodoHistorial {
  hoy('HOY', 'Hoy'),
  estaSemana('ESTA_SEMANA', 'Esta Semana'),
  esteMes('ESTE_MES', 'Este Mes'),
  rango('RANGO', 'Rango');

  final String codigo;
  final String label;
  const PeriodoHistorial(this.codigo, this.label);
}

class HistorialCajaState {
  final bool isLoading;
  final String? errorMessage;
  final HistorialCajaResponseModel? data;

  // Filtros Activos
  final PeriodoHistorial periodo;
  final String? fechaDesde;
  final String? fechaHasta;
  final String estadoOrden; // 'TODOS', 'Pagada', 'Despachada', 'Anulada'
  final String metodoPago; // 'TODOS', 'Efectivo', 'Débito', 'Crédito', 'Transferencia', 'Cheque'
  final String busqueda;
  final int? montoMin;
  final int? montoMax;
  final int paginaActual;

  // Auditoría Seleccionada
  final HistorialOrdenItemModel? ordenAuditoria;

  HistorialCajaState({
    this.isLoading = false,
    this.errorMessage,
    this.data,
    this.periodo = PeriodoHistorial.hoy,
    this.fechaDesde,
    this.fechaHasta,
    this.estadoOrden = 'TODOS',
    this.metodoPago = 'TODOS',
    this.busqueda = '',
    this.montoMin,
    this.montoMax,
    this.paginaActual = 1,
    this.ordenAuditoria,
  });

  bool get tieneFiltrosActivos =>
      periodo != PeriodoHistorial.hoy ||
      estadoOrden != 'TODOS' ||
      metodoPago != 'TODOS' ||
      busqueda.isNotEmpty ||
      fechaDesde != null ||
      fechaHasta != null;

  int get cantidadFiltrosActivos {
    int count = 0;
    if (periodo != PeriodoHistorial.hoy || fechaDesde != null || fechaHasta != null) count++;
    if (estadoOrden != 'TODOS') count++;
    if (metodoPago != 'TODOS') count++;
    if (busqueda.trim().isNotEmpty) count++;
    return count;
  }

  HistorialCajaState copyWith({
    bool? isLoading,
    String? errorMessage,
    HistorialCajaResponseModel? data,
    PeriodoHistorial? periodo,
    String? fechaDesde,
    String? fechaHasta,
    String? estadoOrden,
    String? metodoPago,
    String? busqueda,
    int? montoMin,
    int? montoMax,
    int? paginaActual,
    HistorialOrdenItemModel? ordenAuditoria,
    bool clearAuditoria = false,
    bool clearRango = false,
    bool clearErrorMessage = false,
  }) {
    return HistorialCajaState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      data: data ?? this.data,
      periodo: periodo ?? this.periodo,
      fechaDesde: clearRango ? null : (fechaDesde ?? this.fechaDesde),
      fechaHasta: clearRango ? null : (fechaHasta ?? this.fechaHasta),
      estadoOrden: estadoOrden ?? this.estadoOrden,
      metodoPago: metodoPago ?? this.metodoPago,
      busqueda: busqueda ?? this.busqueda,
      montoMin: montoMin ?? this.montoMin,
      montoMax: montoMax ?? this.montoMax,
      paginaActual: paginaActual ?? this.paginaActual,
      ordenAuditoria: clearAuditoria ? null : (ordenAuditoria ?? this.ordenAuditoria),
    );
  }
}

class HistorialCajaProvider extends ChangeNotifier {
  final ICajaService _cajaService;
  final int sucursalId;

  HistorialCajaState _state = HistorialCajaState();
  HistorialCajaState get state => _state;

  Timer? _debounceTimer;
  bool _isDisposed = false;
  int _currentRequestId = 0;

  HistorialCajaProvider({
    ICajaService? cajaService,
    required this.sucursalId,
    bool autoCargar = true,
  }) : _cajaService = cajaService ?? CajaService() {
    if (autoCargar) {
      cargarHistorial();
    }
  }

  Future<void> cargarHistorial({int pagina = 1}) async {
    final requestId = ++_currentRequestId;
    _state = _state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      paginaActual: pagina,
    );
    notifyListeners();

    try {
      final response = await _cajaService.obtenerHistorialCaja(
        sucursalId: sucursalId,
        periodo: _state.periodo.codigo,
        fechaDesde: _state.fechaDesde,
        fechaHasta: _state.fechaHasta,
        estadoOrden: _state.estadoOrden,
        metodoPago: _state.metodoPago,
        busqueda: _state.busqueda.isEmpty ? null : _state.busqueda,
        montoMin: _state.montoMin,
        montoMax: _state.montoMax,
        pagina: pagina,
      );

      // Si otra petición se disparó mientras esta estaba en vuelo, descartar resultado obsoleto
      if (requestId != _currentRequestId || _isDisposed) return;

      _state = _state.copyWith(
        isLoading: false,
        data: response,
      );
    } catch (e) {
      if (requestId != _currentRequestId || _isDisposed) return;
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: 'Error al obtener historial de auditoría: $e',
      );
    } finally {
      if (requestId == _currentRequestId && !_isDisposed) {
        notifyListeners();
      }
    }
  }

  /// Recarga silenciosa en segundo plano manteniendo la página y filtros activos sin mostrar spinner
  Future<void> cargarHistorialSilencioso({int? pagina}) async {
    final requestId = ++_currentRequestId;
    final targetPagina = pagina ?? _state.paginaActual;
    try {
      final response = await _cajaService.obtenerHistorialCaja(
        sucursalId: sucursalId,
        periodo: _state.periodo.codigo,
        fechaDesde: _state.fechaDesde,
        fechaHasta: _state.fechaHasta,
        estadoOrden: _state.estadoOrden,
        metodoPago: _state.metodoPago,
        busqueda: _state.busqueda.isEmpty ? null : _state.busqueda,
        montoMin: _state.montoMin,
        montoMax: _state.montoMax,
        pagina: targetPagina,
      );

      if (requestId != _currentRequestId || _isDisposed) return;

      _state = _state.copyWith(
        isLoading: false,
        data: response,
        paginaActual: targetPagina,
      );
    } catch (_) {
      // Silenciar errores en ciclo en segundo plano
    } finally {
      if (requestId == _currentRequestId && !_isDisposed) {
        notifyListeners();
      }
    }
  }

  void cambiarPeriodo(PeriodoHistorial nuevoPeriodo) {
    if (_state.periodo == nuevoPeriodo && nuevoPeriodo != PeriodoHistorial.rango) return;
    _state = _state.copyWith(
      periodo: nuevoPeriodo,
      clearRango: nuevoPeriodo != PeriodoHistorial.rango,
      paginaActual: 1,
    );
    cargarHistorial(pagina: 1);
  }

  void aplicarRangoFechas(String desde, String hasta) {
    _state = _state.copyWith(
      periodo: PeriodoHistorial.rango,
      fechaDesde: desde,
      fechaHasta: hasta,
      paginaActual: 1,
    );
    cargarHistorial(pagina: 1);
  }

  void cambiarFiltroEstado(String nuevoEstado) {
    if (_state.estadoOrden == nuevoEstado) return;
    _state = _state.copyWith(estadoOrden: nuevoEstado, paginaActual: 1);
    cargarHistorial(pagina: 1);
  }

  void cambiarFiltroMetodo(String nuevoMetodo) {
    if (_state.metodoPago == nuevoMetodo) return;
    _state = _state.copyWith(metodoPago: nuevoMetodo, paginaActual: 1);
    cargarHistorial(pagina: 1);
  }

  void actualizarBusqueda(String texto) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _state = _state.copyWith(busqueda: texto.trim(), paginaActual: 1);
      cargarHistorial(pagina: 1);
    });
  }

  void limpiarBusqueda() {
    _debounceTimer?.cancel();
    _state = _state.copyWith(busqueda: '', paginaActual: 1);
    cargarHistorial(pagina: 1);
  }

  void limpiarFiltros() {
    _debounceTimer?.cancel();
    _state = _state.copyWith(
      periodo: PeriodoHistorial.hoy,
      clearRango: true,
      estadoOrden: 'TODOS',
      metodoPago: 'TODOS',
      busqueda: '',
      paginaActual: 1,
      clearAuditoria: true,
    );
    cargarHistorial(pagina: 1);
  }

  void seleccionarOrdenAuditoria(HistorialOrdenItemModel? orden) {
    _state = _state.copyWith(
      ordenAuditoria: orden,
      clearAuditoria: orden == null,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _debounceTimer?.cancel();
    super.dispose();
  }
}
