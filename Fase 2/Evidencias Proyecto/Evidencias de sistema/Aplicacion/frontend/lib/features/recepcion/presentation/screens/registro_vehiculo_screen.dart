import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../../../../core/constants/api_constants.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../auth/services/auth_service.dart';
import '../../services/recepcion_service.dart';

/// Formulario Paso a Paso (Wizard) de Recepción Vehicular de Patio (SPEC-22).
/// Diseñado con arquitectura idéntica al Carrito de Ventas (Checkout Wizard):
/// - 4 Vistas secuenciales dedicadas con Stepper Bar superior.
/// - Títulos legibles arriba de cada input (_buildFieldHeader).
/// - Altura y tamaño uniforme entre inputs y botones (50px).
/// - Cero desbordes de píxeles mediante uso estricto de Expanded y LayoutBuilder.
class RegistroVehiculoScreen extends StatefulWidget {
  const RegistroVehiculoScreen({super.key});

  @override
  State<RegistroVehiculoScreen> createState() => _RegistroVehiculoScreenState();
}

class _RegistroVehiculoScreenState extends State<RegistroVehiculoScreen> {
  final RecepcionService _recepcionService = RecepcionService();
  final ImagePicker _imagePicker = ImagePicker();

  int _currentStep = 0; // 0: Identificación, 1: Datos Técnicos, 2: Procedencia, 3: Confirmación
  final int _totalSteps = 4;

  // Controladores de Texto
  final TextEditingController _patenteController = TextEditingController();
  final TextEditingController _facturaController = TextEditingController();
  final TextEditingController _origenController = TextEditingController();
  final TextEditingController _marcaController = TextEditingController();
  final TextEditingController _modeloController = TextEditingController();
  final TextEditingController _anioController = TextEditingController();
  final TextEditingController _colorController = TextEditingController();
  final TextEditingController _motorController = TextEditingController();
  final TextEditingController _gruaController = TextEditingController();
  final TextEditingController _observacionesController = TextEditingController();

  String _siguienteIngreso = '...';
  bool _isSaving = false;
  bool _isOcrProcessing = false;
  bool _esSppu = false;

  DateTime _fechaIngreso = DateTime.now();
  String _destinoSeleccionado = 'DESARME';

  // Catálogos Inteligentes de Chips (Matriz Los Pinos)
  final List<String> _chipsMarcas = [
    'TOYOTA', 'CHEVROLET', 'HYUNDAI', 'NISSAN', 'PEUGEOT', 'KIA', 'SUZUKI', 'MAZDA'
  ];

  final List<String> _chipsColores = [
    'BLANCO', 'GRIS', 'NEGRO', 'PLATEADO', 'AZUL', 'ROJO', 'GRAFITO'
  ];

  final List<String> _chipsOrigen = [
    'PARTICULAR', 'OVALLE', 'REYCO', 'MONTERO', 'ZÁRATE', 'VEDISA', 'MARAMBIO', 'RECSIN', 'VIERA', 'BUIN'
  ];

  final List<String> _chipsDestino = [
    'DESARME', 'VENTA', 'REPARACIÓN', 'CHATARRA'
  ];

  final List<String> _chipsGrua = [
    'F. FANO', 'A. NÚÑEZ', 'C. CAZAM', 'O. VARELA', 'M. BURGOS', 'PARTICULAR'
  ];

  final List<String> _chipsObservaciones = [
    '+ Con Llave', '+ Sin Llave', '+ Con Documentos', '+ Sin Documentos', '+ Chocado', '+ Motor Girando'
  ];

  @override
  void initState() {
    super.initState();
    _cargarSiguienteFolio();
  }

