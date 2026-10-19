import 'dart:convert';
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
  try {
    final configFile = File('/data/wifi_config.json');
    if (!configFile.existsSync()) {
      return true;
    }
    final content = configFile.readAsStringSync().trim();
    if (content.isEmpty) {
      return true;
    }
    final Map<String, dynamic> data = json.decode(content);
    final ssid = data['ssid']?.toString().trim();
    if (ssid == null || ssid.isEmpty) {
      return true;
    }
    return false;
  } catch (_) {
    // Si hubo una excepción temporal de lectura/parseo pero el archivo existe, no forzar modo aprovisionamiento
    final configFile = File('/data/wifi_config.json');
    return !configFile.existsSync();
  }
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

bool writeConfigFile(String path, String content) {
  try {
    final file = File(path);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    // Escritura atómica vía archivo temporal
    final tmpPath = '$path.tmp';
    final tmpFile = File(tmpPath);
    tmpFile.writeAsStringSync(content);
    try {
      Process.runSync('chmod', ['666', tmpPath]);
    } catch (_) {}
    tmpFile.renameSync(path);
    try {
      Process.runSync('chmod', ['666', path]);
    } catch (_) {}
    return true;
  } catch (_) {
    try {
      final file = File(path);
      file.writeAsStringSync(content);
      try {
        Process.runSync('chmod', ['666', path]);
      } catch (_) {}
      return true;
    } catch (_) {
      return false;
    }
  }
}

Future<List<String>> scanWifiNetworks() async {
  try {
    final result = await Process.run(
      'sh',
      ['-c', "iw dev wlan0 scan 2>/dev/null | grep 'SSID:' | sed 's/.*SSID: //' | sort -u"],
    );
    if (result.exitCode == 0 && result.stdout is String) {
      final lines = (result.stdout as String)
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && !s.contains('\x00'))
          .toList();
      return lines;
    }
  } catch (_) {}
  return [];
}

Future<bool> reconnectWifiHot() async {
  try {
    await Process.start('/usr/bin/helios-network-manager.sh', ['--force-reconnect'], mode: ProcessStartMode.detached);
    return true;
  } catch (_) {
    try {
      await Process.start('sh', ['-c', '/usr/bin/helios-network-manager.sh --force-reconnect &'], mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }
}

Future<bool> checkWifiConnected() async {
  try {
    final result = await Process.run(
      'sh',
      ['-c', 'ip -4 a show wlan0 | grep "inet " | grep -v "192.168.4.1" | grep -qv "169.254"'],
    );
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<bool> isCaptivePortalRunning() async {
  try {
    final result = await Process.run(
      'sh',
      ['-c', 'pgrep -f portal.py || pgrep hostapd'],
    );
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<bool> launchCaptivePortalService() async {
  try {
    await Process.start('/usr/bin/helios-network-manager.sh', [], mode: ProcessStartMode.detached);
    return true;
  } catch (_) {
    try {
      await Process.start('sh', ['-c', '/usr/bin/helios-network-manager.sh &'], mode: ProcessStartMode.detached);
      return true;
    } catch (_) {
      return false;
    }
  }
}

Future<void> rebootSystem() async {
  try {
    await Process.run('sh', ['-c', 'sync && reboot']);
  } catch (_) {}
}

Future<void> resetToProvisioningMode() async {
  try {
    final file = File('/data/wifi_config.json');
    if (file.existsSync()) {
      file.deleteSync();
    }
  } catch (_) {}
  try {
    await Process.run('sh', ['-c', 'rm -f /data/wifi_config.json && sync && reboot']);
  } catch (_) {}
}