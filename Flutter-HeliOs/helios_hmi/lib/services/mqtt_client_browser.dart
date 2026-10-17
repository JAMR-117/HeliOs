import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

MqttClient createMqttClient(String brokerIp, String clientId) {
  // En Web nos conectamos mediante WebSocket al puerto WebSocket del broker (usualmente 9001)
  final client = MqttBrowserClient('ws://$brokerIp', clientId);
  client.port = 9001;
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  return client;
}