  @override
  void dispose() {
    _patenteController.dispose();
    _facturaController.dispose();
    _origenController.dispose();
    _marcaController.dispose();
    _modeloController.dispose();
    _anioController.dispose();
    _colorController.dispose();
    _motorController.dispose();
    _gruaController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _cargarSiguienteFolio() async {
    final folio = await _recepcionService.obtenerSiguienteIngreso();
    if (mounted) {
      setState(() {
        _siguienteIngreso = folio;
        if (_esSppu) {
          _patenteController.text = 'SPPU-$_siguienteIngreso';
        }
      });
    }
  }

  void _onToggleSppu(bool valor) {
    setState(() {
      _esSppu = valor;
      if (_esSppu) {
        _patenteController.text = 'SPPU-$_siguienteIngreso';
      } else {
        _patenteController.clear();
      }
    });
  }

  void _aplicarChipObservacion(String texto) {
    final actual = _observacionesController.text.trim();
    if (actual.isEmpty) {
      _observacionesController.text = texto;
    } else if (!actual.contains(texto)) {
      _observacionesController.text = '$actual $texto';
    }
    setState(() {});
  }

  Future<void> _seleccionarFechaIngreso() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fechaIngreso,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppPalette.primary,
              onPrimary: Colors.white,
              surface: AppPalette.surface,
              onSurface: AppPalette.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (elegida != null) {
      setState(() {
        _fechaIngreso = elegida;
      });
    }
  }

  Future<void> _ejecutarOcrPadron() async {
    try {
      ImageSource source = ImageSource.camera;

      // En Windows Desktop o Web suele no haber cámara web directa; permitir seleccionar archivo
      if (kIsWeb || (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows)) {
        source = ImageSource.gallery;
      } else {
        final elegida = await showModalBottomSheet<ImageSource>(
          context: context,
          backgroundColor: AppPalette.surface,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
          builder: (ctx) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded, color: AppPalette.primary),
                  title: const Text('Tomar Foto con Cámara', style: TextStyle(color: AppPalette.textPrimary, fontWeight: FontWeight.bold)),
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded, color: AppPalette.secondary),
                  title: const Text('Seleccionar de Galería / Archivos', style: TextStyle(color: AppPalette.textPrimary, fontWeight: FontWeight.bold)),
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
        if (elegida == null) return;
        source = elegida;
      }

      final XFile? imagen = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1600,
      );

      if (imagen == null) return;

      setState(() => _isOcrProcessing = true);

      final token = await AuthService.getToken();
      final uri = Uri.parse('${ApiConstants.vehiculosEndpoint}/ocr-padron');

      final request = http.MultipartRequest('POST', uri);
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      request.files.add(await http.MultipartFile.fromPath('file', imagen.path));

      final streamedResponse = await ApiService.send(request).timeout(const Duration(seconds: 25));
      final res = await http.Response.fromStream(streamedResponse);

      if (res.statusCode == 401) {
        await AuthService.manejarSesionExpirada();
        return;
      }

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          int camposRellenados = 0;
          setState(() {
            if (!_esSppu && data['patente'] != null && data['patente'].toString().isNotEmpty) {
              _patenteController.text = data['patente'].toString().toUpperCase();
              camposRellenados++;
            }
            if (data['marca'] != null && data['marca'].toString().isNotEmpty) {
              _marcaController.text = data['marca'].toString().toUpperCase();
              camposRellenados++;
            }
            if (data['modelo'] != null && data['modelo'].toString().isNotEmpty) {
              _modeloController.text = data['modelo'].toString().toUpperCase();
              camposRellenados++;
            }
            if (data['anio'] != null && data['anio'].toString().isNotEmpty) {
              _anioController.text = data['anio'].toString();
              camposRellenados++;
            }
            if (data['numero_motor'] != null && data['numero_motor'].toString().isNotEmpty) {
              _motorController.text = data['numero_motor'].toString().toUpperCase();
              camposRellenados++;
            }
            if (data['color'] != null && data['color'].toString().isNotEmpty) {
              _colorController.text = data['color'].toString().toUpperCase();
              camposRellenados++;
            }
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: AppPalette.success,
              content: Text('✓ Padrón escaneado ($camposRellenados campos auto-rellenados en Pasos 1 y 2).'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.orange,
              content: Text('OCR no pudo leer con claridad. Puedes continuar digitando manualmente.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppPalette.surface,
            content: Text('Aviso OCR: Digitación manual habilitada ($e)'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isOcrProcessing = false);
    }
  }

  bool _validarPasoActual() {
    if (_currentStep == 0) {
      // Paso 1: Requiere patente (o S/PPU)
      if (!_esSppu && _patenteController.text.trim().isEmpty) {
        _mostrarAlertaError('Por favor ingresa la patente o marca la opción Sin Patente (S/PPU).');
        return false;
      }
    } else if (_currentStep == 1) {
      // Paso 2: Requiere Marca y Modelo
      if (_marcaController.text.trim().isEmpty) {
        _mostrarAlertaError('La marca comercial del vehículo es obligatoria.');
        return false;
      }
      if (_modeloController.text.trim().isEmpty) {
        _mostrarAlertaError('El modelo y versión del vehículo son obligatorios.');
        return false;
      }
    } else if (_currentStep == 2) {
      // Paso 3: Requiere Origen y Destino
      if (_origenController.text.trim().isEmpty) {
        _mostrarAlertaError('Por favor indica el origen o proveedor de procedencia.');
        return false;
      }
    }
    return true;
  }

  void _mostrarAlertaError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppPalette.error,
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(mensaje, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );
  }

  void _avanzarPaso() {
    if (!_validarPasoActual()) return;
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
    }
  }

