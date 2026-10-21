import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

// Rutas relativas hacia la capa core y services del feature
import '../../../../core/widgets/gradient_button.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/constants/especificaciones_vehiculo.dart';
import '../../services/vehiculo_service.dart';
import '../../utils/vehiculo_parser_util.dart';

class RecepcionVehiculoScreen extends StatefulWidget {
  const RecepcionVehiculoScreen({super.key});

  @override
  State<RecepcionVehiculoScreen> createState() =>
      _RecepcionVehiculoScreenState();
}

class _RecepcionVehiculoScreenState extends State<RecepcionVehiculoScreen> {
  // Variables de Estado
  String numeroIngreso = "Cargando...";
  bool isLoading = true;
  bool _seRegistroAlMenosUno = false;
  final VehiculoService _vehiculoService = VehiculoService();

  // Switch Sin Patente (S/PPU)
  bool _esSppu = false;

  // Variables para los selectores obligatorios
  String? traccionSeleccionada;
  String? transmisionSeleccionada;
  String? combustibleSeleccionado;

  // Fecha de Ingreso
  DateTime _fechaIngreso = DateTime.now();

  // Controladores de texto técnicos
  final TextEditingController _patenteController = TextEditingController();
  final TextEditingController _marcaController = TextEditingController();
  final TextEditingController _modeloController = TextEditingController();
  final TextEditingController _anoController = TextEditingController();
  final TextEditingController _cilindradaController = TextEditingController();
  final TextEditingController _motorController = TextEditingController();
  final TextEditingController _traccionOtroController = TextEditingController();
  final TextEditingController _transmisionOtroController = TextEditingController();
  final TextEditingController _combustibleOtroController = TextEditingController();

  // Controladores Matriz Los Pinos (13 columnas)
  final TextEditingController _facturaController = TextEditingController();
  final TextEditingController _origenController = TextEditingController();
  final TextEditingController _colorController = TextEditingController();
  final TextEditingController _destinoController = TextEditingController(text: 'DESARME');
  final TextEditingController _gruaController = TextEditingController();
  final TextEditingController _observacionesController = TextEditingController();

  // Variables para la cámara
  final ImagePicker _picker = ImagePicker();

  // Variable para manejar la pantalla de carga del OCR y Scraping
  bool _isUploading = false;
  bool _isSearchingPatente = false;
  int _ocrFailedAttempts = 0;

  @override
  void initState() {
    super.initState();
    _cargarFolioDesdeBackend();
  }

  @override
  void dispose() {
    _patenteController.dispose();
    _marcaController.dispose();
    _modeloController.dispose();
    _anoController.dispose();
    _cilindradaController.dispose();
    _motorController.dispose();
    _traccionOtroController.dispose();
    _transmisionOtroController.dispose();
    _combustibleOtroController.dispose();
    _facturaController.dispose();
    _origenController.dispose();
    _colorController.dispose();
    _destinoController.dispose();
    _gruaController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  Future<void> _cargarFolioDesdeBackend() async {
    final folio = await _vehiculoService.obtenerSiguienteIngreso();

    if (mounted) {
      setState(() {
        numeroIngreso = folio;
        isLoading = false;
        if (_esSppu) {
          _patenteController.text = 'SPPU-$folio';
        }
      });
    }
  }

  Future<void> _ejecutarScrapingPatente() async {
    final patente = _patenteController.text.trim().toUpperCase();
    if (patente.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Ingresa una patente primero para buscar.'),
          backgroundColor: AppPalette.secondary,
        ),
      );
      return;
    }

    setState(() {
      _isSearchingPatente = true;
    });

    // Ejecutar Scraping NATIVO
    final datos = await _vehiculoService.buscarDatosPorPatente(patente);

    if (!mounted) return;

