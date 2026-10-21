import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:helios_hmi/services/mqtt_service.dart';
import 'package:helios_hmi/services/web_telemetry_service.dart';
import 'package:helios_hmi/ui/dashboard.dart';
import 'package:helios_hmi/ui/widgets/helios_bottom_nav_bar.dart';
import 'package:helios_hmi/ui/scada_errors_screen.dart';
import 'package:helios_hmi/ui/plant_config_screen.dart';

void main() {
  testWidgets('DashboardScreen se renderiza correctamente con métricas Web y barra de navegación', (WidgetTester tester) async {
    final mqtt = MqttService();
    final web = WebTelemetryService();

    // Configurar viewport amplio para el test
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: mqtt),
          ChangeNotifierProvider.value(value: web),
        ],
        child: const MaterialApp(
          home: DashboardScreen(),
        ),
      ),
    );

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Condiciones actuales'), findsOneWidget);
    expect(find.text('Potencia'), findsOneWidget);
    expect(find.text('Voltaje DC'), findsOneWidget);
    expect(find.text('Corriente DC'), findsOneWidget);

    // Verificar presencia de la barra de navegación inferior
    expect(find.byType(HeliosGlassBottomBar), findsOneWidget);
    expect(find.text('Monitoreo'), findsOneWidget);
    expect(find.text('Bitácora SCADA'), findsOneWidget);
    expect(find.text('Configuración'), findsOneWidget);

    // Probar transición fluida a la pestaña de Bitácora SCADA
    await tester.tap(find.text('Bitácora SCADA'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
    expect(find.byType(ScadaErrorsScreen), findsOneWidget);

    // Probar transición fluida a la pestaña de Configuración
    await tester.tap(find.text('Configuración'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
    expect(find.byType(PlantConfigScreen), findsOneWidget);

    // Regresar al Monitoreo
    await tester.tap(find.text('Monitoreo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 360));
    expect(find.text('Condiciones actuales'), findsOneWidget);

    // Desmontar widget y cancelar timers para evitar fugas en el test
    await tester.pumpWidget(const SizedBox());
    mqtt.dispose();
    web.dispose();
  });
}