  void _retrocederPaso() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _guardarVehiculo() async {
    setState(() => _isSaving = true);

    try {
      final payload = {
        'numero_ingreso': _siguienteIngreso,
        'patente': _esSppu ? null : _patenteController.text.trim().toUpperCase(),
        'es_sppu': _esSppu,
        'factura': _facturaController.text.trim().isNotEmpty ? _facturaController.text.trim() : null,
        'fecha_ingreso': _fechaIngreso.toIso8601String().substring(0, 10),
        'origen': _origenController.text.trim().isNotEmpty ? _origenController.text.trim().toUpperCase() : null,
        'marca': _marcaController.text.trim().toUpperCase(),
        'modelo': _modeloController.text.trim().toUpperCase(),
        'anio': int.tryParse(_anioController.text.trim()),
        'color': _colorController.text.trim().isNotEmpty ? _colorController.text.trim().toUpperCase() : null,
        'numero_motor': _motorController.text.trim().isNotEmpty ? _motorController.text.trim().toUpperCase() : null,
        'destino': _destinoSeleccionado,
        'grua': _gruaController.text.trim().isNotEmpty ? _gruaController.text.trim().toUpperCase() : null,
        'observaciones': _observacionesController.text.trim().isNotEmpty ? _observacionesController.text.trim() : null,
      };

      final resultado = await _recepcionService.registrarVehiculo(payload);

      if (!mounted) return;

      if (resultado['exito'] == true) {
        final vehiculo = resultado['vehiculo'];
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppPalette.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: AppPalette.success),
            ),
            title: Row(
              children: const [
                Icon(Icons.check_circle_rounded, color: AppPalette.success, size: 28),
                SizedBox(width: 10),
                Text('¡Ingreso Exitoso!', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Folio Asignado: N° ${vehiculo?.numeroIngreso ?? _siguienteIngreso}',
                  style: const TextStyle(color: AppPalette.secondary, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Patente: ${vehiculo?.patente ?? (_esSppu ? "SPPU-$_siguienteIngreso" : _patenteController.text.toUpperCase())}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Vehículo: ${_marcaController.text.toUpperCase()} ${_modeloController.text.toUpperCase()}',
                  style: const TextStyle(color: AppPalette.textSecondary),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppPalette.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined, color: AppPalette.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Activos base MOT-${vehiculo?.numeroIngreso ?? _siguienteIngreso} y CAJ-${vehiculo?.numeroIngreso ?? _siguienteIngreso} listos en patio para desarme.',
                          style: const TextStyle(color: AppPalette.primary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.primary,
                  minimumSize: const Size(120, 44),
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).pop(true);
                },
                child: const Text('VOLVER A PATIO', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      } else {
        _mostrarAlertaError(resultado['mensaje'] ?? 'Error desconocido al registrar.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ==========================================
  // ELEMENTOS VISUALES & FORMULARIO
  // ==========================================

  Widget _buildFieldHeader(String title, {IconData? icon, bool obligatorio = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppPalette.primary),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              obligatorio ? '$title *' : title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco({String? hint, Widget? prefixIcon, Widget? suffixIcon}) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13.5),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppPalette.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF334155), width: 1.0),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF334155), width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
      ),
    );
  }

