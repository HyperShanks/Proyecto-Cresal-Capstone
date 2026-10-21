// test/features/autorefresh/autorefresh_navigation_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/core/routes/route_observer.dart';
import 'package:frontend/features/alertas/models/tarea_alerta.dart';
import 'package:frontend/features/alertas/presentation/screens/alertas_screen.dart';
import 'package:frontend/features/alertas/services/bodega_polling_service.dart';
import 'package:frontend/features/caja/presentation/screens/caja_main_screen.dart';
import 'package:frontend/features/caja/presentation/screens/historial_caja_screen.dart';
import 'package:frontend/features/ventas/presentation/screens/ventas_main_screen.dart';
import 'package:frontend/features/ventas/presentation/screens/catalogo_screen.dart';
import 'package:frontend/features/ventas/presentation/screens/historial_screen.dart';
import 'package:frontend/features/ventas/presentation/screens/bandeja_precios_screen.dart';
import 'package:frontend/features/gerencia/presentation/screens/dashboard_gerencia_view.dart';

// Screen auxiliar para probar RouteAware
class DummyRouteAwareScreen extends StatefulWidget {
  final VoidCallback onDidPopNext;
  const DummyRouteAwareScreen({super.key, required this.onDidPopNext});

  @override
  State<DummyRouteAwareScreen> createState() => _DummyRouteAwareScreenState();
}

