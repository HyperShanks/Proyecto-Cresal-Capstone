import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../models/ticket_model.dart';
import '../../services/ticket_service.dart';
import 'ticket_detail_dialog.dart';

/// Vista de Escritorio para el módulo de Soporte Técnico (HU-06).
/// Implementa fielmente la estructura visual de `prototipo_caja_sprint4.html` (Líneas 983–1190):
/// - Cabecera con selector segmentado (`[+ Crear Ticket]` y `[Mis Tickets (N)]`).
/// - Pestaña 1: Formulario centrado (`maxWidth: 672`) con grid de prioridades y validaciones.
/// - Pestaña 2: Tabla de datos estructurada con filtros superiores por estado (`Todos`, `Abiertos`, `En Proceso`, `Resueltos`) y modal centrado de detalle.
class SoporteDesktopView extends StatefulWidget {
  const SoporteDesktopView({super.key});

  @override
  State<SoporteDesktopView> createState() => _SoporteDesktopViewState();
}

class _SoporteDesktopViewState extends State<SoporteDesktopView> {
  int _activeTabIndex = 0; // 0: Crear Ticket, 1: Mis Tickets
  String _filtroEstado = 'TODOS'; // TODOS, Abierto, En Proceso, Resuelto

  List<TicketModel> _tickets = [];
  bool _isLoadingTickets = false;
  String? _errorTickets;

  // ── Form State ──
  final _formKey = GlobalKey<FormState>();
  final _asuntoCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  static const List<String> _tiposTicket = [
    'Error de App',
    'Anulación / Corrección de Orden',
    'Problema de Hardware',
    'Sugerencia',
    'Otro',
  ];

  static const List<String> _prioridades = ['Baja', 'Media', 'Alta', 'Urgente'];

  String _tipoSeleccionado = _tiposTicket.first;
  String _prioridadSeleccionada = 'Media';
  bool _isSubmitting = false;
  String? _ticketToast;

  @override
  void initState() {
    super.initState();
    _cargarTickets();
  }

