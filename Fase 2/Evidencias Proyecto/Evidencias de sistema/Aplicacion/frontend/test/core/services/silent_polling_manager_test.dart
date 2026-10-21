import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/services/silent_polling_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SilentPollingManager Unit Tests', () {
    test('triggerNow ejecuta onPoll si no está pausado', () async {
      int pollCount = 0;
      final manager = SilentPollingManager(
        interval: const Duration(seconds: 10),
        onPoll: () async {
          pollCount++;
        },
      );

      manager.start();
      expect(manager.isRunning, isTrue);

      await manager.triggerNow();
      expect(pollCount, 1);

      manager.dispose();
      expect(manager.isRunning, isFalse);
    });

    test('shouldPause == true omite la ejecución del sondeo', () async {
      int pollCount = 0;
      bool isBusy = true;

      final manager = SilentPollingManager(
        interval: const Duration(seconds: 10),
        shouldPause: () => isBusy,
        onPoll: () async {
          pollCount++;
        },
      );

      manager.start();
      await manager.triggerNow();
      expect(pollCount, 0, reason: 'No debió ejecutarse porque isBusy era true');

      isBusy = false;
      await manager.triggerNow();
      expect(pollCount, 1, reason: 'Debió ejecutarse al pasar isBusy a false');

      manager.dispose();
    });

    test('didChangeAppLifecycleState suspende sondeo si app pasa a paused', () async {
      int pollCount = 0;

      final manager = SilentPollingManager(
        interval: const Duration(seconds: 10),
        onPoll: () async {
          pollCount++;
        },
      );

      manager.start();

      // Simular que la app se minimizó (paused)
      manager.didChangeAppLifecycleState(AppLifecycleState.paused);
      await manager.triggerNow();
      expect(pollCount, 0, reason: 'Omitido porque la app está pausada en segundo plano');

      // Simular que la app volvió a primer plano (resumed)
      manager.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(pollCount, 1, reason: 'Debió reanudarse al volver a primer plano');

      manager.dispose();
    });
  });
}
