import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../auth/services/auth_service.dart';
import '../../../paletizado/domain/models/etiqueta_data.dart';
import '../../services/inventario_service.dart';
import '../widgets/editar_activo_modal.dart';
import '../widgets/dialogo_despaletizar.dart';

class DetalleActivoScreen extends StatefulWidget {
  final Map<String, dynamic> activo;

  const DetalleActivoScreen({super.key, required this.activo});

  @override
  State<DetalleActivoScreen> createState() => _DetalleActivoScreenState();
}

class _DetalleActivoScreenState extends State<DetalleActivoScreen> {
  int _currentImageIndex = 0;
  bool _isUploadingPhoto = false;
  final ImagePicker _picker = ImagePicker();

  // Refleja localmente el estado qr_impreso para actualizar el botón
  // sin tener que recargar toda la pantalla desde el backend.
  late bool _qrImpreso;
  late Map<String, dynamic> _activo;
  bool _puedeEditar = false;

  @override
  void initState() {
    super.initState();
    _activo = Map<String, dynamic>.from(widget.activo);
    _qrImpreso = _activo['qr_impreso'] as bool? ?? false;
    _verificarRolUsuario();
  }

  bool get _esEstadoEditable {
    final estado = (_activo['estado'] ?? '').toString().toUpperCase();
    return estado == 'DISPONIBLE' || estado == 'PALETIZADO';
  }

  Future<void> _verificarRolUsuario() async {
    final idRol = await AuthService.getIdRol();
    final rol = await AuthService.getRol();
    final rLower = rol?.toLowerCase() ?? '';
    final esBodegueroOAdmin = idRol == 1 ||
        idRol == 5 ||
        rLower == 'bodeguero' ||
        rLower == 'administrador' ||
        rLower == 'admin';

    if (mounted) {
      setState(() {
        _puedeEditar = esBodegueroOAdmin;
      });
    }
  }

  Future<void> _abrirModalEdicion() async {
    final resultado = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditarActivoModal(activo: _activo),
    );

    if (!mounted || resultado == null) return;

    if (resultado['conflict'] == true) {
      return;
    }

