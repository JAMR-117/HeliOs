import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

bool _sqliteInitialized = false;

void initDatabasePlatform() {
  if (_sqliteInitialized) return;
  _sqliteInitialized = true;

  // PUENTE Yocto-Linux: Carga garantizada de la librería de SQLite en ARM64 / Linux
  open.overrideFor(OperatingSystem.linux, () {
    const candidatePaths = [
      'libsqlite3.so.0',
      '/usr/lib/libsqlite3.so.0',
      '/usr/lib64/libsqlite3.so.0',
      'libsqlite3.so',
      '/usr/lib/libsqlite3.so',
      '/usr/lib/aarch64-linux-gnu/libsqlite3.so.0',
    ];

    for (final path in candidatePaths) {
      try {
        return DynamicLibrary.open(path);
      } catch (_) {}
    }
    // Fallback estándar por defecto
    return DynamicLibrary.process();
  });
}

Future<CommonDatabase?> openAppDatabase(String dbPath) async {
  initDatabasePlatform();
  final file = File(dbPath);
  if (!file.existsSync()) {
    return null;
  }
  try {
    return sql.sqlite3.open(dbPath);
  } catch (_) {
    return null;
  }
}

bool isProvisioningFileMissing() {
  final configFile = File('/data/wifi_config.json');
  return !configFile.existsSync();
}

String? readConfigFile(String path) {
  try {
    final file = File(path);
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  } catch (_) {}
  return null;
}