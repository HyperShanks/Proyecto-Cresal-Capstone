// lib/features/ventas/controllers/cart_controller.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/cart_item_model.dart';
import '../models/catalogo_model.dart';
import '../services/carrito_service.dart';

/// Controlador Reactivo de Estado Global para el Carrito Híbrido (HU-3.3).
/// Implementado como Singleton con ChangeNotifier (100% Flutter nativo).
/// Persiste en memoria y en almacenamiento seguro (FlutterSecureStorage),
/// sobreviviendo a cierres de aplicación y reconciliando reservas con el backend.
class CartController extends ChangeNotifier {
  static const String _storageCartKey = 'cresal_cart_items_v1';
  static CartController _instance = CartController._internal();
  factory CartController() => _instance;
  static CartController get instance => _instance;

  FlutterSecureStorage _storage;
  bool _estaCargandoPersistencia = false;

  CartController._internal({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                resetOnError: true,
              ),
            ) {
    unawaited(cargarDesdeAlmacenamiento());
  }

  /// Método para reiniciar la instancia en entornos de pruebas unitarias
  @visibleForTesting
  static void resetForTesting({FlutterSecureStorage? mockStorage}) {
    _instance = CartController._internal(storage: mockStorage);
  }

  final List<CartItem> _items = [];

  /// Lista inmutable de ítems en el carrito
  List<CartItem> get items => List.unmodifiable(_items);

  /// Cantidad total de unidades de productos en el carrito
  int get totalItems => _items.fold(0, (sum, item) => sum + item.cantidad);

  /// Monto total acumulado en pesos chilenos (CLP)
  int get totalMonto => _items.fold(0, (sum, item) => sum + item.subtotal);

  /// Monto total formateado en moneda CLP (ej. "$1.250.000")
  String get totalMontoFormateado {
    final valor = totalMonto.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
    return '\$$valor';
  }

  /// Indica si el carrito está actualmente vacío
  bool get estaVacio => _items.isEmpty;

  /// Indica si el carrito contiene actualmente una Venta en Verde (Reserva Backorder)
  bool get tieneVentaEnVerde => _items.any((i) => i is ReservaBackorderCartItem);

  /// Indica si el carrito contiene ítems regulares (inventariados o venta libre)
  bool get tieneItemsRegulares => _items.any((i) => i is! ReservaBackorderCartItem);

  /// Las ventas en verde van exclusivamente solas en el pedido
  bool get puedeAgregarVentaEnVerde => _items.isEmpty;

  /// Solo se pueden agregar ítems regulares si no hay una venta en verde en el pedido
  bool get puedeAgregarItemRegular => !tieneVentaEnVerde;

  /// Verifica si existe algún repuesto inventariado cuyo precio final acordado
  /// esté fuera del rango de tasación permitido (mínimo y máximo).
  bool get hayPreciosInvalidos {
    return _items.any((item) => item is InventariadoCartItem && !item.esPrecioValido);
  }

  /// Verifica si un activo inventariado específico ya se encuentra en el carrito
  bool estaEnCarrito(String idActivo) {
    return _items.any((item) => item.esInventariado && item.id == idActivo);
  }

  /// Persiste el estado actual de los ítems del carrito en el almacenamiento seguro
  Future<void> guardarEnAlmacenamiento() async {
    try {
      if (_items.isEmpty) {
        await _storage.delete(key: _storageCartKey);
      } else {
        final rawList = _items.map((i) => i.toJson()).toList();
        await _storage.write(key: _storageCartKey, value: jsonEncode(rawList));
      }
    } catch (e) {
      debugPrint('Error al guardar carrito en almacenamiento seguro: $e');
    }
  }

