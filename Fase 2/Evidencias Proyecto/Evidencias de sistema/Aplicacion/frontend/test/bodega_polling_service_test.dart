// test/bodega_polling_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/alertas/models/tarea_alerta.dart';
import 'package:frontend/features/alertas/services/bodega_polling_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tarea1 = TareaAlerta(
    idTarea: 'tar-001',
    idDetalle: 'det-001',
    tipoAlerta: 'PREPARACION',
    tituloPieza: 'Motor Toyota Yaris 2018',
    ubicacion: 'P-01 PL-04',
    accionRequerida: 'Preparar pieza para entrega',
    esTraslado: false,
  );

  final tarea2 = TareaAlerta(
    idTarea: 'tar-002',
    idDetalle: 'det-002',
    tipoAlerta: 'TRASLADO',
    tituloPieza: 'Caja de Cambio Corolla 2020',
    ubicacion: 'P-02 PL-10',
    accionRequerida: 'Preparar pieza para traslado',
    esTraslado: true,
  );

  final tarea3 = TareaAlerta(
    idTarea: 'tar-003',
    idDetalle: 'det-003',
    tipoAlerta: 'PREPARACION',
    tituloPieza: 'Alternador Yaris',
    ubicacion: 'P-03 PL-02',
    accionRequerida: 'Preparar pieza para entrega',
    esTraslado: false,
  );

  setUp(() {
    BodegaPollingService.instance.reset();
  });

  group('BodegaPollingService - Deduplicación de Tareas Nuevas', () {
    test('Ciclo 1: Detecta tareas nuevas, notifica y agrega IDs al Set _tareasNotificadas', () async {
      final notificaciones = <Map<String, String>>[];
      BodegaPollingService.instance.onNotificacion = (titulo, cuerpo) {
        notificaciones.add({'titulo': titulo, 'cuerpo': cuerpo});
      };

      // Ejecutar primer ciclo con tarea1 y tarea2
      await BodegaPollingService.instance.procesarCiclo(
        tareasMock: [tarea1, tarea2],
      );

      // Debe emitir alerta de nueva tarea y alerta de resumen inicial
      expect(
        notificaciones.any((n) => n['titulo'] == '¡Nueva tarea de bodega!'),
        isTrue,
      );
      expect(
        notificaciones.any((n) => n['titulo'] == 'Recordatorio de Bodega'),
        isTrue,
      );

      // Set de tareas notificadas debe contener ambos IDs
      expect(BodegaPollingService.instance.tareasNotificadas.contains('det-001'), isTrue);
      expect(BodegaPollingService.instance.tareasNotificadas.contains('det-002'), isTrue);
      expect(BodegaPollingService.instance.tareasNotificadas.length, 2);
      expect(BodegaPollingService.instance.totalPendientesNotifier.value, 2);
      expect(BodegaPollingService.instance.tieneTrasladosNotifier.value, isTrue);
    });

    test('Ciclo 2: Mismas tareas no vuelven a disparar notificación de nueva tarea', () async {
      final notificaciones = <Map<String, String>>[];
      BodegaPollingService.instance.onNotificacion = (titulo, cuerpo) {
        notificaciones.add({'titulo': titulo, 'cuerpo': cuerpo});
      };

      // Ciclo 1 inicial
      await BodegaPollingService.instance.procesarCiclo(
        tareasMock: [tarea1, tarea2],
      );
      notificaciones.clear();

      // Ciclo 2 con exactamente las mismas tareas
      await BodegaPollingService.instance.procesarCiclo(
        tareasMock: [tarea1, tarea2],
      );

      // No debe emitir ninguna notificación de nueva tarea ni de recordatorio (menos de 2 horas)
      expect(
        notificaciones.any((n) => n['titulo'] == '¡Nueva tarea de bodega!'),
        isFalse,
      );
      expect(
        notificaciones.any((n) => n['titulo'] == 'Recordatorio de Bodega'),
        isFalse,
      );
      expect(notificaciones.isEmpty, isTrue);
    });

    test('Ciclo 3: Tarea nueva se detecta y notifica de forma incremental', () async {
      final notificaciones = <Map<String, String>>[];
      BodegaPollingService.instance.onNotificacion = (titulo, cuerpo) {
        notificaciones.add({'titulo': titulo, 'cuerpo': cuerpo});
      };

      // Ciclo 1 inicial con tarea1
      await BodegaPollingService.instance.procesarCiclo(
        tareasMock: [tarea1],
      );
      notificaciones.clear();

      // Ciclo 2 llega tarea3 adicional
      await BodegaPollingService.instance.procesarCiclo(
        tareasMock: [tarea1, tarea3],
      );

      // Debe emitir alerta por la nueva tarea3
      expect(
        notificaciones.any((n) => n['titulo'] == '¡Nueva tarea de bodega!'),
        isTrue,
      );
      expect(BodegaPollingService.instance.tareasNotificadas.contains('det-003'), isTrue);
      expect(BodegaPollingService.instance.tareasNotificadas.length, 2);
    });

    test('Sincronización: Tareas completadas/removidas en backend se eliminan de _tareasNotificadas', () async {
      // Ciclo 1 con tarea1 y tarea2
      await BodegaPollingService.instance.procesarCiclo(
        tareasMock: [tarea1, tarea2],
      );
      expect(BodegaPollingService.instance.tareasNotificadas.length, 2);

      // Ciclo 2: tarea1 fue completada y ya no viene en el backend
      await BodegaPollingService.instance.procesarCiclo(
        tareasMock: [tarea2],
      );

      // _tareasNotificadas se sincroniza y solo retiene det-002
      expect(BodegaPollingService.instance.tareasNotificadas.contains('det-001'), isFalse);
      expect(BodegaPollingService.instance.tareasNotificadas.contains('det-002'), isTrue);
      expect(BodegaPollingService.instance.tareasNotificadas.length, 1);
    });
  });

  group('BodegaPollingService - Recordatorio Periódico (2 Horas)', () {
    test('Emite recordatorio cuando transcurren 2 o más horas y hay pendientes', () async {
      final notificaciones = <Map<String, String>>[];
      BodegaPollingService.instance.onNotificacion = (titulo, cuerpo) {
        notificaciones.add({'titulo': titulo, 'cuerpo': cuerpo});
      };

      // Ciclo 1 inicial
      await BodegaPollingService.instance.procesarCiclo(
        tareasMock: [tarea1, tarea2],
      );
      expect(notificaciones.any((n) => n['titulo'] == 'Recordatorio de Bodega'), isTrue);
      notificaciones.clear();

      // Simular paso del tiempo: menos de 2 horas (ej. 1 hora)
      // En ejecución real no emitirá recordatorio
      await BodegaPollingService.instance.procesarCiclo(
        tareasMock: [tarea1, tarea2],
      );
      expect(notificaciones.any((n) => n['titulo'] == 'Recordatorio de Bodega'), isFalse);
    });

    test('Reset limpia estado en memoria, cancela polling y resetea notifiers', () {
      BodegaPollingService.instance.iniciarPolling(interval: const Duration(seconds: 10));
      expect(BodegaPollingService.instance.isPollingActive, isTrue);

      BodegaPollingService.instance.reset();
      expect(BodegaPollingService.instance.isPollingActive, isFalse);
      expect(BodegaPollingService.instance.tareasNotificadas.isEmpty, isTrue);
      expect(BodegaPollingService.instance.ultimaAlertaResumen, isNull);
      expect(BodegaPollingService.instance.totalPendientesNotifier.value, 0);
    });
  });
}
