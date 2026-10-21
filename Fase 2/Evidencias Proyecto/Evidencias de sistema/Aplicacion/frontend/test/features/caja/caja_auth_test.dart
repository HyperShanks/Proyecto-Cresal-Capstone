import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/features/auth/services/auth_service.dart';
import 'package:frontend/features/auth/controllers/login_controller.dart';
import 'package:frontend/features/auth/models/auth_user_model.dart';
import 'package:frontend/features/auth/presentation/screens/splash_screen.dart';
import 'package:frontend/features/home/presentation/screens/home_screen.dart';
import 'package:frontend/features/caja/presentation/screens/caja_main_screen.dart';
import 'package:frontend/features/caja/presentation/widgets/caja_drawer.dart';
import 'package:frontend/core/widgets/cresal_logo.dart';
import 'package:frontend/routes/app_routes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockStorage = {};

  setUp(() {
    mockStorage.clear();
    FlutterSecureStorage.setMockInitialValues(mockStorage);
  });

  group('SPEC-HU-01: AuthUserModel & AuthService Role Helpers', () {
    test('AuthUserModel serializa y deserializa correctamente', () {
      final user = AuthUserModel(
        idUsuario: 'user-uuid-123',
        rutUsuario: '12.345.678-9',
        nombres: 'María Jesús',
        apellidos: 'López Vega',
        email: 'maria.caja@cresal.cl',
        idRol: 3,
        nombreRol: 'Caja',
        idSucursal: 1,
      );

      final json = user.toJson();
      expect(json['id_rol'], 3);
      expect(json['nombre_rol'], 'Caja');
      expect(json['rut_usuario'], '12.345.678-9');
      expect(user.nombreCompleto, 'María Jesús López Vega');

      final fromJson = AuthUserModel.fromJson(json);
      expect(fromJson.idUsuario, 'user-uuid-123');
      expect(fromJson.idRol, 3);
      expect(fromJson.nombreRol, 'Caja');
    });

    test('AuthService.esCaja() retorna true para id_rol == 3 y nombre_rol Caja', () async {
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '3');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Caja');
      expect(await AuthService.esCaja(), isTrue);

      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '1');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Bodeguero');
      expect(await AuthService.esCaja(), isFalse);

      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '2');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Vendedor');
      expect(await AuthService.esCaja(), isFalse);
    });

    test('AuthService.esAdmin() retorna true para id_rol == 5', () async {
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '5');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Administrador');
      expect(await AuthService.esAdmin(), isTrue);

      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '3');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Caja');
      expect(await AuthService.esAdmin(), isFalse);
    });
  });

  group('SPEC-HU-01: AppRoutes RBAC Route Guards', () {
    test('isRouteAllowedForRole bloquea vistas operativas no autorizadas para rol Caja (3)', () {
      expect(AppRoutes.isRouteAllowedForRole(3, '/caja'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(3, '/login'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(3, '/tickets'), isTrue);

      expect(AppRoutes.isRouteAllowedForRole(3, '/catalogo'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(3, '/carrito'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(3, '/recepcion'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(3, '/paletizado'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(3, '/etiqueta-preview'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(3, '/buscador'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(3, '/bandeja_precios'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(3, '/home'), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(3, '/ventas_main'), isFalse);
    });

    test('isRouteAllowedForRole permite rutas a otros roles autorizados (ej: Admin 5)', () {
      expect(AppRoutes.isRouteAllowedForRole(5, '/catalogo'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(5, '/caja'), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(5, '/home'), isTrue);
    });
  });

  group('SPEC-HU-01: LoginController & Navigation Routing', () {
    testWidgets('handlePostLoginNavigation redirige a /caja cuando idRol == 3', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => LoginController.handlePostLoginNavigation(context, idRol: 3),
                child: const Text('TRIGGER_NAV'),
              );
            },
          ),
          routes: {
            '/caja': (context) => const Scaffold(body: Text('PANTALLA_CAJA')),
            '/home': (context) => const Scaffold(body: Text('PANTALLA_HOME')),
            '/ventas_main': (context) => const Scaffold(body: Text('PANTALLA_VENTAS')),
          },
        ),
      );

      await tester.tap(find.text('TRIGGER_NAV'));
      await tester.pumpAndSettle();

      expect(find.text('PANTALLA_CAJA'), findsOneWidget);
    });

    testWidgets('SplashScreen con sesión de Caja (id_rol == 3) redirige a /caja', (tester) async {
      await const FlutterSecureStorage().write(key: 'access_token', value: 'jwt-caja-token');
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '3');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Caja');

      await tester.pumpWidget(
        MaterialApp(
          home: const SplashScreen(),
          routes: {
            '/login': (context) => const Scaffold(body: Text('LOGIN_SCREEN')),
            '/caja': (context) => const Scaffold(body: Text('CAJA_SCREEN')),
            '/home': (context) => const Scaffold(body: Text('HOME_SCREEN')),
            '/ventas_main': (context) => const Scaffold(body: Text('VENTAS_MAIN_SCREEN')),
          },
        ),
      );

      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pumpAndSettle();

      expect(find.text('CAJA_SCREEN'), findsOneWidget);
    });

    testWidgets('HomeScreen intercepta a usuario de Caja (id_rol == 3) y redirige a /caja', (tester) async {
      await const FlutterSecureStorage().write(key: 'access_token', value: 'jwt-caja-token');
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '3');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Caja');

      await tester.pumpWidget(
        MaterialApp(
          home: const HomeScreen(),
          routes: {
            '/login': (context) => const Scaffold(body: Text('LOGIN_SCREEN')),
            '/caja': (context) => const Scaffold(body: Text('CAJA_SCREEN')),
            '/ventas_main': (context) => const Scaffold(body: Text('VENTAS_MAIN_SCREEN')),
          },
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('CAJA_SCREEN'), findsOneWidget);
    });
  });

  group('SPEC-HU-01: CajaMainScreen & CajaDrawer Widgets UI Tests', () {
    testWidgets('CajaMainScreen renderiza AppBar, datos de cajera, sucursal y pestañas de navegación', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await const FlutterSecureStorage().write(key: 'user_nombre_completo', value: 'María Jesús López');
      await const FlutterSecureStorage().write(key: 'user_sucursal_nombre', value: 'Casa Matriz - Viña');
      await const FlutterSecureStorage().write(key: 'user_sucursal_id', value: '1');
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '3');

      await tester.pumpWidget(
        const MaterialApp(
          home: CajaMainScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CresalLogo), findsOneWidget);
      expect(find.text('MÓDULO DE CAJA'), findsOneWidget);
      expect(find.text('Caja'), findsWidgets);
      expect(find.text('Historial'), findsWidgets);

      // Navegar a la pestaña de Historial de Pagos para ver pantalla de auditoría
      await tester.tap(find.text('Historial').first);
      await tester.pumpAndSettle();

      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Esta Semana'), findsOneWidget);
      expect(find.text('Este Mes'), findsOneWidget);
    });

    testWidgets('CajaDrawer muestra exclusivamente las opciones autorizadas de caja y no las de bodega/ventas', (tester) async {
      await const FlutterSecureStorage().write(key: 'user_nombre_completo', value: 'María Jesús López');
      await const FlutterSecureStorage().write(key: 'user_sucursal_nombre', value: 'Casa Matriz - Viña');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'CAJA');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            drawer: const CajaDrawer(),
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  child: const Text('OPEN_DRAWER'),
                );
              },
            ),
          ),
          routes: {
            '/login': (context) => const Scaffold(body: Text('LOGIN_SCREEN')),
            '/tickets': (context) => const Scaffold(body: Text('TICKETS_SCREEN')),
          },
        ),
      );

      // Abrir drawer
      await tester.tap(find.text('OPEN_DRAWER'));
      await tester.pumpAndSettle();

      // Opciones autorizadas presentes
      expect(find.text('Bandeja de Cobros'), findsOneWidget);
      expect(find.text('Historial de Órdenes y Pagos'), findsOneWidget);
      expect(find.text('Tickets de Soporte'), findsOneWidget);
      expect(find.text('CERRAR SESIÓN'), findsOneWidget);

      // Opciones ajenas de ventas / bodega ausentes
      expect(find.text('Catálogo'), findsNothing);
      expect(find.text('Carrito'), findsNothing);
      expect(find.text('Recepción Vehículo'), findsNothing);
      expect(find.text('Paletizado'), findsNothing);
      expect(find.text('Bandeja de Precios'), findsNothing);
    });

    testWidgets('CajaDrawer: Acción de Cerrar Sesión muestra diálogo y destruye credenciales', (tester) async {
      await const FlutterSecureStorage().write(key: 'access_token', value: 'token-cajera');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Caja');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            drawer: const CajaDrawer(),
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  child: const Text('OPEN_DRAWER'),
                );
              },
            ),
          ),
          routes: {
            '/login': (context) => const Scaffold(body: Text('LOGIN_SCREEN')),
          },
        ),
      );

      // Abrir drawer
      await tester.tap(find.text('OPEN_DRAWER'));
      await tester.pumpAndSettle();

      // Presionar botón de cerrar sesión
      await tester.tap(find.text('CERRAR SESIÓN'));
      await tester.pumpAndSettle();

      // Verificar diálogo de confirmación
      expect(find.text('¿Está seguro de que desea cerrar la sesión del turno de caja actual?'), findsOneWidget);

      // Confirmar cierre en el diálogo
      final botonConfirmar = find.widgetWithText(ElevatedButton, 'CERRAR SESIÓN');
      await tester.tap(botonConfirmar);
      await tester.pumpAndSettle();

      // Verificar navegación hacia /login
      expect(find.text('LOGIN_SCREEN'), findsOneWidget);
      // Verificar eliminación de credenciales
      expect(await AuthService.getToken(), isNull);
    });
  });
}
