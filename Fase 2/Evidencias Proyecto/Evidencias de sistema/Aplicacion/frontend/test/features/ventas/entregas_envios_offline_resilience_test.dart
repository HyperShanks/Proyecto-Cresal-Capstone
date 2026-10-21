import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/features/ventas/services/ordenes_service.dart';
import 'package:frontend/features/ventas/services/entregas_envios_storage_service.dart';
import 'package:frontend/features/ventas/services/entregas_envios_sync_service.dart';
import 'package:frontend/features/ventas/presentation/screens/entregas_envios_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockOrdenesJson = [
    {
      'id_orden': '11111111-aaaa-bbbb-cccc-111111111111',
      'folio': 'ORD-PATIO-001',
      'tipo_entrega': 'Retiro',
      'estado_orden': 'Pagada',
      'total_venta': 120000,
      'monto_pendiente': 0,
      'qr_transaccional_salida': 'ORD-PATIO-001',
      'fecha_creacion': '2026-10-08T10:00:00',
      'total_items': 1,
      'cliente': {
        'rut_cliente': '11.111.111-1',
        'nombres': 'Operario',
        'apellidos': 'Patio',
        'telefono': '+56911112222',
      },
      'despacho': null,
      'vendedor_nombre': 'Vendedor Central',
      'detalles': [
        {
          'id_detalle': 'det-001',
          'id_activo': null,
          'titulo': 'Pastillas de Freno Delanteras',
          'descripcion_manual': 'Pastillas de Freno',
          'cantidad': 1,
          'precio_final': 120000,
          'subtotal': 120000,
          'es_inventariado': false,
          'preparacion_lista': true,
          'estado_preparacion': 'Listo',
        }
      ],
      'preparacion_lista': true,
      'todos_preparados': true,
    },
    {
      'id_orden': '22222222-aaaa-bbbb-cccc-222222222222',
      'folio': 'ORD-PATIO-002',
      'tipo_entrega': 'Despacho',
      'estado_orden': 'Pagada',
      'total_venta': 450000,
      'monto_pendiente': 0,
      'qr_transaccional_salida': 'ORD-PATIO-002',
      'fecha_creacion': '2026-10-08T11:00:00',
      'total_items': 1,
      'cliente': {
        'rut_cliente': '22.222.222-2',
        'nombres': 'Transportes',
        'apellidos': 'Starken',
        'telefono': '+56933334444',
      },
      'despacho': {
        'id_despacho': 'desp-patio-002',
        'direccion_envio': 'Bodega Andén 4',
        'receptor_nombres': 'Conductor Starken',
        'receptor_rut': '22.222.222-2',
        'receptor_telefono': '+56933334444',
        'empresa_transporte': 'Starken',
        'costo_envio': 8000,
        'estado_despacho': 'Por Enviar',
        'comuna_destino': 'Valparaíso',
        'numero_seguimiento': 'OT-778899',
      },
      'vendedor_nombre': 'Vendedor Central',
      'detalles': [
        {
          'id_detalle': 'det-002',
          'id_activo': 'act-002',
          'titulo': 'Capó Frontal Toyota Hilux',
          'sku_qr_fisico': 'CAP-002',
          'cantidad': 1,
          'precio_final': 450000,
          'subtotal': 450000,
          'es_inventariado': true,
          'preparacion_lista': true,
          'estado_preparacion': 'Listo',
        }
      ],
      'preparacion_lista': true,
      'todos_preparados': true,
    }
  ];

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'mock-token-patio',
      'id_sucursal': '1',
      'user_id_rol': '2',
      'user_rol': 'Bodeguero Patio',
      'user_nombre': 'Operario Mesón',
    });
  });

  group('Criterio 1 & 2: Caché Local Stale-While-Revalidate y Apertura Inmediata', () {
    test('EntregasEnviosStorageService persiste y recupera lista de órdenes correctamente', () async {
      final storage = EntregasEnviosStorageService();
      await storage.limpiarCache();

      final ordenes = mockOrdenesJson.map((j) => EntregaEnvioModel.fromJson(j)).toList();
      await storage.guardarCache(ordenes);

      final recuperadas = await storage.cargarCache();
      expect(recuperadas.length, 2);
      expect(recuperadas[0].folioDisplay, 'ORD-PATIO-001');
      expect(recuperadas[1].folioDisplay, 'ORD-PATIO-002');
      expect(recuperadas[1].despacho?.empresaTransporte, 'Starken');
      expect(recuperadas[1].despacho?.numeroSeguimiento, 'OT-778899');
    });

    test('EntregasEnviosSyncService devuelve caché local cuando ocurre microcorte de red', () async {
      final storage = EntregasEnviosStorageService();
      final ordenes = mockOrdenesJson.map((j) => EntregaEnvioModel.fromJson(j)).toList();
      await storage.guardarCache(ordenes);

      // Cliente con corte de red en patio (503 Service Unavailable / Timeout)
      final clientCaido = MockClient((request) async {
        return http.Response('Service Unavailable: Red débil en patio', 503);
      });

      final syncService = EntregasEnviosSyncService(
        storageService: storage,
        client: clientCaido,
      );

      // Debe recurrir a caché local sin explotar
      final resultado = await syncService.sincronizarEntregas(soloActivas: true);
      expect(resultado.length, 2);
      expect(resultado[0].folioDisplay, 'ORD-PATIO-001');
      expect(syncService.statusNotifier.value.esInestable, isTrue);

      syncService.dispose();
    });
  });

  group('Criterio 3: Tolerancia a Microcortes con Reintentos Automáticos', () {
    test('sincronizarEntregas reintenta silenciosamente ante fallo transitorio y triunfa', () async {
      final storage = EntregasEnviosStorageService();
      int intentos = 0;

      final clientIntermitente = MockClient((request) async {
        intentos++;
        if (intentos == 1) {
          // Microcorte en el primer intento
          return http.Response('Connection reset by peer', 502);
        }
        // Éxito en el segundo intento
        return http.Response(
          jsonEncode(mockOrdenesJson),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final syncService = EntregasEnviosSyncService(
        storageService: storage,
        client: clientIntermitente,
      );

      final resultado = await syncService.sincronizarEntregas(soloActivas: true);
      expect(intentos, 2);
      expect(resultado.length, 2);
      expect(syncService.statusNotifier.value.estaAlDia, isTrue);

      syncService.dispose();
    });
  });

  group('Criterio 4: Registro Seguro con Cola Outbox e Idempotencia', () {
    test('ejecutarAccionConCola encola la acción si no hay red y se procesa al reconectar', () async {
      final storage = EntregasEnviosStorageService();
      await storage.limpiarCola();

      bool conRed = false;

      final clientFlexible = MockClient((request) async {
        if (!conRed) {
          return http.Response('Network unreachable', 503);
        }
        return http.Response(
          jsonEncode({'mensaje': 'Entrega confirmada con éxito'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final syncService = EntregasEnviosSyncService(
        storageService: storage,
        client: clientFlexible,
      );

      final accion = AccionEntregaEnvio(
        idAccion: 'acc-offline-01',
        tipo: 'confirmar_entrega',
        idOrden: '11111111-aaaa-bbbb-cccc-111111111111',
        fecha: DateTime.now().toIso8601String(),
      );

      // 1. Intento sin red: debe encolarse
      final exitoInmediato = await syncService.ejecutarAccionConCola(accion);
      expect(exitoInmediato, isFalse);

      final pendientes = await storage.obtenerAccionesPendientes();
      expect(pendientes.length, 1);
      expect(pendientes.first.idAccion, 'acc-offline-01');
      expect(syncService.colaPendienteCount, 1);

      // 2. Se restablece la señal en patio
      conRed = true;
      await syncService.procesarColaPendiente();

      final despuesDeReconectar = await storage.obtenerAccionesPendientes();
      expect(despuesDeReconectar.isEmpty, isTrue);
      expect(syncService.statusNotifier.value.estaAlDia, isTrue);

      syncService.dispose();
    });

    test('Idempotencia: si la orden ya fue completada previamente, no genera error ni duplicidad', () async {
      final storage = EntregasEnviosStorageService();
      await storage.limpiarCola();

      final clientYaEntregada = MockClient((request) async {
        // Simula backend que responde que ya estaba entregada (o 200 con mensaje)
        return http.Response(
          jsonEncode({'mensaje': 'La orden ya fue entregada previamente'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final syncService = EntregasEnviosSyncService(
        storageService: storage,
        client: clientYaEntregada,
      );

      final accion = AccionEntregaEnvio(
        idAccion: 'acc-idempotente-01',
        tipo: 'confirmar_entrega',
        idOrden: '11111111-aaaa-bbbb-cccc-111111111111',
        fecha: DateTime.now().toIso8601String(),
      );

      final exito = await syncService.ejecutarAccionConCola(accion);
      expect(exito, isTrue);

      final restantes = await storage.obtenerAccionesPendientes();
      expect(restantes.isEmpty, isTrue);

      syncService.dispose();
    });
  });

  group('Criterio 5 & UI: Feedback de Red No Invasivo y Despacho Optimista', () {
    testWidgets('UI muestra banner no invasivo cuando la red es inestable sin bloquear operario', (tester) async {
      final storage = EntregasEnviosStorageService();
      final ordenes = mockOrdenesJson.map((j) => EntregaEnvioModel.fromJson(j)).toList();
      await storage.guardarCache(ordenes);

      final syncService = EntregasEnviosSyncService(
        storageService: storage,
        client: MockClient((_) async => http.Response('OK', 200)),
      );

      // Forzamos estado inestable
      syncService.statusNotifier.value = const SyncStatus(
        state: SyncStatusState.conexionInestable,
        mensaje: 'Conexión intermitente en patio · Reintentando...',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: EntregasEnviosScreen(
            initialEntregas: ordenes,
            syncService: syncService,
          ),
        ),
      );

      expect(find.byKey(const Key('sync_status_banner')), findsOneWidget);
      expect(find.textContaining('Conexión intermitente'), findsOneWidget);
      // El operario aún puede ver la lista normalmente
      expect(find.text('ORD-PATIO-001'), findsOneWidget);
      expect(find.text('ORD-PATIO-002'), findsOneWidget);

      syncService.dispose();
    });

    testWidgets('Al confirmar entrega física, la orden desaparece de inmediato de forma optimista', (tester) async {
      final storage = EntregasEnviosStorageService();
      final ordenes = mockOrdenesJson.map((j) => EntregaEnvioModel.fromJson(j)).toList();

      final listaServidor = List<Map<String, dynamic>>.from(mockOrdenesJson);

      final mockClient = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode(listaServidor),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.method == 'PATCH') {
          listaServidor.removeWhere((o) => o['id_orden'] == '11111111-aaaa-bbbb-cccc-111111111111');
          return http.Response(
            jsonEncode({'mensaje': 'Entrega exitosa'}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final syncService = EntregasEnviosSyncService(
        storageService: storage,
        client: mockClient,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: EntregasEnviosScreen(
            initialEntregas: ordenes,
            syncService: syncService,
          ),
        ),
      );

      expect(find.text('ORD-PATIO-001'), findsOneWidget);

      // Tocar botón 'Entregado' en la tarjeta de ORD-PATIO-001
      final btnEntregado = find.widgetWithText(ElevatedButton, 'Entregado');
      expect(btnEntregado, findsOneWidget);
      await tester.tap(btnEntregado);
      await tester.pumpAndSettle();

      // Diálogo de confirmación
      expect(find.text('Confirmar Entrega'), findsOneWidget);
      await tester.tap(find.text('CONFIRMAR ENTREGA'));
      await tester.pumpAndSettle();

      // Desaparición inmediata optimista (sin bloqueos)
      expect(find.text('ORD-PATIO-001'), findsNothing);
      expect(find.textContaining('¡Orden #ORD-PATIO-001 entregada!'), findsOneWidget);

      syncService.dispose();
    });
  });
}
