import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import 'crear_ticket_screen.dart';
import 'tickets_list_screen.dart';

import '../widgets/soporte_desktop_view.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TICKETS SCREEN — Pantalla principal del módulo de soporte (Theme-Aware)
// Se adapta dinámicamente según la arquitectura ortogonal (SSOT):
// - Tema cromático: Heredado del usuario autenticado (ThemeController / Theme.of(context)).
// - Layout geométrico:
//   * Pantallas amplias (ancho >= 768px): Renderiza SoporteDesktopView con tabla estructurada y formulario.
//   * Pantallas compactas (ancho < 768px): Renderiza vista compacta TabBarView.
// ─────────────────────────────────────────────────────────────────────────────
class TicketsScreen extends StatelessWidget {
  const TicketsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgScreen = isDark ? AppPalette.background : AppPalette.backgroundLight;

    if (isDesktop) {
      return Scaffold(
        backgroundColor: bgScreen,
        body: const SafeArea(
          child: SoporteDesktopView(),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bgScreen,
        appBar: _buildAppBar(context, isDark),
        body: const TabBarView(
          children: [
            CrearTicketScreen(),
            TicketsListScreen(),
          ],
        ),
      ),
    );
  }

  // ── AppBar con pestañas adaptativas (Dark Mode PDA / Light Mode Caja) ───────
  AppBar _buildAppBar(BuildContext context, bool isDark) {
    final surfaceColor = isDark ? AppPalette.surface : AppPalette.surfaceLight;
    final textPrimaryColor = isDark ? AppPalette.textPrimary : AppPalette.textPrimaryLight;
    final textSecondaryColor = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;
    final borderColor = isDark ? AppPalette.neutral.withValues(alpha: 0.2) : AppPalette.borderLight;

    return AppBar(
      backgroundColor: surfaceColor,
      foregroundColor: textPrimaryColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: Border(
        bottom: BorderSide(color: borderColor, width: 1),
      ),
      title: Text(
        'Soporte Técnico e Incidencias',
        style: AppTypography.title.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: textPrimaryColor,
        ),
      ),
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: textPrimaryColor, size: 18),
        tooltip: 'Volver',
        onPressed: () => Navigator.of(context).pop(),
      ),
      bottom: TabBar(
        indicatorColor: AppPalette.primary,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: AppPalette.primary,
        unselectedLabelColor: textSecondaryColor,
        labelStyle: AppTypography.button.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle: AppTypography.small.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
        tabs: const [
          Tab(
            icon: Icon(Icons.add_circle_outline_rounded, size: 20),
            text: 'CREAR TICKET',
          ),
          Tab(
            icon: Icon(Icons.list_alt_rounded, size: 20),
            text: 'MIS TICKETS',
          ),
        ],
      ),
    );
  }
}
