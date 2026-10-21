import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

import '../services/mqtt_service.dart';
import '../services/web_telemetry_service.dart';
import '../theme/helios_animations.dart';
import '../theme/helios_theme.dart';
import '../theme/weather_palette.dart';
import '../database/db_platform.dart';
import 'scada_errors_screen.dart';
import 'plant_config_screen.dart';
import 'widgets/helios_bottom_nav_bar.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<dynamic> _forecastData = [];
  Timer? _refreshTimer;
  Timer? _clockTimer;
  String _currentTimeStr = '--:--:--';
  late PageController _pageController;
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());

    _loadForecast();
    _startForecastTimer(const Duration(seconds: 1));
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
      if (_forecastData.isNotEmpty && interval != const Duration(seconds: 60)) {
        _startForecastTimer(const Duration(seconds: 60));
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _refreshTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  void _onTabSelected(int index) {
    if (index == _currentTabIndex) return;
    setState(() {
      _currentTabIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadForecast() async {
    try {
      final content = readConfigFile('/data/forecast.json');
      if (content == null) {
        if (kIsWeb && mounted) {
          final webService = Provider.of<WebTelemetryService>(context, listen: false);
          if (webService.forecastData.isNotEmpty) {
            setState(() => _forecastData = webService.forecastData);
          }
        }
        return;
      }
      final List<dynamic> all = json.decode(content);
      if (all.isEmpty) return;

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

      // Si filtered tiene datos lo usamos; si quedó vacío por desfase de reloj tras reboot,
      // usamos las primeras 24 horas del pronóstico para renderizado instantáneo (<2s)
      final List<dynamic> displayData =
          filtered.isNotEmpty ? filtered.take(24).toList() : all.take(24).toList();
      if (!mounted) return;
      setState(() => _forecastData = displayData);
    } catch (e) {
      debugPrint("Error leyendo pronóstico: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final mqttService = context.watch<MqttService>();
    final webService = kIsWeb ? context.watch<WebTelemetryService>() : null;

    final bool useWeb = kIsWeb &&
        mqttService.telemetryData.isEmpty &&
        mqttService.spaData.isEmpty &&
        webService != null;

    final telemetry = useWeb ? webService.telemetryData : mqttService.telemetryData;
    final spa = useWeb ? webService.spaData : mqttService.spaData;
    final scada = useWeb ? webService.scadaData : mqttService.scadaData;

    final double? realPower   = (telemetry['power_w']   as num?)?.toDouble();
    final double? realVoltage = (telemetry['v_dc']       as num?)?.toDouble();
    final double? realCurrent = (telemetry['i_dc']       as num?)?.toDouble();
    final double? yieldKwh    = (telemetry['yield_kwh']  as num?)?.toDouble();
    final double? tempC       = (telemetry['temp_c']     as num?)?.toDouble();

    final double? expPower   = (spa['p_exp']            as num?)?.toDouble();
    final double? expVoltage = (spa['v_exp']            as num?)?.toDouble();
    final double? expCurrent = (spa['i_exp']            as num?)?.toDouble();
    final double? ghi        = (spa['ghi']              as num?)?.toDouble();

    final double currentAngle = useWeb ? webService.currentAngle : mqttService.currentAngle;
    final double targetAngle  = useWeb ? webService.targetAngle : mqttService.targetAngle;
    final bool isStow         = useWeb ? webService.isStow : mqttService.isStow;
    final double windKmh      = useWeb ? webService.windKmh : mqttService.windKmh;

    // Estado centralizado de tema (Día vs Noche)
    final bool isNight = useWeb ? webService.isNight : mqttService.isNight;
    final bool isOnline = useWeb ? webService.isInverterConnected : mqttService.isInverterConnected;

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
    } else if (windKmh >= 50.0) {
      hasError = true;
      alertMessage = "FALLA SCADA (104): ¡VIENTO PELIGROSO! ESTIBA ACTIVA (0°)";
    } else if (!isNight &&
        realVoltage != null &&
        expVoltage != null &&
        expVoltage > 0 &&
        realVoltage < expVoltage * 0.90) {
      hasError = true;
      alertMessage = "FALLA SCADA (101): PÉRDIDA DE PANEL EN SERIE";
    } else if (!isNight &&
        realPower != null &&
        expPower != null &&
        expPower > 0 &&
        realPower < expPower * 0.85) {
      hasError = true;
      alertMessage = "FALLA SCADA (102): SOMBREO O SUCIEDAD";
    } else if (tempC != null && tempC > 65.0) {
      hasError = true;
      alertMessage = "FALLA SCADA (103): SOBRECALENTAMIENTO EN INVERSOR";
    } else if (isStow) {
      alertMessage = "MODO ESTIBA (0°) - PANELES EN POSICIÓN SEGURA";
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
    // SISTEMA CROMÁTICO ADAPTATIVO POR CLIMA (TAREA 4)
    // ---------------------------------------------------------
    final String activeWeatherState = mqttService.weatherState;
    final WeatherPalette palette = WeatherPalette.getPalette(activeWeatherState, isNight);

    final Color cardColor = palette.cardColor;
    final Color cardBorderColor = palette.cardBorderColor;
    final Color textPrimary = palette.textPrimary;
    final Color textMuted = palette.textMuted;
    final Color accentSolar = palette.accentSolar;
    final Color accentWarm = palette.accentSecondary;

    final Color statusColor = hasError
        ? HeliosTheme.truffleTrouble.withValues(alpha: isNight ? 0.35 : 0.20)
        : palette.cardColor;

    final Color statusBorderColor = hasError
        ? HeliosTheme.truffleTrouble
        : isNight
            ? palette.accentSolar.withValues(alpha: 0.6)
            : palette.cardBorderColor;



    return Container(
      decoration: palette.rootDecoration,
      child: Scaffold(
        key: _scaffoldKey,
        extendBody: true,
        extendBodyBehindAppBar: _currentTabIndex == 0,
        backgroundColor: Colors.transparent,
        appBar: _currentTabIndex == 0
            ? AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                centerTitle: true,
                // Óvalo / Círculo para menú hamburguesa
                leading: Padding(
                  padding: const EdgeInsets.only(left: 12.0),
                  child: Center(
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: palette.headerCapsuleBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.headerCapsuleBorder, width: 1),
                        boxShadow: palette.headerCapsuleShadow,
                      ),
                      child: IconButton(
                        icon: Icon(Icons.menu, color: palette.headerCapsuleText, size: 20),
                        tooltip: 'Menú principal',
                        padding: EdgeInsets.zero,
                        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                      ),
                    ),
                  ),
                ),
          // Óvalo Central para Reloj (Alto Contraste)
          title: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: palette.headerCapsuleBg,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: palette.headerCapsuleBorder, width: 1),
              boxShadow: palette.headerCapsuleShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.access_time, color: palette.headerCapsuleText, size: 18),
                const SizedBox(width: 8),
                AnimatedMetricText(
                  text: _currentTimeStr,
                  style: TextStyle(
                    color: palette.headerCapsuleText,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          // Óvalo Derecho para Temperatura, kWh, Tema y Estado de Inversor
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: palette.headerCapsuleBg,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: palette.headerCapsuleBorder, width: 1),
                    boxShadow: palette.headerCapsuleShadow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tempC != null) ...[
                        Icon(
                          Icons.thermostat,
                          color: tempC > 65 ? const Color(0xFFDC2626) : palette.headerCapsuleText,
                          size: 17,
                        ),
                        const SizedBox(width: 4),
                        AnimatedMetricText(
                          text: '${tempC.toStringAsFixed(1)}°C',
                          style: TextStyle(
                            color: tempC > 65 ? const Color(0xFFDC2626) : palette.headerCapsuleText,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (yieldKwh != null) ...[
                        const Icon(Icons.bolt, color: Color(0xFFD97706), size: 17),
                        const SizedBox(width: 4),
                        AnimatedMetricText(
                          text: '${yieldKwh.toStringAsFixed(1)} kWh',
                          style: TextStyle(
                            color: palette.headerCapsuleText,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      PulsingGlow(
                        duration: const Duration(milliseconds: 2000),
                        child: Icon(
                          isOnline
                              ? Icons.cloud_done
                              : Icons.cloud_off,
                          color: isOnline
                              ? const Color(0xFF059669) // Verde esmeralda intenso
                              : const Color(0xFFDC2626), // Rojo alerta
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        )
      : null,
        drawer: Drawer(
          backgroundColor: palette.bgColor,
          child: Container(
            decoration: palette.rootDecoration,
            child: Material(
              color: Colors.transparent,
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: BoxDecoration(
                      color: palette.cardColor,
                      border: Border(
                        bottom: BorderSide(color: palette.cardBorderColor, width: 1),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(
                          isNight ? Icons.nightlight_round : Icons.solar_power,
                          size: 44,
                          color: palette.accentSolar,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'HeliOs OS',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (kIsWeb)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: palette.accentSolar.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: palette.accentSolar.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.language, color: palette.accentSolar, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Entorno Web • Telemetría Activa',
                              style: TextStyle(
                                color: palette.accentSolar,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
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
                    selected: _currentTabIndex == 0,
                    selectedTileColor: HeliosTheme.burningFlame.withValues(alpha: 0.15),
                    onTap: () {
                      Navigator.pop(context);
                      _onTabSelected(0);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.warning_amber_rounded, color: textMuted),
                    title: Text(
                      'Menú de Errores SCADA',
                      style: TextStyle(color: textPrimary),
                    ),
                    selected: _currentTabIndex == 1,
                    selectedTileColor: HeliosTheme.burningFlame.withValues(alpha: 0.15),
                    onTap: () {
                      Navigator.pop(context);
                      _onTabSelected(1);
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.settings, color: textMuted),
                    title: Text(
                      'Configuración de Planta',
                      style: TextStyle(color: textPrimary),
                    ),
                    selected: _currentTabIndex == 2,
                    selectedTileColor: HeliosTheme.burningFlame.withValues(alpha: 0.15),
                    onTap: () {
                      Navigator.pop(context);
                      _onTabSelected(2);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: HeliosGlassBottomBar(
          currentIndex: _currentTabIndex,
          onTap: _onTabSelected,
          hasActiveAlarm: hasError,
          activeAlarmCode: scadaCode,
          palette: palette,
          isNight: isNight,
        ),
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // PAISAJE MINIMALISTA GENERADO POR CÓDIGO CON DESVANECIDO INFERIOR
              WeatherHeaderScene(
                weatherState: activeWeatherState,
                isNight: isNight,
                hillBottomColor: palette.hillBottomColor,
                height: 200,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'Pronóstico de Irradiancia y Generación por Hora',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Modelo Híbrido Clear Sky + Open-Meteo WMO',
                      style: TextStyle(color: textMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 12),

                    // --- CARRUSEL DE PRONÓSTICO (TAREA 3) ---
                    Builder(
                      builder: (ctx) {
                        final List<dynamic> activeForecast = _forecastData.isNotEmpty
                            ? _forecastData
                            : (useWeb ? webService.forecastData : []);

                        return StaggeredEntrance(
                          index: 0,
                          child: Container(
                            height: 132,
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
                          child: activeForecast.isEmpty
                              ? Center(
                                  child: Text(
                                    "Sincronizando efemérides solares...",
                                    style: TextStyle(color: textMuted),
                                  ),
                                )
                              : ScrollConfiguration(
                                  behavior: ScrollConfiguration.of(context).copyWith(
                                    dragDevices: {
                                      PointerDeviceKind.touch,
                                      PointerDeviceKind.mouse,
                                      PointerDeviceKind.trackpad,
                                    },
                                  ),
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    physics: const BouncingScrollPhysics(),
                                    itemCount: activeForecast.length,
                                    itemBuilder: (context, index) {
                                      final item = activeForecast[index];
                                  final double fGhi =
                                      (item['ghi'] as num).toDouble();
                                  final double pExpFore =
                                      (item['p_exp'] as num).toDouble();
                                  final bool isDay = fGhi > 0;

                                  final String horaStr =
                                      item['hora_str'] as String? ?? '??:00';
                                  final String fechaStr =
                                      item['fecha_str'] as String? ?? '';
                                  final String itemWeatherState =
                                      (item['weather_state'] as String?) ??
                                          (fGhi > 10 ? 'sunny' : 'clear_night');
                                  final int itemCloudCover =
                                      (item['cloud_cover'] as num?)?.toInt() ?? 0;

                                  return HoverCard(
                                    scaleFactor: 1.05,
                                    child: Container(
                                      width: 82.0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6.0,
                                        vertical: 8.0,
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
                                              fontWeight: FontWeight.w600,
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
                                          _buildHourlyWeatherIcon(
                                            itemWeatherState,
                                            itemCloudCover,
                                            isNight,
                                            isDay,
                                          ),
                                          if (itemWeatherState == 'rain' ||
                                              itemWeatherState == 'storm' ||
                                              (itemCloudCover > 0 && !isDay))
                                            Text(
                                              '$itemCloudCover%',
                                              style: const TextStyle(
                                                color: Color(0xFF38BDF8),
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
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
                                              color: palette.accentSolar,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
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
                      index: 1,
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
                      index: 2,
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
                      index: 3,
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
                      index: 4,
                    ),

                    // Tarjeta Seguidor SAT (1 Eje)
                    _buildMetricCard(
                      title: 'Inclinación del Seguidor (SAT)',
                      realValue: '${currentAngle.toStringAsFixed(1)}°',
                      expValue: 'Óptimo calculado: ${targetAngle.toStringAsFixed(1)}° | ${isStow ? "MODO ESTIBA (0°)" : "Seguimiento Activo"}',
                      icon: Icons.solar_power,
                      cardColor: cardColor,
                      cardBorderColor: cardBorderColor,
                      mutedColor: textMuted,
                      primaryColor: textPrimary,
                      accentColor: isNight ? accentSolar : accentWarm,
                      isComparison: false,
                      valueFontSize: 24,
                      isNight: isNight,
                      index: 5,
                    ),

                    // Tarjeta interactiva: Velocidad del Viento
                    Builder(
                      builder: (cardCtx) {
                        final bool isWindWarning = windKmh >= 35.0 && windKmh < 50.0;
                        final bool isWindCritical = windKmh >= 50.0;

                        final Color windCardBg = isWindCritical
                            ? Colors.red.shade900.withValues(alpha: isNight ? 0.45 : 0.28)
                            : (isWindWarning
                                ? Colors.amber.shade900.withValues(alpha: isNight ? 0.35 : 0.20)
                                : cardColor);

                        final Color windCardBorder = isWindCritical
                            ? Colors.redAccent
                            : (isWindWarning
                                ? Colors.orange.shade600
                                : cardBorderColor);

                        final double windBorderWidth = (isWindCritical || isWindWarning) ? 2.0 : 1.0;

                        final Color windIconColor = isWindCritical
                            ? Colors.redAccent
                            : (isWindWarning ? Colors.orangeAccent : accentSolar);

                        final String windSubtitle = isWindCritical
                            ? "¡VIENTO PELIGROSO! ESTIBA ACTIVA (0°)"
                            : (isWindWarning
                                ? "VIENTO GRAVE - PRECAUCIÓN"
                                : "Viento Normal - Operación Segura");

                        final Color windSubtitleColor = isWindCritical
                            ? Colors.redAccent
                            : (isWindWarning ? Colors.orange.shade300 : textMuted);

                        return StaggeredEntrance(
                          index: 6,
                          child: HoverCard(
                            scaleFactor: 1.02,
                            onTap: () => _showWindProtectionModal(
                              context: context,
                              windKmh: windKmh,
                              currentAngle: currentAngle,
                              isStow: isStow,
                              isNight: isNight,
                              palette: palette,
                              mqttService: mqttService,
                              webService: webService,
                              useWeb: useWeb,
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: windCardBg,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: windCardBorder, width: windBorderWidth),
                                boxShadow: [
                                  BoxShadow(
                                    color: isWindCritical
                                        ? Colors.red.withValues(alpha: 0.3)
                                        : (isWindWarning
                                            ? Colors.orange.withValues(alpha: 0.2)
                                            : (isNight
                                                ? Colors.black.withValues(alpha: 0.25)
                                                : HeliosTheme.blueFantastic.withValues(alpha: 0.06))),
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
                                          'Velocidad del Viento',
                                          style: TextStyle(
                                            color: isWindCritical || isWindWarning
                                                ? windSubtitleColor
                                                : textMuted,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: windIconColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: PulsingGlow(
                                          duration: const Duration(milliseconds: 1400),
                                          child: Icon(Icons.air, color: windIconColor, size: 18),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      AnimatedMetricText(
                                        text: '${windKmh.toStringAsFixed(1)} km/h',
                                        style: TextStyle(
                                          color: textPrimary,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        windSubtitle,
                                        style: TextStyle(
                                          color: windSubtitleColor,
                                          fontSize: 10,
                                          fontWeight: isWindCritical || isWindWarning
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // Tarjeta clickeable: Estado del Sistema
                    StaggeredEntrance(
                      index: 7,
                      child: HoverCard(
                        scaleFactor: 1.02,
                        onTap: () => _onTabSelected(1),
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
                              PulsingGlow(
                                duration: const Duration(milliseconds: 1300),
                                child: Icon(
                                  statusIcon,
                                  color: statusIconColor,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Estado del Sistema',
                                style: TextStyle(color: textMuted, fontSize: 11),
                              ),
                              const SizedBox(height: 4),
                              AnimatedMetricText(
                                text: alertMessage,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
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
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // --- NUEVA GRÁFICA EN TIEMPO REAL (TAREA 5) ---
                StaggeredEntrance(
                  index: 8,
                  child: MultimodalChartContainer(
                    cardColor: cardColor,
                    cardBorderColor: cardBorderColor,
                    textMuted: textMuted,
                    textPrimary: textPrimary,
                    isNight: isNight,
                    forecastData: _forecastData.isNotEmpty
                        ? _forecastData
                        : (useWeb ? webService.forecastData : []),
                  ),
                ),
                const SizedBox(height: 84),
                  ],
                ),
              ),
            ],
          ),
        ),
        const ScadaErrorsScreen(isTab: true),
        const PlantConfigScreen(isTab: true),
      ],
    ),
  ),
);
  }

  void _showWindProtectionModal({
    required BuildContext context,
    required double windKmh,
    required double currentAngle,
    required bool isStow,
    required bool isNight,
    required WeatherPalette palette,
    required MqttService mqttService,
    WebTelemetryService? webService,
    bool useWeb = false,
  }) {
    final Color dialogBg = isNight ? const Color(0xFF1E293B) : Colors.white;
    final Color textPri = isNight ? HeliosTheme.palladian : const Color(0xFF0F172A);
    final Color textMut = isNight ? HeliosTheme.oatmeal : const Color(0xFF64748B);
    final bool isDangerous = windKmh >= 50.0;
    final bool isWarning = windKmh >= 35.0 && windKmh < 50.0;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bool currentManual = (useWeb && webService != null)
                ? webService.manualStow
                : mqttService.manualStow;
            final bool currentStow = (useWeb && webService != null)
                ? webService.isStow
                : mqttService.isStow;
            final double currentDeg = (useWeb && webService != null)
                ? webService.currentAngle
                : mqttService.currentAngle;

            return AlertDialog(
              backgroundColor: dialogBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(
                  color: isDangerous
                      ? Colors.redAccent
                      : (isWarning ? Colors.orangeAccent : palette.cardBorderColor),
                  width: isDangerous || isWarning ? 2 : 1,
                ),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isDangerous ? Colors.red : (isWarning ? Colors.orange : palette.accentSolar))
                          .withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.air,
                      color: isDangerous ? Colors.redAccent : (isWarning ? Colors.orangeAccent : palette.accentSolar),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Protección por Viento',
                      style: TextStyle(
                        color: textPri,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Métrica Actual de Viento
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (isDangerous ? Colors.red : (isWarning ? Colors.orange : palette.cardColor))
                            .withValues(alpha: isNight ? 0.20 : 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDangerous
                              ? Colors.redAccent
                              : (isWarning ? Colors.orangeAccent : palette.cardBorderColor),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'VELOCIDAD MEDIDA',
                                style: TextStyle(
                                  color: textMut,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${windKmh.toStringAsFixed(1)} km/h',
                                style: TextStyle(
                                  color: isDangerous
                                      ? Colors.redAccent
                                      : (isWarning ? Colors.orangeAccent : textPri),
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: (isDangerous ? Colors.red : (isWarning ? Colors.orange : Colors.green))
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isDangerous
                                  ? 'PELIGRO (≥50 km/h)'
                                  : (isWarning ? 'PRECAUCIÓN (≥35 km/h)' : 'NORMAL (<35 km/h)'),
                              style: TextStyle(
                                color: isDangerous
                                    ? Colors.redAccent
                                    : (isWarning ? Colors.orangeAccent : Colors.green),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Estado actual de los paneles
                    Row(
                      children: [
                        Text('Estado de Paneles: ', style: TextStyle(color: textMut, fontSize: 13)),
                        Text(
                          currentStow
                              ? 'En Posición de Estiba a 0.0°'
                              : 'En Seguimiento Normal (${currentDeg.toStringAsFixed(1)}°)',
                          style: TextStyle(
                            color: currentStow ? Colors.orangeAccent : Colors.green,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Mensaje explicativo
                    Text(
                      'Protección Mecánica Aerodinámica:\n'
                      'Las ráfagas intensas pueden inducir torsión y fuerzas de sustentación que dañan '
                      'los rodamientos y actuadores. Ante vientos ≥50 km/h, el sistema activa automáticamente '
                      'la Estiba Plana (0.0° horizontal) para reducir el arrastre aerodinámico.',
                      style: TextStyle(color: textMut, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 16),

                    // Botón de acción directa de Estiba Manual
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: currentManual
                              ? Colors.green.withValues(alpha: 0.2)
                              : Colors.orange.withValues(alpha: 0.2),
                          foregroundColor: currentManual ? Colors.green : Colors.orangeAccent,
                          side: BorderSide(
                            color: currentManual ? Colors.green : Colors.orangeAccent,
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(
                          currentManual ? Icons.play_arrow : Icons.pan_tool,
                          size: 18,
                        ),
                        label: Text(
                          currentManual
                              ? 'Desactivar Estiba Manual y Retomar Seguimiento'
                              : 'Activar Modo Estiba Manual (llevar paneles a 0°)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: () {
                          final bool newStow = !currentManual;
                          mqttService.publishTrackerCommand(manualStow: newStow);
                          if (useWeb && webService != null) {
                            webService.setManualStow(newStow);
                          }
                          setModalState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cerrar', style: TextStyle(color: textPri)),
                ),
              ],
            );
          },
        );
      },
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
    int index = 0,
    VoidCallback? onTap,
  }) {
    return StaggeredEntrance(
      index: index,
      child: HoverCard(
        onTap: onTap,
        child: Container(
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
                  AnimatedMetricText(
                    text: realValue,
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: valueFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  AnimatedMetricText(
                    text: isComparison ? 'Esperado: $expValue' : expValue,
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
        ),
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
    final webService = kIsWeb ? context.watch<WebTelemetryService>() : null;
    final bool useWeb = kIsWeb &&
        mqttService.telemetryData.isEmpty &&
        mqttService.spaData.isEmpty &&
        webService != null;

    final livePoints = useWeb ? webService.livePowerPoints : mqttService.livePowerPoints;
    final double currentExp = useWeb
        ? ((webService.spaData['p_exp'] as num?)?.toDouble() ?? 0.0)
        : ((mqttService.spaData['p_exp'] as num?)?.toDouble() ?? 0.0);
    final double? currentReal = useWeb
        ? ((webService.telemetryData['power_w'] as num?)?.toDouble())
        : ((mqttService.telemetryData['power_w'] as num?)?.toDouble());

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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
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
                mainAxisSize: MainAxisSize.min,
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

// ===========================================================
// ÍCONOS Y ESTILOS DINÁMICOS POR HORA (OPEN-METEO WMO)
// ===========================================================
Widget _buildHourlyWeatherIcon(
  String weatherState,
  int cloudCover,
  bool isNight,
  bool isDay,
) {
  switch (weatherState) {
    case 'sunny':
      return const Icon(
        Icons.wb_sunny,
        color: HeliosTheme.burningFlame,
        size: 26,
      );
    case 'partly_cloudy':
      return SizedBox(
        width: 28,
        height: 28,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned(
              top: 2,
              left: 2,
              child: Icon(Icons.wb_sunny, color: HeliosTheme.burningFlame, size: 18),
            ),
            Positioned(
              bottom: 1,
              right: 1,
              child: Icon(
                Icons.cloud,
                color: isNight ? HeliosTheme.oatmeal : const Color(0xFF94A3B8),
                size: 18,
              ),
            ),
          ],
        ),
      );
    case 'cloudy':
      return Icon(
        Icons.cloud,
        color: isNight ? HeliosTheme.oatmeal : const Color(0xFF64748B),
        size: 26,
      );
    case 'rain':
      return const Icon(
        Icons.water_drop,
        color: Color(0xFF38BDF8),
        size: 26,
      );
    case 'storm':
      return const Icon(
        Icons.thunderstorm,
        color: Color(0xFFA855F7),
        size: 26,
      );
    case 'clear_night':
      return const Icon(
        Icons.nightlight_round,
        color: Color(0xFF818CF8),
        size: 26,
      );
    case 'cloudy_night':
      return const Icon(
        Icons.nights_stay,
        color: Color(0xFF94A3B8),
        size: 26,
      );
    default:
      return Icon(
        isDay ? Icons.wb_sunny : Icons.nightlight_round,
        color: isDay
            ? HeliosTheme.burningFlame
            : (isNight ? HeliosTheme.oatmeal : HeliosTheme.blueFantastic),
        size: 26,
      );
  }
}

// ===========================================================
// PAISAJE MINIMALISTA VECTORIAL / PROCEDURAL (CUSTOM PAINTER)
// ===========================================================
class WeatherHeaderScene extends StatefulWidget {
  final String weatherState;
  final bool isNight;
  final Color? hillBottomColor;
  final double height;

  const WeatherHeaderScene({
    super.key,
    required this.weatherState,
    required this.isNight,
    this.hillBottomColor,
    this.height = 200,
  });

  @override
  State<WeatherHeaderScene> createState() => _WeatherHeaderSceneState();
}

class _WeatherHeaderSceneState extends State<WeatherHeaderScene>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ShaderMask(
        shaderCallback: (Rect bounds) {
          return const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.55, 1.0],
            colors: [
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: AnimatedBuilder(
          animation: _animCtrl,
          builder: (context, _) {
            return CustomPaint(
              size: Size(double.infinity, widget.height),
              painter: _WeatherScenePainter(
                weatherState: widget.weatherState,
                isNight: widget.isNight,
                hillBottomColor: widget.hillBottomColor,
                animProgress: _animCtrl.value,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WeatherScenePainter extends CustomPainter {
  final String weatherState;
  final bool isNight;
  final Color? hillBottomColor;
  final double animProgress;

  _WeatherScenePainter({
    required this.weatherState,
    required this.isNight,
    this.hillBottomColor,
    this.animProgress = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawSky(canvas, size);
    _drawCelestialAndWeather(canvas, size);
    _drawHills(canvas, size);
    _drawSolarPanels(canvas, size);
    _drawTrees(canvas, size);

    // Gradiente sutil superior para legibilidad óptima de AppBar
    final Rect topRect = Rect.fromLTWH(0, 0, size.width, 68);
    final Paint topVignette = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.40),
          Colors.transparent,
        ],
      ).createShader(topRect);
    canvas.drawRect(topRect, topVignette);
  }

  void _drawSky(Canvas canvas, Size size) {
    final Rect skyRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final List<Color> colors;

    switch (weatherState) {
      case 'storm':
        colors = const [Color(0xFF0F0B1E), Color(0xFF1E1B4B), Color(0xFF312E81)];
        break;
      case 'rain':
        colors = const [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF334155)];
        break;
      case 'cloudy':
        colors = isNight
            ? const [Color(0xFF090D16), Color(0xFF131D2D), Color(0xFF1E293B)]
            : const [Color(0xFF334155), Color(0xFF64748B), Color(0xFF94A3B8)];
        break;
      case 'partly_cloudy':
        colors = isNight
            ? const [Color(0xFF0B132B), Color(0xFF1C2541), Color(0xFF2C3B4D)]
            : const [Color(0xFF1E3A8A), Color(0xFF3B82F6), Color(0xFF93C5FD)];
        break;
      case 'cloudy_night':
        colors = const [Color(0xFF090D16), Color(0xFF131D2D), Color(0xFF1E293B)];
        break;
      case 'clear_night':
        colors = const [Color(0xFF030712), Color(0xFF0B132B), Color(0xFF1C2541)];
        break;
      case 'sunny':
      default:
        colors = isNight
            ? const [Color(0xFF030712), Color(0xFF0B132B), Color(0xFF1C2541)]
            : const [Color(0xFF1D4ED8), Color(0xFF38BDF8), Color(0xFFBAE6FD)];
        break;
    }

    final Paint skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      ).createShader(skyRect);
    canvas.drawRect(skyRect, skyPaint);
  }

  void _drawCelestialAndWeather(Canvas canvas, Size size) {
    final bool isNightMode = weatherState.contains('night') || isNight;

    if (isNightMode) {
      final Paint starPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
      final List<Offset> stars = [
        Offset(size.width * 0.08, size.height * 0.16),
        Offset(size.width * 0.18, size.height * 0.28),
        Offset(size.width * 0.28, size.height * 0.14),
        Offset(size.width * 0.42, size.height * 0.22),
        Offset(size.width * 0.58, size.height * 0.18),
        Offset(size.width * 0.70, size.height * 0.12),
        Offset(size.width * 0.88, size.height * 0.25),
        Offset(size.width * 0.94, size.height * 0.15),
      ];
      for (int i = 0; i < stars.length; i++) {
        final double twinkle = (0.35 + 0.65 * math.sin((animProgress * 2 * math.pi) + (i * 1.6)).abs()).clamp(0.0, 1.0);
        starPaint.color = Colors.white.withValues(alpha: twinkle);
        canvas.drawCircle(stars[i], 1.2, starPaint);
      }

      final Offset moonCenter = Offset(size.width * 0.82, size.height * 0.32);
      final double moonPulse = 1.0 + 0.04 * math.sin(animProgress * 2 * math.pi);
      final Paint moonHalo = Paint()
        ..color = const Color(0xFFFEF08A).withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(moonCenter, 20 * moonPulse, moonHalo);

      final Paint moonBody = Paint()..color = const Color(0xFFFEF9C3);
      canvas.drawCircle(moonCenter, 14, moonBody);

      final Paint moonCut = Paint()..color = const Color(0xFF0B132B);
      canvas.drawCircle(Offset(moonCenter.dx - 5, moonCenter.dy - 3), 12, moonCut);
    } else {
      final Offset sunCenter = Offset(size.width * 0.82, size.height * 0.30);
      final double sunPulse = 1.0 + 0.08 * math.sin(animProgress * 2 * math.pi);
      final Paint sunGlow = Paint()
        ..color = const Color(0xFFFBBF24).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawCircle(sunCenter, 32 * sunPulse, sunGlow);

      final Paint sunCore = Paint()..color = const Color(0xFFFDE047);
      canvas.drawCircle(sunCenter, 16, sunCore);
    }

    if (weatherState == 'partly_cloudy' ||
        weatherState == 'cloudy' ||
        weatherState == 'rain' ||
        weatherState == 'storm' ||
        weatherState == 'cloudy_night') {
      final Color cloudColor = (weatherState == 'rain' || weatherState == 'storm')
          ? const Color(0xFF334155).withValues(alpha: 0.8)
          : isNightMode
              ? const Color(0xFF1E293B).withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.75);

      final double drift = math.sin(animProgress * 2 * math.pi) * 12.0;
      _drawCloud(canvas, Offset(size.width * 0.25 + drift, size.height * 0.32), 24, cloudColor);
      _drawCloud(canvas, Offset(size.width * 0.78 - drift * 0.7, size.height * 0.34), 30, cloudColor);
      if (weatherState == 'cloudy' || weatherState == 'rain' || weatherState == 'storm') {
        _drawCloud(canvas, Offset(size.width * 0.50 + drift * 0.5, size.height * 0.26), 28, cloudColor);
      }
    }

    if (weatherState == 'rain' || weatherState == 'storm') {
      final Paint rainPaint = Paint()
        ..color = const Color(0xFF93C5FD).withValues(alpha: 0.55)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;

      for (int i = 0; i < 24; i++) {
        final double rx = (size.width * (i * 0.042 + 0.02)) % size.width;
        final double ry = (size.height * 0.15 + (i * 12.0) + (animProgress * size.height * 0.8)) % (size.height * 0.65);
        canvas.drawLine(Offset(rx, ry), Offset(rx - 7, ry + 16), rainPaint);
      }
    }

    if (weatherState == 'storm') {
      final Paint boltPaint = Paint()
        ..color = const Color(0xFFFDE047)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final Path bolt = Path()
        ..moveTo(size.width * 0.52, size.height * 0.22)
        ..lineTo(size.width * 0.49, size.height * 0.34)
        ..lineTo(size.width * 0.53, size.height * 0.34)
        ..lineTo(size.width * 0.47, size.height * 0.50);
      canvas.drawPath(bolt, boltPaint);
    }
  }

  void _drawCloud(Canvas canvas, Offset center, double baseRadius, Color color) {
    final Paint cloudPaint = Paint()..color = color;
    canvas.drawCircle(center, baseRadius, cloudPaint);
    canvas.drawCircle(Offset(center.dx - baseRadius * 0.7, center.dy + baseRadius * 0.2), baseRadius * 0.65, cloudPaint);
    canvas.drawCircle(Offset(center.dx + baseRadius * 0.7, center.dy + baseRadius * 0.2), baseRadius * 0.65, cloudPaint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(center.dx, center.dy + baseRadius * 0.3), width: baseRadius * 2.5, height: baseRadius * 0.8),
        Radius.circular(baseRadius * 0.4),
      ),
      cloudPaint,
    );
  }

  void _drawHills(Canvas canvas, Size size) {
    final bool isNightMode = weatherState.contains('night') || isNight;

    final Color hill1Color = isNightMode
        ? const Color(0xFF162544)
        : (weatherState == 'rain' || weatherState == 'storm')
            ? const Color(0xFF334E43)
            : const Color(0xFF65A30D);
    final Path hill1 = Path()
      ..moveTo(0, size.height * 0.48)
      ..quadraticBezierTo(size.width * 0.25, size.height * 0.38, size.width * 0.55, size.height * 0.46)
      ..quadraticBezierTo(size.width * 0.80, size.height * 0.52, size.width, size.height * 0.42)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(hill1, Paint()..color = hill1Color);

    final Color hill2Color = isNightMode
        ? const Color(0xFF111E38)
        : (weatherState == 'rain' || weatherState == 'storm')
            ? const Color(0xFF243B33)
            : const Color(0xFF22C55E);
    final Path hill2 = Path()
      ..moveTo(0, size.height * 0.60)
      ..quadraticBezierTo(size.width * 0.35, size.height * 0.50, size.width * 0.68, size.height * 0.62)
      ..quadraticBezierTo(size.width * 0.88, size.height * 0.68, size.width, size.height * 0.56)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(hill2, Paint()..color = hill2Color);

    final Color hill3Color = hillBottomColor ??
        (isNightMode
            ? const Color(0xFF0C1628)
            : (weatherState == 'rain' || weatherState == 'storm')
                ? const Color(0xFF1A2E28)
                : const Color(0xFF15803D));
    final Path hill3 = Path()
      ..moveTo(0, size.height * 0.72)
      ..quadraticBezierTo(size.width * 0.28, size.height * 0.62, size.width * 0.58, size.height * 0.74)
      ..quadraticBezierTo(size.width * 0.85, size.height * 0.68, size.width, size.height * 0.76)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(hill3, Paint()..color = hill3Color);
  }

  void _drawSolarPanels(Canvas canvas, Size size) {
    final Paint polePaint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 2.0;

    final Paint panelBorder = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final Paint panelFill = Paint()..color = const Color(0xFF1E3A8A);
    final Paint panelGrid = Paint()
      ..color = const Color(0xFF60A5FA).withValues(alpha: 0.6)
      ..strokeWidth = 0.8;

    final List<Offset> bases = [
      Offset(size.width * 0.20, size.height * 0.58),
      Offset(size.width * 0.26, size.height * 0.57),
    ];

    for (final base in bases) {
      canvas.drawLine(base, Offset(base.dx, base.dy - 12), polePaint);

      final Path panel = Path()
        ..moveTo(base.dx - 12, base.dy - 10)
        ..lineTo(base.dx + 10, base.dy - 16)
        ..lineTo(base.dx + 14, base.dy - 6)
        ..lineTo(base.dx - 8, base.dy - 0)
        ..close();

      canvas.drawPath(panel, panelFill);
      canvas.drawPath(panel, panelBorder);
      canvas.drawLine(
        Offset(base.dx - 1, base.dy - 13),
        Offset(base.dx + 3, base.dy - 3),
        panelGrid,
      );
    }
  }

  void _drawTrees(Canvas canvas, Size size) {
    final bool isNightMode = weatherState.contains('night') || isNight;

    final List<Map<String, double>> treePositions = [
      {'x': 0.08, 'y': 0.56, 'scale': 0.85},
      {'x': 0.14, 'y': 0.54, 'scale': 0.75},
      {'x': 0.35, 'y': 0.57, 'scale': 0.90},
      {'x': 0.44, 'y': 0.62, 'scale': 1.05},
      {'x': 0.52, 'y': 0.64, 'scale': 0.95},
      {'x': 0.64, 'y': 0.65, 'scale': 1.10},
      {'x': 0.76, 'y': 0.62, 'scale': 0.90},
      {'x': 0.85, 'y': 0.58, 'scale': 0.80},
      {'x': 0.92, 'y': 0.60, 'scale': 0.85},
    ];

    final Paint trunkPaint = Paint()
      ..color = const Color(0xFF5C4033)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final Color canopyPrimary = isNightMode
        ? const Color(0xFF1E3A5F)
        : (weatherState == 'rain' || weatherState == 'storm')
            ? const Color(0xFF1B4332)
            : const Color(0xFF2D6A4F);

    final Color canopySecondary = isNightMode
        ? const Color(0xFF142844)
        : (weatherState == 'rain' || weatherState == 'storm')
            ? const Color(0xFF143627)
            : const Color(0xFF40916C);

    final Paint canopyPaint = Paint()..color = canopyPrimary;
    final Paint canopyPaint2 = Paint()..color = canopySecondary;
    final Paint fruitPaint = Paint()..color = const Color(0xFFFBBF24);

    for (final t in treePositions) {
      final double tx = size.width * t['x']!;
      final double ty = size.height * t['y']!;
      final double sc = t['scale']!;

      final double trunkH = 18.0 * sc;
      final double canopyR = 14.0 * sc;

      canvas.drawLine(Offset(tx, ty), Offset(tx, ty - trunkH), trunkPaint);

      final Offset cCenter = Offset(tx, ty - trunkH - canopyR * 0.6);
      canvas.drawCircle(Offset(cCenter.dx - 4 * sc, cCenter.dy), canopyR * 0.85, canopyPaint2);
      canvas.drawCircle(Offset(cCenter.dx + 4 * sc, cCenter.dy), canopyR * 0.85, canopyPaint2);
      canvas.drawCircle(cCenter, canopyR, canopyPaint);

      final List<Offset> fruits = [
        Offset(cCenter.dx - 5 * sc, cCenter.dy - 3 * sc),
        Offset(cCenter.dx + 4 * sc, cCenter.dy - 5 * sc),
        Offset(cCenter.dx, cCenter.dy + 3 * sc),
        Offset(cCenter.dx - 3 * sc, cCenter.dy + 5 * sc),
        Offset(cCenter.dx + 6 * sc, cCenter.dy + 2 * sc),
      ];
      for (final f in fruits) {
        canvas.drawCircle(f, 1.8 * sc, fruitPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherScenePainter oldDelegate) {
    return oldDelegate.weatherState != weatherState ||
        oldDelegate.isNight != isNight ||
        oldDelegate.animProgress != animProgress;
  }
}
