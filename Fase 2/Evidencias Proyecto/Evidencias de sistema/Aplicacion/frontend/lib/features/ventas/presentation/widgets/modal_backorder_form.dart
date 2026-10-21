import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/constants/especificaciones_vehiculo.dart';
import '../../models/checkout_wizard_models.dart';
import '../../controllers/cart_controller.dart';

/// Modal dialog interactivo para configurar una Reserva por Encargo (Compra en Verde / Backorder) (SPEC-HU-05)
class ModalBackorderForm extends StatefulWidget {
  const ModalBackorderForm({super.key});

  /// Abre el diálogo y retorna la `ReservaBackorderModel` configurada o `null` si se cancela.
  static Future<ReservaBackorderModel?> mostrar(BuildContext context) {
    if (CartController.instance.items.isNotEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'No se pueden agregar ventas en verde porque el carrito ya contiene productos. Las ventas en verde van solas.',
          ),
        ),
      );
      return Future.value(null);
    }
    return showDialog<ReservaBackorderModel>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const ModalBackorderForm(),
    );
  }

  @override
  State<ModalBackorderForm> createState() => _ModalBackorderFormState();
}

class _ModalBackorderFormState extends State<ModalBackorderForm> {
  final _formKey = GlobalKey<FormState>();

  int _selectedCategoriaId = 1;
  String _selectedCategoriaNombre = 'Motor';

  final _marcaController = TextEditingController();
  final _modeloController = TextEditingController();
  final _anioController = TextEditingController();
  final _cilindradaController = TextEditingController();
  final _precioController = TextEditingController();
  final _notasController = TextEditingController();
  final _combustibleOtroController = TextEditingController();
  final _transmisionOtroController = TextEditingController();

  String _combustible = OpcionesCombustible.seleccionar;
  String _transmision = OpcionesTransmision.seleccionar;

  final List<Map<String, dynamic>> _categoriasDisponibles = [
    {'id': 1, 'nombre': 'Motor'},
    {'id': 2, 'nombre': 'Caja de Cambios'},
  ];

  @override
  void dispose() {
    _marcaController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _cilindradaController.dispose();
    _precioController.dispose();
    _notasController.dispose();
    _combustibleOtroController.dispose();
    _transmisionOtroController.dispose();
    super.dispose();
  }

