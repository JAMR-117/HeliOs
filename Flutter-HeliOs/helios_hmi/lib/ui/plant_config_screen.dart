import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/db_platform.dart';
import '../services/mqtt_service.dart';
import '../theme/helios_theme.dart';

class PlantConfigScreen extends StatefulWidget {
  const PlantConfigScreen({super.key});

  @override
  State<PlantConfigScreen> createState() => _PlantConfigScreenState();
}

class _PlantConfigScreenState extends State<PlantConfigScreen> {
  static const String _configPath = '/data/wifi_config.json';

  String _ssid = 'Planta_Industrial_Solar';
  double _voc = 49.6;
  double _isc = 14.0;
  double _wp = 550.0;
  int _serie = 18;
  int _paralelo = 4;

  bool _isLoading = false;
  bool _isUsingFallback = false;

  static const Color _accentBlue = HeliosTheme.burningFlame;
  static const Color _accentOrange = HeliosTheme.truffleTrouble;

  @override
  void initState() {
    super.initState();
    _loadPlantConfiguration();
  }

  void _loadPlantConfiguration() {
    setState(() => _isLoading = true);

    try {
      final content = readConfigFile(_configPath);
      if (content == null) {
        _applyFallbackData();
        return;
      }

      final Map<String, dynamic> data = json.decode(content);

      setState(() {
        _ssid = data['ssid']?.toString() ?? 'Planta_Industrial_Solar';
        _voc = (data['voc'] as num?)?.toDouble() ?? 49.6;
        _isc = (data['isc'] as num?)?.toDouble() ?? 14.0;
        _wp = (data['wp'] as num?)?.toDouble() ?? 550.0;
        _serie = (data['serie'] as num?)?.toInt() ?? 18;
        _paralelo = (data['paralelo'] as num?)?.toInt() ?? 4;
        _isUsingFallback = false;
        _isLoading = false;
      });
    } catch (_) {
      _applyFallbackData();
    }
  }

  void _applyFallbackData() {
    setState(() {
      _ssid = 'Planta_Industrial_Solar';
      _voc = 49.6;
      _isc = 14.0;
      _wp = 550.0;
      _serie = 18;
      _paralelo = 4;
      _isUsingFallback = true;
      _isLoading = false;
    });
  }

