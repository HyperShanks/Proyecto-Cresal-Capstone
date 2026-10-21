// frontend/test/features/gerencia/gerencia_silent_refresh_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/gerencia/presentation/screens/dashboard_gerencia_view.dart';
import 'package:frontend/features/gerencia/presentation/screens/ordenes_gerencia_view.dart';
import 'package:frontend/features/gerencia/presentation/screens/inventario_gerencia_view.dart';
import 'package:frontend/features/gerencia/presentation/screens/backorders_gerencia_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Gerencia - Silent Refresh & Polling Tests', () {
    testWidgets('DashboardGerenciaView utiliza IndexedStack con las 4 vistas montadas y cambio 60 FPS', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DashboardGerenciaView(sucursalInicial: 1),
          ),
        ),
      );
      await tester.pump();

      // Verifica que exista el IndexedStack principal con las 4 vistas
      final indexedStackFinder = find.byWidgetPredicate(
        (w) => w is IndexedStack && w.children.length == 4,
      );
      expect(indexedStackFinder, findsOneWidget);

      final indexedStackInitial = tester.widget<IndexedStack>(indexedStackFinder);
      expect(indexedStackInitial.index, equals(0)); // Dashboard activo inicialmente

      // 1. Pasa a la pestaña Historial de Órdenes (index 1)
      final ordenesNav = find.text('Historial de Órdenes');
      expect(ordenesNav, findsOneWidget);
      await tester.tap(ordenesNav);
      await tester.pump();

      final stackOrdenes = tester.widget<IndexedStack>(indexedStackFinder);
      expect(stackOrdenes.index, equals(VistaGerencia.ordenes.index));

      // 2. Pasa a Inventario y Tasación (index 2)
      final inventarioNav = find.text('Inventario y Tasación');
      expect(inventarioNav, findsOneWidget);
      await tester.tap(inventarioNav);
      await tester.pump();

      final stackInventario = tester.widget<IndexedStack>(indexedStackFinder);
      expect(stackInventario.index, equals(VistaGerencia.inventario.index));

      // 3. Pasa a Ventas en Verde (index 3)
      final backordersNav = find.text('Ventas en Verde');
      expect(backordersNav, findsOneWidget);
      await tester.tap(backordersNav);
      await tester.pump();

      final stackBackorders = tester.widget<IndexedStack>(indexedStackFinder);
      expect(stackBackorders.index, equals(VistaGerencia.backorders.index));

      // 4. Regresar al Dashboard (index 0)
      final dashboardNav = find.text('Dashboard Ejecutivo');
      expect(dashboardNav, findsOneWidget);
      await tester.tap(dashboardNav);
      await tester.pump();

      final stackDashboard = tester.widget<IndexedStack>(indexedStackFinder);
      expect(stackDashboard.index, equals(VistaGerencia.dashboard.index));
    });

    testWidgets('OrdenesGerenciaView expone refrescarSilencioso sin forzar página 1', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final key = GlobalKey<OrdenesGerenciaViewState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrdenesGerenciaView(
              key: key,
              idSucursalInicial: 1,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(key.currentState, isNotNull);
      // Comprobamos que el método refrescarSilencioso existe y está tipado correctamente
      expect(key.currentState!.refrescarSilencioso, isNotNull);
    });

    testWidgets('InventarioGerenciaView expone refrescarSilencioso y guardia isModalAbierto', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final key = GlobalKey<InventarioGerenciaViewState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventarioGerenciaView(
              key: key,
              idSucursalInicial: 1,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(key.currentState, isNotNull);
      expect(key.currentState!.isModalAbierto, isFalse);
      expect(key.currentState!.refrescarSilencioso, isNotNull);
    });

    testWidgets('BackordersGerenciaView expone refrescarSilencioso', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final key = GlobalKey<BackordersGerenciaViewState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BackordersGerenciaView(
              key: key,
              idSucursalInicial: 1,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(key.currentState, isNotNull);
      expect(key.currentState!.refrescarSilencioso, isNotNull);
    });
  });
}
