import 'package:sqlite3/common.dart';
import 'package:sqlite3/wasm.dart' as sql;

sql.WasmSqlite3? _wasmSqlite;

Future<CommonDatabase?> openAppDatabase(String dbPath) async {
  try {
    _wasmSqlite ??= await sql.WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
    final fs = await sql.IndexedDbFileSystem.open(dbName: dbPath);
    _wasmSqlite!.registerVirtualFileSystem(fs, makeDefault: true);

    final db = _wasmSqlite!.open(dbPath);

    // En Web verificamos si existen las tablas; si está vacía retornamos null
    final checkTables = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND (name='telemetry_log' OR name='scada_errors');",
    );
    if (checkTables.isEmpty) {
      db.dispose();
      return null;
    }

    return db;
  } catch (_) {
    return null;
  }
}