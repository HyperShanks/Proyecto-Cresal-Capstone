// lib/features/ventas/presentation/screens/detalle_activo_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../controllers/cart_controller.dart';
import '../../models/catalogo_model.dart';
import '../../services/carrito_service.dart';
import '../widgets/visor_imagen_completa_dialog.dart';
import '../widgets/cart_fly_animation.dart';
import '../../../../core/widgets/glass_snackbar.dart';

/// Pantalla Completa de Detalle del Repuesto (HU-3.2 / Fase 3 Mesón de Ventas).
/// Incluye carrusel de imágenes en gran formato con indicador interactivo,
/// ficha técnica detallada y barra inferior fija con acción de 'Agregar al Carrito'.
class DetalleActivoScreen extends StatefulWidget {
  final CatalogoItem item;
  final int? vendedorSucursalId;
  final http.Client? httpClient;

  const DetalleActivoScreen({
    super.key,
    required this.item,
    this.vendedorSucursalId,
    this.httpClient,
  });

  @override
  State<DetalleActivoScreen> createState() => _DetalleActivoScreenState();
}

class _DetalleActivoScreenState extends State<DetalleActivoScreen> {
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;
  late CatalogoItem _currentItem;
  bool _isAdding = false;

  bool get _esMismaSucursal =>
      widget.vendedorSucursalId != null &&
      _currentItem.idSucursalActual == widget.vendedorSucursalId;

