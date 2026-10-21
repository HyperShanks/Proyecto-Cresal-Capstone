import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../alertas/services/bodega_service.dart';

/// Pantalla PDA de Bodega para Logística Inversa y Tareas de Reingreso (SPEC-HU-TAREA-4)
class ReingresoTareasScreen extends StatefulWidget {
  const ReingresoTareasScreen({super.key});

  @override
  State<ReingresoTareasScreen> createState() => _ReingresoTareasScreenState();
}

class _ReingresoTareasScreenState extends State<ReingresoTareasScreen> {
  late Future<List<TareaReingresoModel>> _futureTareas;
  final TextEditingController _searchController = TextEditingController();
  String _filtroTexto = '';

  @override
  void initState() {
    super.initState();
    _cargarTareas();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _cargarTareas() {
    setState(() {
      _futureTareas = BodegaService.obtenerReingresosPendientes();
    });
  }

  Future<void> _abrirDialogoConfirmarReingreso(TareaReingresoModel tarea) async {
    final galponController = TextEditingController(text: tarea.ubicacionGalpon ?? '');
    final pasilloController = TextEditingController(text: tarea.ubicacionPasillo ?? '');
    final palletController = TextEditingController(text: tarea.ubicacionPallet ?? '');
    final skuController = TextEditingController(text: tarea.skuQrFisico);

    bool isSubmitting = false;
    String? modalError;

    final bool? confirmado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: AppPalette.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
                side: const BorderSide(color: Colors.white12),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppPalette.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.qr_code_scanner_rounded, color: AppPalette.primary, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Confirmar Reingreso', style: AppTypography.title.copyWith(fontSize: 17)),
                        Text('SKU: ${tarea.skuQrFisico}', style: AppTypography.small.copyWith(color: AppPalette.secondary, fontWeight: FontWeight.bold)),
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppPalette.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tarea.descripcionPieza, style: AppTypography.body.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Orden Origen: ${tarea.folioOrden ?? tarea.idOrden.substring(0, 8).toUpperCase()}', style: AppTypography.small.copyWith(color: AppPalette.textSecondary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Escaneo de QR Físico (Validación):', style: AppTypography.small.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: skuController,
                      enabled: !isSubmitting,
                      style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'Escanee o digite el SKU del repuesto',
                        filled: true,
                        fillColor: AppPalette.background,
                        prefixIcon: const Icon(Icons.qr_code, color: AppPalette.primary, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppPalette.primary, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Galpón:', style: AppTypography.small.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              TextField(
                                controller: galponController,
                                enabled: !isSubmitting,
                                textCapitalization: TextCapitalization.characters,
                                style: AppTypography.body,
                                decoration: InputDecoration(
                                  hintText: 'Ej: 1',
                                  filled: true,
                                  fillColor: AppPalette.background,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white24)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Pasillo / Rack:', style: AppTypography.small.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              TextField(
                                controller: pasilloController,
                                enabled: !isSubmitting,
                                textCapitalization: TextCapitalization.characters,
                                style: AppTypography.body,
                                decoration: InputDecoration(
                                  hintText: 'Ej: P-02',
                                  filled: true,
                                  fillColor: AppPalette.background,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white24)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Pallet:', style: AppTypography.small.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              TextField(
                                controller: palletController,
                                enabled: !isSubmitting,
                                textCapitalization: TextCapitalization.characters,
                                style: AppTypography.body,
                                decoration: InputDecoration(
                                  hintText: 'Ej: PAL-05',
                                  filled: true,
                                  fillColor: AppPalette.background,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white24)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (modalError != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: AppPalette.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: AppPalette.error, size: 16),
                            const SizedBox(width: 6),
                            Expanded(child: Text(modalError!, style: const TextStyle(color: AppPalette.error, fontSize: 12))),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.of(ctx).pop(false),
                  child: Text('Cancelar', style: AppTypography.button.copyWith(color: AppPalette.textSecondary)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppPalette.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, size: 18),
                  label: Text(isSubmitting ? 'Guardando...' : 'CONFIRMAR REINGRESO'),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final skuEscaneado = skuController.text.trim();
                          if (skuEscaneado.isEmpty) {
                            setModalState(() => modalError = 'Debe ingresar o escanear el SKU físico.');
                            return;
                          }

                          setModalState(() {
                            isSubmitting = true;
                            modalError = null;
                          });

                          try {
                            await BodegaService.confirmarReingreso(
                              skuQrFisico: skuEscaneado,
                              idOrdenAnulada: tarea.idOrden,
                              ubicacionGalpon: galponController.text.trim(),
                              ubicacionPasillo: pasilloController.text.trim(),
                              ubicacionPallet: palletController.text.trim(),
                            );

                            if (!ctx.mounted) return;
                            Navigator.of(ctx).pop(true);
                          } catch (e) {
                            setModalState(() {
                              isSubmitting = false;
                              modalError = e.toString().replaceAll('Exception:', '').trim();
                            });
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );

    galponController.dispose();
    pasilloController.dispose();
    palletController.dispose();
    skuController.dispose();

    if (!mounted) return;
    if (confirmado == true) {
      _cargarTareas();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        foregroundColor: AppPalette.textPrimary,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Logística Inversa', style: AppTypography.title.copyWith(fontSize: 18)),
            Text('Reingresos y Paletizado PDA', style: AppTypography.small.copyWith(fontSize: 12, color: AppPalette.secondary)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppPalette.primary),
            onPressed: _cargarTareas,
            tooltip: 'Actualizar lista',
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de búsqueda rápida
          Container(
            color: AppPalette.surface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _filtroTexto = val.trim().toLowerCase()),
              style: AppTypography.body,
              decoration: InputDecoration(
                hintText: 'Buscar por SKU, Folio o Pieza...',
                hintStyle: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                prefixIcon: const Icon(Icons.search, color: AppPalette.primary, size: 20),
                suffixIcon: _filtroTexto.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _filtroTexto = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppPalette.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),

          // Listado reactivo de tareas
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _cargarTareas(),
              color: AppPalette.primary,
              backgroundColor: AppPalette.surface,
              child: FutureBuilder<List<TareaReingresoModel>>(
                future: _futureTareas,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppPalette.primary));
                  } else if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, color: AppPalette.error, size: 48),
                            const SizedBox(height: 12),
                            Text('Error al cargar reingresos: ${snapshot.error}', style: const TextStyle(color: AppPalette.error), textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _cargarTareas,
                              style: ElevatedButton.styleFrom(backgroundColor: AppPalette.primary),
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final todasTareas = snapshot.data ?? [];
                  final tareasFiltradas = todasTareas.where((t) {
                    if (_filtroTexto.isEmpty) return true;
                    final matchSku = t.skuQrFisico.toLowerCase().contains(_filtroTexto);
                    final matchFolio = (t.folioOrden ?? '').toLowerCase().contains(_filtroTexto);
                    final matchDesc = t.descripcionPieza.toLowerCase().contains(_filtroTexto);
                    return matchSku || matchFolio || matchDesc;
                  }).toList();

                  if (tareasFiltradas.isEmpty) {
                    return Center(
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.task_alt_rounded, color: AppPalette.success, size: 64),
                              const SizedBox(height: 16),
                              Text('¡Sin reingresos pendientes!', style: AppTypography.title.copyWith(fontSize: 18)),
                              const SizedBox(height: 6),
                              Text('Todas las órdenes anuladas han sido reubicadas en rack.', style: AppTypography.small.copyWith(color: AppPalette.textSecondary), textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: tareasFiltradas.length,
                    itemBuilder: (context, index) {
                      final tarea = tareasFiltradas[index];
                      return Card(
                        color: AppPalette.surface,
                        margin: const EdgeInsets.only(bottom: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: AppPalette.secondary.withValues(alpha: 0.3), width: 1.2),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Cabecera de la tarjeta: Folio y badge
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppPalette.secondary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      tarea.folioOrden ?? 'ORD-${tarea.idOrden.substring(0, 8).toUpperCase()}',
                                      style: AppTypography.small.copyWith(color: AppPalette.secondary, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppPalette.error.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'ORDEN ANULADA',
                                      style: TextStyle(color: AppPalette.error, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Descripción de la pieza
                              Text(
                                tarea.descripcionPieza,
                                style: AppTypography.cardTitle.copyWith(fontSize: 16),
                              ),
                              const SizedBox(height: 8),

                              // SKU QR Físico
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppPalette.background,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.white10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.qr_code, color: AppPalette.primary, size: 18),
                                    const SizedBox(width: 6),
                                    Text(
                                      tarea.skuQrFisico,
                                      style: const TextStyle(
                                        color: AppPalette.primary,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Ubicación previa / sugerida
                              Row(
                                children: [
                                  const Icon(Icons.location_on_outlined, color: AppPalette.textSecondary, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Ubicación: Pasillo ${tarea.ubicacionPasillo ?? 'S/P'} • Pallet ${tarea.ubicacionPallet ?? 'S/P'}',
                                    style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // Botón de acción táctil >= 48px
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppPalette.primary,
                                    foregroundColor: AppPalette.textPrimary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(Icons.qr_code_scanner, size: 20),
                                  label: const Text('REINGRESAR / PALETIZAR', style: TextStyle(fontWeight: FontWeight.bold)),
                                  onPressed: () => _abrirDialogoConfirmarReingreso(tarea),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
