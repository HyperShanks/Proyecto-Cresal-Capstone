import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';

/// Utilidad para ejecutar una animación de vuelo ("Fly-to-Cart")
/// cuando el usuario agrega un producto al carrito.
class CartFlyAnimation {
  /// Lanza una partícula animada en trayectoria parabólica desde [context]
  /// hacia la ubicación del carrito (por defecto la esquina inferior derecha).
  static void run({
    required BuildContext context,
    Offset? startOffset,
    Offset? targetOffset,
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    // Calcular posición de origen a partir del BuildContext
    Offset origin = startOffset ?? Offset.zero;
    if (startOffset == null) {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final localCenter = Offset(
          renderBox.size.width / 2,
          renderBox.size.height / 2,
        );
        origin = renderBox.localToGlobal(localCenter);
      }
    }

    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;

    // Destino: pestaña de Carrito en el extremo inferior derecho del BottomNavigationBar
    final destination = targetOffset ??
        Offset(
          screenSize.width - 50.0,
          screenSize.height - mediaQuery.padding.bottom - 28.0,
        );

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _FlyingBadge(
        start: origin,
        end: destination,
        onComplete: () {
          if (entry.mounted) {
            entry.remove();
          }
        },
      ),
    );

    overlay.insert(entry);
  }
}

class _FlyingBadge extends StatefulWidget {
  final Offset start;
  final Offset end;
  final VoidCallback onComplete;

  const _FlyingBadge({
    required this.start,
    required this.end,
    required this.onComplete,
  });

  @override
  State<_FlyingBadge> createState() => _FlyingBadgeState();
}

class _FlyingBadgeState extends State<_FlyingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    _controller.forward().then((_) {
      if (mounted) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final t = _animation.value;

        // Trayectoria parabólica (Curva Bézier cuadrática)
        // El punto de control se eleva para simular lanzamiento parabólico
        final controlY = math.min(widget.start.dy, widget.end.dy) - 60.0;
        final currentX = widget.start.dx + (widget.end.dx - widget.start.dx) * t;
        final currentY = (1 - t) * (1 - t) * widget.start.dy +
            2 * (1 - t) * t * controlY +
            t * t * widget.end.dy;

        // Escala: inicia en 1.0, sube a 1.25 al inicio y se reduce a 0.35 al entrar al carrito
        double scale;
        if (t < 0.25) {
          scale = 1.0 + (t / 0.25) * 0.25;
        } else {
          scale = 1.25 - ((t - 0.25) / 0.75) * 0.9;
        }

        // Opacidad: se mantiene sólida y se desvanece suavemente al final
        final opacity = (1.0 - (t > 0.85 ? (t - 0.85) / 0.15 : 0.0)).clamp(0.0, 1.0);

        return Positioned(
          left: currentX - 18,
          top: currentY - 18,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppPalette.primary, AppPalette.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppPalette.primary.withValues(alpha: 0.65),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.shopping_cart,
                      color: AppPalette.textPrimary,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
