// lib/features/ventas/models/cart_item_model.dart

import 'catalogo_model.dart';

/// Clase base abstracta para cualquier ítem dentro del Carrito Híbrido (HU-3.3).
/// Soporta tanto repuestos inventariados en BD como ventas libres / misceláneas.
abstract class CartItem {
  String get id;
  String get titulo;
  String get subtitulo;
  int get precioUnitario;
  int get cantidad;
  int get subtotal => precioUnitario * cantidad;
  bool get esInventariado;

  String get precioUnitarioFormateado => _formatearMoneda(precioUnitario);
  String get subtotalFormateado => _formatearMoneda(subtotal);

  Map<String, dynamic> toJson();

  static CartItem? fromJson(Map<String, dynamic> json) {
    final tipo = json['tipo']?.toString();
    switch (tipo) {
      case 'inventariado':
        return InventariadoCartItem.fromJson(json);
      case 'venta_libre':
        return VentaLibreCartItem.fromJson(json);
      case 'reserva_backorder':
        return ReservaBackorderCartItem.fromJson(json);
      default:
        // Fallback detection heurística
        if (json.containsKey('catalogo_item') || json.containsKey('id_activo')) {
          return InventariadoCartItem.fromJson(json);
        } else if (json.containsKey('id_reserva') || json.containsKey('marca_requerida')) {
          return ReservaBackorderCartItem.fromJson(json);
        } else if (json.containsKey('descripcion')) {
          return VentaLibreCartItem.fromJson(json);
        }
        return null;
    }
  }

  static String _formatearMoneda(int monto) {
    final valor = monto.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]}.',
        );
    return '\$$valor';
  }
}

/// Representa un Activo Inventariado proveniente del catálogo.
/// Permite que el precio final sea negociado/modificado por el vendedor antes de generar la orden.
class InventariadoCartItem extends CartItem {
  final CatalogoItem catalogoItem;
  int precioFinal;
  String? notasPreparacion;

  InventariadoCartItem({
    required this.catalogoItem,
    required this.precioFinal,
    this.notasPreparacion,
  });

  @override
  String get id => catalogoItem.idActivo;

  @override
  String get titulo => catalogoItem.tituloRepuesto;

  String get sku => catalogoItem.skuQrFisico;
  String get nombreSucursal => catalogoItem.nombreSucursal;

  @override
  String get subtitulo => 'SKU: $sku | Sucursal: $nombreSucursal';

  @override
  int get precioUnitario => precioFinal;

  @override
  int get cantidad => 1; // Un activo físico inventariado es una pieza única (cantidad = 1)

  @override
  bool get esInventariado => true;

  int? get precioMinimo => catalogoItem.precioMinimo;
  int? get precioMaximo => catalogoItem.precioMaximo ?? catalogoItem.precioReferencia;
  int? get precioSugerido => catalogoItem.precioSugerido;

  bool get tieneRango => precioMinimo != null && precioMaximo != null;

  String get rangoPrecioFormateado => catalogoItem.rangoPrecioFormateado;

  /// Valida si el precio acordado actual se encuentra dentro del rango de tasación estipulado
  bool get esPrecioValido {
    if (precioMinimo != null && precioFinal < precioMinimo!) return false;
    if (precioMaximo != null && precioFinal > precioMaximo!) return false;
    return precioFinal > 0;
  }

  /// Retorna un mensaje descriptivo si el precio acordado está fuera del rango
  String? get errorRangoPrecio {
    if (precioMinimo != null && precioFinal < precioMinimo!) {
      return 'Bajo el mínimo permitido (${CartItem._formatearMoneda(precioMinimo!)})';
    }
    if (precioMaximo != null && precioFinal > precioMaximo!) {
      return 'Sobre el máximo permitido (${CartItem._formatearMoneda(precioMaximo!)})';
    }
    if (precioFinal <= 0) {
      return 'El precio debe ser mayor a \$0';
    }
    return null;
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'tipo': 'inventariado',
      'id_activo': catalogoItem.idActivo,
      'sku_qr_fisico': catalogoItem.skuQrFisico,
      'titulo': titulo,
      'precio_referencia_original': catalogoItem.precioReferencia,
      'precio_final': precioFinal,
      'cantidad': cantidad,
      'subtotal': subtotal,
      'notas_preparacion': notasPreparacion,
      'id_sucursal_actual': catalogoItem.idSucursalActual,
      'catalogo_item': catalogoItem.toJson(),
    };
  }

  factory InventariadoCartItem.fromJson(Map<String, dynamic> json) {
    final CatalogoItem item;
    if (json['catalogo_item'] != null && json['catalogo_item'] is Map) {
      item = CatalogoItem.fromJson(Map<String, dynamic>.from(json['catalogo_item'] as Map));
    } else {
      item = CatalogoItem(
        idActivo: json['id_activo']?.toString() ?? '',
        skuQrFisico: json['sku_qr_fisico']?.toString() ?? '',
        precioReferencia: json['precio_referencia_original'] as int?,
        idCategoria: 0,
        nombreCategoria: json['titulo']?.toString() ?? 'Repuesto',
        idSucursalActual: json['id_sucursal_actual'] as int? ?? 0,
        nombreSucursal: '',
      );
    }

    return InventariadoCartItem(
      catalogoItem: item,
      precioFinal: json['precio_final'] as int? ?? item.precioReferencia ?? 0,
      notasPreparacion: json['notas_preparacion'] as String?,
    );
  }
}

