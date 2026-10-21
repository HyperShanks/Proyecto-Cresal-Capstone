import 'dart:async';
import 'package:flutter/widgets.dart';

/// Gestor desacoplado de temporizadores de sondeo en segundo plano (Silent Polling).
/// Garantiza que el sondeo periódico:
/// 1. Respete el ciclo de vida del sistema operativo (se suspenda cuando la app se minimice).
/// 2. Respete guardas de UI activa mediante el callback [shouldPause] (evita interferir con cobros o inputs).
/// 3. Evite concurrencia si una petición anterior sigue en curso.
class SilentPollingManager with WidgetsBindingObserver {
  final Duration interval;
  final Future<void> Function() onPoll;
  final bool Function()? shouldPause;
  final String debugLabel;

  Timer? _timer;
  bool _isRunning = false;
  bool _isAppResumed = true;
  bool _isPollExecuting = false;

  SilentPollingManager({
    required this.interval,
    required this.onPoll,
    this.shouldPause,
    this.debugLabel = 'SilentPolling',
  }) {
    WidgetsBinding.instance.addObserver(this);
  }

  bool get isRunning => _isRunning;

  /// Inicia el sondeo periódico si no está corriendo.
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _scheduleNext();
    debugPrint('[$debugLabel] Polling iniciado con intervalo de ${interval.inSeconds}s.');
  }

  /// Detiene el sondeo periódico.
  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
    debugPrint('[$debugLabel] Polling detenido.');
  }

  /// Ejecuta un sondeo inmediato si no está pausado ni ejecutándose.
  Future<void> triggerNow() async {
    if (!_isRunning) return;
    await _executePoll();
  }

  void _scheduleNext() {
    _timer?.cancel();
    if (!_isRunning) return;

    _timer = Timer(interval, () async {
      await _executePoll();
      if (_isRunning) {
        _scheduleNext();
      }
    });
  }

  Future<void> _executePoll() async {
    if (!_isRunning) return;

    // 1. Verificar si la app está en primer plano
    if (!_isAppResumed) {
      debugPrint('[$debugLabel] Omitido: Aplicación en segundo plano.');
      return;
    }

    // 2. Verificar si la pantalla solicitó pausa (ej. modal abierto o digitando pago)
    if (shouldPause != null && shouldPause!()) {
      debugPrint('[$debugLabel] Omitido: Operación en curso o formulario activo.');
      return;
    }

    // 3. Evitar peticiones concurrentes acumuladas
    if (_isPollExecuting) {
      debugPrint('[$debugLabel] Omitido: Petición anterior aún en proceso.');
      return;
    }

    _isPollExecuting = true;
    try {
      await onPoll();
    } catch (e) {
      debugPrint('[$debugLabel] Error temporal en ciclo de polling (silenciado): $e');
    } finally {
      _isPollExecuting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasResumed = _isAppResumed;
    _isAppResumed = (state == AppLifecycleState.resumed);

    if (!wasResumed && _isAppResumed && _isRunning) {
      debugPrint('[$debugLabel] App volvió a primer plano. Reanudando polling...');
      triggerNow();
    }
  }

  /// Libera recursos y remueve el observer del ciclo de vida.
  void dispose() {
    stop();
    WidgetsBinding.instance.removeObserver(this);
  }
}
