import 'package:flutter/material.dart';
import '../theme/app_components.dart';
import '../theme/tokens/app_typography.dart';

class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final LinearGradient gradient;
  final double height;
  final double? width;
  final double borderRadius;

  const GradientButton({
    super.key,
    this.onPressed, // <-- Corregido: Se quitó el "required"
    required this.child,
    required this.gradient,
    this.height = AppComponents.minTouchTarget,
    this.width,
    this.borderRadius = AppComponents.defaultBorderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        gradient: isEnabled ? gradient : null,
        color: isEnabled ? null : Theme.of(context).disabledColor,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(borderRadius),
          child: Center(
            child: DefaultTextStyle(style: AppTypography.button, child: child),
          ),
        ),
      ),
    );
  }
}
