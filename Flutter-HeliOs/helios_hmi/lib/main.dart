import 'dart:io';
import 'dart:async';
import 'dart:ffi'; // NUEVO: Interfaz de Funciones Foráneas para C/C++

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/open.dart'; // NUEVO: Control manual del motor SQLite

import 'services/mqtt_service.dart';
import 'ui/dashboard.dart';
import 'ui/provisioning_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. PUENTE Yocto-Linux: Obligamos a Dart a leer la librería de Runtime de Yocto
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so');
    } catch (_) {
      // Si falla, enlazamos a la librería exacta que Yocto instala por defecto
      return DynamicLibrary.open('libsqlite3.so.0');
    }
  });

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

class HeliosApp extends StatelessWidget {
  const HeliosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HeliOs HMI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E1E1E),
          elevation: 8,
          margin: EdgeInsets.all(12),
        ),
      ),
      home: const RootController(),
    );
  }
}

class RootController extends StatefulWidget {
  const RootController({super.key});

  @override
  State<RootController> createState() => _RootControllerState();
}

class _RootControllerState extends State<RootController> {
  bool _isProvisioningMode = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkProvisioningStatus();

    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _checkProvisioningStatus();
    });
  }

  void _checkProvisioningStatus() {
    final configFile = File('/data/wifi_config.json');
    final bool isMissing = !configFile.existsSync();

    if (_isProvisioningMode != isMissing) {
      setState(() {
        _isProvisioningMode = isMissing;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _isProvisioningMode
        ? const ProvisioningScreen()
        : const DashboardScreen();
  }
}
