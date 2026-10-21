import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/constants/especificaciones_vehiculo.dart';
import '../../services/paletizado_service.dart';
import '../../services/print_service.dart';
import '../../domain/exceptions/printer_exceptions.dart';
import '../../domain/models/etiqueta_data.dart';
import '../widgets/dialogo_falla_impresora.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class PaletizadoScreen extends StatefulWidget {
  final String? numeroIngresoInicial;
  final PaletizadoService? paletizadoService;

  const PaletizadoScreen({
    super.key,
    this.numeroIngresoInicial,
    this.paletizadoService,
  });

  @override
  State<PaletizadoScreen> createState() => _PaletizadoScreenState();
}

class _PaletizadoScreenState extends State<PaletizadoScreen> {
  final TextEditingController _searchController = TextEditingController();
  late final PaletizadoService _paletizadoService;

  final TextEditingController _galponController = TextEditingController();
  final TextEditingController _pasilloController = TextEditingController();
  final TextEditingController _palletController = TextEditingController();
  final TextEditingController _observacionController = TextEditingController();

  bool _isLoading = false;
  bool _vehiculoEncontrado = false;
  bool _buscarPorNumeroMotor = false;

  String _marca = "";
  String _modelo = "";
  String _anio = "";
  // Datos técnicos específicos del activo
  Map<String, dynamic> _datosMotor = {};
  Map<String, dynamic> _datosCaja = {};

  String _tipoActivoSeleccionado = 'Motor';
  List<String> _opcionesRepuestos = []; // ⚠️ NUEVA LISTA DINÁMICA

  bool _isValidatingOCR = false;
  int _ocrFailedAttempts = 0;

  final ImagePicker _picker = ImagePicker();
  final List<XFile> _fotosComerciales = [];

  // Controladores y estado para edición de especificaciones técnicas
  final TextEditingController _cilindradaController = TextEditingController();
  final TextEditingController _numeroMotorController = TextEditingController();
  String? _combustibleSeleccionado;
  String? _transmisionSeleccionada;
  String? _traccionSeleccionada;

  @override
  void initState() {
    super.initState();
    _paletizadoService = widget.paletizadoService ?? PaletizadoService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inicializarIngreso();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _galponController.dispose();
    _pasilloController.dispose();
    _palletController.dispose();
    _observacionController.dispose();
    _cilindradaController.dispose();
    _numeroMotorController.dispose();
    super.dispose();
  }

  void _cargarCamposTecnicos() {
    if (_tipoActivoSeleccionado == 'Motor') {
      final numMot = (_datosMotor['numero_motor'] ?? '').toString().trim();
      _numeroMotorController.text = (numMot == 'S/A' || numMot == 'null' || numMot == '-') ? '' : numMot;

      final cil = (_datosMotor['cilindrada'] ?? '').toString().trim();
      _cilindradaController.text = (cil == 'S/A' || cil == 'null' || cil == '-') ? '' : cil;

      final comb = (_datosMotor['combustible'] ?? '').toString().trim();
      _combustibleSeleccionado = OpcionesCombustible.lista.contains(comb) ? comb : null;

      final trans = (_datosMotor['transmision_tipo'] ?? '').toString().trim();
      _transmisionSeleccionada = OpcionesTransmision.lista.contains(trans) ? trans : null;

      final trac = (_datosMotor['traccion'] ?? '').toString().trim();
      _traccionSeleccionada = OpcionesTraccion.lista.contains(trac) ? trac : null;
    } else {
      final trans = (_datosCaja['transmision_tipo'] ?? '').toString().trim();
      _transmisionSeleccionada = OpcionesTransmision.lista.contains(trans) ? trans : null;

      final trac = (_datosCaja['traccion'] ?? _datosMotor['traccion'] ?? '').toString().trim();
      _traccionSeleccionada = OpcionesTraccion.lista.contains(trac) ? trac : null;

      final cil = (_datosCaja['cilindrada'] ?? _datosMotor['cilindrada'] ?? '').toString().trim();
      _cilindradaController.text = (cil == 'S/A' || cil == 'null' || cil == '-') ? '' : cil;

      final comb = (_datosCaja['combustible'] ?? _datosMotor['combustible'] ?? '').toString().trim();
      _combustibleSeleccionado = OpcionesCombustible.lista.contains(comb) ? comb : null;
    }
  }

  void _inicializarIngreso() {
    final folio = widget.numeroIngresoInicial ??
        (ModalRoute.of(context)?.settings.arguments as String?);
    if (folio != null && folio.trim().isNotEmpty) {
      _searchController.text = folio.trim();
      _buscarVehiculo();
    }
  }

