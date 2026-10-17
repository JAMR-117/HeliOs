import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'mqtt_client_factory.dart';

enum DashboardThemeMode { auto, forceDay, forceNight }

class MqttService extends ChangeNotifier {
  MqttClient? _client;
  bool isConnected = false;

  Map<String, dynamic> telemetryData = {};
  Map<String, dynamic> spaData = {};
  Map<String, dynamic> scadaData = {
    "code": 0,
    "description": "Operación Normal",
  };

  // --- MODO DE TEMA CENTRALIZADO ---
  DashboardThemeMode _themeMode = DashboardThemeMode.auto;
  DashboardThemeMode get themeMode => _themeMode;

  void setThemeMode(DashboardThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
    }
  }

  /// Retorna si el sistema debe renderizarse en Modo Noche (oscuro).
  /// Si el tema está en auto:
  /// - Si spaData tiene 'is_night', respeta la efeméride astronómica.
  /// - Si aún no hay spaData, infiere según la hora actual en UTC-6 (06:30 a 18:30 es día).
  bool get isNight {
    switch (_themeMode) {
      case DashboardThemeMode.forceDay:
        return false;
      case DashboardThemeMode.forceNight:
        return true;
      case DashboardThemeMode.auto:
        if (spaData.containsKey('is_night')) {
          return spaData['is_night'] as bool? ?? false;
        }
        final nowUtc6 = DateTime.now().toUtc().subtract(const Duration(hours: 6));
        final hourMinute = nowUtc6.hour * 60 + nowUtc6.minute;
        // Día: 06:30 (390 min) hasta 18:30 (1110 min)
        return hourMinute < 390 || hourMinute >= 1110;
    }
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
    sessionErrors.insert(0, {
      'timestamp': _formatTimestamp(nowUtc6),
      'code': code,
      'description': description,
    });
    // Limitar tamaño de bitácora en memoria
    if (sessionErrors.length > 100) {
      sessionErrors.removeLast();
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
    _client = createMqttClient(brokerIp, 'helios_hmi_client');
    _client!.keepAlivePeriod = 20;
    _client!.autoReconnect = true;
    _client!.logging(on: false);

    final connMessage = MqttConnectMessage()
        .withClientIdentifier('helios_hmi_client')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMessage;

    void attemptConnect() async {
      try {
        await _client!.connect();
        isConnected = true;
        notifyListeners();

        _client!.subscribe("helios/inverter/telemetry", MqttQos.atLeastOnce);
        _client!.subscribe("helios/spa/expected", MqttQos.atLeastOnce);
        _client!.subscribe("helios/spa/coordinates", MqttQos.atLeastOnce);
        _client!.subscribe("helios/scada/alerts", MqttQos.atLeastOnce);

        _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
          final recMess = c[0].payload as MqttPublishMessage;
          final payload = MqttPublishPayload.bytesToStringAsString(
            recMess.payload.message,
          );
          final topic = c[0].topic;

          try {
            final data = json.decode(payload);
            if (topic == "helios/inverter/telemetry") {
              telemetryData = data;
              final int fault = (data['fault'] as num?)?.toInt() ?? 0;
              if (fault != 0) {
                final sunspecNames = {
                  1: "Sobrevoltaje de Red",
                  13: "Fuga a Tierra Detectada",
                  14: "Sobrecalentamiento del Inversor",
                  101: "Pérdida de Panel en Serie",
                  102: "Sombreo o Suciedad en Arreglo",
                  103: "Alerta Térmica: Sobrecalentamiento (>65°C)",
                };
                _recordSessionError(
                  fault,
                  sunspecNames[fault] ?? 'Falla Inversor SunSpec código $fault',
                );
              }
              _recordPowerPoint();
            } else if (topic == "helios/spa/expected" ||
                topic == "helios/spa/coordinates") {
              spaData.addAll(data);
              _recordPowerPoint();
            } else if (topic == "helios/scada/alerts") {
              scadaData = data;
              final int code = (data['code'] as num?)?.toInt() ?? 0;
              final String desc =
                  data['description'] as String? ?? 'Alerta SCADA';
              if (code != 0) {
                _recordSessionError(code, desc);
              }
            }
            notifyListeners();
          } catch (_) {}
        });
      } catch (e) {
        isConnected = false;
        notifyListeners();
        _client?.disconnect();
        Future.delayed(const Duration(seconds: 5), attemptConnect);
      }
    }

    attemptConnect();
  }

  @override
  void dispose() {
    _client?.disconnect();
    super.dispose();
  }
}
