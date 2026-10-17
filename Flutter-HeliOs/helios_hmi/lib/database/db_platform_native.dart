import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

bool _sqliteInitialized = false;

void initDatabasePlatform() {
  if (_sqliteInitialized) return;
  _sqliteInitialized = true;

  // PUENTE Yocto-Linux: Obligamos a Dart a leer la librería de Runtime de Yocto
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {
      // Si falla, enlazamos a la librería exacta que Yocto instala por defecto
      return DynamicLibrary.open('libsqlite3.so.0');
    }
  });
}

Future<CommonDatabase?> openAppDatabase(String dbPath) async {
  initDatabasePlatform();
  final file = File(dbPath);
  if (!file.existsSync()) {
    return null; // Retorna null para disparar los datos simulados
  }
  return sql.sqlite3.open(dbPath);
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