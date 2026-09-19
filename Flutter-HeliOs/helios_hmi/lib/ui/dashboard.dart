import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import '../services/mqtt_service.dart';
import 'scada_errors_screen.dart';
import 'plant_config_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mqttService = context.watch<MqttService>();

    final telemetry = mqttService.telemetryData;
    final spa = mqttService.spaData;
    final scada = mqttService.scadaData;

    final double? realPower = (telemetry['power_w'] as num?)?.toDouble();
    final double? realVoltage = (telemetry['v_dc'] as num?)?.toDouble();
    final double? realCurrent = (telemetry['i_dc'] as num?)?.toDouble();
    final double? yieldKwh = (telemetry['yield_kwh'] as num?)?.toDouble();
    final double? tempC = (telemetry['temp_c'] as num?)?.toDouble();

    final double? expPower = (spa['p_exp'] as num?)?.toDouble();
    final double? expVoltage = (spa['v_exp'] as num?)?.toDouble();
    final double? expCurrent = (spa['i_exp'] as num?)?.toDouble();
    final double? azimuth = (spa['azimuth'] as num?)?.toDouble();
    final double? elevation = (spa['elevation'] as num?)?.toDouble();

    final int scadaCode = (scada['code'] as num?)?.toInt() ?? 0;
    final String scadaDesc =
        scada['description'] as String? ?? 'Operación Normal';

    final bool isWaitingData = telemetry.isEmpty && spa.isEmpty;
    bool hasError = false;
    String alertMessage = "OPERACIÓN NORMAL";
    Color statusColor = const Color(0xFF1E293B);
    Color statusBorderColor = Colors.transparent;

    if (isWaitingData) {
      alertMessage = "ESPERANDO TELEMETRÍA...";
    } else if (scadaCode != 0) {
      hasError = true;
      alertMessage = "FALLA SCADA ($scadaCode): ${scadaDesc.toUpperCase()}";
      statusColor = Colors.red.shade900.withValues(alpha: 0.4);
      statusBorderColor = Colors.redAccent;
    } else if (realVoltage != null &&
        expVoltage != null &&
        expVoltage > 0 &&
        realVoltage < (expVoltage * 0.90)) {
      hasError = true;
      alertMessage = "ALERTA: PÉRDIDA DE PANEL EN SERIE";
      statusColor = Colors.red.shade900.withValues(alpha: 0.4);
      statusBorderColor = Colors.redAccent;
    } else if (realPower != null &&
        expPower != null &&
        expPower > 0 &&
        realPower < (expPower * 0.85)) {
      hasError = true;
      alertMessage = "ALERTA: SOMBREO O SUCIEDAD";
      statusColor = Colors.amber.shade900.withValues(alpha: 0.4);
      statusBorderColor = Colors.amberAccent;
    }

    const Color bgColor = Color(0xFF131B2A);
    const Color cardColor = Color(0xFF1E293B);
    const Color headerColor = Color(0xFF114238);
    const Color accentBlue = Color(0xFF38BDF8);
    const Color textMuted = Color(0xFF94A3B8);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white, size: 28),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20.0),
            child: Row(
              children: [
                if (tempC != null) ...[
                  Icon(
                    Icons.thermostat,
                    color: tempC > 65 ? Colors.redAccent : textMuted,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${tempC.toStringAsFixed(1)}°C',
                    style: TextStyle(
                      color: tempC > 65 ? Colors.redAccent : textMuted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
                if (yieldKwh != null) ...[
                  const Icon(Icons.bolt, color: textMuted, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '${yieldKwh.toStringAsFixed(1)} kWh',
                    style: const TextStyle(color: textMuted, fontSize: 13),
                  ),
                  const SizedBox(width: 14),
                ],
                Icon(
                  mqttService.isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: mqttService.isConnected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                  size: 24,
                ),
              ],
            ),
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: cardColor,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: bgColor),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.solar_power, size: 48, color: accentBlue),
                  SizedBox(height: 12),
                  Text(
                    'HeliOs OS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard, color: accentBlue),
              title: const Text(
                'Monitoreo Principal',
                style: TextStyle(
                  color: accentBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              selected: true,
              selectedTileColor: bgColor.withValues(alpha: 0.5),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white70,
              ),
              title: const Text(
                'Menú de Errores SCADA',
                style: TextStyle(color: Colors.white70),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ScadaErrorsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Colors.white70),
              title: const Text(
                'Configuración de Planta',
                style: TextStyle(color: Colors.white70),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PlantConfigScreen()),
                );
              },
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: headerColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.landscape, size: 48, color: Colors.greenAccent),
                    SizedBox(height: 8),
                    Text(
                      'HEADER ILUSTRATIVO',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Clima por horas',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 110,
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: MediaQuery.of(context).size.width - 32,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(24, (index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 16.0,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _getFormattedHour(index),
                                  style: const TextStyle(
                                    color: textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                const Icon(
                                  Icons.cloud_queue,
                                  color: Colors.white70,
                                  size: 24,
                                ),
                                const Text(
                                  '22°C',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Condiciones actuales',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 900 ? 4 : 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildMetricCard(
                    title: 'Potencia',
                    realValue: realPower != null
                        ? '${realPower.round()} W'
                        : '-- W',
                    expValue: expPower != null
                        ? '${expPower.round()} W'
                        : '-- W',
                    icon: Icons.bolt,
                    cardColor: cardColor,
                    mutedColor: textMuted,
                    accentColor: accentBlue,
                  ),
                  _buildMetricCard(
                    title: 'Voltaje DC',
                    realValue: realVoltage != null
                        ? '${realVoltage.toStringAsFixed(1)} V'
                        : '-- V',
                    expValue: expVoltage != null
                        ? '${expVoltage.toStringAsFixed(1)} V'
                        : '-- V',
                    icon: Icons.battery_charging_full,
                    cardColor: cardColor,
                    mutedColor: textMuted,
                    accentColor: accentBlue,
                  ),
                  _buildMetricCard(
                    title: 'Corriente DC',
                    realValue: realCurrent != null
                        ? '${realCurrent.toStringAsFixed(1)} A'
                        : '-- A',
                    expValue: expCurrent != null
                        ? '${expCurrent.toStringAsFixed(1)} A'
                        : '-- A',
                    icon: Icons.electric_meter,
                    cardColor: cardColor,
                    mutedColor: textMuted,
                    accentColor: accentBlue,
                  ),
                  _buildMetricCard(
                    title: 'Pos. Solar',
                    realValue: azimuth != null
                        ? '${azimuth.toStringAsFixed(1)}°'
                        : '--°',
                    expValue: elevation != null
                        ? 'El: ${elevation.toStringAsFixed(1)}°'
                        : 'El: --°',
                    icon: Icons.explore,
                    cardColor: cardColor,
                    mutedColor: textMuted,
                    accentColor: accentBlue,
                    isComparison: false,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: statusBorderColor,
                        width: hasError ? 2 : 0,
                      ),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          hasError
                              ? Icons.warning_amber_rounded
                              : (isWaitingData
                                    ? Icons.hourglass_empty
                                    : Icons.check_circle_outline),
                          color: hasError
                              ? (statusBorderColor == Colors.redAccent
                                    ? Colors.redAccent
                                    : Colors.amberAccent)
                              : (isWaitingData
                                    ? textMuted
                                    : Colors.greenAccent),
                          size: 38,
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Estado del Sistema',
                          style: TextStyle(color: textMuted, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          alertMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isWaitingData ? textMuted : Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              MultimodalChartContainer(
                expPower: expPower,
                realPower: realPower,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  String _getFormattedHour(int index) {
    int hour24 = (13 + index) % 24;
    if (hour24 == 0) return '12 AM';
    if (hour24 == 12) return '12 PM';
    return hour24 > 12 ? '${hour24 - 12} PM' : '$hour24 AM';
  }

  Widget _buildMetricCard({
    required String title,
    required String realValue,
    required String expValue,
    required IconData icon,
    required Color cardColor,
    required Color mutedColor,
    required Color accentColor,
    bool isComparison = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(icon, color: accentColor, size: 20),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                realValue,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isComparison ? 'Esperado: $expValue' : expValue,
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MultimodalChartContainer extends StatefulWidget {
  final double? expPower;
  final double? realPower;

  const MultimodalChartContainer({
    super.key,
    required this.expPower,
    required this.realPower,
  });

  @override
  State<MultimodalChartContainer> createState() =>
      _MultimodalChartContainerState();
}

class _MultimodalChartContainerState extends State<MultimodalChartContainer> {
  int _selectedTab = 0;

  static const Color _cardColor = Color(0xFF1E293B);
  static const Color _accentBlue = Color(0xFF38BDF8);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _bgSelector = Color(0xFF0F172A);

  Future<List<Map<String, double>>> _loadHistoricalTelemetry() async {
    const dbPath = '/data/helios_history.db';
    final file = File(dbPath);

    if (!file.existsSync()) {
      return List.generate(50, (index) {
        final double x = index.toDouble();
        final double pExp = 4500 + 400 * math.sin(x / 5);
        final double pReal = pExp * (0.88 + 0.1 * math.cos(x / 3));
        return {'p_real': pReal, 'p_exp': pExp};
      });
    }

    try {
      final db = sql.sqlite3.open(dbPath);
      final sql.ResultSet results = db.select(
        'SELECT timestamp, p_real, p_exp FROM telemetry_log ORDER BY timestamp DESC LIMIT 50;',
      );

      final List<Map<String, double>> loaded = [];
      for (final sql.Row row in results) {
        loaded.add({
          'p_real': (row['p_real'] as num?)?.toDouble() ?? 0.0,
          'p_exp': (row['p_exp'] as num?)?.toDouble() ?? 0.0,
        });
      }
      db.close();
      return loaded.reversed.toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Analítica de Rendimiento',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: _bgSelector,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    _buildTabButton(0, 'En Vivo'),
                    _buildTabButton(1, 'Histórico SCADA'),
                    _buildTabButton(2, 'Proyección Salud'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(height: 280, child: _buildSelectedChart()),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label) {
    final bool isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? _cardColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected
              ? Border.all(color: _accentBlue.withValues(alpha: 0.5))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? _accentBlue : _textMuted,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedChart() {
    switch (_selectedTab) {
      case 0:
        return _buildLiveChart();
      case 1:
        return _buildHistoricalChart();
      case 2:
        return _buildHealthProjectionChart();
      default:
        return _buildLiveChart();
    }
  }

  Widget _buildLiveChart() {
    final double peak = (widget.expPower != null && widget.expPower! > 500.0)
        ? widget.expPower!
        : 5000.0;
    final List<FlSpot> expectedSpots = [];

    for (double h = 6; h <= 18; h += 0.5) {
      double eff = math.max(0.0, math.sin(math.pi * (h - 6) / 12));
      expectedSpots.add(FlSpot(h, peak * eff));
    }

    final double nowHour = DateTime.now().hour + (DateTime.now().minute / 60.0);
    final bool hasValidRealPoint =
        widget.realPower != null && nowHour >= 6 && nowHour <= 18;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: _buildDefaultTitlesData(),
        borderData: FlBorderData(show: false),
        minX: 6,
        maxX: 18,
        minY: 0,
        maxY: peak * 1.15,
        lineBarsData: [
          LineChartBarData(
            spots: expectedSpots,
            isCurved: true,
            color: _accentBlue,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: _accentBlue.withValues(alpha: 0.12),
            ),
          ),
          if (hasValidRealPoint)
            LineChartBarData(
              spots: [FlSpot(nowHour, widget.realPower!)],
              isCurved: false,
              color: Colors.amberAccent,
              barWidth: 0,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 6,
                    color: Colors.amberAccent,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoricalChart() {
    return FutureBuilder<List<Map<String, double>>>(
      future: _loadHistoricalTelemetry(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: _accentBlue,
              strokeWidth: 2,
            ),
          );
        }

        final data = snapshot.data ?? [];
        if (data.isEmpty) {
          return const Center(
            child: Text(
              'Sin registros históricos en telemetry_log',
              style: TextStyle(color: _textMuted, fontSize: 13),
            ),
          );
        }

        final List<FlSpot> realSpots = [];
        final List<FlSpot> expSpots = [];

        for (int i = 0; i < data.length; i++) {
          realSpots.add(FlSpot(i.toDouble(), data[i]['p_real']!));
          expSpots.add(FlSpot(i.toDouble(), data[i]['p_exp']!));
        }

        return LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(
                color: Colors.white.withValues(alpha: 0.05),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: 10,
                  getTitlesWidget: (val, _) => Text(
                    'T-${50 - val.toInt()}',
                    style: const TextStyle(color: _textMuted, fontSize: 10),
                  ),
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: (data.length - 1).toDouble(),
            lineBarsData: [
              LineChartBarData(
                spots: expSpots,
                isCurved: true,
                color: _textMuted.withValues(alpha: 0.6),
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
              LineChartBarData(
                spots: realSpots,
                isCurved: true,
                color: _accentBlue,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: _accentBlue.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHealthProjectionChart() {
    return FutureBuilder<List<Map<String, double>>>(
      future: _loadHistoricalTelemetry(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: _accentBlue,
              strokeWidth: 2,
            ),
          );
        }

        final data = snapshot.data ?? [];
        if (data.isEmpty) {
          return const Center(
            child: Text(
              'No hay suficientes muestras para calcular el PR',
              style: TextStyle(color: _textMuted, fontSize: 13),
            ),
          );
        }

        final List<FlSpot> prSpots = [];
        for (int i = 0; i < data.length; i++) {
          final pExp = data[i]['p_exp']!;
          final pReal = data[i]['p_real']!;
          double pr = pExp > 0 ? (pReal / pExp) : 1.0;
          pr = pr.clamp(0.0, 1.2);
          prSpots.add(FlSpot(i.toDouble(), pr * 100));
        }

        return LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (val) {
                if (val == 85.0) {
                  return const FlLine(
                    color: Colors.amberAccent,
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  );
                }
                return FlLine(
                  color: Colors.white.withValues(alpha: 0.05),
                  strokeWidth: 1,
                );
              },
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  interval: 20,
                  getTitlesWidget: (val, _) => Text(
                    '${val.toInt()}%',
                    style: const TextStyle(color: _textMuted, fontSize: 10),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: 10,
                  getTitlesWidget: (val, _) => Text(
                    'P-${val.toInt()}',
                    style: const TextStyle(color: _textMuted, fontSize: 10),
                  ),
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: (data.length - 1).toDouble(),
            minY: 40,
            maxY: 110,
            lineBarsData: [
              LineChartBarData(
                spots: prSpots,
                isCurved: true,
                color: const Color(0xFF10B981),
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: Colors.greenAccent.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  FlTitlesData _buildDefaultTitlesData() {
    return FlTitlesData(
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          interval: 3,
          getTitlesWidget: (value, meta) {
            if (value == 6 ||
                value == 9 ||
                value == 12 ||
                value == 15 ||
                value == 18) {
              return Text(
                '${value.toInt()}:00',
                style: const TextStyle(color: _textMuted, fontSize: 12),
              );
            }
            return const Text('');
          },
        ),
      ),
    );
  }
}
