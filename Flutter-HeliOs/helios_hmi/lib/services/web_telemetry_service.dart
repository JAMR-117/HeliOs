import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Servicio de Telemetría Web y Simulación Solar para HeliOs HMI.
/// Provee métricas realistas en tiempo real cuando la aplicación corre en Web
/// o cuando no hay un broker MQTT conectado localmente, garantizando que
/// la interfaz visualice todas las lecturas de forma viva y fidedigna
/// sin alterar en lo absoluto la arquitectura MQTT nativa.
class WebTelemetryService extends ChangeNotifier {
  Timer? _timer;
  final math.Random _random = math.Random();

  // Coordenadas geográficas de la planta HeliOs (Ojo de Agua, EdoMex)
  static const double latitude = 19.6800;
  static const double longitude = -99.0100;
  // Potencia pico: 18 módulos en serie * 4 cadenas * 550 Wp = 39,600 Wp
  static const double pPeak = 39600.0;

  // Estado del motor y simulación
  bool _manualStow = false;
  double? _forcedWindKmh;
  double? _simulatedHour; // Permite probar diferentes horas del día si se desea

  double _currentTrackerAngle = 0.0;
  double _windKmh = 13.2;

  // Buffers y datos
  final Map<String, dynamic> _telemetryData = {};
  final Map<String, dynamic> _spaData = {};
  final Map<String, dynamic> _trackerData = {};
  final Map<String, dynamic> _scadaData = {
    'code': 0,
    'description': 'Operación Normal',
  };

  final List<Map<String, double>> _livePowerPoints = [];
  List<dynamic> _forecastData = [];

