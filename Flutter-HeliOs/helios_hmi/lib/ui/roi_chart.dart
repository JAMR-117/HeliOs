import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'dart:math';

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

    return Card(
      color: const Color(0xFF1E1E1E),
      child: Padding(
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
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.cyanAccent,
                  ),
                ),
                Text(
                  elevation > 0
                      ? 'GANANCIA ACTUAL: +$gainPercentage%'
                      : 'SISTEMA EN REPOSO',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: elevation > 0 ? Colors.greenAccent : Colors.white54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            Expanded(
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(
                    show: true,
                    drawVerticalLine: false,
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
                              style: const TextStyle(color: Colors.white54),
                            );
                          }
                          return const Text('');
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
                      color: Colors.grey.withValues(alpha: 0.5),
                      barWidth: 4,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.grey.withValues(alpha: 0.1),
                      ),
                    ),
                    LineChartBarData(
                      spots: heliosSpots,
                      isCurved: true,
                      color: Colors.cyanAccent,
                      barWidth: 6,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.cyanAccent.withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    getTouchedSpotIndicator:
                        (LineChartBarData barData, List<int> spotIndexes) {
                          return spotIndexes.map((index) {
                            return TouchedSpotIndicatorData(
                              const FlLine(
                                color: Colors.white38,
                                strokeWidth: 2,
                                dashArray: [5, 5],
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
                  Colors.cyanAccent,
                  'Seguidor HeliOs (${heliosWatts.round()}W)',
                ),
                const SizedBox(width: 40),
                _buildLegendItem(
                  Colors.grey,
                  'Panel Estático (${staticWatts.round()}W)',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 18, color: Colors.white70)),
      ],
    );
  }
}
