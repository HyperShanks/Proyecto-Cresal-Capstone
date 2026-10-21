// test/features/home/home_paletizado_input_test.dart
// Suite de pruebas de Widgets y Flujos de SPEC-HU-TAREA-14:
// Acceso Directo por Número de Ingreso al Flujo de Paletizado y Enriquecimiento

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/features/home/presentation/screens/home_screen.dart';
import 'package:frontend/features/paletizado/services/paletizado_service.dart';
import 'package:frontend/features/paletizado/presentation/screens/paletizado_screen.dart';
import 'package:http/http.dart' as http;

class MockPaletizadoService extends PaletizadoService {
  final Future<ConsultaIngresoResult> Function(String folio)? onConsultarIngreso;
  int llamadasConsulta = 0;

  MockPaletizadoService({this.onConsultarIngreso});

  @override
  Future<ConsultaIngresoResult> consultarIngresoParaPaletizado(
    String numeroIngreso, {
    http.Client? client,
  }) async {
    llamadasConsulta++;
    if (onConsultarIngreso != null) {
      return onConsultarIngreso!(numeroIngreso);
    }
    return ConsultaIngresoResult.success({
      'numero_ingreso': numeroIngreso,
      'pendiente_paletizado': true,
      'vehiculo': {
        'marca': 'Toyota',
        'modelo': 'Corolla',
        'anio': 2021,
      },
      'motor': {'id_estado': 5, 'numero_motor': '1ZR-FE'},
      'caja_cambios': {'id_estado': 5},
    });
  }
}

