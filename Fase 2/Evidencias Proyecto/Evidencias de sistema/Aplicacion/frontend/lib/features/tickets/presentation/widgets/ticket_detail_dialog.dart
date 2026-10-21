import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../models/ticket_model.dart';

/// Modal Dialog centrado de escritorio para visualizar el detalle completo de un ticket de soporte.
/// Diseñado según la especificación visual de `prototipo_caja_sprint4.html` (Líneas 1480-1540).
class TicketDetailDialog extends StatelessWidget {
  final TicketModel ticket;

  const TicketDetailDialog({
    super.key,
    required this.ticket,
  });

  static Future<void> mostrar(BuildContext context, TicketModel ticket) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => TicketDetailDialog(ticket: ticket),
    );
  }

  static Color _colorForPrioridad(String prioridad) {
    switch (prioridad.toLowerCase()) {
      case 'urgente':
        return AppPalette.error;
      case 'alta':
        return const Color(0xFFEA580C); // Orange-600
      case 'media':
        return AppPalette.secondary;
      case 'baja':
        return AppPalette.success;
      default:
        return AppPalette.textSecondaryLight;
    }
  }

  static String _formatFecha(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '—';
    try {
      final String formattedIso = isoDate.contains('Z')
          ? isoDate
          : '${isoDate.replaceAll(' ', 'T')}Z';
      final dt = DateTime.parse(formattedIso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final prioridadColor = _colorForPrioridad(ticket.prioridad);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppPalette.surface : AppPalette.surfaceLight;
    final borderColor = isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight;
    final textPrimary = isDark ? AppPalette.textPrimary : AppPalette.textPrimaryLight;
    final textSecondary = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;
    final descBg = isDark ? AppPalette.background : const Color(0xFFF8FAFC);
    final closeHover = isDark ? AppPalette.surfaceLight.withValues(alpha: 0.1) : const Color(0xFFF1F5F9);

    return Dialog(
      backgroundColor: surfaceColor,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header: Tipo, Título / Folio y Botón Cerrar (X) ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.tipoTicket.toUpperCase(),
                          style: AppTypography.small.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${ticket.folioVisual} — ${ticket.asunto}',
                          style: AppTypography.title.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Reportado el ${_formatFecha(ticket.fechaCreacion)}',
                          style: AppTypography.small.copyWith(
                            fontSize: 12,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: textSecondary,
                    hoverColor: closeHover,
                    splashRadius: 18,
                    tooltip: 'Cerrar',
                  ),
                ],
              ),
              Divider(color: borderColor, height: 24),

              // ── Fila de Estados y Prioridad ──
              Row(
                children: [
                  Text(
                    'Estado:',
                    style: AppTypography.small.copyWith(
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildEstadoBadge(ticket.estadoTicket, isDark, borderColor, textSecondary),
                  const SizedBox(width: 16),
                  Text(
                    'Prioridad:',
                    style: AppTypography.small.copyWith(
                      fontWeight: FontWeight.w600,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _buildPrioridadBadge(ticket.prioridad, prioridadColor),
                ],
              ),
              const SizedBox(height: 16),

              // ── Descripción del Reporte ──
              Text(
                'DESCRIPCIÓN DEL REPORTE',
                style: AppTypography.small.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: descBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  ticket.descripcion,
                  style: AppTypography.body.copyWith(
                    fontSize: 14,
                    color: textPrimary,
                    height: 1.45,
                  ),
                ),
              ),

              // ── Resolución de TI (Si existe) ──
              if (ticket.observacionCierre != null &&
                  ticket.observacionCierre!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 15,
                      color: AppPalette.success,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'RESOLUCIÓN DE TI',
                      style: AppTypography.small.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppPalette.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? AppPalette.success.withValues(alpha: 0.12) : AppPalette.successBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? AppPalette.success.withValues(alpha: 0.3) : AppPalette.successBorder,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket.observacionCierre!,
                        style: AppTypography.body.copyWith(
                          fontSize: 14,
                          color: textPrimary,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (ticket.fechaCierre != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Cerrado el ${_formatFecha(ticket.fechaCierre)}',
                          style: AppTypography.small.copyWith(
                            fontSize: 12,
                            color: AppPalette.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // ── Botón de Cerrar Modal ──
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cerrar Detalle',
                    style: AppTypography.button.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEstadoBadge(String estado, bool isDark, Color fallbackBorder, Color fallbackText) {
    Color bg;
    Color border;
    Color text;

    switch (estado.toLowerCase()) {
      case 'abierto':
        bg = AppPalette.secondary.withValues(alpha: 0.12);
        border = AppPalette.secondary.withValues(alpha: 0.35);
        text = AppPalette.secondary;
        break;
      case 'en proceso':
      case 'en revisión':
      case 'en revision':
        bg = AppPalette.primary.withValues(alpha: 0.12);
        border = AppPalette.primary.withValues(alpha: 0.35);
        text = AppPalette.primary;
        break;
      case 'resuelto':
        bg = isDark ? AppPalette.success.withValues(alpha: 0.12) : AppPalette.successBg;
        border = isDark ? AppPalette.success.withValues(alpha: 0.3) : AppPalette.successBorder;
        text = AppPalette.success;
        break;
      case 'cerrado':
      default:
        bg = isDark ? AppPalette.background : const Color(0xFFF1F5F9);
        border = fallbackBorder;
        text = fallbackText;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
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
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildPrioridadBadge(String prioridad, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        prioridad,
        style: AppTypography.small.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
