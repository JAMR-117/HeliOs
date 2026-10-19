import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/db_platform.dart';
import '../services/mqtt_service.dart';
import '../theme/helios_theme.dart';
import '../theme/weather_palette.dart';

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
  double _lat = 19.6800;
  double _lon = -99.0100;
  String _city = 'Ojo de Agua, EdoMex';

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
        _lat = (data['lat'] as num?)?.toDouble() ??
            (data['latitud'] as num?)?.toDouble() ??
            19.6800;
        _lon = (data['lon'] as num?)?.toDouble() ??
            (data['longitud'] as num?)?.toDouble() ??
            -99.0100;
        _city = data['city']?.toString() ??
            data['ubicacion']?.toString() ??
            'Ojo de Agua, EdoMex';
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
      _lat = 19.6800;
      _lon = -99.0100;
      _city = 'Ojo de Agua, EdoMex';
      _isUsingFallback = true;
      _isLoading = false;
    });
  }

  void _showChangeWifiDialog(BuildContext context, bool isNight) {
    final Color dialogBg = isNight ? const Color(0xFF1E293B) : Colors.white;
    final Color dialogTextPrimary = isNight ? HeliosTheme.palladian : const Color(0xFF0F172A);
    final Color dialogTextMuted = isNight ? HeliosTheme.oatmeal : const Color(0xFF475569);
    final Color inputFill = isNight ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final Color borderColor = isNight ? HeliosTheme.oatmeal.withValues(alpha: 0.25) : const Color(0xFFCBD5E1);

    final TextEditingController ssidController = TextEditingController(text: _ssid);
    final TextEditingController passController = TextEditingController();

    List<String> discoveredNetworks = [];
    bool isScanning = true;
    bool isPasswordVisible = false;
    bool isConnecting = false;
    String? selectedNetwork;

    showDialog(
      context: context,
      barrierDismissible: !isConnecting,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (isScanning && discoveredNetworks.isEmpty) {
              scanWifiNetworks().then((networks) {
                if (ctx.mounted) {
                  setDialogState(() {
                    discoveredNetworks = networks;
                    isScanning = false;
                  });
                }
              }).catchError((_) {
                if (ctx.mounted) {
                  setDialogState(() {
                    isScanning = false;
                  });
                }
              });
            }

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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _accentBlue.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.wifi_find, color: _accentBlue, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Cambiar Red Wi-Fi',
                      style: TextStyle(
                        color: dialogTextPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isConnecting) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: _accentBlue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _accentBlue.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: _accentBlue),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'Reconectando a "${ssidController.text.trim()}"...\n(verificando enlace en caliente)',
                                style: TextStyle(
                                  color: dialogTextPrimary,
                                  fontSize: 13,
                                  height: 1.3,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Seleccione una red detectada o ingrese las credenciales de la planta:',
                        style: TextStyle(
                          color: dialogTextMuted,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (isScanning) ...[
                      Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _accentBlue),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Buscando redes cercanas (wlan0)...',
                            style: TextStyle(color: dialogTextMuted, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ] else if (discoveredNetworks.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        initialValue: selectedNetwork,
                        decoration: InputDecoration(
                          labelText: 'Redes disponibles',
                          labelStyle: TextStyle(color: dialogTextMuted, fontSize: 12),
                          filled: true,
                          fillColor: inputFill,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: borderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: borderColor),
                          ),
                        ),
                        dropdownColor: dialogBg,
                        style: TextStyle(color: dialogTextPrimary, fontSize: 14),
                        hint: Text('Seleccionar de la lista...', style: TextStyle(color: dialogTextMuted, fontSize: 13)),
                        items: discoveredNetworks.map((net) {
                          return DropdownMenuItem<String>(
                            value: net,
                            child: Row(
                              children: [
                                const Icon(Icons.wifi, size: 16, color: _accentBlue),
                                const SizedBox(width: 8),
                                Text(net),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedNetwork = val;
                              ssidController.text = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: ssidController,
                      style: TextStyle(color: dialogTextPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Nombre de Red (SSID)',
                        labelStyle: TextStyle(color: dialogTextMuted, fontSize: 12),
                        filled: true,
                        fillColor: inputFill,
                        prefixIcon: const Icon(Icons.router, color: _accentBlue, size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: borderColor),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passController,
                      obscureText: !isPasswordVisible,
                      style: TextStyle(color: dialogTextPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Contraseña Wi-Fi',
                        labelStyle: TextStyle(color: dialogTextMuted, fontSize: 12),
                        filled: true,
                        fillColor: inputFill,
                        prefixIcon: const Icon(Icons.lock_outline, color: _accentBlue, size: 20),
                        suffixIcon: IconButton(
                          icon: Icon(
                            isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                            color: dialogTextMuted,
                            size: 20,
                          ),
                          onPressed: () {
                            setDialogState(() {
                              isPasswordVisible = !isPasswordVisible;
                            });
                          },
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: borderColor),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isConnecting ? null : () => Navigator.pop(ctx),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(color: dialogTextMuted),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  icon: isConnecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.wifi_protected_setup, size: 18),
                  label: Text(isConnecting ? 'Verificando...' : 'Guardar y Conectar'),
                  onPressed: isConnecting
                      ? null
                      : () async {
                          final newSsid = ssidController.text.trim();
                          final newPass = passController.text;

                          if (newSsid.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Por favor ingresa un nombre de red (SSID).'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                            return;
                          }

                          final messenger = ScaffoldMessenger.of(context);
                          final navigator = Navigator.of(ctx);
                          setDialogState(() => isConnecting = true);

                          try {
                            Map<String, dynamic> currentConfig = {};
                            final existing = readConfigFile(_configPath);
                            if (existing != null) {
                              try {
                                currentConfig = json.decode(existing);
                              } catch (_) {}
                            }

                            currentConfig['ssid'] = newSsid;
                            currentConfig['pass'] = newPass;

                            writeConfigFile(
                              _configPath,
                              const JsonEncoder.withIndent('  ').convert(currentConfig),
                            );

                            await reconnectWifiHot();

                            // Sondeo de enlace IP en caliente durante hasta 20 segundos
                            bool connected = false;
                            for (int i = 0; i < 10; i++) {
                              await Future.delayed(const Duration(seconds: 2));
                              if (!ctx.mounted) break;
                              connected = await checkWifiConnected();
                              if (connected) break;
                            }

                            if (connected) {
                              if (mounted) {
                                setState(() {
                                  _ssid = newSsid;
                                });
                                navigator.pop();
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Conexión establecida con éxito a "$newSsid"',
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                    backgroundColor: Colors.green,
                                    duration: const Duration(seconds: 4),
                                  ),
                                );
                              }
                            } else {
                              if (ctx.mounted) {
                                setDialogState(() => isConnecting = false);
                                _showWifiConnectionFailedDialog(context, isNight, newSsid);
                              }
                            }
                          } catch (err) {
                            if (ctx.mounted) {
                              setDialogState(() => isConnecting = false);
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Error al guardar Wi-Fi: $err'),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showWifiConnectionFailedDialog(BuildContext context, bool isNight, String targetSsid) {
    final Color dialogBg = isNight ? const Color(0xFF1E293B) : Colors.white;
    final Color dialogTextPrimary = isNight ? HeliosTheme.palladian : const Color(0xFF0F172A);
    final Color dialogTextMuted = isNight ? HeliosTheme.oatmeal : const Color(0xFF475569);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext failCtx) {
        return AlertDialog(
          backgroundColor: dialogBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: Colors.redAccent.withValues(alpha: 0.4),
            ),
          ),
          title: Row(
            children: [
              const Icon(Icons.wifi_off, color: Colors.redAccent, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Fallo de Conexión',
                  style: TextStyle(
                    color: dialogTextPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No fue posible obtener dirección IP en la red "$targetSsid" tras 20 segundos.',
                style: TextStyle(color: dialogTextPrimary, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'Es posible que la contraseña sea incorrecta o la señal esté fuera de alcance. Seleccione una acción:',
                style: TextStyle(color: dialogTextMuted, fontSize: 13, height: 1.3),
              ),
            ],
          ),
          actions: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: dialogTextPrimary,
                side: BorderSide(color: dialogTextMuted.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Reintentar contraseña'),
              onPressed: () {
                Navigator.pop(failCtx); // Cierra la alerta y mantiene abierto el diálogo Wi-Fi
              },
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: HeliosTheme.burningFlame,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.wifi_tethering, size: 16),
              label: const Text('Reiniciar en Modo Aprovisionamiento'),
              onPressed: () async {
                Navigator.pop(failCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Reiniciando equipo en Modo Aprovisionamiento (HeliOs_Setup)...'),
                    backgroundColor: HeliosTheme.burningFlame,
                    duration: Duration(seconds: 4),
                  ),
                );
                await resetToProvisioningMode();
              },
            ),
          ],
        );
      },
    );
  }

  void _showResetProvisioningDialog(BuildContext context, bool isNight) {
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
              const Icon(Icons.warning_amber_rounded, color: HeliosTheme.truffleTrouble, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Restablecer Red de Fábrica',
                  style: TextStyle(
                    color: dialogTextPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            '¿Desea restablecer las credenciales de red? '
            'El equipo eliminará la configuración actual, se reiniciará '
            'y levantará el portal cautivo HeliOs_Setup.',
            style: TextStyle(
              color: dialogTextMuted,
              fontSize: 13,
              height: 1.4,
            ),
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
                backgroundColor: HeliosTheme.truffleTrouble,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Restableciendo red y reiniciando en Modo Aprovisionamiento...'),
                    backgroundColor: HeliosTheme.truffleTrouble,
                    duration: Duration(seconds: 4),
                  ),
                );
                await resetToProvisioningMode();
              },
              child: const Text('Confirmar y Reiniciar'),
            ),
          ],
        );
      },
    );
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

  void _showEditPvParamsDialog(BuildContext context, bool isNight) {
    final Color dialogBg = isNight ? const Color(0xFF1E293B) : Colors.white;
    final Color dialogTextPrimary = isNight ? HeliosTheme.palladian : const Color(0xFF0F172A);
    final Color dialogTextMuted = isNight ? HeliosTheme.oatmeal : const Color(0xFF475569);
    final Color inputFill = isNight ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final Color borderColor = isNight ? HeliosTheme.oatmeal.withValues(alpha: 0.25) : const Color(0xFFCBD5E1);

    final vocController = TextEditingController(text: _voc.toStringAsFixed(1));
    final iscController = TextEditingController(text: _isc.toStringAsFixed(1));
    final wpController = TextEditingController(text: _wp.toInt().toString());
    final serieController = TextEditingController(text: _serie.toString());
    final paraleloController = TextEditingController(text: _paralelo.toString());

    String? errorMessage;

    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget buildInputField({
              required String label,
              required String helper,
              required TextEditingController controller,
              required String suffix,
              bool isInteger = false,
            }) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: dialogTextPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.numberWithOptions(decimal: !isInteger),
                      style: TextStyle(color: dialogTextPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: inputFill,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        suffixText: suffix,
                        suffixStyle: TextStyle(color: dialogTextMuted, fontSize: 13),
                        helperText: helper,
                        helperStyle: TextStyle(color: dialogTextMuted.withValues(alpha: 0.8), fontSize: 11),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: _accentBlue, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

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
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _accentBlue.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.solar_power, color: _accentBlue, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Parámetros del Arreglo',
                      style: TextStyle(
                        color: dialogTextPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Edita las características eléctricas y geométricas del arreglo fotovoltaico para recalcular la curva esperada y el punto de máxima potencia.',
                        style: TextStyle(color: dialogTextMuted, fontSize: 12, height: 1.3),
                      ),
                      const SizedBox(height: 14),
                      if (errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.redAccent),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.redAccent, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMessage!,
                                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      buildInputField(
                        label: 'Voltaje de Circuito Abierto Unitario (Voc)',
                        helper: 'Por panel bajo condiciones STC (1000 W/m², 25°C)',
                        controller: vocController,
                        suffix: 'V',
                      ),
                      buildInputField(
                        label: 'Corriente de Cortocircuito Unitaria (Isc)',
                        helper: 'Por panel bajo condiciones STC',
                        controller: iscController,
                        suffix: 'A',
                      ),
                      buildInputField(
                        label: 'Potencia Pico Unitaria (Wp)',
                        helper: 'Capacidad nominal de cada módulo',
                        controller: wpController,
                        suffix: 'Wp',
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: buildInputField(
                              label: 'Módulos en Serie',
                              helper: 'Paneles por string',
                              controller: serieController,
                              suffix: 'paneles',
                              isInteger: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: buildInputField(
                              label: 'Cadenas en Paralelo',
                              helper: 'Strings en paralelo',
                              controller: paraleloController,
                              suffix: 'strings',
                              isInteger: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancelar', style: TextStyle(color: dialogTextMuted)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Guardar y Aplicar'),
                  onPressed: () {
                    final double? parsedVoc = double.tryParse(vocController.text.trim());
                    final double? parsedIsc = double.tryParse(iscController.text.trim());
                    final double? parsedWp = double.tryParse(wpController.text.trim());
                    final int? parsedSerie = int.tryParse(serieController.text.trim());
                    final int? parsedParalelo = int.tryParse(paraleloController.text.trim());

                    if (parsedVoc == null || parsedVoc <= 0 ||
                        parsedIsc == null || parsedIsc <= 0 ||
                        parsedWp == null || parsedWp <= 0 ||
                        parsedSerie == null || parsedSerie <= 0 ||
                        parsedParalelo == null || parsedParalelo <= 0) {
                      setDialogState(() {
                        errorMessage = 'Todos los campos deben ser valores numéricos positivos mayores a cero.';
                      });
                      return;
                    }

                    // Lectura del archivo de configuración existente para conservar SSID, pass, etc.
                    Map<String, dynamic> currentConfig = {};
                    final existing = readConfigFile(_configPath);
                    if (existing != null) {
                      try {
                        currentConfig = json.decode(existing);
                      } catch (_) {}
                    }

                    currentConfig['voc'] = parsedVoc;
                    currentConfig['isc'] = parsedIsc;
                    currentConfig['wp'] = parsedWp;
                    currentConfig['serie'] = parsedSerie;
                    currentConfig['paralelo'] = parsedParalelo;

                    final success = writeConfigFile(
                      _configPath,
                      const JsonEncoder.withIndent('  ').convert(currentConfig),
                    );

                    if (success) {
                      setState(() {
                        _voc = parsedVoc;
                        _isc = parsedIsc;
                        _wp = parsedWp;
                        _serie = parsedSerie;
                        _paralelo = parsedParalelo;
                      });

                      // Notificar inmediatamente al broker MQTT para recargar helios-spa.py
                      context.read<MqttService>().publishConfigReload();

                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Parámetros del arreglo fotovoltaico actualizados y enviados al gateway. Modelos astronómicos recalculados con éxito.',
                            style: TextStyle(color: Colors.white),
                          ),
                          backgroundColor: Colors.green,
                          duration: Duration(seconds: 4),
                        ),
                      );
                    } else {
                      setDialogState(() {
                        errorMessage = 'Error al escribir en /data/wifi_config.json. Verifica permisos.';
                      });
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mqttService = context.watch<MqttService>();
    final String weatherState = mqttService.weatherState;
    final bool isNight = mqttService.isNight;
    final palette = WeatherPalette.getPalette(weatherState, isNight);
    final spa = mqttService.spaData;

    final double spaLat = (spa['lat'] as num?)?.toDouble() ?? _lat;
    final double spaLon = (spa['lon'] as num?)?.toDouble() ?? _lon;
    final String spaCity = (spa['ubicacion'] as String?) ?? _city;

    final Color cardColor = palette.cardColor;
    final Color cardBorderColor = palette.cardBorderColor;
    final Color textPrimary = palette.textPrimary;
    final Color textMuted = palette.textMuted;
    final Color appBarItemColor = palette.textPrimary;

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
        decoration: palette.rootDecoration,
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
                  'Red y Ubicación Geográfica',
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
                      const SizedBox(height: 14),
                      // Coordenadas activas pvlib
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isNight
                              ? HeliosTheme.abyssalAnchorfishBlue.withValues(alpha: 0.6)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: cardBorderColor,
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on, color: _accentBlue, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'COORDENADAS ASTRONÓMICAS ACTIVAS (PVLIB)',
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Lat: ${spaLat.toStringAsFixed(4)}°, Lon: ${spaLon.toStringAsFixed(4)}°',
                                    style: TextStyle(
                                      color: textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Ubicación: $spaCity',
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Botón destacado: Cambiar Red Wi-Fi
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accentBlue.withValues(alpha: 0.18),
                            foregroundColor: _accentBlue,
                            side: const BorderSide(color: _accentBlue, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.wifi_find, size: 20),
                          label: const Text(
                            'Cambiar Red Wi-Fi',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          onPressed: () => _showChangeWifiDialog(context, isNight),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: textMuted,
                            side: BorderSide(
                              color: cardBorderColor,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.settings_backup_restore, size: 18),
                          label: const Text(
                            'Restablecer Red de Fábrica (Modo Aprovisionamiento)',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () => _showResetProvisioningDialog(context, isNight),
                        ),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Parámetros Eléctricos del Arreglo',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text(
                        'Editar Parámetros del Arreglo',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _showEditPvParamsDialog(context, isNight),
                    ),
                  ],
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
