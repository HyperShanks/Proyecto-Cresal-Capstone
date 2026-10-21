import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../auth/services/auth_service.dart';
import '../widgets/qr_ticket_dialog.dart';
import '../../services/ordenes_service.dart';
import '../../services/ordenes_sync_notifier.dart';
import '../../services/entregas_envios_storage_service.dart';
import '../../services/entregas_envios_sync_service.dart';
import '../../../../core/services/silent_polling_manager.dart';

/// Pantalla colaborativa para el Módulo 'Entregas y Envíos'
/// Permite gestionar retiros en sucursal y despachos externos con filtros avanzados,
/// trazabilidad de vendedores, tarjetas limpias y modal de detalle exhaustivo.
class EntregasEnviosScreen extends StatefulWidget {
  final List<EntregaEnvioModel>? initialEntregas;
  final EntregasEnviosSyncService? syncService;
  final http.Client? httpClient;

  const EntregasEnviosScreen({
    super.key,
    this.initialEntregas,
    this.syncService,
    this.httpClient,
  });

  @override
  State<EntregasEnviosScreen> createState() => _EntregasEnviosScreenState();
}

class _EntregasEnviosScreenState extends State<EntregasEnviosScreen> {
  // Controladores y Estados de Filtros
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _clienteFilterController = TextEditingController();
  final TextEditingController _vendedorFilterController = TextEditingController();
  String _searchQuery = '';
  bool _soloMisAsignadas = false;
  String? _currentUserId;
  String? _currentUserName;
  String _estadoPagoFilter = 'pagados'; // 'pagados' (predeterminado / listas para entrega), 'pendientes', 'todos'
  String _tipoEntregaFilter = 'todos'; // 'todos', 'retiro', 'despacho', 'traslado'

  List<EntregaEnvioModel> _todasEntregas = [];
  bool _isLoading = true;
  String? _errorMessage;
  SilentPollingManager? _pollingManager;
  late EntregasEnviosSyncService _syncService;

  @override
  void initState() {
    super.initState();
    _syncService = widget.syncService ??
        EntregasEnviosSyncService(client: widget.httpClient);
    OrdenesSyncNotifier.instance.addListener(_onSyncNotification);
    _iniciarAutoRefresh();
    _despliegueInmediatoYCarga();
  }

  void _iniciarAutoRefresh() {
    _pollingManager?.dispose();
    _pollingManager = SilentPollingManager(
      interval: const Duration(seconds: 15),
      debugLabel: 'EntregasEnviosPolling',
      shouldPause: () => _isLoading,
      onPoll: () async {
        if (mounted) {
          await _cargarDatosSilencioso();
        }
      },
    )..start();
  }

  void _onSyncNotification() {
    if (mounted) {
      if (_todasEntregas.isNotEmpty) {
        _cargarDatosSilencioso();
      } else {
        _cargarDatos();
      }
    }
  }

  Future<void> _despliegueInmediatoYCarga() async {
    // 1. Apertura Inmediata (< 50ms) usando datos en memoria/caché local
    if (widget.initialEntregas != null) {
      setState(() {
        _todasEntregas = List.from(widget.initialEntregas!);
        _isLoading = false;
      });
    } else {
      final cache = await _syncService.storage.cargarCache();
      if (mounted && cache.isNotEmpty) {
        setState(() {
          _todasEntregas = cache;
          _isLoading = false;
        });
      }
    }

    // 2. Comprobar permisos del usuario
    await _verificarPermisos();

    // 3. Sincronización en segundo plano (Stale-While-Revalidate) y procesamiento de cola outbox
    if (mounted && widget.initialEntregas == null) {
      await _sincronizarConBackend(mostrarLoader: _todasEntregas.isEmpty);
      // Despachar acciones pendientes que hayan quedado por desconexiones previas
      _syncService.procesarCola();
    }
  }

