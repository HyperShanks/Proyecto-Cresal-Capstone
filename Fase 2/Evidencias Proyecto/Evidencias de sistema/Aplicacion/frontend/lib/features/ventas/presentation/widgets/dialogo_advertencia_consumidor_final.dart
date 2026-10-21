import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';

/// Diálogo modal de advertencia preventiva al seleccionar "Consumidor Final" (Sin RUT).
///
/// Promueve la cultura de captura de leads y datos de cliente en la empresa,
/// inhabilitando el botón de confirmación con un temporizador de 3 segundos
/// para disuadir la omisión impulsiva de datos del comprador.
class DialogoAdvertenciaConsumidorFinal extends StatefulWidget {
  final int duracionSegundos;

  const DialogoAdvertenciaConsumidorFinal({
    super.key,
    this.duracionSegundos = 3,
  });

  /// Método estático de conveniencia para mostrar el diálogo.
  /// Retorna `true` si el vendedor esperó los 3 segundos y confirmó continuar sin datos.
  static Future<bool?> mostrar(
    BuildContext context, {
    int duracionSegundos = 3,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          DialogoAdvertenciaConsumidorFinal(duracionSegundos: duracionSegundos),
    );
  }

  @override
  State<DialogoAdvertenciaConsumidorFinal> createState() =>
      _DialogoAdvertenciaConsumidorFinalState();
}

class _DialogoAdvertenciaConsumidorFinalState
    extends State<DialogoAdvertenciaConsumidorFinal> {
  late int _segundosRestantes;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _segundosRestantes = widget.duracionSegundos;
    if (_segundosRestantes > 0) {
      _iniciarCuentaRegresiva();
    }
  }

  void _iniciarCuentaRegresiva() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_segundosRestantes > 1) {
        setState(() {
          _segundosRestantes--;
        });
      } else {
        setState(() {
          _segundosRestantes = 0;
        });
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppPalette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppPalette.warning.withValues(alpha: 0.35)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppPalette.warning.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: AppPalette.warning,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Datos de Cliente Requeridos',
                  style: AppTypography.title.copyWith(
                    color: AppPalette.textPrimary,
                    fontSize: 16.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Políticas Comerciales de Cresal',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Caja con la advertencia clave exigida
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppPalette.warning.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.contact_mail_outlined,
                    color: AppPalette.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Es vital para la empresa los datos del cliente, ¿estás seguro que quieres continuar?',
                      style: AppTypography.body.copyWith(
                        color: AppPalette.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Impacto de omitir la identificación del comprador:',
              style: AppTypography.small.copyWith(
                color: AppPalette.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 8),
            _buildCheckItem(
              'Impide emitir y asociar la garantía legal del repuesto a una persona.',
            ),
            _buildCheckItem(
              'No se podrán enviar comprobantes de orden ni seguimiento por WhatsApp o correo.',
            ),
            _buildCheckItem(
              'Dificulta la entrega en bodega si el cliente extravía su número de orden.',
            ),
            const SizedBox(height: 14),

            // Banner del contador de seguridad de 3 segundos
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppPalette.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _segundosRestantes > 0
                      ? AppPalette.warning.withValues(alpha: 0.3)
                      : AppPalette.success.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_segundosRestantes > 0) ...[
                    SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        value: widget.duracionSegundos > 0
                            ? (widget.duracionSegundos - _segundosRestantes) /
                                  widget.duracionSegundos.toDouble()
                            : 0,
                        color: AppPalette.warning,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Por política interna, espera ${_segundosRestantes}s para confirmar...',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.warning,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ] else ...[
                    const Icon(
                      Icons.check_circle_outline,
                      color: AppPalette.success,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tiempo cumplido. Puedes proceder como Consumidor Final.',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.success,
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              Expanded(child: _buildBotonCancelar()),
              const SizedBox(width: 8),
              Expanded(child: _buildBotonConfirmar()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBotonConfirmar() {
    return ElevatedButton.icon(
      key: const Key('btn_confirmar_consumidor_final'),
      onPressed: _segundosRestantes == 0
          ? () => Navigator.of(context).pop(true)
          : null,
      icon: Icon(
        Icons.no_accounts_outlined,
        size: 16,
        color: _segundosRestantes == 0 ? Colors.white : Colors.white38,
      ),
      label: Text(
        _segundosRestantes > 0
            ? 'CONTINUAR (${_segundosRestantes}s)'
            : 'CONTINUAR',
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: _segundosRestantes == 0 ? Colors.white : Colors.white38,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFD97706),
        disabledBackgroundColor: const Color(0xFFD97706).withValues(alpha: 0.2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildBotonCancelar() {
    return OutlinedButton(
      key: const Key('btn_cancelar_consumidor_final'),
      onPressed: () => Navigator.of(context).pop(false),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: AppPalette.primary.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        'VOLVER Y PEDIR DATOS',
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
        style: AppTypography.button.copyWith(
          color: AppPalette.primary,
          fontWeight: FontWeight.bold,
          fontSize: 11.5,
        ),
      ),
    );
  }

  Widget _buildCheckItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.arrow_right_rounded,
            color: AppPalette.warning,
            size: 18,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: AppTypography.small.copyWith(
                color: AppPalette.textSecondary,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
