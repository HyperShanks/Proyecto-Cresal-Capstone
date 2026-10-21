import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/tokens/app_palette.dart';

/// Modelo de datos para un elemento de la barra de navegación flotante tipo Glassmorphism.
class FloatingGlassNavItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final int badgeCount;

  const FloatingGlassNavItem({
    required this.icon,
    this.activeIcon,
    required this.label,
    this.badgeCount = 0,
  });
}

/// Barra de navegación flotante con estética Glassmorphism:
/// - Despegada del fondo (bottom) y sin tocar los bordes laterales.
/// - Bordes redondeados continuos (forma de píldora / estadio).
/// - Fondo translúcido con desenfoque gaussiano suave (BackdropFilter blur).
/// - Íconos limpios con indicador circular translúcido en la pestaña activa (estilo Gorilas).
/// - Soporte para badges de notificación numéricos.
class FloatingGlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<FloatingGlassNavItem> items;
  final double horizontalMargin;
  final double topMargin;
  final double bottomMargin;

  final double blurSigma;
  final double surfaceOpacity;
  final double height;

  const FloatingGlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.horizontalMargin = 20.0,
    this.topMargin = 8.0,
    this.bottomMargin = 14.0,
    this.blurSigma = 20.0,
    this.surfaceOpacity = 0.90,
    this.height = 70.0,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalMargin,
          topMargin,
          horizontalMargin,
          bottomMargin + (bottomPadding > 0 ? 4 : 0),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36.0),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: Container(
              height: height,
              decoration: BoxDecoration(
                color: AppPalette.surface.withValues(alpha: surfaceOpacity),
                borderRadius: BorderRadius.circular(36.0),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.40),
                    blurRadius: 20.0,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(items.length, (index) {
                  final item = items[index];
                  final isSelected = index == currentIndex;
                  return Expanded(
                    child: _buildItem(context, item, isSelected, () => onTap(index)),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    FloatingGlassNavItem item,
    bool isSelected,
    VoidCallback onItemTap,
  ) {
    final iconWidget = Icon(
      isSelected ? (item.activeIcon ?? item.icon) : item.icon,
      color: isSelected ? AppPalette.primary : AppPalette.textSecondary,
      size: 22.0,
    );

    final displayIcon = item.badgeCount > 0
        ? Badge.count(
            count: item.badgeCount,
            backgroundColor: AppPalette.secondary,
            textColor: AppPalette.background,
            child: iconWidget,
          )
        : iconWidget;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onItemTap,
        borderRadius: BorderRadius.circular(24.0),
        splashColor: AppPalette.primary.withValues(alpha: 0.15),
        highlightColor: Colors.transparent,
        child: Semantics(
          label: item.label,
          selected: isSelected,
          button: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Indicador circular/estadio para el ícono
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: 44.0,
                  height: 30.0,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15.0),
                    color: isSelected
                        ? AppPalette.primary.withValues(alpha: 0.18)
                        : Colors.transparent,
                    border: isSelected
                        ? Border.all(
                            color: AppPalette.primary.withValues(alpha: 0.25),
                            width: 1.0,
                          )
                        : null,
                  ),
                  child: Center(child: displayIcon),
                ),
                const SizedBox(height: 3.0),
                // Etiqueta de la vista / pestaña
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 11.0,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? AppPalette.primary
                        : AppPalette.textSecondary,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
