// test/inventario_paletizado_optimizaciones_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/ventas/models/catalogo_model.dart';
import 'package:frontend/features/ventas/presentation/widgets/catalogo_item_card.dart';
import 'package:frontend/features/ventas/presentation/screens/detalle_activo_screen.dart';
import 'package:frontend/features/ventas/presentation/widgets/orden_card.dart';
import 'package:frontend/features/ventas/services/ordenes_service.dart';
import 'package:frontend/features/inventario/presentation/screens/buscador_screen.dart';
import 'package:frontend/features/paletizado/presentation/screens/paletizado_screen.dart';

void main() {
  group('CatalogoItem Model & Multimedia_Activo Images Tests', () {
    test('CatalogoItem.fromJson parsea adecuadamente arreglo de URLs de imagenes', () {
      final json = {
        'id_activo': '3cdbbf67-2df3-428e-861d-6d6f529a3dea',
        'sku_qr_fisico': 'MOT-2026-001',
        'precio_referencia': 850000,
        'id_categoria': 1,
        'nombre_categoria': 'Motores',
        'id_sucursal_actual': 1,
        'nombre_sucursal': 'Viña del Mar',
        'marca': 'Toyota',
        'modelo': 'Yaris',
        'anio': 2018,
        'ubicacion_pasillo': 'A1',
        'ubicacion_pallet': 'P-04',
        'estado_activo': 'Disponible',
        'imagenes': [
          'https://storage.cresal.cl/motor1.jpg',
          'https://storage.cresal.cl/motor2.jpg',
        ],
      };

      final item = CatalogoItem.fromJson(json);

      expect(item.idActivo, '3cdbbf67-2df3-428e-861d-6d6f529a3dea');
      expect(item.skuQrFisico, 'MOT-2026-001');
      expect(item.imagenes.length, 2);
      expect(item.imagenes.first, 'https://storage.cresal.cl/motor1.jpg');
      expect(item.precioFormateado, '\$850.000');
    });

    test('CatalogoItem.fromJson tolera arreglo de imagenes nulo o vacio', () {
      final json = {
        'id_activo': '3cdbbf67-2df3-428e-861d-6d6f529a3dea',
        'sku_qr_fisico': 'CAJ-2026-002',
        'id_categoria': 2,
        'nombre_categoria': 'Cajas de Cambio',
        'id_sucursal_actual': 2,
        'nombre_sucursal': 'Limache',
      };

      final item = CatalogoItem.fromJson(json);
      expect(item.imagenes, isEmpty);
    });
  });

  group('CatalogoItemCard Widget Tests with Images', () {
    testWidgets('Renderiza tarjeta con datos clave y SKU fisico', (tester) async {
      const item = CatalogoItem(
        idActivo: 'act-1',
        skuQrFisico: 'MOT-YAR-001',
        idCategoria: 1,
        nombreCategoria: 'Motores',
        idSucursalActual: 1,
        nombreSucursal: 'Viña del Mar',
        marca: 'Toyota',
        modelo: 'Yaris',
        anio: 2020,
        precioReferencia: 750000,
        imagenes: ['https://storage.cresal.cl/foto.jpg'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CatalogoItemCard(
              item: item,
              onAddToCart: () {},
            ),
          ),
        ),
      );

      expect(find.text('Viña'), findsOneWidget);
      expect(find.text('SKU: MOT-YAR-001'), findsNothing);
      expect(find.text('Motores - Toyota Yaris 2020'), findsOneWidget);
      expect(find.text('\$750.000'), findsOneWidget);
    });
  });

  group('DetalleActivoScreen Widget Tests', () {
    testWidgets('Renderiza galeria de imagenes, especificaciones y boton de carrito', (tester) async {
      const item = CatalogoItem(
        idActivo: 'act-2',
        skuQrFisico: 'CAJ-COR-002',
        idCategoria: 2,
        nombreCategoria: 'Cajas de Cambio',
        idSucursalActual: 2,
        nombreSucursal: 'Limache',
        marca: 'Toyota',
        modelo: 'Corolla',
        anio: 2021,
        transmisionTipo: 'Manual 6 Vel',
        ubicacionGalpon: 'G1',
        ubicacionPasillo: 'B2',
        ubicacionPallet: 'P-10',
        precioReferencia: 620000,
        imagenes: [
          'https://storage.cresal.cl/caja1.jpg',
          'https://storage.cresal.cl/caja2.jpg',
        ],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: DetalleActivoScreen(item: item),
        ),
      );

      expect(find.text('Detalle del Repuesto'), findsOneWidget);
      expect(find.text('SKU: CAJ-COR-002'), findsOneWidget);
      expect(find.text('\$620.000'), findsOneWidget);
      expect(find.text('Galpón'), findsOneWidget);
      expect(find.text('G1'), findsOneWidget);
      expect(find.text('Pasillo'), findsOneWidget);
      expect(find.text('B2'), findsOneWidget);
      expect(find.text('Pallet'), findsOneWidget);
      expect(find.text('P-10'), findsOneWidget);
      expect(find.text('Agregar'), findsOneWidget);
    });
  });

  group('BuscadorScreen (Bodega) Widget Tests', () {
    testWidgets('Renderiza AppBar, barra de busqueda y boton compacto de filtros', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BuscadorScreen(),
        ),
      );

      expect(find.text('INVENTARIO DE BODEGA'), findsOneWidget);
      expect(find.byKey(const Key('input_busqueda_inventario')), findsOneWidget);
      expect(find.byKey(const Key('btn_abrir_filtros_bodega')), findsOneWidget);
      expect(find.text('Buscar por marca, modelo o SKU...'), findsOneWidget);
    });

    testWidgets('Tap en boton de filtros abre ModalBottomSheet con selectores avanzados', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BuscadorScreen(),
        ),
      );

      await tester.tap(find.byKey(const Key('btn_abrir_filtros_bodega')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Filtros de Inventario'), findsOneWidget);
      expect(find.text('CATEGORÍA DE INVENTARIO'), findsOneWidget);
      expect(find.text('PASILLO'), findsOneWidget);
      expect(find.text('PALLET'), findsOneWidget);
      expect(find.text('MARCA'), findsOneWidget);
      expect(find.text('MODELO'), findsOneWidget);
    });
  });

  group('PaletizadoScreen Widget Tests', () {
    testWidgets('Renderiza buscador por Folio y vista de piezas pendientes / empty state', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PaletizadoScreen(),
        ),
      );

      expect(find.text('Paletizado y Enriquecimiento'), findsOneWidget);
      expect(find.text('Buscar N° Ingreso...'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });
  });

  group('Ajustes UI/UX: OrdenCard Overflow & Venta Anonima Tests', () {
    testWidgets('OrdenCard renderiza folio largo sin provocar RenderFlex overflow', (tester) async {
      final ordenLarga = OrdenHistorialModel(
        idOrden: 'ord-long-1234567890-abcdef',
        qrTransaccionalSalida: 'ORD-MUY-LARGA-123456789-VINA',
        estadoOrden: 'Reservada',
        totalVenta: 1500000,
        montoPendiente: 0,
        fechaCreacion: '2026-08-14T10:30:00',
        totalItems: 3,
        detalles: const [],
        cliente: const ClienteOrdenResumenModel(
          rutCliente: '12.345.678-9',
          nombres: 'Esteban',
          apellidos: 'Trabajos Largos',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320, // Pantalla estrecha
              child: OrdenCard(orden: ordenLarga),
            ),
          ),
        ),
      );

      expect(find.text('ORD-MUY-LARGA-123456789-VINA'), findsOneWidget);
      expect(find.text('Reservada'), findsOneWidget);
    });
  });
}
