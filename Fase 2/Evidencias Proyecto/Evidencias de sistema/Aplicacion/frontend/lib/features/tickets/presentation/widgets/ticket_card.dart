import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../models/ticket_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TICKET CARD — Widget local del módulo de tickets (Theme-Aware)
// Muestra el resumen de un ticket en el historial adaptado a Dark Mode y Light Mode.
// Touch target ≥ 48dp (W3C) garantizado por el InkWell wrapping.
// ─────────────────────────────────────────────────────────────────────────────
class TicketCard extends StatelessWidget {
  final TicketModel ticket;
  final VoidCallback? onTap;

  const TicketCard({super.key, required this.ticket, this.onTap});

  // ── Colores y etiquetas de estado ─────────────────────────────────────────
  static Color _colorForPrioridad(String prioridad) {
    switch (prioridad.toLowerCase()) {
      case 'urgente':
        return AppPalette.error;
      case 'alta':
        return AppPalette.secondary;
      case 'media':
        return AppPalette.primary;
      case 'baja':
        return AppPalette.success;
      default:
        return AppPalette.neutral;
    }
  }

  // ── Formateo de fecha ─────────────────────────────────────────────────────
  static String _formatFecha(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '—';
    try {
      final String formattedIso = isoDate.contains('Z') 
          ? isoDate 
          : '${isoDate.replaceAll(' ', 'T')}Z';
      final dt = DateTime.parse(formattedIso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year}  '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppPalette.surface : AppPalette.surfaceLight;
    final borderColor = isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight;
    final textPrimary = isDark ? AppPalette.textPrimary : AppPalette.textPrimaryLight;
    final textSecondary = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;
    final tagBg = isDark ? AppPalette.background : AppPalette.backgroundLight;
    final tagBorder = isDark ? AppPalette.neutral.withValues(alpha: 0.2) : AppPalette.borderLight;
    final prioridadColor = _colorForPrioridad(ticket.prioridad);

    return Material(
      color: surfaceColor,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppPalette.primary.withValues(alpha: 0.08),
        splashColor: AppPalette.primary.withValues(alpha: 0.15),
        highlightColor: AppPalette.primary.withValues(alpha: 0.05),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: prioridadColor, width: 4),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Fila superior: tipo + badge de estado ────────────────────
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: tagBg,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: tagBorder),
                        ),
                        child: Text(
                          '${ticket.folioVisual} • ${ticket.tipoTicket.toUpperCase()}',
                          style: AppTypography.small.copyWith(
                            color: textSecondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _EstadoBadge(estado: ticket.estadoTicket, isDark: isDark),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Asunto ───────────────────────────────────────────────────
                  Text(
                    ticket.asunto,
                    style: AppTypography.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),

                  // ── Fila inferior: prioridad + fecha ─────────────────────────
                  Row(
                    children: [
                      Icon(Icons.flag_rounded, size: 14, color: prioridadColor),
                      const SizedBox(width: 4),
                      Text(
                        ticket.prioridad,
                        style: AppTypography.small.copyWith(
                          color: prioridadColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _formatFecha(ticket.fechaCreacion),
                          style: AppTypography.small.copyWith(
                            color: textSecondary,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BADGE de estado — Pill semántica Theme-Aware (Dark & Light)
// ─────────────────────────────────────────────────────────────────────────────
class _EstadoBadge extends StatelessWidget {
  final String estado;
  final bool isDark;

  const _EstadoBadge({required this.estado, required this.isDark});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color border;
    Color text;

    if (isDark) {
      switch (estado.toLowerCase()) {
        case 'abierto':
          bg = AppPalette.secondary.withValues(alpha: 0.15);
          border = AppPalette.secondary.withValues(alpha: 0.5);
          text = AppPalette.secondary;
          break;
        case 'en proceso':
        case 'en revisión':
        case 'en revision':
          bg = AppPalette.primary.withValues(alpha: 0.15);
          border = AppPalette.primary.withValues(alpha: 0.5);
          text = AppPalette.primary;
          break;
        case 'resuelto':
          bg = AppPalette.success.withValues(alpha: 0.15);
          border = AppPalette.success.withValues(alpha: 0.5);
          text = AppPalette.success;
          break;
        case 'cerrado':
        case 'rechazado':
        default:
          bg = AppPalette.background;
          border = AppPalette.neutral.withValues(alpha: 0.3);
          text = AppPalette.textSecondary;
          break;
      }
    } else {
      switch (estado.toLowerCase()) {
        case 'abierto':
          bg = AppPalette.warningBg;
          border = AppPalette.warningBorder;
          text = AppPalette.warningText;
          break;
        case 'en proceso':
        case 'en revisión':
        case 'en revision':
          bg = AppPalette.primary.withValues(alpha: 0.12);
          border = AppPalette.primary.withValues(alpha: 0.35);
          text = AppPalette.primary;
          break;
        case 'resuelto':
          bg = AppPalette.successBg;
          border = AppPalette.successBorder;
          text = AppPalette.success;
          break;
        case 'cerrado':
        case 'rechazado':
        default:
          bg = AppPalette.backgroundLight;
          border = AppPalette.borderLight;
          text = AppPalette.textSecondaryLight;
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Text(
        estado,
        style: AppTypography.small.copyWith(
          color: text,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}