  Future<void> _verificarPermisos() async {
    final idRol = await AuthService.getIdRol();
    final rol = await AuthService.getRol();
    final esVendedorOnline = idRol == 7 ||
        rol?.toLowerCase() == 'vendedoronline' ||
        rol?.toLowerCase() == 'vendedor online';

    if (esVendedorOnline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppPalette.surface,
          content: Text(
            'Acceso restringido: Las entregas presenciales son gestionadas por el equipo de sucursal.',
            style: TextStyle(color: AppPalette.error),
          ),
        ),
      );
      Navigator.of(context).pop();
      return;
    }

    final authUser = await AuthService.getAuthUser();
    final nombre = await AuthService.getNombreUsuario();
    if (mounted) {
      setState(() {
        _currentUserId = authUser?.idUsuario;
        _currentUserName = nombre ?? authUser?.nombreCompleto;
      });
    }
  }

  Future<void> _sincronizarConBackend({bool mostrarLoader = false}) async {
    if (mostrarLoader) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final data = await _syncService.sincronizarEntregas(
        busquedaCliente: _clienteFilterController.text.trim().isNotEmpty
            ? _clienteFilterController.text.trim()
            : null,
        busquedaVendedor: _vendedorFilterController.text.trim().isNotEmpty
            ? _vendedorFilterController.text.trim()
            : null,
        soloActivas: true,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _todasEntregas = data;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Solo mostrar error si no teníamos absolutamente nada en caché
        if (_todasEntregas.isEmpty) {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _cargarDatosSilencioso() async {
    await _sincronizarConBackend(mostrarLoader: false);
  }

  @override
  void dispose() {
    _pollingManager?.dispose();
    OrdenesSyncNotifier.instance.removeListener(_onSyncNotification);
    if (widget.syncService == null) {
      _syncService.dispose();
    }
    _searchController.dispose();
    _clienteFilterController.dispose();
    _vendedorFilterController.dispose();
    super.dispose();
  }

  bool get _tieneFiltrosActivos =>
      _searchQuery.isNotEmpty ||
      _soloMisAsignadas ||
      _clienteFilterController.text.trim().isNotEmpty ||
      _vendedorFilterController.text.trim().isNotEmpty ||
      _estadoPagoFilter != 'pagados' ||
      _tipoEntregaFilter != 'todos';

  Future<void> _cargarDatos() async {
    await _sincronizarConBackend(mostrarLoader: _todasEntregas.isEmpty);
  }

  bool _isAsignadaAMi(EntregaEnvioModel e) {
    if (_currentUserId != null &&
        e.idVendedorAsignado != null &&
        e.idVendedorAsignado!.trim().isNotEmpty &&
        e.idVendedorAsignado == _currentUserId) {
      return true;
    }
    if (_currentUserName != null &&
        _currentUserName!.trim().isNotEmpty &&
        e.vendedorAsignadoNombre != null &&
        e.vendedorAsignadoNombre!.trim().isNotEmpty) {
      final userTokens = _currentUserName!
          .toLowerCase()
          .split(' ')
          .where((t) => t.length > 2);
      final asignadoLower = e.vendedorAsignadoNombre!.toLowerCase();
      for (final token in userTokens) {
        if (asignadoLower.contains(token)) return true;
      }
    }
    return false;
  }

  List<EntregaEnvioModel> get _ordenesFiltradas {
    var lista = _todasEntregas.where((e) {
      if (e.esVentaEnVerde && (!e.estaPagada || !e.tieneQrDisponible)) {
        return false;
      }
      return true;
    }).toList();

    // 1. Filtro rápido de "Mis Asignadas" (Responsabilidad de entrega física)
    if (_soloMisAsignadas) {
      lista = lista.where(_isAsignadaAMi).toList();
    }

    // 2. Filtro por Modalidad de Entrega
    if (_tipoEntregaFilter != 'todos') {
      if (_tipoEntregaFilter == 'despacho') {
        lista = lista
            .where((e) =>
                e.tipoEntrega.toLowerCase() == 'despacho' ||
                e.tipoEntrega.toLowerCase() == 'despacho domicilio')
            .toList();
      } else if (_tipoEntregaFilter == 'traslado') {
        lista = lista
            .where((e) => e.tipoEntrega.toLowerCase() == 'traslado')
            .toList();
      } else {
        lista = lista
            .where((e) => e.tipoEntrega.toLowerCase() == _tipoEntregaFilter)
            .toList();
      }
    }

    // 3. Filtro por Estado de Pago
    if (_estadoPagoFilter != 'todos') {
      if (_estadoPagoFilter == 'pagados') {
        lista = lista.where((e) => e.estaPagada).toList();
      } else if (_estadoPagoFilter == 'pendientes') {
        lista = lista.where((e) => e.tieneSaldoPendiente).toList();
      }
    }

    // 4. Buscador Reactivo Unificado (Folio, Cliente, RUT, Teléfono, Vendedor Online, Vendedor Responsable, Repuesto)
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      final qSinPuntos = q.replaceAll('.', '').replaceAll('-', '');
      lista = lista.where((e) {
        // Coincidencia por Folio
        if (e.folioDisplay.toLowerCase().contains(q) ||
            e.folio.toLowerCase().contains(q)) {
          return true;
        }
        // Coincidencia por Cliente (Nombre completo o display)
        if (e.cliente != null &&
            e.cliente!.nombreCompleto.toLowerCase().contains(q)) {
          return true;
        }
        if (e.clienteDisplay.toLowerCase().contains(q)) {
          return true;
        }
        // Coincidencia por RUT de Cliente (tolerante a puntos y guión)
        if (e.cliente != null && e.cliente!.rutCliente.isNotEmpty) {
          final rutLimpio = e.cliente!.rutCliente
              .replaceAll('.', '')
              .replaceAll('-', '')
              .toLowerCase();
          if (rutLimpio.contains(qSinPuntos)) return true;
        }
        // Coincidencia por Teléfono de Contacto
        if (e.cliente?.telefono != null && e.cliente!.telefono!.contains(q)) {
          return true;
        }
        if (e.despacho?.receptorTelefono != null &&
            e.despacho!.receptorTelefono.contains(q)) {
          return true;
        }
        // Coincidencia por Receptor y Comuna de Despacho
        if (e.despacho != null &&
            e.despacho!.receptorNombres.toLowerCase().contains(q)) {
          return true;
        }
        if (e.despacho?.comunaDestino != null &&
            e.despacho!.comunaDestino!.toLowerCase().contains(q)) {
          return true;
        }
        // Coincidencia por Vendedor Creador (Online / Central)
        if (e.vendedorNombre != null &&
            e.vendedorNombre!.toLowerCase().contains(q)) {
          return true;
        }
        // Coincidencia por Vendedor Asignado (Responsable en tienda de la entrega)
        if (e.vendedorAsignadoNombre != null &&
            e.vendedorAsignadoNombre!.toLowerCase().contains(q)) {
          return true;
        }
        // Coincidencia por Título o SKU del Repuesto
        if (e.detalles.any((d) =>
            d.tituloDisplay.toLowerCase().contains(q) ||
            (d.skuQrFisico != null &&
                d.skuQrFisico!.toLowerCase().contains(q)))) {
          return true;
        }

        return false;
      }).toList();
    }

    // 5. Filtro adicional por Cliente desde Modal
    if (_clienteFilterController.text.trim().isNotEmpty) {
      final cq = _clienteFilterController.text.trim().toLowerCase();
      final cleanCq = cq.replaceAll('.', '').replaceAll('-', '');
      lista = lista.where((e) {
        final nom = e.cliente?.nombreCompleto.toLowerCase() ?? '';
        final disp = e.clienteDisplay.toLowerCase();
        final rut = e.cliente?.rutCliente.toLowerCase().replaceAll('.', '').replaceAll('-', '') ?? '';
        final tel = e.cliente?.telefono?.toLowerCase() ?? '';
        final recNom = e.despacho?.receptorNombres.toLowerCase() ?? '';
        final recRut = e.despacho?.receptorRut.toLowerCase().replaceAll('.', '').replaceAll('-', '') ?? '';
        final recTel = e.despacho?.receptorTelefono.toLowerCase() ?? '';
        return nom.contains(cq) ||
            disp.contains(cq) ||
            rut.contains(cleanCq) ||
            tel.contains(cq) ||
            recNom.contains(cq) ||
            recRut.contains(cleanCq) ||
            recTel.contains(cq);
      }).toList();
    }

    // 6. Filtro adicional por Vendedor desde Modal
    if (_vendedorFilterController.text.trim().isNotEmpty) {
      final vq = _vendedorFilterController.text.trim().toLowerCase();
      lista = lista.where((e) {
        final vend = e.vendedorNombre?.toLowerCase() ?? '';
        final asig = e.vendedorAsignadoNombre?.toLowerCase() ?? '';
        return vend.contains(vq) || asig.contains(vq);
      }).toList();
    }

    return lista;
  }

  void _abrirModalFiltros() {
    String draftEstadoPago = _estadoPagoFilter;
    String draftTipoEntrega = _tipoEntregaFilter;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.88,
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 14,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Handle bar centrado
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),

                        // Cabecera del Modal de Filtros
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.tune_rounded, color: AppPalette.primary, size: 22),
                                const SizedBox(width: 8),
                                Text(
                                  'Filtros de Búsqueda',
                                  style: AppTypography.title.copyWith(color: AppPalette.textPrimary),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: AppPalette.textSecondary),
                              onPressed: () => Navigator.of(ctx).pop(),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white10, height: 20),

                        // Buscador 1: Cliente (Nombre, RUT, Teléfono)
                        Text(
                          'Búsqueda por Cliente',
                          style: AppTypography.small.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFCBD5E1),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _clienteFilterController,
                          onChanged: (_) => setModalState(() {}),
                          style: AppTypography.body.copyWith(fontSize: 14, color: AppPalette.textPrimary),
                          cursorColor: AppPalette.primary,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Nombre, RUT o Teléfono del cliente / receptor...',
                            hintStyle: AppTypography.small.copyWith(
                              color: AppPalette.textSecondary.withValues(alpha: 0.65),
                              fontSize: 13,
                            ),
                            prefixIcon: const Icon(
                              Icons.person_search_outlined,
                              size: 20,
                              color: AppPalette.textSecondary,
                            ),
                            suffixIcon: _clienteFilterController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 18, color: AppPalette.textSecondary),
                                    onPressed: () {
                                      _clienteFilterController.clear();
                                      setModalState(() {});
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: AppPalette.surface,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFF334155)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFF334155)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Buscador 2: Vendedor (Creador o Asignado)
                        Text(
                          'Búsqueda por Vendedor',
                          style: AppTypography.small.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFCBD5E1),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _vendedorFilterController,
                          onChanged: (_) => setModalState(() {}),
                          style: AppTypography.body.copyWith(fontSize: 14, color: AppPalette.textPrimary),
                          cursorColor: AppPalette.primary,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Nombre del vendedor creador o asignado...',
                            hintStyle: AppTypography.small.copyWith(
                              color: AppPalette.textSecondary.withValues(alpha: 0.65),
                              fontSize: 13,
                            ),
                            prefixIcon: const Icon(
                              Icons.badge_outlined,
                              size: 20,
                              color: AppPalette.textSecondary,
                            ),
                            suffixIcon: _vendedorFilterController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 18, color: AppPalette.textSecondary),
                                    onPressed: () {
                                      _vendedorFilterController.clear();
                                      setModalState(() {});
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: AppPalette.surface,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFF334155)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFF334155)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Filtro 3: Estado de Pago
                        Text(
                          'Estado de Pago / Liquidación',
                          style: AppTypography.small.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFCBD5E1),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildModalFilterPill(
                              label: 'Todos',
                              isSelected: draftEstadoPago == 'todos',
                              onTap: () => setModalState(() => draftEstadoPago = 'todos'),
                            ),
                            _buildModalFilterPill(
                              label: 'Pagados',
                              isSelected: draftEstadoPago == 'pagados',
                              activeColor: AppPalette.success,
                              onTap: () => setModalState(() => draftEstadoPago = 'pagados'),
                            ),
                            _buildModalFilterPill(
                              label: 'Con Saldo Pendiente',
                              isSelected: draftEstadoPago == 'pendientes',
                              activeColor: AppPalette.warning,
                              onTap: () => setModalState(() => draftEstadoPago = 'pendientes'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Filtro 4: Tipo de Pedido / Modalidad
                        Text(
                          'Tipo de Pedido / Modalidad',
                          style: AppTypography.small.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFCBD5E1),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildModalFilterPill(
                              label: 'Todos',
                              isSelected: draftTipoEntrega == 'todos',
                              onTap: () => setModalState(() => draftTipoEntrega = 'todos'),
                            ),
                            _buildModalFilterPill(
                              label: 'Solo Retiros',
                              isSelected: draftTipoEntrega == 'retiro',
                              onTap: () => setModalState(() => draftTipoEntrega = 'retiro'),
                            ),
                            _buildModalFilterPill(
                              label: 'Solo Despachos',
                              isSelected: draftTipoEntrega == 'despacho',
                              activeColor: AppPalette.secondary,
                              onTap: () => setModalState(() => draftTipoEntrega = 'despacho'),
                            ),
                            _buildModalFilterPill(
                              label: 'Solo Traslados',
                              isSelected: draftTipoEntrega == 'traslado',
                              activeColor: const Color(0xFFAB47BC),
                              onTap: () => setModalState(() => draftTipoEntrega = 'traslado'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Botonera de Acción del Modal
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppPalette.textSecondary,
                                  side: const BorderSide(color: Colors.white24),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () {
                                  _clienteFilterController.clear();
                                  _vendedorFilterController.clear();
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _soloMisAsignadas = false;
                                    _estadoPagoFilter = 'pagados';
                                    _tipoEntregaFilter = 'todos';
                                  });
                                  Navigator.of(ctx).pop();
                                  _cargarDatos();
                                },
                                child: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'LIMPIAR',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppPalette.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () {
                                  setState(() {
                                    _estadoPagoFilter = draftEstadoPago;
                                    _tipoEntregaFilter = draftTipoEntrega;
                                  });
                                  Navigator.of(ctx).pop();
                                  _cargarDatos();
                                },
                                child: const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'APLICAR FILTROS',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _abrirQrModal(EntregaEnvioModel orden) {
    QrTicketDialog.mostrar(context, orden.toHistorialModel());
  }

  Widget _buildModalFilterPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? activeColor,
  }) {
    final selectedColor = activeColor ?? AppPalette.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8.0),
        splashColor: selectedColor.withValues(alpha: 0.25),
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: isSelected ? selectedColor : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(
              color: isSelected ? selectedColor : const Color(0xFF334155),
              width: 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderFilterPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
    Color? activeColor,
    Key? key,
  }) {
    final color = activeColor ?? AppPalette.primary;
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 7.0),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.22)
                : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(
              color: isSelected ? color : const Color(0xFF334155),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: isSelected ? color : const Color(0xFFCBD5E1),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? color : const Color(0xFFCBD5E1),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDatoFila(IconData icon, String label, String valor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppPalette.textSecondary),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTypography.small.copyWith(
            color: AppPalette.textSecondary,
            fontWeight: FontWeight.w500,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            valor,
            style: AppTypography.small.copyWith(
              color: AppPalette.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );
  }

  /// Confirmar entrega en tienda física (mostrador) para órdenes sin motor ni caja
  Future<void> _confirmarEntregaTienda(EntregaEnvioModel orden) async {
    if (orden.tieneSaldoPendiente) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppPalette.surface,
          behavior: SnackBarBehavior.floating,
          content: Row(
            children: [
              const Icon(Icons.lock_clock_rounded, color: AppPalette.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No se puede entregar: Orden con saldo pendiente de ${orden.montoPendienteFormateado}. Requiere liquidación previa en Caja.',
                  style: const TextStyle(color: AppPalette.warning),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: AppPalette.success, size: 24),
            const SizedBox(width: 8),
            const Text('Confirmar Entrega', style: TextStyle(color: AppPalette.textPrimary)),
          ],
        ),
        content: Text(
          '¿Confirmar la entrega del pedido #${orden.folioDisplay} al cliente?\n\nEsta acción marcará la orden como Completada.',
          style: const TextStyle(color: AppPalette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCELAR', style: TextStyle(color: AppPalette.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('CONFIRMAR ENTREGA', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      // 1. Cambio visual inmediato en la interfaz (optimista)
      setState(() {
        _todasEntregas.removeWhere((e) => e.idOrden == orden.idOrden);
      });

      // 2. Feedback discreto al operario
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppPalette.surface,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: AppPalette.success),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '¡Orden #${orden.folioDisplay} entregada! Procesando sincronización...',
                  style: const TextStyle(color: AppPalette.textPrimary),
                ),
              ),
            ],
          ),
        ),
      );

      // 3. Registro seguro con cola Outbox y reintento resiliente
      final accion = AccionEntregaEnvio(
        idAccion: DateTime.now().millisecondsSinceEpoch.toString(),
        tipo: 'confirmar_entrega',
        idOrden: orden.idOrden,
        fecha: DateTime.now().toIso8601String(),
      );
      _syncService.ejecutarAccionConCola(accion);
      OrdenesSyncNotifier.instance.notificarCambio();
    }
  }

  /// Registrar despacho externo a transportista (Starken, Chilexpress, etc.) con OT opcional
  Future<void> _marcarDespachoEnviadoModal(EntregaEnvioModel orden) async {
    final otCtrl = TextEditingController(text: orden.despacho?.numeroSeguimiento ?? '');
    final transpCtrl = TextEditingController(
      text: (orden.despacho?.empresaTransporte != null && orden.despacho!.empresaTransporte!.trim().isNotEmpty)
          ? orden.despacho!.empresaTransporte!
          : 'Chilexpress',
    );

    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.local_shipping_outlined, color: AppPalette.secondary, size: 24),
            const SizedBox(width: 8),
            const Text('Despachar Mercadería', style: TextStyle(color: AppPalette.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Registra la entrega del bulto al transportista para la orden #${orden.folioDisplay}.',
              style: const TextStyle(color: AppPalette.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: transpCtrl,
              style: const TextStyle(color: AppPalette.textPrimary),
              decoration: InputDecoration(
                labelText: 'Empresa / Transportista',
                labelStyle: const TextStyle(color: AppPalette.textSecondary),
                hintText: 'Starken, Chilexpress, Transportes Norte...',
                hintStyle: TextStyle(color: AppPalette.textSecondary.withValues(alpha: 0.5)),
                filled: true,
                fillColor: AppPalette.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: otCtrl,
              style: const TextStyle(color: AppPalette.textPrimary),
              decoration: InputDecoration(
                labelText: 'Nº Orden de Transporte (OT) / Seguimiento',
                labelStyle: const TextStyle(color: AppPalette.textSecondary),
                hintText: 'Ej: 994821038 (opcional)',
                hintStyle: TextStyle(color: AppPalette.textSecondary.withValues(alpha: 0.5)),
                filled: true,
                fillColor: AppPalette.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCELAR', style: TextStyle(color: AppPalette.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.secondary,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('CONFIRMAR DESPACHO', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      // 1. Cambio visual inmediato optimista
      setState(() {
        _todasEntregas.removeWhere((e) => e.idOrden == orden.idOrden);
      });

      // 2. Feedback discreto
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppPalette.surface,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            content: Row(
              children: [
                const Icon(Icons.local_shipping, color: AppPalette.secondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '¡Despacho #${orden.folioDisplay} registrado! Sincronizando con backend...',
                    style: const TextStyle(color: AppPalette.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      // 3. Encolar con reintento resiliente
      final accion = AccionEntregaEnvio(
        idAccion: DateTime.now().millisecondsSinceEpoch.toString(),
        tipo: 'marcar_enviado',
        idDespacho: orden.despacho?.idDespacho,
        idOrden: orden.idOrden,
        numeroSeguimiento: otCtrl.text.trim().isNotEmpty ? otCtrl.text.trim() : null,
        empresaTransporte: transpCtrl.text.trim().isNotEmpty ? transpCtrl.text.trim() : null,
        fecha: DateTime.now().toIso8601String(),
      );
      _syncService.ejecutarAccionConCola(accion);
      OrdenesSyncNotifier.instance.notificarCambio();
    }
  }

  /// Modal de Detalle Completo de la Orden al tocar la tarjeta (onTap)
  void _abrirDetalleCompleto(EntregaEnvioModel orden) {
    final bool saldoPendiente = orden.tieneSaldoPendiente;
    final desp = orden.despacho;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: ListView(
                controller: scrollController,
                children: [
                  // Handle bar
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
                  const SizedBox(height: 16),

                  // Cabecera: Folio + Fecha + Estado
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(orden.folioDisplay, style: AppTypography.title.copyWith(fontSize: 20)),
                          Text(orden.fechaFormateada, style: AppTypography.small.copyWith(color: AppPalette.textSecondary)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (orden.tipoEntrega.toLowerCase() == 'despacho'
                                  ? AppPalette.secondary
                                  : (orden.tipoEntrega.toLowerCase() == 'traslado'
                                      ? const Color(0xFFAB47BC)
                                      : AppPalette.primary))
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (orden.tipoEntrega.toLowerCase() == 'despacho'
                                    ? AppPalette.secondary
                                    : (orden.tipoEntrega.toLowerCase() == 'traslado'
                                        ? const Color(0xFFAB47BC)
                                        : AppPalette.primary))
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          orden.tipoEntrega.toUpperCase(),
                          style: TextStyle(
                            color: orden.tipoEntrega.toLowerCase() == 'despacho'
                                ? AppPalette.secondary
                                : (orden.tipoEntrega.toLowerCase() == 'traslado'
                                    ? const Color(0xFFAB47BC)
                                    : AppPalette.primary),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 24),

                  // Ficha de Cliente
                  Text('DATOS DEL CLIENTE', style: AppTypography.small.copyWith(fontWeight: FontWeight.bold, color: AppPalette.textSecondary)),
                  const SizedBox(height: 8),
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
                        Row(
                          children: [
                            Icon(
                              orden.esConsumidorFinal ? Icons.receipt_long_outlined : Icons.person,
                              size: 16,
                              color: AppPalette.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                orden.esConsumidorFinal
                                    ? 'Orden: #${orden.folioDisplay} (Consumidor Final)'
                                    : 'Cliente: ${orden.cliente?.nombres ?? ""} ${orden.cliente?.apellidos ?? ""}'.trim(),
                                style: AppTypography.body.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          orden.esConsumidorFinal
                              ? 'Venta mostrador sin RUT personal registrado'
                              : 'RUT: ${orden.cliente?.rutCliente ?? "S/R"}  •  Tel: ${orden.cliente?.telefono ?? "S/T"}',
                          style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                        ),
                        if (orden.cliente?.correo != null && orden.cliente!.correo!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('Correo: ${orden.cliente!.correo}', style: AppTypography.small.copyWith(color: AppPalette.textSecondary)),
                          ),
                      ],
                    ),
                  ),

                  // Ficha Completa de Despacho y Envío
                  if (desp != null) ...[
                    const SizedBox(height: 14),
                    Text('DATOS COMPLETOS DE DESPACHO Y ENVÍO', style: AppTypography.small.copyWith(fontWeight: FontWeight.bold, color: AppPalette.secondary)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppPalette.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppPalette.secondary.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.local_shipping, size: 18, color: AppPalette.secondary),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Despacho a Domicilio',
                                    style: AppTypography.body.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppPalette.secondary,
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppPalette.secondary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: AppPalette.secondary.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  desp.estadoDespacho,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppPalette.secondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white10, height: 16),
                          _buildDatoFila(
                            Icons.person_outline,
                            'Receptor:',
                            '${desp.receptorNombres} (${desp.receptorRut.isNotEmpty ? desp.receptorRut : "S/R"})',
                          ),
                          const SizedBox(height: 6),
                          _buildDatoFila(
                            Icons.phone_outlined,
                            'Teléfono:',
                            desp.receptorTelefono.isNotEmpty
                                ? desp.receptorTelefono
                                : (orden.cliente?.telefono?.isNotEmpty == true
                                    ? orden.cliente!.telefono!
                                    : 'No registrado'),
                          ),
                          const SizedBox(height: 6),
                          _buildDatoFila(
                            Icons.location_on_outlined,
                            'Dirección:',
                            desp.direccionEnvio,
                          ),
                          const SizedBox(height: 6),
                          _buildDatoFila(
                            Icons.map_outlined,
                            'Comuna Destino:',
                            (desp.comunaDestino != null && desp.comunaDestino!.isNotEmpty)
                                ? desp.comunaDestino!
                                : (orden.cliente?.comuna ?? 'No especificada'),
                          ),
                          const SizedBox(height: 6),
                          _buildDatoFila(
                            Icons.local_shipping_outlined,
                            'Transporte:',
                            desp.empresaTransporte ?? 'Chilexpress',
                          ),
                          const SizedBox(height: 6),
                          _buildDatoFila(
                            Icons.payments_outlined,
                            'Costo Envío:',
                            desp.costoEnvioFormateado,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Trazabilidad de Vendedores
                  Text('TRAZABILIDAD DE VENDEDORES', style: AppTypography.small.copyWith(fontWeight: FontWeight.bold, color: AppPalette.textSecondary)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppPalette.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_pin_outlined, size: 16, color: AppPalette.textSecondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Vendedor Creador: ${orden.vendedorNombre ?? "Vendedor Central"}', style: AppTypography.small.copyWith(fontSize: 13.5)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.assignment_ind_outlined, size: 16, color: AppPalette.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Responsable Asignado: ${orden.vendedorAsignadoNombre ?? "Mesón General (Todos)"}', style: AppTypography.small.copyWith(color: AppPalette.primary, fontWeight: FontWeight.bold, fontSize: 13.5)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Desglose de Repuestos Exhaustivo
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'DESGLOSE DE REPUESTOS (${orden.totalItems})',
                          style: AppTypography.small.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppPalette.textSecondary,
                            fontSize: 13.0,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildPreparacionBadge(orden.preparacionLista),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...orden.detalles.map((item) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppPalette.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  item.esInventariado ? Icons.inventory_2_outlined : Icons.edit_note_outlined,
                                  size: 16,
                                  color: item.esInventariado ? AppPalette.primary : AppPalette.secondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item.tituloDisplay,
                                    style: AppTypography.body.copyWith(fontWeight: FontWeight.bold, fontSize: 14.5),
                                    maxLines: 2,
                                  ),
                                ),
                                Text(item.subtotalFormateado, style: AppTypography.body.copyWith(fontWeight: FontWeight.bold, fontSize: 14.5, color: AppPalette.primary)),
                              ],
                            ),
                            if (item.skuQrFisico != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text('SKU QR: ${item.skuQrFisico}', style: AppTypography.small.copyWith(color: AppPalette.textSecondary, fontSize: 12.5)),
                              ),
                            const SizedBox(height: 4.0),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                              decoration: BoxDecoration(
                                color: item.esMotorOCaja
                                    ? AppPalette.primary.withValues(alpha: 0.12)
                                    : AppPalette.secondary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4.0),
                                border: Border.all(
                                  color: item.esMotorOCaja
                                      ? AppPalette.primary.withValues(alpha: 0.3)
                                      : AppPalette.secondary.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    item.esMotorOCaja
                                        ? Icons.warehouse_outlined
                                        : Icons.storefront_outlined,
                                    size: 12.0,
                                    color: item.esMotorOCaja
                                        ? AppPalette.primary
                                        : AppPalette.secondary,
                                  ),
                                  const SizedBox(width: 4.0),
                                  Text(
                                    item.esMotorOCaja
                                        ? 'Retiro en Bodega (Barrera)'
                                        : 'Entrega Inmediata en Mesón',
                                    style: TextStyle(
                                      fontSize: 12.0,
                                      fontWeight: FontWeight.w600,
                                      color: item.esMotorOCaja
                                          ? AppPalette.primary
                                          : AppPalette.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (item.notasPreparacion != null &&
                                item.notasPreparacion!.isNotEmpty &&
                                (item.esInventariado || item.esMotorOCaja))
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text('Nota: ${item.notasPreparacion}', style: AppTypography.small.copyWith(color: AppPalette.warning, fontSize: 12.5)),
                              ),
                            const SizedBox(height: 4.0),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Cantidad: ${item.cantidad}x  •  Unitario: ${item.precioFinalFormateado}', style: AppTypography.small.copyWith(color: Colors.white, fontSize: 13.0)),
                                Text('Estado: ${item.estadoPreparacion ?? "Pendiente"}', style: TextStyle(color: item.preparacionLista ? AppPalette.success : AppPalette.warning, fontSize: 13.0, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 16),

                  // Resumen Financiero
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppPalette.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: saldoPendiente ? AppPalette.warning.withValues(alpha: 0.5) : AppPalette.success.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('TOTAL VENTA', style: TextStyle(color: AppPalette.textSecondary, fontSize: 12.0, fontWeight: FontWeight.bold)),
                            Text(orden.totalVentaFormateado, style: AppTypography.body.copyWith(fontWeight: FontWeight.bold, fontSize: 17.0)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              saldoPendiente ? 'SALDO PENDIENTE' : 'ESTADO DE PAGO',
                              style: TextStyle(
                                color: saldoPendiente ? AppPalette.warning : AppPalette.success,
                                fontSize: 12.0,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              saldoPendiente ? orden.montoPendienteFormateado : 'PAGADO COMPLETO',
                              style: TextStyle(
                                color: saldoPendiente ? AppPalette.warning : AppPalette.success,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Aviso Informativo para Orden Mixta
                  if (orden.esMixta) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppPalette.secondary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppPalette.secondary.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.swap_horiz_rounded, color: AppPalette.secondary, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Orden Mixta: Entrega los repuestos misceláneos al cliente en mostrador. El activo principal (motor/caja) debe retirarse en bodega con el Ticket QR.',
                              style: AppTypography.small.copyWith(
                                color: AppPalette.textPrimary,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Botonera de Acción en Detalle
                  Row(
                    children: [
                      if (orden.tipoEntrega.toLowerCase() == 'retiro') ...[
                        if (orden.contieneMotorOCaja) ...[
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: orden.tieneQrDisponible
                                    ? AppPalette.primary
                                    : AppPalette.textSecondary,
                                side: BorderSide(
                                  color: orden.tieneQrDisponible
                                      ? AppPalette.primary
                                      : Colors.white24,
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                if (!orden.tieneQrDisponible) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: AppPalette.surface,
                                      behavior: SnackBarBehavior.floating,
                                      content: Row(
                                        children: [
                                          const Icon(Icons.lock_clock_rounded,
                                              color: AppPalette.warning, size: 20),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              saldoPendiente
                                                  ? 'QR bloqueado: Orden con saldo pendiente de ${orden.montoPendienteFormateado}. Requiere confirmación de pago en Caja.'
                                                  : 'Esta orden no requiere código QR para retiro en bodega.',
                                              style: const TextStyle(color: AppPalette.warning),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                Navigator.of(ctx).pop();
                                _abrirQrModal(orden);
                              },
                              icon: Icon(
                                orden.tieneQrDisponible ? Icons.qr_code_2 : Icons.lock_outline,
                                size: 18,
                              ),
                              label: Text(
                                orden.tieneQrDisponible ? 'VER TICKET QR' : 'QR BLOQUEADO',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ] else ...[
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: saldoPendiente ? AppPalette.surface : AppPalette.success,
                                foregroundColor: saldoPendiente ? AppPalette.textSecondary : Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: saldoPendiente ? Colors.white12 : AppPalette.success,
                                  ),
                                ),
                              ),
                              onPressed: () {
                                Navigator.of(ctx).pop();
                                _confirmarEntregaTienda(orden);
                              },
                              icon: Icon(
                                saldoPendiente ? Icons.lock_outline : Icons.check_circle_outline,
                                size: 18,
                              ),
                              label: const Text(
                                'ENTREGADO',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ] else ...[
                        // Despacho: Permite visualizar Ticket QR para salida en Barrera de Bodega y Registrar Despacho con OT
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: orden.tieneQrDisponible
                                  ? AppPalette.secondary
                                  : AppPalette.textSecondary,
                              side: BorderSide(
                                color: orden.tieneQrDisponible
                                    ? AppPalette.secondary
                                    : Colors.white24,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () {
                              if (!orden.tieneQrDisponible) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    backgroundColor: AppPalette.surface,
                                    behavior: SnackBarBehavior.floating,
                                    content: Row(
                                      children: [
                                        const Icon(Icons.lock_clock_rounded,
                                            color: AppPalette.warning, size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            saldoPendiente
                                                ? 'QR bloqueado: Orden con saldo pendiente de ${orden.montoPendienteFormateado}. Requiere confirmación de pago en Caja.'
                                                : 'Esta orden no tiene código QR disponible.',
                                            style: const TextStyle(color: AppPalette.warning),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                                return;
                              }
                              Navigator.of(ctx).pop();
                              _abrirQrModal(orden);
                            },
                            icon: Icon(
                              orden.tieneQrDisponible ? Icons.qr_code_2 : Icons.lock_outline,
                              size: 18,
                            ),
                            label: Text(
                              orden.tieneQrDisponible ? 'TICKET QR' : 'QR BLOQUEADO',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppPalette.secondary,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () {
                              Navigator.of(ctx).pop();
                              _marcarDespachoEnviadoModal(orden);
                            },
                            icon: const Icon(Icons.local_shipping, size: 18),
                            label: const Text(
                              'DESPACHAR (OT)',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        foregroundColor: AppPalette.textPrimary,
        iconTheme: const IconThemeData(color: AppPalette.textPrimary),
        elevation: 0,
        titleSpacing: 12,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: AppPalette.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Volver',
              )
            : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_shipping_outlined, color: AppPalette.primary, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Retiro y Envíos',
                style: AppTypography.title.copyWith(fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!_isLoading) ...[
              const SizedBox(width: 8),
              _buildBadgeCount(_ordenesFiltradas.length, AppPalette.primary),
            ],
          ],
        ),
        actions: [
          // Botón de Filtros con indicador de estado
          IconButton(
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            icon: Stack(
              children: [
                Icon(
                  Icons.tune_outlined,
                  size: 22,
                  color: _tieneFiltrosActivos ? AppPalette.primary : AppPalette.textPrimary,
                ),
                if (_tieneFiltrosActivos)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppPalette.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: 'Filtros de Búsqueda',
            onPressed: _abrirModalFiltros,
          ),
          const SizedBox(width: 4),
          IconButton(
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            icon: const Icon(Icons.refresh_rounded, color: AppPalette.textPrimary, size: 22),
            tooltip: 'Actualizar lista',
            onPressed: _cargarDatos,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading && _todasEntregas.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppPalette.primary))
          : _errorMessage != null && _todasEntregas.isEmpty
              ? _buildErrorView()
              : Column(
                  children: [
                    _buildSyncStatusBanner(),
                    _buildSearchAndFiltersHeader(),
                    Expanded(child: _buildListaRetirosYEnvios()),
                  ],
                ),
    );
  }

  Widget _buildSyncStatusBanner() {
    return ValueListenableBuilder<SyncStatus>(
      valueListenable: _syncService.statusNotifier,
      builder: (context, status, _) {
        final int colaPendiente = _syncService.colaPendienteCount;

        if (status.estaAlDia && colaPendiente == 0) {
          return const SizedBox.shrink();
        }

        Color bg;
        Color fg;
        IconData icon;
        String mensaje;

        if (status.esInestable) {
          bg = AppPalette.warning.withValues(alpha: 0.15);
          fg = AppPalette.warning;
          icon = Icons.wifi_protected_setup_rounded;
          mensaje = colaPendiente > 0
              ? 'Señal débil en patio · Reintentando sincronización ($colaPendiente despachos en cola)...'
              : (status.mensaje ?? 'Conexión intermitente · Reintentando en segundo plano...');
        } else if (status.estaSincronizando) {
          bg = AppPalette.primary.withValues(alpha: 0.15);
          fg = AppPalette.primary;
          icon = Icons.sync_rounded;
          mensaje = colaPendiente > 0
              ? 'Sincronizando entregas y procesando cola ($colaPendiente pendientes)...'
              : (status.mensaje ?? 'Actualizando retiros y despachos...');
        } else if (status.tienePendientes || colaPendiente > 0) {
          final count = colaPendiente > 0 ? colaPendiente : status.pendientesCount;
          bg = AppPalette.secondary.withValues(alpha: 0.15);
          fg = AppPalette.secondary;
          icon = Icons.pending_actions_rounded;
          mensaje = '$count despacho(s) registrado(s) localmente pendientes de red';
        } else {
          return const SizedBox.shrink();
        }

        return Container(
          key: const Key('sync_status_banner'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              bottom: BorderSide(
                color: fg.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: fg, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mensaje,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (status.esInestable)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _cargarDatos(),
                  child: Text(
                    'REINTENTAR',
                    style: TextStyle(
                      color: fg,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchAndFiltersHeader() {
    final validas = _todasEntregas.where((e) {
      if (e.esVentaEnVerde && (!e.estaPagada || !e.tieneQrDisponible)) {
        return false;
      }
      return true;
    }).toList();

    final misAsignadasCount = validas.where(_isAsignadaAMi).length;
    final pagadasCount = validas.where((e) => e.estaPagada).length;
    final pendientesCount = validas.where((e) => e.tieneSaldoPendiente).length;
    final retirosCount = validas
        .where((e) => e.tipoEntrega.toLowerCase() == 'retiro')
        .length;
    final despachosCount = validas
        .where((e) =>
            e.tipoEntrega.toLowerCase() == 'despacho' ||
            e.tipoEntrega.toLowerCase() == 'despacho domicilio')
        .length;
    final trasladosCount = validas
        .where((e) => e.tipoEntrega.toLowerCase() == 'traslado')
        .length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 920;

        final searchBar = TextField(
          key: const Key('buscador_entregas_textfield'),
          controller: _searchController,
          onChanged: (val) {
            setState(() {
              _searchQuery = val;
            });
          },
          style: AppTypography.body.copyWith(
            color: AppPalette.textPrimary,
            fontSize: 13.5,
          ),
          cursorColor: AppPalette.primary,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Buscar por Folio, Cliente, RUT, Vendedor o SKU...',
            hintStyle: AppTypography.body.copyWith(
              color: AppPalette.textSecondary.withValues(alpha: 0.6),
              fontSize: 13,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: AppPalette.textSecondary,
              size: 20,
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    key: const Key('btn_limpiar_busqueda_entregas'),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppPalette.textSecondary,
                      size: 18,
                    ),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                    tooltip: 'Limpiar búsqueda',
                  )
                : null,
            filled: true,
            fillColor: AppPalette.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF334155)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF334155)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppPalette.primary, width: 1.5),
            ),
          ),
        );

        final chipsRow = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Chip Especial: Mis Entregas Asignadas
            _buildHeaderFilterPill(
              key: const Key('chip_mis_asignadas'),
              label: 'Mis Asignadas ($misAsignadasCount)',
              icon: Icons.person_pin_circle_rounded,
              isSelected: _soloMisAsignadas,
              activeColor: AppPalette.primary,
              onTap: () {
                setState(() {
                  _soloMisAsignadas = !_soloMisAsignadas;
                });
              },
            ),
            const SizedBox(width: 8),

            // Separador vertical sutil
            Container(
              height: 20,
              width: 1,
              color: Colors.white12,
              margin: const EdgeInsets.symmetric(horizontal: 2),
            ),
            const SizedBox(width: 8),

            // 2. Grupo Estado de Preparación / Pago
            // Chip: Listas para Entrega (Pagadas) [PREDETERMINADO]
            _buildHeaderFilterPill(
              key: const Key('chip_filtro_pagadas'),
              label: 'Listas ($pagadasCount)',
              icon: Icons.check_circle_outline_rounded,
              isSelected: _estadoPagoFilter == 'pagados',
              activeColor: AppPalette.success,
              onTap: () {
                setState(() => _estadoPagoFilter = 'pagados');
              },
            ),
            const SizedBox(width: 6),

            // Chip: Con Saldo Pendiente
            _buildHeaderFilterPill(
              key: const Key('chip_filtro_pendientes'),
              label: 'Con Saldo ($pendientesCount)',
              icon: Icons.monetization_on_outlined,
              isSelected: _estadoPagoFilter == 'pendientes',
              activeColor: AppPalette.warning,
              onTap: () {
                setState(() => _estadoPagoFilter = 'pendientes');
              },
            ),
            const SizedBox(width: 6),

            // Chip: Todas
            _buildHeaderFilterPill(
              key: const Key('chip_filtro_todas'),
              label: 'Todas (${validas.length})',
              icon: Icons.layers_outlined,
              isSelected: _estadoPagoFilter == 'todos' && _tipoEntregaFilter == 'todos',
              activeColor: AppPalette.primary,
              onTap: () {
                setState(() {
                  _estadoPagoFilter = 'todos';
                  _tipoEntregaFilter = 'todos';
                });
              },
            ),
            const SizedBox(width: 8),

            // Separador vertical sutil
            Container(
              height: 20,
              width: 1,
              color: Colors.white12,
              margin: const EdgeInsets.symmetric(horizontal: 2),
            ),
            const SizedBox(width: 8),

            // 3. Grupo Modalidad de Entrega
            // Chip: Retiros
            _buildHeaderFilterPill(
              label: 'Retiros ($retirosCount)',
              isSelected: _tipoEntregaFilter == 'retiro',
              activeColor: AppPalette.primary,
              onTap: () {
                setState(() {
                  _tipoEntregaFilter = _tipoEntregaFilter == 'retiro' ? 'todos' : 'retiro';
                });
              },
            ),
            const SizedBox(width: 6),

            // Chip: Despachos
            _buildHeaderFilterPill(
              label: 'Despachos ($despachosCount)',
              isSelected: _tipoEntregaFilter == 'despacho',
              activeColor: AppPalette.secondary,
              onTap: () {
                setState(() {
                  _tipoEntregaFilter = _tipoEntregaFilter == 'despacho' ? 'todos' : 'despacho';
                });
              },
            ),
            const SizedBox(width: 6),

            // Chip: Traslados (si hay)
            if (trasladosCount > 0 || _tipoEntregaFilter == 'traslado') ...[
              _buildHeaderFilterPill(
                label: 'Traslados ($trasladosCount)',
                isSelected: _tipoEntregaFilter == 'traslado',
                activeColor: const Color(0xFFAB47BC),
                onTap: () {
                  setState(() {
                    _tipoEntregaFilter = _tipoEntregaFilter == 'traslado' ? 'todos' : 'traslado';
                  });
                },
              ),
              const SizedBox(width: 6),
            ],

            // Botón rápido de restablecer a predeterminado
            if (_tieneFiltrosActivos) ...[
              Material(
                color: AppPalette.surface,
                borderRadius: BorderRadius.circular(8.0),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _searchController.clear();
                      _searchQuery = '';
                      _soloMisAsignadas = false;
                      _tipoEntregaFilter = 'todos';
                      _estadoPagoFilter = 'pagados';
                      _clienteFilterController.clear();
                      _vendedorFilterController.clear();
                    });
                    _cargarDatos();
                  },
                  borderRadius: BorderRadius.circular(8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 7.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(
                        color: AppPalette.error.withValues(alpha: 0.6),
                        width: 1.2,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close, size: 14, color: AppPalette.error),
                        SizedBox(width: 4),
                        Text(
                          'Limpiar',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppPalette.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        );

        return Container(
          color: AppPalette.background,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: isDesktop
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 4,
                      child: searchBar,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 6,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: chipsRow,
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchBar,
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: chipsRow,
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildBadgeCount(int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$count',
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppPalette.error, size: 54),
            const SizedBox(height: 16),
            Text('Error al cargar retiros y envíos', style: AppTypography.title),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Ocurrió un error inesperado.',
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: AppPalette.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _cargarDatos,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListaRetirosYEnvios() {
    final lista = _ordenesFiltradas;
    if (lista.isEmpty) {
      return _buildEmptyView(
        icon: Icons.local_shipping_outlined,
        title: 'Sin Retiros o Envíos Pendientes',
        subtitle: _tieneFiltrosActivos
            ? 'No se encontraron órdenes con los filtros seleccionados.'
            : 'No hay pedidos pendientes en espera de retiro ni despachos.',
      );
    }

    return RefreshIndicator(
      color: AppPalette.primary,
      onRefresh: _cargarDatos,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: lista.length,
        itemBuilder: (context, index) {
          return _buildEntregaEnvioCard(lista[index]);
        },
      ),
    );
  }

  Widget _buildEmptyView({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: AppPalette.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(title, style: AppTypography.title.copyWith(color: AppPalette.textPrimary)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: AppPalette.textSecondary),
            ),
            if (_tieneFiltrosActivos) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  _searchController.clear();
                  _clienteFilterController.clear();
                  _vendedorFilterController.clear();
                  setState(() {
                    _searchQuery = '';
                    _soloMisAsignadas = false;
                    _estadoPagoFilter = 'todos';
                    _tipoEntregaFilter = 'todos';
                  });
                  _cargarDatos();
                },
                icon: const Icon(Icons.filter_alt_off),
                label: const Text('Limpiar Filtros'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Tarjeta Unificada para Retiro en Tienda y Despacho Courier
  Widget _buildEntregaEnvioCard(EntregaEnvioModel orden) {
    final bool saldoPendiente = orden.tieneSaldoPendiente;
    final bool esDespacho = orden.esDespacho;
    final desp = orden.despacho;

    // Resumen simple de ítems
    final itemsResumen = orden.detalles.length == 1
        ? '${orden.detalles.first.cantidad}x ${orden.detalles.first.tituloDisplay}'
        : '${orden.totalItems} piezas (${orden.detalles.map((d) => d.tituloDisplay).take(2).join(", ")}${orden.detalles.length > 2 ? "..." : ""})';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: saldoPendiente
              ? AppPalette.warning.withValues(alpha: 0.35)
              : esDespacho
                  ? AppPalette.secondary.withValues(alpha: 0.35)
                  : AppPalette.success.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _abrirDetalleCompleto(orden),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Fila 1: Folio + Fecha + Chip de Modalidad / Courier
              Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: (esDespacho ? AppPalette.secondary : AppPalette.primary)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              orden.folioDisplay,
                              style: AppTypography.body.copyWith(
                                fontWeight: FontWeight.bold,
                                color: esDespacho ? AppPalette.secondary : AppPalette.primary,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          orden.fechaFormateada,
                          style: AppTypography.small.copyWith(
                            color: AppPalette.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (esDespacho ? AppPalette.secondary : AppPalette.primary)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: (esDespacho ? AppPalette.secondary : AppPalette.primary)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          esDespacho ? Icons.local_shipping : Icons.storefront,
                          size: 12,
                          color: esDespacho ? AppPalette.secondary : AppPalette.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          esDespacho
                              ? (desp?.empresaTransporte ?? 'Despacho')
                              : 'Retiro',
                          style: AppTypography.small.copyWith(
                            color: esDespacho ? AppPalette.secondary : AppPalette.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Fila 2: Datos de Cliente / Receptor y Despacho + Vendedor
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    esDespacho
                        ? Icons.location_on_outlined
                        : (orden.esConsumidorFinal ? Icons.receipt_long_outlined : Icons.person_outline),
                    size: 18,
                    color: esDespacho
                        ? AppPalette.secondary
                        : (orden.esConsumidorFinal ? AppPalette.primary : AppPalette.textSecondary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          esDespacho
                              ? ((desp != null && desp.receptorNombres.isNotEmpty && desp.receptorNombres != "S/R")
                                  ? '${desp.receptorNombres} (${desp.comunaDestino ?? "Destino"})'
                                  : orden.clienteDisplay)
                              : orden.clienteDisplay,
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: (!esDespacho && orden.esConsumidorFinal)
                                ? AppPalette.primary
                                : AppPalette.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        if (esDespacho && desp != null) ...[
                          Text(
                            'Destino: ${desp.direccionEnvio}${(desp.comunaDestino != null && desp.comunaDestino!.isNotEmpty) ? ", ${desp.comunaDestino!}" : ""}${desp.receptorTelefono.isNotEmpty ? " • Tel: ${desp.receptorTelefono}" : (orden.cliente?.telefono?.isNotEmpty == true ? " • Tel: ${orden.cliente!.telefono!}" : "")}',
                            style: AppTypography.small.copyWith(
                              color: AppPalette.textSecondary,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Courier: ${desp.empresaTransporte ?? "Chilexpress"} • ${desp.costoEnvioFormateado} • Estado: ${desp.estadoDespacho}',
                            style: AppTypography.small.copyWith(
                              color: AppPalette.secondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        Text(
                          'Vendedor: ${orden.vendedorNombre ?? "Vendedor Central"} • Resp: ${orden.vendedorAsignadoNombre ?? "Mesón General"}',
                          style: AppTypography.small.copyWith(
                            color: AppPalette.textSecondary,
                            fontSize: 12.5,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Fila 3: Resumen de ítems y Badge de estado financiero / despacho
              Row(
                children: [
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            itemsResumen,
                            style: AppTypography.body.copyWith(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                              color: AppPalette.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (orden.esMixta) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppPalette.secondary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppPalette.secondary.withValues(alpha: 0.4)),
                            ),
                            child: const Text(
                              'Mixta',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: AppPalette.secondary,
                              ),
                            ),
                          ),
                        ] else if (!orden.contieneMotorOCaja && !esDespacho) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppPalette.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppPalette.success.withValues(alpha: 0.3)),
                            ),
                            child: const Text(
                              'Mesón',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: AppPalette.success,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  saldoPendiente
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppPalette.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppPalette.warning),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'SALDO: ${orden.montoPendienteFormateado}',
                              style: const TextStyle(
                                color: AppPalette.warning,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppPalette.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppPalette.success),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'PAGADO',
                              style: TextStyle(
                                color: AppPalette.success,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                ],
              ),
              const SizedBox(height: 12),

              // Fila 4: Botonera de Acción Rápida (Ticket QR para salida de barrera o Entrega en Mesón)
              if (esDespacho || orden.contieneMotorOCaja) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: InkWell(
                        onTap: () {
                          if (!orden.tieneQrDisponible) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: AppPalette.surface,
                                behavior: SnackBarBehavior.floating,
                                content: Row(
                                  children: [
                                    const Icon(Icons.lock_clock_rounded,
                                        color: AppPalette.warning, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        saldoPendiente
                                            ? 'QR bloqueado: Orden con saldo pendiente de ${orden.montoPendienteFormateado}. Requiere confirmación de pago en Caja.'
                                            : 'Esta orden no tiene código QR disponible.',
                                        style: const TextStyle(color: AppPalette.warning),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                            return;
                          }
                          _abrirQrModal(orden);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                orden.tieneQrDisponible ? Icons.qr_code_2 : Icons.lock_outline,
                                color: orden.tieneQrDisponible
                                    ? (esDespacho ? AppPalette.secondary : AppPalette.primary)
                                    : AppPalette.warning,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  orden.tieneQrDisponible ? 'Ticket QR' : 'QR Bloqueado',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.body.copyWith(
                                    color: orden.tieneQrDisponible
                                        ? (esDespacho ? AppPalette.secondary : AppPalette.primary)
                                        : AppPalette.warning,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (esDespacho) ...[
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _marcarDespachoEnviadoModal(orden),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppPalette.secondary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppPalette.secondary.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.local_shipping,
                                size: 15,
                                color: AppPalette.secondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Despachar (OT)',
                                style: AppTypography.small.copyWith(
                                  color: AppPalette.secondary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppPalette.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.qr_code_scanner,
                                size: 15,
                                color: orden.esMixta ? AppPalette.secondary : AppPalette.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  orden.esMixta ? 'Mixta · Barrera Bodega' : 'Salida en Barrera Bodega',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.small.copyWith(
                                    color: orden.esMixta ? AppPalette.secondary : AppPalette.textSecondary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () => _abrirDetalleCompleto(orden),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.receipt_long_outlined, color: AppPalette.textSecondary, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'Ver Detalle',
                              style: AppTypography.body.copyWith(
                                color: AppPalette.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 38,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: saldoPendiente
                              ? AppPalette.surface
                              : AppPalette.success,
                          foregroundColor: saldoPendiente
                              ? AppPalette.textSecondary
                              : Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: saldoPendiente
                                  ? Colors.white12
                                  : AppPalette.success,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        ),
                        onPressed: () => _confirmarEntregaTienda(orden),
                        icon: Icon(
                          saldoPendiente ? Icons.lock_outline : Icons.check_circle_outline,
                          size: 18,
                        ),
                        label: const Text(
                          'Entregado',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreparacionBadge(bool lista) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: lista
            ? AppPalette.success.withValues(alpha: 0.15)
            : AppPalette.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        lista ? 'PREPARACIÓN LISTA' : 'EN PREPARACIÓN',
        style: TextStyle(
          color: lista ? AppPalette.success : AppPalette.warning,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