  /// Carga los ítems persistidos desde el almacenamiento seguro y opcionalmente
  /// reconcilia la vigencia de las reservas con el backend
  Future<void> cargarDesdeAlmacenamiento({bool reconciliarBackend = true}) async {
    if (_estaCargandoPersistencia) return;
    _estaCargandoPersistencia = true;

    try {
      final jsonStr = await _storage.read(key: _storageCartKey);
      if (jsonStr != null && jsonStr.trim().isNotEmpty) {
        final trimmed = jsonStr.trim();
        if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
          final dynamic decoded = jsonDecode(trimmed);
          if (decoded is List) {
            _items.clear();
            for (final itemMap in decoded) {
              if (itemMap is Map) {
                final cartItem = CartItem.fromJson(Map<String, dynamic>.from(itemMap));
                if (cartItem != null) {
                  _items.add(cartItem);
                }
              }
            }
            notifyListeners();
          }
        }
      }

      if (reconciliarBackend) {
        unawaited(reconciliarConBackend());
      }
    } catch (e) {
      debugPrint('Error al cargar carrito desde almacenamiento seguro: $e');
    } finally {
      _estaCargandoPersistencia = false;
    }
  }

  /// Reconcilia los activos inventariados reservados con el estado en el backend (SSOT).
  /// Si una reserva expiró mientras la app estuvo cerrada, se remueve del carrito.
  /// Si hay reservas activas en backend que no están en memoria local, se rehidratan automáticamente.
  Future<void> reconciliarConBackend() async {
    try {
      final misReservas = await CarritoService.obtenerMisReservas();
      if (misReservas == null) {
        // En caso de problema de conexión o sesión no autenticada, no alteramos el estado local
        return;
      }

      final idsActivosVigentes = misReservas
          .map((r) => r['id_activo']?.toString())
          .where((id) => id != null)
          .toSet();

      bool huboCambios = false;

      // 1. Remover ítems locales cuyas reservas hayan expirado o no existan en el backend
      _items.removeWhere((item) {
        if (item.esInventariado) {
          final sigueVigente = idsActivosVigentes.contains(item.id);
          if (!sigueVigente) {
            huboCambios = true;
            return true;
          }
        }
        return false;
      });

      // 2. REHIDRATACIÓN (SSOT): Restaurar cualquier reserva activa que esté en el backend pero no en el carrito local
      final idsLocales = _items.where((i) => i.esInventariado).map((i) => i.id).toSet();
      for (final r in misReservas) {
        final idActivo = r['id_activo']?.toString();
        if (idActivo != null && !idsLocales.contains(idActivo)) {
          if (!tieneVentaEnVerde) {
            final catalogoItem = CatalogoItem(
              idActivo: idActivo,
              skuQrFisico: r['sku_qr_fisico']?.toString() ?? '',
              precioReferencia: r['precio_referencia'] as int?,
              precioMinimo: r['precio_minimo'] as int?,
              precioMaximo: r['precio_maximo'] as int?,
              idCategoria: r['id_categoria'] as int? ?? 0,
              nombreCategoria: r['nombre_categoria']?.toString() ?? 'Repuesto',
              idSucursalActual: r['id_sucursal_actual'] as int? ?? 1,
              nombreSucursal: r['nombre_sucursal']?.toString() ?? 'Sucursal no especificada',
              idVehiculo: r['id_vehiculo']?.toString(),
              marca: r['marca']?.toString(),
              modelo: r['modelo']?.toString(),
              anio: r['anio'] as int?,
              ubicacionPasillo: r['ubicacion_pasillo']?.toString(),
              ubicacionPallet: r['ubicacion_pallet']?.toString(),
              ubicacionGalpon: r['ubicacion_galpon']?.toString(),
              numeroMotor: r['numero_motor']?.toString(),
              cilindrada: r['cilindrada']?.toString(),
              combustible: r['combustible']?.toString(),
              transmisionTipo: r['transmision_tipo']?.toString(),
              imagenes: (r['imagenes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
              versionLock: r['version_lock'] as int? ?? 1,
              idEstado: 2,
              estadoActivo: 'Reservado',
            );

            final cartItem = InventariadoCartItem(
              catalogoItem: catalogoItem,
              precioFinal: catalogoItem.precioSugerido ?? catalogoItem.precioReferencia ?? 0,
            );

            _items.add(cartItem);
            idsLocales.add(idActivo);
            huboCambios = true;
          }
        }
      }

      if (huboCambios) {
        notifyListeners();
        await guardarEnAlmacenamiento();
      }
    } catch (e) {
      debugPrint('Error al reconciliar carrito con backend: $e');
    }
  }

  /// Agrega un Activo Inventariado al carrito.
  /// Retorna `true` si se agregó exitosamente, o `false` si ya existía en el carrito
  /// o si el carrito contiene una Venta en Verde (las ventas en verde van solas).
  bool agregarInventariado(
    CatalogoItem item, {
    int? precioFinal,
    String? notas,
  }) {
    if (_items.any((i) => i is ReservaBackorderCartItem)) {
      return false;
    }
    if (estaEnCarrito(item.idActivo)) {
      return false;
    }

    final cartItem = InventariadoCartItem(
      catalogoItem: item,
      precioFinal: precioFinal ?? item.precioSugerido ?? item.precioReferencia ?? 0,
      notasPreparacion: notas,
    );

    _items.add(cartItem);
    notifyListeners();
    unawaited(guardarEnAlmacenamiento());
    return true;
  }

  /// Agrega un artículo de Venta Libre / Misceláneo al carrito
  bool agregarVentaLibre({
    required String descripcion,
    required int monto,
    int cantidad = 1,
    String? observacion,
  }) {
    if (_items.any((i) => i is ReservaBackorderCartItem)) {
      return false;
    }

    final cartItem = VentaLibreCartItem(
      id: 'VL-${DateTime.now().millisecondsSinceEpoch}',
      descripcion: descripcion.trim(),
      monto: monto,
      cantidad: cantidad > 0 ? cantidad : 1,
      observacion: observacion?.trim(),
    );

    _items.add(cartItem);
    notifyListeners();
    unawaited(guardarEnAlmacenamiento());
    return true;
  }

  /// Agrega una Reserva por Encargo (Compra en Verde / Backorder) al carrito.
  /// Regla de Negocio: Las ventas en verde van solas y de a una por orden.
  /// Retorna `true` si se agregó, o `false` si el carrito no está vacío.
  bool agregarReservaBackorder({
    required int idCategoria,
    required String categoriaNombre,
    required String marca,
    required String modelo,
    int? anio,
    required int precioAcordado,
    int montoAbonado = 0,
    String? notas,
  }) {
    if (_items.isNotEmpty) {
      return false;
    }

    final cartItem = ReservaBackorderCartItem(
      id: 'BO-${DateTime.now().millisecondsSinceEpoch}',
      idCategoria: idCategoria,
      categoriaNombre: categoriaNombre,
      marca: marca,
      modelo: modelo,
      anio: anio,
      precioAcordado: precioAcordado,
      montoAbonado: montoAbonado,
      notas: notas,
    );

    _items.add(cartItem);
    notifyListeners();
    unawaited(guardarEnAlmacenamiento());
    return true;
  }

  /// Actualiza el precio acordado de un ítem (inventariado, venta libre o backorder)
  void actualizarPrecio(String itemId, int nuevoPrecio) {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1) return;

    final item = _items[index];
    if (item is InventariadoCartItem) {
      item.precioFinal = nuevoPrecio;
    } else if (item is VentaLibreCartItem) {
      item.monto = nuevoPrecio;
    }
    notifyListeners();
    unawaited(guardarEnAlmacenamiento());
  }

  /// Actualiza la cantidad de un ítem de venta libre (si es 0 se elimina)
  void actualizarCantidad(String itemId, int nuevaCantidad) {
    if (nuevaCantidad <= 0) {
      eliminarItem(itemId);
      return;
    }

    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1) return;

    final item = _items[index];
    if (item is VentaLibreCartItem) {
      item.cantidad = nuevaCantidad;
      notifyListeners();
      unawaited(guardarEnAlmacenamiento());
    }
  }

  /// Actualiza las notas / observaciones de preparación de un ítem
  void actualizarNotas(String itemId, String? notas) {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index == -1) return;

    final item = _items[index];
    if (item is InventariadoCartItem) {
      item.notasPreparacion = notas;
    } else if (item is VentaLibreCartItem) {
      item.observacion = notas;
    }
    notifyListeners();
    unawaited(guardarEnAlmacenamiento());
  }

  /// Elimina un ítem específico del carrito por su ID y libera su reserva si es inventariado
  void eliminarItem(String itemId, {bool liberarEnBackend = true}) {
    final index = _items.indexWhere((item) => item.id == itemId);
    if (index == -1) return;

    final item = _items[index];
    if (liberarEnBackend && item.esInventariado) {
      unawaited(CarritoService.liberarActivo(item.id));
    }

    _items.removeAt(index);
    notifyListeners();
    unawaited(guardarEnAlmacenamiento());
  }

  /// Libera todas las reservas inventariadas en el backend y limpia el almacenamiento
  Future<void> liberarYVaciarEnBackend() async {
    final inventariados = _items.where((item) => item.esInventariado).toList();
    _items.clear();
    notifyListeners();
    await guardarEnAlmacenamiento();
    if (inventariados.isNotEmpty) {
      await Future.wait(
        inventariados.map((item) => CarritoService.liberarActivo(item.id)),
      );
    }
  }

  /// Vacía por completo el carrito.
  /// Si [liberarEnBackend] es true, libera todas las reservas temporales de activos inventariados en el backend.
  void vaciarCarrito({bool liberarEnBackend = false}) {
    if (liberarEnBackend) {
      final inventariados = _items.where((item) => item.esInventariado).toList();
      for (final item in inventariados) {
        unawaited(CarritoService.liberarActivo(item.id));
      }
    }
    _items.clear();
    notifyListeners();
    unawaited(guardarEnAlmacenamiento());
  }
}
