// test/features/ventas/galeria_tasacion_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/ventas/models/pendiente_precio_model.dart';
import 'package:frontend/features/ventas/presentation/widgets/galeria_activo_widget.dart';
import 'package:frontend/features/ventas/presentation/widgets/asignar_precio_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ActivoPendientePrecioModel - Soporte de Fotografías (SPEC-HU-TAREA-15)', () {
    test('Parsea lista de URLs de fotografías correctamente desde JSON', () {
      final json = {
        'id_activo': 'act-001',
        'sku_qr_fisico': 'SKU-001',
        'id_categoria': 1,
        'nombre_categoria': 'Motor',
        'id_sucursal_actual': 1,
        'nombre_sucursal': 'Casa Matriz',
        'titulo_repuesto': 'Motor 1.6L Gasolina',
        'estado_activo': 'En Desarme',
        'fotografias': [
          'https://cresal.s3.amazonaws.com/repuestos/foto1.jpg',
          'https://cresal.s3.amazonaws.com/repuestos/foto2.jpg',
        ],
      };

      final model = ActivoPendientePrecioModel.fromJson(json);

      expect(model.fotografias.length, equals(2));
      expect(model.fotografias.first, equals('https://cresal.s3.amazonaws.com/repuestos/foto1.jpg'));
      expect(model.fotografias.last, equals('https://cresal.s3.amazonaws.com/repuestos/foto2.jpg'));
    });

    test('Asigna lista vacía cuando el campo fotografias es nulo o ausente', () {
      final json = {
        'id_activo': 'act-002',
        'sku_qr_fisico': 'SKU-002',
        'id_categoria': 2,
        'nombre_categoria': 'Caja de Cambios',
        'id_sucursal_actual': 1,
        'nombre_sucursal': 'Casa Matriz',
        'titulo_repuesto': 'Caja Manual 5 Vel',
        'estado_activo': 'En Desarme',
      };

      final model = ActivoPendientePrecioModel.fromJson(json);

      expect(model.fotografias, isEmpty);
    });
  });

  group('GaleriaActivoWidget - Componente Visual de Tasación', () {
    testWidgets('Muestra mensaje de Empty State cuando no hay fotografías', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GaleriaActivoWidget(fotografias: []),
          ),
        ),
      );

      // Verificación de mensaje exigido por SPEC-HU-TAREA-15
      expect(find.text('Activo sin fotografías registradas.'), findsOneWidget);
      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    });

    testWidgets('Muestra indicador "1 fotografía" si contiene exactamente 1 foto', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: GaleriaActivoWidget(
              fotografias: ['https://example.com/foto1.jpg'],
            ),
          ),
        ),
      );

      expect(find.text('1 fotografía'), findsOneWidget);
      expect(find.text('Activo sin fotografías registradas.'), findsNothing);
      // No deben existir botones de navegación izquierda/derecha
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('Muestra "Foto 1 de 3" y flechas de navegación si hay múltiples imágenes', (tester) async {
      final fotos = [
        'https://example.com/foto1.jpg',
        'https://example.com/foto2.jpg',
        'https://example.com/foto3.jpg',
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GaleriaActivoWidget(fotografias: fotos),
          ),
        ),
      );

      expect(find.text('Foto 1 de 3'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsNothing); // Al inicio no hay chevron izquierdo
    });
  });

  group('AsignarPrecioDialog - Integración de Galería de Fotos', () {
    testWidgets('Renderiza la galería y el input de precio simultáneamente', (tester) async {
      const activo = ActivoPendientePrecioModel(
        idActivo: 'act-diag-1',
        skuQrFisico: 'SKU-DIAG-01',
        idCategoria: 1,
        nombreCategoria: 'Motor',
        idSucursalActual: 1,
        nombreSucursal: 'Casa Matriz',
        tituloRepuesto: 'Motor Test con Galería',
        estadoActivo: 'En Desarme',
        fotografias: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AsignarPrecioDialog(
              activo: activo,
              onPrecioAsignado: () {},
            ),
          ),
        ),
      );

      // Verifica presencia de encabezado
      expect(find.text('Fijar Precio de Referencia'), findsOneWidget);

      // Verifica presencia del Empty State de fotos
      expect(find.text('Activo sin fotografías registradas.'), findsOneWidget);

      // Verifica presencia del campo de precio (rango mínimo y máximo)
      expect(find.text('PRECIO MÍNIMO (PISO DE NEGOCIACIÓN CLP)'), findsOneWidget);
      expect(find.text('PRECIO MÁXIMO (PRECIO SUGERIDO / LISTA CLP)'), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(2));
    });
  });
}
