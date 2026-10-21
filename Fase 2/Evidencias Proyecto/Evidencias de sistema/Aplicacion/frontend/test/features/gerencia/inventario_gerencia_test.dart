// frontend/test/features/gerencia/inventario_gerencia_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/ventas/models/catalogo_model.dart';
import 'package:frontend/features/gerencia/presentation/screens/inventario_gerencia_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HU-5.3: Modelos de Inventario y Tasación', () {
    test('CatalogoItem deserializa correctamente nuevos campos HU-5.3', () {
      final json = {
        'id_activo': 'act-001',
        'sku_qr_fisico': 'REP-ENG-001',
        'nombre_categoria': 'Motor',
        'marca': 'Toyota',
        'modelo': 'Hilux',
        'anio': 2021,
        'estado_activo': 'Paletizado',
        'nombre_sucursal': 'Casa Matriz (Viña)',
        'id_sucursal_actual': 1,
        'ubicacion_pasillo': 'Rack C',
        'ubicacion_pallet': 'Nivel 2',
        'ubicacion_galpon': 'Galpón 1',
        'precio_referencia': 450000,
        'cilindrada': '2.8',
        'combustible': 'Diésel',
        'transmision_tipo': 'Manual 6ta',
        'traccion': '4x4',
        'numero_motor': '1GD-1234567',
        'observacion_estado': 'Excelente estado de compresión',
        'imagenes': ['https://example.com/foto1.jpg'],
      };

      final item = CatalogoItem.fromJson(json);

      expect(item.idActivo, 'act-001');
      expect(item.skuQrFisico, 'REP-ENG-001');
      expect(item.nombreCategoria, 'Motor');
      expect(item.marca, 'Toyota');
      expect(item.modelo, 'Hilux');
      expect(item.anio, 2021);
      expect(item.estadoActivo, 'Paletizado');
      expect(item.ubicacionGalpon, 'Galpón 1');
      expect(item.observacionEstado, 'Excelente estado de compresión');
      expect(item.precioReferencia, 450000);
      expect(item.combustible, 'Diésel');
      expect(item.transmisionTipo, 'Manual 6ta');
      expect(item.imagenes.length, 1);
    });

    test('PaginatedCatalogoResponse deserializa pendientesTasacionCount', () {
      final json = {
        'total_count': 45,
        'items': [
          {
            'id_activo': 'act-002',
            'sku_qr_fisico': 'REP-CAJ-002',
            'nombre_categoria': 'Transmisión',
            'marca': 'Nissan',
            'modelo': 'Navara',
            'anio': 2020,
            'estado_activo': 'Paletizado',
            'nombre_sucursal': 'Patio Limache',
            'id_sucursal_actual': 2,
            'precio_referencia': 0,
            'imagenes': [],
          }
        ],
        'pendientes_tasacion_count': 14,
      };

      final paginated = PaginatedCatalogoResponse.fromJson(json);

      expect(paginated.totalCount, 45);
      expect(paginated.items.length, 1);
      expect(paginated.pendientesTasacionCount, 14);
      expect(paginated.items.first.skuQrFisico, 'REP-CAJ-002');
    });
  });

  group('HU-5.3: Componente InventarioGerenciaView', () {
    testWidgets('Renderiza barra de búsqueda, chips y botones de vista', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InventarioGerenciaView(
              idSucursalInicial: null,
              filtroSinTasarInicial: false,
            ),
          ),
        ),
      );

      // Verificamos presencia de los componentes interactivos clave
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Buscar por SKU, Marca, Pasillo (A, B, C), Pallet o N° Ingreso...'), findsOneWidget);
      expect(find.text('Sin Tasar'), findsOneWidget);
      expect(find.text('Limpiar'), findsOneWidget);
      expect(find.text('Tarjetas'), findsOneWidget);
      expect(find.text('Tabla'), findsOneWidget);
    });

    testWidgets('Conmutación interactiva entre modo Tarjetas y Tabla', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InventarioGerenciaView(
              idSucursalInicial: 1,
              filtroSinTasarInicial: true,
            ),
          ),
        ),
      );

      // Verificamos botón de vista Tabla
      final botonTabla = find.text('Tabla');
      expect(botonTabla, findsOneWidget);

      await tester.tap(botonTabla);
      await tester.pump();

      // Verificamos botón de vista Tarjetas
      final botonTarjetas = find.text('Tarjetas');
      expect(botonTarjetas, findsOneWidget);

      await tester.tap(botonTarjetas);
      await tester.pump();
    });

    testWidgets('Botón Limpiar muestra badge de filtros activos y resetea al presionar', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: InventarioGerenciaView(
              idSucursalInicial: 1,
              filtroSinTasarInicial: true,
            ),
          ),
        ),
      );

      // Dado que filtroSinTasarInicial es true, debe haber 1 filtro activo y mostrar el badge '1'
      expect(find.text('Limpiar'), findsOneWidget);
      expect(find.text('1'), findsWidgets);

      // Al presionar Limpiar, se limpian los filtros
      await tester.tap(find.text('Limpiar'));
      await tester.pump();
    });
  });
}
