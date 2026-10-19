import 'package:flutter/material.dart';
import '../database/db_platform.dart';
import '../theme/helios_theme.dart';

class ProvisioningScreen extends StatefulWidget {
  const ProvisioningScreen({super.key});

  @override
  State<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

class _ProvisioningScreenState extends State<ProvisioningScreen> {
  bool _isRebooting = false;

  @override
  void initState() {
    super.initState();
    _ensurePortalRunning();
  }

  Future<void> _ensurePortalRunning() async {
    final running = await isCaptivePortalRunning();
    if (!running) {
      await launchCaptivePortalService();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: HeliosTheme.nightBackgroundGradient,
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(40.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: HeliosTheme.burningFlame.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: HeliosTheme.burningFlame.withValues(alpha: 0.35),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.wifi_tethering,
                    size: 80,
                    color: HeliosTheme.burningFlame,
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'MODO APROVISIONAMIENTO',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: HeliosTheme.palladian,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'El equipo no tiene conexión a internet o requiere configuración de red. Siga estos pasos:',
                  style: TextStyle(fontSize: 16, color: HeliosTheme.oatmeal),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 36),
                _buildStepCard(
                  '1',
                  'Abra el Wi-Fi en su teléfono o computadora.',
                ),
                _buildStepCard('2', 'Conéctese a la red abierta: HeliOs_Setup'),
                _buildStepCard(
                  '3',
                  'Inicie sesión en el portal emergente o navegue a cualquier sitio web.',
                ),
                _buildStepCard(
                  '4',
                  'Ingrese las credenciales de la planta. El equipo se reiniciará automáticamente.',
                ),
                const SizedBox(height: 36),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HeliosTheme.burningFlame,
                    foregroundColor: HeliosTheme.abyssalAnchorfishBlue,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                  icon: _isRebooting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: HeliosTheme.abyssalAnchorfishBlue,
                          ),
                        )
                      : const Icon(Icons.restart_alt, size: 24),
                  label: Text(
                    _isRebooting
                        ? 'Reiniciando equipo...'
                        : 'Reiniciar Equipo / Relanzar Red HeliOs_Setup',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  onPressed: _isRebooting
                      ? null
                      : () async {
                          setState(() => _isRebooting = true);
                          await rebootSystem();
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard(String step, String text) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: HeliosTheme.blueFantastic,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: HeliosTheme.oatmeal.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      width: 620,
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: HeliosTheme.burningFlame,
            foregroundColor: HeliosTheme.abyssalAnchorfishBlue,
            child: Text(
              step,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                color: HeliosTheme.palladian,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