  Future<void> _tomarFotoComercial() async {
    if (_fotosComerciales.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Has alcanzado el límite de 10 fotografías.'),
          backgroundColor: AppPalette.secondary,
        ),
      );
      return;
    }

    try {
      // imageQuality: 75 y maxWidth/Height: 1280 optimiza drásticamente el peso (~200KB vs 5MB) para subidas ágiles en datos móviles
      final XFile? foto = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 75,
      );

      if (foto != null) {
        setState(() {
          _fotosComerciales.add(foto);
        });
      }
    } catch (e) {
      debugPrint("Error al abrir la cámara: $e");
    }
  }

  // ── Función para eliminar una foto por error ──
  void _eliminarFoto(int index) {
    setState(() {
      _fotosComerciales.removeAt(index);
    });
  }

  // ── Función para Validar OCR y Guardar ──
  Future<void> _validarYGuardar() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final folio = _searchController.text.trim();

    // 1. Validaciones básicas de interfaz
    if (_fotosComerciales.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe tomar al menos 1 foto comercial de la pieza.'),
          backgroundColor: AppPalette.secondary,
        ),
      );
      return;
    }

    if (_galponController.text.isEmpty ||
        _pasilloController.text.isEmpty ||
        _palletController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Por favor, complete todos los campos de ubicación física.',
          ),
          backgroundColor: AppPalette.error,
        ),
      );
      return;
    }

    // 2. Abrir cámara para la foto técnica (Poka-Yoke) optimizada para OCR veloz
    final XFile? fotoOcr = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 75,
    );
    if (fotoOcr == null) {
      return; // Si el usuario cancela la cámara, no hacemos nada
    }

    // 3. Bloquear la UI (Botón de carga activado para OCR + Subida a la nube)
    setState(() => _isValidatingOCR = true);

    // 4. Llamada al servicio de validación Poka-Yoke
    final resultadoOCR = await _paletizadoService.validarOCRPieza(
      folio,
      File(fotoOcr.path),
    );

    if (!mounted) return;

    // 5. Analizar el resultado de la Inteligencia Artificial
    if (resultadoOCR != null) {
      final bool esMatch = resultadoOCR['match'] ?? false;
      final String mensaje = resultadoOCR['mensaje'] ?? 'Error desconocido';

      if (esMatch) {
        _ocrFailedAttempts = 0;
        // ¡ÉXITO OCR! Avisamos al usuario que ahora estamos guardando...
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Validación exitosa. Subiendo fotos a la nube...'),
            backgroundColor: AppPalette.success,
          ),
        );

        // --- 6. GUARDADO DEFINITIVO ---
        // Convertimos la lista de XFile a File para el servicio
        List<File> fotosArchivos = _fotosComerciales
            .map((x) => File(x.path))
            .toList();

        // Llamamos al guardado que envía los textos y las fotos
        final resultadoGuardado = await _paletizadoService
            .guardarPaletizadoDefinitivo(
              folio: folio,
              tipoRepuesto: _tipoActivoSeleccionado,
              galpon: _galponController.text.trim(),
              pasillo: _pasilloController.text.trim(),
              pallet: _palletController.text.trim(),
              observaciones: _observacionController.text.trim(),
              cilindrada: _cilindradaController.text.trim(),
              combustible: _combustibleSeleccionado,
              transmisionTipo: _transmisionSeleccionada,
              numeroMotor: _numeroMotorController.text.trim(),
              traccion: _traccionSeleccionada,
              fotos: fotosArchivos,
            );

        if (!mounted) return;

        // Terminó el proceso pesado, detenemos el indicador de carga del botón
        setState(() => _isValidatingOCR = false);

        // HU-2.4: En lugar de un simple SnackBar, mostramos el modal interactivo
        if (resultadoGuardado != null) {
          // Construimos el EtiquetaData a partir de la respuesta enriquecida del backend
          final etiqueta = EtiquetaData.fromJson(resultadoGuardado);

          // Limpiamos el formulario ANTES de mostrar el modal
          _limpiarFormulario();

          // Mostramos el Modal Bottom Sheet con las 3 opciones
          await _mostrarModalExito(etiqueta);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Error al guardar en el servidor. Revise la consola.',
              ),
              backgroundColor: AppPalette.error,
            ),
          );
        }
      } else {
        // ERROR: La pieza no coincide.
        _ocrFailedAttempts++;
        setState(() => _isValidatingOCR = false); // Detenemos la carga
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'ALERTA: $mensaje (Intento $_ocrFailedAttempts/3)\nTexto detectado: ${resultadoOCR['texto_detectado']}',
            ),
            backgroundColor: AppPalette.error,
            duration: const Duration(seconds: 4),
          ),
        );

        if (_ocrFailedAttempts >= 3 && mounted) {
          _mostrarModalIngresoManual();
        }
      }
    } else {
      // Error de red o Google Cloud Vision al intentar conectar con el OCR
      _ocrFailedAttempts++;
      setState(() => _isValidatingOCR = false); // Detenemos la carga
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error de conexión o fallo en servicio OCR (Intento $_ocrFailedAttempts/3).',
          ),
          backgroundColor: AppPalette.error,
        ),
      );

      // Solo si se alcanzaron los 3 intentos fallidos -> Dispara contingencia manual
      if (_ocrFailedAttempts >= 3 && mounted) {
        _mostrarModalIngresoManual();
      }
    }
  }

  // ── MODALES DE CONTINGENCIA / VALIDACIÓN MANUAL (HU-2.3 Poka-Yoke Fallback) ──

  Future<void> _mostrarModalIngresoManual() async {
    final TextEditingController manualIngresoController =
        TextEditingController(text: _searchController.text.trim());

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppPalette.secondary, size: 28),
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
              'No logramos detectar el número automáticamente o hubo un problema de conexión. Ingresa manualmente el N° de Ingreso visible en el vehículo o pieza.',
              style: AppTypography.body.copyWith(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('input_numero_ingreso_manual_paletizado'),
              controller: manualIngresoController,
              decoration: const InputDecoration(
                labelText: 'N° de Ingreso Físico',
                hintText: 'Ej: 1001',
                prefixIcon: Icon(Icons.confirmation_number_outlined, color: AppPalette.primary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('btn_reintentar_camara_paletizado'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Reintentar con Cámara',
              style: AppTypography.button.copyWith(color: AppPalette.textSecondary),
            ),
          ),
          ElevatedButton(
            key: const Key('btn_confirmar_ingreso_manual_paletizado'),
            onPressed: () {
              if (manualIngresoController.text.trim().isNotEmpty) {
                Navigator.of(ctx).pop(true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppPalette.primary),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final numeroManual = manualIngresoController.text.trim();

      // Consultar al backend para validar que el numero_ingreso exista en la tabla Vehiculo_Origen
      setState(() => _isValidatingOCR = true);
      final vehiculoValido = await _paletizadoService.buscarVehiculoPorIngreso(numeroManual);
      if (!mounted) return;
      setState(() => _isValidatingOCR = false);

      if (vehiculoValido == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ El N° de Ingreso $numeroManual no existe en el sistema.'),
            backgroundColor: AppPalette.error,
          ),
        );
        return;
      }

      await _mostrarModalDobleConfirmacion(numeroManual);
    }
  }

  Future<void> _mostrarModalDobleConfirmacion(
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
            const Icon(Icons.verified_user_outlined, color: AppPalette.primary, size: 28),
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
          '¿Confirmas que el N° de Ingreso $numeroManual corresponde fielmente a la pieza que estás paletizando?',
          style: AppTypography.body.copyWith(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: AppTypography.button.copyWith(color: AppPalette.textSecondary),
            ),
          ),
          ElevatedButton(
            key: const Key('btn_aceptar_doble_confirmacion_paletizado'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppPalette.success),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );

    if (doubleConfirmed == true && mounted) {
      setState(() => _isValidatingOCR = true);

      List<File> fotosArchivos = _fotosComerciales.map((x) => File(x.path)).toList();

      final resultadoGuardado = await _paletizadoService.guardarPaletizadoDefinitivo(
        folio: numeroManual,
        tipoRepuesto: _tipoActivoSeleccionado,
        galpon: _galponController.text.trim(),
        pasillo: _pasilloController.text.trim(),
        pallet: _palletController.text.trim(),
        observaciones: _observacionController.text.trim(),
        cilindrada: _cilindradaController.text.trim(),
        combustible: _combustibleSeleccionado,
        transmisionTipo: _transmisionSeleccionada,
        numeroMotor: _numeroMotorController.text.trim(),
        traccion: _traccionSeleccionada,
        fotos: fotosArchivos,
      );

      if (!mounted) return;
      setState(() => _isValidatingOCR = false);

      if (resultadoGuardado != null) {
        final etiqueta = EtiquetaData.fromJson(resultadoGuardado);
        _limpiarFormulario();
        await _mostrarModalExito(etiqueta);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al guardar en el servidor. Revise la consola.'),
            backgroundColor: AppPalette.error,
          ),
        );
      }
    }
  }

  /// Limpia todos los campos del formulario para preparar la siguiente operación.
  void _limpiarFormulario() {
    setState(() {
      _searchController.clear();
      _vehiculoEncontrado = false;
      _galponController.clear();
      _pasilloController.clear();
      _palletController.clear();
      _observacionController.clear();
      _cilindradaController.clear();
      _numeroMotorController.clear();
      _combustibleSeleccionado = null;
      _transmisionSeleccionada = null;
      _traccionSeleccionada = null;
      _fotosComerciales.clear();
      _tipoActivoSeleccionado = 'Motor';
    });
  }

  // ── HU-2.4: Modal Bottom Sheet con 3 acciones post-guardado ──────────────
  //
  // Este método es el punto de entrada para el flujo de identidad digital.
  // Se invoca SOLO en caso de éxito, inyectando el [EtiquetaData] ya construido
  // para que los 3 botones puedan actuar sin otra llamada al backend.
  Future<void> _mostrarModalExito(EtiquetaData etiqueta) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isDismissible: false, // El operario debe elegir conscientemente
      enableDrag: false,
      builder: (ctx) => _ModalExitoContent(etiqueta: etiqueta),
    );
  }

  Future<void> _ejecutarFlujoForzado() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final vehiculo = await _paletizadoService.obtenerSiguienteParaForzar();

    if (mounted) Navigator.pop(context); // cerrar loading

    if (vehiculo != null && mounted) {
      Navigator.pushNamed(context, '/forzar-ingreso', arguments: vehiculo);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay vehículos vírgenes disponibles para forzar.'),
          backgroundColor: AppPalette.warning,
        ),
      );
    }
  }

  Future<void> _ejecutarBusqueda() async {
    if (_buscarPorNumeroMotor) {
      await _buscarPorMotor();
    } else {
      await _buscarVehiculo();
    }
  }

  Future<void> _buscarPorMotor() async {
    final motorTerm = _searchController.text.trim();
    if (motorTerm.isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _vehiculoEncontrado = false;
    });

    final res = await _paletizadoService.buscarVehiculoPorNumeroMotor(motorTerm);

    if (!mounted) return;

    if (res != null && res['numero_ingreso'] != null) {
      final numIngreso = res['numero_ingreso'].toString();
      _searchController.text = numIngreso;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Motor identificado. Corresponde al Folio N° $numIngreso'),
          backgroundColor: AppPalette.success,
          duration: const Duration(seconds: 3),
        ),
      );

      // Cambiar a modo ingreso y cargar los datos para el flujo normal de paletizado
      setState(() {
        _buscarPorNumeroMotor = false;
      });
      await _buscarVehiculo();
    } else {
      setState(() {
        _isLoading = false;
        _vehiculoEncontrado = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ No se encontró ningún vehículo con el N° de Motor "$motorTerm".'),
          backgroundColor: AppPalette.error,
        ),
      );
    }
  }

  Future<void> _buscarVehiculo() async {
    final folio = _searchController.text.trim();
    if (folio.isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _vehiculoEncontrado = false;
    });

    final consulta = await _paletizadoService.consultarIngresoParaPaletizado(folio);

    if (!mounted) return;

    if (consulta.exitoso && consulta.datos != null) {
      final datosVehiculo = consulta.datos!;
      final datosMotorTemp = datosVehiculo['motor'] ?? {};
      final datosCajaTemp = datosVehiculo['caja_cambios'] ?? {};

      List<String> opcionesDisponibles = [];
      if (datosMotorTemp['id_estado'] == 5 && datosMotorTemp['pendiente'] != false) {
        opcionesDisponibles.add('Motor');
      }
      if (datosCajaTemp['id_estado'] == 5 && datosCajaTemp['pendiente'] != false) {
        opcionesDisponibles.add('Caja de Cambios');
      }

      if (opcionesDisponibles.isEmpty) {
        setState(() {
          _isLoading = false;
          _vehiculoEncontrado = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El activo asociado a este número ya fue paletizado previamente o no requiere este flujo.'),
            backgroundColor: AppPalette.secondary,
          ),
        );
        return;
      }

      setState(() {
        _isLoading = false;
        _vehiculoEncontrado = true;

        final vehiculo = datosVehiculo['vehiculo'] ?? {};
        _marca = vehiculo['marca'] ?? 'Desconocida';
        _modelo = vehiculo['modelo'] ?? 'Desconocido';
        _anio = vehiculo['anio']?.toString() ?? 'S/A';

        _datosMotor = datosMotorTemp;
        _datosCaja = datosCajaTemp;

        _opcionesRepuestos = opcionesDisponibles;
        _tipoActivoSeleccionado = _opcionesRepuestos.isNotEmpty ? _opcionesRepuestos.first : 'Motor';
        _cargarCamposTecnicos();
      });
    } else {
      // Fallback a buscarVehiculoPorIngreso
      final fallbackDatos = await _paletizadoService.buscarVehiculoPorIngreso(folio);
      if (!mounted) return;

      if (fallbackDatos != null) {
        final datosMotorTemp = fallbackDatos['motor'] ?? {};
        final datosCajaTemp = fallbackDatos['caja_cambios'] ?? {};

        List<String> opcionesDisponibles = [];
        if (datosMotorTemp['id_estado'] == 5) opcionesDisponibles.add('Motor');
        if (datosCajaTemp['id_estado'] == 5) opcionesDisponibles.add('Caja de Cambios');

        if (opcionesDisponibles.isEmpty) {
          setState(() {
            _isLoading = false;
            _vehiculoEncontrado = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('El activo asociado a este número ya fue paletizado previamente o no requiere este flujo.'),
              backgroundColor: AppPalette.secondary,
            ),
          );
          return;
        }

        setState(() {
          _isLoading = false;
          _vehiculoEncontrado = true;

          final vehiculo = fallbackDatos['vehiculo'] ?? {};
          _marca = vehiculo['marca'] ?? 'Desconocida';
          _modelo = vehiculo['modelo'] ?? 'Desconocido';
          _anio = vehiculo['anio']?.toString() ?? 'S/A';

          _datosMotor = datosMotorTemp;
          _datosCaja = datosCajaTemp;
          _opcionesRepuestos = opcionesDisponibles;
          _tipoActivoSeleccionado = _opcionesRepuestos.first;
          _cargarCamposTecnicos();
        });
      } else {
        setState(() {
          _isLoading = false;
          _vehiculoEncontrado = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(consulta.mensajeError ?? 'Número de ingreso no encontrado en la base de datos.'),
            backgroundColor: AppPalette.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        backgroundColor: AppPalette.background,
        foregroundColor: AppPalette.textPrimary,
        iconTheme: const IconThemeData(color: AppPalette.textPrimary),
        title: const Text(
          'Paletizado y Enriquecimiento',
          style: AppTypography.title,
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 1. SELECTOR DE MODO DE BÚSQUEDA ──────────────────
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppPalette.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (_buscarPorNumeroMotor) {
                          setState(() {
                            _buscarPorNumeroMotor = false;
                            _searchController.clear();
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_buscarPorNumeroMotor ? AppPalette.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.tag,
                              size: 16,
                              color: !_buscarPorNumeroMotor ? AppPalette.textPrimary : AppPalette.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Por N° Ingreso',
                              style: AppTypography.button.copyWith(
                                color: !_buscarPorNumeroMotor ? AppPalette.textPrimary : AppPalette.textSecondary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (!_buscarPorNumeroMotor) {
                          setState(() {
                            _buscarPorNumeroMotor = true;
                            _searchController.clear();
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _buscarPorNumeroMotor ? AppPalette.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.precision_manufacturing_outlined,
                              size: 16,
                              color: _buscarPorNumeroMotor ? AppPalette.textPrimary : AppPalette.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Por N° Motor',
                              style: AppTypography.button.copyWith(
                                color: _buscarPorNumeroMotor ? AppPalette.textPrimary : AppPalette.textSecondary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── 2. CAMPO DE BÚSQUEDA ──────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: _buscarPorNumeroMotor
                          ? 'Ingresar N° Motor grabado (ej. G4KEAH...)'
                          : 'Buscar N° Ingreso...',
                      prefixIcon: Icon(
                        _buscarPorNumeroMotor
                            ? Icons.precision_manufacturing_outlined
                            : Icons.search,
                        color: AppPalette.primary,
                      ),
                    ),
                    onSubmitted: (_) => _ejecutarBusqueda(),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 55,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: _isLoading ? null : _ejecutarBusqueda,
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.arrow_forward),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // ── 2. FORMULARIO LOGÍSTICO ───────────────────────────
            if (_vehiculoEncontrado) ...[
              // Banner de información destacada
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('VEHÍCULO ORIGEN', style: AppTypography.small),
                        InkWell(
                          onTap: _limpiarFormulario,
                          child: Text(
                            'Volver a la lista',
                            style: AppTypography.small.copyWith(
                              color: AppPalette.secondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_marca $_modelo',
                      style: AppTypography.headline.copyWith(
                        color: AppPalette.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text('Año: $_anio', style: AppTypography.title),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              const Text('Datos del Activo a Paletizar', style: AppTypography.title),
              const SizedBox(height: 16),

              // ── Selector Segmentado de Tipo de Repuesto ([ Motor ] / [ Caja de Cambios ]) ──
              if (_opcionesRepuestos.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppPalette.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Row(
                    children: [
                      if (_opcionesRepuestos.contains('Motor'))
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _tipoActivoSeleccionado = 'Motor';
                                _cargarCamposTecnicos();
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _tipoActivoSeleccionado == 'Motor'
                                    ? AppPalette.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.settings,
                                    size: 18,
                                    color: _tipoActivoSeleccionado == 'Motor'
                                        ? AppPalette.textPrimary
                                        : AppPalette.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Motor',
                                    style: AppTypography.button.copyWith(
                                      color: _tipoActivoSeleccionado == 'Motor'
                                          ? AppPalette.textPrimary
                                          : AppPalette.textSecondary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_opcionesRepuestos.contains('Caja de Cambios')) ...[
                        if (_opcionesRepuestos.contains('Motor')) const SizedBox(width: 6),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _tipoActivoSeleccionado = 'Caja de Cambios';
                                _cargarCamposTecnicos();
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _tipoActivoSeleccionado == 'Caja de Cambios'
                                    ? AppPalette.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.swap_horiz,
                                    size: 18,
                                    color: _tipoActivoSeleccionado == 'Caja de Cambios'
                                        ? AppPalette.textPrimary
                                        : AppPalette.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Caja de Cambios',
                                    style: AppTypography.button.copyWith(
                                      color: _tipoActivoSeleccionado == 'Caja de Cambios'
                                          ? AppPalette.textPrimary
                                          : AppPalette.textSecondary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppPalette.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.edit_note, color: AppPalette.primary, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Especificaciones Técnicas (Editables)',
                                style: AppTypography.title.copyWith(
                                  color: AppPalette.primary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Modifica antes de etiquetar',
                                style: AppTypography.small.copyWith(
                                  color: AppPalette.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (_tipoActivoSeleccionado == 'Motor') ...[
                      _buildTextField(
                        _numeroMotorController,
                        'N° Motor grabado',
                        Icons.precision_manufacturing_outlined,
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        _cilindradaController,
                        'Cilindrada (ej: 2.0L)',
                        Icons.speed,
                      ),
                      const SizedBox(height: 12),
                      _buildDropdownField(
                        label: 'Combustible',
                        value: _combustibleSeleccionado,
                        items: OpcionesCombustible.lista,
                        icon: Icons.local_gas_station_outlined,
                        onChanged: (val) => setState(() => _combustibleSeleccionado = val),
                      ),
                      const SizedBox(height: 12),
                      _buildDropdownField(
                        label: 'Transmisión',
                        value: _transmisionSeleccionada,
                        items: OpcionesTransmision.lista,
                        icon: Icons.settings_outlined,
                        onChanged: (val) => setState(() => _transmisionSeleccionada = val),
                      ),
                      const SizedBox(height: 12),
                      _buildDropdownField(
                        label: 'Tracción',
                        value: _traccionSeleccionada,
                        items: OpcionesTraccion.lista,
                        icon: Icons.swap_calls_outlined,
                        onChanged: (val) => setState(() => _traccionSeleccionada = val),
                      ),
                    ] else if (_tipoActivoSeleccionado == 'Caja de Cambios') ...[
                      _buildDropdownField(
                        label: 'Transmisión',
                        value: _transmisionSeleccionada,
                        items: OpcionesTransmision.lista,
                        icon: Icons.settings_outlined,
                        onChanged: (val) => setState(() => _transmisionSeleccionada = val),
                      ),
                      const SizedBox(height: 12),
                      _buildDropdownField(
                        label: 'Tracción',
                        value: _traccionSeleccionada,
                        items: OpcionesTraccion.lista,
                        icon: Icons.swap_calls_outlined,
                        onChanged: (val) => setState(() => _traccionSeleccionada = val),
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        _cilindradaController,
                        'Cilindrada (ej: 2.0L)',
                        Icons.speed,
                      ),
                      const SizedBox(height: 12),
                      _buildDropdownField(
                        label: 'Combustible',
                        value: _combustibleSeleccionado,
                        items: OpcionesCombustible.lista,
                        icon: Icons.local_gas_station_outlined,
                        onChanged: (val) => setState(() => _combustibleSeleccionado = val),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              const Text('Ubicación Física', style: AppTypography.title),
              const SizedBox(height: 16),

              _buildDropdownLocationField(
                label: 'Galpón',
                value: _galponController.text,
                items: OpcionesUbicacionBodega.galpones,
                icon: Icons.warehouse,
                onChanged: (val) {
                  setState(() {
                    _galponController.text = val ?? '';
                  });
                },
              ),
              const SizedBox(height: 16),
              _buildDropdownLocationField(
                label: 'Pasillo',
                value: _pasilloController.text,
                items: OpcionesUbicacionBodega.pasillos,
                icon: Icons.view_column,
                onChanged: (val) {
                  setState(() {
                    _pasilloController.text = val ?? '';
                  });
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(_palletController, 'Pallet', Icons.layers),
              const SizedBox(height: 16),
              _buildTextField(
                _observacionController,
                'Observación del estado (Opcional)',
                Icons.note_alt_outlined,
                maxLines: 3,
              ),

              const SizedBox(height: 32),

              // ── C. CATÁLOGO COMERCIAL ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Catálogo Comercial (Max. 10)', style: AppTypography.title),
                  Text(
                    '${_fotosComerciales.length}/10',
                    style: AppTypography.small.copyWith(
                      color: _fotosComerciales.length == 10
                          ? AppPalette.secondary
                          : AppPalette.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Carrusel Horizontal de Fotos
              SizedBox(
                height: 140,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _fotosComerciales.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: InkWell(
                          onTap: _tomarFotoComercial,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 110,
                            decoration: BoxDecoration(
                              color: AppPalette.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppPalette.primary,
                                width: 2,
                              ),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.camera_alt,
                                  color: AppPalette.primary,
                                  size: 36,
                                ),
                                SizedBox(height: 8),
                                Text('Agregar', style: AppTypography.small),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    final fotoIndex = index - 1;
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              File(_fotosComerciales[fotoIndex].path),
                              width: 110,
                              height: 140,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _eliminarFoto(fotoIndex),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppPalette.error,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 40),

              // Botón Final
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isValidatingOCR ? null : _validarYGuardar,
                  icon: _isValidatingOCR
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.camera_alt, color: Colors.white),
                  label: Text(
                    _isValidatingOCR
                        ? 'ANALIZANDO CON IA...'
                        : 'VALIDAR CON OCR Y GUARDAR',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.primary,
                  ),
                ),
              ),
            ] else ...[
              // ── 2. MODO DE PALETIZADO DIRECTO (SPEC-HU-TAREA-14) ──
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 16.0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                    decoration: BoxDecoration(
                      color: AppPalette.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppPalette.primary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.inventory_2_outlined,
                            color: AppPalette.primary,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Modo de Paletizado Directo',
                          style: AppTypography.cardTitle.copyWith(fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Ingresa el número de ingreso físico en el buscador superior para cargar de inmediato los datos del vehículo y enriquecer sus repuestos.',
                          style: AppTypography.body.copyWith(
                            fontSize: 13,
                            color: AppPalette.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // ── 3. BOTÓN / SECCIÓN DE PALETIZADO FORZADO ──
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppPalette.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppPalette.warning.withValues(alpha: 0.35),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppPalette.warning.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                color: AppPalette.warning,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Forzado de Ingreso',
                                    style: AppTypography.title.copyWith(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: AppPalette.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Para repuestos sin N° de ingreso físico o sin trazabilidad',
                                    style: AppTypography.small.copyWith(
                                      fontSize: 11,
                                      color: AppPalette.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppPalette.warning,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 0,
                            ),
                            onPressed: _isLoading ? null : _ejecutarFlujoForzado,
                            icon: const Icon(Icons.bolt, color: Colors.black, size: 20),
                            label: Text(
                              'FORZAR PALETIZADO',
                              style: AppTypography.button.copyWith(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
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
    return DropdownButtonFormField<String>(
      initialValue: validValue,
      dropdownColor: AppPalette.surface,
      style: const TextStyle(color: AppPalette.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppPalette.primary, size: 20),
      ),
      items: items.map((item) {
        return DropdownMenuItem<String>(
          value: item,
          child: Text(item),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildDropdownLocationField({
    required String label,
    required String? value,
    required List<String> items,
    required IconData icon,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: (value != null && value.isNotEmpty && items.contains(value)) ? value : null,
      dropdownColor: AppPalette.surface,
      style: const TextStyle(color: AppPalette.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppPalette.primary, size: 20),
      ),
      items: items.map((item) {
        return DropdownMenuItem<String>(
          value: item,
          child: Text(label == 'Galpón' ? 'Galpón $item' : 'Pasillo $item'),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: AppPalette.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppPalette.primary, size: 20),
      ),
    );
  }
}

// ── HU-2.4: Widget del Modal Bottom Sheet con las 3 acciones ─────────────────
//
// Se extrae como un StatefulWidget separado para encapsular su propio estado
// (ej. el indicador de carga del botón "Imprimir Ahora") sin contaminar
// el estado de PaletizadoScreen.
class _ModalExitoContent extends StatefulWidget {
  final EtiquetaData etiqueta;
  const _ModalExitoContent({required this.etiqueta});

  @override
  State<_ModalExitoContent> createState() => _ModalExitoContentState();
}

class _ModalExitoContentState extends State<_ModalExitoContent> {
  bool _isConnecting = false;
  final PaletizadoService _paletizadoService = PaletizadoService();

  Future<void> _ejecutarImpresion() async {
    bool exito = false;

    while (!exito && mounted) {
      setState(() => _isConnecting = true);

      try {
        exito = await PrintService.imprimirEtiqueta(widget.etiqueta);
      } on PrinterException catch (e) {
        debugPrint('📌 [PALETIZADO_SCREEN] ❌ Error de dominio de impresora: ${e.mensaje}');
        if (!mounted) break;
        setState(() => _isConnecting = false);

        // Modal interactivo de diagnóstico con instrucciones físicas
        final reintentar = await DialogoFallaImpresora.mostrar(context, e);
        if (!reintentar || !mounted) {
          return;
        }
        continue;
      } catch (e) {
        debugPrint('📌 [PALETIZADO_SCREEN] ❌ Excepción no controlada: $e');
        if (!mounted) break;
        setState(() => _isConnecting = false);

        final reintentar = await DialogoFallaImpresora.mostrar(
          context,
          PrinterCommunicationException(
            'Error inesperado de comunicación con la impresora térmica.',
            e,
          ),
        );
        if (!reintentar || !mounted) {
          return;
        }
        continue;
      } finally {
        if (mounted && !exito) {
          setState(() => _isConnecting = false);
        }
      }
    }

    if (!mounted || !exito) return;

    // Confirmación en Backend (PATCH qr_impreso = true)
    await _paletizadoService.confirmarQrImpreso(widget.etiqueta.idActivo);

    if (!mounted) return;
    Navigator.of(context).pop(); // Cierra el modal
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ Etiqueta impresa y registrada. SKU: ${widget.etiqueta.skuQrFisico}',
        ),
        backgroundColor: AppPalette.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Indicador visual del modal ────────────────────────────────────
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppPalette.neutral,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // ── Ícono y título de éxito ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppPalette.success,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 16),
          Text(
            '¡Activo Guardado!',
            style: AppTypography.headline.copyWith(
              color: AppPalette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'SKU: ${widget.etiqueta.skuQrFisico}  •  Folio N° ${widget.etiqueta.numeroIngreso}',
            style: AppTypography.small.copyWith(color: AppPalette.primary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // ── Botón 1: Imprimir Ahora ───────────────────────────────────────
          // Impresión térmica industrial vía Sockets TCP (Puerto 9100 / ZPL).
          // Ver: lib/features/paletizado/services/print_service.dart
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isConnecting ? null : _ejecutarImpresion,
              icon: _isConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.print, color: Colors.white),
              label: Text(_isConnecting ? 'CONECTANDO...' : 'Imprimir Ahora'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Botón 2: Ver Tarjeta ──────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop(); // Cierra el modal
                // Navega a la pantalla de previsualización con los datos de la etiqueta
                Navigator.of(
                  context,
                ).pushNamed('/etiqueta-preview', arguments: widget.etiqueta);
              },
              icon: const Icon(Icons.qr_code_2, color: AppPalette.primary),
              label: const Text(
                'Ver Tarjeta',
                style: TextStyle(color: AppPalette.primary),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppPalette.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Botón 3: Hacerlo más tarde ────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Hacerlo más tarde',
                style: TextStyle(color: AppPalette.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
