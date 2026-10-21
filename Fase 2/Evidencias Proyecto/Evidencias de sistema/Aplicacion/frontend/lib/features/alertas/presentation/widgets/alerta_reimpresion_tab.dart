// lib/features/alertas/presentation/widgets/alerta_reimpresion_tab.dart

import 'package:flutter/material.dart';
import '../../models/tarea_alerta.dart';
import 'task_card.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';

/// Pestaña de Alertas para Re-impresión de Etiquetas QR (SPEC-HU-TAREA-13).
/// Agrupa activos nuevos o paletizados que no tienen etiqueta física impresa (tipoAlerta == 'IMPRESION').
class AlertaReimpresionTab extends StatelessWidget {
  final List<TareaAlerta> tareas;
  final Future<void> Function() onRefresh;

  const AlertaReimpresionTab({
    super.key,
    required this.tareas,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (tareas.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        color: AppPalette.primary,
        backgroundColor: AppPalette.surface,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppPalette.primary.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.qr_code_scanner,
                          color: AppPalette.primary,
                          size: 56,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Sin tareas de re-impresión',
                        style: AppTypography.title.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppPalette.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Todas las piezas cuentan con su código QR físico impreso.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppPalette.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppPalette.primary,
      backgroundColor: AppPalette.surface,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        itemCount: tareas.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppPalette.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppPalette.neutral.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${tareas.length} ${tareas.length == 1 ? 'ETIQUETA POR IMPRIMIR' : 'ETIQUETAS POR IMPRIMIR'}',
                    style: AppTypography.small.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppPalette.primary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            );
          }

          final tarea = tareas[index - 1];
          return TaskCard(
            key: Key('task_card_${tarea.idTarea}'),
            tarea: tarea,
            onActualizar: onRefresh,
          );
        },
      ),
    );
  }
}
