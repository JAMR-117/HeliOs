import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService extends ChangeNotifier {
  MqttServerClient? _client;

  // Mapas de memoria reactiva
  Map<String, dynamic> spaData = {};
  Map<String, dynamic> scadaData = {};
  Map<String, dynamic> telemetryData = {}; // NUEVO: Datos crudos SunSpec
  bool isConnected = false;

  Future<void> connect(String serverIp) async {
    // Usamos el ID de cliente HMI
    _client = MqttServerClient(serverIp, 'HeliOs_HMI_Client');
    _client!.port = 1883;
    _client!.keepAlivePeriod = 20;
    _client!.onDisconnected = _onDisconnected;

    final connMess = MqttConnectMessage().startClean().withWillQos(
      MqttQos.atLeastOnce,
    );
    _client!.connectionMessage = connMess;

    try {
      await _client!.connect();
    } catch (e) {
      _client!.disconnect();
      return;
    }

    if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
      isConnected = true;
      notifyListeners();

      // Suscripciones a la topología completa
      _client!.subscribe('helios/spa/coordinates', MqttQos.atMostOnce);
      _client!.subscribe('helios/scada/alerts', MqttQos.atMostOnce);
      _client!.subscribe(
        'helios/inverter/telemetry',
        MqttQos.atMostOnce,
      ); // NUEVO

      _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final recMess = c[0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(
          recMess.payload.message,
        );
        final topic = c[0].topic;

        _parseTelemetry(topic, payload);
      });
    }
  }

  void _parseTelemetry(String topic, String payload) {
    try {
      final data = json.decode(payload);
      if (topic == 'helios/spa/coordinates') {
        spaData = data;
      } else if (topic == 'helios/scada/alerts') {
        scadaData = data;
      } else if (topic == 'helios/inverter/telemetry') {
        telemetryData = data; // Guardamos el JSON de Streamlit
      }
      notifyListeners();
    } catch (e) {
      // Failsafe: tramas corruptas se ignoran
    }
  }

  void _onDisconnected() {
    isConnected = false;
    notifyListeners();
  }
}
