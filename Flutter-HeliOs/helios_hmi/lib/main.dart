import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/mqtt_service.dart';
import 'ui/dashboard.dart';

void main() {
  // 1. Candado estricto: Asegura que el motor gráfico de Flutter/Wayland esté listo
  WidgetsFlutterBinding.ensureInitialized();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => MqttService()..connect('127.0.0.1'),
        ),
      ],
      child: const HeliosApp(),
    ),
  );
}

// ... (El resto de la clase HeliosApp se queda igual)

class HeliosApp extends StatelessWidget {
  const HeliosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HeliOs HMI',
      debugShowCheckedModeBanner:
          false, // Quitamos la etiqueta de debug para el Kiosco
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardTheme: const CardThemeData(
          // <--- CORRECCIÓN APLICADA
          color: Color(0xFF1E1E1E),
          elevation: 8,
          margin: EdgeInsets.all(12),
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}
