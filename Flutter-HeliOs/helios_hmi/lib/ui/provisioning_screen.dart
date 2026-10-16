import 'package:flutter/material.dart';

class ProvisioningScreen extends StatelessWidget {
  const ProvisioningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Fondo oscuro
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.wifi_tethering,
                size: 100,
                color: Colors.blueAccent,
              ),
              const SizedBox(height: 30),
              const Text(
                'MODO APROVISIONAMIENTO',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'El equipo no tiene conexión a internet. Siga estos pasos:',
                style: TextStyle(fontSize: 20, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepCard(String step, String text) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
      ),
      width: 600,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            child: Text(
              step,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
