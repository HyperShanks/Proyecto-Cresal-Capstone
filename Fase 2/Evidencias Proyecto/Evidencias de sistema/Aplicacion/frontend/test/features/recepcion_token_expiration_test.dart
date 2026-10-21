// frontend/test/features/recepcion_token_expiration_test.dart
// Tests automatizados para verificar que la aplicación de Recepción de Vehículos (Gloria)
// maneje la expiración de sesión (HTTP 401) cerrando sesión automáticamente hacia la pantalla de PIN/Login.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:frontend/core/services/api_service.dart';
import 'package:frontend/features/auth/services/auth_service.dart';
import 'package:frontend/features/recepcion/services/recepcion_service.dart';
import 'package:frontend/features/recepcion/services/vehiculo_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecepcionService recepcionService;
  late VehiculoService vehiculoService;
  bool unauthorizedTriggered = false;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'test-gloria-token',
      'user_rol': 'Recepcion Patio',
      'user_id_rol': '9',
      'user_nombre_completo': 'Gloria Recepción',
      'user_email': 'gloria@cresal.cl',
    });

    unauthorizedTriggered = false;
    ApiService.onUnauthorized = () async {
      unauthorizedTriggered = true;
      await AuthService.manejarSesionExpirada();
    };

    recepcionService = RecepcionService();
    vehiculoService = VehiculoService();
  });

  tearDown(() {
    ApiService.onUnauthorized = null;
    ApiService.resetClient();
  });

  group('Recepción de Vehículos - Cierre de Sesión Automático por Token Expirado (401)', () {
    test('RecepcionService.obtenerRecientes ante HTTP 401 dispara cierre de sesión automático', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Token inválido o expirado'}),
          401,
        );
      });
      ApiService.resetClient(client: mockClient);

      expect(await AuthService.getToken(), isNotNull);

      final resultado = await recepcionService.obtenerRecientes();
      expect(resultado, isEmpty);
      expect(unauthorizedTriggered, isTrue);
      // El token debe haber sido eliminado del almacenamiento local
      expect(await AuthService.getToken(), isNull);
    });

    test('RecepcionService.registrarVehiculo ante HTTP 401 dispara cierre de sesión automático', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Token inválido o expirado'}),
          401,
        );
      });
      ApiService.resetClient(client: mockClient);

      expect(await AuthService.getToken(), isNotNull);

      final resultado = await recepcionService.registrarVehiculo({
        'patente': 'AB123CD',
        'marca': 'TOYOTA',
        'modelo': 'YARIS',
      });

      expect(resultado['exito'], isFalse);
      expect(unauthorizedTriggered, isTrue);
      expect(await AuthService.getToken(), isNull);
    });

    test('RecepcionService.obtenerSiguienteIngreso ante HTTP 401 dispara cierre de sesión automático', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Token inválido o expirado'}),
          401,
        );
      });
      ApiService.resetClient(client: mockClient);

      expect(await AuthService.getToken(), isNotNull);

      final folio = await recepcionService.obtenerSiguienteIngreso();
      expect(folio, equals('1'));
      expect(unauthorizedTriggered, isTrue);
      expect(await AuthService.getToken(), isNull);
    });

    test('RecepcionService.exportarMatriz ante HTTP 401 dispara cierre de sesión automático', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Token inválido o expirado'}),
          401,
        );
      });
      ApiService.resetClient(client: mockClient);

      expect(await AuthService.getToken(), isNotNull);

      final resultado = await recepcionService.exportarMatriz();
      expect(resultado['exito'], isFalse);
      expect(unauthorizedTriggered, isTrue);
      expect(await AuthService.getToken(), isNull);
    });

    test('VehiculoService.guardarIngresoManual ante HTTP 401 dispara cierre de sesión automático', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Token inválido o expirado'}),
          401,
        );
      });
      ApiService.resetClient(client: mockClient);

      expect(await AuthService.getToken(), isNotNull);

      final resultado = await vehiculoService.guardarIngresoManual({
        'patente': 'CD345EF',
        'marca': 'NISSAN',
        'modelo': 'VERSA',
      });

      expect(resultado['exito'], isFalse);
      expect(unauthorizedTriggered, isTrue);
      expect(await AuthService.getToken(), isNull);
    });

    test('VehiculoService.obtenerSiguienteIngreso ante HTTP 401 dispara cierre de sesión automático', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Token inválido o expirado'}),
          401,
        );
      });
      ApiService.resetClient(client: mockClient);

      expect(await AuthService.getToken(), isNotNull);

      final resultado = await vehiculoService.obtenerSiguienteIngreso();
      expect(resultado, equals('ERROR'));
      expect(unauthorizedTriggered, isTrue);
      expect(await AuthService.getToken(), isNull);
    });
  });
}
