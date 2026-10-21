// test/home_screen_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/features/alertas/services/bodega_polling_service.dart';
import 'package:frontend/features/home/presentation/screens/home_screen.dart';

Widget _createHomeScreenWrapper({
  Map<String, WidgetBuilder>? additionalRoutes,
}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: const HomeScreen(),
    routes: {
      '/login': (context) => const Scaffold(body: Text('Login Screen Mock')),
      '/ventas_main': (context) => const Scaffold(body: Text('Ventas Main Mock')),
      '/recepcion': (context) => const Scaffold(body: Text('Recepcion Screen Mock')),
      '/paletizado': (context) => const Scaffold(body: Text('Paletizado Screen Mock')),
      '/buscador': (context) => const Scaffold(body: Text('Buscador Screen Mock')),
      '/alertas': (context) => const Scaffold(body: Text('Alertas Screen Mock')),
      '/tickets': (context) => const Scaffold(body: Text('Tickets Screen Mock')),
      ...?additionalRoutes,
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'mock-valid-token',
      'user_rol': 'Bodeguero',
      'user_id_rol': '1',
      'user_sucursal_id': '2',
      'user_sucursal_nombre': 'Viña del Mar',
      'user_nombre_completo': 'Juan Pérez',
    });
    BodegaPollingService.instance.reset();
  });

  group('HomeScreen - Cabecera de Contexto Operativo', () {
    testWidgets('Muestra saludo personalizado, rol y badge de sucursal real', (tester) async {
      await tester.pumpWidget(_createHomeScreenWrapper());
      await tester.pumpAndSettle();

      // Saludo y subtítulo
      expect(find.text('Hola, Juan 👋'), findsOneWidget);
      expect(find.text('Operador de Bodega'), findsOneWidget);

      // Badge de sucursal real
      expect(find.text('📍 Viña del Mar'), findsOneWidget);
    });

    testWidgets('Usa fallbacks si no hay nombre o sucursal en sesión', (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'access_token': 'mock-valid-token',
        'user_rol': 'Bodeguero',
      });

      await tester.pumpWidget(_createHomeScreenWrapper());
      await tester.pumpAndSettle();

      expect(find.text('Hola, Operador 👋'), findsOneWidget);
      expect(find.text('📍 Sucursal Central'), findsOneWidget);
    });
  });

  group('HomeScreen - Tarjeta Hero Reactiva (Alerta Tareas)', () {
    testWidgets('Estado 0 tareas: Muestra mensaje de sin tareas y ningún badge', (tester) async {
      BodegaPollingService.instance.totalPendientesNotifier.value = 0;
      BodegaPollingService.instance.tieneTrasladosNotifier.value = false;

      await tester.pumpWidget(_createHomeScreenWrapper());
      await tester.pumpAndSettle();

      expect(find.text('ALERTA TAREAS'), findsOneWidget);
      expect(find.text('Sin tareas pendientes en sucursal'), findsOneWidget);
      expect(find.byKey(const Key('home_badge_alertas')), findsNothing);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
    });

    testWidgets('Estado > 0 tareas sin traslados: Muestra badge numérico y atención inmediata', (tester) async {
      BodegaPollingService.instance.totalPendientesNotifier.value = 4;
      BodegaPollingService.instance.tieneTrasladosNotifier.value = false;

      await tester.pumpWidget(_createHomeScreenWrapper());
      await tester.pumpAndSettle();

      expect(find.text('ALERTA TAREAS'), findsOneWidget);
      expect(find.text('Requiere atención inmediata'), findsOneWidget);
      expect(find.byKey(const Key('home_badge_alertas')), findsOneWidget);
      expect(find.text('4'), findsWidgets);
      expect(find.byIcon(Icons.notifications_active_rounded), findsOneWidget);
    });

    testWidgets('Estado > 0 tareas con traslados: Muestra texto de traslados prioritarios e ícono de advertencia', (tester) async {
      BodegaPollingService.instance.totalPendientesNotifier.value = 7;
      BodegaPollingService.instance.tieneTrasladosNotifier.value = true;

      await tester.pumpWidget(_createHomeScreenWrapper());
      await tester.pumpAndSettle();

      expect(find.text('Requiere atención inmediata • Incluye traslados prioritarios'), findsOneWidget);
      expect(find.text('7'), findsWidgets);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('Tap en Alerta Tareas navega a /alertas', (tester) async {
      await tester.pumpWidget(_createHomeScreenWrapper());
      await tester.pumpAndSettle();

      await tester.tap(find.text('ALERTA TAREAS'));
      await tester.pumpAndSettle();

      expect(find.text('Alertas Screen Mock'), findsOneWidget);
    });
  });

  group('HomeScreen - Cuadrícula de Acciones Frecuentes y Buscador', () {
    testWidgets('Segregación: No renderiza Recepción de Vehículo ni Reingresos y Alertas en Acciones Frecuentes', (tester) async {
      await tester.pumpWidget(_createHomeScreenWrapper());
      await tester.pumpAndSettle();

      expect(find.text('Recepción de Vehículo'), findsNothing);
      expect(find.text('Reingresos y Alertas'), findsNothing);
      expect(find.text('Bandeja de logística inversa y piezas devueltas'), findsNothing);
      expect(find.byIcon(Icons.assignment_return_rounded), findsNothing);
    });

    testWidgets('Renderiza Paletizado de Piezas y navega correctamente', (tester) async {
      await tester.pumpWidget(_createHomeScreenWrapper());
      await tester.pumpAndSettle();

      expect(find.text('Paletizado de Piezas'), findsOneWidget);
      expect(find.text('Validación OCR o selección manual del N° de ingreso'), findsOneWidget);
      expect(find.byIcon(Icons.inventory_2_outlined), findsWidgets);

      await tester.tap(find.text('Paletizado de Piezas'));
      await tester.pumpAndSettle();

      expect(find.text('Paletizado Screen Mock'), findsOneWidget);
    });

    testWidgets('Renderiza Buscador de Inventario a ancho completo y navega', (tester) async {
      await tester.pumpWidget(_createHomeScreenWrapper());
      await tester.pumpAndSettle();

      expect(find.text('Buscador de Inventario'), findsOneWidget);
      expect(find.text('Consulta rápida por SKU, QR, Pasillo o Modelo'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);

      await tester.tap(find.text('Buscador de Inventario'));
      await tester.pumpAndSettle();

      expect(find.text('Buscador Screen Mock'), findsOneWidget);
    });

    testWidgets('Renderiza AppBar con título Terminal Bodega', (tester) async {
      await tester.pumpWidget(_createHomeScreenWrapper());
      await tester.pumpAndSettle();

      expect(find.text('Terminal Bodega'), findsOneWidget);
    });
  });

  group('HomeScreen - Drawer y Cierre de Sesión', () {
    testWidgets('Apertura de Drawer muestra datos y diálogo de confirmación de logout', (tester) async {
      await tester.pumpWidget(_createHomeScreenWrapper());
      await tester.pumpAndSettle();

      // Abrir Drawer con el botón hamburguesa
      await tester.tap(find.byTooltip('Menú'));
      await tester.pumpAndSettle();

      expect(find.text('Juan Pérez'), findsOneWidget);
      expect(find.text('BODEGUERO'), findsOneWidget);
      expect(find.text('Viña del Mar'), findsOneWidget);
      expect(find.text('TICKET'), findsOneWidget);
      expect(find.text('CONFIGURACIÓN'), findsOneWidget);
      expect(find.text('CERRAR SESIÓN'), findsOneWidget);

      // Tap en Cerrar Sesión
      await tester.tap(find.text('CERRAR SESIÓN'));
      await tester.pumpAndSettle();

      // Diálogo de confirmación
      expect(find.text('¿Estás seguro de que deseas cerrar sesión?'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);

      // Cancelar diálogo
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('¿Estás seguro de que deseas cerrar sesión?'), findsNothing);
    });

    testWidgets('Confirmar CERRAR SESIÓN redirige a /login', (tester) async {
      await tester.pumpWidget(_createHomeScreenWrapper());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Menú'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('CERRAR SESIÓN'));
      await tester.pumpAndSettle();

      // Confirmar en el modal
      final confirmBtn = find.widgetWithText(TextButton, 'CERRAR SESIÓN');
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(find.text('Login Screen Mock'), findsOneWidget);
    });
  });
}
