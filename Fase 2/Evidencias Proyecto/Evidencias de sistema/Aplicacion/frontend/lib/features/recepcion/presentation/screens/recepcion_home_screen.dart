import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/widgets/update_dialog.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../routes/app_routes.dart';
import '../../../auth/services/auth_service.dart';
import '../../models/vehiculo_recepcion_model.dart';
import '../../services/recepcion_service.dart';

class RecepcionHomeScreen extends StatefulWidget {
  const RecepcionHomeScreen({super.key});

  @override
  State<RecepcionHomeScreen> createState() => _RecepcionHomeScreenState();
}

class _RecepcionHomeScreenState extends State<RecepcionHomeScreen> {
  final RecepcionService _recepcionService = RecepcionService();
  final TextEditingController _searchController = TextEditingController();

  String _siguienteIngreso = '...';
  bool _isLoadingFolio = true;
  bool _isLoadingRecientes = true;
  List<VehiculoRecepcionModel> _recientes = [];
  String? _userNombre;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _cargarDatosUsuario();
    _cargarDatos();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatosUsuario() async {
    final cached = AuthService.cachedUser;
    if (cached != null) {
      setState(() {
        _userNombre = cached.nombreCompleto;
        _userEmail = cached.email;
      });
    } else {
      final nombre = await AuthService.getNombreUsuario();
      final email = await AuthService.getEmailUsuario();
      setState(() {
        _userNombre = nombre ?? 'Gloria';
        _userEmail = email ?? 'gloria@cresal.cl';
      });
    }
  }

  Future<void> _cargarDatos() async {
    await Future.wait([
      _cargarSiguienteFolio(),
      _cargarRecientes(),
    ]);
  }

  Future<void> _cargarSiguienteFolio() async {
    setState(() => _isLoadingFolio = true);
    final folio = await _recepcionService.obtenerSiguienteIngreso();
    if (mounted) {
      setState(() {
        _siguienteIngreso = folio;
        _isLoadingFolio = false;
      });
    }
  }

  Future<void> _cargarRecientes([String? busqueda]) async {
    setState(() => _isLoadingRecientes = true);
    final esBusqueda = busqueda != null && busqueda.trim().isNotEmpty;
    final lista = await _recepcionService.obtenerRecientes(
      busqueda: esBusqueda ? busqueda : null,
      limite: esBusqueda ? 50 : 5,
    );
    if (mounted) {
      setState(() {
        _recientes = lista;
        _isLoadingRecientes = false;
      });
    }
  }

