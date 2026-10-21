// test/login_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/features/auth/services/auth_service.dart';
import 'package:frontend/features/auth/models/auth_user_model.dart';
import 'package:frontend/features/auth/presentation/screens/splash_screen.dart';
import 'package:frontend/features/home/presentation/screens/home_screen.dart';
import 'package:frontend/routes/app_routes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockStorage = {};

  setUp(() {
    mockStorage.clear();
    FlutterSecureStorage.setMockInitialValues(mockStorage);
  });

  group('AuthService - Role Resolution & Helper Tests', () {
    test('esModuloVentas retorna true para id_rol 2 (Vendedor), 6 (Jefe de Ventas) y 7 (VendedorOnline)', () async {
      // Test id_rol 2
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '2');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Vendedor');
      expect(await AuthService.esModuloVentas(), isTrue);

      // Test id_rol 6
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '6');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Jefe de Ventas');
      expect(await AuthService.esModuloVentas(), isTrue);

      // Test id_rol 7
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '7');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Vendedor Online');
      expect(await AuthService.esModuloVentas(), isTrue);
    });

    test('esModuloVentas retorna false para id_rol 1 (Bodeguero) y 3 (Caja)', () async {
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '1');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Bodeguero');
      expect(await AuthService.esModuloVentas(), isFalse);

      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '3');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Caja');
      expect(await AuthService.esModuloVentas(), isFalse);
    });

    test('esVendedorOnline retorna true solo para id_rol 7', () async {
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '7');
      expect(await AuthService.esVendedorOnline(), isTrue);

      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '2');
      expect(await AuthService.esVendedorOnline(), isFalse);
    });

    test('esGerente retorna true solo para id_rol 4 o rol Gerente', () async {
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '4');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Gerente');
      expect(await AuthService.esGerente(), isTrue);

      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '1');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Bodeguero');
      expect(await AuthService.esGerente(), isFalse);
    });

    test('esAuditor retorna true solo para id_rol 8 o rol Auditor', () async {
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '8');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Auditor');
      expect(await AuthService.esAuditor(), isTrue);

      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '4');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Gerente');
      expect(await AuthService.esAuditor(), isFalse);
    });

    test('esAuditorSucursal distingue entre Auditor Casa Matriz (sucursal 1) y Auditor Satélite (sucursal 2)', () async {
      // Auditor Limache (sucursal 2) -> true
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '8');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Auditor');
      await const FlutterSecureStorage().write(key: 'user_sucursal_id', value: '2');
      expect(await AuthService.esAuditorSucursal(), isTrue);

      // Auditor Ricardo Crovetto / Casa Matriz (sucursal 1) -> false
      await const FlutterSecureStorage().write(key: 'user_sucursal_id', value: '1');
      expect(await AuthService.esAuditorSucursal(), isFalse);

      // Gerente general en sucursal 2 -> false (no es auditor)
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '4');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Gerente');
      expect(await AuthService.esAuditorSucursal(), isFalse);
    });

    test('esAuditorSucursalSync resuelve instantáneamente en RAM sin latencia de disco', () {
      AuthService.setMockUserCache(null);
      expect(AuthService.esAuditorSucursalSync, isFalse);

      AuthService.setMockUserCache(const AuthUserModel(
        idUsuario: 'usr-1',
        rutUsuario: '11.111.111-1',
        nombres: 'Auditor',
        apellidos: 'Limache',
        email: 'auditor.limache@cresal.cl',
        idRol: 8,
        nombreRol: 'Auditor',
        idSucursal: 2,
      ));
      expect(AuthService.esAuditorSucursalSync, isTrue);

      AuthService.setMockUserCache(const AuthUserModel(
        idUsuario: 'usr-2',
        rutUsuario: '22.222.222-2',
        nombres: 'Ricardo',
        apellidos: 'Crovetto',
        email: 'gerenteauditor@cresal.cl',
        idRol: 8,
        nombreRol: 'Auditor',
        idSucursal: 1,
      ));
      expect(AuthService.esAuditorSucursalSync, isFalse);

      AuthService.setMockUserCache(null);
    });

    test('AppRoutes.getHomeRouteForRole resuelve rutas según SSOT', () {
      expect(AppRoutes.getHomeRouteForRole(4), equals(AppRoutes.gerencia));
      expect(AppRoutes.getHomeRouteForRole(8), equals(AppRoutes.gerencia));
      expect(AppRoutes.getHomeRouteForRole(3), equals(AppRoutes.caja));
      expect(AppRoutes.getHomeRouteForRole(2), equals(AppRoutes.ventasMain));
      expect(AppRoutes.getHomeRouteForRole(6), equals(AppRoutes.ventasMain));
      expect(AppRoutes.getHomeRouteForRole(7), equals(AppRoutes.ventasMain));
      expect(AppRoutes.getHomeRouteForRole(1), equals(AppRoutes.home));
      expect(AppRoutes.getHomeRouteForRole(5), equals(AppRoutes.home)); // Admin técnico permanece en home
      expect(AppRoutes.getHomeRouteForRole(null), equals(AppRoutes.home));
    });

    test('AppRoutes.isRouteAllowedForRole restringe al Auditor (8) exclusivamente a gerencia', () {
      expect(AppRoutes.isRouteAllowedForRole(8, AppRoutes.gerencia), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(8, AppRoutes.caja), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(8, AppRoutes.ventasMain), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(8, AppRoutes.paletizado), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(8, AppRoutes.recepcion), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(8, AppRoutes.login), isTrue); // Ruta pública siempre permitida
    });
  });

  group('SplashScreen - Navigation Routing Tests', () {
    testWidgets('Sin enrolamiento ni sesión redirige a /enrolamiento', (tester) async {
      await const FlutterSecureStorage().deleteAll();

      await tester.pumpWidget(
        MaterialApp(
          home: const SplashScreen(),
          routes: {
            '/enrolamiento': (context) => const Scaffold(body: Text('ENROLAMIENTO_SCREEN')),
            '/login': (context) => const Scaffold(body: Text('LOGIN_SCREEN')),
            '/home': (context) => const Scaffold(body: Text('HOME_SCREEN')),
            '/ventas_main': (context) => const Scaffold(body: Text('VENTAS_MAIN_SCREEN')),
          },
        ),
      );

      // Avanzar tiempo del splash
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      expect(find.text('ENROLAMIENTO_SCREEN'), findsOneWidget);
    });

    testWidgets('Terminal enrolado sin sesión activa redirige a /login (PIN)', (tester) async {
      await const FlutterSecureStorage().deleteAll();
      await const FlutterSecureStorage().write(key: 'enrolled_user_id', value: 'user-uuid-123');
      await const FlutterSecureStorage().write(key: 'enrolled_user_email', value: 'operario@cresal.cl');

      await tester.pumpWidget(
        MaterialApp(
          home: const SplashScreen(),
          routes: {
            '/enrolamiento': (context) => const Scaffold(body: Text('ENROLAMIENTO_SCREEN')),
            '/login': (context) => const Scaffold(body: Text('LOGIN_SCREEN')),
            '/home': (context) => const Scaffold(body: Text('HOME_SCREEN')),
            '/ventas_main': (context) => const Scaffold(body: Text('VENTAS_MAIN_SCREEN')),
          },
        ),
      );

      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      expect(find.text('LOGIN_SCREEN'), findsOneWidget);
    });

    testWidgets('VendedorOnline (id_rol == 7) redirige a /ventas_main', (tester) async {
      await const FlutterSecureStorage().write(key: 'access_token', value: 'mock-token-7');
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '7');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Vendedor Online');

      await tester.pumpWidget(
        MaterialApp(
          home: const SplashScreen(),
          routes: {
            '/login': (context) => const Scaffold(body: Text('LOGIN_SCREEN')),
            '/home': (context) => const Scaffold(body: Text('HOME_SCREEN')),
            '/ventas_main': (context) => const Scaffold(body: Text('VENTAS_MAIN_SCREEN')),
          },
        ),
      );

      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      expect(find.text('VENTAS_MAIN_SCREEN'), findsOneWidget);
    });

    testWidgets('Vendedor regular (id_rol == 2) redirige a /ventas_main', (tester) async {
      await const FlutterSecureStorage().write(key: 'access_token', value: 'mock-token-2');
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '2');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Vendedor');

      await tester.pumpWidget(
        MaterialApp(
          home: const SplashScreen(),
          routes: {
            '/login': (context) => const Scaffold(body: Text('LOGIN_SCREEN')),
            '/home': (context) => const Scaffold(body: Text('HOME_SCREEN')),
            '/ventas_main': (context) => const Scaffold(body: Text('VENTAS_MAIN_SCREEN')),
          },
        ),
      );

      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      expect(find.text('VENTAS_MAIN_SCREEN'), findsOneWidget);
    });

    testWidgets('Bodeguero (id_rol == 1) redirige a /home', (tester) async {
      await const FlutterSecureStorage().write(key: 'access_token', value: 'mock-token-1');
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '1');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Bodeguero');

      await tester.pumpWidget(
        MaterialApp(
          home: const SplashScreen(),
          routes: {
            '/login': (context) => const Scaffold(body: Text('LOGIN_SCREEN')),
            '/home': (context) => const Scaffold(body: Text('HOME_SCREEN')),
            '/ventas_main': (context) => const Scaffold(body: Text('VENTAS_MAIN_SCREEN')),
          },
        ),
      );

      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      expect(find.text('HOME_SCREEN'), findsOneWidget);
    });
  });

  group('HomeScreen - Guard Routing for Sales Roles', () {
    testWidgets('Usuario de ventas (id_rol == 7) es interceptado y redirigido a /ventas_main', (tester) async {
      await const FlutterSecureStorage().write(key: 'access_token', value: 'mock-token-7');
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '7');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Vendedor Online');

      await tester.pumpWidget(
        MaterialApp(
          home: const HomeScreen(),
          routes: {
            '/login': (context) => const Scaffold(body: Text('LOGIN_SCREEN')),
            '/ventas_main': (context) => const Scaffold(body: Text('VENTAS_MAIN_SCREEN')),
          },
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('VENTAS_MAIN_SCREEN'), findsOneWidget);
    });

    testWidgets('Gerente (id_rol == 4) en HomeScreen es interceptado y redirigido a /gerencia', (tester) async {
      await const FlutterSecureStorage().write(key: 'access_token', value: 'mock-token-4');
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '4');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Gerente');

      await tester.pumpWidget(
        MaterialApp(
          home: const HomeScreen(),
          routes: {
            '/login': (context) => const Scaffold(body: Text('LOGIN_SCREEN')),
            '/gerencia': (context) => const Scaffold(body: Text('GERENCIA_SCREEN')),
          },
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('GERENCIA_SCREEN'), findsOneWidget);
    });

    testWidgets('Gerente (id_rol == 4) en SplashScreen redirige directamente a /gerencia', (tester) async {
      await const FlutterSecureStorage().write(key: 'access_token', value: 'mock-token-4');
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '4');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Gerente');

      await tester.pumpWidget(
        MaterialApp(
          home: const SplashScreen(),
          routes: {
            '/login': (context) => const Scaffold(body: Text('LOGIN_SCREEN')),
            '/gerencia': (context) => const Scaffold(body: Text('GERENCIA_SCREEN')),
          },
        ),
      );

      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      expect(find.text('GERENCIA_SCREEN'), findsOneWidget);
    });

    testWidgets('Administrador (id_rol == 5) en SplashScreen aterriza en /home', (tester) async {
      await const FlutterSecureStorage().write(key: 'access_token', value: 'mock-token-5');
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '5');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Administrador');

      await tester.pumpWidget(
        MaterialApp(
          home: const SplashScreen(),
          routes: {
            '/login': (context) => const Scaffold(body: Text('LOGIN_SCREEN')),
            '/home': (context) => const Scaffold(body: Text('HOME_SCREEN')),
          },
        ),
      );

      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      expect(find.text('HOME_SCREEN'), findsOneWidget);
    });
  });
}
