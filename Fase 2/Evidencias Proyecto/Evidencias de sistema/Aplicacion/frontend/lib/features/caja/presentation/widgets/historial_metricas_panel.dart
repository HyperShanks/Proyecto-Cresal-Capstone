import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../models/historial_caja_model.dart';
import 'cobro_pendiente_card.dart';

/// Panel superior de 4 tarjetas con métricas de arqueo y cuadre de caja (SPEC-HU-4.5).
/// Diseño responsivo adaptable a pantallas de escritorio amplio, POS compacto y tablets.
class HistorialMetricasPanel extends StatelessWidget {
  final ResumenCuadreCajaModel resumen;

  const HistorialMetricasPanel({super.key, required this.resumen});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final card1 = _buildMetricCard(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Total Recaudado',
          value: CobroPendienteCard.formatClp(resumen.totalRecaudado),
          subtitle: '${resumen.totalOrdenesPagadas} órdenes pagadas',
          color: AppPalette.primary,
        );
        final card2 = _buildMetricCard(
          icon: Icons.payments_rounded,
          title: 'Total Efectivo',
          value: CobroPendienteCard.formatClp(resumen.totalEfectivo),
          subtitle: 'Arqueo físico disponible',
          color: AppPalette.success,
        );
        final card3 = _buildMetricCard(
          icon: Icons.credit_card_rounded,
          title: 'Total Tarjetas POS',
          value: CobroPendienteCard.formatClp(resumen.totalPos),
          subtitle:
              'Déb: ${CobroPendienteCard.formatClp(resumen.totalDebito)} • Créd: ${CobroPendienteCard.formatClp(resumen.totalCredito)}',
          color: const Color(0xFF4F46E5),
        );
        final card4 = _buildMetricCard(
          icon: Icons.swap_horiz_rounded,
          title: 'Transferencias / Cheques',
          value: CobroPendienteCard.formatClp(
            resumen.totalTransferencia + resumen.totalCheque,
          ),
          subtitle:
              'Transf: ${CobroPendienteCard.formatClp(resumen.totalTransferencia)} • Chq: ${CobroPendienteCard.formatClp(resumen.totalCheque)}',
          color: AppPalette.secondary,
        );

        // Pantallas estrechas (< 640px): 1 columna apilada
        if (constraints.maxWidth < 640) {
          return Column(
            children: [
              card1,
              const SizedBox(height: 10),
              card2,
              const SizedBox(height: 10),
              card3,
              const SizedBox(height: 10),
              card4,
            ],
          );
        }

        // Pantallas medianas o terminales POS compactos (< 1000px): Grilla 2x2
        if (constraints.maxWidth < 1000) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: card1),
                  const SizedBox(width: 12),
                  Expanded(child: card2),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: card3),
                  const SizedBox(width: 12),
                  Expanded(child: card4),
                ],
              ),
            ],
          );
        }

        // Escritorio amplio (>= 1000px): Fila horizontal de 4 métricas
        return Row(
          children: [
            Expanded(child: card1),
            const SizedBox(width: 14),
            Expanded(child: card2),
            const SizedBox(width: 14),
            Expanded(child: card3),
            const SizedBox(width: 14),
            Expanded(child: card4),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppPalette.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppPalette.neutral.withValues(alpha: 0.18),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: AppTypography.cardTitle.copyWith(
                    color: AppPalette.textSecondaryLight,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTypography.title.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppPalette.textPrimaryLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Tooltip(
                  message: subtitle,
                  child: Text(
                    subtitle,
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textSecondaryLight,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
