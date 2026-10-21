import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../services/paletizado_service.dart';

class ForzarIngresoScreen extends StatefulWidget {
  final Map<String, dynamic> vehiculoData;
  final PaletizadoService paletizadoService;

  const ForzarIngresoScreen({
    super.key,
    required this.vehiculoData,
    required this.paletizadoService,
  });

  @override
  State<ForzarIngresoScreen> createState() => _ForzarIngresoScreenState();
}

class _ForzarIngresoScreenState extends State<ForzarIngresoScreen> {
  late TextEditingController _marcaController;
  late TextEditingController _modeloController;
  late TextEditingController _anioController;
  late TextEditingController _traccionController;
  late TextEditingController _cilindradaController;
  late TextEditingController _combustibleController;
  late TextEditingController _transmisionMotorController;
  late TextEditingController _transmisionCajaController;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _marcaController = TextEditingController(text: widget.vehiculoData['marca']?.toString() ?? '');
    _modeloController = TextEditingController(text: widget.vehiculoData['modelo']?.toString() ?? '');
    _anioController = TextEditingController(text: widget.vehiculoData['anio']?.toString() ?? '');
    _traccionController = TextEditingController(text: widget.vehiculoData['traccion']?.toString() ?? '');
    
    final motor = widget.vehiculoData['motor'] ?? {};
    _cilindradaController = TextEditingController(text: motor['cilindrada']?.toString() ?? '');
    _combustibleController = TextEditingController(text: motor['combustible']?.toString() ?? '');
    _transmisionMotorController = TextEditingController(text: motor['transmision_tipo']?.toString() ?? '');

    final caja = widget.vehiculoData['caja'] ?? {};
    _transmisionCajaController = TextEditingController(text: caja['transmision_tipo']?.toString() ?? '');
  }

  @override
  void dispose() {
    _marcaController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _traccionController.dispose();
    _cilindradaController.dispose();
    _combustibleController.dispose();
    _transmisionMotorController.dispose();
    _transmisionCajaController.dispose();
    super.dispose();
  }

  Future<void> _guardarYPaletizar() async {
    setState(() => _isLoading = true);
    final payload = {
      "marca": _marcaController.text.trim(),
      "modelo": _modeloController.text.trim(),
      "anio": int.tryParse(_anioController.text.trim()) ?? 0,
      "traccion": _traccionController.text.trim(),
      "motor": {
        "cilindrada": _cilindradaController.text.trim(),
        "combustible": _combustibleController.text.trim(),
        "transmision_tipo": _transmisionMotorController.text.trim()
      },
      "caja": {
        "transmision_tipo": _transmisionCajaController.text.trim()
      }
    };

    final exito = await widget.paletizadoService.forzarIngresoVehiculo(
      widget.vehiculoData['id_vehiculo'],
      payload,
    );

    setState(() => _isLoading = false);

    if (exito && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Datos forzados correctamente. Redirigiendo a paletizado...'),
          backgroundColor: AppPalette.success,
        ),
      );
      Navigator.of(context).pushReplacementNamed(
        '/paletizado',
        arguments: widget.vehiculoData['numero_ingreso'],
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al guardar los datos forzados.'),
          backgroundColor: AppPalette.error,
        ),
      );
    }
  }

  Widget _buildTextField(String label, TextEditingController controller, {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: AppTypography.small.copyWith(color: AppPalette.textSecondary),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          filled: true,
          fillColor: AppPalette.surface,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        title: const Text('Forzar Ingreso de Repuesto', style: AppTypography.title),
        backgroundColor: AppPalette.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppPalette.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppPalette.warning),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppPalette.warning, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Usando Vehículo Comodín #${widget.vehiculoData["numero_ingreso"]}', 
                             style: AppTypography.title.copyWith(color: AppPalette.warning)),
                        const SizedBox(height: 4),
                        Text('Estás a punto de sobreescribir permanentemente la información de este número de ingreso.', 
                             style: AppTypography.small.copyWith(color: AppPalette.textPrimary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            Text('Datos del Vehículo', style: AppTypography.title.copyWith(color: AppPalette.primary)),
            const Divider(),
            _buildTextField('Marca', _marcaController),
            _buildTextField('Modelo', _modeloController),
            _buildTextField('Año', _anioController, keyboardType: TextInputType.number),
            _buildTextField('Tracción', _traccionController),
            
            const SizedBox(height: 16),
            Text('Especificaciones del Motor', style: AppTypography.title.copyWith(color: AppPalette.primary)),
            const Divider(),
            _buildTextField('Cilindrada', _cilindradaController),
            _buildTextField('Combustible', _combustibleController),
            _buildTextField('Transmisión', _transmisionMotorController),
            
            const SizedBox(height: 16),
            Text('Especificaciones de la Caja de Cambios', style: AppTypography.title.copyWith(color: AppPalette.primary)),
            const Divider(),
            _buildTextField('Transmisión', _transmisionCajaController),
            
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isLoading ? null : _guardarYPaletizar,
                child: _isLoading
                    ? const CircularProgressIndicator(color: AppPalette.surface)
                    : Text('GUARDAR Y PALETIZAR', style: AppTypography.button.copyWith(color: AppPalette.surface)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
