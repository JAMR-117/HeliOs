import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sqlite3/common.dart';
import 'package:sqlite3/wasm.dart' as sql;

void initDatabasePlatform() {
  // En Web la base de datos corre vía WASM / IndexedDB con datos TMY
}

sql.WasmSqlite3? _wasmSqlite;
sql.IndexedDbFileSystem? _indexedDbFs;
bool _fsRegistered = false;

Future<void> _initSqliteWeb() async {
  if (_wasmSqlite != null) return;
  _wasmSqlite = await sql.WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  if (!_fsRegistered) {
    try {
      _indexedDbFs =
          await sql.IndexedDbFileSystem.open(dbName: 'helios_tmy_vfs');
      _wasmSqlite!.registerVirtualFileSystem(_indexedDbFs!, makeDefault: true);
      _fsRegistered = true;
    } catch (_) {
      _fsRegistered = true;
    }
  }
}

Future<void> _populateTmyDatabase(CommonDatabase db) async {
  db.execute('''
    CREATE TABLE IF NOT EXISTS telemetry_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp TEXT NOT NULL,
      p_real REAL NOT NULL,
      p_exp REAL NOT NULL,
      v_dc REAL,
      i_dc REAL,
      ghi REAL,
      temp_c REAL
    );
    CREATE TABLE IF NOT EXISTS scada_errors (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp TEXT NOT NULL,
      code INTEGER NOT NULL,
      description TEXT NOT NULL
    );
  ''');

  try {
    final jsonStr = await rootBundle.loadString('lib/database/tmy_data.json');
    final Map<String, dynamic> data = json.decode(jsonStr);

    db.execute('BEGIN TRANSACTION;');

    final stmt = db.prepare(
      'INSERT INTO telemetry_log (timestamp, p_real, p_exp, v_dc, i_dc, ghi, temp_c) VALUES (?, ?, ?, ?, ?, ?, ?);',
    );

    // Arreglo HeliOs: 18 módulos en serie * 4 cadenas en paralelo * 550 Wp = 39,600 Wp (39.6 kWp)
    const double pPeak = 39600.0;

    for (final entry in data.entries) {
      final String ts = entry.key;
      final Map<String, dynamic> values = entry.value as Map<String, dynamic>;

      final double ghi = (values['ghi'] as num?)?.toDouble() ?? 0.0;
      final double dni = (values['dni'] as num?)?.toDouble() ?? 0.0;
      final double dhi = (values['dhi'] as num?)?.toDouble() ?? 0.0;
      final double tempAir = (values['temp_air'] as num?)?.toDouble() ?? 25.0;

      double pExp = 0.0;
      double pReal = 0.0;
      double vDc = 0.0;
      double iDc = 0.0;

      if (ghi > 0.0) {
        // Modelo térmico fotovoltaico estándar (-0.38% por °C sobre 25°C)
        final double tempFactor = 1.0 - 0.0038 * (tempAir - 25.0);
        // Seguidor solar HeliOs de 2 ejes: aprovecha radiación directa DNI y difusa
        final double effectiveGhi = dni > 0 ? (dni * 0.82 + dhi) : ghi;
        final double irradRatio = (effectiveGhi / 1000.0).clamp(0.0, 1.25);

        pExp = pPeak * irradRatio * tempFactor;
        if (pExp < 0) pExp = 0.0;

        // Rendimiento real del inversor trifásico (97.3%)
        pReal = pExp * 0.973;

        // Tensión de string y corriente continua calculadas
        vDc = (740.0 - 1.8 * (tempAir - 25.0)).clamp(400.0, 850.0);
        iDc = pReal / vDc;
      }

      stmt.execute([
        ts,
        double.parse(pReal.toStringAsFixed(2)),
        double.parse(pExp.toStringAsFixed(2)),
        double.parse(vDc.toStringAsFixed(2)),
        double.parse(iDc.toStringAsFixed(2)),
        double.parse(ghi.toStringAsFixed(2)),
        double.parse(tempAir.toStringAsFixed(2)),
      ]);
    }
    stmt.dispose();

    // Registros SCADA representativos vinculados al histórico TMY
    db.execute('''
      INSERT INTO scada_errors (timestamp, code, description) VALUES
      ('2025-12-30 06:10:00', 0, 'Operación Normal — Salida de modo reposo TMY'),
      ('2025-12-30 13:30:00', 104, 'Seguimiento Solar Óptimo — Pico de Irradiancia TMY'),
      ('2025-12-30 18:40:00', 0, 'Posición de Estiba — Modo Nocturno TMY'),
      ('2025-12-31 06:12:00', 0, 'Operación Normal — Salida de modo reposo TMY'),
      ('2025-12-31 14:15:00', 104, 'Seguimiento Solar Óptimo — Pico de Irradiancia TMY'),
      ('2025-12-31 18:35:00', 0, 'Posición de Estiba — Modo Nocturno TMY');
    ''');

    db.execute('COMMIT;');
  } catch (e) {
    try {
      db.execute('ROLLBACK;');
    } catch (_) {}
  }
}

Future<CommonDatabase?> openAppDatabase(String dbPath) async {
  try {
    await _initSqliteWeb();
    if (_wasmSqlite == null) return null;

    final db = _wasmSqlite!.open(dbPath);

    // Verificar si telemetry_log ya contiene registros
    final checkTables = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='telemetry_log';",
    );

    bool needsInit = false;
    if (checkTables.isEmpty) {
      needsInit = true;
    } else {
      final countResult =
          db.select("SELECT COUNT(*) AS total FROM telemetry_log;");
      final total = (countResult.first['total'] as num?)?.toInt() ?? 0;
      if (total == 0) {
        needsInit = true;
      }
    }

    if (needsInit) {
      await _populateTmyDatabase(db);
    }

    return db;
  } catch (_) {
    return null;
  }
}

bool isProvisioningFileMissing() {
  // En Web iniciamos directo en el Dashboard
  return false;
}

final Map<String, String> _webConfigStore = {};

String? readConfigFile(String path) {
  if (_webConfigStore.containsKey(path)) {
    return _webConfigStore[path];
  }
  if (path == '/data/wifi_config.json') {
    return json.encode({
      'ssid': 'Planta_Industrial_Solar',
      'voc': 49.6,
      'isc': 14.0,
      'wp': 550.0,
      'serie': 18,
      'paralelo': 4,
      'lat': 19.6800,
      'lon': -99.0100,
      'city': 'Ojo de Agua, EdoMex',
    });
  }
  return null;
}

bool writeConfigFile(String path, String content) {
  _webConfigStore[path] = content;
  return true;
}

Future<List<String>> scanWifiNetworks() async {
  return ['HeliOs_Local_Wifi', 'Planta_Solar_Industrial', 'Red_Invitados'];
}

Future<bool> reconnectWifiHot() async {
  return true;
}

Future<bool> checkWifiConnected() async {
  return true;
}

Future<bool> isCaptivePortalRunning() async {
  return true;
}

Future<bool> launchCaptivePortalService() async {
  return true;
}

Future<void> rebootSystem() async {}

Future<void> resetToProvisioningMode() async {}