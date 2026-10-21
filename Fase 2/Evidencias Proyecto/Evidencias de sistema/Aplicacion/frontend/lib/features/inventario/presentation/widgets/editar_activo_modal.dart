import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/constants/especificaciones_vehiculo.dart';
import '../../services/inventario_service.dart';

/// Modal para editar la ubicación física y especificaciones técnicas de un activo en bodega.
/// Solo disponible para repuestos en estado 'Disponible' o 'Paletizado'.
class EditarActivoModal extends StatefulWidget {
  final Map<String, dynamic> activo;

  const EditarActivoModal({
    super.key,
    required this.activo,
  });

  @override
  State<EditarActivoModal> createState() => _EditarActivoModalState();
}

class _EditarActivoModalState extends State<EditarActivoModal> {
  // Controladores vehiculares
  late final TextEditingController _marcaController;
  late final TextEditingController _modeloController;
  late final TextEditingController _anioController;

  // Controladores de ubicación
  late final TextEditingController _pasilloController;
  late final TextEditingController _palletController;
  late final TextEditingController _galponController;

  // Controladores técnicos y notas
  late final TextEditingController _numeroMotorController;
  late final TextEditingController _cilindradaController;
  late final TextEditingController _observacionController;

  String? _combustibleSeleccionado;
  String? _transmisionSeleccionada;
  String? _traccionSeleccionada;

  late final String _initialMarca;
  late final String _initialModelo;
  late final String _initialAnio;
  late final String _initialPasillo;
  late final String _initialPallet;
  late final String _initialGalpon;
  late final String _initialNumeroMotor;
  late final String _initialCilindrada;
  late final String _initialObservacion;
  late final String? _initialCombustible;
  late final String? _initialTransmision;
  late final String? _initialTraccion;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    final rawMarca = (widget.activo['marca'] ?? widget.activo['vehiculo']?['marca'] ?? '').toString().trim();
    _initialMarca = (rawMarca == 'Desconocida' || rawMarca == 'null' || rawMarca == 'N/A') ? '' : rawMarca;
    _marcaController = TextEditingController(text: _initialMarca);

    final rawModelo = (widget.activo['modelo'] ?? widget.activo['vehiculo']?['modelo'] ?? '').toString().trim();
    _initialModelo = (rawModelo == 'Desconocido' || rawModelo == 'null' || rawModelo == 'N/A') ? '' : rawModelo;
    _modeloController = TextEditingController(text: _initialModelo);

    final rawAnio = (widget.activo['anio'] ?? widget.activo['ano'] ?? widget.activo['vehiculo']?['anio'] ?? '').toString().trim();
    _initialAnio = (rawAnio == '0' || rawAnio == 'null' || rawAnio == 'S/A' || rawAnio == 'N/A') ? '' : rawAnio;
    _anioController = TextEditingController(text: _initialAnio);

    _initialPasillo = (widget.activo['pasillo'] ?? widget.activo['ubicacion_pasillo'] ?? '').toString().trim();
    _initialPallet = (widget.activo['pallet'] ?? widget.activo['ubicacion_pallet'] ?? '').toString().trim();
    _initialGalpon = (widget.activo['galpon'] ?? widget.activo['ubicacion_galpon'] ?? '').toString().trim();

    _pasilloController = TextEditingController(text: _initialPasillo == 'S/P' ? '' : _initialPasillo);
    _palletController = TextEditingController(text: _initialPallet == 'S/P' ? '' : _initialPallet);
    _galponController = TextEditingController(text: _initialGalpon == 'S/G' ? '' : _initialGalpon);

    final numMotor = (widget.activo['numero_motor'] ?? widget.activo['numeroMotor'] ?? '').toString().trim();
    _initialNumeroMotor = (numMotor == 'S/A' || numMotor == 'null' || numMotor == 'N/A') ? '' : numMotor;
    _numeroMotorController = TextEditingController(text: _initialNumeroMotor);

    final cil = (widget.activo['cilindrada'] ?? '').toString().trim();
    _initialCilindrada = (cil == 'S/A' || cil == 'null' || cil == 'N/A') ? '' : cil;
    _cilindradaController = TextEditingController(text: _initialCilindrada);

    final obs = (widget.activo['observacion'] ?? widget.activo['observacion_estado'] ?? '').toString().trim();
    _initialObservacion = (obs == 'Sin observaciones registradas.' || obs == 'null') ? '' : obs;
    _observacionController = TextEditingController(text: _initialObservacion);

    final comb = (widget.activo['combustible'] ?? '').toString().trim();
    _combustibleSeleccionado = OpcionesCombustible.lista.contains(comb) ? comb : null;
    _initialCombustible = _combustibleSeleccionado;