  @override
  void initState() {
    super.initState();
    _currentItem = widget.item;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _onAddToCart() async {
    if (_isAdding) return;

    if (_currentItem.esReservado) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppPalette.surface,
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppPalette.error,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '¡Lo sentimos! Este repuesto acaba de ser reservado por otro vendedor hace un instante.',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    if (CartController.instance.estaEnCarrito(_currentItem.idActivo)) {
      GlassSnackbar.mostrar(
        context,
        mensaje: 'Este activo ya está en el carrito',
        icono: Icons.info_outline,
        colorIcono: AppPalette.secondary,
      );
      return;
    }

    if (CartController.instance.tieneVentaEnVerde) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
          content: Text(
            'No se pueden combinar productos con una Venta en Verde. Las ventas en verde van solas en el pedido.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isAdding = true;
    });

    try {
      final reserva = await CarritoService.reservarActivo(
        _currentItem.idActivo,
        _currentItem.versionLock,
        client: widget.httpClient,
      );

      final updatedItem = _currentItem.copyWith(
        versionLock: reserva['version_lock'] as int? ?? (_currentItem.versionLock + 1),
      );

      if (mounted) {
        setState(() {
          _currentItem = updatedItem;
        });
      }

      final agregado = CartController.instance.agregarInventariado(updatedItem);

      if (!mounted) return;

      GlassSnackbar.mostrar(
        context,
        mensaje: agregado
            ? '${updatedItem.tituloRepuesto} agregado al carrito'
            : 'Este activo ya está en el carrito',
        icono: agregado ? Icons.check_circle_outline_rounded : Icons.info_outline,
        colorIcono: agregado ? AppPalette.primary : AppPalette.secondary,
      );

      if (agregado && mounted) {
        Navigator.of(context).pop();
      }
    } on CarritoException catch (e) {
      if (!mounted) return;

      if (e.statusCode == 409 || e.errorCode == 'RESERVATION_COLLISION') {
        setState(() {
          _currentItem = _currentItem.copyWith(
            idEstado: 2,
            estadoActivo: 'Reservado',
          );
        });
      }

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppPalette.surface,
          duration: const Duration(seconds: 4),
          content: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppPalette.error,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  e.message,
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppPalette.surface,
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
            style: AppTypography.small.copyWith(color: AppPalette.error),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAdding = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<String> imagenes = widget.item.imagenes;

    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        backgroundColor: AppPalette.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppPalette.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Volver',
        ),
        title: Text(
          'Detalle del Repuesto',
          style: AppTypography.title.copyWith(fontSize: 18),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: _buildDisponibilidadBadge(),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 1. Carrusel / Galería de Fotos en Gran Formato ───────
                    _buildImageGallery(imagenes),
                    const SizedBox(height: 24),

                    // ── 2. Radar de Stock & SKU ──────────────────────────────
                    Row(
                      children: [
                        Flexible(child: _buildSucursalBadge()),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10.0,
                            vertical: 5.0,
                          ),
                          decoration: BoxDecoration(
                            color: AppPalette.surface,
                            borderRadius: BorderRadius.circular(8.0),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Text(
                            'SKU: ${widget.item.skuQrFisico}',
                            style: AppTypography.small.copyWith(
                              fontSize: 13,
                              color: AppPalette.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── 3. Título Principal ──────────────────────────────────
                    Text(
                      widget.item.tituloRepuesto,
                      style: AppTypography.headline.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Categoría chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10.0,
                        vertical: 4.0,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6.0),
                      ),
                      child: Text(
                        widget.item.nombreCategoria.toUpperCase(),
                        style: AppTypography.small.copyWith(
                          color: AppPalette.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── 4. Ficha Técnica Completa ────────────────────────────
                    _buildFichaTecnica(),
                    const SizedBox(height: 24),

                    // ── 5. Ubicación en Bodega ───────────────────────────────
                    _buildUbicacionCard(),
                    if (widget.item.observacionEstado != null &&
                        widget.item.observacionEstado!.trim().isNotEmpty &&
                        widget.item.observacionEstado!.trim().toLowerCase() != 'null' &&
                        widget.item.observacionEstado!.trim() != 'Sin observaciones registradas.') ...[
                      const SizedBox(height: 24),
                      _buildObservacionBodegaCard(),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ── Barra Fija Inferior (Bottom Action Bar) ─────────────────────
            _buildBottomActionBar(),
          ],
        ),
      ),
    );
  }

  /// Visor / Carrusel de Imágenes
  Widget _buildImageGallery(List<String> imagenes) {
    final totalSlides = imagenes.isEmpty ? 1 : imagenes.length;

    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.0),
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: totalSlides,
              onPageChanged: (idx) {
                setState(() => _currentImageIndex = idx);
              },
              itemBuilder: (context, index) {
                if (imagenes.isNotEmpty) {
                  return GestureDetector(
                    onTap: () {
                      VisorImagenCompletaDialog.show(
                        context,
                        fotografias: imagenes,
                        initialIndex: index,
                        titulo: widget.item.tituloRepuesto,
                        sku: widget.item.skuQrFisico,
                      );
                    },
                    child: Image.network(
                      imagenes[index],
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => _buildPlaceholderImage(),
                      loadingBuilder: (ctx, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppPalette.primary,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }
                return _buildPlaceholderImage();
              },
            ),

            // Contador estilo "1/3" en la esquina superior derecha
            if (imagenes.isNotEmpty)
              Positioned(
                top: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () {
                    VisorImagenCompletaDialog.show(
                      context,
                      fotografias: imagenes,
                      initialIndex: _currentImageIndex,
                      titulo: widget.item.tituloRepuesto,
                      sku: widget.item.skuQrFisico,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.fullscreen, color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '${_currentImageIndex + 1}/$totalSlides',
                          style: AppTypography.small.copyWith(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Indicador de Puntos / Páginas si hay más de 1
            if (totalSlides > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    totalSlides,
                    (idx) => Container(
                      width: _currentImageIndex == idx ? 20 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: _currentImageIndex == idx
                            ? AppPalette.primary
                            : Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    final bool esMotor = widget.item.nombreCategoria.toLowerCase().contains('motor');
    final IconData icono = esMotor ? Icons.engineering : Icons.settings;

    return Container(
      color: AppPalette.surface,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppPalette.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icono,
                size: 54,
                color: AppPalette.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Fotografía Técnica de Inventario',
              style: AppTypography.small.copyWith(
                color: AppPalette.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Badge de Disponibilidad
  Widget _buildDisponibilidadBadge() {
    final bool esReservado = _currentItem.esReservado;
    final estado = _currentItem.estadoActivo ?? 'Disponible';
    final color = esReservado ? const Color(0xFFF59E0B) : AppPalette.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            estado.toUpperCase(),
            style: AppTypography.small.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// Badge de Radar de Stock
  Widget _buildSucursalBadge() {
    if (_esMismaSucursal) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
        decoration: BoxDecoration(
          color: AppPalette.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: AppPalette.primary, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.my_location, size: 16, color: AppPalette.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'En tu sucursal (${widget.item.nombreSucursal})',
                style: AppTypography.small.copyWith(
                  fontSize: 13,
                  color: AppPalette.primary,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(8.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storefront_outlined, size: 16, color: AppPalette.neutral),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              widget.item.nombreSucursal,
              style: AppTypography.small.copyWith(
                fontSize: 13,
                color: AppPalette.neutral,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Ficha Técnica Completa
  Widget _buildFichaTecnica() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.article_outlined, size: 20, color: AppPalette.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ESPECIFICACIONES TÉCNICAS',
                  style: AppTypography.title.copyWith(
                    fontSize: 15,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 24),
          _buildSpecRow('Marca', widget.item.marca ?? 'N/A'),
          _buildSpecRow('Modelo', widget.item.modelo ?? 'N/A'),
          _buildSpecRow('Año', widget.item.anio?.toString() ?? 'N/A'),
          if (widget.item.idCategoria == 1)
            _buildSpecRow(
              'Número de Motor',
              (widget.item.numeroMotor != null &&
                      widget.item.numeroMotor!.trim().isNotEmpty &&
                      widget.item.numeroMotor!.trim() != 'null')
                  ? widget.item.numeroMotor!.trim()
                  : 'N/A',
            ),
          if (widget.item.cilindrada != null && widget.item.cilindrada!.isNotEmpty)
            _buildSpecRow('Cilindrada', widget.item.cilindrada!),
          if (widget.item.transmisionTipo != null && widget.item.transmisionTipo!.isNotEmpty)
            _buildSpecRow('Transmisión', widget.item.transmisionTipo!),
          if (widget.item.combustible != null && widget.item.combustible!.isNotEmpty)
            _buildSpecRow('Combustible', widget.item.combustible!),
          if (widget.item.traccion != null && widget.item.traccion!.isNotEmpty)
            _buildSpecRow('Tracción', widget.item.traccion!),
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.small.copyWith(
                color: AppPalette.textSecondary,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTypography.body.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Ubicación en Bodega
  Widget _buildUbicacionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on_outlined, size: 20, color: AppPalette.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'UBICACIÓN FÍSICA EN BODEGA',
                  style: AppTypography.title.copyWith(
                    fontSize: 15,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 24),
          Row(
            children: [
              Expanded(
                child: _buildLocationTile(
                  'Galpón',
                  (widget.item.ubicacionGalpon != null && widget.item.ubicacionGalpon!.trim().isNotEmpty)
                      ? widget.item.ubicacionGalpon!.trim()
                      : 'S/G',
                  Icons.warehouse_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildLocationTile(
                  'Pasillo',
                  (widget.item.ubicacionPasillo != null && widget.item.ubicacionPasillo!.trim().isNotEmpty)
                      ? widget.item.ubicacionPasillo!.trim()
                      : 'S/P',
                  Icons.view_column_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildLocationTile(
                  'Pallet',
                  (widget.item.ubicacionPallet != null && widget.item.ubicacionPallet!.trim().isNotEmpty)
                      ? widget.item.ubicacionPallet!.trim()
                      : 'S/P',
                  Icons.inventory_2_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Observaciones de Bodega / Estado del Activo
  Widget _buildObservacionBodegaCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
          color: AppPalette.secondary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sticky_note_2_outlined, size: 20, color: AppPalette.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'OBSERVACIÓN DE BODEGA / ESTADO',
                  style: AppTypography.title.copyWith(
                    fontSize: 15,
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.bold,
                    color: AppPalette.secondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 24),
          Text(
            widget.item.observacionEstado!.trim(),
            style: AppTypography.body.copyWith(
              fontSize: 14,
              height: 1.4,
              color: AppPalette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppPalette.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppPalette.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.small.copyWith(
                    fontSize: 11,
                    color: AppPalette.textSecondary,
                  ),
                ),
                Text(
                  value,
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Barra Fija Inferior con Precio y Botón Agregar
  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1.0),
        ),
      ),
      child: Row(
        children: [
          // Precio
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PRECIO SUGERIDO',
                  style: AppTypography.small.copyWith(
                    fontSize: 11,
                    letterSpacing: 1.0,
                    color: AppPalette.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.item.precioSugeridoFormateado,
                  style: AppTypography.headline.copyWith(
                    color: AppPalette.secondary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.item.precioMinimo != null && widget.item.precioMaximo != null && widget.item.precioMinimo != widget.item.precioMaximo) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Rango: ${widget.item.rangoPrecioFormateado}',
                    style: AppTypography.small.copyWith(
                      fontSize: 11,
                      color: AppPalette.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Botón Agregar
          Builder(
            builder: (btnContext) {
              final bool bloqueado = _currentItem.esReservado;
              return SizedBox(
                height: 42,
                child: ElevatedButton.icon(
                  key: const Key('btn_agregar_carrito_detalle'),
                  onPressed: (_isAdding || bloqueado)
                      ? null
                      : () {
                          CartFlyAnimation.run(context: btnContext);
                          _onAddToCart();
                        },
                  icon: _isAdding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          bloqueado ? Icons.lock_outline : Icons.add_shopping_cart,
                          size: 18,
                        ),
                  label: Text(
                    _isAdding
                        ? 'Reservando...'
                        : (bloqueado ? 'Reservado' : 'Agregar'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: bloqueado
                        ? AppPalette.neutral.withValues(alpha: 0.25)
                        : AppPalette.primary,
                    foregroundColor: AppPalette.textPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
