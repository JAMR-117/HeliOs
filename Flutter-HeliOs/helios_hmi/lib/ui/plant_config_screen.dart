import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

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

  static const Color _bgColor = Color(0xFF131B2A);
  static const Color _cardColor = Color(0xFF1E293B);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _accentBlue = Color(0xFF38BDF8);
  static const Color _accentGreen = Color(0xFF10B981);

  @override
  void initState() {
    super.initState();
    _loadPlantConfiguration();
  }

  void _loadPlantConfiguration() {
    setState(() => _isLoading = true);

    try {
      final file = File(_configPath);
      if (!file.existsSync()) {
        _applyFallbackData();
        return;
      }

      final content = file.readAsStringSync();
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

  void _showStowModeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: _cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.amberAccent, size: 28),
              SizedBox(width: 10),
              Text(
                'Modo Estiba (Flat-Stow)',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
          content: const Text(
            'Se enviará un comando preventivo de seguridad al bus de actuación. Los paneles se posicionarán en ángulo plano horizontal (0°) para mitigar cargas mecánicas por viento.',
            style: TextStyle(color: _textMuted, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: _textMuted),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Comando emitido: Arreglo posicionado en Modo Estiba Preventivo',
                    ),
                    backgroundColor: Colors.amber,
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
    final double totalPeakKw = (_serie * _paralelo * _wp) / 1000.0;
    final double totalVoc = _serie * _voc;
    final double totalIsc = _paralelo * _isc;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: const Text(
          'Configuración de Planta',
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
            tooltip: 'Recargar configuración',
            onPressed: _isLoading ? null : _loadPlantConfiguration,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isUsingFallback)
              Container(
                margin: const EdgeInsets.only(bottom: 16.0),
                padding: const EdgeInsets.symmetric(
                  vertical: 8.0,
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
                        'Modo Fallback: Archivo /data/wifi_config.json no detectado. Visualizando parámetros simulados.',
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.all(22.0),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _accentBlue.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'POTENCIA PICO INSTALADA',
                        style: TextStyle(
                          color: _textMuted,
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
                        style: const TextStyle(color: _textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _accentBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
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
            const Text(
              'Red y Comunicación',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.wifi, color: _accentGreen, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SSID Conectado',
                              style: TextStyle(color: _textMuted, fontSize: 11),
                            ),
                            Text(
                              _ssid,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _accentGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'ENLACE ACTIVO',
                          style: TextStyle(
                            color: _accentGreen,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildGatewayMeta('BROKER LOCAL', '127.0.0.1:1883'),
                      _buildGatewayMeta('INTEROP', 'SunSpec Modbus RTU/TCP'),
                      _buildGatewayMeta(
                        'GATEWAY STATUS',
                        'Online / Determinista',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Parámetros Eléctricos del Arreglo',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width > 900 ? 4 : 2,
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
                ),
                _buildArrayMetricCard(
                  'Corriente Cortocircuito',
                  '${_isc.toStringAsFixed(1)} A',
                  'Isc Total: ${totalIsc.toStringAsFixed(1)} A',
                  Icons.electric_meter,
                ),
                _buildArrayMetricCard(
                  'Módulos en Serie',
                  '$_serie paneles',
                  'Por cadena activa',
                  Icons.linear_scale,
                ),
                _buildArrayMetricCard(
                  'Cadenas en Paralelo',
                  '$_paralelo strings',
                  'Arreglo general',
                  Icons.view_column,
                ),
                _buildArrayMetricCard(
                  'Potencia Unitaria',
                  '${_wp.toInt()} Wp',
                  'Módulo Tier 1',
                  Icons.wb_sunny_outlined,
                ),
                _buildArrayMetricCard(
                  'Voltaje Estimado Vmp',
                  '${(totalVoc * 0.81).toStringAsFixed(1)} V',
                  'Punto de máxima potencia',
                  Icons.speed,
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Acciones del Gateway',
              style: TextStyle(
                color: Colors.white,
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
                    label: const Text(
                      'Recargar Configuración',
                      style: TextStyle(color: Colors.white),
                    ),
                    onPressed: _loadPlantConfiguration,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.amber.shade900.withValues(
                        alpha: 0.5,
                      ),
                      foregroundColor: Colors.amberAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(
                          color: Colors.amberAccent,
                          width: 1,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.shield_outlined),
                    label: const Text(
                      'Forzar Modo Estiba',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onPressed: _showStowModeDialog,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildGatewayMeta(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white70,
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
  ) {
    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
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
                  style: const TextStyle(
                    color: _textMuted,
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subValue,
                style: const TextStyle(color: _textMuted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
