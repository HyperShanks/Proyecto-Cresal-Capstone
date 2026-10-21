import 'package:flutter/material.dart';

import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../models/ticket_model.dart';

import 'ticket_detail_dialog.dart';

/// Modal BottomSheet que despliega el detalle completo de un ticket de soporte,
/// incluyendo la descripción detallada, metadatos, referencias y resolución.
/// Se adapta dinámicamente tanto a Dark Mode (PDA / Celular) como a Light Mode (Caja / Desktop).
class TicketDetailSheet extends StatelessWidget {
  final TicketModel ticket;

  const TicketDetailSheet({
    super.key,
    required this.ticket,
  });

  /// Método de invocación estática adaptativo (Dialog en Desktop >= 768px, BottomSheet en Móvil < 768px)
  static Future<void> mostrar(BuildContext context, TicketModel ticket) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768;
    if (isDesktop) {
      return TicketDetailDialog.mostrar(context, ticket);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppPalette.surface : AppPalette.surfaceLight,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (context) => TicketDetailSheet(ticket: ticket),
    );
  }

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppPalette.surface : AppPalette.surfaceLight;
    final bgBoxColor = isDark ? AppPalette.background : AppPalette.backgroundLight;
    final borderBoxColor = isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight;
    final textPrimary = isDark ? AppPalette.textPrimary : AppPalette.textPrimaryLight;
    final textSecondary = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;
    final dividerColor = isDark ? AppPalette.neutral.withValues(alpha: 0.2) : AppPalette.borderLight;
    final handleColor = isDark ? AppPalette.neutral.withValues(alpha: 0.4) : AppPalette.borderLight;
    final resBg = isDark ? AppPalette.success.withValues(alpha: 0.12) : AppPalette.successBg;
    final resBorder = isDark ? AppPalette.success.withValues(alpha: 0.4) : AppPalette.successBorder;
    final prioridadColor = _colorForPrioridad(ticket.prioridad);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20.0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Handle / Pill central ─────────────────────────────────────
              Center(
                child: Container(
                  width: 44.0,
                  height: 4.0,
                  margin: const EdgeInsets.only(bottom: 16.0),
                  decoration: BoxDecoration(
                    color: handleColor,
                    borderRadius: BorderRadius.circular(2.0),
                  ),
                ),
              ),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    // ── Header: Tipo de Ticket + Badge de Estado ────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                          decoration: BoxDecoration(
                            color: bgBoxColor,
                            borderRadius: BorderRadius.circular(6.0),
                            border: Border.all(color: borderBoxColor),
                          ),
                          child: Text(
                            ticket.tipoTicket.toUpperCase(),
                            style: AppTypography.small.copyWith(
                              color: textSecondary,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        _buildEstadoBadge(ticket.estadoTicket, isDark),
                      ],
                    ),

                    const SizedBox(height: 14.0),

                    // ── Asunto / Título del Ticket ──────────────────────────
                    Text(
                      '${ticket.folioVisual} — ${ticket.asunto}',
                      style: AppTypography.headline.copyWith(
                        color: textPrimary,
                        fontSize: 18.0,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 16.0),

                    // ── Ficha de Metadatos (Prioridad, Fecha, ID) ───────────
                    Container(
                      padding: const EdgeInsets.all(14.0),
                      decoration: BoxDecoration(
                        color: bgBoxColor,
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(color: borderBoxColor),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.flag_rounded, color: prioridadColor, size: 18.0),
                              const SizedBox(width: 8.0),
                              Text('Prioridad:', style: AppTypography.small.copyWith(color: textSecondary)),
                              const Spacer(),
                              Text(
                                ticket.prioridad,
                                style: AppTypography.body.copyWith(
                                  color: prioridadColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Divider(color: dividerColor, height: 16.0),
                          Row(
                            children: [
                              Icon(Icons.calendar_today_rounded, color: textSecondary, size: 16.0),
                              const SizedBox(width: 8.0),
                              Text('Fecha de Creación:', style: AppTypography.small.copyWith(color: textSecondary)),
                              const Spacer(),
                              Text(
                                _formatFecha(ticket.fechaCreacion),
                                style: AppTypography.body.copyWith(
                                  color: textPrimary,
                                  fontSize: 13.0,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          if (ticket.tablaReferencia != null && ticket.tablaReferencia!.isNotEmpty) ...[
                            Divider(color: dividerColor, height: 16.0),
                            Row(
                              children: [
                                const Icon(Icons.link_rounded, color: AppPalette.primary, size: 16.0),
                                const SizedBox(width: 8.0),
                                Text('Referencia:', style: AppTypography.small.copyWith(color: textSecondary)),
                                const Spacer(),
                                Text(
                                  ticket.tablaReferencia!,
                                  style: AppTypography.small.copyWith(
                                    color: AppPalette.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20.0),

                    // ── Sección: Descripción Detallada ──────────────────────
                    Row(
                      children: [
                        const Icon(Icons.notes_rounded, color: AppPalette.primary, size: 18.0),
                        const SizedBox(width: 8.0),
                        Text(
                          'DESCRIPCIÓN DETALLADA',
                          style: AppTypography.small.copyWith(
                            color: textSecondary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8.0),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: bgBoxColor,
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(color: borderBoxColor),
                      ),
                      child: Text(
                        ticket.descripcion,
                        style: AppTypography.body.copyWith(
                          color: textPrimary,
                          fontSize: 14.0,
                          height: 1.4,
                        ),
                      ),
                    ),

                    // ── Sección: Respuesta / Resolución de Cierre ───────────
                    if (ticket.observacionCierre != null && ticket.observacionCierre!.trim().isNotEmpty) ...[
                      const SizedBox(height: 20.0),
                      Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, color: AppPalette.success, size: 18.0),
                          const SizedBox(width: 8.0),
                          Expanded(
                            child: Text(
                              'RESOLUCIÓN TÉCNICA / OBSERVACIÓN DE CIERRE',
                              style: AppTypography.small.copyWith(
                                color: AppPalette.success,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8.0),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16.0),
                        decoration: BoxDecoration(
                          color: resBg,
                          borderRadius: BorderRadius.circular(10.0),
                          border: Border.all(color: resBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ticket.observacionCierre!,
                              style: AppTypography.body.copyWith(
                                color: textPrimary,
                                fontSize: 14.0,
                                height: 1.4,
                              ),
                            ),
                            if (ticket.fechaCierre != null) ...[
                              const SizedBox(height: 8.0),
                              Text(
                                'Cerrado el: ${_formatFecha(ticket.fechaCierre)}',
                                style: AppTypography.small.copyWith(
                                  color: AppPalette.success,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12.0,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24.0),
                  ],
                ),
              ),

              // ── Botón de Cerrar Modal ─────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: surfaceColor,
                    foregroundColor: textPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                      side: BorderSide(color: borderBoxColor),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('CERRAR DETALLE', style: AppTypography.button.copyWith(fontWeight: FontWeight.bold, color: textPrimary, fontSize: 14)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEstadoBadge(String estado, bool isDark) {
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
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20.0),
        border: Border.all(color: border),
      ),
      child: Text(
        estado.toUpperCase(),
        style: AppTypography.small.copyWith(
          color: text,
          fontWeight: FontWeight.bold,
          fontSize: 11.0,
        ),
      ),
    );
  }
}
