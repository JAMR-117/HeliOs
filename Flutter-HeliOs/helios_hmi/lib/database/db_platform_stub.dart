import 'package:sqlite3/common.dart';

void initDatabasePlatform() {}

Future<CommonDatabase?> openAppDatabase(String dbPath) {
  throw UnsupportedError('Plataforma no soportada');
}

bool isProvisioningFileMissing() => false;

String? readConfigFile(String path) => null;

bool writeConfigFile(String path, String content) => false;

Future<List<String>> scanWifiNetworks() async => [];

Future<bool> reconnectWifiHot() async => false;

Future<bool> checkWifiConnected() async => true;

Future<bool> isCaptivePortalRunning() async => true;

Future<bool> launchCaptivePortalService() async => true;

Future<void> rebootSystem() async {}

Future<void> resetToProvisioningMode() async {}
