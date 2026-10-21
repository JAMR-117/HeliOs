import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'database/db_platform.dart';
import 'services/mqtt_service.dart';
import 'services/web_telemetry_service.dart';
import 'theme/helios_animations.dart';
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
        ChangeNotifierProvider(
          create: (_) => WebTelemetryService(),
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
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: HeliosPageTransitionsBuilder(),
            TargetPlatform.iOS: HeliosPageTransitionsBuilder(),
            TargetPlatform.windows: HeliosPageTransitionsBuilder(),
            TargetPlatform.linux: HeliosPageTransitionsBuilder(),
            TargetPlatform.macOS: HeliosPageTransitionsBuilder(),
            TargetPlatform.fuchsia: HeliosPageTransitionsBuilder(),
          },
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
  Timer? _provisioningPollTimer;

  @override
  void initState() {
    super.initState();
    // Determinar modo inicial de operación al encender el equipo
    _isProvisioningMode = isProvisioningFileMissing();

    // Solo si arrancamos en Modo Aprovisionamiento, sondeamos si se completó la configuración.
    // Una vez en Modo Normal (Dashboard), queda ESTRICTAMENTE bloqueado cualquier regreso automático.
    if (_isProvisioningMode) {
      _provisioningPollTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (!isProvisioningFileMissing()) {
          timer.cancel();
          _provisioningPollTimer = null;
          if (mounted) {
            setState(() {
              _isProvisioningMode = false;
            });
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _provisioningPollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: _isProvisioningMode
          ? const ProvisioningScreen(key: ValueKey('provisioning'))
          : const DashboardScreen(key: ValueKey('dashboard')),
    );
  }
}
