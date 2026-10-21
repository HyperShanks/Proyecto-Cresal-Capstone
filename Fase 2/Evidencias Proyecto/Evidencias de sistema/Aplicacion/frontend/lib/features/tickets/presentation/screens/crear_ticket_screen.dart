import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../services/ticket_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CREAR TICKET SCREEN — Formulario reactivo Theme-Aware (HU-06 / CA-01)
// Permite reportar requerimientos con Categoría, Prioridad, Asunto y Descripción.
// Coexiste armónicamente en Dark Mode (PDA / Celular) y Light Mode (Caja / Desktop).
// ─────────────────────────────────────────────────────────────────────────────
class CrearTicketScreen extends StatefulWidget {
  const CrearTicketScreen({super.key});

  @override
  State<CrearTicketScreen> createState() => _CrearTicketScreenState();
}

class _CrearTicketScreenState extends State<CrearTicketScreen> {
  // ── Opciones de los selectores (SPEC-HU-06 / CA-01) ─────────────────────────
  static const List<String> _tiposTicket = [
    'Error de App',
    'Anulación / Corrección de Orden',
    'Problema de Hardware',
    'Sugerencia',
    'Otro',
  ];

  static const List<String> _prioridades = ['Baja', 'Media', 'Alta', 'Urgente'];

  // ── Estado del formulario ──────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  String _tipoSeleccionado = _tiposTicket.first;
  String _prioridadSeleccionada = 'Media';
  final _asuntoController = TextEditingController();
  final _descripcionController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _asuntoController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  // ── Helper de color por prioridad ──────────────────────────────────────────
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

