// frontend/lib/features/gerencia/presentation/widgets/kpi_card_widget.dart
import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';

/// Tarjeta KPI reutilizable para el Dashboard Ejecutivo (HU-5.1).
/// Diseñé este componente siguiendo el layout ejecutivo de prototipo_gerencia_v1.html:
/// presenta la etiqueta superior en mayúsculas, badge de variación porcentual,
/// valor destacado en alta legibilidad y texto de contexto operativo.
class KpiCardWidget extends StatefulWidget {
  final String titulo;
  final String valor;
  final String? badgeTexto;
  final Color? badgeColor;
  final String subtitulo;
  final Widget? subtituloWidget;
  final IconData? icono;
  final Color? valorColor;

  const KpiCardWidget({
    super.key,
    required this.titulo,
    required this.valor,
    this.badgeTexto,
    this.badgeColor,
    this.subtitulo = '',
    this.subtituloWidget,
    this.icono,
    this.valorColor,
  });

  @override
  State<KpiCardWidget> createState() => _KpiCardWidgetState();
}

class _KpiCardWidgetState extends State<KpiCardWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final effectiveBadgeColor = widget.badgeColor ?? AppPalette.success;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isHovered
                ? AppPalette.primary.withValues(alpha: 0.4)
                : const Color(0xFFE2E8F0),
            width: _isHovered ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: _isHovered
                  ? AppPalette.primary.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.02),
              blurRadius: _isHovered ? 12 : 4,
              offset: Offset(0, _isHovered ? 4 : 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Fila superior: Título del KPI y Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (widget.icono != null) ...[
                        Icon(
                          widget.icono,
                          size: 16,
                          color: AppPalette.textSecondaryLight,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          widget.titulo.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Color(0xFF94A3B8), // Slate 400
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.badgeTexto != null &&
                    widget.badgeTexto!.trim().isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: effectiveBadgeColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: effectiveBadgeColor.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      widget.badgeTexto!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: effectiveBadgeColor,
                      ),
                    ),
                  ),
              ],
            ),

            // Valor Principal Destacado (con FittedBox para resiliencia responsiva)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                widget.valor,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                  color: widget.valorColor ?? const Color(0xFF0F172A),
                ),
                maxLines: 1,
              ),
            ),

            // Subtítulo descriptivo o Widget de contexto (mantiene altura uniforme)
            if (widget.subtituloWidget != null)
              widget.subtituloWidget!
            else if (widget.subtitulo.trim().isNotEmpty)
              Text(
                widget.subtitulo,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF64748B),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else
              const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}
