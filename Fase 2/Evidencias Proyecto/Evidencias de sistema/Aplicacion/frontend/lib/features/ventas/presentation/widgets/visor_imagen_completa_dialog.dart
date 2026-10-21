// lib/features/ventas/presentation/widgets/visor_imagen_completa_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';

/// Modal a pantalla completa para visualizar con zoom las fotografías del activo
/// sin perder el estado o monto digitado en la tasación o inventario.
class VisorImagenCompletaDialog extends StatefulWidget {
  final List<String> fotografias;
  final int initialIndex;
  final String? titulo;
  final String? sku;

  const VisorImagenCompletaDialog({
    super.key,
    required this.fotografias,
    this.initialIndex = 0,
    this.titulo,
    this.sku,
  });

  static Future<void> show(
    BuildContext context, {
    required List<String> fotografias,
    int initialIndex = 0,
    String? titulo,
    String? sku,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (ctx) => VisorImagenCompletaDialog(
        fotografias: fotografias,
        initialIndex: initialIndex,
        titulo: titulo,
        sku: sku,
      ),
    );
  }

  @override
  State<VisorImagenCompletaDialog> createState() =>
      _VisorImagenCompletaDialogState();
}

class _VisorImagenCompletaDialogState extends State<VisorImagenCompletaDialog> {
  late PageController _pageController;
  late int _currentIndex;
  final Map<int, int> _retryCounters = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.fotografias.isEmpty ? 0 : widget.fotografias.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
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

  @override
  Widget build(BuildContext context) {
    if (widget.fotografias.isEmpty) {
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppPalette.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined, size: 48, color: Colors.white54),
              const SizedBox(height: 12),
              Text(
                'Activo sin fotografías registradas.',
                style: AppTypography.body.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ),
      );
    }

    final totalFotos = widget.fotografias.length;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _irAAnterior();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _irASiguiente();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: Colors.black.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Stack(
          children: [
            // Carrusel interactivo a pantalla completa con espacio para cabecera y tira de miniaturas
            Padding(
              padding: EdgeInsets.only(
                top: 64,
                bottom: totalFotos > 1 ? 84 : 20,
              ),
              child: PageView.builder(
                controller: _pageController,
                physics: const BouncingScrollPhysics(),
                itemCount: totalFotos,
                onPageChanged: (index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final url = widget.fotografias[index];
                  final retryKey = ValueKey('$url-${_retryCounters[index] ?? 0}');

                  return InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Center(
                      child: Image.network(
                        url,
                        key: retryKey,
                        fit: BoxFit.contain,
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
                              padding: const EdgeInsets.all(16),
                              margin: const EdgeInsets.symmetric(horizontal: 32),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.amberAccent,
                                    size: 40,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Error al cargar la imagen. Presione para reintentar.',
                                    textAlign: TextAlign.center,
                                    style: AppTypography.small.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppPalette.primary,
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text('Reintentar'),
                                    onPressed: () => _reintentarCarga(index),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),

            // Barra Superior: Botón de cierre, título/SKU y pill "Foto X de Y"
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  if (totalFotos > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        'Foto ${_currentIndex + 1} de $totalFotos',
                        style: AppTypography.small.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (widget.sku != null || widget.titulo != null) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          children: [
                            if (widget.sku != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: AppPalette.tertiary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  widget.sku!,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            if (widget.titulo != null)
                              Expanded(
                                child: Text(
                                  widget.titulo!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Cerrar visor (Esc)',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.6),
                    ),
                    icon: const Icon(Icons.close, color: Colors.white, size: 24),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Botones de Navegación Lateral (si hay más de 1 imagen)
            if (totalFotos > 1 && _currentIndex > 0)
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.65),
                      padding: const EdgeInsets.all(12),
                    ),
                    icon: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
                    onPressed: _irAAnterior,
                  ),
                ),
              ),
            if (totalFotos > 1 && _currentIndex < totalFotos - 1)
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.65),
                      padding: const EdgeInsets.all(12),
                    ),
                    icon: const Icon(Icons.chevron_right, color: Colors.white, size: 32),
                    onPressed: _irASiguiente,
                  ),
                ),
              ),

            // Tira inferior de miniaturas (cuando hay más de 1 fotografía)
            if (totalFotos > 1)
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(totalFotos, (idx) {
                          final isSelected = idx == _currentIndex;
                          return GestureDetector(
                            onTap: () {
                              _pageController.animateToPage(
                                idx,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: isSelected ? 52 : 44,
                              height: isSelected ? 52 : 44,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? AppPalette.primary : Colors.white24,
                                  width: isSelected ? 2.5 : 1.0,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.network(
                                widget.fotografias[idx],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: Colors.white12,
                                  child: const Icon(Icons.broken_image, size: 18, color: Colors.white54),
                                ),
                              ),
                            ),
                          );
                        }),
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
}