/// Representa un artículo de Venta Libre / Misceláneo no registrado previamente en el inventario.
/// Permite especificar una descripción abierta, monto acordado, cantidad y notas.
class VentaLibreCartItem extends CartItem {
  @override
  final String id;
  String descripcion;
  int monto;
  int _cantidad;
  String? observacion;

  VentaLibreCartItem({
    required this.id,
    required this.descripcion,
    required this.monto,
    int cantidad = 1,
    this.observacion,
  }) : _cantidad = cantidad > 0 ? cantidad : 1;

  @override
  String get titulo => descripcion;

  @override
  String get subtitulo =>
      observacion != null && observacion!.isNotEmpty
          ? observacion!
          : 'Venta Libre / Misceláneo';

  @override
  int get precioUnitario => monto;

  @override
  int get cantidad => _cantidad;

  set cantidad(int value) {
    if (value > 0) {
      _cantidad = value;
    }
  }

  @override
  bool get esInventariado => false;

  @override
  Map<String, dynamic> toJson() {
    return {
      'tipo': 'venta_libre',
      'id_item': id,
      'descripcion': descripcion,
      'monto_unitario': monto,
      'cantidad': cantidad,
      'subtotal': subtotal,
      'observacion': observacion,
    };
  }

  factory VentaLibreCartItem.fromJson(Map<String, dynamic> json) {
    return VentaLibreCartItem(
      id: json['id_item']?.toString() ?? json['id']?.toString() ?? 'VL-${DateTime.now().millisecondsSinceEpoch}',
      descripcion: json['descripcion']?.toString() ?? '',
      monto: json['monto_unitario'] as int? ?? json['monto'] as int? ?? 0,
      cantidad: json['cantidad'] as int? ?? 1,
      observacion: json['observacion'] as String?,
    );
  }
}

/// Representa una Reserva por Encargo (Compra en Verde / Backorder) en el carrito
class ReservaBackorderCartItem extends CartItem {
  @override
  final String id;
  final String marca;
  final String modelo;
  final int? anio;
  final String categoriaNombre;
  final int idCategoria;
  final int precioAcordado;
  final int montoAbonado;
  final String? notas;

  ReservaBackorderCartItem({
    required this.id,
    required this.marca,
    required this.modelo,
    this.anio,
    required this.categoriaNombre,
    required this.idCategoria,
    required this.precioAcordado,
    this.montoAbonado = 0,
    this.notas,
  });

  @override
  String get titulo => '[COMPRA EN VERDE] $categoriaNombre - $marca $modelo ${anio != null ? "($anio)" : ""}';

  @override
  String get subtitulo => montoAbonado > 0
      ? 'Precio Acordado: \$${_montoFormateado(precioAcordado)} | Abono: \$${_montoFormateado(montoAbonado)}'
      : 'Precio Acordado: \$${_montoFormateado(precioAcordado)}';

  static String _montoFormateado(int monto) {
    return monto.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  @override
  int get precioUnitario => precioAcordado;

  @override
  int get cantidad => 1;

  @override
  bool get esInventariado => false;

  @override
  Map<String, dynamic> toJson() {
    return {
      'tipo': 'reserva_backorder',
      'id_reserva': id,
      'id_categoria_requerida': idCategoria,
      'categoria_nombre': categoriaNombre,
      'marca_requerida': marca,
      'modelo_requerido': modelo,
      'anio_requerido': anio,
      'precio_acordado': precioAcordado,
      'monto_abonado': montoAbonado,
      'notas_preparacion': notas,
    };
  }

  factory ReservaBackorderCartItem.fromJson(Map<String, dynamic> json) {
    return ReservaBackorderCartItem(
      id: json['id_reserva']?.toString() ?? json['id']?.toString() ?? 'BO-${DateTime.now().millisecondsSinceEpoch}',
      idCategoria: json['id_categoria_requerida'] as int? ?? 0,
      categoriaNombre: json['categoria_nombre']?.toString() ?? 'Repuesto',
      marca: json['marca_requerida']?.toString() ?? '',
      modelo: json['modelo_requerido']?.toString() ?? '',
      anio: json['anio_requerido'] as int?,
      precioAcordado: json['precio_acordado'] as int? ?? 0,
      montoAbonado: json['monto_abonado'] as int? ?? 0,
      notas: json['notas_preparacion'] as String?,
    );
  }
}