  WebTelemetryService() {
    _initForecast();
    _prefillLivePowerBuffer();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  // Getters públicos compatibles con la estructura consumida por el Dashboard
  Map<String, dynamic> get telemetryData => Map.unmodifiable(_telemetryData);
  Map<String, dynamic> get spaData => Map.unmodifiable(_spaData);
  Map<String, dynamic> get trackerData => Map.unmodifiable(_trackerData);
  Map<String, dynamic> get scadaData => Map.unmodifiable(_scadaData);
  List<Map<String, double>> get livePowerPoints => List.unmodifiable(_livePowerPoints);
  List<dynamic> get forecastData => List.unmodifiable(_forecastData);

  double get currentAngle => _currentTrackerAngle;
  double get targetAngle => (_spaData['target_angle'] as num?)?.toDouble() ?? 0.0;
  bool get isStow => (_spaData['is_stow'] as bool?) ?? false;
  double get windKmh => _windKmh;
  bool get isNight => (_spaData['is_night'] as bool?) ?? false;
  String get weatherState => (_spaData['weather_state'] as String?) ?? 'sunny';
  int get cloudCover => (_spaData['cloud_cover'] as num?)?.toInt() ?? 0;
  bool get isInverterConnected => true;
  bool get isTrackerConnected => true;
  bool get manualStow => _manualStow;

  double? get tempC => (_telemetryData['temp_c'] as num?)?.toDouble();
  double? get yieldKwh => (_telemetryData['yield_kwh'] as num?)?.toDouble();

  void setManualStow(bool value) {
    _manualStow = value;
    _tick();
    notifyListeners();
  }

  void setWindKmh(double? value) {
    _forcedWindKmh = value;
    _tick();
    notifyListeners();
  }

  void setSimulatedHour(double? hour) {
    _simulatedHour = hour;
    _initForecast();
    _tick();
    notifyListeners();
  }

  /// Retorna la hora solar efectiva en UTC-6
  double _getCurrentSolarHour(DateTime nowUtc6) {
    if (_simulatedHour != null) {
      return _simulatedHour!.clamp(0.0, 23.99);
    }
    return nowUtc6.hour + nowUtc6.minute / 60.0 + nowUtc6.second / 3600.0;
  }

  void _tick() {
    final nowUtc6 = DateTime.now().toUtc().subtract(const Duration(hours: 6));
    final double solarHour = _getCurrentSolarHour(nowUtc6);

    // Definición astronómica del ciclo diario en HeliOs (06:30 a 18:30)
    const double sunrise = 6.5;
    const double sunset = 18.5;
    final bool isNightTime = solarHour < sunrise || solarHour >= sunset;

    // Cálculo de elevación solar y GHI
    double elevation = 0.0;
    double ghi = 0.0;
    double progress = 0.0;

    if (!isNightTime) {
      progress = (solarHour - sunrise) / (sunset - sunrise); // 0.0 a 1.0
      elevation = math.sin(progress * math.pi) * 72.0; // Elevación máxima 72°
      // Curva sinusoidal de irradiancia Clear Sky con sutil microvariación dinámica
      final double microVariation = 1.0 + (_random.nextDouble() - 0.5) * 0.015;
      ghi = (960.0 * math.pow(math.sin(progress * math.pi), 1.15) * microVariation).clamp(0.0, 1050.0);
    }

    // Modelo térmico del inversor y celdas fotovoltaicas
    final double tempAir = isNightTime ? 16.5 : (18.0 + 11.0 * math.sin(progress * math.pi));
    final double tempCell = isNightTime ? tempAir : (tempAir + (ghi / 800.0) * 26.0);
    final double tempDerating = 1.0 - 0.0038 * (tempCell - 25.0);

    // Potencia Esperada (SPA + Modelo Planta)
    double pExp = 0.0;
    if (ghi > 0.0) {
      pExp = (pPeak * (ghi / 1000.0) * tempDerating).clamp(0.0, pPeak);
    }

    // Potencia Real (con 97.3% de rendimiento de conversión del inversor)
    double pReal = 0.0;
    if (pExp > 0.0) {
      final double noise = 1.0 + (_random.nextDouble() - 0.5) * 0.008;
      pReal = (pExp * 0.973 * noise).clamp(0.0, pPeak);
    }

    // Voltajes y Corrientes DC (18 paneles en serie, 4 cadenas en paralelo)
    double vDc = 0.0;
    double vExp = 0.0;
    double iDc = 0.0;
    double iExp = 0.0;

    if (pReal > 0.0) {
      vExp = (740.0 - 1.8 * (tempCell - 25.0)).clamp(450.0, 820.0);
      final double vNoise = (_random.nextDouble() - 0.5) * 2.0;
      vDc = (vExp + vNoise).clamp(440.0, 830.0);
      iDc = pReal / vDc;
      iExp = pExp / vExp;
    }

    // Temperatura interna del Inversor
    final double tempInverter = tempAir + (pReal > 0 ? (pReal / pPeak) * 22.0 : 4.0);

    // Integración de Energía Diaria acumulada (kWh)
    double yieldToday = 0.0;
    if (solarHour >= sunrise) {
      final double elapsedDayHours = math.min(solarHour, sunset) - sunrise;
      // Aproximación integral del área bajo la curva senoidal
      final double totalDayPotentialKwh = 215.0; // kWh típicos en día despejado
      final double dayFactor = (1.0 - math.cos(elapsedDayHours / 12.0 * math.pi)) / 2.0;
      yieldToday = totalDayPotentialKwh * dayFactor;
    }

    // Seguidor Solar de 1 Eje (SAT)
    // Rango: -45° (Este) en la mañana -> 0° (Zenith) al mediodía -> +45° (Oeste) en la tarde
    double calculatedTargetAngle = 0.0;
    if (!isNightTime) {
      calculatedTargetAngle = (progress - 0.5) * 90.0;
    }

    // Viento
    if (_forcedWindKmh != null) {
      _windKmh = _forcedWindKmh!;
    } else {
      // Variación orgánica suave de brisa (11.5 a 15.5 km/h)
      final double windDelta = (_random.nextDouble() - 0.5) * 0.4;
      _windKmh = (_windKmh + windDelta).clamp(11.0, 16.5);
    }

    // Lógica de Estiba (Flat-Stow a 0°)
    final bool windEmergency = _windKmh >= 50.0;
    final bool activeStow = _manualStow || isNightTime || windEmergency;
    final double finalTargetAngle = activeStow ? 0.0 : calculatedTargetAngle;

    // Movimiento suave del actuador mecánico hacia el ángulo objetivo
    final double angleDiff = finalTargetAngle - _currentTrackerAngle;
    if (angleDiff.abs() > 0.1) {
      _currentTrackerAngle += angleDiff.sign * math.min(0.35, angleDiff.abs());
    } else {
      _currentTrackerAngle = finalTargetAngle;
    }

    // Estado del tiempo (Weather State)
    final String currentWState = isNightTime ? 'clear_night' : 'sunny';
    final int currentCloud = isNightTime ? 0 : 8;

    // Actualizar mapas de datos
    _telemetryData['power_w'] = double.parse(pReal.toStringAsFixed(1));
    _telemetryData['v_dc'] = double.parse(vDc.toStringAsFixed(1));
    _telemetryData['i_dc'] = double.parse(iDc.toStringAsFixed(2));
    _telemetryData['yield_kwh'] = double.parse(yieldToday.toStringAsFixed(1));
    _telemetryData['temp_c'] = double.parse(tempInverter.toStringAsFixed(1));
    _telemetryData['fault'] = 0;
    _telemetryData['wind_kmh'] = double.parse(_windKmh.toStringAsFixed(1));

    _spaData['p_exp'] = double.parse(pExp.toStringAsFixed(1));
    _spaData['v_exp'] = double.parse(vExp.toStringAsFixed(1));
    _spaData['i_exp'] = double.parse(iExp.toStringAsFixed(2));
    _spaData['ghi'] = double.parse(ghi.toStringAsFixed(1));
    _spaData['target_angle'] = double.parse(finalTargetAngle.toStringAsFixed(1));
    _spaData['motor_angle'] = double.parse(finalTargetAngle.toStringAsFixed(1));
    _spaData['motor_azimuth'] = double.parse((90.0 + progress * 180.0).toStringAsFixed(1));
    _spaData['motor_elevation'] = double.parse(elevation.toStringAsFixed(1));
    _spaData['is_stow'] = activeStow;
    _spaData['is_night'] = isNightTime;
    _spaData['weather_state'] = currentWState;
    _spaData['cloud_cover'] = currentCloud;
    _spaData['system_time'] = '${nowUtc6.hour.toString().padLeft(2, '0')}:${nowUtc6.minute.toString().padLeft(2, '0')}:${nowUtc6.second.toString().padLeft(2, '0')}';

    _trackerData['current_angle'] = double.parse(_currentTrackerAngle.toStringAsFixed(1));

    if (windEmergency) {
      _scadaData['code'] = 104;
      _scadaData['description'] = 'Alerta de Viento Peligroso - Estiba de Emergencia Activada (0°)';
    } else {
      _scadaData['code'] = 0;
      _scadaData['description'] = 'Operación Normal';
    }

    // Agregar punto en tiempo real para la gráfica
    _livePowerPoints.add({
      'p_exp': pExp,
      'p_real': pReal,
    });
    if (_livePowerPoints.length > 50) {
      _livePowerPoints.removeAt(0);
    }

    notifyListeners();
  }

  /// Precarga el buffer con puntos de los últimos minutos para que la gráfica no inicie vacía
  void _prefillLivePowerBuffer() {
    _livePowerPoints.clear();
    final nowUtc6 = DateTime.now().toUtc().subtract(const Duration(hours: 6));
    final double currentHour = _getCurrentSolarHour(nowUtc6);

    for (int i = 30; i >= 1; i--) {
      final double pastHour = currentHour - (i * (2.0 / 3600.0));
      double ghi = 0.0;
      if (pastHour >= 6.5 && pastHour < 18.5) {
        final double progress = (pastHour - 6.5) / 12.0;
        ghi = 960.0 * math.pow(math.sin(progress * math.pi), 1.15);
      }
      final double pExp = ghi > 0 ? (pPeak * (ghi / 1000.0) * 0.95) : 0.0;
      final double pReal = pExp > 0 ? (pExp * 0.973) : 0.0;
      _livePowerPoints.add({
        'p_exp': pExp,
        'p_real': pReal,
      });
    }
  }

  /// Inicializa 24 horas continuas de pronóstico a partir de la hora actual
  void _initForecast() {
    final nowUtc6 = DateTime.now().toUtc().subtract(const Duration(hours: 6));
    final List<dynamic> list = [];

    final months = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

    for (int i = 0; i < 24; i++) {
      final dt = nowUtc6.add(Duration(hours: i));
      final double hour = dt.hour.toDouble();

      double ghi = 0.0;
      String wState = 'clear_night';
      int cloud = 0;

      if (hour >= 6.5 && hour < 18.5) {
        final double progress = (hour - 6.5) / 12.0;
        ghi = 960.0 * math.pow(math.sin(progress * math.pi), 1.15);
        wState = (i % 5 == 2) ? 'partly_cloudy' : 'sunny';
        cloud = (i % 5 == 2) ? 25 : 5;
      }

      final double pExp = ghi > 0 ? (pPeak * (ghi / 1000.0) * 0.94) : 0.0;

      list.add({
        'hora': dt.toIso8601String(),
        'hora_str': '${dt.hour.toString().padLeft(2, '0')}:00',
        'fecha_str': '${dt.day} ${months[dt.month - 1]}',
        'timestamp_epoch': dt.millisecondsSinceEpoch ~/ 1000,
        'ghi': double.parse(ghi.toStringAsFixed(1)),
        'p_exp': double.parse(pExp.toStringAsFixed(1)),
        'weather_state': wState,
        'cloud_cover': cloud,
      });
    }

    _forecastData = list;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