  void _showStowModeDialog(BuildContext context, bool isNight) {
    final Color dialogBg = isNight ? const Color(0xFF1E293B) : Colors.white;
    final Color dialogTextPrimary = isNight ? HeliosTheme.palladian : const Color(0xFF0F172A);
    final Color dialogTextMuted = isNight ? HeliosTheme.oatmeal : const Color(0xFF475569);

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isNight
                  ? HeliosTheme.oatmeal.withValues(alpha: 0.2)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          title: Row(
            children: [
              const Icon(Icons.shield_outlined, color: _accentBlue, size: 28),
              const SizedBox(width: 10),
              Text(
                'Modo Estiba (Flat-Stow)',
                style: TextStyle(
                  color: dialogTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Esta operación ordenará a los actuadores mecánicos colocar el arreglo '
                'fotovoltaico en posición horizontal plana (Elevación 90°, Azimut 180°).',
                style: TextStyle(
                  color: dialogTextMuted,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _accentOrange.withValues(alpha: isNight ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _accentOrange.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: _accentOrange, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Protocolo de seguridad por ráfagas de viento o mantenimiento.',
                        style: TextStyle(
                          color: dialogTextPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancelar',
                style: TextStyle(color: dialogTextMuted),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Comando emitido: Arreglo posicionado en Modo Estiba Preventivo',
                      style: TextStyle(color: Colors.white),
                    ),
                    backgroundColor: _accentOrange,
                  ),
                );
              },
              child: const Text('Confirmar Posición'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mqttService = context.watch<MqttService>();
    final bool isNight = mqttService.isNight;

    final Color bgColor = isNight ? const Color(0xFF131B2A) : const Color(0xFFF1F5F9);
    final Gradient? bgGradient = isNight ? HeliosTheme.nightBackgroundGradient : null;
    final Color cardColor = isNight ? const Color(0xFF1E293B) : Colors.white;
    final Color cardBorderColor = isNight
        ? HeliosTheme.oatmeal.withValues(alpha: 0.2)
        : const Color(0xFFE2E8F0);
    final Color textPrimary = isNight ? HeliosTheme.palladian : const Color(0xFF0F172A);
    final Color textMuted = isNight ? HeliosTheme.oatmeal : const Color(0xFF475569);
    final Color appBarItemColor = isNight ? HeliosTheme.palladian : const Color(0xFF0F172A);

    final double totalPeakKw = (_serie * _paralelo * _wp) / 1000.0;
    final double totalVoc = _serie * _voc;
    final double totalIsc = _paralelo * _isc;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: appBarItemColor),
        title: Text(
          'Configuración de Planta',
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
            tooltip: 'Recargar configuración',
            onPressed: _isLoading ? null : _loadPlantConfiguration,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: bgColor,
          gradient: bgGradient,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isUsingFallback)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16.0),
                    padding: const EdgeInsets.symmetric(
                      vertical: 10.0,
                      horizontal: 14.0,
                    ),
                    decoration: BoxDecoration(
                      color: _accentOrange.withValues(alpha: isNight ? 0.25 : 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _accentBlue.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: _accentBlue,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Modo Fallback: Archivo /data/wifi_config.json no detectado. Visualizando parámetros simulados.',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(22.0),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _accentBlue.withValues(alpha: 0.35),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isNight ? 0.2 : 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'POTENCIA PICO INSTALADA',
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${totalPeakKw.toStringAsFixed(1)} kWp',
                            style: const TextStyle(
                              color: _accentBlue,
                              fontSize: 38,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Capacidad teórica calculada: ${_serie * _paralelo} módulos conectados',
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _accentBlue.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _accentBlue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.solar_power,
                          color: _accentBlue,
                          size: 42,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Red y Comunicación',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cardBorderColor,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.wifi, color: _accentBlue, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SSID Conectado',
                                  style: TextStyle(
                                    color: textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  _ssid,
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _accentBlue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _accentBlue.withValues(alpha: 0.4),
                              ),
                            ),
                            child: const Text(
                              'ENLACE ACTIVO',
                              style: TextStyle(
                                color: _accentBlue,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Divider(
                        color: cardBorderColor,
                        height: 24,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildGatewayMeta('BROKER LOCAL', '127.0.0.1:1883', textPrimary, textMuted),
                          _buildGatewayMeta('INTEROP', 'SunSpec Modbus RTU/TCP', textPrimary, textMuted),
                          _buildGatewayMeta(
                            'GATEWAY STATUS',
                            'Online / Determinista',
                            textPrimary,
                            textMuted,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Parámetros Eléctricos del Arreglo',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount:
                      MediaQuery.of(context).size.width > 900 ? 4 : 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.45,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildArrayMetricCard(
                      'Voltaje Circuito Abierto',
                      '${_voc.toStringAsFixed(1)} V',
                      'Voc Total: ${totalVoc.toStringAsFixed(1)} V',
                      Icons.bolt,
                      cardColor,
                      cardBorderColor,
                      textPrimary,
                      textMuted,
                    ),
                    _buildArrayMetricCard(
                      'Corriente Cortocircuito',
                      '${_isc.toStringAsFixed(1)} A',
                      'Isc Total: ${totalIsc.toStringAsFixed(1)} A',
                      Icons.electric_meter,
                      cardColor,
                      cardBorderColor,
                      textPrimary,
                      textMuted,
                    ),
                    _buildArrayMetricCard(
                      'Módulos en Serie',
                      '$_serie paneles',
                      'Por cadena activa',
                      Icons.linear_scale,
                      cardColor,
                      cardBorderColor,
                      textPrimary,
                      textMuted,
                    ),
                    _buildArrayMetricCard(
                      'Cadenas en Paralelo',
                      '$_paralelo strings',
                      'Arreglo general',
                      Icons.view_column,
                      cardColor,
                      cardBorderColor,
                      textPrimary,
                      textMuted,
                    ),
                    _buildArrayMetricCard(
                      'Potencia Unitaria',
                      '${_wp.toInt()} Wp',
                      'Módulo Tier 1',
                      Icons.wb_sunny_outlined,
                      cardColor,
                      cardBorderColor,
                      textPrimary,
                      textMuted,
                    ),
                    _buildArrayMetricCard(
                      'Voltaje Estimado Vmp',
                      '${(totalVoc * 0.81).toStringAsFixed(1)} V',
                      'Punto de máxima potencia',
                      Icons.speed,
                      cardColor,
                      cardBorderColor,
                      textPrimary,
                      textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Acciones del Gateway',
                  style: TextStyle(
                    color: textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(
                            color: _accentBlue.withValues(alpha: 0.6),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.sync, color: _accentBlue),
                        label: Text(
                          'Recargar Configuración',
                          style: TextStyle(color: textPrimary),
                        ),
                        onPressed: _loadPlantConfiguration,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: _accentOrange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(
                              color: _accentBlue,
                              width: 1,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.shield_outlined),
                        label: const Text(
                          'Forzar Modo Estiba',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _showStowModeDialog(context, isNight),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGatewayMeta(String label, String value, Color textPrimary, Color textMuted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildArrayMetricCard(
    String title,
    String mainValue,
    String subValue,
    IconData icon,
    Color cardColor,
    Color cardBorderColor,
    Color textPrimary,
    Color textMuted,
  ) {
    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cardBorderColor,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, color: _accentBlue, size: 18),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mainValue,
                style: TextStyle(
                  color: textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subValue,
                style: TextStyle(color: textMuted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