    final trans = (widget.activo['transmision'] ?? widget.activo['transmision_tipo'] ?? widget.activo['transmisionTipo'] ?? '').toString().trim();
    _transmisionSeleccionada = OpcionesTransmision.lista.contains(trans) ? trans : null;
    _initialTransmision = _transmisionSeleccionada;

    final trac = (widget.activo['traccion'] ?? '').toString().trim();
    _traccionSeleccionada = OpcionesTraccion.lista.contains(trac) ? trac : null;
    _initialTraccion = _traccionSeleccionada;
  }

  @override
  void dispose() {
    _marcaController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _pasilloController.dispose();
    _palletController.dispose();
    _galponController.dispose();
    _numeroMotorController.dispose();
    _cilindradaController.dispose();
    _observacionController.dispose();
    super.dispose();
  }

  bool _isFormDirty() {
    final curMarca = _marcaController.text.trim();
    final curModelo = _modeloController.text.trim();
    final curAnio = _anioController.text.trim();

    final curPasillo = _pasilloController.text.trim();
    final curPallet = _palletController.text.trim();
    final curGalpon = _galponController.text.trim();

    final curNumMotor = _numeroMotorController.text.trim();
    final curCil = _cilindradaController.text.trim();
    final curObs = _observacionController.text.trim();

    final initP = _initialPasillo == 'S/P' ? '' : _initialPasillo;
    final initPl = _initialPallet == 'S/P' ? '' : _initialPallet;
    final initG = _initialGalpon == 'S/G' ? '' : _initialGalpon;

    return curMarca != _initialMarca ||
        curModelo != _initialModelo ||
        curAnio != _initialAnio ||
        curPasillo != initP ||
        curPallet != initPl ||
        curGalpon != initG ||
        curNumMotor != _initialNumeroMotor ||
        curCil != _initialCilindrada ||
        curObs != _initialObservacion ||
        _combustibleSeleccionado != _initialCombustible ||
        _transmisionSeleccionada != _initialTransmision ||
        _traccionSeleccionada != _initialTraccion;
  }

  Future<bool> _mostrarDialogoConfirmacionDescarte() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        title: Text(
          'Descartar cambios',
          style: AppTypography.title.copyWith(color: AppPalette.textPrimary),
        ),
        content: Text(
          'Tienes cambios sin guardar. ¿Estás seguro de que quieres salir y descartar las modificaciones?',
          style: AppTypography.body.copyWith(color: AppPalette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Seguir editando',
              style: AppTypography.button.copyWith(color: AppPalette.neutral),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.error,
            ),
            child: Text(
              'Descartar',
              style: AppTypography.button.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  Future<void> _handleCancelOrClose() async {
    if (_isFormDirty()) {
      final shouldPop = await _mostrarDialogoConfirmacionDescarte();
      if (shouldPop && mounted) {
        Navigator.of(context).pop();
      }
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _guardarCambios() async {
    setState(() => _isSaving = true);
    try {
      final idActivo = widget.activo['id_activo']?.toString() ?? '';
      final versionLock = (widget.activo['version_lock'] as num?)?.toInt() ?? 1;

      final Map<String, dynamic> payload = {
        'version_lock_esperado': versionLock,
        'ubicacion_pasillo': _pasilloController.text.trim(),
        'ubicacion_pallet': _palletController.text.trim(),
        'ubicacion_galpon': _galponController.text.trim(),
        'observacion_estado': _observacionController.text.trim(),
        'numero_motor': _numeroMotorController.text.trim(),
        'cilindrada': _cilindradaController.text.trim(),
        'marca': _marcaController.text.trim(),
        'modelo': _modeloController.text.trim(),
        if (int.tryParse(_anioController.text.trim()) != null)
          'anio': int.parse(_anioController.text.trim()),
        if (_combustibleSeleccionado != null) 'combustible': _combustibleSeleccionado,
        if (_transmisionSeleccionada != null) 'transmision_tipo': _transmisionSeleccionada,
        if (_traccionSeleccionada != null) 'traccion': _traccionSeleccionada,
      };

      final resultado = await InventarioService.editarActivo(idActivo, payload);

      if (!mounted) return;
      setState(() => _isSaving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Activo y especificaciones actualizados exitosamente.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppPalette.success,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.of(context).pop({
        'ubicacion_pasillo': _pasilloController.text.trim(),
        'ubicacion_pallet': _palletController.text.trim(),
        'ubicacion_galpon': _galponController.text.trim(),
        'observacion_estado': _observacionController.text.trim(),
        'numero_motor': _numeroMotorController.text.trim(),
        'cilindrada': _cilindradaController.text.trim(),
        'combustible': _combustibleSeleccionado,
        'transmision': _transmisionSeleccionada,
        'transmision_tipo': _transmisionSeleccionada,
        'traccion': _traccionSeleccionada,
        'marca': _marcaController.text.trim(),
        'modelo': _modeloController.text.trim(),
        'anio': int.tryParse(_anioController.text.trim()),
        'version_lock': resultado['version_lock'] ?? (versionLock + 1),
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);

      final errorStr = e.toString();
      if (errorStr.contains('409') || errorStr.contains('colisión') || errorStr.contains('modificada por otro usuario')) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppPalette.surface,
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppPalette.secondary, size: 28),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Información Desactualizada',
                    style: AppTypography.title.copyWith(color: AppPalette.textPrimary),
                  ),
                ),
              ],
            ),
            content: Text(
              'Este repuesto fue modificado recientemente por otro usuario. '
              'Los datos se actualizarán ahora para que revises los cambios antes de volver a editar.',
              style: AppTypography.body.copyWith(color: AppPalette.textSecondary),
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop({'conflict': true});
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppPalette.primary),
                child: const Text('Actualizar y Revisar'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorStr.replaceAll('Exception: ', ''),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppPalette.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final categoria = widget.activo['categoria']?.toString() ?? 'Repuesto';
    final sku = widget.activo['sku']?.toString() ?? widget.activo['sku_qr_fisico']?.toString() ?? 'S/N';

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        padding: EdgeInsets.only(bottom: bottomInset),
        decoration: const BoxDecoration(
          color: AppPalette.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabecera Modal
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: AppPalette.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(
                  bottom: BorderSide(
                    color: AppPalette.neutral.withValues(alpha: 0.15),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppPalette.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.edit_note,
                      color: AppPalette.primary,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Editar Activo: $categoria',
                          style: AppTypography.title.copyWith(
                            fontSize: 16,
                            color: AppPalette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'SKU: $sku',
                          style: AppTypography.small.copyWith(
                            color: AppPalette.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppPalette.textSecondary),
                    onPressed: _handleCancelOrClose,
                    tooltip: 'Cerrar',
                  ),
                ],
              ),
            ),

            // Formulario Scrollable con Ubicación, Vehículo y Especificaciones Técnicas
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 1. UBICACIÓN FÍSICA EN BODEGA (GALPÓN, PASILLO, PALLET) ──
                    _buildSectionHeader(
                      title: 'UBICACIÓN FÍSICA EN BODEGA',
                      subtitle: 'Indica o actualiza la posición física: galpón, pasillo y pallet.',
                      icon: Icons.warehouse_outlined,
                    ),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _galponController,
                            label: 'Galpón',
                            hintText: 'Ej. 1',
                            icon: Icons.warehouse_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: _pasilloController,
                            label: 'Pasillo',
                            hintText: 'Ej. A',
                            icon: Icons.view_column_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: _palletController,
                            label: 'Pallet',
                            hintText: 'Ej. P-01',
                            icon: Icons.layers_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Sugerencias rápidas de Galpón y Pasillo
                    _buildQuickLocationSuggestions(),

                    const SizedBox(height: 24),

                    // ── 2. DATOS DEL VEHÍCULO DE ORIGEN ──
                    _buildSectionHeader(
                      title: 'DATOS DEL VEHÍCULO DE ORIGEN',
                      subtitle: 'Marca, modelo, año y tracción del vehículo de procedencia.',
                      icon: Icons.directions_car_outlined,
                    ),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _marcaController,
                            label: 'Marca',
                            hintText: 'Ej. Toyota',
                            icon: Icons.branding_watermark_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: _modeloController,
                            label: 'Modelo',
                            hintText: 'Ej. Corolla',
                            icon: Icons.directions_car_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _anioController,
                            label: 'Año',
                            hintText: 'Ej. 2021',
                            icon: Icons.calendar_today_outlined,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Tracción',
                            value: _traccionSeleccionada,
                            items: OpcionesTraccion.lista,
                            icon: Icons.swap_calls_outlined,
                            onChanged: (val) => setState(() => _traccionSeleccionada = val),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── 3. ESPECIFICACIONES TÉCNICAS (DISPONIBLES PARA TODO ACTIVO) ──
                    _buildSectionHeader(
                      title: 'ESPECIFICACIONES TÉCNICAS',
                      subtitle: 'Modifica los datos mecánicos registrados para este activo.',
                      icon: Icons.precision_manufacturing_outlined,
                    ),
                    const SizedBox(height: 14),

                    _buildTextField(
                      controller: _numeroMotorController,
                      label: 'Número de Motor',
                      hintText: 'Ej. 1NZ-FE-123456',
                      icon: Icons.tag,
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _cilindradaController,
                            label: 'Cilindrada',
                            hintText: 'Ej. 1.8L',
                            icon: Icons.speed,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildDropdownField(
                            label: 'Combustible',
                            value: _combustibleSeleccionado,
                            items: OpcionesCombustible.lista,
                            icon: Icons.local_gas_station_outlined,
                            onChanged: (val) => setState(() => _combustibleSeleccionado = val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    _buildDropdownField(
                      label: 'Transmisión',
                      value: _transmisionSeleccionada,
                      items: OpcionesTransmision.lista,
                      icon: Icons.settings_outlined,
                      onChanged: (val) => setState(() => _transmisionSeleccionada = val),
                    ),

                    const SizedBox(height: 24),

                    // ── 4. OBSERVACIÓN / ESTADO ──
                    _buildSectionHeader(
                      title: 'OBSERVACIÓN DEL ESTADO',
                      subtitle: 'Detalles visuales, mecánicos o condiciones del repuesto.',
                      icon: Icons.notes_outlined,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _observacionController,
                      maxLines: 3,
                      style: AppTypography.body.copyWith(color: AppPalette.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Detalles visuales o mecánicos del repuesto...',
                        hintStyle: AppTypography.body.copyWith(color: AppPalette.textSecondary.withValues(alpha: 0.5)),
                        filled: true,
                        fillColor: AppPalette.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppPalette.neutral.withValues(alpha: 0.2)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: AppPalette.neutral.withValues(alpha: 0.2)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Barra Inferior de Acciones
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppPalette.surface,
                border: Border(
                  top: BorderSide(
                    color: AppPalette.neutral.withValues(alpha: 0.15),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : _handleCancelOrClose,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: AppPalette.neutral.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'CANCELAR',
                        style: AppTypography.button.copyWith(color: AppPalette.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _guardarCambios,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.check_rounded, color: Colors.white),
                      label: Text(
                        _isSaving ? 'GUARDANDO...' : 'GUARDAR CAMBIOS',
                        style: AppTypography.button.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppPalette.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickLocationSuggestions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.flash_on, size: 13, color: AppPalette.primary),
            const SizedBox(width: 4),
            Text(
              'Sugerencias rápidas para Galpón y Pasillo:',
              style: AppTypography.small.copyWith(
                color: AppPalette.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...OpcionesUbicacionBodega.galpones.map((g) {
              final isSelected = _galponController.text.trim() == g;
              return InkWell(
                onTap: () {
                  setState(() {
                    _galponController.text = g;
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppPalette.primary.withValues(alpha: 0.25)
                        : AppPalette.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected
                          ? AppPalette.primary
                          : AppPalette.neutral.withValues(alpha: 0.25),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warehouse_outlined, size: 12, color: isSelected ? AppPalette.primary : AppPalette.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'Galpón $g',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? AppPalette.primary : AppPalette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            ...['A', 'B', 'C', 'D', 'E'].map((p) {
              final isSelected = _pasilloController.text.trim() == p;
              return InkWell(
                onTap: () {
                  setState(() {
                    _pasilloController.text = p;
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppPalette.secondary.withValues(alpha: 0.25)
                        : AppPalette.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected
                          ? AppPalette.secondary
                          : AppPalette.neutral.withValues(alpha: 0.25),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.view_column_outlined, size: 12, color: isSelected ? AppPalette.secondary : AppPalette.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        'Pasillo $p',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected ? AppPalette.secondary : AppPalette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppPalette.primary, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: AppTypography.small.copyWith(
                  color: AppPalette.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: AppTypography.small.copyWith(
            color: AppPalette.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.small.copyWith(
            fontWeight: FontWeight.bold,
            color: AppPalette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: AppTypography.body.copyWith(color: AppPalette.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: hintText,
            hintStyle: AppTypography.body.copyWith(color: AppPalette.textSecondary.withValues(alpha: 0.5)),
            prefixIcon: Icon(icon, color: AppPalette.primary, size: 18),
            prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            filled: true,
            fillColor: AppPalette.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppPalette.neutral.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppPalette.neutral.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required ValueChanged<String?> onChanged,
  }) {
    final validValue = (value != null && items.contains(value)) ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.small.copyWith(
            fontWeight: FontWeight.bold,
            color: AppPalette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: validValue,
          isExpanded: true,
          dropdownColor: AppPalette.surface,
          style: const TextStyle(color: AppPalette.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: Icon(icon, color: AppPalette.primary, size: 18),
            prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            filled: true,
            fillColor: AppPalette.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppPalette.neutral.withValues(alpha: 0.2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppPalette.neutral.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
            ),
          ),
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppPalette.textPrimary, fontSize: 13),
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