  // ── Barra Superior de Progreso (Stepper Bar de 4 Pasos) ──────────────────
  Widget _buildStepProgressBar() {
    final stepLabels = ['Padrón', 'Técnico', 'Origen', 'Revisión'];

    return Container(
      color: AppPalette.surface,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: List.generate(_totalSteps, (index) {
          final isCompleted = index < _currentStep;
          final isCurrent = index == _currentStep;
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCurrent
                              ? AppPalette.primary
                              : isCompleted
                                  ? AppPalette.success
                                  : AppPalette.background,
                          border: Border.all(
                            color: isCurrent
                                ? AppPalette.primary
                                : isCompleted
                                    ? AppPalette.success
                                    : Colors.white24,
                          ),
                        ),
                        child: Center(
                          child: isCompleted
                              ? const Icon(Icons.check, size: 16, color: Colors.white)
                              : Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isCurrent ? Colors.white : AppPalette.textSecondary,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          stepLabels[index],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                            color: isCurrent ? AppPalette.primary : AppPalette.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < _totalSteps - 1)
                  Container(
                    width: 14,
                    height: 2,
                    color: index < _currentStep ? AppPalette.success : Colors.white12,
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ==========================================
  // VISTAS DE CADA PASO
  // ==========================================

  // ── PASO 1: Identificación y Padrón ────────────────────────────────────────
  Widget _buildStep1Identificacion() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner de Folio
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppPalette.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppPalette.secondary.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.tag_rounded, color: AppPalette.secondary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FOLIO DE INGRESO A PATIO',
                        style: TextStyle(color: AppPalette.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'N° $_siguienteIngreso',
                        style: const TextStyle(
                          color: AppPalette.secondary,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Switch S/PPU
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppPalette.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _esSppu ? Colors.orange : Colors.white12,
                width: _esSppu ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.no_crash_outlined,
                  color: _esSppu ? Colors.orange : AppPalette.textSecondary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vehículo Sin Patente (S/PPU)',
                        style: TextStyle(
                          color: _esSppu ? Colors.orange : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Marcar si el auto donante ingresó sin placas',
                        style: TextStyle(color: AppPalette.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _esSppu,
                  activeThumbColor: Colors.orange,
                  onChanged: _onToggleSppu,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Input Patente + Botón OCR (Misma altura exacta de 50px)
          _buildFieldHeader('Patente del Vehículo', icon: Icons.pin_outlined, obligatorio: !_esSppu),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: TextField(
                    controller: _patenteController,
                    enabled: !_esSppu,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1.1),
                    decoration: _inputDeco(
                      hint: _esSppu ? 'SPPU-$_siguienteIngreso' : 'Ej: BBCL12 o ABCD12',
                      prefixIcon: const Icon(Icons.badge_outlined, color: AppPalette.primary, size: 20),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 110,
                height: 50,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppPalette.primary,
                    side: const BorderSide(color: AppPalette.primary, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: _isOcrProcessing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppPalette.primary))
                      : const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('📷 OCR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: _isOcrProcessing ? null : _ejecutarOcrPadron,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // N° Factura / Póliza
          _buildFieldHeader('N° Factura / Póliza / Remate (Opcional)', icon: Icons.receipt_long_outlined),
          SizedBox(
            height: 50,
            child: TextField(
              controller: _facturaController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _inputDeco(
                hint: 'Ej: 115548 o Póliza 4821',
                prefixIcon: const Icon(Icons.receipt_outlined, color: AppPalette.textSecondary, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Fecha de Ingreso
          _buildFieldHeader('Fecha de Recepción Física en Patio', icon: Icons.calendar_today_outlined),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _seleccionarFechaIngreso,
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppPalette.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined, color: AppPalette.primary, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    '${_fechaIngreso.day.toString().padLeft(2, '0')}/${_fechaIngreso.month.toString().padLeft(2, '0')}/${_fechaIngreso.year}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Spacer(),
                  const Text('Cambiar', style: TextStyle(color: AppPalette.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PASO 2: Datos Técnicos del Vehículo ─────────────────────────────────────
  Widget _buildStep2DatosTecnicos() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Marca
          _buildFieldHeader('Marca Comercial', icon: Icons.branding_watermark_outlined, obligatorio: true),
          SizedBox(
            height: 50,
            child: TextField(
              controller: _marcaController,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              decoration: _inputDeco(
                hint: 'Ej: TOYOTA, CHEVROLET, HYUNDAI',
                prefixIcon: const Icon(Icons.car_rental_rounded, color: AppPalette.primary, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _chipsMarcas.map((marca) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    backgroundColor: AppPalette.surface,
                    side: const BorderSide(color: Color(0xFF334155)),
                    label: Text(marca, style: const TextStyle(color: AppPalette.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () => setState(() => _marcaController.text = marca),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),

          // Modelo
          _buildFieldHeader('Modelo y Versión', icon: Icons.directions_car_outlined, obligatorio: true),
          SizedBox(
            height: 50,
            child: TextField(
              controller: _modeloController,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _inputDeco(
                hint: 'Ej: YARIS GLI 1.5, NP300 4X4 2.3, ACCENT RB',
                prefixIcon: const Icon(Icons.drive_file_rename_outline, color: AppPalette.primary, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Año y Color en dos columnas simétricas
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldHeader('Año Fabricación', icon: Icons.event_outlined),
                    SizedBox(
                      height: 50,
                      child: TextField(
                        controller: _anioController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: _inputDeco(hint: 'Ej: 2018'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldHeader('Color Carrocería', icon: Icons.palette_outlined),
                    SizedBox(
                      height: 50,
                      child: TextField(
                        controller: _colorController,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: _inputDeco(hint: 'Ej: BLANCO, GRIS'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _chipsColores.map((color) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    backgroundColor: AppPalette.surface,
                    side: const BorderSide(color: Color(0xFF334155)),
                    label: Text(color, style: const TextStyle(color: AppPalette.textSecondary, fontSize: 11)),
                    onPressed: () => setState(() => _colorController.text = color),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),

          // Número de Motor
          _buildFieldHeader('N° de Motor (Estampado en Bloque - Opcional)', icon: Icons.miscellaneous_services_outlined),
          SizedBox(
            height: 50,
            child: TextField(
              controller: _motorController,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _inputDeco(
                hint: 'Ej: 1NZ-FE12345 o B12D1532',
                prefixIcon: const Icon(Icons.settings_suggest_outlined, color: AppPalette.textSecondary, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PASO 3: Procedencia y Logística ─────────────────────────────────────────
  Widget _buildStep3Procedencia() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Origen / Proveedor
          _buildFieldHeader('Origen / Proveedor de Procedencia', icon: Icons.storefront_outlined, obligatorio: true),
          SizedBox(
            height: 50,
            child: TextField(
              controller: _origenController,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _inputDeco(
                hint: 'Ej: REMATES OVALLE, PARTICULAR',
                prefixIcon: const Icon(Icons.business_outlined, color: AppPalette.primary, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _chipsOrigen.map((origen) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    backgroundColor: AppPalette.surface,
                    side: const BorderSide(color: Color(0xFF334155)),
                    label: Text(origen, style: const TextStyle(color: AppPalette.secondary, fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () => setState(() => _origenController.text = origen),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),

          // Chofer / Grúa
          _buildFieldHeader('Transportista / Grúa (Opcional)', icon: Icons.local_shipping_outlined),
          SizedBox(
            height: 50,
            child: TextField(
              controller: _gruaController,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _inputDeco(
                hint: 'Ej: F. FANO, A. NÚÑEZ, PARTICULAR',
                prefixIcon: const Icon(Icons.fire_truck_outlined, color: AppPalette.textSecondary, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _chipsGrua.map((grua) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    backgroundColor: AppPalette.surface,
                    side: const BorderSide(color: Color(0xFF334155)),
                    label: Text(grua, style: const TextStyle(color: AppPalette.textSecondary, fontSize: 11)),
                    onPressed: () => setState(() => _gruaController.text = grua),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 18),

          // Destino
          _buildFieldHeader('Destino en Planta *', icon: Icons.alt_route_outlined),
          Wrap(
            spacing: 8,
            children: _chipsDestino.map((dest) {
              final sel = _destinoSeleccionado == dest;
              return ChoiceChip(
                label: Text(dest, style: TextStyle(color: sel ? Colors.white : AppPalette.textSecondary, fontWeight: FontWeight.bold)),
                selected: sel,
                selectedColor: AppPalette.primary,
                backgroundColor: AppPalette.surface,
                onSelected: (val) {
                  if (val) setState(() => _destinoSeleccionado = dest);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),

          // Observaciones de Patio
          _buildFieldHeader('Observaciones y Estado Físico', icon: Icons.notes_outlined),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _chipsObservaciones.map((obs) {
              return ActionChip(
                backgroundColor: AppPalette.surface,
                side: const BorderSide(color: Color(0xFF334155)),
                label: Text(obs, style: const TextStyle(color: AppPalette.textPrimary, fontSize: 11)),
                onPressed: () => _aplicarChipObservacion(obs),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _observacionesController,
            maxLines: 3,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: _inputDeco(hint: 'Detalle de llaves, faltantes, choques o papeles adjuntos...'),
          ),
        ],
      ),
    );
  }

  // ── PASO 4: Resumen y Confirmación ──────────────────────────────────────────
  Widget _buildStep4Confirmacion() {
    final patenteDisplay = _esSppu ? 'SPPU-$_siguienteIngreso' : _patenteController.text.toUpperCase();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppPalette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppPalette.primary.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Folio N° $_siguienteIngreso',
                      style: const TextStyle(color: AppPalette.secondary, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _esSppu ? Colors.orange.withValues(alpha: 0.2) : AppPalette.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _esSppu ? Colors.orange : AppPalette.primary),
                      ),
                      child: Text(
                        patenteDisplay,
                        style: TextStyle(
                          color: _esSppu ? Colors.orangeAccent : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),
                _buildResumenFila('Vehículo:', '${_marcaController.text.toUpperCase()} ${_modeloController.text.toUpperCase()}'),
                _buildResumenFila('Año:', _anioController.text.isNotEmpty ? _anioController.text : 'S/I'),
                _buildResumenFila('Color:', _colorController.text.isNotEmpty ? _colorController.text.toUpperCase() : 'S/I'),
                _buildResumenFila('N° Motor:', _motorController.text.isNotEmpty ? _motorController.text.toUpperCase() : 'S/I'),
                const SizedBox(height: 8),
                const Divider(color: Colors.white12),
                const SizedBox(height: 8),
                _buildResumenFila('Origen:', _origenController.text.toUpperCase()),
                _buildResumenFila('Factura:', _facturaController.text.isNotEmpty ? _facturaController.text : 'S/I'),
                _buildResumenFila('Fecha Ingreso:', '${_fechaIngreso.day}/${_fechaIngreso.month}/${_fechaIngreso.year}'),
                _buildResumenFila('Grúa:', _gruaController.text.isNotEmpty ? _gruaController.text.toUpperCase() : 'S/I'),
                _buildResumenFila('Destino:', _destinoSeleccionado),
                if (_observacionesController.text.isNotEmpty)
                  _buildResumenFila('Obs:', _observacionesController.text),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppPalette.primary.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: AppPalette.primary, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _destinoSeleccionado == 'DESARME'
                        ? 'Al registrar, el sistema generará automáticamente los repuestos MOT-$_siguienteIngreso y CAJ-$_siguienteIngreso listos para desarmar.'
                        : 'El vehículo se registrará con destino $_destinoSeleccionado.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResumenFila(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: AppPalette.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ── Botones de Navegación Inferior (Mismo Tamaño 50px) ──────────────────────
  Widget _buildBottomNavigation() {
    final bool esUltimoPaso = _currentStep == _totalSteps - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppPalette.surface,
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (_currentStep > 0) ...[
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppPalette.textPrimary,
                      side: const BorderSide(color: Color(0xFF475569)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _isSaving ? null : _retrocederPaso,
                    child: const Text('ANTERIOR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: _currentStep > 0 ? 1 : 2,
              child: SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: esUltimoPaso ? AppPalette.success : AppPalette.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isSaving
                      ? null
                      : esUltimoPaso
                          ? _guardarVehiculo
                          : _avanzarPaso,
                  child: _isSaving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(
                          esUltimoPaso ? '✓ CONFIRMAR INGRESO' : 'CONTINUAR  ➔',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_currentStep > 0) {
              _retrocederPaso();
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingreso de Vehículo Donante',
              style: TextStyle(color: AppPalette.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'Paso ${_currentStep + 1} de $_totalSteps • Folio N° $_siguienteIngreso',
              style: const TextStyle(color: AppPalette.secondary, fontSize: 12),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 1. Barra Stepper
          _buildStepProgressBar(),

          // 2. Vista Dedicada del Paso
          Expanded(
            child: IndexedStack(
              index: _currentStep,
              children: [
                _buildStep1Identificacion(),
                _buildStep2DatosTecnicos(),
                _buildStep3Procedencia(),
                _buildStep4Confirmacion(),
              ],
            ),
          ),

          // 3. Botones de Navegación Fijos (Misma Altura)
          _buildBottomNavigation(),
        ],
      ),
    );
  }
}
