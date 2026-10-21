import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/routes/app_routes.dart';
import 'package:frontend/features/auth/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockStorage = {};

  setUp(() {
    mockStorage.clear();
    FlutterSecureStorage.setMockInitialValues(mockStorage);
  });

  group('AppRoutes RBAC Route Guards - All Roles', () {
    test('Bodeguero (id_rol == 1) solo puede acceder a rutas operativas de bodega y soporte', () {
      // Rutas permitidas
      expect(AppRoutes.isRouteAllowedForRole(1, '/home'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(1, '/recepcion'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(1, '/paletizado'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(1, '/etiqueta-preview'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(1, '/buscador'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(1, '/alertas'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(1, '/tickets'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(1, '/login'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(1, '/enrolamiento'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(1, '/'), isTrue);

      // Rutas denegadas (ventas y caja)
      expect(AppRoutes.isRouteAllowedForRole(1, '/ventas_main'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(1, '/catalogo'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(1, '/checkout_crm'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(1, '/bandeja_precios'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(1, '/caja'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(1, '/entregas-envios'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(1, '/carrito'), isFalse);
    });

    test('Vendedor (id_rol == 2 y 7) solo puede acceder a rutas de ventas y soporte', () {
      for (final rolId in [2, 7]) {
        // Rutas permitidas
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/ventas_main'), isTrue);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/catalogo'), isTrue);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/checkout_crm'), isTrue);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/bandeja_precios'), isTrue);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/entregas-envios'), isTrue);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/carrito'), isTrue);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/tickets'), isTrue);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/login'), isTrue);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/enrolamiento'), isTrue);

        // Rutas denegadas (bodega y caja)
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/home'), isFalse);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/recepcion'), isFalse);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/paletizado'), isFalse);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/etiqueta-preview'), isFalse);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/buscador'), isFalse);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/alertas'), isFalse);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/caja'), isFalse);
      }
    });

    test('Jefe de Ventas (id_rol == 6) tiene acceso al módulo de ventas y tasación', () {
      expect(AppRoutes.isRouteAllowedForRole(6, '/ventas_main'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(6, '/catalogo'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(6, '/bandeja_precios'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(6, '/checkout_crm'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(6, '/entregas-envios'), isTrue);

      expect(AppRoutes.isRouteAllowedForRole(6, '/home'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(6, '/recepcion'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(6, '/caja'), isFalse);
    });

    test('Caja (id_rol == 3) solo puede acceder a módulo de caja y soporte', () {
      expect(AppRoutes.isRouteAllowedForRole(3, '/caja'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(3, '/tickets'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(3, '/login'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(3, '/enrolamiento'), isTrue);

      expect(AppRoutes.isRouteAllowedForRole(3, '/home'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(3, '/ventas_main'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(3, '/catalogo'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(3, '/recepcion'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(3, '/paletizado'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(3, '/buscador'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(3, '/bandeja_precios'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(3, '/alertas'), isFalse);
    });

    test('Administrador (5) y Gerente (4) tienen acceso a todas las rutas', () {
      for (final rolId in [4, 5]) {
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/home'), isTrue);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/ventas_main'), isTrue);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/caja'), isTrue);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/recepcion'), isTrue);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/paletizado'), isTrue);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/catalogo'), isTrue);
        expect(AppRoutes.isRouteAllowedForRole(rolId, '/bandeja_precios'), isTrue);
      }
    });

    test('Usuario sin rol autenticado (null) solo puede acceder a rutas públicas', () {
      expect(AppRoutes.isRouteAllowedForRole(null, '/login'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(null, '/enrolamiento'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(null, '/tickets'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(null, '/'), isTrue);

      expect(AppRoutes.isRouteAllowedForRole(null, '/home'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(null, '/caja'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(null, '/ventas_main'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(null, '/recepcion'), isFalse);
    });
  });

  group('AppRoutes getHomeRouteForRole Tests', () {
    test('getHomeRouteForRole resuelve el panel correcto según rol', () {
      expect(AppRoutes.getHomeRouteForRole(3), '/caja');
      expect(AppRoutes.getHomeRouteForRole(2), '/ventas_main');
      expect(AppRoutes.getHomeRouteForRole(6), '/ventas_main');
      expect(AppRoutes.getHomeRouteForRole(7), '/ventas_main');
      expect(AppRoutes.getHomeRouteForRole(1), '/home');
      expect(AppRoutes.getHomeRouteForRole(4), '/gerencia');
      expect(AppRoutes.getHomeRouteForRole(5), '/home');
      expect(AppRoutes.getHomeRouteForRole(null), '/home');
    });
  });

  group('AuthService Token Cleansing vs Desenrolar Tests', () {
    test('clearToken elimina sesión pero mantiene enrolamiento', () async {
      await const FlutterSecureStorage().write(key: 'access_token', value: 'token-123');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Bodeguero');
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '1');
      await const FlutterSecureStorage().write(key: 'enrolled_user_id', value: 'uuid-operario-1');
      await const FlutterSecureStorage().write(key: 'enrolled_user_email', value: 'operario1@cresal.cl');
      await const FlutterSecureStorage().write(key: 'enrolled_user_name', value: 'Operario Uno');

      await AuthService.clearToken();

      expect(await AuthService.getToken(), isNull);
      expect(await AuthService.getRol(), isNull);
      expect(await AuthService.getIdRol(), isNull);
      expect(await AuthService.getEnrolledUserId(), 'uuid-operario-1');
      expect(await AuthService.getEnrolledUserEmail(), 'operario1@cresal.cl');
      expect(await AuthService.getEnrolledUserName(), 'Operario Uno');
      expect(await AuthService.isTerminalEnrolled(), isTrue);
    });

    test('desenrolarTerminal elimina sesión Y datos de enrolamiento', () async {
      await const FlutterSecureStorage().write(key: 'access_token', value: 'token-123');
      await const FlutterSecureStorage().write(key: 'enrolled_user_id', value: 'uuid-operario-1');
      await const FlutterSecureStorage().write(key: 'enrolled_user_email', value: 'operario1@cresal.cl');
      await const FlutterSecureStorage().write(key: 'enrolled_user_name', value: 'Operario Uno');

      await AuthService.desenrolarTerminal();

      expect(await AuthService.getToken(), isNull);
      expect(await AuthService.getEnrolledUserId(), isNull);
      expect(await AuthService.getEnrolledUserEmail(), isNull);
      expect(await AuthService.getEnrolledUserName(), isNull);
      expect(await AuthService.isTerminalEnrolled(), isFalse);
    });
  });
}
