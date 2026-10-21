// test/features/inventario/filtros_estado_test.dart
// Pruebas automatizadas de Widgets para SPEC-HU-TAREA-16:
// Filtros de Estado y Visualización de Galpón/Ubicación en Inventario y Alertas

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/features/inventario/presentation/screens/inventario_screen.dart';
import 'package:frontend/features/inventario/presentation/widgets/resultado_card.dart';
import 'package:frontend/features/alertas/models/tarea_alerta.dart';
import 'package:frontend/features/alertas/presentation/widgets/task_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockStorage = {};

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'read') {
          return mockStorage[methodCall.arguments['key'] as String];
        } else if (methodCall.method == 'write') {
          mockStorage[methodCall.arguments['key'] as String] = methodCall.arguments['value'] as String;
          return null;
        } else if (methodCall.method == 'delete') {
          mockStorage.remove(methodCall.arguments['key'] as String);
          return null;
        }
        return null;
      },
    );
  });

  setUp(() {
    mockStorage.clear();
    mockStorage['access_token'] = 'mock_jwt_token_bodega';
    mockStorage['user_rol'] = 'Bodeguero';
    mockStorage['user_id_rol'] = '1';
  });

  group('SPEC-HU-TAREA-16: ResultadoCard - Enriquecimiento Visual de Galpón', () {
    testWidgets('Muestra Galpón en chip destacado y pasillo/pallet como subtítulo', (tester) async {
      final itemConGalpon = {
        'id_activo': 'act-001',
        'categoria': 'Motor',
        'marca': 'Toyota',
        'modelo': 'Hilux',
        'sku': 'MOT-TOY-HIL-01',
        'galpon': 'Galpón A',
        'ubicacion_galpon': 'Galpón A',
        'pasillo': 'P-03',
        'pallet': 'PL-12',
        'estado': 'DISPONIBLE',
        'imagenes': [],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultadoCard(
              itemCompleto: itemConGalpon,
              marca: 'Toyota',
              modelo: 'Hilux',
              sku: 'MOT-TOY-HIL-01',
              ubicacion: 'P-03 - PL-12',
              estado: 'DISPONIBLE',
            ),
          ),
        ),
      );

      // Verificación de que el chip duplicado de Galpón fue eliminado
      expect(find.byKey(const Key('chip_galpon_destacado')), findsNothing);
      expect(find.text('GALPÓN: Galpón A'), findsNothing);

      // Verificación de la ubicación oficial única
      expect(find.textContaining('Pasillo: P-03'), findsOneWidget);
      expect(find.textContaining('Pallet: PL-12'), findsOneWidget);
      expect(find.textContaining('Galpón: Galpón A'), findsOneWidget);
    });

    testWidgets('Muestra "Sin Galpón / Sin Ubicación asignada" en activo huérfano de ubicación', (tester) async {
      final itemHuerfano = {
        'id_activo': 'act-huerfano',
        'categoria': 'Accesorio',
        'marca': 'Nissan',
        'modelo': 'Kicks',
        'sku': 'ACC-NIS-KIC-99',
        'galpon': '',
        'ubicacion_galpon': '',
        'pasillo': '',
        'pallet': '',
        'estado': 'DISPONIBLE',
        'imagenes': [],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResultadoCard(
              itemCompleto: itemHuerfano,
              marca: 'Nissan',
              modelo: 'Kicks',
              sku: 'ACC-NIS-KIC-99',
              ubicacion: '',
              estado: 'DISPONIBLE',
            ),
          ),
        ),
      );

      // Aviso preventivo exigido por SPEC-HU-TAREA-16
      expect(find.text('Sin Galpón / Sin Ubicación asignada'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });

  group('SPEC-HU-TAREA-16: TaskCard (Alertas) - Visualización de Galpón', () {
    testWidgets('Muestra Galpón en chip destacado en la tarjeta de tarea', (tester) async {
      const tareaConGalpon = TareaAlerta(
        idTarea: 'ORD-101',
        tipoAlerta: 'PREPARACION',
        tituloPieza: 'Motor Toyota Corolla',
        accionRequerida: 'PREPARAR',
        ubicacion: 'P-01 - PL-05',
        ubicacionGalpon: 'Galpón Central',
        ubicacionPasillo: 'P-01',
        ubicacionPallet: 'PL-05',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TaskCard(tarea: tareaConGalpon),
          ),
        ),
      );

      expect(find.byKey(const Key('chip_galpon_tarea')), findsOneWidget);
      expect(find.textContaining('Galpón: Galpón Central'), findsOneWidget);
      expect(find.textContaining('Pasillo: P-01'), findsOneWidget);
      expect(find.textContaining('Pallet: PL-05'), findsOneWidget);
    });

    testWidgets('Muestra aviso preventivo cuando la tarea no tiene ubicación asignada', (tester) async {
      const tareaSinUbicacion = TareaAlerta(
        idTarea: 'ORD-102',
        tipoAlerta: 'PREPARACION',
        tituloPieza: 'Caja Sin Ubicar',
        accionRequerida: 'PREPARAR',
        ubicacion: 'Ubicación Pendiente',
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TaskCard(tarea: tareaSinUbicacion),
          ),
        ),
      );

      expect(find.text('Sin Galpón / Sin Ubicación asignada'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });
  });

  group('SPEC-HU-TAREA-16: BuscadorScreen & InventarioScreen - Filter Chips de Estado', () {
    testWidgets('InventarioScreen es un alias funcional de BuscadorScreen', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: InventarioScreen(),
        ),
      );

      expect(find.byType(BuscadorScreen), findsOneWidget);
      expect(find.text('INVENTARIO DE BODEGA'), findsOneWidget);
    });

    testWidgets('Renderiza los 4 chips de estado operativo en la cabecera (excluyendo Vendidos)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BuscadorScreen(),
        ),
      );

      expect(find.byKey(const Key('chip_filtro_todos')), findsOneWidget);
      expect(find.byKey(const Key('chip_filtro_disponibles')), findsOneWidget);
      expect(find.byKey(const Key('chip_filtro_reservados')), findsOneWidget);
      expect(find.byKey(const Key('chip_filtro_paletizados')), findsOneWidget);
      expect(find.byKey(const Key('chip_filtro_vendidos')), findsNothing);

      expect(find.text('Todos'), findsOneWidget);
      expect(find.text('Disponibles'), findsOneWidget);
      expect(find.text('Reservados'), findsOneWidget);
      expect(find.text('Paletizados'), findsOneWidget);
      expect(find.text('Vendidos'), findsNothing);
    });

    testWidgets('Permite alternar entre chips de filtro de estado cuando está online', (tester) async {
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('opciones-filtros')) {
          return http.Response(jsonEncode({}), 200);
        }
        if (request.url.path.contains('buscar')) {
          return http.Response(jsonEncode([]), 200);
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(
          const MaterialApp(
            home: BuscadorScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Tocar el chip 'Disponibles'
        await tester.tap(find.byKey(const Key('chip_filtro_disponibles')));
        await tester.pumpAndSettle();

        final filterChipWidget = tester.widget<FilterChip>(find.byKey(const Key('chip_filtro_disponibles')));
        expect(filterChipWidget.selected, isTrue);

        // Tocar el chip 'Paletizados'
        await tester.tap(find.byKey(const Key('chip_filtro_paletizados')));
        await tester.pumpAndSettle();

        final paletizadosChip = tester.widget<FilterChip>(find.byKey(const Key('chip_filtro_paletizados')));
        expect(paletizadosChip.selected, isTrue);

        final disponiblesChip = tester.widget<FilterChip>(find.byKey(const Key('chip_filtro_disponibles')));
        expect(disponiblesChip.selected, isFalse);
      }, () => mockClient);
    });

    testWidgets('Muestra mensaje de error offline al fallar conexión en cambio de filtro', (tester) async {
      final offlineClient = MockClient((request) async {
        if (request.url.path.contains('opciones-filtros')) {
          return http.Response(jsonEncode({}), 200);
        }
        if (request.url.path.contains('buscar')) {
          throw http.ClientException('Connection failed');
        }
        return http.Response('{}', 200);
      });

      await http.runWithClient(() async {
        await tester.pumpWidget(
          const MaterialApp(
            home: BuscadorScreen(),
          ),
        );
        await tester.pumpAndSettle();

        // Tocar chip 'Reservados' mientras falla la red
        await tester.tap(find.byKey(const Key('chip_filtro_reservados')));
        await tester.pump();

        // Verifica mensaje exacto de SPEC-HU-TAREA-16
        expect(find.text('No hay conexión para aplicar este filtro. Mostrando caché temporal.'), findsOneWidget);
      }, () => offlineClient);
    });
  });
}