  Future<void> _copiarRegistroAlPortapapeles(VehiculoRecepcionModel v) async {
    final texto = v.toTextoCamposValores();
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '📋 Folio N° ${v.numeroIngreso} (${v.patente ?? "S/PPU"}): Ficha copiada al portapapeles',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppPalette.primary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'VER FICHA',
          textColor: Colors.white,
          onPressed: () => _mostrarDetalleVehiculo(v),
        ),
      ),
    );
  }

  Future<void> _copiarFilaExcelAlPortapapeles(VehiculoRecepcionModel v) async {
    final tsv = v.toTsvRow();
    await Clipboard.setData(ClipboardData(text: tsv));
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '📊 Folio N° ${v.numeroIngreso}: Fila copiada para Excel. Pégala con Ctrl+V en la columna A.',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF107C41),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'VER FICHA',
          textColor: Colors.white,
          onPressed: () => _mostrarDetalleVehiculo(v),
        ),
      ),
    );
  }

  Future<void> _cerrarSesion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        title: const Text('Cerrar Sesión', style: TextStyle(color: AppPalette.textPrimary)),
        content: const Text(
          '¿Deseas salir del módulo de Recepción de Patio?',
          style: TextStyle(color: AppPalette.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: AppTypography.button.copyWith(color: AppPalette.neutral),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'CERRAR SESIÓN',
              style: AppTypography.button.copyWith(color: AppPalette.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await AuthService.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: AppPalette.primary, size: 22),
      title: Text(
        label,
        style: AppTypography.button.copyWith(fontSize: 14, letterSpacing: 1.0),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final cached = AuthService.cachedUser;
    final nombreCompleto = (_userNombre != null && _userNombre!.trim().isNotEmpty)
        ? _userNombre!.trim()
        : (cached != null && cached.nombres.isNotEmpty
            ? '${cached.nombres} ${cached.apellidos}'.trim()
            : 'GLORIA');
    final email = (_userEmail != null && _userEmail!.trim().isNotEmpty)
        ? _userEmail!.trim()
        : (cached != null && cached.email.isNotEmpty ? cached.email : 'gloria@cresal.cl');
    final sucursal = 'Patio Central • $email';

    return Drawer(
      backgroundColor: AppPalette.surface,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            decoration: const BoxDecoration(
              color: AppPalette.background,
              border: Border(
                bottom: BorderSide(color: AppPalette.surface, width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: AppPalette.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.person,
                    color: AppPalette.textPrimary,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  nombreCompleto,
                  style: AppTypography.title.copyWith(
                    fontSize: 15,
                    letterSpacing: 0.8,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'RECEPCIÓN DE PATIO',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
                Text(
                  sucursal,
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _buildDrawerItem(
            icon: Icons.confirmation_number_outlined,
            label: 'TICKET',
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed(AppRoutes.tickets);
            },
          ),
          _buildDrawerItem(
            icon: Icons.settings_outlined,
            label: 'CONFIGURACIÓN',
            onTap: () => Navigator.of(context).pop(),
          ),
          _buildDrawerItem(
            icon: Icons.system_update_alt_rounded,
            label: 'BUSCAR ACTUALIZACIONES',
            onTap: () {
              Navigator.of(context).pop();
              AppUpdateChecker.check(context, showIfUpToDate: true);
            },
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _cerrarSesion,
                icon: const Icon(Icons.logout, size: 20),
                label: Text(
                  'CERRAR SESIÓN',
                  style: AppTypography.button.copyWith(
                    fontSize: 14,
                    letterSpacing: 0.8,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.error,
                  foregroundColor: AppPalette.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
          FutureBuilder<String>(
            future: AppUpdateService().getCurrentVersion(),
            builder: (context, snapshot) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Cresal App v${snapshot.data ?? "..."}',
                  style: AppTypography.small.copyWith(
                    color: AppPalette.textSecondary.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        foregroundColor: AppPalette.textPrimary,
        elevation: 0,
        title: Text(
          'Terminal Recepción',
          style: AppTypography.title.copyWith(fontSize: 17),
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: AppPalette.textPrimary),
            onPressed: () {
              FocusScope.of(context).unfocus();
              Scaffold.of(context).openDrawer();
            },
            tooltip: 'Menú',
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppPalette.primary),
            tooltip: 'Actualizar bandeja',
            onPressed: _cargarDatos,
          ),
        ],
      ),
      drawer: _buildDrawer(context),
      body: RefreshIndicator(
        onRefresh: _cargarDatos,
        color: AppPalette.primary,
        backgroundColor: AppPalette.surface,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. BANNER EN VIVO: SIGUIENTE INGRESO
              _buildFolioLiveBanner(),

              const SizedBox(height: 16),

              // 2. BOTÓN PRINCIPAL: + INGRESAR VEHÍCULO A PATIO (ALTA VISIBILIDAD)
              _buildBotonIngresarVehiculo(),

              const SizedBox(height: 20),

              // 3. BUSCADOR RÁPIDO PARA EVITAR DUPLICADOS
              _buildBuscadorRapido(),

              const SizedBox(height: 16),

              // 4. BANDEJA DE ENTRADAS RECIENTES (PREDETERMINADO 5)
              _buildBandejaRecientes(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolioLiveBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.primary.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.tag_rounded, color: AppPalette.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CORRELATIVO EN VIVO',
                  style: const TextStyle(
                    color: AppPalette.textSecondary,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      const Text(
                        'Siguiente Ingreso: ',
                        style: TextStyle(color: AppPalette.textPrimary, fontSize: 14),
                      ),
                      Text(
                        _isLoadingFolio ? '...' : 'N° $_siguienteIngreso',
                        style: const TextStyle(
                          color: AppPalette.secondary,
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.sync_rounded, color: AppPalette.textSecondary),
            onPressed: _cargarSiguienteFolio,
            tooltip: 'Refrescar correlativo',
          ),
        ],
      ),
    );
  }

  Widget _buildBotonIngresarVehiculo() {
    return SizedBox(
      height: 60,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        onPressed: () async {
          final creado = await Navigator.of(context).pushNamed(AppRoutes.recepcionRegistro);
          if (creado == true) {
            _cargarDatos();
          }
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_circle_outline_rounded, size: 26),
            const SizedBox(width: 10),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: const Text(
                  'INGRESAR VEHÍCULO A PATIO',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuscadorRapido() {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.neutral.withValues(alpha: 0.3)),
      ),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: AppPalette.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Buscar por Patente, Folio N°, Marca o Chofer...',
          hintStyle: const TextStyle(color: AppPalette.textSecondary, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, color: AppPalette.primary, size: 22),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: AppPalette.textSecondary, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    _cargarRecientes();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
        onChanged: (val) {
          setState(() {});
          if (val.trim().isEmpty) {
            _cargarRecientes();
          }
        },
        onSubmitted: (val) => _cargarRecientes(val),
      ),
    );
  }

  Widget _buildBandejaRecientes() {
    final esBusqueda = _searchController.text.trim().isNotEmpty;
    final titulo = esBusqueda
        ? 'Resultados de Búsqueda (${_recientes.length})'
        : 'Últimos 5 Ingresos Registrados';
    final subtitulo = esBusqueda
        ? 'Coincidencias encontradas'
        : 'Presiona cualquier registro para copiar sus datos';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      color: AppPalette.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    style: const TextStyle(color: AppPalette.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (esBusqueda)
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  _cargarRecientes();
                },
                child: const Text('Ver últimos 5', style: TextStyle(color: AppPalette.secondary, fontSize: 12)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoadingRecientes)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(color: AppPalette.primary),
            ),
          )
        else if (_recientes.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppPalette.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.no_crash_rounded, color: AppPalette.textSecondary, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    esBusqueda
                        ? 'No se encontraron resultados para la búsqueda'
                        : 'No hay ingresos vehiculares registrados aún',
                    style: const TextStyle(color: AppPalette.textSecondary, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recientes.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (ctx, idx) {
              final v = _recientes[idx];
              return _buildVehiculoCard(v);
            },
          ),
      ],
    );
  }

  Widget _buildVehiculoCard(VehiculoRecepcionModel v) {
    final esSppu = v.esSppu;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _copiarFilaExcelAlPortapapeles(v),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppPalette.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.neutral.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Folio N°
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppPalette.secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'N° ${v.numeroIngreso}',
                      style: const TextStyle(
                        color: AppPalette.secondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Patente / Badge SPPU
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: esSppu ? Colors.orange.withValues(alpha: 0.2) : AppPalette.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: esSppu ? Colors.orange : AppPalette.primary,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      v.patente ?? 'S/PPU',
                      style: TextStyle(
                        color: esSppu ? Colors.orangeAccent : Colors.white,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Botón Copiar Excel (TSV)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _copiarFilaExcelAlPortapapeles(v),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF107C41).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF107C41).withValues(alpha: 0.6),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.table_chart_rounded, color: Color(0xFF22C55E), size: 13),
                          SizedBox(width: 4),
                          Text(
                            'Excel',
                            style: TextStyle(
                              color: Color(0xFF22C55E),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Botón Copiar TXT
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _copiarRegistroAlPortapapeles(v),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppPalette.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: AppPalette.primary.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.copy_rounded, color: AppPalette.primary, size: 13),
                          SizedBox(width: 4),
                          Text(
                            'TXT',
                            style: TextStyle(
                              color: AppPalette.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.info_outline_rounded, size: 20, color: AppPalette.textSecondary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Ver ficha completa',
                    onPressed: () => _mostrarDetalleVehiculo(v),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${v.marca} ${v.modelo} ${v.anio != null ? "(${v.anio})" : ""}',
                style: const TextStyle(
                  color: AppPalette.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (v.origen != null && v.origen!.isNotEmpty) ...[
                    const Icon(Icons.store_rounded, size: 14, color: AppPalette.textSecondary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        v.origen!,
                        style: const TextStyle(color: AppPalette.textSecondary, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (v.grua != null && v.grua!.isNotEmpty) ...[
                    const Icon(Icons.local_shipping_rounded, size: 14, color: AppPalette.textSecondary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Grúa: ${v.grua}',
                        style: const TextStyle(color: AppPalette.textSecondary, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              if (v.observaciones != null && v.observaciones!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppPalette.background,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Obs: ${v.observaciones}',
                    style: const TextStyle(
                      color: AppPalette.textSecondary,
                      fontStyle: FontStyle.italic,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarDetalleVehiculo(VehiculoRecepcionModel v) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppPalette.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Folio N° ${v.numeroIngreso}',
                        style: const TextStyle(
                          color: AppPalette.secondary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: v.esSppu ? Colors.orange.withValues(alpha: 0.2) : AppPalette.primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: v.esSppu ? Colors.orange : AppPalette.primary,
                          ),
                        ),
                        child: Text(
                          v.patente ?? 'S/PPU',
                          style: TextStyle(
                            color: v.esSppu ? Colors.orangeAccent : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 12),
                  _buildDetalleFila('Marca:', v.marca),
                  _buildDetalleFila('Modelo:', v.modelo),
                  _buildDetalleFila('Año:', v.anio?.toString() ?? 'S/I'),
                  _buildDetalleFila('Color:', v.color ?? 'S/I'),
                  _buildDetalleFila('N° Motor:', v.numeroMotor ?? 'S/I'),
                  _buildDetalleFila('Tracción:', v.traccion ?? 'S/I'),
                  _buildDetalleFila('Destino:', v.destino),
                  _buildDetalleFila('Origen:', v.origen ?? 'S/I'),
                  _buildDetalleFila('Factura:', v.factura ?? 'S/I'),
                  _buildDetalleFila('Fecha Ingreso:', v.fechaIngresoFormateada),
                  _buildDetalleFila('Grúa:', v.grua ?? 'S/I'),
                  _buildDetalleFila('Observaciones:', v.observaciones ?? 'Sin observaciones'),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF107C41),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.table_chart_rounded, size: 18),
                          label: const Text('COPIAR EXCEL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _copiarFilaExcelAlPortapapeles(v);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppPalette.primary,
                            side: const BorderSide(color: AppPalette.primary),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          label: const Text('COPIAR TXT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _copiarRegistroAlPortapapeles(v);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetalleFila(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: AppPalette.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: const TextStyle(
                color: AppPalette.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