Widget _crearHomeScreenWrapper({
  required PaletizadoService service,
  Widget Function(BuildContext)? paletizadoBuilder,
}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: HomeScreen(paletizadoService: service),
    routes: {
      '/login': (context) => const Scaffold(body: Text('Login Screen Mock')),
      '/alertas': (context) => const Scaffold(body: Text('Alertas Screen Mock')),
      '/recepcion': (context) => const Scaffold(body: Text('Recepcion Screen Mock')),
      '/paletizado': (context) => paletizadoBuilder != null
          ? paletizadoBuilder(context)
          : Scaffold(
              body: Builder(builder: (ctx) {
                final arg = ModalRoute.of(ctx)?.settings.arguments;
                return Text('Paletizado Screen Mock - Arg: $arg');
              }),
            ),
      '/buscador': (context) => const Scaffold(body: Text('Buscador Screen Mock')),
      '/tickets': (context) => const Scaffold(body: Text('Tickets Screen Mock')),
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'mock-valid-token',
      'user_rol': 'Bodeguero',
      'id_rol': '1',
      'user_nombre': 'Pedro Bodega',
      'user_sucursal': 'Casa Matriz',
      'sucursal_id': '1',
    });
  });

  group('SPEC-HU-TAREA-14: Input de Paletizado Directo en HomeScreen', () {
    testWidgets('Tarea 2: Renderiza input numérico y botón de lupa en la tarjeta de paletizado', (tester) async {
      final mockService = MockPaletizadoService();
      await tester.pumpWidget(_crearHomeScreenWrapper(service: mockService));
      await tester.pumpAndSettle();

      // Verificar que el TextField existe con teclado numérico
      final inputFinder = find.byKey(const Key('input_numero_ingreso_home'));
      expect(inputFinder, findsOneWidget);

      final textField = tester.widget<TextField>(inputFinder);
      expect(textField.keyboardType, TextInputType.number);
      expect(textField.decoration?.hintText, 'Búsqueda rápida N° Ingreso');

      // Verificar que el botón de lupa existe
      final btnBuscar = find.byKey(const Key('btn_buscar_paletizado_home'));
      expect(btnBuscar, findsOneWidget);
      expect(find.descendant(of: btnBuscar, matching: find.byIcon(Icons.search)), findsOneWidget);
    });

    testWidgets('Validación Vacía: Campo vacío al presionar buscar no realiza petición HTTP ni redirige', (tester) async {
      final mockService = MockPaletizadoService();
      await tester.pumpWidget(_crearHomeScreenWrapper(service: mockService));
      await tester.pumpAndSettle();

      final btnBuscar = find.byKey(const Key('btn_buscar_paletizado_home'));
      await tester.tap(btnBuscar);
      await tester.pumpAndSettle();

      expect(mockService.llamadasConsulta, 0);
      expect(find.textContaining('Paletizado Screen Mock'), findsNothing);
    });

    testWidgets('Tarea 5 & 6: Activo No Encontrado (404) muestra SnackBar exacto y mantiene foco en el input', (tester) async {
      final mockService = MockPaletizadoService(
        onConsultarIngreso: (folio) async => ConsultaIngresoResult.error(
          404,
          'Número de ingreso no encontrado en la base de datos.',
        ),
      );

      await tester.pumpWidget(_crearHomeScreenWrapper(service: mockService));
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const Key('input_numero_ingreso_home'));
      await tester.enterText(inputFinder, '9999');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mockService.llamadasConsulta, 1);
      expect(find.text('Número de ingreso no encontrado en la base de datos.'), findsOneWidget);
      expect(find.textContaining('Paletizado Screen Mock'), findsNothing);

      // Verificar que el input retuvo el foco
      final FocusNode focusNode = tester.widget<TextField>(inputFinder).focusNode!;
      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets('Tarea 5: Activo Ya Paletizado (400) muestra SnackBar exacto y no redirige', (tester) async {
      final mockService = MockPaletizadoService(
        onConsultarIngreso: (folio) async => ConsultaIngresoResult.error(
          400,
          'El activo asociado a este número ya fue paletizado previamente o no requiere este flujo.',
        ),
      );

      await tester.pumpWidget(_crearHomeScreenWrapper(service: mockService));
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const Key('input_numero_ingreso_home'));
      await tester.enterText(inputFinder, '7002');
      final btnBuscar = find.byKey(const Key('btn_buscar_paletizado_home'));
      await tester.tap(btnBuscar);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mockService.llamadasConsulta, 1);
      expect(
        find.text('El activo asociado a este número ya fue paletizado previamente o no requiere este flujo.'),
        findsOneWidget,
      );
      expect(find.textContaining('Paletizado Screen Mock'), findsNothing);
    });

    testWidgets('Tarea 5: Fallo de Red muestra mensaje de reintento de conexión y no colapsa', (tester) async {
      final mockService = MockPaletizadoService(
        onConsultarIngreso: (folio) async => ConsultaIngresoResult.error(
          -1,
          'Error de conexión. Reintentando la búsqueda...',
        ),
      );

      await tester.pumpWidget(_crearHomeScreenWrapper(service: mockService));
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const Key('input_numero_ingreso_home'));
      await tester.enterText(inputFinder, '5001');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(mockService.llamadasConsulta, 1);
      expect(find.text('Error de conexión. Reintentando la búsqueda...'), findsOneWidget);
      expect(find.textContaining('Paletizado Screen Mock'), findsNothing);
    });

    testWidgets('Tarea 3: Búsqueda exitosa redirige de inmediato a /paletizado con el folio en argumentos', (tester) async {
      final mockService = MockPaletizadoService(
        onConsultarIngreso: (folio) async => ConsultaIngresoResult.success({
          'numero_ingreso': folio,
          'pendiente_paletizado': true,
          'vehiculo': {'marca': 'Toyota', 'modelo': 'Yaris'},
        }),
      );

      await tester.pumpWidget(_crearHomeScreenWrapper(service: mockService));
      await tester.pumpAndSettle();

      final inputFinder = find.byKey(const Key('input_numero_ingreso_home'));
      await tester.enterText(inputFinder, '7001');
      final btnBuscar = find.byKey(const Key('btn_buscar_paletizado_home'));
      await tester.tap(btnBuscar);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(mockService.llamadasConsulta, 1);
      expect(find.text('Paletizado Screen Mock - Arg: 7001'), findsOneWidget);
    });
  });

  group('SPEC-HU-TAREA-14: PaletizadoScreen en Modo Directo y Desacoplamiento de Lista', () {
    testWidgets('Tarea 4: PaletizadoScreen muestra Modo de Paletizado Directo y NO renderiza lista masiva', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PaletizadoScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Paletizado y Enriquecimiento'), findsOneWidget);
      expect(find.text('Buscar N° Ingreso...'), findsOneWidget);
      expect(find.text('Modo de Paletizado Directo'), findsOneWidget);

      // Verificar que NO existe la lista previa ni el texto que antes mostraba las piezas
      expect(find.textContaining('Piezas Disponibles para Paletizar'), findsNothing);
      expect(find.byKey(const Key('item_pendiente_paletizado_0')), findsNothing);
    });

    testWidgets('PaletizadoScreen precarga automáticamente con numeroIngresoInicial', (tester) async {
      final mockService = MockPaletizadoService(
        onConsultarIngreso: (folio) async => ConsultaIngresoResult.success({
          'numero_ingreso': folio,
          'pendiente_paletizado': true,
          'vehiculo': {'marca': 'Mazda', 'modelo': '3', 'anio': 2019},
          'motor': {'id_estado': 5, 'numero_motor': 'SKYACTIV-G', 'pendiente': true},
          'caja_cambios': {'id_estado': 5, 'pendiente': true},
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PaletizadoScreen(
            numeroIngresoInicial: '7001',
            paletizadoService: mockService,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // Formulario debe estar abierto con los datos del vehículo cargado
      expect(find.text('VEHÍCULO ORIGEN'), findsOneWidget);
      expect(find.text('Mazda 3'), findsOneWidget);
      expect(find.text('Año: 2019'), findsOneWidget);
      expect(find.text('Datos del Activo a Paletizar'), findsOneWidget);
    });
  });
}
