import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/features/ventas/services/ordenes_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({'access_token': 'mock-jwt-token'});

  group('OrdenesService Unit Tests', () {
    final samplePayload = {
      'cliente': {
        'rut_cliente': '18.765.432-1',
        'nombres': 'Juan',
        'apellidos': 'Pérez',
        'telefono': '+56912345678',
        'comuna': 'Viña del Mar',
        'consentimiento_legal': true,
      },
      'requiere_despacho': false,
      'consentimiento_legal': true,
      'items': [
        {
          'id_activo': '3fa85f64-5717-4562-b3fc-2c963f66afa6',
          'notas_preparacion': 'Entregar con soporte',
          'cantidad': 1,
          'precio_unitario': 520000,
          'precio_final': 520000,
        }
      ],
    };

    test('crearOrden exitoso (201 Created) retorna OrdenResponseModel parseado', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/api/v1/ordenes'));
        expect(request.method, 'POST');
        expect(request.headers['Content-Type'], 'application/json');

        final responseJson = {
          'id_orden': 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
          'estado_orden': 'Reservada',
          'total_venta': 520000,
          'monto_pendiente': 520000,
          'qr_transaccional_salida': 'ORD-A1B2C3D4',
          'mensaje': 'Orden generada exitosamente',
          'fecha_creacion': '2026-08-14T00:00:00',
          'total_items': 1,
        };

        return http.Response(
          jsonEncode(responseJson),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final result = await OrdenesService.crearOrden(samplePayload, client: mockClient);

      expect(result.idOrden, 'a1b2c3d4-e5f6-7890-abcd-ef1234567890');
      expect(result.estadoOrden, 'Reservada');
      expect(result.totalVenta, 520000);
      expect(result.totalVentaFormateado, '\$520.000');
      expect(result.montoPendiente, 520000);
      expect(result.qrTransaccionalSalida, 'ORD-A1B2C3D4');
      expect(result.totalItems, 1);
    });

    test('crearOrden con conflicto de stock (409 Conflict) lanza excepción con mensaje detallado', () async {
      final mockClient = MockClient((request) async {
        final errorJson = {
          'detail': "El repuesto 'MOT-TOY-YAR-001' no está disponible para venta. Estado actual: Reservado."
        };
        return http.Response(
          jsonEncode(errorJson),
          409,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      expect(
        () async => await OrdenesService.crearOrden(samplePayload, client: mockClient),
        throwsA(
          predicate((e) =>
              e is Exception &&
              e.toString().contains('no está disponible para venta')),
        ),
      );
    });

    test('crearOrden con datos inválidos (400 Bad Request) lanza excepción descriptiva', () async {
      final mockClient = MockClient((request) async {
        final errorJson = {
          'detail': 'El consentimiento expreso para tratamiento de datos (Ley N° 21.719) es obligatorio.'
        };
        return http.Response(
          jsonEncode(errorJson),
          400,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      expect(
        () async => await OrdenesService.crearOrden(samplePayload, client: mockClient),
        throwsA(
          predicate((e) =>
              e is Exception &&
              e.toString().contains('Ley N° 21.719')),
        ),
      );
    });

    test('crearOrden con sesión expirada (401 Unauthorized) lanza excepción clara', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Token inválido o expirado'}),
          401,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      expect(
        () async => await OrdenesService.crearOrden(samplePayload, client: mockClient),
        throwsA(
          predicate((e) =>
              e is Exception &&
              e.toString().contains('Sesión expirada')),
        ),
      );
    });

    test('buscarClientePorRut retorna mapa si existe (200)', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/api/v1/clientes/18.765.432-1'));
        expect(request.method, 'GET');

        final responseJson = {
          'id_cliente': '3fa85f64-5717-4562-b3fc-2c963f66afa6',
          'rut_cliente': '18.765.432-1',
          'nombres': 'Juan',
          'apellidos': 'Pérez',
          'telefono': '+56912345678',
          'comuna': 'Viña del Mar',
        };

        return http.Response(
          jsonEncode(responseJson),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final cliente = await OrdenesService.buscarClientePorRut('18.765.432-1', client: mockClient);

      expect(cliente, isNotNull);
      expect(cliente!['nombres'], 'Juan');
      expect(cliente['apellidos'], 'Pérez');
      expect(cliente['comuna'], 'Viña del Mar');
    });

    test('buscarClientePorRut retorna null si no existe (404)', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Cliente no encontrado'}),
          404,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final cliente = await OrdenesService.buscarClientePorRut('99.999.999-9', client: mockClient);

      expect(cliente, isNull);
    });
  });
}
