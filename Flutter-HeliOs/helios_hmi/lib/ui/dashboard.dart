import 'dart:convert';
import 'dart:async';

import 'package:sqlite3/common.dart' as sql;
import 'package:helios_hmi/database/db_platform.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../services/mqtt_service.dart';
import '../theme/helios_theme.dart';
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
    // Reintento rápido (10 s) para evadir carrera de arranque
    _startForecastTimer(const Duration(seconds: 10));
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
    super.dispose();
  }

  /// Lee /data/forecast.json y filtra registros desde la hora actual.
  /// Usa timestamp_epoch (segundos UTC) para evitar el bug de .toLocal()
  /// cuando el OS Yocto está en UTC puro.
  Future<void> _loadForecast() async {
    try {
      final content = readConfigFile('/data/forecast.json');
      if (content == null) return;
      final List<dynamic> all = json.decode(content);

      // Umbral: "ahora" en segundos epoch UTC (sin zona horaria del OS)
      final int nowEpoch =
          DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      // Margen de 59 minutos hacia atrás para mostrar la hora actual
      final int threshold = nowEpoch - 59 * 60;

      final filtered = all.where((item) {
        final epoch = item['timestamp_epoch'] as int?;
        if (epoch != null) return epoch >= threshold;
        // Fallback para JSONs antiguos sin timestamp_epoch
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

  void _showThemeMenu(BuildContext context, bool isNight) {
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
              label: 'Automático (según irradiancia)',
              value: DashboardThemeMode.auto,
              isNight: isNight,
            ),
            _themeOption(
              icon: Icons.wb_sunny,
              label: 'Forzar Día',
              value: DashboardThemeMode.forceDay,
              isNight: isNight,
            ),
            _themeOption(
              icon: Icons.nightlight_round,
              label: 'Forzar Noche',
              value: DashboardThemeMode.forceNight,
              isNight: isNight,
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
    required bool isNight,
  }) {
    final bool selected = _themeMode == value;
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
        setState(() => _themeMode = value);
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mqttService = context.watch<MqttService>();

    final telemetry = mqttService.telemetryData;
    final spa       = mqttService.spaData;
    final scada     = mqttService.scadaData;

    final double? realPower   = (telemetry['power_w']   as num?)?.toDouble();
    final double? realVoltage = (telemetry['v_dc']       as num?)?.toDouble();
    final double? realCurrent = (telemetry['i_dc']       as num?)?.toDouble();
    final double? yieldKwh    = (telemetry['yield_kwh']  as num?)?.toDouble();
    final double? tempC       = (telemetry['temp_c']     as num?)?.toDouble();

    final double? expPower   = (spa['p_exp']            as num?)?.toDouble();
    final double? expVoltage = (spa['v_exp']            as num?)?.toDouble();
    final double? expCurrent = (spa['i_exp']            as num?)?.toDouble();
    final double? ghi        = (spa['ghi']              as num?)?.toDouble();
    // Fallback a azimuth/elevation si motor_* aún no viene en el payload
    final double? motorAz    = (spa['motor_azimuth']    as num?)?.toDouble() ??
        (spa['azimuth']   as num?)?.toDouble();
    final double? motorEl    = (spa['motor_elevation']  as num?)?.toDouble() ??
        (spa['elevation'] as num?)?.toDouble();

    // is_night viene del SPA; si aún no hay datos se asume noche
    final bool isNightFromSpa = spa['is_night'] as bool? ?? true;

    // Aplicar override manual de tema
    final bool isNight = switch (_themeMode) {
      DashboardThemeMode.forceDay   => false,
      DashboardThemeMode.forceNight => true,
      DashboardThemeMode.auto       => isNightFromSpa,
    };

    final int    scadaCode = (scada['code']        as num?)?.toInt() ?? 0;
    final String scadaDesc =  scada['description'] as String? ?? 'Operación Normal';

    // --- Lógica de estado del sistema ---
    final bool inversorSinDatos = telemetry.isEmpty;
    final bool spaActivo        = spa.isNotEmpty;
    bool   hasError      = false;
    String alertMessage  = "OPERACIÓN NORMAL";

    if (scadaCode != 0) {
      hasError    = true;
      alertMessage = "FALLA SCADA ($scadaCode): ${scadaDesc.toUpperCase()}";
    } else if (inversorSinDatos && spaActivo) {
      // SPA activo pero sin inversor conectado
      alertMessage = isNightFromSpa
          ? "MODO NOCTURNO - PANELES EN ESTIBA"
          : "MONITOREO LOCAL ACTIVO (SIN INVERSOR)";
    } else if (inversorSinDatos && !spaActivo) {
      alertMessage = "ESPERANDO TELEMETRÍA...";
    } else if (isNightFromSpa) {
      alertMessage = "MODO NOCTURNO - PANELES EN ESTIBA";
    }
    // Validaciones de anomalía solo de día (la RPi ya las reporta en scadaCode,
    // pero por si llega antes de que helios-scada procese):
    else if (!isNightFromSpa &&
        realVoltage != null &&
        expVoltage  != null &&
        expVoltage  > 0 &&
        realVoltage < expVoltage * 0.90) {
      hasError     = true;
      alertMessage = "ALERTA: PÉRDIDA DE PANEL EN SERIE";
    } else if (!isNightFromSpa &&
        realPower != null &&
        expPower  != null &&
        expPower  > 0 &&
        realPower < expPower * 0.85) {
      hasError     = true;
      alertMessage = "ALERTA: SOMBREO O SUCIEDAD";
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
        ? (scadaCode != 0 ||
                (realVoltage != null &&
                    expVoltage != null &&
                    realVoltage < expVoltage * 0.90)
            ? HeliosTheme.truffleTrouble.withValues(alpha: 0.35)
            : HeliosTheme.burningFlame.withValues(alpha: 0.3))
        : isNightFromSpa
            ? (isNight
                ? HeliosTheme.blueFantastic.withValues(alpha: 0.7)
                : HeliosTheme.oatmeal.withValues(alpha: 0.4))
            : cardColor;

    final Color statusBorderColor = hasError
        ? (scadaCode != 0 ||
                (realVoltage != null &&
                    expVoltage != null &&
                    realVoltage < expVoltage * 0.90)
            ? HeliosTheme.truffleTrouble
            : HeliosTheme.burningFlame)
        : isNightFromSpa
            ? HeliosTheme.burningFlame.withValues(alpha: 0.6)
            : cardBorderColor;

    // Tarjeta de motores
    final String motorAzStr = motorAz != null ? motorAz.toStringAsFixed(1) : '--';
    final String motorElStr = motorEl != null ? motorEl.toStringAsFixed(1) : '--';
    final String motorSubtitle = isNightFromSpa
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
          iconTheme: IconThemeData(
            color: textPrimary,
            size: 28,
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
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (yieldKwh != null) ...[
                    Icon(Icons.bolt, color: accentSolar, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '${yieldKwh.toStringAsFixed(1)} kWh',
                      style: TextStyle(color: textMuted, fontSize: 13),
                    ),
                    const SizedBox(width: 10),
                  ],
                  // Botón Tema Día/Noche
                  IconButton(
                    icon: Icon(
                      _themeMode == DashboardThemeMode.forceDay
                          ? Icons.wb_sunny
                          : _themeMode == DashboardThemeMode.forceNight
                              ? Icons.nightlight_round
                              : Icons.brightness_auto,
                      color: _themeMode == DashboardThemeMode.forceDay
                          ? HeliosTheme.burningFlame
                          : _themeMode == DashboardThemeMode.forceNight
                              ? HeliosTheme.oatmeal
                              : accentSolar,
                    ),
                    tooltip: 'Modo de tema',
                    onPressed: () => _showThemeMenu(context, isNight),
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
                        Icons.solar_power,
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
                  leading: Icon(Icons.dashboard, color: HeliosTheme.burningFlame),
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
                // --- HEADER ---
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

                // --- CARRUSEL DE PRONÓSTICO (hora local México pre-formateada) ---
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

                    // --- Tarjeta fusionada: Ángulo Óptimo (Motores) ---
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

                    // --- Tarjeta clickeable: Estado del Sistema ---
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
                            width: hasError || isNightFromSpa ? 2 : 1,
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
                              hasError
                                  ? Icons.warning_amber_rounded
                                  : isNightFromSpa
                                      ? Icons.bedtime
                                      : (inversorSinDatos && spaActivo
                                          ? Icons.wifi_tethering
                                          : (inversorSinDatos && !spaActivo
                                              ? Icons.hourglass_empty
                                              : Icons.check_circle_outline)),
                              color: hasError
                                  ? HeliosTheme.truffleTrouble
                                  : isNightFromSpa
                                      ? HeliosTheme.burningFlame
                                      : (inversorSinDatos
                                          ? textMuted
                                          : (isNight ? HeliosTheme.burningFlame : HeliosTheme.truffleTrouble)),
                              size: 32,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Estado del Sistema',
                              style:
                                  TextStyle(color: textMuted, fontSize: 11),
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
                MultimodalChartContainer(
                  cardColor: cardColor,
                  cardBorderColor: cardBorderColor,
                  textMuted: textMuted,
                  textPrimary: textPrimary,
                  accentSolar: accentSolar,
                  accentSecondary:
                      isNight ? HeliosTheme.oatmeal : HeliosTheme.blueFantastic,
                  isNight: isNight,
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
// GRÁFICO HISTÓRICO SCADA — Sin FutureBuilder en build()
// ===========================================================
class MultimodalChartContainer extends StatefulWidget {
  final Color cardColor;
  final Color cardBorderColor;
  final Color textMuted;
  final Color textPrimary;
  final Color accentSolar;
  final Color accentSecondary;
  final bool isNight;

  const MultimodalChartContainer({
    super.key,
    required this.cardColor,
    required this.cardBorderColor,
    required this.textMuted,
    required this.textPrimary,
    required this.accentSolar,
    required this.accentSecondary,
    required this.isNight,
  });

  @override
  State<MultimodalChartContainer> createState() =>
      _MultimodalChartContainerState();
}

class _MultimodalChartContainerState
    extends State<MultimodalChartContainer> {
  Timer? _historyTimer;
  List<Map<String, double>> _chartData = [];
  bool _initialLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _historyTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _fetchData());
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchData() async {
    const dbPath = '/data/helios_history.db';
    sql.CommonDatabase? db;
    try {
      db = await openAppDatabase(dbPath);
      if (db == null) {
        if (mounted) setState(() => _initialLoading = false);
        return;
      }
      final sql.ResultSet results = db.select(
        'SELECT p_real, p_exp FROM telemetry_log ORDER BY timestamp DESC LIMIT 50;',
      );
      final List<Map<String, double>> loaded = [];
      for (final sql.Row row in results) {
        loaded.add({
          'p_real': (row['p_real'] as num?)?.toDouble() ?? 0.0,
          'p_exp':  (row['p_exp']  as num?)?.toDouble() ?? 0.0,
        });
      }
      if (!mounted) return;
      setState(() {
        _chartData      = loaded.reversed.toList();
        _initialLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _initialLoading = false);
    } finally {
      db?.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.cardBorderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: widget.isNight
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: widget.accentSolar,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('Real',
                      style: TextStyle(color: widget.textMuted, fontSize: 11)),
                  const SizedBox(width: 10),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: widget.accentSecondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('Esperada',
                      style: TextStyle(color: widget.textMuted, fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(height: 280, child: _buildChart()),
        ],
      ),
    );
  }

  Widget _buildChart() {
    if (_initialLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: widget.accentSolar,
          strokeWidth: 2,
        ),
      );
    }

    if (_chartData.isEmpty) {
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
    for (int i = 0; i < _chartData.length; i++) {
      realSpots.add(FlSpot(i.toDouble(), _chartData[i]['p_real']!));
      expSpots.add(FlSpot(i.toDouble(),  _chartData[i]['p_exp']!));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: widget.isNight
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
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 10,
              getTitlesWidget: (val, _) => Text(
                'T-${50 - val.toInt()}',
                style:
                    TextStyle(color: widget.textMuted, fontSize: 10),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (_chartData.length - 1).toDouble(),
        lineBarsData: [
          // Curva Potencia Esperada (Modelo Astronómico)
          LineChartBarData(
            spots: expSpots,
            isCurved: true,
            color: widget.accentSecondary.withValues(alpha: 0.7),
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
          // Curva Potencia Real (inversor)
          LineChartBarData(
            spots: realSpots,
            isCurved: true,
            color: widget.accentSolar,
            barWidth: 2.8,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  widget.accentSolar.withValues(alpha: 0.28),
                  widget.accentSolar.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
