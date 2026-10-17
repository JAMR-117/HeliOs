import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../services/mqtt_service.dart';
import '../theme/helios_theme.dart';
import '../database/db_platform.dart';
import 'scada_errors_screen.dart';
import 'plant_config_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<dynamic> _forecastData = [];
  Timer? _refreshTimer;
  Timer? _clockTimer;
  String _currentTimeStr = '--:--:--';

  @override
  void initState() {
    super.initState();
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());

    _loadForecast();
    _startForecastTimer(const Duration(seconds: 10));
  }

  void _updateClock() {
    final nowUtc6 = DateTime.now().toUtc().subtract(const Duration(hours: 6));
    final h = nowUtc6.hour.toString().padLeft(2, '0');
    final m = nowUtc6.minute.toString().padLeft(2, '0');
    final s = nowUtc6.second.toString().padLeft(2, '0');
    if (mounted) {
      setState(() {
        _currentTimeStr = '$h:$m:$s';
      });
    }
  }

  void _startForecastTimer(Duration interval) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(interval, (_) async {
      await _loadForecast();
      if (_forecastData.isNotEmpty) {
        _startForecastTimer(const Duration(minutes: 5));
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadForecast() async {
    try {
      final content = readConfigFile('/data/forecast.json');
      if (content == null) return;
      final List<dynamic> all = json.decode(content);

      final int nowEpoch =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final int threshold = nowEpoch - 59 * 60;

      final filtered = all.where((item) {
        final epoch = item['timestamp_epoch'] as int?;
        if (epoch != null) return epoch >= threshold;
        try {
          final t = DateTime.parse(item['hora'] as String);
          return t.millisecondsSinceEpoch ~/ 1000 >= threshold;
        } catch (_) {
          return false;
        }
      }).toList();

      if (!mounted) return;
      setState(() => _forecastData = filtered);
    } catch (e) {
      debugPrint("Error leyendo pronóstico: $e");
    }
  }

  void _showThemeMenu(BuildContext context, MqttService mqttService, bool isNight) {
    final Color sheetBg = isNight ? HeliosTheme.blueFantastic : HeliosTheme.palladian;
    final Color titleColor = isNight ? HeliosTheme.palladian : HeliosTheme.abyssalAnchorfishBlue;

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Modo de Tema',
              style: TextStyle(
                color: titleColor,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _themeOption(
              icon: Icons.brightness_auto,
              label: 'Automático (según efemérides solares)',
              value: DashboardThemeMode.auto,
              currentMode: mqttService.themeMode,
              isNight: isNight,
              onSelect: (m) => mqttService.setThemeMode(m),
            ),
            _themeOption(
              icon: Icons.wb_sunny,
              label: 'Forzar Día',
              value: DashboardThemeMode.forceDay,
              currentMode: mqttService.themeMode,
              isNight: isNight,
              onSelect: (m) => mqttService.setThemeMode(m),
            ),
            _themeOption(
              icon: Icons.nightlight_round,
              label: 'Forzar Noche',
              value: DashboardThemeMode.forceNight,
              currentMode: mqttService.themeMode,
              isNight: isNight,
              onSelect: (m) => mqttService.setThemeMode(m),
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
    required DashboardThemeMode currentMode,
    required bool isNight,
    required ValueChanged<DashboardThemeMode> onSelect,
  }) {
    final bool selected = currentMode == value;
    final Color activeColor = HeliosTheme.burningFlame;
    final Color inactiveColor =
        isNight ? HeliosTheme.oatmeal : HeliosTheme.blueFantastic;

    return ListTile(
      leading: Icon(
        icon,
        color: selected ? activeColor : inactiveColor.withValues(alpha: 0.6),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? activeColor : inactiveColor,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: selected ? Icon(Icons.check, color: activeColor) : null,
      onTap: () {
        onSelect(value);
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

    final double? realPower   = (telemetry['power_w']   as num?)?.toDouble();
    final double? realVoltage = (telemetry['v_dc']       as num?)?.toDouble();
    final double? realCurrent = (telemetry['i_dc']       as num?)?.toDouble();
    final double? yieldKwh    = (telemetry['yield_kwh']  as num?)?.toDouble();
    final double? tempC       = (telemetry['temp_c']     as num?)?.toDouble();

    final double? expPower   = (spa['p_exp']            as num?)?.toDouble();
    final double? expVoltage = (spa['v_exp']            as num?)?.toDouble();
    final double? expCurrent = (spa['i_exp']            as num?)?.toDouble();
    final double? ghi        = (spa['ghi']              as num?)?.toDouble();
    final double? motorAz    = (spa['motor_azimuth']    as num?)?.toDouble() ??
        (spa['azimuth']   as num?)?.toDouble();
    final double? motorEl    = (spa['motor_elevation']  as num?)?.toDouble() ??
        (spa['elevation'] as num?)?.toDouble();

    // Estado centralizado de tema (Día vs Noche)
    final bool isNight = mqttService.isNight;

    final int scadaCode = (scada['code'] as num?)?.toInt() ?? 0;
    final String scadaDesc = scada['description'] as String? ?? 'Operación Normal';

    // --- Lógica de Alertas y Estado del Sistema ---
    bool hasError = false;
    String alertMessage = "OPERACIÓN NORMAL";
    IconData statusIcon;
    Color statusIconColor;

    if (scadaCode != 0) {
      hasError = true;
      alertMessage = "FALLA SCADA ($scadaCode): ${scadaDesc.toUpperCase()}";
    } else if (!isNight &&
        realVoltage != null &&
        expVoltage != null &&
        expVoltage > 0 &&
        realVoltage < expVoltage * 0.90) {
      hasError = true;
      alertMessage = "ALERTA: PÉRDIDA DE PANEL EN SERIE";
    } else if (!isNight &&
        realPower != null &&
        expPower != null &&
        expPower > 0 &&
        realPower < expPower * 0.85) {
      hasError = true;
      alertMessage = "ALERTA: SOMBREO O SUCIEDAD";
    } else if (isNight) {
      alertMessage = "MODO NOCTURNO - PANELES EN ESTIBA";
    } else if (telemetry.isNotEmpty) {
      alertMessage = "OPERACIÓN NORMAL";
    } else if (spa.isNotEmpty) {
      alertMessage = "MONITOREO SOLAR ACTIVO - ESPERANDO INVERSOR";
    } else {
      alertMessage = "ESPERANDO TELEMETRÍA...";
    }

    // --- Sincronización explícita del ícono según Tarea 4 ---
    if (hasError) {
      statusIcon = Icons.warning_amber_rounded;
      statusIconColor = HeliosTheme.truffleTrouble;
    } else if (isNight) {
      statusIcon = Icons.nightlight_round;
      statusIconColor = HeliosTheme.burningFlame;
    } else {
      if (telemetry.isNotEmpty) {
        statusIcon = Icons.check_circle_outline;
        statusIconColor = const Color(0xFF10B981); // Verde esmeralda
      } else if (spa.isNotEmpty) {
        statusIcon = Icons.wb_sunny_outlined;
        statusIconColor = const Color(0xFF0284C7); // Azul cielo
      } else {
        statusIcon = Icons.hourglass_empty;
        statusIconColor = isNight ? HeliosTheme.oatmeal : HeliosTheme.blueFantastic;
      }
    }

    // ---------------------------------------------------------
    // PALETA DINÁMICA OFICIAL HELIOS: Día vs Noche
    // ---------------------------------------------------------
    final Color cardColor;
    final Color cardBorderColor;
    final Color textPrimary;
    final Color textMuted;
    final Color accentSolar = HeliosTheme.burningFlame;
    final Color accentWarm = HeliosTheme.truffleTrouble;
    final Gradient bgGradient;
    final Gradient headerGradient;

    if (isNight) {
      cardColor       = HeliosTheme.blueFantastic;
      cardBorderColor = HeliosTheme.oatmeal.withValues(alpha: 0.18);
      textPrimary     = HeliosTheme.palladian;
      textMuted       = HeliosTheme.oatmeal;
      bgGradient      = HeliosTheme.nightBackgroundGradient;
      headerGradient  = HeliosTheme.nightHeaderGradient;
    } else {
      cardColor       = const Color(0xFFFAF7F2);
      cardBorderColor = HeliosTheme.oatmeal.withValues(alpha: 0.5);
      textPrimary     = HeliosTheme.abyssalAnchorfishBlue;
      textMuted       = HeliosTheme.blueFantastic.withValues(alpha: 0.75);
      bgGradient      = HeliosTheme.dayBackgroundGradient;
      headerGradient  = HeliosTheme.dayHeaderGradient;
    }

    final Color statusColor = hasError
        ? HeliosTheme.truffleTrouble.withValues(alpha: isNight ? 0.35 : 0.15)
        : isNight
            ? HeliosTheme.blueFantastic.withValues(alpha: 0.7)
            : cardColor;

    final Color statusBorderColor = hasError
        ? HeliosTheme.truffleTrouble
        : isNight
            ? HeliosTheme.burningFlame.withValues(alpha: 0.6)
            : cardBorderColor;

    final String motorAzStr = motorAz != null ? motorAz.toStringAsFixed(1) : '--';
    final String motorElStr = motorEl != null ? motorEl.toStringAsFixed(1) : '--';
    final String motorSubtitle = isNight
        ? 'Posición de Estiba Plana (Seguridad)'
        : 'Óptimo Solar Calculado';

    return Container(
      decoration: BoxDecoration(
        gradient: bgGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(
            color: textPrimary,
            size: 28,
          ),
          // Reloj centrado provisional para supervisión y sincronización
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.access_time, color: textPrimary, size: 20),
              const SizedBox(width: 6),
              Text(
                _currentTimeStr,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Row(
                children: [
                  if (tempC != null) ...[
                    Icon(
                      Icons.thermostat,
                      color: tempC > 65 ? HeliosTheme.truffleTrouble : textMuted,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${tempC.toStringAsFixed(1)}°C',
                      style: TextStyle(
                        color: tempC > 65 ? HeliosTheme.truffleTrouble : textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (yieldKwh != null) ...[
                    Icon(Icons.bolt, color: accentSolar, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '${yieldKwh.toStringAsFixed(2)} kWh',
                      style: TextStyle(
                        color: textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  // Botón Selector de Modo de Tema
                  IconButton(
                    icon: Icon(
                      mqttService.themeMode == DashboardThemeMode.forceDay
                          ? Icons.wb_sunny
                          : mqttService.themeMode == DashboardThemeMode.forceNight
                              ? Icons.nightlight_round
                              : Icons.brightness_auto,
                      color: mqttService.themeMode == DashboardThemeMode.forceDay
                          ? HeliosTheme.burningFlame
                          : mqttService.themeMode == DashboardThemeMode.forceNight
                              ? HeliosTheme.oatmeal
                              : accentSolar,
                    ),
                    tooltip: 'Modo de tema',
                    onPressed: () => _showThemeMenu(context, mqttService, isNight),
                  ),
                  Icon(
                    mqttService.isConnected
                        ? Icons.cloud_done
                        : Icons.cloud_off,
                    color: mqttService.isConnected
                        ? const Color(0xFF4ADE80)
                        : HeliosTheme.truffleTrouble,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ],
        ),
        drawer: Drawer(
          backgroundColor: isNight ? HeliosTheme.abyssalAnchorfishBlue : HeliosTheme.palladian,
          child: Container(
            decoration: BoxDecoration(
              gradient: bgGradient,
            ),
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    gradient: headerGradient,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Icon(
                        isNight ? Icons.nightlight_round : Icons.solar_power,
                        size: 44,
                        color: isNight ? HeliosTheme.burningFlame : HeliosTheme.palladian,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'HeliOs OS',
                        style: TextStyle(
                          color: isNight ? HeliosTheme.palladian : Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.dashboard, color: HeliosTheme.burningFlame),
                  title: const Text(
                    'Monitoreo Principal',
                    style: TextStyle(
                      color: HeliosTheme.burningFlame,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  selected: true,
                  selectedTileColor: HeliosTheme.burningFlame.withValues(alpha: 0.15),
                  onTap: () => Navigator.pop(context),
                ),
                ListTile(
                  leading: Icon(Icons.warning_amber_rounded, color: textMuted),
                  title: Text(
                    'Menú de Errores SCADA',
                    style: TextStyle(color: textPrimary),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ScadaErrorsScreen()),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.settings, color: textMuted),
                  title: Text(
                    'Configuración de Planta',
                    style: TextStyle(color: textPrimary),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PlantConfigScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                // --- HEADER BANNER ---
                Container(
                  height: 120,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: headerGradient,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isNight
                          ? HeliosTheme.burningFlame.withValues(alpha: 0.3)
                          : HeliosTheme.oatmeal.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isNight
                            ? Colors.black.withValues(alpha: 0.3)
                            : HeliosTheme.truffleTrouble.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isNight ? Icons.nightlight_round : Icons.solar_power,
                        size: 44,
                        color: isNight
                            ? HeliosTheme.burningFlame
                            : HeliosTheme.palladian,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'SISTEMA DE MONITOREO HELIOS',
                        style: TextStyle(
                          color: isNight ? HeliosTheme.palladian : Colors.white,
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

                // --- CARRUSEL DE PRONÓSTICO ---
                Container(
                  height: 128,
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cardBorderColor, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: isNight
                            ? Colors.black.withValues(alpha: 0.25)
                            : HeliosTheme.blueFantastic.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
                    ],
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
                            final item = _forecastData[index];
                            final double fGhi =
                                (item['ghi'] as num).toDouble();
                            final double pExpFore =
                                (item['p_exp'] as num).toDouble();
                            final bool isDay = fGhi > 0;

                            final String horaStr =
                                item['hora_str'] as String? ?? '??:00';
                            final String fechaStr =
                                item['fecha_str'] as String? ?? '';

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14.0,
                                vertical: 10.0,
                              ),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  Text(
                                    horaStr,
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (fechaStr.isNotEmpty)
                                    Text(
                                      fechaStr,
                                      style: TextStyle(
                                        color: textMuted,
                                        fontSize: 10,
                                      ),
                                    ),
                                  Icon(
                                    isDay
                                        ? Icons.wb_sunny
                                        : Icons.nightlight_round,
                                    color: isDay
                                        ? HeliosTheme.burningFlame
                                        : (isNight ? HeliosTheme.oatmeal : HeliosTheme.blueFantastic),
                                    size: 26,
                                  ),
                                  Text(
                                    '${fGhi.round()} W/m²',
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Est: ${pExpFore.round()} W',
                                    style: TextStyle(
                                      color: isNight ? HeliosTheme.burningFlame : HeliosTheme.truffleTrouble,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
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

                // --- GRID DE MÉTRICAS ---
                GridView.count(
                  crossAxisCount:
                      MediaQuery.of(context).size.width > 900 ? 4 : 2,
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
                      cardBorderColor: cardBorderColor,
                      mutedColor: textMuted,
                      primaryColor: textPrimary,
                      accentColor: accentSolar,
                      isNight: isNight,
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
                      cardBorderColor: cardBorderColor,
                      mutedColor: textMuted,
                      primaryColor: textPrimary,
                      accentColor: accentSolar,
                      isNight: isNight,
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
                      cardBorderColor: cardBorderColor,
                      mutedColor: textMuted,
                      primaryColor: textPrimary,
                      accentColor: accentSolar,
                      isNight: isNight,
                    ),
                    _buildMetricCard(
                      title: 'Irradiancia (GHI)',
                      realValue:
                          ghi != null ? '${ghi.round()} W/m²' : '-- W/m²',
                      expValue: 'Modelo Clear Sky',
                      icon: Icons.wb_twilight,
                      cardColor: cardColor,
                      cardBorderColor: cardBorderColor,
                      mutedColor: textMuted,
                      primaryColor: textPrimary,
                      accentColor: accentSolar,
                      isComparison: false,
                      isNight: isNight,
                    ),

                    // Tarjeta fusionada: Ángulo Óptimo (Motores)
                    _buildMetricCard(
                      title: 'Ángulo Óptimo (Motores)',
                      realValue: 'Az: $motorAzStr° | El: $motorElStr°',
                      expValue: motorSubtitle,
                      icon: Icons.solar_power,
                      cardColor: cardColor,
                      cardBorderColor: cardBorderColor,
                      mutedColor: textMuted,
                      primaryColor: textPrimary,
                      accentColor: isNight ? accentSolar : accentWarm,
                      isComparison: false,
                      valueFontSize: 16,
                      isNight: isNight,
                    ),

                    // Tarjeta clickeable: Estado del Sistema
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ScadaErrorsScreen()),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: statusBorderColor,
                            width: hasError || isNight ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isNight
                                  ? Colors.black.withValues(alpha: 0.25)
                                  : HeliosTheme.blueFantastic.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              statusIcon,
                              color: statusIconColor,
                              size: 32,
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
                                color: textPrimary,
                                fontSize: 12,
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
                                  'Ver SCADA',
                                  style: TextStyle(
                                      color: accentSolar, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                                Icon(Icons.arrow_forward_ios,
                                    color: accentSolar, size: 10),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // --- NUEVA GRÁFICA EN TIEMPO REAL (TAREA 5) ---
                MultimodalChartContainer(
                  cardColor: cardColor,
                  cardBorderColor: cardBorderColor,
                  textMuted: textMuted,
                  textPrimary: textPrimary,
                  isNight: isNight,
                  forecastData: _forecastData,
                ),
                const SizedBox(height: 40),
              ],
            ),
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
    required Color cardBorderColor,
    required Color mutedColor,
    required Color primaryColor,
    required Color accentColor,
    required bool isNight,
    bool isComparison = true,
    double valueFontSize = 22,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: isNight
                ? Colors.black.withValues(alpha: 0.25)
                : HeliosTheme.blueFantastic.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
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
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
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
// GRÁFICA EN TIEMPO REAL: POTENCIA ESPERADA VS REAL (TAREA 5)
// ===========================================================
class MultimodalChartContainer extends StatelessWidget {
  final Color cardColor;
  final Color cardBorderColor;
  final Color textMuted;
  final Color textPrimary;
  final bool isNight;
  final List<dynamic> forecastData;

  const MultimodalChartContainer({
    super.key,
    required this.cardColor,
    required this.cardBorderColor,
    required this.textMuted,
    required this.textPrimary,
    required this.isNight,
    required this.forecastData,
  });

  // Colores de alto contraste requeridos
  static const Color colorExpected = Color(0xFF0284C7); // Azul Cian
  static const Color colorReal = Color(0xFF10B981);     // Verde Esmeralda

  @override
  Widget build(BuildContext context) {
    final mqttService = context.watch<MqttService>();
    final livePoints = mqttService.livePowerPoints;
    final double currentExp =
        (mqttService.spaData['p_exp'] as num?)?.toDouble() ?? 0.0;
    final double? currentReal =
        (mqttService.telemetryData['power_w'] as num?)?.toDouble();

    final List<FlSpot> expSpots = [];
    final List<FlSpot> realSpots = [];

    if (livePoints.isNotEmpty) {
      for (int i = 0; i < livePoints.length; i++) {
        final double x = i.toDouble();
        expSpots.add(FlSpot(x, livePoints[i]['p_exp'] ?? 0.0));
        realSpots.add(FlSpot(x, livePoints[i]['p_real'] ?? 0.0));
      }
    } else {
      // Precarga inicial si aún no se han acumulado puntos en el buffer de sesión
      // Muestra la curva del pronóstico del día o un segmento sintético inicial
      if (forecastData.isNotEmpty) {
        final count = forecastData.length > 12 ? 12 : forecastData.length;
        for (int i = 0; i < count; i++) {
          final pExp = (forecastData[i]['p_exp'] as num?)?.toDouble() ?? 0.0;
          expSpots.add(FlSpot(i.toDouble(), pExp));
        }
        if (currentReal != null) {
          realSpots.add(FlSpot(0, currentReal));
        }
      } else {
        // Fallback básico inicial con el valor actual esperado
        expSpots.add(FlSpot(0, currentExp));
        expSpots.add(FlSpot(1, currentExp));
        if (currentReal != null) {
          realSpots.add(FlSpot(0, currentReal));
          realSpots.add(FlSpot(1, currentReal));
        }
      }
    }

    final double maxX = (expSpots.isNotEmpty ? expSpots.length - 1 : 1).toDouble();
    double maxY = 100.0;
    for (final s in expSpots) {
      if (s.y > maxY) maxY = s.y;
    }
    for (final s in realSpots) {
      if (s.y > maxY) maxY = s.y;
    }
    maxY = maxY * 1.15; // Margen superior

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: isNight
                ? Colors.black.withValues(alpha: 0.25)
                : HeliosTheme.blueFantastic.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // CABECERA Y LEYENDA VISUAL CLARA
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Potencia: Esperada vs. Real (W)',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: colorExpected,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '● Potencia Esperada (W)',
                    style: TextStyle(
                      color: textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: colorReal,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '● Potencia Real Inversor (W)',
                    style: TextStyle(
                      color: textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 260,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: maxX > 0 ? maxX : 1,
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: isNight
                        ? HeliosTheme.oatmeal.withValues(alpha: 0.08)
                        : HeliosTheme.blueFantastic.withValues(alpha: 0.08),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:
                      const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (val, _) {
                        if (val == 0) return const SizedBox.shrink();
                        return Text(
                          '${val.toInt()}W',
                          style: TextStyle(color: textMuted, fontSize: 10),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: (maxX / 5).clamp(1.0, 10.0),
                      getTitlesWidget: (val, _) => Text(
                        'T-${(maxX - val).toInt()}',
                        style: TextStyle(color: textMuted, fontSize: 10),
                      ),
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  // SERIE 1: Potencia Esperada (Azul Cian)
                  LineChartBarData(
                    spots: expSpots,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: colorExpected,
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colorExpected.withValues(alpha: 0.18),
                          colorExpected.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                  // SERIE 2: Potencia Real (Verde Esmeralda)
                  if (realSpots.isNotEmpty)
                    LineChartBarData(
                      spots: realSpots,
                      isCurved: true,
                      curveSmoothness: 0.25,
                      color: colorReal,
                      barWidth: 2.8,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colorReal.withValues(alpha: 0.25),
                            colorReal.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
