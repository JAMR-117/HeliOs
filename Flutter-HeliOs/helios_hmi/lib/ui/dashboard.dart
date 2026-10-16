import 'dart:io';
import 'dart:convert';
import 'dart:async';

import 'package:sqlite3/common.dart' as sql;
import 'package:helios_hmi/database/db_platform.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../services/mqtt_service.dart';
import 'scada_errors_screen.dart';
import 'plant_config_screen.dart';

// ===========================================================
// MODO DE TEMA: Automático / Forzar Día / Forzar Noche
// ===========================================================
enum DashboardThemeMode { auto, forceDay, forceNight }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<dynamic> _forecastData = [];
  Timer? _refreshTimer;
  DashboardThemeMode _themeMode = DashboardThemeMode.auto;

  @override
  void initState() {
    super.initState();
    _loadForecast();
    // Inicia con reintento rápido (10s) para evadir la carrera de arranque
    _startForecastTimer(const Duration(seconds: 10));
  }

  void _startForecastTimer(Duration interval) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(interval, (_) async {
      await _loadForecast();
      // Una vez cargado el pronóstico, cambia al intervalo largo de 5 minutos
      if (_forecastData.isNotEmpty) {
        _startForecastTimer(const Duration(minutes: 5));
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Lectura del archivo JSON de 10 días generado por el Modelo Astronómico en la Raspberry Pi
  Future<void> _loadForecast() async {
    try {
      final file = File('/data/forecast.json');
      if (file.existsSync()) {
        final content = await file.readAsString();
        final List<dynamic> all = json.decode(content);

        // Filtrar: mostrar solo desde la hora actual (con margen de 59 min atrás)
        final threshold = DateTime.now().subtract(const Duration(minutes: 59));
        final filtered = all.where((item) {
          try {
            final t = DateTime.parse(item['hora'] as String);
            return t.isAfter(threshold);
          } catch (_) {
            return false;
          }
        }).toList();

        setState(() {
          _forecastData = filtered;
        });
      }
    } catch (e) {
      debugPrint("Error leyendo pronóstico: $e");
    }
  }

  void _showThemeMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Modo de Tema',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _themeOption(
              icon: Icons.brightness_auto,
              label: 'Automático (según irradiancia)',
              value: DashboardThemeMode.auto,
            ),
            _themeOption(
              icon: Icons.wb_sunny,
              label: 'Forzar Día',
              value: DashboardThemeMode.forceDay,
            ),
            _themeOption(
              icon: Icons.nightlight_round,
              label: 'Forzar Noche',
              value: DashboardThemeMode.forceNight,
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeOption({
    required IconData icon,
    required String label,
    required DashboardThemeMode value,
  }) {
    final bool selected = _themeMode == value;
    return ListTile(
      leading: Icon(icon, color: selected ? const Color(0xFF38BDF8) : Colors.white54),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? const Color(0xFF38BDF8) : Colors.white70,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: selected ? const Icon(Icons.check, color: Color(0xFF38BDF8)) : null,
      onTap: () {
        setState(() => _themeMode = value);
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mqttService = context.watch<MqttService>();

    final telemetry = mqttService.telemetryData;
    final spa = mqttService.spaData;
    final scada = mqttService.scadaData;

    final double? realPower   = (telemetry['power_w'] as num?)?.toDouble();
    final double? realVoltage = (telemetry['v_dc']    as num?)?.toDouble();
    final double? realCurrent = (telemetry['i_dc']    as num?)?.toDouble();
    final double? yieldKwh    = (telemetry['yield_kwh'] as num?)?.toDouble();
    final double? tempC       = (telemetry['temp_c']  as num?)?.toDouble();

    final double? expPower   = (spa['p_exp']     as num?)?.toDouble();
    final double? expVoltage = (spa['v_exp']     as num?)?.toDouble();
    final double? expCurrent = (spa['i_exp']     as num?)?.toDouble();
    final double? ghi        = (spa['ghi']       as num?)?.toDouble();
    final double? motorAz    = (spa['motor_azimuth']   as num?)?.toDouble() ??
        (spa['azimuth'] as num?)?.toDouble();
    final double? motorEl    = (spa['motor_elevation'] as num?)?.toDouble() ??
        (spa['elevation'] as num?)?.toDouble();

    // is_night desde el payload SPA; si aún no hay datos, asume noche
    final bool isNightFromSpa = spa['is_night'] as bool? ?? true;

    // Aplicar override de tema
    final bool isNight = switch (_themeMode) {
      DashboardThemeMode.forceDay   => false,
      DashboardThemeMode.forceNight => true,
      DashboardThemeMode.auto       => isNightFromSpa,
    };

    final int scadaCode    = (scada['code']        as num?)?.toInt() ?? 0;
    final String scadaDesc = scada['description']  as String? ?? 'Operación Normal';

    final bool isWaitingData = telemetry.isEmpty && spa.isEmpty;
    bool hasError     = false;
    String alertMessage = "OPERACIÓN NORMAL";

    if (isWaitingData) {
      alertMessage = "ESPERANDO TELEMETRÍA...";
    } else if (scadaCode != 0) {
      hasError     = true;
      alertMessage = "FALLA SCADA ($scadaCode): ${scadaDesc.toUpperCase()}";
    } else if (isNightFromSpa) {
      // Modo nocturno real (sin falsas alarmas)
      alertMessage = "MODO NOCTURNO - ESTIBA ACTIVA";
    } else if (realVoltage != null &&
        expVoltage != null &&
        expVoltage > 0 &&
        realVoltage < expVoltage * 0.90) {
      hasError     = true;
      alertMessage = "ALERTA: PÉRDIDA DE PANEL EN SERIE";
    } else if (realPower != null &&
        expPower != null &&
        expPower > 0 &&
        realPower < expPower * 0.85) {
      hasError     = true;
      alertMessage = "ALERTA: SOMBREO O SUCIEDAD";
    }

    // -------------------------------------------------------
    // PALETA DINÁMICA: Día (Claro) vs Noche (Oscuro)
    // -------------------------------------------------------
    final Color bgColor;
    final Color cardColor;
    final Color headerColor;
    final Color textPrimary;
    final Color textMuted;
    final Color accentBlue = const Color(0xFF38BDF8);

    if (isNight) {
      // Modo Oscuro (Estiba Nocturna)
      bgColor     = const Color(0xFF131B2A);
      cardColor   = const Color(0xFF1E293B);
      headerColor = const Color(0xFF114238);
      textPrimary = Colors.white;
      textMuted   = const Color(0xFF94A3B8);
    } else {
      // Modo Claro (Operación Diurna)
      bgColor     = const Color(0xFFF1F5F9);
      cardColor   = Colors.white;
      headerColor = const Color(0xFF166534);
      textPrimary = const Color(0xFF0F172A);
      textMuted   = const Color(0xFF475569);
    }

    final Color statusColor = hasError
        ? (scadaCode != 0 || (realVoltage != null && expVoltage != null && realVoltage < expVoltage * 0.90)
            ? Colors.red.shade900.withValues(alpha: 0.4)
            : Colors.amber.shade900.withValues(alpha: 0.4))
        : isNightFromSpa
            ? const Color(0xFF1E3A5F).withValues(alpha: 0.6)
            : cardColor;
    final Color statusBorderColor = hasError
        ? (scadaCode != 0 || (realVoltage != null && expVoltage != null && realVoltage < expVoltage * 0.90)
            ? Colors.redAccent
            : Colors.amberAccent)
        : isNightFromSpa
            ? Colors.blueAccent.withValues(alpha: 0.5)
            : Colors.transparent;

    // Motor display values
    final String motorAzStr = motorAz != null ? motorAz.toStringAsFixed(1) : '--';
    final String motorElStr = motorEl != null ? motorEl.toStringAsFixed(1) : '--';
    final String motorSubtitle = isNightFromSpa
        ? 'Modo Estiba Plana (Seguridad)'
        : 'Seguimiento Solar Óptimo';

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isNight ? Colors.white : const Color(0xFF0F172A), size: 28),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
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
                  const SizedBox(width: 10),
                ],
                if (yieldKwh != null) ...[
                  Icon(Icons.bolt, color: textMuted, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    '${yieldKwh.toStringAsFixed(1)} kWh',
                    style: TextStyle(color: textMuted, fontSize: 13),
                  ),
                  const SizedBox(width: 10),
                ],
                // Botón de tema Sol/Luna
                IconButton(
                  icon: Icon(
                    _themeMode == DashboardThemeMode.forceDay
                        ? Icons.wb_sunny
                        : _themeMode == DashboardThemeMode.forceNight
                            ? Icons.nightlight_round
                            : Icons.brightness_auto,
                    color: _themeMode == DashboardThemeMode.forceDay
                        ? Colors.amberAccent
                        : _themeMode == DashboardThemeMode.forceNight
                            ? Colors.indigoAccent
                            : accentBlue,
                  ),
                  tooltip: 'Modo de tema',
                  onPressed: () => _showThemeMenu(context),
                ),
                Icon(
                  mqttService.isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: mqttService.isConnected ? Colors.greenAccent : Colors.redAccent,
                  size: 24,
                ),
                const SizedBox(width: 12),
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
            DrawerHeader(
              decoration: BoxDecoration(color: bgColor),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.solar_power, size: 48, color: accentBlue),
                  const SizedBox(height: 12),
                  Text(
                    'HeliOs OS',
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.dashboard, color: accentBlue),
              title: Text(
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
              leading: Icon(Icons.warning_amber_rounded, color: textMuted),
              title: Text('Menú de Errores SCADA', style: TextStyle(color: textMuted)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ScadaErrorsScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.settings, color: textMuted),
              title: Text('Configuración de Planta', style: TextStyle(color: textMuted)),
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
              // --- HEADER ---
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: headerColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isNight ? Icons.nightlight_round : Icons.landscape,
                      size: 48,
                      color: isNight ? Colors.indigoAccent : Colors.greenAccent,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'SISTEMA DE MONITOREO HELIOS',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Pronóstico de Irradiancia y Generación por Hora',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Modelo Astronómico Clear Sky',
                style: TextStyle(color: textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),

              // --- SECCIÓN 1: CARRUSEL DINÁMICO (desde hora actual) ---
              Container(
                height: 125,
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isNight
                      ? []
                      : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
                ),
                child: _forecastData.isEmpty
                    ? Center(
                        child: Text(
                          "Sincronizando efemérides solares...",
                          style: TextStyle(color: textMuted),
                        ),
                      )
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _forecastData.length,
                        itemBuilder: (context, index) {
                          final item  = _forecastData[index];
                          final time  = DateTime.parse(item['hora']).toLocal();
                          final double fGhi     = (item['ghi']   as num).toDouble();
                          final double pExpFore = (item['p_exp'] as num).toDouble();
                          final bool   isDay    = fGhi > 0;

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 12.0,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "${time.hour.toString().padLeft(2, '0')}:00",
                                  style: TextStyle(color: textMuted, fontSize: 12),
                                ),
                                Icon(
                                  isDay ? Icons.wb_sunny : Icons.nightlight_round,
                                  color: isDay ? Colors.amberAccent : Colors.indigoAccent,
                                  size: 28,
                                ),
                                Text(
                                  '${fGhi.round()} W/m²',
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Est: ${pExpFore.round()} W',
                                  style: TextStyle(color: accentBlue, fontSize: 11),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 24),
              Text(
                'Condiciones actuales',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // --- SECCIÓN 2: GRIDVIEW ---
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
                    realValue: realPower != null ? '${realPower.round()} W' : '-- W',
                    expValue: expPower != null ? '${expPower.round()} W' : '-- W',
                    icon: Icons.bolt,
                    cardColor: cardColor,
                    mutedColor: textMuted,
                    primaryColor: textPrimary,
                    accentColor: accentBlue,
                  ),
                  _buildMetricCard(
                    title: 'Voltaje DC',
                    realValue: realVoltage != null ? '${realVoltage.toStringAsFixed(1)} V' : '-- V',
                    expValue: expVoltage != null ? '${expVoltage.toStringAsFixed(1)} V' : '-- V',
                    icon: Icons.battery_charging_full,
                    cardColor: cardColor,
                    mutedColor: textMuted,
                    primaryColor: textPrimary,
                    accentColor: accentBlue,
                  ),
                  _buildMetricCard(
                    title: 'Corriente DC',
                    realValue: realCurrent != null ? '${realCurrent.toStringAsFixed(1)} A' : '-- A',
                    expValue: expCurrent != null ? '${expCurrent.toStringAsFixed(1)} A' : '-- A',
                    icon: Icons.electric_meter,
                    cardColor: cardColor,
                    mutedColor: textMuted,
                    primaryColor: textPrimary,
                    accentColor: accentBlue,
                  ),
                  // Irradiancia GHI
                  _buildMetricCard(
                    title: 'Irradiancia (GHI)',
                    realValue: ghi != null ? '${ghi.round()} W/m²' : '-- W/m²',
                    expValue: 'Modelo Clear Sky',
                    icon: Icons.wb_twilight,
                    cardColor: cardColor,
                    mutedColor: textMuted,
                    primaryColor: textPrimary,
                    accentColor: Colors.amberAccent,
                    isComparison: false,
                  ),

                  // --- TARJETA FUSIONADA: Ángulo Óptimo (Motores) ---
                  _buildMetricCard(
                    title: 'Ángulo Óptimo (Motores)',
                    realValue: 'Az: $motorAzStr° | El: $motorElStr°',
                    expValue: motorSubtitle,
                    icon: Icons.solar_power,
                    cardColor: cardColor,
                    mutedColor: textMuted,
                    primaryColor: textPrimary,
                    accentColor: isNightFromSpa ? Colors.indigoAccent : Colors.tealAccent,
                    isComparison: false,
                    valueFontSize: 18,
                  ),

                  // --- TARJETA CLICKEABLE: Estado del Sistema ---
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ScadaErrorsScreen()),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: statusBorderColor,
                          width: hasError || isNightFromSpa ? 2 : 0,
                        ),
                        boxShadow: isNight
                            ? []
                            : [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)],
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            hasError
                                ? Icons.warning_amber_rounded
                                : isNightFromSpa
                                    ? Icons.bedtime
                                    : (isWaitingData
                                        ? Icons.hourglass_empty
                                        : Icons.check_circle_outline),
                            color: hasError
                                ? (statusBorderColor == Colors.redAccent
                                    ? Colors.redAccent
                                    : Colors.amberAccent)
                                : isNightFromSpa
                                    ? Colors.indigoAccent
                                    : (isWaitingData ? textMuted : Colors.greenAccent),
                            size: 34,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Estado del Sistema',
                            style: TextStyle(color: textMuted, fontSize: 11),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            alertMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isWaitingData ? textMuted : textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Ver detalles SCADA',
                                style: TextStyle(color: accentBlue, fontSize: 10),
                              ),
                              Icon(Icons.arrow_forward_ios, color: accentBlue, size: 10),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              MultimodalChartContainer(
                expPower: expPower,
                realPower: realPower,
                cardColor: cardColor,
                textMuted: textMuted,
                textPrimary: textPrimary,
                accentBlue: accentBlue,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String realValue,
    required String expValue,
    required IconData icon,
    required Color cardColor,
    required Color mutedColor,
    required Color primaryColor,
    required Color accentColor,
    bool isComparison = true,
    double valueFontSize = 24,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    color: mutedColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
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
                style: TextStyle(
                  color: primaryColor,
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isComparison ? 'Esperado: $expValue' : expValue,
                style: TextStyle(
                  color: mutedColor,
                  fontSize: 11,
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

// ===========================================================
// GRÁFICO HISTÓRICO SCADA
// ===========================================================
class MultimodalChartContainer extends StatefulWidget {
  final double? expPower;
  final double? realPower;
  final Color cardColor;
  final Color textMuted;
  final Color textPrimary;
  final Color accentBlue;

  const MultimodalChartContainer({
    super.key,
    required this.expPower,
    required this.realPower,
    required this.cardColor,
    required this.textMuted,
    required this.textPrimary,
    required this.accentBlue,
  });

  @override
  State<MultimodalChartContainer> createState() =>
      _MultimodalChartContainerState();
}

class _MultimodalChartContainerState extends State<MultimodalChartContainer> {
  Timer? _historyTimer;
  // Clave que cambia cada 15s para forzar el rebuild del FutureBuilder
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    // Auto-refresco del histórico SCADA cada 15 segundos
    _historyTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _refreshKey++);
    });
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    super.dispose();
  }

  Future<List<Map<String, double>>> _loadHistoricalTelemetry() async {
    const dbPath = '/data/helios_history.db';
    sql.CommonDatabase? db;
    try {
      db = await openAppDatabase(dbPath);
      if (db == null) return [];

      final sql.ResultSet results = db.select(
        'SELECT timestamp, p_real, p_exp FROM telemetry_log ORDER BY timestamp DESC LIMIT 50;',
      );
      final List<Map<String, double>> loaded = [];
      for (final sql.Row row in results) {
        loaded.add({
          'p_real': (row['p_real'] as num?)?.toDouble() ?? 0.0,
          'p_exp':  (row['p_exp']  as num?)?.toDouble() ?? 0.0,
        });
      }
      return loaded.reversed.toList();
    } catch (_) {
      return [];
    } finally {
      db?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Histórico SCADA — Potencia Esperada vs Real',
            style: TextStyle(
              color: widget.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(height: 280, child: _buildHistoricalChart()),
        ],
      ),
    );
  }

  Widget _buildHistoricalChart() {
    return FutureBuilder<List<Map<String, double>>>(
      key: ValueKey(_refreshKey),
      future: _loadHistoricalTelemetry(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: widget.accentBlue,
              strokeWidth: 2,
            ),
          );
        }
        final data = snapshot.data ?? [];
        if (data.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hourglass_empty, color: widget.textMuted, size: 36),
                const SizedBox(height: 12),
                Text(
                  'Esperando registros históricos en base de datos...',
                  style: TextStyle(color: widget.textMuted, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        final List<FlSpot> realSpots = [];
        final List<FlSpot> expSpots  = [];
        for (int i = 0; i < data.length; i++) {
          realSpots.add(FlSpot(i.toDouble(), data[i]['p_real']!));
          expSpots.add(FlSpot(i.toDouble(),  data[i]['p_exp']!));
        }
        return LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(
                color: Colors.grey.withValues(alpha: 0.12),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              topTitles:    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: 10,
                  getTitlesWidget: (val, _) => Text(
                    'T-${50 - val.toInt()}',
                    style: TextStyle(color: widget.textMuted, fontSize: 10),
                  ),
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: (data.length - 1).toDouble(),
            lineBarsData: [
              // Curva Potencia Esperada (Modelo Astronómico)
              LineChartBarData(
                spots: expSpots,
                isCurved: true,
                color: widget.textMuted.withValues(alpha: 0.6),
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
              // Curva Potencia Real (inversor)
              LineChartBarData(
                spots: realSpots,
                isCurved: true,
                color: widget.accentBlue,
                barWidth: 2.5,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: widget.accentBlue.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
