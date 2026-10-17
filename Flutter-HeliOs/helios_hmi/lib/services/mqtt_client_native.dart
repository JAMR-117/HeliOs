import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient createMqttClient(String brokerIp, String clientId) {
  final client = MqttServerClient(brokerIp, clientId);
  client.port = 1883;
  return client;
}
