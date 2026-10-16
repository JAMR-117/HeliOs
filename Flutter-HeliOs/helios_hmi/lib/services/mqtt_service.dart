import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService extends ChangeNotifier {
  MqttServerClient? _client;
  bool isConnected = false;

  Map<String, dynamic> telemetryData = {};
  Map<String, dynamic> spaData = {};
  Map<String, dynamic> scadaData = {
    "code": 0,
    "description": "Operación Normal",
  };

  Future<void> connect(String brokerIp) async {
    _client = MqttServerClient(brokerIp, 'helios_hmi_client');
    _client!.port = 1883;
    _client!.keepAlivePeriod = 20;
    _client!.autoReconnect =
        true; // Habilita reconexión nativa si se cae la red
    _client!.logging(on: false);

    final connMessage = MqttConnectMessage()
        .withClientIdentifier('helios_hmi_client')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    _client!.connectionMessage = connMessage;

    // Bucle interno de reconexión para la carrera de arranque
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
            } else if (topic == "helios/spa/expected" ||
                topic == "helios/spa/coordinates") {
              spaData.addAll(data);
            } else if (topic == "helios/scada/alerts") {
              scadaData = data;
            }
            notifyListeners();
          } catch (_) {}
        });
      } catch (e) {
        isConnected = false;
        notifyListeners();
        _client?.disconnect();
        // Si el broker no está listo en el arranque, reintenta en 5 segundos
        Future.delayed(const Duration(seconds: 5), attemptConnect);
      }
    }

    attemptConnect(); // Inicia el ciclo
  }

  @override
  void dispose() {
    _client?.disconnect();
    super.dispose();
  }
}