  void _guardarReserva() {
    if (!_formKey.currentState!.validate()) return;

    final precio = CurrencyFormatter.parse(_precioController.text);
    final anio = int.tryParse(_anioController.text.trim());

    final combFinal = (_combustible == OpcionesCombustible.otro && _combustibleOtroController.text.trim().isNotEmpty)
        ? _combustibleOtroController.text.trim()
        : (_combustible != OpcionesCombustible.seleccionar ? _combustible : null);
    final transFinal = (_transmision == OpcionesTransmision.otro && _transmisionOtroController.text.trim().isNotEmpty)
        ? _transmisionOtroController.text.trim()
        : (_transmision != OpcionesTransmision.seleccionar ? _transmision : null);

    final reserva = ReservaBackorderModel(
      idCategoriaRequerida: _selectedCategoriaId,
      categoriaNombre: _selectedCategoriaNombre,
      marcaRequerida: _marcaController.text.trim(),
      modeloRequerido: _modeloController.text.trim(),
      anioRequerido: anio,
      cilindradaRequerida: _cilindradaController.text.trim().isNotEmpty ? _cilindradaController.text.trim() : null,
      combustibleRequerido: combFinal,
      transmisionRequerida: transFinal,
      precioAcordado: precio,
      montoAbonado: 0,
      notasPreparacion: _notasController.text.trim().isNotEmpty ? _notasController.text.trim() : null,
    );

    Navigator.of(context).pop(reserva);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppPalette.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: const BorderSide(color: Colors.white12),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppPalette.secondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.bookmark_add_rounded, color: AppPalette.secondary, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Venta en Verde', style: AppTypography.title.copyWith(fontSize: 18)),
                Text('Pedido por encargo (Sin stock inmediato)', style: AppTypography.small.copyWith(color: AppPalette.secondary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppPalette.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppPalette.primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Esta pieza se registrará como Venta en Verde. Podrás definir el abono acordado en el Paso 4 (Condiciones Comerciales y Abonos) del Checkout.',
                          style: AppTypography.small.copyWith(color: AppPalette.textSecondary, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Categoría
                Text('Categoría Requerida *', style: AppTypography.small.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _selectedCategoriaId,
                  dropdownColor: AppPalette.surface,
                  style: AppTypography.body,
                  decoration: _inputDecoration('Seleccione categoría'),
                  items: _categoriasDisponibles.map((cat) {
                    return DropdownMenuItem<int>(
                      value: cat['id'] as int,
                      child: Text(
                        cat['nombre'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedCategoriaId = val;
                        _selectedCategoriaNombre = _categoriasDisponibles.firstWhere((c) => c['id'] == val)['nombre'] as String;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Marca y Modelo
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Marca *', style: AppTypography.small.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _marcaController,
                            style: AppTypography.body,
                            textCapitalization: TextCapitalization.words,
                            decoration: _inputDecoration('Ej: Toyota, Nissan...'),
                            validator: (val) => (val == null || val.trim().isEmpty) ? 'Requerido' : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Modelo *', style: AppTypography.small.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _modeloController,
                            style: AppTypography.body,
                            textCapitalization: TextCapitalization.words,
                            decoration: _inputDecoration('Ej: Corolla, Sentra...'),
                            validator: (val) => (val == null || val.trim().isEmpty) ? 'Requerido' : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Año y Cilindrada
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Año', style: AppTypography.small.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _anioController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: AppTypography.body,
                            decoration: _inputDecoration('Ej: 2021'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cilindrada / Motor', style: AppTypography.small.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _cilindradaController,
                            style: AppTypography.body,
                            decoration: _inputDecoration('Ej: 1.8L, 2.0 Turbo'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Combustible y Transmisión
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Combustible',
                            style: AppTypography.small.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _combustible,
                            dropdownColor: AppPalette.surface,
                            style: AppTypography.body,
                            decoration: _inputDecoration(''),
                            items: OpcionesCombustible.listaConSeleccionar.map((opcion) {
                              return DropdownMenuItem<String>(
                                value: opcion,
                                child: Text(opcion, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) => setState(() => _combustible = val ?? OpcionesCombustible.seleccionar),
                          ),
                          if (_combustible == OpcionesCombustible.otro) ...[
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _combustibleOtroController,
                              style: AppTypography.body,
                              decoration: _inputDecoration('Especifique combustible'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Transmisión',
                            style: AppTypography.small.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: _transmision,
                            dropdownColor: AppPalette.surface,
                            style: AppTypography.body,
                            decoration: _inputDecoration(''),
                            items: OpcionesTransmision.listaConSeleccionar.map((opcion) {
                              return DropdownMenuItem<String>(
                                value: opcion,
                                child: Text(opcion, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) => setState(() => _transmision = val ?? OpcionesTransmision.seleccionar),
                          ),
                          if (_transmision == OpcionesTransmision.otro) ...[
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _transmisionOtroController,
                              style: AppTypography.body,
                              decoration: _inputDecoration('Especifique transmisión'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Precio Acordado
                Text(
                  'Precio Acordado (\$) *',
                  style: AppTypography.small.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppPalette.secondary,
                  ),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _precioController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [MilesTextInputFormatter()],
                  style: AppTypography.body.copyWith(fontWeight: FontWeight.bold),
                  decoration: _inputDecoration('Ej: 450.000'),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Requerido';
                    final n = CurrencyFormatter.parse(val);
                    if (n <= 0) return 'Mayor a 0';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Notas Técnicas / Especificaciones:
                Text('Notas Técnicas / Especificaciones:', style: AppTypography.small.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _notasController,
                  maxLines: 2,
                  style: AppTypography.body,
                  decoration: _inputDecoration('Detalles específicos para desarme o compras...'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text('Cancelar', style: AppTypography.button.copyWith(color: AppPalette.textSecondary)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppPalette.secondary,
            foregroundColor: AppPalette.background,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('AÑADIR RESERVA', style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: _guardarReserva,
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTypography.small.copyWith(color: AppPalette.textSecondary),
      filled: true,
      fillColor: AppPalette.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white24)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppPalette.primary, width: 1.5)),
    );
  }
}
