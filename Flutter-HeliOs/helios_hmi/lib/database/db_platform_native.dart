import 'dart:io';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

Future<CommonDatabase?> openAppDatabase(String dbPath) async {
  final file = File(dbPath);
  if (!file.existsSync()) {
    return null; // Retorna null para disparar los datos simulados
  }
  return sql.sqlite3.open(dbPath);
}