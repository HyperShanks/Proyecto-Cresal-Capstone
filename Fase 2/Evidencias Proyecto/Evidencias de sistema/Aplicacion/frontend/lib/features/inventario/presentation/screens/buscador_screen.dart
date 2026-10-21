// lib/features/inventario/presentation/screens/buscador_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../services/inventario_service.dart';
import '../widgets/resultado_card.dart';

/// Pantalla Rediseñada del Buscador de Inventario en Bodega.
/// Incluye Carga Inicial Automática, Paginación Infinita (10 en 10),
/// Búsqueda por Texto Superior y ModalBottomSheet para Filtros Avanzados.
class BuscadorScreen extends StatefulWidget {
  const BuscadorScreen({super.key});

  @override
  State<BuscadorScreen> createState() => _BuscadorScreenState();
}

class _BuscadorScreenState extends State<BuscadorScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounceTimer;

  bool _isLoadingInitial = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String _errorMessage = '';

  List<dynamic> _resultados = [];
  final int _limit = 10;
  int _offset = 0;

  // Opciones dinámicas de filtros
  Map<String, List<String>> _opcionesFiltros = {};
  bool _isUpdatingFiltros = false;

  // Filtros activos
  String? _categoria;
  String? _pasillo;
  String? _pallet;
  String? _marca;
  String? _modelo;
  String? _cilindrada;
  String? _combustible;
  String? _transmision;

  // Filtro de Estado Operativo (SPEC-HU-TAREA-16)
  String _estadoFiltro = 'Todos';
  static const List<String> _estadosOperativos = [
    'Todos',
    'Disponibles',
    'Reservados',
    'Paletizados',
  ];

  int get _activeFiltersCount => [
        _categoria,
        _pasillo,
        _pallet,
        _marca,
        _modelo,
        _cilindrada,
        _combustible,
        _transmision,
      ].where((e) => e != null && e.isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _cargarFiltros();
    _ejecutarBusqueda(reset: true);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingInitial &&
        !_isLoadingMore &&
        _hasMore) {
      _ejecutarBusqueda(reset: false);
    }
  }

  void _onSearchChanged(String query) {
    setState(() {}); // Actualiza de inmediato el botón de limpiar
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _ejecutarBusqueda(reset: true);
    });
  }

  void _onClearSearch() {
    _searchController.clear();
    setState(() {});
    _ejecutarBusqueda(reset: true);
  }

  Future<void> _cargarFiltros() async {
    setState(() => _isUpdatingFiltros = true);
    try {
      final opciones = await InventarioService.obtenerOpcionesFiltros(
        categoria: _categoria,
        pasillo: _pasillo,
        pallet: _pallet,
        marca: _marca,
        modelo: _modelo,
        cilindrada: _cilindrada,
        combustible: _combustible,
        transmision: _transmision,
      );

      if (!mounted) return;
      setState(() {
        _opcionesFiltros = opciones;
      });
    } catch (e) {
      debugPrint('Error cargando opciones de filtros: $e');
    } finally {
      if (mounted) {
        setState(() => _isUpdatingFiltros = false);
      }
    }
  }

  Future<void> _ejecutarBusqueda({required bool reset}) async {
    if (reset) {
      setState(() {
        _isLoadingInitial = true;
        _errorMessage = '';
        _offset = 0;
        _hasMore = true;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final queryText = _searchController.text.trim();
      final nuevosResultados = await InventarioService.buscarRepuestos(
        q: queryText.isNotEmpty ? queryText : null,
        categoria: _categoria,
        pasillo: _pasillo,
        pallet: _pallet,
        marca: _marca,
        modelo: _modelo,
        cilindrada: _cilindrada,
        combustible: _combustible,
        transmision: _transmision,
        estado: _estadoFiltro,
        limit: _limit,
        offset: reset ? 0 : _offset,
      );

      if (!mounted) return;

      setState(() {
        if (reset) {
          _resultados = nuevosResultados;
        } else {
          _resultados.addAll(nuevosResultados);
        }

        _offset = _resultados.length;
        _hasMore = nuevosResultados.length >= _limit;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingInitial = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  /// Cambia reactivamente el filtro de estado operativo (SPEC-HU-TAREA-16).
  /// Limpia la lista, muestra spinner y ejecuta la búsqueda. En caso de desconexión,
  /// preserva el estado previo y despliega el aviso offline de la especificación.
  Future<void> _cambiarFiltroEstado(String nuevoEstado) async {
    if (_estadoFiltro == nuevoEstado) return;

    final estadoAnterior = _estadoFiltro;
    final resultadosPrevios = List<dynamic>.from(_resultados);

    setState(() {
      _estadoFiltro = nuevoEstado;
      _resultados = [];
      _isLoadingInitial = true;
      _errorMessage = '';
      _offset = 0;
      _hasMore = true;
    });

    try {
      final queryText = _searchController.text.trim();
      final nuevosResultados = await InventarioService.buscarRepuestos(
        q: queryText.isNotEmpty ? queryText : null,
        categoria: _categoria,
        pasillo: _pasillo,
        pallet: _pallet,
        marca: _marca,
        modelo: _modelo,
        cilindrada: _cilindrada,
        combustible: _combustible,
        transmision: _transmision,
        estado: nuevoEstado,
        limit: _limit,
        offset: 0,
      );

      if (!mounted) return;

      setState(() {
        _resultados = nuevosResultados;
        _offset = nuevosResultados.length;
        _hasMore = nuevosResultados.length >= _limit;
        _isLoadingInitial = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _estadoFiltro = estadoAnterior;
        _resultados = resultadosPrevios;
        _isLoadingInitial = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay conexión para aplicar este filtro. Mostrando caché temporal.'),
          backgroundColor: AppPalette.secondary,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _limpiarFiltros() {
    setState(() {
      _categoria = null;
      _pasillo = null;
      _pallet = null;
      _marca = null;
      _modelo = null;
      _cilindrada = null;
      _combustible = null;
      _transmision = null;
      _estadoFiltro = 'Todos';
    });
    _cargarFiltros();
    _ejecutarBusqueda(reset: true);
  }

  void _abrirModalFiltros() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalContext, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.75,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (_, scrollController) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
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
                  const SizedBox(height: 14),

                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.tune, color: AppPalette.primary, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'Filtros de Inventario',
                            style: AppTypography.title.copyWith(fontSize: 18),
                          ),
                        ],
                      ),
                      if (_activeFiltersCount > 0)
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              _categoria = null;
                              _pasillo = null;
                              _pallet = null;
                              _marca = null;
                              _modelo = null;
                              _cilindrada = null;
                              _combustible = null;
                              _transmision = null;
                            });
                            _limpiarFiltros();
                            Navigator.of(ctx).pop();
                          },
                          child: Text(
                            'Limpiar todo',
                            style: AppTypography.button.copyWith(
                              color: AppPalette.secondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 20),

                  // Dropdowns scrollable list
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        _buildDropdownItem(
                          label: 'CATEGORÍA DE INVENTARIO',
                          value: _categoria,
                          items: const ['MOTORES', 'CAJAS DE CAMBIO', 'ACCESORIOS'],
                          onChanged: (val) {
                            setModalState(() => _categoria = val);
                            setState(() => _categoria = val);
                            _cargarFiltros();
                          },
                          isFeatured: true,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDropdownItem(
                                label: 'PASILLO',
                                value: _pasillo,
                                items: _opcionesFiltros['pasillos'] ?? [],
                                onChanged: (val) {
                                  setModalState(() => _pasillo = val);
                                  setState(() => _pasillo = val);
                                  _cargarFiltros();
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildDropdownItem(
                                label: 'PALLET',
                                value: _pallet,
                                items: _opcionesFiltros['pallets'] ?? [],
                                onChanged: (val) {
                                  setModalState(() => _pallet = val);
                                  setState(() => _pallet = val);
                                  _cargarFiltros();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDropdownItem(
                                label: 'MARCA',
                                value: _marca,
                                items: _opcionesFiltros['marcas'] ?? [],
                                onChanged: (val) {
                                  setModalState(() => _marca = val);
                                  setState(() => _marca = val);
                                  _cargarFiltros();
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildDropdownItem(
                                label: 'MODELO',
                                value: _modelo,
                                items: _opcionesFiltros['modelos'] ?? [],
                                onChanged: (val) {
                                  setModalState(() => _modelo = val);
                                  setState(() => _modelo = val);
                                  _cargarFiltros();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildDropdownItem(
                          label: 'CILINDRADA',
                          value: _cilindrada,
                          items: _opcionesFiltros['cilindradas'] ?? [],
                          onChanged: (val) {
                            setModalState(() => _cilindrada = val);
                            setState(() => _cilindrada = val);
                            _cargarFiltros();
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildDropdownItem(
                          label: 'TIPO COMBUSTIBLE',
                          value: _combustible,
                          items: _opcionesFiltros['combustibles'] ?? [],
                          onChanged: (val) {
                            setModalState(() => _combustible = val);
                            setState(() => _combustible = val);
                            _cargarFiltros();
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildDropdownItem(
                          label: 'TIPO TRANSMISIÓN',
                          value: _transmision,
                          items: _opcionesFiltros['transmisiones'] ?? [],
                          onChanged: (val) {
                            setModalState(() => _transmision = val);
                            setState(() => _transmision = val);
                            _cargarFiltros();
                          },
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),

                  // Action button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _ejecutarBusqueda(reset: true);
                      },
                      icon: const Icon(Icons.check, size: 20),
                      label: Text(
                        'APLICAR FILTROS ($_activeFiltersCount)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppPalette.primary,
                        foregroundColor: AppPalette.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      appBar: AppBar(
        title: Text(
          'INVENTARIO DE BODEGA',
          style: AppTypography.headline.copyWith(
            color: AppPalette.textPrimary,
            letterSpacing: 1.2,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppPalette.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppPalette.primary),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Barra Superior: Buscador por Texto + Botón Filtros Modal ────
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 12.0),
              child: Row(
                children: [
                  // Campo de Búsqueda
                  Expanded(
                    child: TextField(
                      key: const Key('input_busqueda_inventario'),
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      style: AppTypography.body,
                      decoration: InputDecoration(
                        hintText: 'Buscar por marca, modelo o SKU...',
                        hintStyle: AppTypography.body.copyWith(
                          color: AppPalette.textSecondary,
                          fontSize: 14,
                        ),
                        filled: true,
                        fillColor: AppPalette.surface,
                        prefixIcon: const Icon(
                          Icons.search,
                          color: AppPalette.primary,
                        ),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: AppPalette.textSecondary),
                                onPressed: _onClearSearch,
                                tooltip: 'Limpiar búsqueda',
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 14.0,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12.0),
                          borderSide: const BorderSide(
                            color: AppPalette.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Botón de Filtros con Badge
                  Material(
                    color: _activeFiltersCount > 0
                        ? AppPalette.primary
                        : AppPalette.surface,
                    borderRadius: BorderRadius.circular(12.0),
                    child: InkWell(
                      key: const Key('btn_abrir_filtros_bodega'),
                      borderRadius: BorderRadius.circular(12.0),
                      onTap: _abrirModalFiltros,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12.0),
                          border: Border.all(
                            color: _activeFiltersCount > 0
                                ? AppPalette.primary
                                : Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.tune,
                              color: _activeFiltersCount > 0
                                  ? AppPalette.textPrimary
                                  : AppPalette.textSecondary,
                              size: 22,
                            ),
                            if (_activeFiltersCount > 0)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: AppPalette.secondary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$_activeFiltersCount',
                                    style: const TextStyle(
                                      color: AppPalette.background,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Fila de Filter Chips de Estado Operativo (SPEC-HU-TAREA-16) ──
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                children: _estadosOperativos.map((estadoNom) {
                  final isSelected = _estadoFiltro == estadoNom;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: FilterChip(
                      key: Key('chip_filtro_${estadoNom.toLowerCase()}'),
                      label: Text(
                        estadoNom,
                        style: AppTypography.small.copyWith(
                          color: isSelected ? Colors.white : AppPalette.textSecondary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          fontSize: 12.0,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: _isLoadingInitial ? null : (_) => _cambiarFiltroEstado(estadoNom),
                      selectedColor: AppPalette.primary,
                      backgroundColor: AppPalette.surface,
                      checkmarkColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20.0),
                        side: BorderSide(
                          color: isSelected
                              ? AppPalette.primary
                              : Colors.white.withValues(alpha: 0.12),
                          width: 1.0,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 6.0),

            // ── Conteo de Resultados ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Resultados (${_resultados.length})',
                    style: AppTypography.small.copyWith(
                      color: AppPalette.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_activeFiltersCount > 0 || _searchController.text.isNotEmpty)
                    InkWell(
                      onTap: () {
                        _searchController.clear();
                        _limpiarFiltros();
                      },
                      child: Text(
                        'Limpiar filtros',
                        style: AppTypography.small.copyWith(
                          color: AppPalette.secondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // ── Lista Principal con Paginación Infinita ─────────────────────
            Expanded(
              child: _isLoadingInitial
                  ? const Center(
                      child: CircularProgressIndicator(color: AppPalette.primary),
                    )
                  : _errorMessage.isNotEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline, size: 48, color: AppPalette.error),
                                const SizedBox(height: 12),
                                Text(
                                  'Error al consultar inventario',
                                  style: AppTypography.title.copyWith(color: AppPalette.error),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _errorMessage,
                                  style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () => _ejecutarBusqueda(reset: true),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Reintentar'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppPalette.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _resultados.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.inventory_2_outlined,
                                      size: 54,
                                      color: AppPalette.neutral,
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'No se encontraron repuestos',
                                      style: AppTypography.title,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Intenta ajustar los términos de búsqueda o los filtros.',
                                      style: AppTypography.small.copyWith(
                                        color: AppPalette.textSecondary,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              color: AppPalette.primary,
                              backgroundColor: AppPalette.surface,
                              onRefresh: () => _ejecutarBusqueda(reset: true),
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 24.0),
                                itemCount: _resultados.length + (_isLoadingMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == _resultados.length) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 16.0),
                                      child: Center(
                                        child: SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: AppPalette.primary,
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  final item = _resultados[index];
                                  return ResultadoCard(
                                    itemCompleto: item,
                                    marca: item['marca']?.toString() ?? 'Desconocida',
                                    modelo: item['modelo']?.toString() ?? 'Desconocido',
                                    sku: item['sku']?.toString() ?? 'S/N',
                                    ubicacion: item['ubicacion']?.toString() ?? 'S/P - S/P',
                                    estado: item['estado']?.toString() ?? 'DISPONIBLE',
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownItem({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
    bool isFeatured = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.small.copyWith(
            color: isFeatured ? AppPalette.textPrimary : AppPalette.textSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: value,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppPalette.background,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: AppPalette.primary,
                width: 1.5,
              ),
            ),
          ),
          dropdownColor: AppPalette.surface,
          items: [
            DropdownMenuItem<String>(
              value: null,
              child: Text(
                isFeatured ? '[ SELECCIONE ]' : 'TODAS',
                style: AppTypography.body.copyWith(
                  color: AppPalette.textSecondary,
                  fontSize: 13,
                ),
              ),
            ),
            ...items.map((item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(
                  item,
                  style: AppTypography.body.copyWith(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),
          ],
          onChanged: _isUpdatingFiltros ? null : onChanged,
        ),
      ],
    );
  }
}
