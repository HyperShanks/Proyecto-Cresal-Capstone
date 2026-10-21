// lib/features/alertas/presentation/widgets/panel_tareas_desplegable.dart

import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../models/tarea_alerta.dart';
import '../../services/bodega_polling_service.dart';
import '../../services/logistica_service.dart';

/// Modal Bottom Sheet Desplegable de Tareas Operativas de Bodega (SPEC-HU-06).
/// Se abre al pulsar el Badge numérico del AppBar.
class PanelTareasDesplegable extends StatefulWidget {
  const PanelTareasDesplegable({super.key});

  /// Muestra el panel desplegable de tareas operativas
  static Future<void> mostrar(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const PanelTareasDesplegable(),
    );
  }

  @override
  State<PanelTareasDesplegable> createState() => _PanelTareasDesplegableState();
}

class _PanelTareasDesplegableState extends State<PanelTareasDesplegable> {
  bool _isRefreshing = false;
  String _filtroSeleccionado = 'TODAS'; // 'TODAS', 'PREPARACION', 'ENTREGA', 'IMPRESION'
  final Set<String> _procesandoDetalles = {};

  Future<void> _refrescarTareas() async {
    setState(() => _isRefreshing = true);
    await BodegaPollingService.instance.procesarCiclo();
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  Future<void> _marcarListo(TareaAlerta tarea) async {
    if (tarea.idDetalle == null || tarea.idDetalle!.isEmpty) return;
    final idDetalle = tarea.idDetalle!;

    setState(() => _procesandoDetalles.add(idDetalle));
    try {
      final ok = await LogisticaService.completarPreentrega(idDetalle);
      if (ok) {
        BodegaPollingService.instance.decrementarPendiente();
        await BodegaPollingService.instance.procesarCiclo();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppPalette.success,
              content: Text('✓ Preparación marcada como Lista'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppPalette.error,
            content: Text('Error: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _procesandoDetalles.remove(idDetalle));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 15,
            spreadRadius: 2,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Barra de agarre superior
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header con Título, Botón de Refresco y Cierre
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppPalette.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.assignment_outlined, color: AppPalette.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tareas Operativas',
                        style: AppTypography.title.copyWith(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Carga de trabajo en tiempo real',
                        style: AppTypography.small.copyWith(color: AppPalette.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: _isRefreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppPalette.primary),
                        )
                      : const Icon(Icons.refresh, color: AppPalette.textSecondary, size: 22),
                  tooltip: 'Actualizar tareas',
                  onPressed: _isRefreshing ? null : _refrescarTareas,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppPalette.textSecondary, size: 22),
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 20),

          // Métricas resumidas de carga
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ValueListenableBuilder<ResumenAlertasModel>(
              valueListenable: BodegaPollingService.instance.resumenNotifier,
              builder: (context, resumen, _) {
                return Row(
                  children: [
                    _buildStatChip(
                      label: 'Preparación',
                      count: resumen.desglosePreparacion,
                      color: AppPalette.secondary,
                      icon: Icons.inventory_2_outlined,
                      isSelected: _filtroSeleccionado == 'PREPARACION',
                      onTap: () => setState(() {
                        _filtroSeleccionado = _filtroSeleccionado == 'PREPARACION' ? 'TODAS' : 'PREPARACION';
                      }),
                    ),
                    const SizedBox(width: 8),
                    _buildStatChip(
                      label: 'Salidas/Barrera',
                      count: resumen.desgloseEntregas,
                      color: AppPalette.primary,
                      icon: Icons.local_shipping_outlined,
                      isSelected: _filtroSeleccionado == 'ENTREGA',
                      onTap: () => setState(() {
                        _filtroSeleccionado = _filtroSeleccionado == 'ENTREGA' ? 'TODAS' : 'ENTREGA';
                      }),
                    ),
                    const SizedBox(width: 8),
                    _buildStatChip(
                      label: 'Reingresos',
                      count: resumen.desgloseReingresos,
                      color: AppPalette.success,
                      icon: Icons.assignment_return_outlined,
                      isSelected: _filtroSeleccionado == 'REINGRESO',
                      onTap: () => setState(() {
                        _filtroSeleccionado = _filtroSeleccionado == 'REINGRESO' ? 'TODAS' : 'REINGRESO';
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Lista de Tareas
          Flexible(
            child: ValueListenableBuilder<List<TareaAlerta>>(
              valueListenable: BodegaPollingService.instance.tareasNotifier,
              builder: (context, tareas, _) {
                var filtradas = tareas;
                if (_filtroSeleccionado == 'PREPARACION') {
                  filtradas = tareas.where((t) => t.tipoAlerta == 'PREPARACION' || t.tipoAlerta == 'TRASLADO').toList();
                } else if (_filtroSeleccionado == 'ENTREGA') {
                  filtradas = tareas.where((t) => t.tipoAlerta == 'LIBERADA').toList();
                } else if (_filtroSeleccionado == 'IMPRESION') {
                  filtradas = tareas.where((t) => t.tipoAlerta == 'IMPRESION').toList();
                } else if (_filtroSeleccionado == 'REINGRESO') {
                  filtradas = tareas.where((t) => t.tipoAlerta == 'REINGRESO').toList();
                }

                if (filtradas.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppPalette.success.withValues(alpha: 0.1),
                          ),
                          child: const Icon(Icons.check_circle_outline, color: AppPalette.success, size: 40),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '¡Excelente! Sin tareas pendientes',
                          style: AppTypography.title.copyWith(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'No hay tareas asignadas en este momento para tu sucursal.',
                          style: AppTypography.small.copyWith(color: AppPalette.textSecondary, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtradas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, index) {
                    final t = filtradas[index];
                    return _buildTaskTile(t);
                  },
                );
              },
            ),
          ),

          // Botón inferior para ir a Tablero Completo
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.primary,
                  foregroundColor: AppPalette.textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
                label: const Text('VER TABLERO COMPLETO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.pushNamed(context, '/alertas');
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: isSelected ? color.withValues(alpha: 0.22) : AppPalette.background,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? color : Colors.white12,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 14, color: color),
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? AppPalette.textPrimary : AppPalette.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskTile(TareaAlerta tarea) {
    Color badgeColor;
    IconData badgeIcon;
    String badgeLabel;

    switch (tarea.tipoAlerta) {
      case 'PREPARACION':
        badgeColor = AppPalette.secondary;
        badgeIcon = Icons.inventory_2_outlined;
        badgeLabel = 'PREPARACIÓN';
        break;
      case 'TRASLADO':
        badgeColor = AppPalette.primary;
        badgeIcon = Icons.sync_alt;
        badgeLabel = 'TRASLADO';
        break;
      case 'LIBERADA':
        badgeColor = AppPalette.success;
        badgeIcon = Icons.check_circle_outline;
        badgeLabel = 'LIBERADA';
        break;
      case 'IMPRESION':
        badgeColor = Colors.orangeAccent;
        badgeIcon = Icons.qr_code_2;
        badgeLabel = 'QR IMPRESIÓN';
        break;
      case 'REINGRESO':
        badgeColor = const Color(0xFFFFB300);
        badgeIcon = Icons.assignment_return_outlined;
        badgeLabel = 'REINGRESO';
        break;
      default:
        badgeColor = AppPalette.textSecondary;
        badgeIcon = Icons.task_alt;
        badgeLabel = tarea.tipoAlerta;
    }

    final isProcessing = tarea.idDetalle != null && _procesandoDetalles.contains(tarea.idDetalle!);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 12, color: badgeColor),
                    const SizedBox(width: 4),
                    Text(
                      badgeLabel,
                      style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Text(
                '📍 ${tarea.ubicacion}',
                style: AppTypography.small.copyWith(color: AppPalette.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tarea.tituloPieza,
            style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (tarea.ordenRef != null && tarea.ordenRef!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              tarea.ordenRef!,
              style: AppTypography.small.copyWith(color: AppPalette.secondary, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),

          // Botón de acción rápida
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (tarea.tipoAlerta == 'PREPARACION' || tarea.tipoAlerta == 'TRASLADO') ...[
                SizedBox(
                  height: 32,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: isProcessing
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                        : const Icon(Icons.check, size: 14),
                    label: Text(isProcessing ? 'Guardando...' : 'Marcar Listo', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: isProcessing ? null : () => _marcarListo(tarea),
                  ),
                ),
              ] else if (tarea.tipoAlerta == 'REINGRESO') ...[
                SizedBox(
                  height: 32,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00A3FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 14),
                    label: const Text('Reingresar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.pushNamed(context, '/alertas');
                    },
                  ),
                ),
              ] else if (tarea.tipoAlerta == 'LIBERADA') ...[
                SizedBox(
                  height: 32,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppPalette.primary,
                      side: const BorderSide(color: AppPalette.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.qr_code_scanner, size: 14),
                    label: const Text('Escaneo Barrera', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.pushNamed(context, '/alertas');
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
