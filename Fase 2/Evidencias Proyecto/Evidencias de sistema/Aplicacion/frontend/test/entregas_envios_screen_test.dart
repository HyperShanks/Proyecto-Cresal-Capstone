import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/features/ventas/services/ordenes_service.dart';
import 'package:frontend/features/ventas/services/ordenes_sync_notifier.dart';
import 'package:frontend/features/ventas/presentation/screens/entregas_envios_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({
    'access_token': 'mock-jwt-token',
    'id_sucursal': '1',
  });

  group('Módulo Entregas y Envíos - Service & Presentation Tests', () {
    final mockEntregasJson = [
      {
        'id_orden': '11111111-1111-1111-1111-111111111111',
        'folio': 'ORD-RET-001',
        'tipo_entrega': 'Retiro',
        'estado_orden': 'Pagada',
        'total_venta': 150000,
        'monto_pendiente': 0,
        'qr_transaccional_salida': 'ORD-RET-001',
        'fecha_creacion': '2026-08-17T12:00:00',
        'total_items': 1,
        'cliente': {
          'rut_cliente': '12.345.678-9',
          'nombres': 'Roberto',
          'apellidos': 'Retiro',
          'telefono': '+56912345678',
        },
        'despacho': null,
        'vendedor_nombre': 'Gastón Zamora',
        'detalles': [
          {
            'id_detalle': 'd1111111-1111-1111-1111-111111111111',
            'id_activo': null,
            'titulo': 'Filtro de Aceite Misceláneo',
            'descripcion_manual': 'Filtro de Aceite Misceláneo',
            'cantidad': 1,
            'precio_final': 150000,
            'subtotal': 150000,
            'es_inventariado': false,
            'preparacion_lista': true,
            'estado_preparacion': 'Listo',
          }
        ],
        'preparacion_lista': true,
        'todos_preparados': true,
      },
      {
        'id_orden': '22222222-2222-2222-2222-222222222222',
        'folio': 'ORD-DESP-002',
        'tipo_entrega': 'Despacho',
        'estado_orden': 'Pagada',
        'total_venta': 300000,
        'monto_pendiente': 0,
        'qr_transaccional_salida': 'ORD-DESP-002',
        'fecha_creacion': '2026-08-17T14:00:00',
        'total_items': 1,
        'cliente': {
          'rut_cliente': '15.999.888-7',
          'nombres': 'Daniela',
          'apellidos': 'Despacho',
          'telefono': '+56987654321',
        },
        'despacho': {
          'id_despacho': 'dd222222-2222-2222-2222-222222222222',
          'direccion_envio': 'Av. Libertad 500',
          'receptor_nombres': 'Daniela Despacho',
          'receptor_rut': '15.999.888-7',
          'receptor_telefono': '+56987654321',
          'empresa_transporte': 'Chilexpress',
          'costo_envio': 5000,
          'estado_despacho': 'Por Enviar',
          'comuna_destino': 'Viña del Mar',
        },
        'vendedor_nombre': 'Gastón Zamora',
        'detalles': [
          {
            'id_detalle': 'd2222222-2222-2222-2222-222222222222',
            'id_activo': 'a2222222-2222-2222-2222-222222222222',
            'titulo': 'Kit de Distribución - Toyota Yaris 2018',
            'sku_qr_fisico': 'KIT-002',
            'cantidad': 1,
            'precio_final': 300000,
            'subtotal': 300000,
            'es_inventariado': true,
            'preparacion_lista': true,
            'estado_preparacion': 'Listo',
          }
        ],
        'preparacion_lista': true,
        'todos_preparados': true,
      }
    ];

    test('obtenerEntregasEnvios realiza GET y parsea correctamente Retiro y Despacho', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/api/v1/ordenes/entregas-envios'));
        return http.Response(
          jsonEncode(mockEntregasJson),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final items = await OrdenesService.obtenerEntregasEnvios(client: mockClient);
      expect(items.length, 2);
      expect(items[0].tipoEntrega, 'Retiro');
      expect(items[0].folioDisplay, 'ORD-RET-001');
      expect(items[0].estaPagada, true);
      expect(items[0].vendedorNombre, 'Gastón Zamora');
      expect(items[0].detalles[0].esInventariado, false);

      expect(items[1].tipoEntrega, 'Despacho');
      expect(items[1].vendedorNombre, 'Gastón Zamora');
      expect(items[1].despacho?.empresaTransporte, 'Chilexpress');
    });

    test('confirmarEntregaTienda realiza PATCH exitoso', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/api/v1/ordenes/11111111-1111-1111-1111-111111111111/entregar'));
        expect(request.method, 'PATCH');
        return http.Response(
          jsonEncode({
            'id_orden': '11111111-1111-1111-1111-111111111111',
            'folio': 'ORD-RET-001',
            'estado_orden': 'Completada',
            'mensaje': 'Entrega confirmada',
            'activos_finalizados': 1,
            'fecha_entrega': '2026-08-17T12:30:00',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final ok = await OrdenesService.confirmarEntregaTienda(
        '11111111-1111-1111-1111-111111111111',
        client: mockClient,
      );
      expect(ok, true);
    });

    test('marcarDespachoEnviado realiza PATCH exitoso', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/api/v1/despachos/dd222222-2222-2222-2222-222222222222/enviar'));
        expect(request.method, 'PATCH');
        return http.Response(
          jsonEncode({
            'id_despacho': 'dd222222-2222-2222-2222-222222222222',
            'id_orden': '22222222-2222-2222-2222-222222222222',
            'folio': 'ORD-DESP-002',
            'estado_despacho': 'Enviado',
            'estado_orden': 'Despachada',
            'mensaje': 'Despacho enviado',
            'activos_finalizados': 1,
            'fecha_envio': '2026-08-17T14:30:00',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final ok = await OrdenesService.marcarDespachoEnviado(
        'dd222222-2222-2222-2222-222222222222',
        client: mockClient,
      );
      expect(ok, true);
    });

    test('obtenerVendedores realiza GET y parsea lista de vendedores', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('/api/v1/ordenes/vendedores'));
        return http.Response(
          jsonEncode([
            {
              'id_usuario': '11111111-1111-1111-1111-111111111111',
              'nombre_completo': 'Gastón Zamora',
              'rut': '11.111.111-1',
              'id_sucursal': 1,
              'correo': 'gaston@cresal.cl',
            }
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final vends = await OrdenesService.obtenerVendedores(client: mockClient);
      expect(vends.length, 1);
      expect(vends[0].nombreCompleto, 'Gastón Zamora');
      expect(vends[0].rut, '11.111.111-1');
    });

    test('EntregaEnvioModel detecta cliente anónimo y formatea Orden: #FOLIO', () {
      const ordenAnonima = EntregaEnvioModel(
        idOrden: '33333333-3333-3333-3333-333333333333',
        folio: 'ORD-99581A91',
        tipoEntrega: 'Retiro',
        estadoOrden: 'Pagada',
        totalVenta: 100000,
        montoPendiente: 0,
        totalItems: 1,
        cliente: ClienteOrdenResumenModel(
          rutCliente: '6.666.666-6',
          nombres: 'Consumidor',
          apellidos: 'Final',
        ),
        detalles: [],
        preparacionLista: true,
        todosPreparados: true,
      );

      expect(ordenAnonima.esConsumidorFinal, true);
      expect(ordenAnonima.clienteDisplay, 'Orden: #ORD-99581A91');

      const ordenNominativa = EntregaEnvioModel(
        idOrden: '44444444-4444-4444-4444-444444444444',
        folio: 'ORD-44444444',
        tipoEntrega: 'Retiro',
        estadoOrden: 'Pagada',
        totalVenta: 200000,
        montoPendiente: 0,
        totalItems: 1,
        cliente: ClienteOrdenResumenModel(
          rutCliente: '18.123.456-7',
          nombres: 'Felipe',
          apellidos: 'Dávila',
        ),
        detalles: [],
        preparacionLista: true,
        todosPreparados: true,
      );

      expect(ordenNominativa.esConsumidorFinal, false);
      expect(ordenNominativa.clienteDisplay, 'Felipe Dávila');
    });

    testWidgets('EntregasEnviosScreen renderiza vista unificada Retiro y Envíos y botón de filtros sin pestaña courier', (tester) async {
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '2');

      await tester.pumpWidget(
        const MaterialApp(
          home: EntregasEnviosScreen(),
        ),
      );

      // Debe mostrar el título unificado 'Retiro y Envíos' y los botones de acción
      expect(find.text('Retiro y Envíos'), findsOneWidget);
      // El apartado de despachos courier desapareció por completo (no hay pestañas separadas)
      expect(find.text('Retiros en Tienda'), findsNothing);
      expect(find.text('Despachos (Courier)'), findsNothing);
      expect(find.byIcon(Icons.tune_outlined), findsOneWidget);
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    });

    testWidgets('VendedorOnline (id_rol == 7) es bloqueado al entrar a EntregasEnviosScreen', (tester) async {
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '7');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Vendedor Online');

      await tester.pumpWidget(
        MaterialApp(
          home: const Scaffold(body: Text('HOME_ROOT')),
          routes: {
            '/entregas-envios': (context) => const EntregasEnviosScreen(),
          },
        ),
      );

      // Navegar a entregas
      final navKey = tester.state<NavigatorState>(find.byType(Navigator));
      navKey.pushNamed('/entregas-envios');
      await tester.pumpAndSettle();

      // Debe haber cerrado la pantalla y mostrado el SnackBar de acceso restringido
      expect(find.text('Acceso restringido: Las entregas presenciales son gestionadas por el equipo de sucursal.'), findsOneWidget);
      expect(find.text('HOME_ROOT'), findsOneWidget);
    });

    test('OrdenesSyncNotifier emite notificaciones a suscriptores', () {
      bool notificado = false;
      void listener() {
        notificado = true;
      }

      OrdenesSyncNotifier.instance.addListener(listener);
      expect(notificado, false);

      OrdenesSyncNotifier.instance.notificarCambio();
      expect(notificado, true);

      OrdenesSyncNotifier.instance.removeListener(listener);
    });

    testWidgets('Cards de Entregas y Envíos renderizan vista unificada sin desbordamiento', (tester) async {
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '2');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Vendedor');

      // Instanciar pantalla y verificar que no haya overflow
      await tester.pumpWidget(
        const MaterialApp(
          home: EntregasEnviosScreen(),
        ),
      );
      await tester.pump();

      expect(find.text('Retiro y Envíos'), findsOneWidget);
    });

    test('Orden de despacho incluye datos de despacho y QR transaccional para barrera de salida', () {
      final ordenDespacho = EntregaEnvioModel.fromJson(mockEntregasJson[1]);
      expect(ordenDespacho.esDespacho, true);
      expect(ordenDespacho.despacho?.empresaTransporte, 'Chilexpress');
      expect(ordenDespacho.despacho?.direccionEnvio, 'Av. Libertad 500');
      expect(ordenDespacho.tieneQrDisponible, true);
      expect(ordenDespacho.qrTransaccionalSalida, 'ORD-DESP-002');
    });

    test('EntregaEnvioModel.contieneMotorOCaja identifica con precisión motores y cajas vs repuestos menores', () {
      final ordenCaja = EntregaEnvioModel(
        idOrden: 'c1111111-1111-1111-1111-111111111111',
        folio: 'ORD-D1775AB0',
        tipoEntrega: 'Retiro',
        estadoOrden: 'Reservada',
        totalVenta: 1680000,
        montoPendiente: 1000000,
        totalItems: 1,
        detalles: [
          DetalleOrdenItemModel(
            idDetalle: 'd1',
            titulo: 'Caja de Cambios - DODGE RAM QUAD CAB 4X4 5.9 2008',
            cantidad: 1,
            precioFinal: 1680000,
            subtotal: 1680000,
            esInventariado: true,
          ),
        ],
        preparacionLista: true,
        todosPreparados: true,
      );

      final ordenMotor = EntregaEnvioModel(
        idOrden: 'm1111111-1111-1111-1111-111111111111',
        folio: 'ORD-191D3011',
        tipoEntrega: 'Retiro',
        estadoOrden: 'Pagada',
        totalVenta: 1200000,
        montoPendiente: 0,
        totalItems: 1,
        detalles: [
          DetalleOrdenItemModel(
            idDetalle: 'd2',
            titulo: '[RESERVA EN VERDE] Motor - Peugeot 206 (2022)',
            cantidad: 1,
            precioFinal: 1200000,
            subtotal: 1200000,
            esInventariado: false,
          ),
        ],
        preparacionLista: true,
        todosPreparados: true,
      );

      final ordenPerno = EntregaEnvioModel(
        idOrden: 'p1111111-1111-1111-1111-111111111111',
        folio: 'ORD-0742EC16',
        tipoEntrega: 'Retiro',
        estadoOrden: 'Pagada',
        totalVenta: 10000,
        montoPendiente: 0,
        totalItems: 1,
        detalles: [
          DetalleOrdenItemModel(
            idDetalle: 'd3',
            titulo: 'Perno',
            descripcionManual: 'Perno',
            cantidad: 1,
            precioFinal: 10000,
            subtotal: 10000,
            esInventariado: false,
          ),
        ],
        preparacionLista: true,
        todosPreparados: true,
      );

      final ordenPan = EntregaEnvioModel(
        idOrden: 'b1111111-1111-1111-1111-111111111111',
        folio: 'ORD-B41BB77D',
        tipoEntrega: 'Retiro',
        estadoOrden: 'Pagada',
        totalVenta: 5000,
        montoPendiente: 0,
        totalItems: 1,
        detalles: [
          DetalleOrdenItemModel(
            idDetalle: 'd4',
            titulo: 'pan',
            descripcionManual: 'pan',
            cantidad: 1,
            precioFinal: 5000,
            subtotal: 5000,
            esInventariado: false,
          ),
        ],
        preparacionLista: true,
        todosPreparados: true,
      );

      expect(ordenCaja.contieneMotorOCaja, true);
      expect(ordenMotor.contieneMotorOCaja, true);
      expect(ordenPerno.contieneMotorOCaja, false);
      expect(ordenPan.contieneMotorOCaja, false);
    });

    test('Buscador y filtros en Entregas y Envíos cubren RUT, Folio, Vendedor Asignado y Repuesto', () {
      final ordenOnline = EntregaEnvioModel(
        idOrden: 'ord-online-1',
        folio: 'ORD-9876ABCD',
        tipoEntrega: 'Retiro',
        estadoOrden: 'Pagada',
        totalVenta: 85000,
        montoPendiente: 0,
        totalItems: 1,
        cliente: const ClienteOrdenResumenModel(
          rutCliente: '19.876.543-2',
          nombres: 'Carlos',
          apellidos: 'Muñoz',
          telefono: '+56911223344',
        ),
        vendedorNombre: 'Vendedor Online Central',
        idVendedorAsignado: 'vend-fisico-123',
        vendedorAsignadoNombre: 'Pedro Mostrador',
        detalles: [
          DetalleOrdenItemModel(
            idDetalle: 'det-1',
            titulo: 'Alternador Bosch 12V',
            skuQrFisico: 'ALT-BOSCH-12',
            cantidad: 1,
            precioFinal: 85000,
            subtotal: 85000,
            esInventariado: true,
          ),
        ],
        preparacionLista: true,
        todosPreparados: true,
      );

      final ordenTienda = EntregaEnvioModel(
        idOrden: 'ord-tienda-2',
        folio: 'ORD-1234XYZW',
        tipoEntrega: 'Despacho',
        estadoOrden: 'Pagada',
        totalVenta: 120000,
        montoPendiente: 0,
        totalItems: 1,
        cliente: const ClienteOrdenResumenModel(
          rutCliente: '11.222.333-4',
          nombres: 'María',
          apellidos: 'González',
        ),
        despacho: const DespachoOrdenResumenModel(
          idDespacho: 'desp-1',
          direccionEnvio: 'Calle Falsa 123',
          receptorNombres: 'María González',
          receptorRut: '11.222.333-4',
          receptorTelefono: '+56988776655',
          estadoDespacho: 'Por Enviar',
          comunaDestino: 'Quilpué',
          empresaTransporte: 'Starken',
          costoEnvio: 4500,
        ),
        vendedorNombre: 'Juan Local',
        vendedorAsignadoNombre: null,
        detalles: [
          DetalleOrdenItemModel(
            idDetalle: 'det-2',
            titulo: 'Pastillas de Freno Delanteras',
            skuQrFisico: 'FREN-PAST-01',
            cantidad: 1,
            precioFinal: 120000,
            subtotal: 120000,
            esInventariado: true,
          ),
        ],
        preparacionLista: true,
        todosPreparados: true,
      );

      final lista = [ordenOnline, ordenTienda];

      // 1. Filtrar por Vendedor Asignado (Responsable físico)
      final filtroAsignado = lista.where((e) =>
          e.vendedorAsignadoNombre != null &&
          e.vendedorAsignadoNombre!.toLowerCase().contains('pedro')).toList();
      expect(filtroAsignado.length, 1);
      expect(filtroAsignado.first.folio, 'ORD-9876ABCD');

      // 2. Filtrar por Vendedor Creador (Online)
      final filtroCreador = lista.where((e) =>
          e.vendedorNombre != null &&
          e.vendedorNombre!.toLowerCase().contains('online central')).toList();
      expect(filtroCreador.length, 1);
      expect(filtroCreador.first.folio, 'ORD-9876ABCD');

      // 3. Filtrar por RUT sin puntos ni guión
      String normalizarRut(String r) => r.replaceAll('.', '').replaceAll('-', '').toLowerCase().trim();
      final qRut = normalizarRut('198765432');
      final filtroRut = lista.where((e) {
        final r = normalizarRut(e.cliente?.rutCliente ?? '');
        return r.contains(qRut);
      }).toList();
      expect(filtroRut.length, 1);
      expect(filtroRut.first.cliente?.nombres, 'Carlos');

      // 4. Filtrar por Folio
      final filtroFolio = lista.where((e) =>
          e.folio.toLowerCase().contains('xyzw')).toList();
      expect(filtroFolio.length, 1);
      expect(filtroFolio.first.folio, 'ORD-1234XYZW');

      // 5. Filtrar por SKU de Repuesto
      final filtroSku = lista.where((e) =>
          e.detalles.any((d) => d.skuQrFisico != null && d.skuQrFisico!.contains('ALT-BOSCH'))).toList();
      expect(filtroSku.length, 1);
      expect(filtroSku.first.folio, 'ORD-9876ABCD');

      // 6. Filtrar por Comuna de despacho
      final filtroComuna = lista.where((e) =>
          e.despacho?.comunaDestino?.toLowerCase().contains('quilpué') ?? false).toList();
      expect(filtroComuna.length, 1);
      expect(filtroComuna.first.folio, 'ORD-1234XYZW');
    });

    testWidgets('Buscador in-line y chips de filtros en EntregasEnviosScreen responden a diferentes pantallas sin pixel overflow', (tester) async {
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '2');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Vendedor');

      // 1. Pantalla móvil estrecha (360 x 700)
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: EntregasEnviosScreen(),
        ),
      );

      expect(find.text('Retiro y Envíos'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 2. Pantalla Desktop amplia (1280 x 800)
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();
      expect(find.text('Retiro y Envíos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Filtros predeterminados en Entregas y Envíos renderizan chips de Listas (Pagadas), Con Saldo y Todas', (tester) async {
      await const FlutterSecureStorage().write(key: 'user_id_rol', value: '6');
      await const FlutterSecureStorage().write(key: 'user_rol', value: 'Jefe de Ventas');

      final ordenDespacho = EntregaEnvioModel.fromJson(mockEntregasJson[1]);

      await tester.pumpWidget(
        MaterialApp(
          home: EntregasEnviosScreen(
            initialEntregas: [ordenDespacho],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chip_filtro_pagadas')), findsOneWidget);
      expect(find.byKey(const Key('chip_filtro_pendientes')), findsOneWidget);
      expect(find.byKey(const Key('chip_filtro_todas')), findsOneWidget);
      expect(find.byKey(const Key('chip_mis_asignadas')), findsOneWidget);

      // Al pulsar 'Todas', el chip responde sin errores
      await tester.tap(find.byKey(const Key('chip_filtro_todas')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
