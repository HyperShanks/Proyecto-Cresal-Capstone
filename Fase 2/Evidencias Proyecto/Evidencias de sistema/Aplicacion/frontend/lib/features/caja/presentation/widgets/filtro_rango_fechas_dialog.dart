import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';

/// Diálogo modal para seleccionar un rango de fechas contables con atajos rápidos (SPEC-HU-4.5).
class FiltroRangoFechasDialog extends StatefulWidget {
  final String? fechaDesdeInicial;
  final String? fechaHastaInicial;

  const FiltroRangoFechasDialog({
    super.key,
    this.fechaDesdeInicial,
    this.fechaHastaInicial,
  });

  static Future<Map<String, String>?> show(
    BuildContext context, {
    String? fechaDesde,
    String? fechaHasta,
  }) {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (context) => FiltroRangoFechasDialog(
        fechaDesdeInicial: fechaDesde,
        fechaHastaInicial: fechaHasta,
      ),
    );
  }

  @override
  State<FiltroRangoFechasDialog> createState() => _FiltroRangoFechasDialogState();
}

class _FiltroRangoFechasDialogState extends State<FiltroRangoFechasDialog> {
  late DateTime _fechaDesde;
  late DateTime _fechaHasta;
  String? _errorMensaje;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fechaDesde = widget.fechaDesdeInicial != null
        ? DateTime.tryParse(widget.fechaDesdeInicial!) ?? now
        : now.subtract(const Duration(days: 7));
    _fechaHasta = widget.fechaHastaInicial != null
        ? DateTime.tryParse(widget.fechaHastaInicial!) ?? now
        : now;
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatDisplayDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d/$m/$y';
  }

  void _aplicarAtajoAyer() {
    final ayer = DateTime.now().subtract(const Duration(days: 1));
    setState(() {
      _fechaDesde = ayer;
      _fechaHasta = ayer;
      _errorMensaje = null;
    });
  }

  void _aplicarAtajoSemanaAnterior() {
    final now = DateTime.now();
    final lunesEstaSemana = now.subtract(Duration(days: now.weekday - 1));
    final lunesSemanaAnt = lunesEstaSemana.subtract(const Duration(days: 7));
    final domingoSemanaAnt = lunesSemanaAnt.add(const Duration(days: 6));
    setState(() {
      _fechaDesde = lunesSemanaAnt;
      _fechaHasta = domingoSemanaAnt;
      _errorMensaje = null;
    });
  }

  void _aplicarAtajoMesAnterior() {
    final now = DateTime.now();
    final primerDiaEsteMes = DateTime(now.year, now.month, 1);
    final ultimoDiaMesAnt = primerDiaEsteMes.subtract(const Duration(days: 1));
    final primerDiaMesAnt = DateTime(ultimoDiaMesAnt.year, ultimoDiaMesAnt.month, 1);
    setState(() {
      _fechaDesde = primerDiaMesAnt;
      _fechaHasta = ultimoDiaMesAnt;
      _errorMensaje = null;
    });
  }

  Future<void> _seleccionarFechaDesde() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaDesde,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(
                    primary: AppPalette.primary,
                    onPrimary: Colors.white,
                    surface: AppPalette.surface,
                    onSurface: AppPalette.textPrimary,
                  )
                : ColorScheme.light(
                    primary: AppPalette.primary,
                    onPrimary: Colors.white,
                    surface: AppPalette.surfaceLight,
                    onSurface: AppPalette.textPrimaryLight,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted || picked == null) return;
    setState(() {
      _fechaDesde = picked;
      if (_fechaDesde.isAfter(_fechaHasta)) {
        _fechaHasta = _fechaDesde;
      }
      _errorMensaje = null;
    });
  }

  Future<void> _seleccionarFechaHasta() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fechaHasta,
      firstDate: _fechaDesde,
      lastDate: DateTime(2030),
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? ColorScheme.dark(
                    primary: AppPalette.primary,
                    onPrimary: Colors.white,
                    surface: AppPalette.surface,
                    onSurface: AppPalette.textPrimary,
                  )
                : ColorScheme.light(
                    primary: AppPalette.primary,
                    onPrimary: Colors.white,
                    surface: AppPalette.surfaceLight,
                    onSurface: AppPalette.textPrimaryLight,
                  ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted || picked == null) return;
    setState(() {
      _fechaHasta = picked;
      _errorMensaje = null;
    });
  }

  void _confirmar() {
    if (_fechaDesde.isAfter(_fechaHasta)) {
      setState(() {
        _errorMensaje = 'La fecha de inicio no puede ser posterior a la de término.';
      });
      return;
    }

    Navigator.of(context).pop({
      'desde': _formatDate(_fechaDesde),
      'hasta': _formatDate(_fechaHasta),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppPalette.surfaceLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppPalette.neutral.withValues(alpha: 0.2),
        ),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppPalette.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.date_range_rounded,
              color: AppPalette.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Rango de Fechas Contables',
            style: AppTypography.title.copyWith(
              color: AppPalette.textPrimaryLight,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Seleccione un rango personalizado o use un atajo rápido:',
              style: AppTypography.small.copyWith(
                color: AppPalette.textSecondaryLight,
              ),
            ),
            const SizedBox(height: 14),

            // Atajos Rápidos
            Row(
              children: [
                _buildAtajoButton('Ayer', _aplicarAtajoAyer),
                const SizedBox(width: 8),
                _buildAtajoButton('Semana Anterior', _aplicarAtajoSemanaAnterior),
                const SizedBox(width: 8),
                _buildAtajoButton('Mes Anterior', _aplicarAtajoMesAnterior),
              ],
            ),
            const SizedBox(height: 18),

            // Selectores de Fecha Desde / Hasta
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DESDE',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textSecondaryLight,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _seleccionarFechaDesde,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppPalette.backgroundLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppPalette.neutral.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDisplayDate(_fechaDesde),
                                style: AppTypography.body.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppPalette.textPrimaryLight,
                                ),
                              ),
                              const Icon(
                                Icons.calendar_today_rounded,
                                size: 16,
                                color: AppPalette.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HASTA',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.textSecondaryLight,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: _seleccionarFechaHasta,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppPalette.backgroundLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppPalette.neutral.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDisplayDate(_fechaHasta),
                                style: AppTypography.body.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppPalette.textPrimaryLight,
                                ),
                              ),
                              const Icon(
                                Icons.calendar_today_rounded,
                                size: 16,
                                color: AppPalette.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (_errorMensaje != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMensaje!,
                style: AppTypography.small.copyWith(
                  color: AppPalette.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            backgroundColor: Colors.white,
            side: const BorderSide(color: AppPalette.borderLight),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancelar',
            style: AppTypography.button.copyWith(
              fontFamily: AppTypography.fontFamily,
              color: AppPalette.textSecondaryLight,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            backgroundColor: AppPalette.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: _confirmar,
          child: Text(
            'Aplicar Rango',
            style: AppTypography.button.copyWith(
              fontFamily: AppTypography.fontFamily,
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAtajoButton(String label, VoidCallback onTap) {
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          side: BorderSide(
            color: AppPalette.neutral.withValues(alpha: 0.25),
          ),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: AppTypography.button.copyWith(
            fontFamily: AppTypography.fontFamily,
            color: AppPalette.textPrimaryLight,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
