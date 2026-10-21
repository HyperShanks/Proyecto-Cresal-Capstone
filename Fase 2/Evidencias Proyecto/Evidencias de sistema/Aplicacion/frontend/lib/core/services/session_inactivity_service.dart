// lib/core/services/session_inactivity_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/auth/services/auth_service.dart';
import '../routes/route_observer.dart';

/// Servicio centralizado de configuración de inactividad de sesión.
class SessionInactivityService {
  /// Tiempo de inactividad por defecto: 10 minutos (según política de seguridad).
  static Duration timeout = const Duration(minutes: 800);

  /// Permite ajustar el tiempo de inactividad para pruebas en desarrollo/QA.
  static void setTimeoutForTesting(Duration newTimeout) {
    timeout = newTimeout;
  }
}

/// Widget envoltorio global que escucha eventos táctiles, clics, teclado y cambios
/// de ciclo de vida de la aplicación móvil (pantalla apagada o en segundo plano).
///
/// Si no se detecta ninguna interacción durante 10 minutos (en cualquier rol o vista),
/// bloquea la app cerrando la navegación previa y redirigiendo inmediatamente
/// a la pantalla de PIN (/login).
class SessionInactivityWatcher extends StatefulWidget {
  final Widget child;

  const SessionInactivityWatcher({super.key, required this.child});

  @override
  State<SessionInactivityWatcher> createState() =>
      _SessionInactivityWatcherState();
}

class _SessionInactivityWatcherState extends State<SessionInactivityWatcher>
    with WidgetsBindingObserver {
  Timer? _timer;
  DateTime _lastActivity = DateTime.now();
  bool _isProcessingLock = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _reiniciarTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _timer?.cancel();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    _registrarActividad();
    return false; // Permite que el evento continúe hacia los widgets hijos
  }

  void _registrarActividad() {
    _lastActivity = DateTime.now();
    _reiniciarTimer();
  }

  void _reiniciarTimer() {
    _timer?.cancel();
    _timer = Timer(SessionInactivityService.timeout, _alCumplirInactividad);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final transcurrido = DateTime.now().difference(_lastActivity);
      if (transcurrido >= SessionInactivityService.timeout) {
        _alCumplirInactividad();
      } else {
        final restante = SessionInactivityService.timeout - transcurrido;
        _timer?.cancel();
        _timer = Timer(restante, _alCumplirInactividad);
      }
    } else if (state == AppLifecycleState.paused) {
      _lastActivity = DateTime.now();
    }
  }

  Future<void> _alCumplirInactividad() async {
    if (_isProcessingLock) return;

    try {
      _isProcessingLock = true;

      // 1. Verificar si existe una sesión activa actualmente
      final tieneSesion = await AuthService.hasActiveSession();
      if (!tieneSesion) return;

      // 2. Comprobar que no estemos ya en pantalla de login, enrolamiento o splash
      final rutaActual = AppRouteObserver.currentRouteName;
      if (rutaActual == '/login' ||
          rutaActual == '/enrolamiento' ||
          rutaActual == '/') {
        return;
      }

      if (kDebugMode) {
        debugPrint(
          '[AUTH] ⏰ Inactividad detectada (${SessionInactivityService.timeout.inMinutes} min) -> Bloqueando aplicación y redirigiendo a pantalla de PIN sin guardar vista previa.',
        );
      }

      // 3. Ejecutar bloqueo y descarte de vista
      await AuthService.bloquearPorInactividad();
    } finally {
      _isProcessingLock = false;
      _reiniciarTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _registrarActividad(),
      onPointerMove: (_) => _registrarActividad(),
      onPointerUp: (_) => _registrarActividad(),
      child: widget.child,
    );
  }
}
