import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'database/db_platform.dart';
import 'services/mqtt_service.dart';
import 'theme/helios_theme.dart';
import 'ui/dashboard.dart';
import 'ui/provisioning_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicialización de SQLite según la plataforma (Yocto-Linux / Native / Web)
  initDatabasePlatform();

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
        scaffoldBackgroundColor: HeliosTheme.abyssalAnchorfishBlue,
        cardColor: HeliosTheme.blueFantastic,
        cardTheme: const CardThemeData(
          color: HeliosTheme.blueFantastic,
          elevation: 6,
          margin: EdgeInsets.all(12),
        ),
        colorScheme: const ColorScheme.dark(
          primary: HeliosTheme.burningFlame,
          secondary: HeliosTheme.truffleTrouble,
          surface: HeliosTheme.blueFantastic,
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
    final bool isMissing = isProvisioningFileMissing();

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