    if (datos != null) {
      setState(() {
        _marcaController.text = datos['marca'] ?? '';
        _modeloController.text = datos['modelo'] ?? '';
        _anoController.text = datos['anio']?.toString() ?? '';
        _cilindradaController.text = datos['cilindrada'] ?? '';
        _motorController.text = datos['numero_motor'] ?? '';
      });
      _inferirEspecificacionesDesdeModelo();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Datos recuperados exitosamente.'),
          backgroundColor: AppPalette.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ No se encontraron datos para esta patente.'),
          backgroundColor: AppPalette.error,
        ),
      );
    }

    setState(() {
      _isSearchingPatente = false;
    });
  }

  /// Infiere en tiempo real cilindrada, transmisión, combustible y tracción
  /// analizando la descripción ingresada en Marca y Modelo (Matriz Los Pinos).
  void _inferirEspecificacionesDesdeModelo() {
    final modelo = _modeloController.text.trim();
    if (modelo.isEmpty) return;
    final inf = VehiculoParserUtil.inferir(
      modelo: modelo,
      marca: _marcaController.text.trim(),
    );
    setState(() {
      if (inf.cilindrada != null) {
        _cilindradaController.text = inf.cilindrada!;
      }
      traccionSeleccionada = inf.traccion;
      transmisionSeleccionada = inf.transmision;
      combustibleSeleccionado = inf.combustible;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {},
      child: Scaffold(
        backgroundColor: AppPalette.background,
        appBar: AppBar(
          title: const Text(
            'Recepción de Vehículo',
            style: AppTypography.title,
          ),
          backgroundColor: AppPalette.surface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppPalette.primary),
            onPressed: () => Navigator.of(context).pop(_seRegistroAlMenosUno),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. TARJETA DEL FOLIO (Diseño corporativo industrial sin desbordamiento)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 20.0,
                  horizontal: 16.0,
                ),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppPalette.primary.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'NÚMERO DE INGRESO (FOLIO)',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.primary,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        numeroIngreso,
                        style: AppTypography.headline.copyWith(
                          fontSize: 44,
                          color: AppPalette.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Raye este número con plumón Posca en el vehículo antes de guardar',
                      style: AppTypography.small.copyWith(
                        color: AppPalette.textSecondary,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2. SWITCH S/PPU (SIN PATENTE) - PROTEGIDO CON EXPANDED
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _esSppu
                        ? AppPalette.secondary.withValues(alpha: 0.6)
                        : AppPalette.surface,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.no_crash_rounded,
                      color: _esSppu ? AppPalette.secondary : AppPalette.textSecondary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Vehículo Sin Patente (S/PPU)',
                            style: AppTypography.body.copyWith(
                              fontWeight: FontWeight.bold,
                              color: _esSppu ? AppPalette.secondary : AppPalette.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            _esSppu ? 'Folio: SPPU-$numeroIngreso' : 'Vehículo con placa física',
                            style: AppTypography.small.copyWith(
                              color: AppPalette.textSecondary,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Switch(
                      value: _esSppu,
                      activeThumbColor: AppPalette.secondary,
                      onChanged: (val) {
                        setState(() {
                          _esSppu = val;
                          if (val) {
                            _patenteController.text = 'SPPU-$numeroIngreso';
                          } else {
                            _patenteController.clear();
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 3. CAMPO PATENTE CON SCRAPING NATIVO (TITULO ARRIBA)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _esSppu ? 'Patente Asignada (S/PPU)' : 'Patente del Vehículo *',
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 48,
                    child: TextField(
                      controller: _patenteController,
                      enabled: !_esSppu,
                      style: AppTypography.body.copyWith(
                        color: !_esSppu ? AppPalette.textPrimary : AppPalette.textSecondary,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: _esSppu ? 'SPPU-$numeroIngreso' : 'Ej: XXYY11',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        filled: true,
                        fillColor: !_esSppu
                            ? AppPalette.surface
                            : AppPalette.surface.withValues(alpha: 0.5),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        isDense: true,
                        prefixIcon: const Icon(Icons.directions_car, color: AppPalette.primary, size: 20),
                        prefixIconConstraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                        suffixIcon: _esSppu
                            ? null
                            : (_isSearchingPatente
                                ? const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppPalette.primary,
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.search, size: 20),
                                    color: AppPalette.primary,
                                    onPressed: _ejecutarScrapingPatente,
                                    tooltip: 'Buscar datos del vehículo en línea',
                                  )),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // 4. DATOS DE INGRESO Y MATRIZ (13 COLUMNAS LOS PINOS)
              Text(
                'Datos de Ingreso y Procedencia',
                style: AppTypography.cardTitle.copyWith(
                  color: AppPalette.primary,
                  fontSize: 13.5,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _facturaController,
                      label: 'Factura / Póliza',
                      hint: 'Ej: 10423',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildDatePickerField(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _origenController,
                      label: 'Origen / Proveedor',
                      hint: 'Ej: Remates Sur',
                      isCapitalized: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _gruaController,
                      label: 'Grúa / Chofer',
                      hint: 'Ej: Juan Pérez',
                      isCapitalized: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _colorController,
                      label: 'Color Carrocería',
                      hint: 'Ej: Blanco',
                      isCapitalized: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _destinoController,
                      label: 'Destino',
                      hint: 'Ej: DESARME',
                      isCapitalized: true,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // 5. DATOS TÉCNICOS DEL VEHÍCULO
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Text(
                    'Datos Técnicos del Vehículo',
                    style: AppTypography.cardTitle.copyWith(
                      color: AppPalette.primary,
                      fontSize: 13.5,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppPalette.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppPalette.primary.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, color: AppPalette.primary, size: 12),
                        SizedBox(width: 4),
                        Text(
                          'Autocompletado activo',
                          style: TextStyle(
                            color: AppPalette.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _marcaController,
                      label: 'Marca *',
                      hint: 'Ej: Toyota',
                      isCapitalized: true,
                      onChanged: (_) => _inferirEspecificacionesDesdeModelo(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _modeloController,
                      label: 'Modelo *',
                      hint: 'Ej: Yaris',
                      isCapitalized: true,
                      onChanged: (_) => _inferirEspecificacionesDesdeModelo(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _anoController,
                      label: 'Año *',
                      hint: 'Ej: 2018',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _cilindradaController,
                      label: 'Cilindrada',
                      hint: 'Ej: 1.5L',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _buildTextField(
                controller: _motorController,
                label: 'Nro. de Motor',
                hint: 'Ej: 1NZ-FE123456',
                isCapitalized: true,
              ),
              const SizedBox(height: 12),

              // 6. SELECTORES OBLIGATORIOS (TRACCIÓN, TRANSMISIÓN, COMBUSTIBLE)
              Row(
                children: [
                  Expanded(
                    child: _buildDropdown(
                      label: 'Tracción',
                      value: traccionSeleccionada,
                      items: OpcionesTraccion.listaConSeleccionar,
                      onChanged: (nuevoValor) =>
                          setState(() => traccionSeleccionada = nuevoValor),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildDropdown(
                      label: 'Transmisión',
                      value: transmisionSeleccionada,
                      items: OpcionesTransmision.listaConSeleccionar,
                      onChanged: (nuevoValor) =>
                          setState(() => transmisionSeleccionada = nuevoValor),
                    ),
                  ),
                ],
              ),
              if (traccionSeleccionada == OpcionesTraccion.otro) ...[
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _traccionOtroController,
                  label: 'Especifique Tracción',
                  hint: 'Ej: AWD Inteligente',
                ),
              ],
              if (transmisionSeleccionada == OpcionesTransmision.otro) ...[
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _transmisionOtroController,
                  label: 'Especifique Transmisión',
                  hint: 'Ej: CVT Secuencial',
                ),
              ],
              const SizedBox(height: 12),

              _buildDropdown(
                label: 'Combustible',
                value: combustibleSeleccionado,
                items: OpcionesCombustible.listaConSeleccionar,
                onChanged: (nuevoValor) =>
                    setState(() => combustibleSeleccionado = nuevoValor),
              ),
              if (combustibleSeleccionado == OpcionesCombustible.otro) ...[
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _combustibleOtroController,
                  label: 'Especifique Combustible',
                  hint: 'Ej: Híbrido Enchufable',
                ),
              ],

              const SizedBox(height: 14),

              // 7. OBSERVACIONES (TITULO ARRIBA)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Observaciones (Llaves, choques, faltantes, etc.)',
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _observacionesController,
                    style: AppTypography.body.copyWith(fontSize: 13.5),
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Ingrese observaciones del estado de recepción...',
                      hintStyle: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      filled: true,
                      fillColor: AppPalette.surface,
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              // 8. BANNER INSTRUCTIVO DE VALIDACIÓN POKA-YOKE OCR
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppPalette.secondary.withValues(alpha: 0.35),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.camera_alt_outlined,
                      color: AppPalette.secondary,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '📸 Poka-Yoke: Al presionar GUARDAR se abrirá la cámara para verificar el folio N° $numeroIngreso rayado en el vehículo.',
                        style: AppTypography.body.copyWith(
                          color: AppPalette.textPrimary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // 9. BOTÓN GUARDAR CON OCR ATÓMICO (ALTURA EXACTA 50PX)
              SizedBox(
                height: 50,
                width: double.infinity,
                child: GradientButton(
                  key: const Key('btn_guardar_ingreso_ocr'),
                  onPressed: _isUploading ? null : _ejecutarGuardadoConOCR,
                  gradient: const LinearGradient(
                    colors: [AppPalette.primary, AppPalette.primary],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  child: _isUploading
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'VALIDANDO OCR...',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'GUARDAR / REGISTRAR INGRESO',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 36),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    bool isCapitalized = false,
    TextInputType? keyboardType,
    Widget? suffixWidget,
    bool enabled = true,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.small.copyWith(
            color: AppPalette.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 48,
          child: TextField(
            controller: controller,
            enabled: enabled,
            onChanged: onChanged,
            style: AppTypography.body.copyWith(
              color: enabled ? AppPalette.textPrimary : AppPalette.textSecondary,
              fontSize: 13.5,
            ),
            textCapitalization: isCapitalized
                ? TextCapitalization.characters
                : TextCapitalization.none,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
              filled: true,
              fillColor: enabled
                  ? AppPalette.surface
                  : AppPalette.surface.withValues(alpha: 0.5),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              isDense: true,
              prefixIcon: icon != null
                  ? Icon(icon, color: AppPalette.primary, size: 18)
                  : null,
              prefixIconConstraints: icon != null
                  ? const BoxConstraints(minWidth: 34, minHeight: 34)
                  : null,
              suffixIcon: suffixWidget,
              suffixIconConstraints: suffixWidget != null
                  ? const BoxConstraints(minWidth: 34, minHeight: 34)
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
  }) {
    final effectiveValue = items.contains(value) ? value : items.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.small.copyWith(
            color: AppPalette.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 48,
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: effectiveValue,
            dropdownColor: AppPalette.surface,
            style: AppTypography.body.copyWith(
              fontSize: 13.5,
              color: AppPalette.textPrimary,
            ),
            icon: const Icon(Icons.keyboard_arrow_down, color: AppPalette.primary, size: 18),
            decoration: const InputDecoration(
              filled: true,
              fillColor: AppPalette.surface,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              isDense: true,
            ),
            items: items.map((String valor) {
              return DropdownMenuItem<String>(
                value: valor,
                child: Text(
                  valor,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              );
            }).toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildDatePickerField() {
    final fechaStr =
        '${_fechaIngreso.year}-${_fechaIngreso.month.toString().padLeft(2, '0')}-${_fechaIngreso.day.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Fecha Ingreso',
          style: AppTypography.small.copyWith(
            color: AppPalette.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final seleccionada = await showDatePicker(
              context: context,
              initialDate: _fechaIngreso,
              firstDate: DateTime(2000),
              lastDate: DateTime(2035),
              builder: (context, child) {
                return Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: const ColorScheme.dark(
                      primary: AppPalette.primary,
                      onPrimary: Colors.white,
                      surface: AppPalette.surface,
                      onSurface: AppPalette.textPrimary,
                    ),
                    dialogTheme: const DialogThemeData(
                      backgroundColor: AppPalette.surface,
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (seleccionada != null) {
              setState(() => _fechaIngreso = seleccionada);
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 48,
            child: IgnorePointer(
              child: TextField(
                controller: TextEditingController(text: fechaStr),
                style: AppTypography.body.copyWith(fontSize: 13.5),
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: AppPalette.surface,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  isDense: true,
                  suffixIcon: Icon(Icons.calendar_today_rounded, color: AppPalette.primary, size: 18),
                  suffixIconConstraints: BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _ejecutarGuardadoConOCR() async {
    final patenteFinal = _esSppu
        ? "SPPU-$numeroIngreso"
        : _patenteController.text.trim().toUpperCase();

    // 1. Validar campos obligatorios
    if (!_esSppu && patenteFinal.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Ingresa una patente o activa la casilla S/PPU.'),
          backgroundColor: AppPalette.secondary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_marcaController.text.trim().isEmpty ||
        _modeloController.text.trim().isEmpty ||
        _anoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️ Completa los datos obligatorios (Marca, Modelo y Año) antes de registrar.',
          ),
          backgroundColor: AppPalette.secondary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 2. Abrir automáticamente la cámara para capturar la foto física Poka-Yoke optimizada
    final XFile? foto = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 75,
    );

    if (foto == null) {
      return;
    }

    setState(() {
      _isUploading = true;
    });

    final traccionFinal = (traccionSeleccionada == OpcionesTraccion.otro &&
            _traccionOtroController.text.trim().isNotEmpty)
        ? _traccionOtroController.text.trim()
        : (traccionSeleccionada != null &&
                traccionSeleccionada != OpcionesTraccion.seleccionar
            ? traccionSeleccionada!
            : "");
    final transmisionFinal = (transmisionSeleccionada ==
                OpcionesTransmision.otro &&
            _transmisionOtroController.text.trim().isNotEmpty)
        ? _transmisionOtroController.text.trim()
        : (transmisionSeleccionada != null &&
                transmisionSeleccionada != OpcionesTransmision.seleccionar
            ? transmisionSeleccionada!
            : "");
    final combustibleFinal = (combustibleSeleccionado ==
                OpcionesCombustible.otro &&
            _combustibleOtroController.text.trim().isNotEmpty)
        ? _combustibleOtroController.text.trim()
        : (combustibleSeleccionado != null &&
                combustibleSeleccionado != OpcionesCombustible.seleccionar
            ? combustibleSeleccionado!
            : "");

    final datosNuevos = {
      "correlativo_ingreso": numeroIngreso,
      "patente": patenteFinal,
      "es_sppu": _esSppu,
      "factura": _facturaController.text.trim(),
      "fecha_ingreso":
          '${_fechaIngreso.year}-${_fechaIngreso.month.toString().padLeft(2, '0')}-${_fechaIngreso.day.toString().padLeft(2, '0')}',
      "origen": _origenController.text.trim(),
      "marca": _marcaController.text.trim(),
      "modelo": _modeloController.text.trim(),
      "anio": int.tryParse(_anoController.text.trim()) ?? 2000,
      "color": _colorController.text.trim(),
      "numero_motor": _motorController.text.trim(),
      "destino": _destinoController.text.trim().isEmpty ? 'DESARME' : _destinoController.text.trim().toUpperCase(),
      "grua": _gruaController.text.trim(),
      "observaciones": _observacionesController.text.trim(),
      "cilindrada": _cilindradaController.text.trim(),
      "traccion": traccionFinal,
      "transmision": transmisionFinal,
      "combustible": combustibleFinal,
      "estado": "EN_PATIO",
    };

    try {
      final resultado = await _vehiculoService.guardarIngresoConRespuesta(
        datosNuevos,
        foto,
      );

      if (!mounted) return;

      if (resultado['exito'] == true) {
        _ocrFailedAttempts = 0;
        _seRegistroAlMenosUno = true;

        final tsvRow = [
          numeroIngreso,
          patenteFinal,
          _facturaController.text.trim(),
          '${_fechaIngreso.year}-${_fechaIngreso.month.toString().padLeft(2, '0')}-${_fechaIngreso.day.toString().padLeft(2, '0')}',
          _origenController.text.trim(),
          _marcaController.text.trim(),
          _modeloController.text.trim(),
          _anoController.text.trim(),
          _colorController.text.trim(),
          _motorController.text.trim(),
          _destinoController.text.trim().isEmpty ? 'DESARME' : _destinoController.text.trim().toUpperCase(),
          _gruaController.text.trim(),
          _observacionesController.text.trim().replaceAll('\t', ' ').replaceAll('\n', ' '),
        ].join('\t');

        await Clipboard.setData(ClipboardData(text: tsvRow));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ N° $numeroIngreso ingresado. Fila copiada para Excel (pega con Ctrl+V en columna A).',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: const Color(0xFF107C41),
              duration: const Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }

        _limpiarFormulario();
        _cargarFolioDesdeBackend();
      } else {
        _ocrFailedAttempts++;
        final mensajeError = resultado['mensaje']?.toString() ?? '';
        final String feedback;
        if (mensajeError.toLowerCase().contains('poka-yoke') ||
            mensajeError.toLowerCase().contains('ocr') ||
            mensajeError.toLowerCase().contains('foto') ||
            mensajeError.toLowerCase().contains('texto') ||
            mensajeError.toLowerCase().contains('corresponde')) {
          feedback =
              'No se pudo validar el OCR del vehículo. Verifique que el N° $numeroIngreso esté rayado claramente y reintente.';
        } else {
          feedback = mensajeError.isNotEmpty
              ? mensajeError
              : 'Fallo de validación OCR en el vehículo.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ $feedback (Intento $_ocrFailedAttempts/3)'),
            backgroundColor: AppPalette.error,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );

        if (_ocrFailedAttempts >= 3 && mounted) {
          _mostrarModalIngresoManual(context, datosNuevos);
        }
      }
    } catch (e) {
      _ocrFailedAttempts++;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error en servicio OCR (Intento $_ocrFailedAttempts/3).'),
            backgroundColor: AppPalette.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        if (_ocrFailedAttempts >= 3) {
          _mostrarModalIngresoManual(context, datosNuevos);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _limpiarFormulario() {
    _patenteController.clear();
    _marcaController.clear();
    _modeloController.clear();
    _anoController.clear();
    _cilindradaController.clear();
    _motorController.clear();
    _traccionOtroController.clear();
    _transmisionOtroController.clear();
    _combustibleOtroController.clear();
    _facturaController.clear();
    _origenController.clear();
    _colorController.clear();
    _destinoController.text = 'DESARME';
    _gruaController.clear();
    _observacionesController.clear();
    setState(() {
      _esSppu = false;
      _fechaIngreso = DateTime.now();
      traccionSeleccionada = null;
      transmisionSeleccionada = null;
      combustibleSeleccionado = null;
      numeroIngreso = "Cargando...";
    });
  }

  // ── MODALES DE CONTINGENCIA / VALIDACIÓN MANUAL (Poka-Yoke Fallback) ──

  Future<void> _mostrarModalIngresoManual(
    BuildContext context,
    Map<String, dynamic> datosNuevos,
  ) async {
    final TextEditingController manualIngresoController = TextEditingController(
      text: numeroIngreso != "Cargando..." ? numeroIngreso : "",
    );

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppPalette.secondary,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Validación Manual OCR',
                style: AppTypography.cardTitle.copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No logramos detectar el número automáticamente en la foto. Ingresa manualmente el N° de Ingreso visible en el vehículo.',
              style: AppTypography.body.copyWith(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('input_numero_ingreso_manual'),
              controller: manualIngresoController,
              decoration: const InputDecoration(
                labelText: 'N° de Ingreso Físico',
                hintText: 'Ej: 1003',
                prefixIcon: Icon(
                  Icons.confirmation_number_outlined,
                  color: AppPalette.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('btn_reintentar_camara'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Reintentar con Cámara',
              style: AppTypography.button.copyWith(
                color: AppPalette.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            key: const Key('btn_confirmar_ingreso_manual'),
            onPressed: () {
              if (manualIngresoController.text.trim().isNotEmpty) {
                Navigator.of(ctx).pop(true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.primary,
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final numeroManual = manualIngresoController.text.trim();
      await _mostrarModalDobleConfirmacion(datosNuevos, numeroManual);
    }
  }

  Future<void> _mostrarModalDobleConfirmacion(
    Map<String, dynamic> datosNuevos,
    String numeroManual,
  ) async {
    if (!mounted) return;
    final doubleConfirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(
              Icons.verified_user_outlined,
              color: AppPalette.primary,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Confirmación de Seguridad',
                style: AppTypography.cardTitle.copyWith(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          '¿Confirmas que el N° de Ingreso $numeroManual corresponde fielmente al vehículo físico?',
          style: AppTypography.body.copyWith(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: AppTypography.button.copyWith(
                color: AppPalette.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            key: const Key('btn_aceptar_doble_confirmacion'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.success,
            ),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );

    if (doubleConfirmed == true && mounted) {
      setState(() {
        _isUploading = true;
        _ocrFailedAttempts = 0;
      });

      final datosFinales = Map<String, dynamic>.from(datosNuevos);
      datosFinales["correlativo_ingreso"] = numeroManual;
      if (_esSppu) {
        datosFinales["patente"] = "SPPU-$numeroManual";
      }

      try {
        final res = await _vehiculoService.guardarIngresoManual(datosFinales);
        if (!mounted) return;

        if (res['exito'] == true) {
          _seRegistroAlMenosUno = true;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '✅ Vehículo registrado exitosamente con validación manual.',
              ),
              backgroundColor: AppPalette.success,
              duration: Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );

          _limpiarFormulario();
          _cargarFolioDesdeBackend();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ ${res['mensaje']}'),
              backgroundColor: AppPalette.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error al guardar: $e'),
              backgroundColor: AppPalette.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isUploading = false);
        }
      }
    }
  }
}
