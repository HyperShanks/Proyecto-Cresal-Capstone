import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/caja/models/cobro_pendiente_model.dart';
import 'package:frontend/features/caja/models/cobro_model.dart';
import 'package:frontend/features/caja/models/historial_caja_model.dart';
import 'package:frontend/features/caja/services/caja_service.dart';
import 'package:frontend/features/caja/presentation/providers/caja_provider.dart';

class MockCajaService implements ICajaService {
  List<CobroPendienteModel> dummyItems = [];
  bool shouldFail = false;

  @override
  Future<List<CobroPendienteModel>> obtenerCobrosPendientes({
    required int sucursalId,
    String? busqueda,
    String? tipoOperacion,
  }) async {
    if (shouldFail) {
      throw Exception('Fallo de conexión simulado');
    }
    return List<CobroPendienteModel>.from(dummyItems);
  }

  @override
  Future<RegistrarCobroResponseModel> registrarCobro(
    RegistrarCobroRequestModel request,
  ) async {
    throw UnimplementedError();
  }

  @override
  Future<ValidarActivoBackorderResponseModel> validarActivoBackorder(
    ValidarActivoBackorderRequestModel request,
  ) async {
    return ValidarActivoBackorderResponseModel(
      coincide: true,
      discrepancias: [],
      mensaje: 'OK',
    );
  }

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
    return HistorialCajaResponseModel.empty();
  }
}

CobroPendienteModel _crearCobroMock({
  required String id,
  required String folio,
  int monto = 50000,
}) {
  return CobroPendienteModel(
    idReferencia: id,
    folioDocumento: folio,
    tipoOperacion: 'VENTA',
    estadoDocumento: 'Reservada',
    fechaEmision: DateTime.now(),
    fechaEmisionFormateada: '21/08/2026',
    horaEmisionFormateada: '11:38',
    clienteNombre: 'Cliente Test',
    clienteRut: '12345678-9',
    vendedorNombre: 'Vendedor Test',
    totalOperacion: monto,
    abonoPrevio: 0,
    saldoPendiente: monto,
    montoACobrar: monto,
    articulos: [],
  );
}

void main() {
  group('CajaProvider Silent Polling Tests (SPEC-HU-TAREA-21)', () {
    late MockCajaService mockService;
    late CajaProvider provider;

    setUp(() {
      mockService = MockCajaService();
      provider = CajaProvider(cajaService: mockService);
    });

    test('cargarCobrosPendientesSilencioso no activa loaders ni resetea pantalla', () async {
      mockService.dummyItems = [
        _crearCobroMock(id: '1', folio: 'FOL-001'),
      ];

      await provider.cargarCobrosPendientes();
      expect(provider.cobros.length, 1);
      expect(provider.isLoading, isFalse);

      // Ahora agregamos una segunda orden en el mock y corremos el polling silencioso
      mockService.dummyItems.add(_crearCobroMock(id: '2', folio: 'FOL-002'));

      await provider.cargarCobrosPendientesSilencioso();

      // Debe haberse actualizado a 2 ítems sin poner isLoading en true
      expect(provider.cobros.length, 2);
      expect(provider.isLoading, isFalse);
      expect(provider.isRefreshing, isFalse);
    });

    test('cargarCobrosPendientesSilencioso respeta orden en proceso de cobro activo', () async {
      final orden = _crearCobroMock(id: '1', folio: 'FOL-001');
      mockService.dummyItems = [orden];
      await provider.cargarCobrosPendientes();

      provider.seleccionarOrden(orden);
      provider.agregarMetodoPago(metodo: 'Efectivo', monto: 15000);

      // La cajera ingresó un segundo método de pago (SPLIT):
      expect(provider.pagosDivididos.length, 2);

      // El polling intenta correr:
      mockService.dummyItems.add(_crearCobroMock(id: '2', folio: 'FOL-002'));
      await provider.cargarCobrosPendientesSilencioso();

      // La selección y los pagos divididos deben permanecer intactos
      expect(provider.ordenSeleccionada?.idReferencia, '1');
      expect(provider.pagosDivididos.length, 2);
      expect(provider.pagosDivididos.last.monto, 15000);
    });

    test('cargarCobrosPendientesSilencioso no notifica si los datos no cambiaron', () async {
      mockService.dummyItems = [
        _crearCobroMock(id: '1', folio: 'FOL-001'),
      ];
      await provider.cargarCobrosPendientes();

      int notifyCount = 0;
      provider.addListener(() {
        notifyCount++;
      });

      // Mismos datos, cero cambios
      await provider.cargarCobrosPendientesSilencioso();
      expect(notifyCount, 0, reason: 'No debió notificar porque los IDs y saldos son idénticos');
    });

    test('cargarCobrosPendientesSilencioso ignora fallas de red sin sobreescribir errorMessage', () async {
      mockService.dummyItems = [
        _crearCobroMock(id: '1', folio: 'FOL-001'),
      ];
      await provider.cargarCobrosPendientes();

      // Simular error de red en polling
      mockService.shouldFail = true;
      await provider.cargarCobrosPendientesSilencioso();

      // No debe poner errorMessage
      expect(provider.errorMessage, isNull);
      expect(provider.cobros.length, 1);
    });
  });
}
