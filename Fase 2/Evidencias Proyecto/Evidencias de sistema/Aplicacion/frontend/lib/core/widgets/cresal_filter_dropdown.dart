import 'package:flutter/material.dart';
import '../theme/tokens/app_palette.dart';
import '../theme/tokens/app_typography.dart';

/// Elemento de opción para [CresalFilterDropdown].
class CresalFilterDropdownItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const CresalFilterDropdownItem({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// Selector de filtro desplegable de alta fidelidad basado en [MenuAnchor] (Material 3).
///
/// Diseñado para entornos Desktop y Web: elimina el problema de doble clic de los
/// antiguos [DropdownButton], permitiendo alternar entre múltiples filtros continuos
/// con un solo clic fluido ("one-click switch").
class CresalFilterDropdown<T> extends StatelessWidget {
  final T value;
  final List<CresalFilterDropdownItem<T>> items;
  final ValueChanged<T> onChanged;
  final String? labelPrefix;
  final double height;
  final Color? backgroundColor;
  final Color? borderColor;
  final bool isExpanded;
  final double menuMaxHeight;

  const CresalFilterDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelPrefix,
    this.height = 36.0,
    this.backgroundColor,
    this.borderColor,
    this.isExpanded = true,
    this.menuMaxHeight = 320.0,
  });

  @override
  Widget build(BuildContext context) {
    final selectedItem = items.firstWhere(
      (item) => item.value == value,
      orElse: () => items.isNotEmpty
          ? items.first
          : CresalFilterDropdownItem(value: value, label: '$value'),
    );

    return MenuAnchor(
      builder: (context, controller, child) {
        final isOpen = controller.isOpen;
        final borderThemeColor = isOpen
            ? AppPalette.primary
            : (borderColor ?? AppPalette.neutral.withValues(alpha: 0.25));

        return InkWell(
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: backgroundColor ?? AppPalette.surfaceLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: borderThemeColor,
                width: isOpen ? 1.5 : 1.0,
              ),
              boxShadow: isOpen
                  ? [
                      BoxShadow(
                        color: AppPalette.primary.withValues(alpha: 0.08),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selectedItem.icon != null) ...[
                        Icon(
                          selectedItem.icon,
                          size: 16,
                          color: AppPalette.textSecondaryLight,
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (labelPrefix != null && labelPrefix!.isNotEmpty) ...[
                        Text(
                          labelPrefix!,
                          style: AppTypography.small.copyWith(
                            color: AppPalette.textSecondaryLight,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          selectedItem.label,
                          style: AppTypography.body.copyWith(
                            color: AppPalette.textPrimaryLight,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: isOpen ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: isOpen ? AppPalette.primary : AppPalette.neutral,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          backgroundColor ?? AppPalette.surfaceLight,
        ),
        elevation: const WidgetStatePropertyAll(6),
        shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.12)),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: AppPalette.neutral.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
        maximumSize: WidgetStatePropertyAll(
          Size(double.infinity, menuMaxHeight),
        ),
      ),
      menuChildren: items.map((item) {
        final isSelected = item.value == value;

        return MenuItemButton(
          onPressed: () => onChanged(item.value),
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (isSelected) {
                return AppPalette.primary.withValues(alpha: 0.08);
              }
              if (states.contains(WidgetState.hovered)) {
                return AppPalette.neutral.withValues(alpha: 0.06);
              }
              return Colors.transparent;
            }),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          leadingIcon: item.icon != null
              ? Icon(
                  item.icon,
                  size: 16,
                  color: isSelected
                      ? AppPalette.primary
                      : AppPalette.textSecondaryLight,
                )
              : null,
          trailingIcon: isSelected
              ? const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: AppPalette.primary,
                )
              : null,
          child: Text(
            item.label,
            style: AppTypography.body.copyWith(
              color: isSelected
                  ? AppPalette.primary
                  : AppPalette.textPrimaryLight,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12.5,
            ),
          ),
        );
      }).toList(),
    );
  }
}
