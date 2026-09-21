import 'dart:async';

import 'package:sqlite3/common.dart' as sql;
import 'package:helios_hmi/database/db_platform.dart'; 
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/mqtt_service.dart';

class ScadaErrorRecord {
  final String timestamp;
  final int code;
  final String description;

  ScadaErrorRecord({
    required this.timestamp,
    required this.code,
    required this.description,
  });
}

class ScadaErrorsScreen extends StatefulWidget {
  const ScadaErrorsScreen({super.key});

  @override
  State<ScadaErrorsScreen> createState() => _ScadaErrorsScreenState();
}

class _ScadaErrorsScreenState extends State<ScadaErrorsScreen> {
  static const String _dbPath = '/data/helios_history.db';
  List<ScadaErrorRecord> _errorLogs = [];
  bool _isLoading = false;
  bool _isUsingFallback = false;
  Timer? _refreshTimer;

  static const Color _bgColor = Color(0xFF131B2A);
  static const Color _cardColor = Color(0xFF1E293B);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _accentBlue = Color(0xFF38BDF8);

  @override
  void initState() {
    super.initState();
    _loadHistoricalErrors();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadHistoricalErrors();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _loadHistoricalErrors() async {
    setState(() => _isLoading = true);
    sql.CommonDatabase? db;

    try {
      db = await openAppDatabase(_dbPath);

      if (db == null) {
        _loadFallbackData();
        return;
      }

      final sql.ResultSet resultSet = db.select(
        'SELECT timestamp, code, description FROM scada_errors ORDER BY timestamp DESC;',
      );

      final List<ScadaErrorRecord> loaded = [];
      for (final sql.Row row in resultSet) {
        loaded.add(
          ScadaErrorRecord(
            timestamp: row['timestamp']?.toString() ?? '--',
            code: (row['code'] as num?)?.toInt() ?? 0,
            description:
                row['description']?.toString() ?? 'Falla no especificada',
          ),
        );
      }

      setState(() {
        _errorLogs = loaded;
        _isUsingFallback = false;
        _isLoading = false;
      });
    } catch (_) {
      _loadFallbackData();
    } finally {
      db?.dispose();
    }
  }

  void _loadFallbackData() {
    final mockData = [
      ScadaErrorRecord(
        timestamp: '2026-09-16 18:45:12',
        code: 13,
        description: 'Fuga a Tierra Detectada (DC)',
      ),
      ScadaErrorRecord(
        timestamp: '2026-09-16 15:20:04',
        code: 14,
        description: 'Sobrecalentamiento del Inversor',
      ),
      ScadaErrorRecord(
        timestamp: '2026-09-16 11:05:49',
        code: 20,
        description: 'Falla de Arco Eléctrico',
      ),
      ScadaErrorRecord(
        timestamp: '2026-09-15 13:12:30',
        code: 1,
        description: 'Sobrevoltaje de Red (AC)',
      ),
    ];

    setState(() {
      _errorLogs = mockData;
      _isUsingFallback = true;
      _isLoading = false;
    });
  }

  Color _getSeverityColor(int code) {
    if (code == 13 || code == 20 || code == 21 || code == 32) {
      return Colors.redAccent;
    } else if (code == 14 || code == 1 || code == 2) {
      return Colors.orangeAccent;
    }
    return Colors.amberAccent;
  }

  String _formatTimestamp(String raw) {
    try {
      final parsed = DateTime.parse(raw);
      final y = parsed.year.toString().padLeft(4, '0');
      final m = parsed.month.toString().padLeft(2, '0');
      final d = parsed.day.toString().padLeft(2, '0');
      final h = parsed.hour.toString().padLeft(2, '0');
      final min = parsed.minute.toString().padLeft(2, '0');
      final s = parsed.second.toString().padLeft(2, '0');
      return '$y-$m-$d $h:$min:$s';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mqttService = context.watch<MqttService>();
    final scada = mqttService.scadaData;
    final int activeCode = (scada['code'] as num?)?.toInt() ?? 0;
    final String activeDesc =
        scada['description'] as String? ?? 'Operación Normal';
    final bool hasActiveAlarm = activeCode != 0;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: const Text(
          'Bitácora de Errores SCADA',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _accentBlue,
                    ),
                  )
                : const Icon(Icons.refresh, color: _accentBlue),
            tooltip: 'Recargar bitácora',
            onPressed: _isLoading ? null : _loadHistoricalErrors,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isUsingFallback)
              Container(
                margin: const EdgeInsets.only(bottom: 12.0),
                padding: const EdgeInsets.symmetric(
                  vertical: 6.0,
                  horizontal: 12.0,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.shade900.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amberAccent.withValues(alpha: 0.6),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.amberAccent,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Modo Mock Data activo: No se detectó /data/helios_history.db',
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: hasActiveAlarm
                          ? Colors.red.shade900.withValues(alpha: 0.4)
                          : _cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hasActiveAlarm
                            ? Colors.redAccent
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasActiveAlarm
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline,
                          color: hasActiveAlarm
                              ? Colors.redAccent
                              : Colors.greenAccent,
                          size: 34,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Falla Activa Actual',
                                style: TextStyle(
                                  color: _textMuted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                hasActiveAlarm
                                    ? 'CÓDIGO $activeCode: ${activeDesc.toUpperCase()}'
                                    : 'SIN ALARMAS ACTIVAS',
                                style: TextStyle(
                                  color: hasActiveAlarm
                                      ? Colors.redAccent
                                      : Colors.greenAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: _cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total de Eventos',
                          style: TextStyle(color: _textMuted, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_errorLogs.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Histórico de Alarmas Registradas',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _errorLogs.isEmpty
                  ? Center(
                      child: Container(
                        padding: const EdgeInsets.all(32.0),
                        decoration: BoxDecoration(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              color: _textMuted,
                              size: 48,
                            ),
                            SizedBox(height: 12),
                            Text(
                              'No se registran eventos de error en el historial',
                              style: TextStyle(
                                color: _textMuted,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _errorLogs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final record = _errorLogs[index];
                        final severityColor = _getSeverityColor(record.code);

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 12.0,
                          ),
                          decoration: BoxDecoration(
                            color: _cardColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border(
                              left: BorderSide(color: severityColor, width: 4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: severityColor.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: severityColor.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  'CÓDIGO ${record.code}',
                                  style: TextStyle(
                                    color: severityColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      record.description,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatTimestamp(record.timestamp),
                                      style: const TextStyle(
                                        color: _textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: _textMuted.withValues(alpha: 0.5),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
