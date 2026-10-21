// lib/features/ventas/presentation/widgets/galeria_activo_widget.dart

import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import 'visor_imagen_completa_dialog.dart';

/// Componente de galería/carrusel de fotografías de un activo para la interfaz de tasación (HU-3.8 / SPEC-HU-TAREA-15).
class GaleriaActivoWidget extends StatefulWidget {
  final List<String> fotografias;
  final double height;

  const GaleriaActivoWidget({
    super.key,
    required this.fotografias,
    this.height = 200.0,
  });

  @override
  State<GaleriaActivoWidget> createState() => _GaleriaActivoWidgetState();
}

class _GaleriaActivoWidgetState extends State<GaleriaActivoWidget> {
  late PageController _pageController;
  int _currentIndex = 0;
  final Map<int, int> _retryCounters = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _irAAnterior() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _irASiguiente() {
    if (_currentIndex < widget.fotografias.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _reintentarCarga(int index) {
    setState(() {
      _retryCounters[index] = (_retryCounters[index] ?? 0) + 1;
    });
  }

  void _abrirVisorExpandido(int index) {
    VisorImagenCompletaDialog.show(
      context,
      fotografias: widget.fotografias,
      initialIndex: index,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Caso Empty State: Activo sin fotos registradas
    if (widget.fotografias.isEmpty) {
      return Container(
        height: widget.height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppPalette.background,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.white12),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.image_not_supported_outlined,
                  size: 36.0,
                  color: AppPalette.textSecondary,
                ),
              ),
              const SizedBox(height: 10.0),
              Text(
                'Activo sin fotografías registradas.',
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(
                  color: AppPalette.textSecondary,
                  fontSize: 13.0,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final totalFotos = widget.fotografias.length;

    // 2. Galería con 1 o más fotos
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.0),
      child: Container(
        height: widget.height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: Colors.white12),
        ),
        child: Stack(
          children: [
            // Carrusel de imágenes
            PageView.builder(
              controller: _pageController,
              itemCount: totalFotos,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final url = widget.fotografias[index];
                final retryKey = ValueKey('$url-${_retryCounters[index] ?? 0}');

                return InkWell(
                  onTap: () => _abrirVisorExpandido(index),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        url,
                        key: retryKey,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          final total = loadingProgress.expectedTotalBytes;
                          final loaded = loadingProgress.cumulativeBytesLoaded;
                          return Center(
                            child: CircularProgressIndicator(
                              value: total != null ? loaded / total : null,
                              color: AppPalette.primary,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: AppPalette.warning,
                                    size: 32.0,
                                  ),
                                  const SizedBox(height: 8.0),
                                  Text(
                                    'Error al cargar la imagen. Presione para reintentar.',
                                    textAlign: TextAlign.center,
                                    style: AppTypography.small.copyWith(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8.0),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppPalette.surface,
                                      foregroundColor: AppPalette.textPrimary,
                                      elevation: 0,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    icon: const Icon(Icons.refresh, size: 16),
                                    label: const Text('Reintentar'),
                                    onPressed: () => _reintentarCarga(index),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            ),

            // Pill indicador "Foto X de Y" y sugerencia de zoom
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.zoom_in, color: Colors.white70, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      totalFotos > 1
                          ? 'Foto ${_currentIndex + 1} de $totalFotos'
                          : '1 fotografía',
                      style: AppTypography.small.copyWith(
                        color: Colors.white,
                        fontSize: 11.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Botones de Navegación lateral si hay más de una foto
            if (totalFotos > 1 && _currentIndex > 0)
              Positioned(
                left: 6,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.chevron_left, color: Colors.white, size: 24),
                      visualDensity: VisualDensity.compact,
                      onPressed: _irAAnterior,
                    ),
                  ),
                ),
              ),

            if (totalFotos > 1 && _currentIndex < totalFotos - 1)
              Positioned(
                right: 6,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.chevron_right, color: Colors.white, size: 24),
                      visualDensity: VisualDensity.compact,
                      onPressed: _irASiguiente,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
