import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/recepcion/models/vehiculo_recepcion_model.dart';
import 'package:frontend/routes/app_routes.dart';

void main() {
  group('SPEC-22: Recepción Model and RBAC Routing Tests', () {
    test('VehiculoRecepcionModel serializa 13 columnas y genera TSV para Excel', () {
      final json = {
        'id_vehiculo': 'b1c8f420-1a2b-4c3d-8e9f-0123456789ab',
        'numero_ingreso': '2695',
        'patente': 'CLTC67',
        'factura': 'FAC-1234',
        'fecha_ingreso': '2026-09-29',
        'origen': 'PARTICULAR',
        'marca': 'TOYOTA',
        'modelo': 'YARIS SPORT 1.5',
        'anio': 2018,
        'color': 'BLANCO',
        'numero_motor': '1NZ-FE-9921',
        'destino': 'DESARME',
        'grua': 'F. FANO',
        'observaciones': '+ Con Llave + Sin Documentos',
      };

      final modelo = VehiculoRecepcionModel.fromJson(json);

      expect(modelo.numeroIngreso, '2695');
      expect(modelo.patente, 'CLTC67');
      expect(modelo.esSppu, isFalse);
      expect(modelo.marca, 'TOYOTA');
      expect(modelo.destino, 'DESARME');
      expect(modelo.grua, 'F. FANO');

      final tsvRow = modelo.toTsvRow();
      expect(tsvRow, contains('2695\tCLTC67\tFAC-1234\t2026-09-29\tPARTICULAR\tTOYOTA'));
      expect(tsvRow.split('\t').length, 13);

      final headers = VehiculoRecepcionModel.tsvHeaders();
      expect(headers.split('\t').length, 13);
      expect(headers, contains('N° Ingreso\tPatente\tFactura\tFecha ingreso'));
      expect(modelo.fechaIngresoFormateada, '29/09/2026');
    });

    test('VehiculoRecepcionModel detecta correctamente SPPU', () {
      final jsonSppu = {
        'id_vehiculo': 'c2d3e4f5-0000-1111-2222-333344445555',
        'numero_ingreso': '2696',
        'patente': 'SPPU-2696',
        'marca': 'CHEVROLET',
        'modelo': 'SAIL',
      };

      final modeloSppu = VehiculoRecepcionModel.fromJson(jsonSppu);
      expect(modeloSppu.esSppu, isTrue);
    });

    test('AppRoutes redirige Rol 9 exclusivamente a /recepcion', () {
      // Rol 9 = Recepción
      final homeRoute = AppRoutes.getHomeRouteForRole(9);
      expect(homeRoute, AppRoutes.recepcion);
    });

    test('RBAC: Rol 9 tiene acceso exclusivo a recepción y tickets, bloqueado de bodega/caja/ventas', () {
      const int rolRecepcion = 9;

      // Rutas permitidas
      expect(AppRoutes.isRouteAllowedForRole(rolRecepcion, AppRoutes.recepcion), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(rolRecepcion, AppRoutes.recepcionRegistro), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(rolRecepcion, AppRoutes.tickets), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(rolRecepcion, AppRoutes.login), isTrue);

      // Rutas de bodega/WMS ESTRICTAMENTE BLOQUEADAS
      expect(AppRoutes.isRouteAllowedForRole(rolRecepcion, AppRoutes.home), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(rolRecepcion, AppRoutes.paletizado), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(rolRecepcion, AppRoutes.etiquetaPreview), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(rolRecepcion, AppRoutes.alertas), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(rolRecepcion, AppRoutes.buscador), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(rolRecepcion, AppRoutes.reingresos), isFalse);

      // Rutas de caja y ventas BLOQUEADAS
      expect(AppRoutes.isRouteAllowedForRole(rolRecepcion, AppRoutes.caja), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(rolRecepcion, AppRoutes.ventasMain), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(rolRecepcion, AppRoutes.catalogo), isFalse);
    });

    test('RBAC: Bodeguero (Rol 1) ya no tiene acceso a recepción de patio desvinculada', () {
      const int rolBodeguero = 1;
      expect(AppRoutes.isRouteAllowedForRole(rolBodeguero, AppRoutes.recepcion), isFalse);
      expect(AppRoutes.isRouteAllowedForRole(rolBodeguero, AppRoutes.recepcionRegistro), isFalse);

      // Mantiene acceso pleno a su WMS
      expect(AppRoutes.isRouteAllowedForRole(rolBodeguero, AppRoutes.home), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(rolBodeguero, AppRoutes.paletizado), isTrue);
      expect(AppRoutes.isRouteAllowedForRole(rolBodeguero, AppRoutes.alertas), isTrue);
    });
  });
}
