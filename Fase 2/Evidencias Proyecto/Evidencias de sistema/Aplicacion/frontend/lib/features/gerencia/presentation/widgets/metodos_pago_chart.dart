// frontend/lib/features/gerencia/presentation/widgets/metodos_pago_chart.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../models/gerencia_models.dart';

/// Modalidad de visualización para el gráfico de medios de pago
enum MetricaMedioPago { monto, cantidad }

/// Gráfico de Dona interactivo de Medios de Pago (HU-5.1) con fl_chart.
/// Diseñado según el prototipo ejecutivo de Cresal con toggle [$ Monto / # Cant],
/// centro reactivo de alto rendimiento (60+ FPS sin micro-lag en hover).
class MetodosPagoChart extends StatefulWidget {
  final ResumenPagosModel resumen;

  const MetodosPagoChart({
    super.key,
    required this.resumen,
  });

  @override
  State<MetodosPagoChart> createState() => _MetodosPagoChartState();
}

class _MetodosPagoChartState extends State<MetodosPagoChart> {
  int _touchedIndex = -1;
  MetricaMedioPago _metricaSeleccionada = MetricaMedioPago.monto;

  // Paleta monocromática tonal corporativa de Cresal
  static const List<Color> _tonalPalette = [
    Color(0xFF004C89), // Azul profundo Cresal
    Color(0xFF0284C7), // Azul cielo medio
    Color(0xFF38BDF8), // Cyan celeste
    Color(0xFF94A3B8), // Slate 400
    Color(0xFFCBD5E1), // Slate 300
    Color(0xFFE2E8F0), // Slate 200
  ];

  Color _obtenerColor(int index, String metodo) {
    final m = metodo.toLowerCase();
    if (m.contains('transferencia')) return const Color(0xFF004C89);
    if (m.contains('crédito') || m.contains('credito')) {
      return const Color(0xFF0284C7);
    }
    if (m.contains('efectivo')) return const Color(0xFF38BDF8);
    if (m.contains('débito') || m.contains('debito')) {
      return const Color(0xFF94A3B8);
    }
    if (m.contains('cheque')) return const Color(0xFFCBD5E1);
    return _tonalPalette[index % _tonalPalette.length];
  }

  @override
  Widget build(BuildContext context) {
    final desglose = widget.resumen.desglose;
    final totalMonto = widget.resumen.totalRecaudado;
    final totalCant = widget.resumen.transaccionesCalculadas;
    final esMonto = _metricaSeleccionada == MetricaMedioPago.monto;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera del Bento con Título y Toggle [$ Monto / # Cant]
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'RECAUDACIÓN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Medios de Pago',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Distribución de ingresos por canal transaccional liquidado',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Segmented Control [$ Monto / # Cant]
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9), // Slate 100
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)), // Slate 200
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildToggleButton(
                      label: '\$ Monto',
                      isSelected: esMonto,
                      onTap: () {
                        if (!esMonto) {
                          setState(() {
                            _metricaSeleccionada = MetricaMedioPago.monto;
                            _touchedIndex = -1;
                          });
                        }
                      },
                    ),
                    _buildToggleButton(
                      label: '# Cant',
                      isSelected: !esMonto,
                      onTap: () {
                        if (esMonto) {
                          setState(() {
                            _metricaSeleccionada = MetricaMedioPago.cantidad;
                            _touchedIndex = -1;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Gráfico Donut y Leyenda
          Expanded(
            child: (esMonto ? totalMonto == 0 : totalCant == 0) || desglose.isEmpty
                ? _buildEmptyState()
                : Row(
                    children: [
                      // Donut PieChart
                      Expanded(
                        flex: 5,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            PieChart(
                              PieChartData(
                                pieTouchData: PieTouchData(
                                  touchCallback: (FlTouchEvent event,
                                      pieTouchResponse) {
                                    final newIndex =
                                        (!event.isInterestedForInteractions ||
                                                pieTouchResponse == null ||
                                                pieTouchResponse
                                                        .touchedSection ==
                                                    null)
                                            ? -1
                                            : pieTouchResponse
                                                .touchedSection!
                                                .touchedSectionIndex;
                                    // Optimización de rendimiento a 60+ FPS: Solo reconstruye si el índice cambia
                                    if (newIndex != _touchedIndex) {
                                      setState(() {
                                        _touchedIndex = newIndex;
                                      });
                                    }
                                  },
                                ),
                                borderData: FlBorderData(show: false),
                                sectionsSpace: 2.5,
                                centerSpaceRadius: 36,
                                sections: List.generate(desglose.length, (i) {
                                  final isTouched = i == _touchedIndex;
                                  final item = desglose[i];
                                  final color = _obtenerColor(i, item.metodoPago);
                                  final val = esMonto
                                      ? item.montoTotal.toDouble()
                                      : item.cantidad.toDouble();

                                  return PieChartSectionData(
                                    color: color,
                                    value: val,
                                    showTitle: false,
                                    title: '',
                                    radius: isTouched ? 36.0 : 30.0,
                                  );
                                }),
                              ),
                              duration: const Duration(milliseconds: 100),
                              curve: Curves.easeOutQuad,
                            ),

                            // Centro Reactivo
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _touchedIndex >= 0 &&
                                          _touchedIndex < desglose.length
                                      ? desglose[_touchedIndex]
                                          .metodoPago
                                          .split(' ')[0]
                                          .toUpperCase()
                                      : 'TOTAL',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _touchedIndex >= 0 &&
                                          _touchedIndex < desglose.length
                                      ? (esMonto
                                          ? CurrencyFormatter.formatCLP(
                                              desglose[_touchedIndex].montoTotal)
                                          : '${desglose[_touchedIndex].cantidad} uds')
                                      : (esMonto
                                          ? CurrencyFormatter.formatCLP(totalMonto)
                                          : '$totalCant uds'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Leyenda Tonal
                      Expanded(
                        flex: 6,
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          itemCount: desglose.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, i) {
                            final item = desglose[i];
                            final color = _obtenerColor(i, item.metodoPago);
                            final isHovered = i == _touchedIndex;
                            final pct = esMonto
                                ? item.porcentaje
                                : item.porcentajeCantidad;

                            return MouseRegion(
                              onEnter: (_) {
                                if (_touchedIndex != i) {
                                  setState(() => _touchedIndex = i);
                                }
                              },
                              onExit: (_) {
                                if (_touchedIndex == i) {
                                  setState(() => _touchedIndex = -1);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isHovered
                                      ? color.withValues(alpha: 0.1)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: color,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              item.metodoPago,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: isHovered
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: const Color(0xFF334155),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      esMonto
                                          ? '${pct.toStringAsFixed(0)}%'
                                          : '${item.cantidad} uds',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected
                ? AppPalette.primary
                : const Color(0xFF64748B), // Slate 500
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.pie_chart_outline, size: 40, color: Color(0xFFCBD5E1)),
          SizedBox(height: 8),
          Text(
            'Sin pagos registrados hoy',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