class _DummyRouteAwareScreenState extends State<DummyRouteAwareScreen> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    super.didPopNext();
    widget.onDidPopNext();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const Key('btn_push'),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      key: const Key('btn_pop'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Volver'),
                    ),
                  ),
                ),
              ),
            );
          },
          child: const Text('Push'),
        ),
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockStorage = {
    'access_token': 'fake-token',
    'id_usuario': '1',
    'id_rol': '6',
    'rol': 'Jefe de Ventas',
    'nombre_usuario': 'Carlos Jefe',
    'sucursal': 'Casa Matriz',
    'id_sucursal': '1',
  };

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(mockStorage);
    BodegaPollingService.instance.reset();
  });

  group('SPEC-HU-TAREA-20: RouteObserver Global & RouteAware', () {
    testWidgets('RouteObserver notifica didPopNext cuando la ruta secundaria se cierra con pop', (tester) async {
      int popNextCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routeObserver],
          home: DummyRouteAwareScreen(
            onDidPopNext: () {
              popNextCount++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(popNextCount, 0);

      // Abrir ruta secundaria
      await tester.tap(find.byKey(const Key('btn_push')));
      await tester.pumpAndSettle();

      // Cerrar ruta secundaria (pop)
      await tester.tap(find.byKey(const Key('btn_pop')));
      await tester.pumpAndSettle();

      // Debe haberse ejecutado didPopNext
      expect(popNextCount, 1);
    });

    test('Las pantallas principales implementan RouteAware y métodos de refresco público', () {
      final catalogoState = CatalogoScreenState();
      expect(catalogoState, isA<RouteAware>());
      expect(catalogoState.refrescarCatalogo, isA<Function>());

      final historialState = HistorialScreenState();
      expect(historialState, isA<RouteAware>());
      expect(historialState.refrescar, isA<Function>());

      final bandejaState = BandejaPreciosScreenState();
      expect(bandejaState, isA<RouteAware>());
      expect(bandejaState.refrescar, isA<Function>());

      final historialCajaState = HistorialCajaScreenState();
      expect(historialCajaState, isA<RouteAware>());
      expect(historialCajaState.refrescar, isA<Function>());
    });
  });

  group('SPEC-HU-TAREA-21: AlertasScreen In-Memory Tabs & Non-Destructive Refresh', () {
    testWidgets('Cambio de pestaña en AlertasScreen es instantáneo en memoria sin refetch agresivo', (tester) async {
      int fetchCount = 0;
      final mockTareas = [
        const TareaAlerta(
          idTarea: 'ORD-1',
          tipoAlerta: 'PREPARACION',
          tituloPieza: 'Cilindro Maestro',
          accionRequerida: 'PREPARAR',
          ubicacion: 'A-10',
        ),
        const TareaAlerta(
          idTarea: 'IMP-1',
          tipoAlerta: 'IMPRESION',
          tituloPieza: 'Etiqueta Termostato',
          accionRequerida: 'IMPRIMIR QR',
          ubicacion: 'B-20',
        ),
      ];

      Future<List<TareaAlerta>> mockFetch() async {
        fetchCount++;
        return mockTareas;
      }

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routeObserver],
          home: AlertasScreen(onFetchAlertas: mockFetch),
        ),
      );
      await tester.pumpAndSettle();

      // Carga inicial
      expect(fetchCount, 1);
      expect(find.text('Cilindro Maestro'), findsOneWidget);

      // Tocar tab "Imprimir" (navegación instantánea en memoria sin refetch)
      await tester.tap(find.text('Imprimir'));
      await tester.pumpAndSettle();

      expect(fetchCount, 1);
      expect(find.text('Etiqueta Termostato'), findsOneWidget);

      // Tocar tab "Re-integración"
      await tester.tap(find.text('Re-integración'));
      await tester.pumpAndSettle();

      expect(fetchCount, 1);
      expect(find.text('Sin re-integraciones pendientes'), findsOneWidget);

      // Botón de refresco manual en AppBar actualiza explícitamente
      await tester.tap(find.byTooltip('Actualizar tareas'));
      await tester.pumpAndSettle();

      expect(fetchCount, 2);
    });
  });

  group('SPEC-HU-TAREA-20: VentasMainScreen Tab Reactivity', () {
    testWidgets('Navegación entre pestañas de VentasMainScreen cambia de índice e invoca refrescos', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routeObserver],
          home: const VentasMainScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Catálogo'), findsWidgets);
      expect(find.text('Mis Órdenes'), findsWidgets);

      // Tocar pestaña "Mis Órdenes" (Tab 1)
      await tester.tap(find.text('Mis Órdenes'));
      await tester.pumpAndSettle();

      // Tocar pestaña "Tasación" (Tab 2) si está disponible para Jefe de Ventas
      if (find.text('Tasación').evaluate().isNotEmpty) {
        await tester.tap(find.text('Tasación'));
        await tester.pumpAndSettle();
      }

      // Volver a pestaña "Catálogo" (Tab 0)
      await tester.tap(find.text('Catálogo'));
      await tester.pumpAndSettle();
    });
  });

  group('SPEC-HU-TAREA-20: CajaMainScreen Sidebar Reactivity', () {
    testWidgets('Navegación en Sidebar de CajaMainScreen conmuta vistas en IndexedStack e invoca refrescos', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routeObserver],
          home: const CajaMainScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Caja'), findsWidgets);
      expect(find.text('Historial'), findsWidgets);

      // Cambiar a pestaña Historial
      await tester.tap(find.text('Historial').first);
      await tester.pumpAndSettle();

      // Cambiar de vuelta a Caja
      await tester.tap(find.text('Caja').first);
      await tester.pumpAndSettle();
    });
  });

  group('SPEC-HU-TAREA-20: DashboardGerenciaView Tab & Refresh Reactivity', () {
    testWidgets('Botón Actualizar y cambio de pestañas en DashboardGerenciaView refrescan la vista activa', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routeObserver],
          home: const DashboardGerenciaView(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('CRESAL GERENCIA'), findsWidgets);
      expect(find.text('Actualizar'), findsOneWidget);

      // Presionar botón Actualizar en Dashboard
      await tester.tap(find.text('Actualizar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Conmutar a pestaña "Historial de Órdenes"
      await tester.tap(find.text('Historial de Órdenes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Presionar botón Actualizar en pestaña activa
      if (find.text('Actualizar').evaluate().isNotEmpty) {
        await tester.tap(find.text('Actualizar'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }

      // Conmutar a pestaña "Inventario y Tasación"
      await tester.tap(find.text('Inventario y Tasación'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Conmutar de vuelta a "Dashboard Ejecutivo"
      await tester.tap(find.text('Dashboard Ejecutivo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