  // ── Envío del ticket ───────────────────────────────────────────────────────
  Future<void> _enviarTicket() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final result = await TicketService.crearTicket(
      tipoTicket: _tipoSeleccionado,
      prioridad: _prioridadSeleccionada,
      asunto: _asuntoController.text.trim(),
      descripcion: _descripcionController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result.success) {
      _asuntoController.clear();
      _descripcionController.clear();
      setState(() {
        _tipoSeleccionado = _tiposTicket.first;
        _prioridadSeleccionada = 'Media';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ticket enviado correctamente a administración.',
                  style: AppTypography.body.copyWith(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: AppPalette.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  result.errorMessage ?? 'Error al enviar el ticket.',
                  style: AppTypography.body.copyWith(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ],
          ),
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppPalette.surface : AppPalette.surfaceLight;
    final borderColor = isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight;
    final textPrimary = isDark ? AppPalette.textPrimary : AppPalette.textPrimaryLight;
    final textSecondary = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;
    final dividerColor = isDark ? AppPalette.neutral.withValues(alpha: 0.2) : AppPalette.borderLight;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Encabezado ────────────────────────────────────────────────
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppPalette.primary.withValues(alpha: isDark ? 0.2 : 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.contact_support_rounded,
                          color: AppPalette.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Nuevo Requerimiento de Soporte',
                              style: AppTypography.title.copyWith(
                                color: textPrimary,
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Notifique incidentes operativos, errores de sistema o solicitudes a administración.',
                              style: AppTypography.small.copyWith(
                                color: textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Divider(color: dividerColor, height: 1),
                  ),

                  // ── Tipo de Ticket (Dropdown) ──────────────────────────────────
                  _SectionLabel(label: 'TIPO DE TICKET (CATEGORÍA)', isDark: isDark),
                  const SizedBox(height: 8),
                  _buildDropdown(isDark),
                  const SizedBox(height: 20),

                  // ── Prioridad (Botones seleccionables) ────────────────────────
                  _SectionLabel(label: 'NIVEL DE PRIORIDAD', isDark: isDark),
                  const SizedBox(height: 8),
                  _buildPrioridadSelector(isDark),
                  const SizedBox(height: 20),

                  // ── Asunto ─────────────────────────────────────────────────────
                  _SectionLabel(label: 'ASUNTO DEL REPORTE (MÁX 150 CARACTERES)', isDark: isDark),
                  const SizedBox(height: 8),
                  _buildAsuntoField(isDark),
                  const SizedBox(height: 20),

                  // ── Descripción ────────────────────────────────────────────────
                  _SectionLabel(label: 'DESCRIPCIÓN DETALLADA (MÁX 1000 CARACTERES)', isDark: isDark),
                  const SizedBox(height: 8),
                  _buildDescripcionField(isDark),
                  const SizedBox(height: 28),

                  // ── Botón Enviar ───────────────────────────────────────────────
                  _buildEnviarButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Dropdown de tipo ───────────────────────────────────────────────────────
  Widget _buildDropdown(bool isDark) {
    final bgColor = isDark ? AppPalette.background : AppPalette.surfaceLight;
    final borderColor = isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight;
    final dropdownBg = isDark ? AppPalette.surface : AppPalette.surfaceLight;
    final textColor = isDark ? AppPalette.textPrimary : AppPalette.textPrimaryLight;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _tipoSeleccionado,
          dropdownColor: dropdownBg,
          style: AppTypography.body.copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppPalette.primary),
          items: _tiposTicket
              .map(
                (tipo) => DropdownMenuItem(
                  value: tipo,
                  child: Text(
                    tipo,
                    style: AppTypography.body.copyWith(
                      color: textColor,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (val) {
            if (val != null) setState(() => _tipoSeleccionado = val);
          },
        ),
      ),
    );
  }

  // ── Selector de prioridad (chips táctiles ≥ 48dp) ─────────────────────────
  Widget _buildPrioridadSelector(bool isDark) {
    final unselectedBg = isDark ? AppPalette.background : AppPalette.surfaceLight;
    final unselectedBorder = isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight;
    final unselectedText = isDark ? AppPalette.textSecondary : AppPalette.textPrimaryLight;

    return Row(
      children: _prioridades.map((p) {
        final isSelected = p == _prioridadSeleccionada;
        final color = _colorForPrioridad(p);
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _prioridadSeleccionada = p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              height: 48,
              decoration: BoxDecoration(
                color: isSelected
                    ? color.withValues(alpha: isDark ? 0.25 : 0.15)
                    : unselectedBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? color : unselectedBorder,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      p,
                      style: AppTypography.small.copyWith(
                        color: isSelected ? color : unselectedText,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Campo Asunto ───────────────────────────────────────────────────────────
  Widget _buildAsuntoField(bool isDark) {
    final textColor = isDark ? AppPalette.textPrimary : AppPalette.textPrimaryLight;
    final hintColor = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;
    final fillColor = isDark ? AppPalette.background : AppPalette.surfaceLight;
    final borderColor = isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight;

    return TextFormField(
      controller: _asuntoController,
      style: AppTypography.body.copyWith(color: textColor),
      maxLength: 150,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        filled: true,
        fillColor: fillColor,
        hintText: 'Ej: Descuadre en cierre de turno o POS sin conexión',
        hintStyle: AppTypography.small.copyWith(color: hintColor),
        counterStyle: AppTypography.small.copyWith(color: hintColor),
        prefixIcon: const Icon(Icons.title_rounded, color: AppPalette.primary),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppPalette.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppPalette.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppPalette.error, width: 2),
        ),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) {
          return 'El asunto no puede estar vacío';
        }
        if (v.trim().length < 5) {
          return 'El asunto debe tener al menos 5 caracteres';
        }
        return null;
      },
    );
  }

  // ── Campo Descripción (multilínea) ─────────────────────────────────────────
  Widget _buildDescripcionField(bool isDark) {
    final textColor = isDark ? AppPalette.textPrimary : AppPalette.textPrimaryLight;
    final hintColor = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;
    final fillColor = isDark ? AppPalette.background : AppPalette.surfaceLight;
    final borderColor = isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight;

    return TextFormField(
      controller: _descripcionController,
      style: AppTypography.body.copyWith(color: textColor),
      maxLength: 1000,
      maxLines: 5,
      minLines: 4,
      decoration: InputDecoration(
        filled: true,
        fillColor: fillColor,
        hintText:
            'Describa el incidente con detalle: folio de orden afectada, pasos previos, '
            'mensaje de error o acción solicitada...',
        hintStyle: AppTypography.small.copyWith(color: hintColor),
        counterStyle: AppTypography.small.copyWith(color: hintColor),
        alignLabelWithHint: true,
        prefixIcon: const Padding(
          padding: EdgeInsets.only(bottom: 60),
          child: Icon(Icons.notes_rounded, color: AppPalette.primary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppPalette.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppPalette.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppPalette.error, width: 2),
        ),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) {
          return 'La descripción no puede estar vacía';
        }
        if (v.trim().length < 10) {
          return 'La descripción debe tener al menos 10 caracteres';
        }
        return null;
      },
    );
  }

  // ── Botón Enviar ───────────────────────────────────────────────────────────
  Widget _buildEnviarButton() {
    if (_isLoading) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: CircularProgressIndicator(
            color: AppPalette.primary,
            strokeWidth: 2.5,
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.primary,
          foregroundColor: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: _enviarTicket,
        icon: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
        label: Text(
          'ENVIAR TICKET DE SOPORTE',
          style: AppTypography.button.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER — Etiqueta de sección del formulario Theme-Aware
// ─────────────────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  final bool isDark;

  const _SectionLabel({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.small.copyWith(
        color: isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    );
  }
}
