import 'package:sqlite3/common.dart';

void initDatabasePlatform() {}

Future<CommonDatabase?> openAppDatabase(String dbPath) {
  throw UnsupportedError('Plataforma no soportada');
}

bool isProvisioningFileMissing() => false;

String? readConfigFile(String path) => null;
