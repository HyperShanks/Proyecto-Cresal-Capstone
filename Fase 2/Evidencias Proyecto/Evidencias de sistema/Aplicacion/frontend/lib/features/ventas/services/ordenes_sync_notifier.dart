// lib/features/ventas/services/ordenes_sync_notifier.dart

import 'package:flutter/foundation.dart';

/// Notificador reactivo global tipo EventBus / ChangeNotifier para sincronizar
/// el ciclo de vida de las órdenes de venta entre pantallas (Carrito, Historial, Entregas).
class OrdenesSyncNotifier extends ChangeNotifier {
  OrdenesSyncNotifier._internal();
  static final OrdenesSyncNotifier instance = OrdenesSyncNotifier._internal();

  int _lastEventTimestamp = 0;
  int get lastEventTimestamp => _lastEventTimestamp;

  /// Emite una notificación reactiva para recargar órdenes en segundo plano
  /// tras crear, pagar, entregar, despachar o anular un pedido.
  void notificarCambio() {
    _lastEventTimestamp = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
  }
}
