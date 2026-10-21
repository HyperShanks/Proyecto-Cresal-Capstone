import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../models/ticket_model.dart';
import '../../services/ticket_service.dart';
import '../widgets/ticket_card.dart';
import '../widgets/ticket_detail_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TICKETS LIST SCREEN — Bandeja de historial "Mis Tickets" (Theme-Aware)
// Consume GET /api/v1/tickets/mis-tickets con Shimmer y refresco.
// Se adapta dinámicamente tanto a Dark Mode (PDA / Celular) como a Light Mode (Caja / Desktop).
// ─────────────────────────────────────────────────────────────────────────────
class TicketsListScreen extends StatefulWidget {
  const TicketsListScreen({super.key});

  @override
  State<TicketsListScreen> createState() => _TicketsListScreenState();
}

class _TicketsListScreenState extends State<TicketsListScreen> {
  late Future<List<TicketModel>> _ticketsFuture;

  @override
  void initState() {
    super.initState();
    _cargarTickets();
  }

  void _cargarTickets() {
    setState(() {
      _ticketsFuture = TicketService.obtenerMisTickets();
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppPalette.surface : AppPalette.surfaceLight;

    return FutureBuilder<List<TicketModel>>(
      future: _ticketsFuture,
      builder: (context, snapshot) {
        // ── Cargando ─────────────────────────────────────────────────────────
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildShimmerLoader(isDark);
        }

        // ── Error de red / API ────────────────────────────────────────────────
        if (snapshot.hasError) {
          return _buildErrorState(snapshot.error.toString(), isDark);
        }

        final tickets = snapshot.data ?? [];

        // ── Sin tickets ───────────────────────────────────────────────────────
        if (tickets.isEmpty) {
          return _buildEmptyState(isDark);
        }

        // ── Lista de tickets ──────────────────────────────────────────────────
        return RefreshIndicator(
          color: AppPalette.primary,
          backgroundColor: surfaceColor,
          onRefresh: () async => _cargarTickets(),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                itemCount: tickets.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final ticket = tickets[index];
                  return TicketCard(
                    ticket: ticket,
                    onTap: () => TicketDetailSheet.mostrar(context, ticket),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Shimmer / loader placeholder ──────────────────────────────────────────
  Widget _buildShimmerLoader(bool isDark) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          itemCount: 4,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, _) => _ShimmerCard(isDark: isDark),
        ),
      ),
    );
  }

  // ── Estado vacío ──────────────────────────────────────────────────────────
  Widget _buildEmptyState(bool isDark) {
    final surfaceColor = isDark ? AppPalette.surface : AppPalette.surfaceLight;
    final borderColor = isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight;
    final textPrimary = isDark ? AppPalette.textPrimary : AppPalette.textPrimaryLight;
    final textSecondary = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: surfaceColor,
                shape: BoxShape.circle,
                border: Border.all(color: borderColor),
              ),
              child: Icon(
                Icons.confirmation_number_outlined,
                size: 56,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No hay tickets registrados',
              style: AppTypography.title.copyWith(
                color: textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Los reportes e incidencias que envíes aparecerán en esta bandeja.',
              style: AppTypography.body.copyWith(
                color: textSecondary,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: surfaceColor,
                foregroundColor: AppPalette.primary,
                elevation: 0,
                side: BorderSide(color: borderColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: _cargarTickets,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                'Actualizar Bandeja',
                style: AppTypography.button.copyWith(
                  color: AppPalette.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Estado de error ───────────────────────────────────────────────────────
  Widget _buildErrorState(String error, bool isDark) {
    final mensaje = error.replaceFirst('Exception: ', '');
    final textPrimary = isDark ? AppPalette.textPrimary : AppPalette.textPrimaryLight;
    final textSecondary = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppPalette.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: AppPalette.error,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'No se pudieron cargar los tickets',
              style: AppTypography.title.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              mensaje,
              style: AppTypography.small.copyWith(
                color: textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: _cargarTickets,
              icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
              label: Text('REINTENTAR', style: AppTypography.button.copyWith(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHIMMER CARD — Placeholder animado Theme-Aware (Dark Mode & Light Mode)
// ─────────────────────────────────────────────────────────────────────────────
class _ShimmerCard extends StatefulWidget {
  final bool isDark;
  const _ShimmerCard({required this.isDark});

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = widget.isDark ? AppPalette.surface : AppPalette.surfaceLight;
    final borderColor = widget.isDark ? AppPalette.neutral.withValues(alpha: 0.2) : AppPalette.borderLight;
    final shimmerLineColor = widget.isDark
        ? AppPalette.neutral.withValues(alpha: _animation.value * 0.4)
        : AppPalette.borderLight.withValues(alpha: _animation.value + 0.3);

    return AnimatedBuilder(
      animation: _animation,
      builder: (_, _) {
        return Container(
          height: 96,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ShimmerLine(
                width: 100,
                height: 12,
                color: shimmerLineColor,
              ),
              const SizedBox(height: 10),
              _ShimmerLine(
                width: double.infinity,
                height: 14,
                color: shimmerLineColor,
              ),
              const SizedBox(height: 10),
              _ShimmerLine(
                width: 160,
                height: 11,
                color: shimmerLineColor,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ShimmerLine extends StatelessWidget {
  final double width;
  final double height;
  final Color color;

  const _ShimmerLine({
    required this.width,
    required this.height,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
