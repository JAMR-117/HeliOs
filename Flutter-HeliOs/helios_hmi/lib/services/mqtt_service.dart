import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import '../database/db_platform.dart';
import 'mqtt_client_factory.dart';

class MqttService extends ChangeNotifier {
  MqttClient? _client;
  bool isConnected = false;

  DateTime? _lastInverterPacketTime;
  Timer? _inverterWatchdogTimer;
  bool _inverterActive = false;

  /// Retorna true si se ha recibido telemetría del inversor en los últimos 15 segundos.
  bool get isInverterConnected => _inverterActive;

  MqttService() {
    _startInverterWatchdog();
  }

  void _startInverterWatchdog() {
    _inverterWatchdogTimer?.cancel();
    _inverterWatchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_lastInverterPacketTime != null) {
        final diff = DateTime.now().difference(_lastInverterPacketTime!).inSeconds;
        final bool shouldBeActive = diff <= 15;
        if (_inverterActive != shouldBeActive) {
          _inverterActive = shouldBeActive;
          notifyListeners();
        }
      } else {
        if (_inverterActive) {
          _inverterActive = false;
          notifyListeners();
        }
      }
    });
  }

  Map<String, dynamic> telemetryData = {};
  Map<String, dynamic> spaData = {};
  Map<String, dynamic> trackerData = {};
  Map<String, dynamic> scadaData = {
    "code": 0,
    "description": "Operación Normal",
  };

  DateTime? _lastTrackerPacketTime;
  bool get isTrackerConnected =>
      _lastTrackerPacketTime != null &&
      DateTime.now().difference(_lastTrackerPacketTime!).inSeconds <= 15;

  double? _environmentWind;
  bool manualStow = false;

  /// Ángulo objetivo calculado por el algoritmo solar (SAT)
  double get targetAngle =>
      (spaData['target_angle'] as num?)?.toDouble() ??
      (spaData['motor_angle'] as num?)?.toDouble() ??
      0.0;

  /// Estado de Estiba (Flat-Stow a 0.0°)
  bool get isStow =>
      (spaData['is_stow'] as bool?) ??
      manualStow ||
      (targetAngle == 0.0 && isNight);

  /// Ángulo actual de los paneles fotovoltaicos
  double get currentAngle {
    if (isTrackerConnected && trackerData.containsKey('current_angle')) {
      return (trackerData['current_angle'] as num).toDouble();
    }
    return targetAngle;
  }

  /// Velocidad del viento activa (con prioridad al sensor/simulador externo)
  double get windKmh {
    if (telemetryData.containsKey('wind_kmh')) {
      return (telemetryData['wind_kmh'] as num).toDouble();
    }
    if (_environmentWind != null) {
      return _environmentWind!;
    }
    if (spaData.containsKey('wind_kmh')) {
      return (spaData['wind_kmh'] as num).toDouble();
    }
    return 12.0;
  }

  // --- OVERRIDE TEMPORAL DE CLIMA (DESDE SIMULADOR) ---
  String? _overrideWeatherState;
  int? _overrideCloudCover;
  Timer? _overrideTimer;
  bool get isWeatherOverridden => _overrideWeatherState != null;

  String get weatherState {
    if (_overrideWeatherState != null) {
      return _overrideWeatherState!;
    }
    final state = spaData['weather_state'] as String?;
    if (state != null && state.isNotEmpty) {
      return state;
    }
    return isNight ? 'clear_night' : 'sunny';
  }

  int get cloudCover {
    if (_overrideCloudCover != null) {
      return _overrideCloudCover!;
    }
    return (spaData['cloud_cover'] as num?)?.toInt() ?? 0;
  }

  /// Retorna si el sistema debe renderizarse en Modo Noche (oscuro).
  /// El tema ahora es 100% automático gobernado por el clima activo:
  /// - Si hay override de clima activo, respeta dicho estado.
  /// - Si spaData tiene 'is_night', respeta la efeméride astronómica.
  /// - Si aún no hay spaData, infiere según la hora actual en UTC-6 (06:30 a 18:30 es día).
  bool get isNight {
    if (_overrideWeatherState != null) {
      return _overrideWeatherState == 'clear_night' ||
          _overrideWeatherState == 'cloudy_night';
    }
    if (spaData.containsKey('is_night')) {
      return spaData['is_night'] as bool? ?? false;
    }
    final nowUtc6 = DateTime.now().toUtc().subtract(const Duration(hours: 6));
    final hourMinute = nowUtc6.hour * 60 + nowUtc6.minute;
    // Día: 06:30 (390 min) hasta 18:30 (1110 min)
    return hourMinute < 390 || hourMinute >= 1110;
  }

  // --- BITÁCORA DE ERRORES EN MEMORIA (SESIÓN ACTUAL) ---
  final List<Map<String, dynamic>> sessionErrors = [];

  // --- BUFFER EN TIEMPO REAL DE POTENCIA PARA LA GRÁFICA ---
  // Almacena puntos recientes: {'p_exp': ..., 'p_real': ...}
  final List<Map<String, double>> livePowerPoints = [];

  String? get systemTime => spaData['system_time'] as String?;
  String? get systemTimeFull => spaData['system_time_full'] as String?;

  String _formatTimestamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }

  void _recordSessionError(int code, String description) {
    if (code == 0) return;
    if (sessionErrors.isNotEmpty && sessionErrors.first['code'] == code) {
      return; // No duplicar si es la misma alarma continua
    }
    final nowUtc6 = DateTime.now().toUtc().subtract(const Duration(hours: 6));
    final String tsStr = _formatTimestamp(nowUtc6);
    sessionErrors.insert(0, {
      'timestamp': tsStr,
      'code': code,
      'description': description,
    });
    // Limitar tamaño de bitácora en memoria
    if (sessionErrors.length > 100) {
      sessionErrors.removeLast();
    }
    _persistErrorToDb(tsStr, code, description);
  }

  void _persistErrorToDb(String timestamp, int code, String description) async {
    try {
      final db = await openAppDatabase('/data/helios_history.db');
      if (db != null) {
        db.execute(
          'INSERT INTO scada_errors (timestamp, code, description) VALUES (?, ?, ?)',
          [timestamp, code, description],
        );
        db.dispose();
      }
    } catch (_) {}
  }

  void _checkAnalyticalAnomalies() {
    final double vDc = (telemetryData['v_dc'] as num?)?.toDouble() ?? 0.0;
    final double powerW = (telemetryData['power_w'] as num?)?.toDouble() ?? 0.0;
    final double tempC = (telemetryData['temp_c'] as num?)?.toDouble() ?? 0.0;

    final double ghi = (spaData['ghi'] as num?)?.toDouble() ?? 0.0;
    final double vExp = (spaData['v_exp'] as num?)?.toDouble() ?? 0.0;
    final double pExp = (spaData['p_exp'] as num?)?.toDouble() ?? 0.0;

    // Prioridad Absoluta: Alerta por Viento Peligroso (>= 50 km/h) -> Código 104
    if (windKmh >= 50.0) {
      const desc = "Alerta de Viento Peligroso - Estiba de Emergencia Activada (0°)";
      scadaData = {"inverter": 1, "code": 104, "description": desc};
      _recordSessionError(104, desc);
      return;
    }

    // Solo evaluar si hay telemetría activa del inversor
    if (!isInverterConnected && telemetryData.isEmpty) return;

    if (tempC > 65.0) {
      const desc = "Sobrecalentamiento en Inversor (> 65°C)";
      scadaData = {"inverter": 1, "code": 103, "description": desc};
      _recordSessionError(103, desc);
    } else if (!isNight && ghi > 20.0 && vExp > 0.0) {
      if (vDc < vExp * 0.90) {
        const desc = "Pérdida de Panel en Serie Detectada (Caída de Voltaje DC)";
        scadaData = {"inverter": 1, "code": 101, "description": desc};
        _recordSessionError(101, desc);
      } else if (pExp > 50.0 && powerW < pExp * 0.85) {
        const desc = "Sombreo o Suciedad en Arreglo Fotovoltaico (Baja Potencia)";
        scadaData = {"inverter": 1, "code": 102, "description": desc};
        _recordSessionError(102, desc);
      }
    }
  }

  void _recordPowerPoint() {
    final double exp = (spaData['p_exp'] as num?)?.toDouble() ?? 0.0;
    final double? realVal = (telemetryData['power_w'] as num?)?.toDouble();
    final double real = realVal ?? 0.0;

    // Solo registrar si al menos uno es relevante o para mantener la serie
    livePowerPoints.add({
      'p_exp': exp,
      'p_real': real,
    });

    if (livePowerPoints.length > 50) {
      livePowerPoints.removeAt(0);
    }
  }

  Future<void> connect(String brokerIp) async {
    int retryAttempt = 0;
    StreamSubscription? updatesSub;

    void attemptConnect() async {
      try {
        updatesSub?.cancel();
        _client?.disconnect();

        final clientId = 'helios_hmi_${DateTime.now().millisecondsSinceEpoch % 10000}';
        _client = createMqttClient(brokerIp, clientId);
        _client!.keepAlivePeriod = 20;
        _client!.autoReconnect = true;
        _client!.logging(on: false);

        final connMessage = MqttConnectMessage()
            .withClientIdentifier(clientId)
            .startClean()
            .withWillQos(MqttQos.atLeastOnce);
        _client!.connectionMessage = connMessage;

        await _client!.connect();
        isConnected = true;
        retryAttempt = 0;
        notifyListeners();

        _client!.subscribe("helios/inverter/telemetry", MqttQos.atLeastOnce);
        _client!.subscribe("helios/spa/expected", MqttQos.atLeastOnce);
        _client!.subscribe("helios/spa/coordinates", MqttQos.atLeastOnce);
        _client!.subscribe("helios/scada/alerts", MqttQos.atLeastOnce);
        _client!.subscribe("helios/weather/override", MqttQos.atLeastOnce);
        _client!.subscribe("helios/tracker/status", MqttQos.atLeastOnce);
        _client!.subscribe("helios/tracker/command", MqttQos.atLeastOnce);
        _client!.subscribe("helios/environment/wind", MqttQos.atLeastOnce);
        _client!.subscribe("helios/esp32/wifi_config", MqttQos.atLeastOnce);

        updatesSub = _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
          final recMess = c[0].payload as MqttPublishMessage;
          final payload = MqttPublishPayload.bytesToStringAsString(
            recMess.payload.message,
          );
          final topic = c[0].topic;

          try {
            final data = json.decode(payload);
            if (topic == "helios/inverter/telemetry") {
              _lastInverterPacketTime = DateTime.now();
              _inverterActive = true;
              telemetryData = data;
              final int fault = (data['fault'] as num?)?.toInt() ?? 0;
              if (fault != 0) {
                final sunspecNames = {
                  1: "Sobrevoltaje de Red",
                  13: "Fuga a Tierra Detectada",
                  14: "Sobrecalentamiento del Inversor",
                  101: "Pérdida de Panel en Serie Detectada (Caída de Voltaje DC)",
                  102: "Sombreo o Suciedad en Arreglo Fotovoltaico (Baja Potencia)",
                  103: "Sobrecalentamiento en Inversor (> 65°C)",
                  104: "Alerta de Viento Peligroso - Estiba de Emergencia Activada (0°)",
                };
                _recordSessionError(
                  fault,
                  sunspecNames[fault] ?? 'Falla Inversor SunSpec código $fault',
                );
              }
              _checkAnalyticalAnomalies();
              _recordPowerPoint();
            } else if (topic == "helios/spa/expected" ||
                topic == "helios/spa/coordinates") {
              spaData.addAll(data);
              _checkAnalyticalAnomalies();
              _recordPowerPoint();
            } else if (topic == "helios/tracker/status") {
              _lastTrackerPacketTime = DateTime.now();
              trackerData = data;
            } else if (topic == "helios/tracker/command") {
              if (data.containsKey('manual_stow')) {
                manualStow = data['manual_stow'] as bool? ?? false;
              }
            } else if (topic == "helios/environment/wind") {
              if (data.containsKey('wind_kmh')) {
                _environmentWind = (data['wind_kmh'] as num?)?.toDouble();
              }
              _checkAnalyticalAnomalies();
            } else if (topic == "helios/scada/alerts") {
              scadaData = data;
              final int code = (data['code'] as num?)?.toInt() ?? 0;
              final String desc =
                  data['description'] as String? ?? 'Alerta SCADA';
              if (code != 0) {
                _recordSessionError(code, desc);
              }
            } else if (topic == "helios/weather/override") {
              final st = data['weather_state'] as String?;
              final cc = (data['cloud_cover'] as num?)?.toInt() ?? 0;
              final dur = (data['duration_sec'] as num?)?.toInt() ?? 20;
              _overrideWeatherState = st;
              _overrideCloudCover = cc;
              _overrideTimer?.cancel();
              _overrideTimer = Timer(Duration(seconds: dur), () {
                _overrideWeatherState = null;
                _overrideCloudCover = null;
                notifyListeners();
              });
            }
            notifyListeners();
          } catch (_) {}
        });
      } catch (e) {
        isConnected = false;
        notifyListeners();
        _client?.disconnect();
        retryAttempt++;
        // Reintentos ultrarrápidos tras el reinicio: 500ms, luego 1s, luego 2s
        final int delayMs = retryAttempt <= 2 ? 500 : (retryAttempt <= 4 ? 1000 : 2000);
        Future.delayed(Duration(milliseconds: delayMs), attemptConnect);
      }
    }

    attemptConnect();
  }

  void publishTrackerCommand({bool? manualStow, double? targetAngle}) {
    if (_client != null && isConnected) {
      final builder = MqttClientPayloadBuilder();
      final map = <String, dynamic>{};
      if (manualStow != null) {
        this.manualStow = manualStow;
        map['manual_stow'] = manualStow;
      }
      if (targetAngle != null) map['target_angle'] = targetAngle;
      builder.addString(json.encode(map));
      _client!.publishMessage(
        'helios/tracker/command',
        MqttQos.atLeastOnce,
        builder.payload!,
        retain: true,
      );
      notifyListeners();
    }
  }

  void publishEsp32WifiConfig(String ssid, String pass, [String? brokerIp]) {
    if (_client != null && isConnected) {
      final builder = MqttClientPayloadBuilder();
      final map = <String, dynamic>{
        'ssid': ssid,
        'pass': pass,
        if (brokerIp != null && brokerIp.isNotEmpty) 'broker_ip': brokerIp,
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      };
      builder.addString(json.encode(map));
      _client!.publishMessage(
        'helios/esp32/wifi_config',
        MqttQos.atLeastOnce,
        builder.payload!,
        retain: true,
      );
    }
  }

  void publishConfigReload() {
    if (_client != null && isConnected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(json.encode({'action': 'reload'}));
      _client!.publishMessage(
        'helios/config/reload',
        MqttQos.atLeastOnce,
        builder.payload!,
      );
    }
  }

  @override
  void dispose() {
    _inverterWatchdogTimer?.cancel();
    _overrideTimer?.cancel();
    _client?.disconnect();
    super.dispose();
  }
}