  @override
  void dispose() {
    _asuntoCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarTickets() async {
    setState(() {
      _isLoadingTickets = true;
      _errorTickets = null;
    });

    try {
      final tickets = await TicketService.obtenerMisTickets();
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _isLoadingTickets = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorTickets = e.toString();
        _isLoadingTickets = false;
      });
    }
  }

  Future<void> _handleEnviarTicket() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final result = await TicketService.crearTicket(
      tipoTicket: _tipoSeleccionado,
      prioridad: _prioridadSeleccionada,
      asunto: _asuntoCtrl.text.trim(),
      descripcion: _descCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (result.isOk && result.ticket != null) {
      final ticketCreado = result.ticket!;
      setState(() {
        _tickets.insert(0, ticketCreado);
        _ticketToast = 'Ticket ${ticketCreado.folioVisual} enviado correctamente al equipo de TI.';
        _asuntoCtrl.clear();
        _descCtrl.clear();
        _tipoSeleccionado = _tiposTicket.first;
        _prioridadSeleccionada = 'Media';
      });

      // Ocultar toast automáticamente tras 4 segundos
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() => _ticketToast = null);
        }
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Error al enviar el ticket.'),
          backgroundColor: AppPalette.error,
        ),
      );
    }
  }

  List<TicketModel> get _ticketsFiltrados {
    if (_filtroEstado == 'TODOS') return _tickets;
    return _tickets
        .where((t) => t.estadoTicket.toLowerCase() == _filtroEstado.toLowerCase())
        .toList();
  }

  Color _colorForPrioridad(String prioridad) {
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

  String _formatFecha(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '—';
    try {
      final String formattedIso = isoDate.contains('Z')
          ? isoDate
          : '${isoDate.replaceAll(' ', 'T')}Z';
      final dt = DateTime.parse(formattedIso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/'
          '${dt.month.toString().padLeft(2, '0')}/'
          '${dt.year} ${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgScreen = isDark ? AppPalette.background : AppPalette.backgroundLight;

    return Container(
      color: bgScreen,
      child: Column(
        children: [
          // ── 1. CABECERA CON SELECTOR SEGMENTADO (Líneas 987–1011) ──
          _buildCabecera(),

          // ── 2. ÁREA DE CONTENIDO (Pestaña Crear vs Mis Tickets) ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                children: [
                  // Toast de Éxito al enviar
                  if (_ticketToast != null) ...[
                    _buildToastExito(isDark: isDark),
                    const SizedBox(height: 16),
                  ],

                  if (_activeTabIndex == 0)
                    _buildFormularioCrear()
                  else
                    _buildTablaMisTickets(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── CABECERA Y SELECTOR SEGMENTADO ──────────────────────────────────────────
  Widget _buildCabecera() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppPalette.surface : AppPalette.surfaceLight;
    final borderColor = isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight;
    final textPrimary = isDark ? AppPalette.textPrimary : AppPalette.textPrimaryLight;
    final textSecondary = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;
    final selectorBg = isDark ? AppPalette.background : const Color(0xFFF1F5F9);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Título y Subtítulo
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MÓDULO DE INCIDENCIAS',
                style: AppTypography.small.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Soporte Técnico',
                style: AppTypography.title.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: textPrimary,
                ),
              ),
            ],
          ),

          // Selector Segmentado: [+ Crear Ticket] | [Mis Tickets (N)]
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: selectorBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Botón 1: Crear Ticket
                _buildSegmentButton(
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Crear Ticket',
                  isSelected: _activeTabIndex == 0,
                  onTap: () => setState(() => _activeTabIndex = 0),
                  isDark: isDark,
                ),

                const SizedBox(width: 4),

                // Botón 2: Mis Tickets
                _buildSegmentButton(
                  icon: Icons.list_alt_rounded,
                  label: 'Mis Tickets',
                  badgeCount: _tickets.length,
                  isSelected: _activeTabIndex == 1,
                  onTap: () {
                    setState(() => _activeTabIndex = 1);
                    _cargarTickets();
                  },
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    int? badgeCount,
    required bool isDark,
  }) {
    final activeBg = isDark ? AppPalette.surface : Colors.white;
    final textSecondary = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;
    final badgeInactiveBg = isDark ? AppPalette.surface : const Color(0xFFE2E8F0);
    final badgeInactiveText = isDark ? AppPalette.textPrimary : AppPalette.textPrimaryLight;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppPalette.primary : textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.small.copyWith(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? AppPalette.primary : textSecondary,
              ),
            ),
            if (badgeCount != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppPalette.primary.withValues(alpha: 0.12)
                      : badgeInactiveBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$badgeCount',
                  style: AppTypography.small.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? AppPalette.primary : badgeInactiveText,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── TOAST DE ÉXITO ────────────────────────────────────────────────────────
  Widget _buildToastExito({bool isDark = false}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 672),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppPalette.success.withValues(alpha: 0.12) : AppPalette.successBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppPalette.success.withValues(alpha: 0.3) : AppPalette.successBorder,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: AppPalette.success, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _ticketToast!,
              style: AppTypography.small.copyWith(
                color: AppPalette.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16, color: AppPalette.success),
            onPressed: () => setState(() => _ticketToast = null),
            splashRadius: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ── SUB-PESTAÑA 1: FORMULARIO CENTRADO (Líneas 1026–1104) ───────────────────
  Widget _buildFormularioCrear() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppPalette.surface : AppPalette.surfaceLight;
    final borderColor = isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight;
    final textPrimary = isDark ? AppPalette.textPrimary : AppPalette.textPrimaryLight;
    final textSecondary = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 672),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado de la Tarjeta
              Text(
                'Nuevo Ticket de Soporte',
                style: AppTypography.title.copyWith(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Complete los datos del incidente o consulta técnica para el equipo de TI.',
                style: AppTypography.small.copyWith(
                  color: textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 24),

              // ── Campo 1: Tipo de Ticket ──
              _buildFieldLabel('TIPO DE TICKET (CATEGORÍA)', textSecondary),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _tipoSeleccionado,
                decoration: _inputDecoration(isDark: isDark, borderColor: borderColor),
                style: AppTypography.body.copyWith(
                  color: textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                dropdownColor: surfaceColor,
                items: _tiposTicket.map((tipo) {
                  return DropdownMenuItem(
                    value: tipo,
                    child: Text(tipo),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _tipoSeleccionado = val);
                },
              ),
              const SizedBox(height: 20),

              // ── Campo 2: Prioridad (Grid de 4 botones) ──
              _buildFieldLabel('PRIORIDAD', textSecondary),
              const SizedBox(height: 6),
              _buildGridPrioridad(isDark: isDark, borderColor: borderColor, textSecondary: textSecondary),
              const SizedBox(height: 20),

              // ── Campo 3: Asunto ──
              _buildFieldLabel('ASUNTO DEL REPORTE (MÁX 150 CARACTERES)', textSecondary),
              const SizedBox(height: 6),
              TextFormField(
                controller: _asuntoCtrl,
                maxLength: 150,
                style: AppTypography.body.copyWith(
                  color: textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                decoration: _inputDecoration(
                  hintText: 'Ej: Error al conectar con lector POS en cobro...',
                  isDark: isDark,
                  borderColor: borderColor,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'El asunto no puede estar vacío';
                  }
                  if (val.trim().length < 5) {
                    return 'El asunto debe tener al menos 5 caracteres';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ── Campo 4: Descripción Detallada ──
              _buildFieldLabel('DESCRIPCIÓN DETALLADA (MÁX 1000 CARACTERES)', textSecondary),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descCtrl,
                maxLength: 1000,
                maxLines: 4,
                style: AppTypography.body.copyWith(
                  color: textPrimary,
                  fontSize: 14,
                ),
                decoration: _inputDecoration(
                  hintText:
                      'Describa con precisión lo ocurrido, número de orden involucrada o comportamiento inesperado...',
                  isDark: isDark,
                  borderColor: borderColor,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'La descripción no puede estar vacía';
                  }
                  if (val.trim().length < 10) {
                    return 'La descripción debe tener al menos 10 caracteres';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // ── Botón de Envío Principal ──
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _handleEnviarTicket,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.primary,
                    foregroundColor: Colors.white,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    _isSubmitting ? 'ENVIANDO TICKET...' : 'ENVIAR TICKET DE SOPORTE',
                    style: AppTypography.button.copyWith(
                      color: Colors.white,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800,
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

  Widget _buildFieldLabel(String label, [Color? textColor]) {
    return Text(
      label,
      style: AppTypography.small.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: textColor ?? AppPalette.textSecondaryLight,
      ),
    );
  }

  InputDecoration _inputDecoration({String? hintText, bool isDark = false, Color? borderColor}) {
    final borderCol = borderColor ?? (isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight);
    final fillCol = isDark ? AppPalette.background : Colors.white;
    final hintCol = isDark
        ? AppPalette.textSecondary.withValues(alpha: 0.6)
        : AppPalette.textSecondaryLight.withValues(alpha: 0.6);

    return InputDecoration(
      hintText: hintText,
      hintStyle: AppTypography.body.copyWith(
        color: hintCol,
        fontSize: 13,
      ),
      filled: true,
      fillColor: fillCol,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderCol),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderCol),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppPalette.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppPalette.error),
      ),
    );
  }

  Widget _buildGridPrioridad({bool isDark = false, Color? borderColor, Color? textSecondary}) {
    final borderCol = borderColor ?? (isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight);
    final unselectedBg = isDark ? AppPalette.background : Colors.white;
    final unselectedText = textSecondary ?? (isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight);

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
              height: 46,
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.15) : unselectedBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? color : borderCol,
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
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                        color: isSelected ? color : unselectedText,
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

  // ── SUB-PESTAÑA 2: TABLA DE MIS TICKETS (Líneas 1106–1190) ───────────────────
  Widget _buildTablaMisTickets() {
    final tickets = _ticketsFiltrados;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppPalette.surface : AppPalette.surfaceLight;
    final borderColor = isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight;
    final headerBg = isDark ? AppPalette.background : const Color(0xFFF8FAFC);
    final textSecondary = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;
    final dividerColor = isDark ? AppPalette.neutral.withValues(alpha: 0.15) : const Color(0xFFF1F5F9);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Filtros Rápidos de Estado ──
        Row(
          children: [
            _buildFiltroPill('TODOS', 'Todos', isDark),
            const SizedBox(width: 8),
            _buildFiltroPill('Abierto', 'Abiertos', isDark),
            const SizedBox(width: 8),
            _buildFiltroPill('En Proceso', 'En Proceso', isDark),
            const SizedBox(width: 8),
            _buildFiltroPill('Resuelto', 'Resueltos', isDark),
          ],
        ),
        const SizedBox(height: 16),

        // ── Tabla de Tickets ──
        Container(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              // Encabezado de la Tabla
              Container(
                color: headerBg,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    _th('FOLIO / FECHA', flex: 2, textColor: textSecondary),
                    _th('TIPO', flex: 2, textColor: textSecondary),
                    _th('ASUNTO', flex: 4, textColor: textSecondary),
                    _th('PRIORIDAD', flex: 2, textColor: textSecondary),
                    _th('ESTADO', flex: 2, textColor: textSecondary),
                    _th('ACCIÓN', flex: 2, alignment: TextAlign.center, textColor: textSecondary),
                  ],
                ),
              ),
              Divider(color: borderColor, height: 1),

              // Cuerpo de la Tabla / Shimmer / Empty State
              if (_isLoadingTickets)
                _buildShimmerTable(isDark: isDark)
              else if (_errorTickets != null)
                _buildErrorState()
              else if (tickets.isEmpty)
                _buildEmptyState(textSecondary: textSecondary)
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: tickets.length,
                  separatorBuilder: (context, index) =>
                      Divider(color: dividerColor, height: 1),
                  itemBuilder: (context, index) {
                    final t = tickets[index];
                    return _TicketTableRow(
                      ticket: t,
                      formatFecha: _formatFecha,
                      colorForPrioridad: _colorForPrioridad,
                      badgeEstado: (estado) => _buildBadgeEstado(estado, isDark, borderColor, textSecondary),
                      onTap: () => TicketDetailDialog.mostrar(context, t),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFiltroPill(String valor, String label, bool isDark) {
    return _FiltroPillButton(
      label: label,
      isSelected: _filtroEstado == valor,
      isDark: isDark,
      onTap: () => setState(() => _filtroEstado = valor),
    );
  }

  Widget _th(String label, {required int flex, TextAlign alignment = TextAlign.left, Color? textColor}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: alignment,
        style: AppTypography.small.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: textColor ?? AppPalette.textSecondaryLight,
        ),
      ),
    );
  }

  Widget _buildBadgeEstado(String estado, [bool isDark = false, Color? fallbackBorder, Color? fallbackText]) {
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
        border = fallbackBorder ?? (isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight);
        text = fallbackText ?? (isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight);
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
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: text,
        ),
      ),
    );
  }
  Widget _buildEmptyState({Color? textSecondary}) {
    final col = textSecondary ?? AppPalette.textSecondaryLight;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(
            Icons.inbox_rounded,
            size: 40,
            color: col,
          ),
          const SizedBox(height: 8),
          Text(
            'No hay tickets en este estado',
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: col,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded, size: 36, color: AppPalette.error),
          const SizedBox(height: 8),
          Text(
            'Error al cargar el historial de tickets',
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.bold,
              color: AppPalette.error,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _cargarTickets,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerTable({bool isDark = false}) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: List.generate(
          3,
          (index) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(flex: 2, child: _shimmerBox(height: 16, isDark: isDark)),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _shimmerBox(height: 16, isDark: isDark)),
                const SizedBox(width: 12),
                Expanded(flex: 4, child: _shimmerBox(height: 16, isDark: isDark)),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _shimmerBox(height: 16, isDark: isDark)),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _shimmerBox(height: 16, isDark: isDark)),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _shimmerBox(height: 24, radius: 8, isDark: isDark)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _shimmerBox({required double height, double radius = 4, bool isDark = false}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark ? AppPalette.neutral.withValues(alpha: 0.15) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTÓN DE FILTRO CON HOVER CELESTE CRESAL (AppPalette.primary)
// ─────────────────────────────────────────────────────────────────────────────
class _FiltroPillButton extends StatefulWidget {
  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _FiltroPillButton({
    required this.label,
    required this.isSelected,
    this.isDark = false,
    required this.onTap,
  });

  @override
  State<_FiltroPillButton> createState() => _FiltroPillButtonState();
}

class _FiltroPillButtonState extends State<_FiltroPillButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final isDark = widget.isDark;

    Color bg;
    Color border;
    Color text;

    if (isSelected) {
      bg = AppPalette.primary;
      border = AppPalette.primary;
      text = Colors.white;
    } else if (_isHovered) {
      bg = AppPalette.primary.withValues(alpha: 0.08);
      border = AppPalette.primary.withValues(alpha: 0.45);
      text = AppPalette.primary;
    } else {
      bg = isDark ? AppPalette.surface : Colors.white;
      border = isDark ? AppPalette.neutral.withValues(alpha: 0.25) : AppPalette.borderLight;
      text = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: isSelected ? 1.5 : 1),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppPalette.primary.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : _isHovered
                    ? [
                        BoxShadow(
                          color: AppPalette.primary.withValues(alpha: 0.12),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
          ),
          child: Text(
            widget.label,
            style: AppTypography.small.copyWith(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: text,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FILA DE TICKET INTERACTIVA CON HOVER CELESTE CRESAL (AppPalette.primary)
// ─────────────────────────────────────────────────────────────────────────────
class _TicketTableRow extends StatefulWidget {
  final TicketModel ticket;
  final String Function(String?) formatFecha;
  final Color Function(String) colorForPrioridad;
  final Widget Function(String) badgeEstado;
  final VoidCallback onTap;

  const _TicketTableRow({
    required this.ticket,
    required this.formatFecha,
    required this.colorForPrioridad,
    required this.badgeEstado,
    required this.onTap,
  });

  @override
  State<_TicketTableRow> createState() => _TicketTableRowState();
}

class _TicketTableRowState extends State<_TicketTableRow> {
  bool _isRowHovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final prioridadColor = widget.colorForPrioridad(t.prioridad);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppPalette.textPrimary : AppPalette.textPrimaryLight;
    final textSecondary = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;
    final tagBg = isDark ? AppPalette.background : const Color(0xFFF1F5F9);

    return MouseRegion(
      onEnter: (_) => setState(() => _isRowHovered = true),
      onExit: (_) => setState(() => _isRowHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          color: _isRowHovered
              ? AppPalette.primary.withValues(alpha: 0.06) // Tinte celeste Cresal suave
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              // 1. Folio / Fecha
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.folioVisual,
                      style: AppTypography.small.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppPalette.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.formatFecha(t.fechaCreacion),
                      style: AppTypography.small.copyWith(
                        fontSize: 11,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Tipo
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: tagBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      t.tipoTicket,
                      style: AppTypography.small.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Asunto
              Expanded(
                flex: 4,
                child: Text(
                  t.asunto,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.small.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: textPrimary,
                  ),
                ),
              ),

              // 4. Prioridad
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: prioridadColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: prioridadColor.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      t.prioridad,
                      style: AppTypography.small.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: prioridadColor,
                      ),
                    ),
                  ),
                ),
              ),

              // 5. Estado
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: widget.badgeEstado(t.estadoTicket),
                ),
              ),

              // 6. Acción (Botón Ver Detalle interactivo)
              Expanded(
                flex: 2,
                child: Center(
                  child: _VerDetalleButton(onTap: widget.onTap),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTÓN 'VER DETALLE' CON HOVER CELESTE CRESAL (AppPalette.primary)
// ─────────────────────────────────────────────────────────────────────────────
class _VerDetalleButton extends StatefulWidget {
  final VoidCallback onTap;

  const _VerDetalleButton({required this.onTap});

  @override
  State<_VerDetalleButton> createState() => _VerDetalleButtonState();
}

class _VerDetalleButtonState extends State<_VerDetalleButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _isHovered
                ? AppPalette.primary // Celeste Cresal sólido al hover
                : AppPalette.primary.withValues(alpha: 0.10), // Tinte celeste suave en reposo
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovered
                  ? AppPalette.primary
                  : AppPalette.primary.withValues(alpha: 0.25),
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: AppPalette.primary.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            'Ver Detalle',
            style: AppTypography.button.copyWith(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.1,
              color: _isHovered ? Colors.white : AppPalette.primary,
            ),
          ),
        ),
      ),
    );
  }
}
