import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/common.dart' as sql;
import 'package:helios_hmi/database/db_platform.dart'; 
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/mqtt_service.dart';
import '../services/web_telemetry_service.dart';
import '../theme/helios_animations.dart';
import '../theme/helios_theme.dart';
import '../theme/weather_palette.dart';

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
  final bool isTab;
  const ScadaErrorsScreen({super.key, this.isTab = false});

  @override
  State<ScadaErrorsScreen> createState() => _ScadaErrorsScreenState();
}

class _ScadaErrorsScreenState extends State<ScadaErrorsScreen> {
  static const String _dbPath = '/data/helios_history.db';
  List<ScadaErrorRecord> _dbErrorLogs = [];
  bool _isLoading = false;
  Timer? _refreshTimer;

  static const Color _accentOrange = HeliosTheme.truffleTrouble;
  static const Color _accentBlue = HeliosTheme.burningFlame;

  @override
  void initState() {
    super.initState();
    _loadHistoricalErrors();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
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
        if (mounted) {
          setState(() {
            _dbErrorLogs = [];
            _isLoading = false;
          });
        }
        return;
      }

      sql.ResultSet? resultSet;
      try {
        resultSet = db.select(
          'SELECT timestamp, code, description FROM scada_errors ORDER BY id DESC, timestamp DESC LIMIT 100;',
        );
      } catch (_) {
        try {
          resultSet = db.select(
            'SELECT timestamp, code, description FROM scada_errors ORDER BY timestamp DESC LIMIT 100;',
          );
        } catch (_) {
          try {
            resultSet = db.select(
              'SELECT timestamp, fault_code AS code, description FROM scada_errors ORDER BY timestamp DESC LIMIT 100;',
            );
          } catch (_) {}
        }
      }

      final List<ScadaErrorRecord> loaded = [];
      if (resultSet != null) {
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
      }

      if (mounted) {
        setState(() {
          _dbErrorLogs = loaded;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _dbErrorLogs = [];
          _isLoading = false;
        });
      }
    } finally {
      db?.dispose();
    }
  }

  Color _getSeverityColor(int code) {
    if (code == 13 || code == 20 || code == 21 || code == 32) {
      return HeliosTheme.truffleTrouble;
    } else if (code == 14 || code == 1 || code == 2 || code >= 100) {
      return HeliosTheme.burningFlame;
    }
    return HeliosTheme.oatmeal;
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
    final webService = kIsWeb ? context.watch<WebTelemetryService>() : null;
    final bool useWeb = kIsWeb &&
        mqttService.telemetryData.isEmpty &&
        mqttService.spaData.isEmpty &&
        webService != null;

    final scada = useWeb ? webService.scadaData : mqttService.scadaData;
    final int activeCode = (scada['code'] as num?)?.toInt() ?? 0;
    final String activeDesc =
        scada['description'] as String? ?? 'Operación Normal';
    final bool hasActiveAlarm = activeCode != 0;

    final String weatherState = useWeb ? webService.weatherState : mqttService.weatherState;
    final bool isNight = useWeb ? webService.isNight : mqttService.isNight;
    final palette = WeatherPalette.getPalette(weatherState, isNight);

    // Paleta cromática adaptativa al clima
    final BoxDecoration rootDecoration = palette.rootDecoration;
    final Color cardColor = palette.cardColor;
    final Color cardBorderColor = palette.cardBorderColor;
    final Color textPrimary = palette.textPrimary;
    final Color textMuted = palette.textMuted;
    final Color appBarItemColor = palette.textPrimary;

    // Fusión de errores SQLite con los errores capturados en memoria durante la sesión
    final List<ScadaErrorRecord> combinedLogs = [];
    final Set<String> seen = {};

    // 1. Agregar errores de sesión en tiempo real (más recientes primero)
    for (final err in mqttService.sessionErrors) {
      final String ts = err['timestamp']?.toString() ?? '';
      final int c = (err['code'] as num?)?.toInt() ?? 0;
      final String d = err['description']?.toString() ?? 'Alerta SCADA';
      final String key = '$ts-$c';
      if (!seen.contains(key)) {
        seen.add(key);
        combinedLogs.add(ScadaErrorRecord(timestamp: ts, code: c, description: d));
      }
    }

    // 2. Agregar registros históricos de SQLite
    for (final rec in _dbErrorLogs) {
      final String key = '${rec.timestamp}-${rec.code}';
      if (!seen.contains(key)) {
        seen.add(key);
        combinedLogs.add(rec);
      }
    }

    return Container(
      decoration: rootDecoration,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: !widget.isTab,
          leading: widget.isTab ? null : BackButton(color: appBarItemColor),
          title: Text(
            'Bitácora de Errores SCADA',
            style: TextStyle(
              color: appBarItemColor,
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
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: hasActiveAlarm
                            ? _accentOrange.withValues(alpha: isNight ? 0.35 : 0.15)
                            : cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: hasActiveAlarm
                              ? _accentOrange
                              : cardBorderColor,
                          width: hasActiveAlarm ? 1.8 : 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isNight ? 0.2 : 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          hasActiveAlarm
                              ? const PulsingGlow(
                                  duration: Duration(milliseconds: 1100),
                                  child: Icon(
                                    Icons.warning_amber_rounded,
                                    color: _accentOrange,
                                    size: 34,
                                  ),
                                )
                              : const Icon(
                                  Icons.check_circle_outline,
                                  color: Color(0xFF10B981),
                                  size: 34,
                                ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Falla Activa Actual',
                                  style: TextStyle(
                                    color: textMuted,
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
                                        ? (isNight ? HeliosTheme.burningFlame : const Color(0xFFDC2626))
                                        : textPrimary,
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
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: cardBorderColor,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isNight ? 0.2 : 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total de Eventos',
                            style: TextStyle(color: textMuted, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${combinedLogs.length}',
                            style: TextStyle(
                              color: textPrimary,
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
              Text(
                'Histórico de Alarmas Registradas',
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: combinedLogs.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.all(32.0),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cardBorderColor),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                color: textMuted,
                                size: 48,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Sin fallas registradas en la bitácora.',
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: combinedLogs.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final record = combinedLogs[index];
                          final severityColor = _getSeverityColor(record.code);

                          return StaggeredEntrance(
                            index: index,
                            child: HoverCard(
                              scaleFactor: 1.015,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16.0,
                                  vertical: 12.0,
                                ),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: cardBorderColor),
                                ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: severityColor.withValues(alpha: isNight ? 0.18 : 0.12),
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
                                        style: TextStyle(
                                          color: textPrimary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatTimestamp(record.timestamp),
                                        style: TextStyle(
                                          color: textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right,
                                  color: textMuted.withValues(alpha: 0.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                      ),
              ),
              SizedBox(height: widget.isTab ? 90 : 12),
            ],
          ),
        ),
      ),
    );
  }
}
