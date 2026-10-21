import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/caja/models/historial_caja_model.dart';
import 'package:frontend/features/caja/services/caja_service.dart';
import 'package:frontend/features/caja/presentation/providers/historial_caja_provider.dart';
import 'package:frontend/features/caja/models/cobro_pendiente_model.dart';
import 'package:frontend/features/caja/models/cobro_model.dart';

class MockCajaAuditService implements ICajaService {
  int fetchCount = 0;
  int lastFetchedPagina = 1;

  @override
  Future<List<CobroPendienteModel>> obtenerCobrosPendientes({
    required int sucursalId,
    String? busqueda,
    String? tipoOperacion,
  }) async => [];

  @override
  Future<RegistrarCobroResponseModel> registrarCobro(
    RegistrarCobroRequestModel request,
  ) async => throw UnimplementedError();

  @override
  Future<ValidarActivoBackorderResponseModel> validarActivoBackorder(
    ValidarActivoBackorderRequestModel request,
  ) async => ValidarActivoBackorderResponseModel(coincide: true, discrepancias: [], mensaje: 'OK');

  @override
  Future<HistorialCajaResponseModel> obtenerHistorialCaja({
    required int sucursalId,
    String periodo = 'HOY',
    String? fechaDesde,
    String? fechaHasta,
    String estadoOrden = 'TODOS',
    String metodoPago = 'TODOS',
    String? busqueda,
    int? montoMin,
    int? montoMax,
    String? idCajera,
    String? idVendedor,
    int pagina = 1,
    int limite = 20,
  }) async {
    fetchCount++;
    lastFetchedPagina = pagina;
    return HistorialCajaResponseModel(
      totalRegistros: 50,
      paginaActual: pagina,
      limitePorPagina: limite,
      totalPaginas: 3,
      totalMontoConsolidado: 50000,
      resumenCuadre: ResumenCuadreCajaModel.empty(),
      items: [
        HistorialOrdenItemModel(
          idOrden: 'ORD-TEST-001',
          folio: 'B-001',
          tipoOperacion: 'VENTA_DIRECTA',
          emiteQr: true,
          fechaIso: '2026-09-22',
          hora: '12:00',
          fechaHoraFormateada: '22/09/2026 12:00',
          clienteNombre: 'Juan Perez',
          vendedorNombre: 'Vendedor 1',
          cajeraNombre: 'Cajera 1',
          estadoOrden: 'Pagada',
          modalidadPago: 'Directo',
          metodosResumen: 'Efectivo',
          totalVenta: 50000,
          abonoPrevio: 0,
          totalLiquidado: 50000,
          desglosePagos: [],
          articulos: [],
          historialMovimientos: [],
        ),
      ],
    );
  }
}

void main() {
  group('SPEC-HU-TAREA-21: HistorialCajaProvider - Sincronización Silenciosa', () {
    test('cargarHistorialSilencioso actualiza datos y conserva la página activa sin isLoading', () async {
      final mock = MockCajaAuditService();
      final provider = HistorialCajaProvider(
        cajaService: mock,
        sucursalId: 1,
        autoCargar: false,
      );

      // Estado inicial
      expect(provider.state.isLoading, isFalse);
      expect(provider.state.data, isNull);

      // Cargar página 2 agresivamente
      await provider.cargarHistorial(pagina: 2);
      expect(mock.lastFetchedPagina, 2);
      expect(provider.state.paginaActual, 2);
      expect(provider.state.data?.items.length, 1);
      expect(provider.state.isLoading, isFalse);

      // Ejecutar recarga silenciosa (ej. didPopNext al cerrar modal de auditoría)
      bool capturedLoading = false;
      provider.addListener(() {
        if (provider.state.isLoading) capturedLoading = true;
      });

      await provider.cargarHistorialSilencioso();

      // Debe haber conservado la página 2
      expect(mock.lastFetchedPagina, 2);
      expect(provider.state.paginaActual, 2);
      // Nunca debió mostrar isLoading = true
      expect(capturedLoading, isFalse);
      expect(provider.state.isLoading, isFalse);
    });
  });
}