    setState(() {
      if (resultado['ubicacion_pasillo'] != null) {
        _activo['pasillo'] = resultado['ubicacion_pasillo'];
        _activo['ubicacion_pasillo'] = resultado['ubicacion_pasillo'];
      }
      if (resultado['ubicacion_pallet'] != null) {
        _activo['pallet'] = resultado['ubicacion_pallet'];
        _activo['ubicacion_pallet'] = resultado['ubicacion_pallet'];
      }
      if (resultado['ubicacion_galpon'] != null) {
        _activo['galpon'] = resultado['ubicacion_galpon'];
        _activo['ubicacion_galpon'] = resultado['ubicacion_galpon'];
      }
      if (resultado['observacion_estado'] != null) {
        _activo['observacion'] = resultado['observacion_estado'];
        _activo['observacion_estado'] = resultado['observacion_estado'];
      }
      if (resultado['numero_motor'] != null) {
        _activo['numero_motor'] = resultado['numero_motor'];
      }
      if (resultado['cilindrada'] != null) {
        _activo['cilindrada'] = resultado['cilindrada'];
      }
      if (resultado['combustible'] != null) {
        _activo['combustible'] = resultado['combustible'];
      }
      if (resultado['transmision'] != null) {
        _activo['transmision'] = resultado['transmision'];
        _activo['transmision_tipo'] = resultado['transmision'];
      }
      if (resultado['traccion'] != null) {
        _activo['traccion'] = resultado['traccion'];
      }
      if (resultado['marca'] != null && resultado['marca'].toString().isNotEmpty) {
        _activo['marca'] = resultado['marca'];
      }
      if (resultado['modelo'] != null && resultado['modelo'].toString().isNotEmpty) {
        _activo['modelo'] = resultado['modelo'];
      }
      if (resultado['anio'] != null) {
        _activo['anio'] = resultado['anio'];
      }
      if (resultado['version_lock'] != null) {
        _activo['version_lock'] = resultado['version_lock'];
      }
    });
  }

  Future<void> _confirmarDespaletizado() async {
    final idActivo = _activo['id_activo']?.toString() ?? '';
    final sku = _activo['sku']?.toString() ?? _activo['sku_qr_fisico']?.toString() ?? 'S/N';
    final categoria = _activo['categoria']?.toString() ?? 'Repuesto';
    final numeroIngreso = _activo['numero_ingreso']?.toString();

    final exito = await DialogoDespaletizar.mostrar(
      context,
      idActivo: idActivo,
      sku: sku,
      categoria: categoria,
      numeroIngreso: numeroIngreso,
    );

    if (exito == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Repuesto $sku despaletizado exitosamente. Ha retornado a "En Desarme".',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppPalette.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop({'despaletizado': true, 'id_activo': idActivo});
    }
  }

  Future<void> _subirNuevaFoto(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 75,
      );
      if (picked == null) return;

      setState(() => _isUploadingPhoto = true);
      final idActivo = _activo['id_activo']?.toString() ?? '';
      final updatedImgs = await InventarioService.subirFotosActivo(
        idActivo,
        [File(picked.path)],
      );

      if (!mounted) return;
      setState(() {
        _isUploadingPhoto = false;
        _activo['imagenes'] = updatedImgs;
        _currentImageIndex = updatedImgs.isNotEmpty ? updatedImgs.length - 1 : 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fotografía agregada exitosamente.'),
          backgroundColor: AppPalette.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al subir foto: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _eliminarFotoActual(String url) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        title: Row(
          children: [
            const Icon(Icons.delete_forever, color: AppPalette.error, size: 28),
            const SizedBox(width: 8),
            Text('Eliminar Fotografía', style: AppTypography.title.copyWith(color: AppPalette.textPrimary)),
          ],
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar esta fotografía del activo? Esta acción no se puede deshacer.',
          style: AppTypography.body.copyWith(color: AppPalette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar', style: AppTypography.button.copyWith(color: AppPalette.neutral)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppPalette.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final idActivo = _activo['id_activo']?.toString() ?? '';
      final updatedImgs = await InventarioService.eliminarFotoActivo(idActivo, url);

      if (!mounted) return;
      setState(() {
        _isUploadingPhoto = false;
        _activo['imagenes'] = updatedImgs;
        _currentImageIndex = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fotografía eliminada exitosamente.'),
          backgroundColor: AppPalette.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar foto: ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _mostrarOpcionesAgregarFoto() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Agregar Fotografía Comercial',
                style: AppTypography.title.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, color: AppPalette.primary),
                title: const Text('Tomar Foto con Cámara', style: AppTypography.body),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _subirNuevaFoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppPalette.primary),
                title: const Text('Elegir de la Galería', style: AppTypography.body),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _subirNuevaFoto(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatearUbicacionHumana() {
    final pasillo = (_activo['pasillo'] ?? _activo['ubicacion_pasillo'])?.toString().trim() ?? '';
    final pallet = (_activo['pallet'] ?? _activo['ubicacion_pallet'])?.toString().trim() ?? '';
    final galpon = (_activo['galpon'] ?? _activo['ubicacion_galpon'])?.toString().trim() ?? '';

    final bool tienePasillo = pasillo.isNotEmpty && pasillo != 'S/P' && pasillo != 'null';
    final bool tienePallet = pallet.isNotEmpty && pallet != 'S/P' && pallet != 'null';
    final bool tieneGalpon = galpon.isNotEmpty && galpon != 'S/G' && galpon != 'null';

    if (!tienePasillo && !tienePallet && !tieneGalpon) {
      final rawUbicacion = _activo['ubicacion']?.toString().trim() ?? '';
      if (rawUbicacion.isNotEmpty &&
          rawUbicacion != 'S/P - S/P' &&
          rawUbicacion != 'No asignada' &&
          rawUbicacion != 'null') {
        return rawUbicacion;
      }
      return 'Sin Paletizar / Sin Ubicación Asignada';
    }

    final pStr = tienePasillo ? pasillo : 'S/P';
    final paStr = tienePallet ? pallet : 'S/P';
    final gStr = tieneGalpon ? galpon : 'S/G';

    return 'Pasillo: $pStr | Pallet: $paStr | Galpón: $gStr';
  }

  @override
  Widget build(BuildContext context) {
    final String categoria = _activo['categoria']?.toString() ?? 'Activo';
    final bool esMotor =
        categoria.toUpperCase() == 'MOTOR' ||
        categoria.toUpperCase() == 'MOTORES';
    final int idCategoria = (_activo['id_categoria'] ?? _activo['idCategoria']) as int? ??
        (esMotor ? 1 : (categoria.toUpperCase().contains('CAJA') ? 2 : 0));

    final String marca = _activo['marca']?.toString() ?? 'Desconocida';
    final String modelo = _activo['modelo']?.toString() ?? 'Desconocido';
    final String? anio = (_activo['anio'] ?? _activo['ano'] ?? _activo['vehiculo']?['anio'])?.toString();
    final String sku = _activo['sku']?.toString() ?? 'S/N';
    final String estado = _activo['estado']?.toString() ?? 'DISPONIBLE';

    final String numeroIngreso =
        _activo['numero_ingreso']?.toString() ?? 'N/A';

    final String? numeroMotor =
        (_activo['numero_motor'] ?? _activo['numeroMotor'])?.toString();
    final String? traccion = _activo['traccion']?.toString();
    final String cilindrada = _activo['cilindrada']?.toString() ?? 'N/A';
    final String combustible =
        _activo['combustible']?.toString() ?? 'N/A';
    final String transmision =
        (_activo['transmision'] ?? _activo['transmision_tipo'] ?? _activo['transmisionTipo'])?.toString() ?? 'N/A';
    final String observacion =
        _activo['observacion']?.toString() ??
        'Sin observaciones registradas.';

    final List<dynamic> rawImages = _activo['imagenes'] ?? [];
    final List<String> imagenesReales = rawImages.isNotEmpty
        ? rawImages.map((e) => e.toString()).toList()
        : ['NO_IMAGE'];

    final etiqueta = EtiquetaData.fromMap(_activo);

    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        title: Text(
          'Detalle de $categoria',
          style: AppTypography.title.copyWith(color: AppPalette.textPrimary, fontSize: 18),
        ),
        backgroundColor: AppPalette.surface,
        foregroundColor: AppPalette.textPrimary,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppPalette.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Volver',
        ),
        actions: [
          if (_puedeEditar && _esEstadoEditable) ...[
            IconButton(
              key: const Key('btn_despaletizar_activo'),
              icon: const Icon(Icons.undo_rounded, color: AppPalette.error, size: 24),
              tooltip: 'Despaletizar (Revertir a Desarme)',
              onPressed: _confirmarDespaletizado,
            ),
            IconButton(
              key: const Key('btn_editar_activo'),
              icon: const Icon(Icons.edit_note, color: AppPalette.primary, size: 26),
              tooltip: 'Editar datos y ubicación',
              onPressed: _abrirModalEdicion,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildBadgeEstado(estado),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppPalette.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppPalette.neutral.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          'ID: $sku',
                          style: AppTypography.small.copyWith(
                            color: AppPalette.textSecondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  RichText(
                    text: TextSpan(
                      style: AppTypography.headline.copyWith(fontSize: 26, fontWeight: FontWeight.bold),
                      children: [
                        TextSpan(
                          text: '$marca ',
                          style: const TextStyle(color: Colors.white),
                        ),
                        TextSpan(
                          text: (anio != null && anio.isNotEmpty && anio != '0' && anio != 'null' && anio != 'S/A')
                              ? '$modelo ($anio)'
                              : modelo,
                          style: const TextStyle(color: AppPalette.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── CARRUSEL DE IMÁGENES CON FALLBACK NATIVO ──
            SizedBox(
              height: 260,
              child: PageView.builder(
                itemCount: imagenesReales.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentImageIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  if (imagenesReales[index].startsWith('http')) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16.0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        image: DecorationImage(
                          image: NetworkImage(imagenesReales[index]),
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  } else {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16.0),
                      decoration: BoxDecoration(
                        color: AppPalette.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppPalette.neutral.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.image_not_supported_outlined,
                              color: AppPalette.textSecondary,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Sin registro fotográfico',
                              style: AppTypography.small.copyWith(
                                color: AppPalette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                imagenesReales.length,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentImageIndex == index
                        ? AppPalette.primary
                        : AppPalette.neutral.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
            if (_isUploadingPhoto) ...[
              const SizedBox(height: 12),
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppPalette.primary),
                ),
              ),
            ],
            if (_puedeEditar && _esEstadoEditable) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('btn_agregar_foto_activo'),
                        onPressed: _isUploadingPhoto ? null : _mostrarOpcionesAgregarFoto,
                        icon: const Icon(Icons.add_a_photo_outlined, size: 18, color: AppPalette.primary),
                        label: Text(
                          'Añadir Foto',
                          style: AppTypography.button.copyWith(color: AppPalette.primary, fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppPalette.primary),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    if (imagenesReales.isNotEmpty &&
                        _currentImageIndex < imagenesReales.length &&
                        imagenesReales[_currentImageIndex].startsWith('http')) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('btn_eliminar_foto_activo'),
                          onPressed: _isUploadingPhoto
                              ? null
                              : () => _eliminarFotoActual(imagenesReales[_currentImageIndex]),
                          icon: const Icon(Icons.delete_outline, size: 18, color: AppPalette.error),
                          label: Text(
                            'Eliminar Foto',
                            style: AppTypography.button.copyWith(color: AppPalette.error, fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppPalette.error),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── VALORACIÓN COMERCIAL (RANGO DE PRECIO) ──
                  Builder(
                    builder: (context) {
                      final pMin = _activo['precio_minimo'] as int?;
                      final pMax = _activo['precio_maximo'] as int? ?? _activo['precio_referencia'] as int?;
                      final pRef = _activo['precio_referencia'] as int?;
                      if (pMin == null && pMax == null && pRef == null) {
                        return const SizedBox.shrink();
                      }

                      final minStr = pMin != null && pMin > 0 ? CurrencyFormatter.formatNumber(pMin) : null;
                      final maxStr = pMax != null && pMax > 0 ? CurrencyFormatter.formatNumber(pMax) : null;
                      final refStr = pRef != null && pRef > 0 ? CurrencyFormatter.formatNumber(pRef) : null;

                      String rangoDisplay = 'Sin tasación';
                      if (minStr != null && maxStr != null) {
                        rangoDisplay = minStr == maxStr ? '\$$minStr' : '\$$minStr - \$$maxStr';
                      } else if (refStr != null) {
                        rangoDisplay = '\$$refStr';
                      }

                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppPalette.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppPalette.secondary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppPalette.secondary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.price_change_outlined,
                                color: AppPalette.secondary,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'VALORACIÓN COMERCIAL (RANGO TASADO)',
                                    style: AppTypography.small.copyWith(
                                      color: AppPalette.textSecondary,
                                      letterSpacing: 1.0,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    rangoDisplay,
                                    style: AppTypography.title.copyWith(
                                      color: AppPalette.secondary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (maxStr != null && minStr != null && minStr != maxStr) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Sugerido lista: \$$maxStr | Piso: \$$minStr',
                                      style: AppTypography.small.copyWith(
                                        color: AppPalette.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppPalette.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppPalette.primary.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'UBICACIÓN ACTUAL',
                                    style: AppTypography.small.copyWith(
                                      color: AppPalette.textSecondary,
                                      letterSpacing: 1.2,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _formatearUbicacionHumana(),
                                    style: AppTypography.title.copyWith(
                                      color: AppPalette.primary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppPalette.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: AppPalette.primary,
                                size: 26,
                              ),
                            ),
                          ],
                        ),
                        if (_puedeEditar && _esEstadoEditable) ...[
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              key: const Key('btn_editar_ubicacion_card'),
                              onPressed: _abrirModalEdicion,
                              icon: const Icon(Icons.edit_location_alt_outlined, size: 16, color: AppPalette.primary),
                              label: Text(
                                'Editar Galpón, Pasillo y Pallet',
                                style: AppTypography.button.copyWith(color: AppPalette.primary, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: AppPalette.primary.withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  Text(
                    'ESPECIFICACIONES TÉCNICAS',
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textSecondary,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),

                  _buildSpecCard('Nº DE INGRESO VEHÍCULO', numeroIngreso),
                  if (anio != null && anio.isNotEmpty && anio != '0' && anio != 'null' && anio != 'S/A')
                    _buildSpecCard('AÑO DEL VEHÍCULO', anio),

                  if (idCategoria == 1 && numeroMotor != null && numeroMotor.isNotEmpty && numeroMotor != 'N/A' && numeroMotor != 'S/A' && numeroMotor != 'null')
                    _buildSpecCard('Número de Motor', numeroMotor),

                  // Renderizado dinámico de especificaciones técnicas compartidas (SPEC-HU-TAREA-17)
                  ...[
                    if (cilindrada.isNotEmpty && cilindrada != 'N/A' && cilindrada != 'S/A' && cilindrada != 'null')
                      {'titulo': 'CILINDRADA', 'valor': cilindrada},
                    if (combustible.isNotEmpty && combustible != 'N/A' && combustible != 'S/A' && combustible != 'null')
                      {'titulo': 'COMBUSTIBLE', 'valor': combustible},
                    if (transmision.isNotEmpty && transmision != 'N/A' && transmision != 'S/A' && transmision != 'null')
                      {'titulo': 'TRANSMISIÓN', 'valor': transmision},
                    if (traccion != null && traccion.isNotEmpty && traccion != 'N/A' && traccion != 'S/A' && traccion != 'null')
                      {'titulo': 'TRACCIÓN', 'valor': traccion},
                  ].map((spec) => _buildSpecCard(spec['titulo']!, spec['valor']!)),

                  Container(
                    margin: const EdgeInsets.only(bottom: 28),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppPalette.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppPalette.neutral.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.description_outlined,
                            color: AppPalette.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Observación',
                                style: AppTypography.body.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                observacion,
                                style: AppTypography.small.copyWith(
                                  color: AppPalette.textPrimary,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Botón de Impresión / Reimpresión (HU-2.4 Fase 4) ──
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final resultado = await Navigator.of(
                          context,
                        ).pushNamed('/etiqueta-preview', arguments: etiqueta);

                        if (resultado == true && mounted) {
                          setState(() => _qrImpreso = true);
                        }
                      },
                      icon: Icon(
                        _qrImpreso ? Icons.replay : Icons.qr_code_scanner,
                        color: Colors.white,
                      ),
                      label: Text(
                        _qrImpreso
                            ? 'REIMPRIMIR ETIQUETA QR'
                            : 'IMPRIMIR ETIQUETA QR',
                        style: AppTypography.button.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _qrImpreso
                            ? AppPalette.secondary
                            : AppPalette.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  if (_puedeEditar && _esEstadoEditable) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        key: const Key('btn_editar_activo_bottom'),
                        onPressed: _abrirModalEdicion,
                        icon: const Icon(Icons.edit_note, color: Colors.white, size: 22),
                        label: Text(
                          'EDITAR UBICACIÓN (PASILLO, PALLET, GALPÓN) Y DATOS',
                          style: AppTypography.button.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppPalette.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        key: const Key('btn_despaletizar_activo_bottom'),
                        onPressed: _confirmarDespaletizado,
                        icon: const Icon(Icons.undo_rounded, color: AppPalette.error, size: 18),
                        label: Text(
                          'DESPALETIZAR (REVERTIR A DESARME)',
                          style: AppTypography.button.copyWith(
                            color: AppPalette.error,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppPalette.error.withValues(alpha: 0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.list_alt, color: Colors.white, size: 18),
                      label: Text(
                        'VOLVER AL LISTADO',
                        style: AppTypography.button.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: AppPalette.neutral.withValues(alpha: 0.3),
                        ),
                        backgroundColor: AppPalette.background,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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

  Widget _buildSpecCard(String title, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.small.copyWith(
              color: AppPalette.textSecondary,
              fontSize: 9,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.bold,
              color: AppPalette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeEstado(String estado) {
    Color estadoColor;
    switch (estado.toUpperCase()) {
      case 'DISPONIBLE':
        estadoColor = AppPalette.success;
        break;
      case 'VENDIDO':
        estadoColor = AppPalette.secondary;
        break;
      case 'RESERVADO':
        estadoColor = Colors.orange;
        break;
      default:
        estadoColor = AppPalette.neutral;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: estadoColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: estadoColor, width: 1),
      ),
      child: Text(
        estado.toUpperCase(),
        style: AppTypography.small.copyWith(
          color: estadoColor,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }
}
