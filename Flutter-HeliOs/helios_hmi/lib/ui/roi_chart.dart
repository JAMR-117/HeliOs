import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import '../theme/helios_theme.dart';

class RoiChart extends StatelessWidget {
  final Map<String, dynamic> spaData;

  const RoiChart({super.key, required this.spaData});

  @override
  Widget build(BuildContext context) {
    final currentHour = DateTime.now().hour + (DateTime.now().minute / 60.0);
    final elevation = (spaData['elevation'] as num?)?.toDouble() ?? 0.0;

    double staticWatts = 0.0;
    double heliosWatts = 0.0;

    if (elevation > 0) {
      double staticEfficiency = max(0.0, sin(pi * (currentHour - 6) / 12));
      staticWatts = 500.0 * staticEfficiency * (elevation / 90.0);

      double heliosEfficiency = max(0.0, sin(pi * (currentHour - 5) / 14));
      heliosWatts = 500.0 * heliosEfficiency;
    }

    int gainPercentage = 0;
    if (staticWatts > 0) {
      gainPercentage = (((heliosWatts - staticWatts) / staticWatts) * 100)
          .round();
    }

    final List<FlSpot> staticSpots = [];
    final List<FlSpot> heliosSpots = [];

    for (double h = 6; h <= 18; h += 0.5) {
      double sEff = max(0.0, sin(pi * (h - 6) / 12));
      double hEff = max(0.0, sin(pi * (h - 5) / 14));
      staticSpots.add(FlSpot(h, 500.0 * sEff * sEff));
      heliosSpots.add(FlSpot(h, 500.0 * hEff));
    }

    return Container(
      decoration: BoxDecoration(
        color: HeliosTheme.blueFantastic,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: HeliosTheme.oatmeal.withValues(alpha: 0.25),
        ),
      ),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ESTIMADOR DE ROI',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: HeliosTheme.palladian,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                elevation > 0
                    ? 'GANANCIA ACTUAL: +$gainPercentage%'
                    : 'SISTEMA EN REPOSO',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: elevation > 0 ? HeliosTheme.burningFlame : HeliosTheme.oatmeal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: HeliosTheme.oatmeal.withValues(alpha: 0.12),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      getTitlesWidget: (value, meta) {
                        if (value % 2 == 0) {
                          return Text(
                            '${value.toInt()}:00',
                            style: const TextStyle(
                              color: HeliosTheme.oatmeal,
                              fontSize: 12,
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 45,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${value.toInt()}W',
                          style: const TextStyle(
                            color: HeliosTheme.oatmeal,
                            fontSize: 11,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 6,
                maxX: 18,
                minY: 0,
                maxY: 600,
                lineBarsData: [
                  LineChartBarData(
                    spots: staticSpots,
                    isCurved: true,
                    color: HeliosTheme.oatmeal.withValues(alpha: 0.6),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: HeliosTheme.oatmeal.withValues(alpha: 0.08),
                    ),
                  ),
                  LineChartBarData(
                    spots: heliosSpots,
                    isCurved: true,
                    gradient: const LinearGradient(
                      colors: [
                        HeliosTheme.burningFlame,
                        HeliosTheme.truffleTrouble,
                      ],
                    ),
                    barWidth: 4,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          HeliosTheme.burningFlame.withValues(alpha: 0.35),
                          HeliosTheme.burningFlame.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  getTouchedSpotIndicator:
                      (LineChartBarData barData, List<int> spotIndexes) {
                    return spotIndexes.map((index) {
                      return TouchedSpotIndicatorData(
                        FlLine(
                          color: HeliosTheme.burningFlame.withValues(alpha: 0.6),
                          strokeWidth: 2,
                          dashArray: const [5, 5],
                        ),
                        const FlDotData(show: true),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem(
                HeliosTheme.burningFlame,
                'Seguidor HeliOs (${heliosWatts.round()}W)',
              ),
              const SizedBox(width: 40),
              _buildLegendItem(
                HeliosTheme.oatmeal,
                'Panel Estático (${staticWatts.round()}W)',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            color: HeliosTheme.palladian,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
