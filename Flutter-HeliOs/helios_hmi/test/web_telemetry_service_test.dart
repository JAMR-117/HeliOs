import 'package:flutter_test/flutter_test.dart';
import 'package:helios_hmi/services/web_telemetry_service.dart';

void main() {
  test('WebTelemetryService genera métricas solares diurnas coherentes', () {
    final service = WebTelemetryService();

    // Simular hora diurna de máxima producción (12:45 UTC-6)
    service.setSimulatedHour(12.75);

    expect(service.isNight, isFalse);
    expect(service.weatherState, equals('sunny'));
    expect(service.isInverterConnected, isTrue);

    // Irradiancia y potencia esperada deben ser mayores a cero
    final double ghi = (service.spaData['ghi'] as num).toDouble();
    final double pExp = (service.spaData['p_exp'] as num).toDouble();
    final double pReal = (service.telemetryData['power_w'] as num).toDouble();
    final double vDc = (service.telemetryData['v_dc'] as num).toDouble();
    final double iDc = (service.telemetryData['i_dc'] as num).toDouble();

    expect(ghi, greaterThan(800.0));
    expect(pExp, greaterThan(25000.0));
    expect(pReal, greaterThan(20000.0));
    expect(pReal, lessThanOrEqualTo(pExp));
    expect(vDc, greaterThan(500.0));
    expect(iDc, greaterThan(20.0));

    // Pronóstico de 24 horas debe estar poblado
    expect(service.forecastData.length, equals(24));

    // Puntos en tiempo real para la gráfica deben estar precargados
    expect(service.livePowerPoints.isNotEmpty, isTrue);

    service.dispose();
  });

  test('WebTelemetryService maneja modo nocturno y estiba correctamente', () {
    final service = WebTelemetryService();

    // Simular hora nocturna (23:00 UTC-6)
    service.setSimulatedHour(23.0);

    expect(service.isNight, isTrue);
    expect(service.weatherState, equals('clear_night'));

    final double ghi = (service.spaData['ghi'] as num).toDouble();
    final double pExp = (service.spaData['p_exp'] as num).toDouble();
    final double pReal = (service.telemetryData['power_w'] as num).toDouble();

    expect(ghi, equals(0.0));
    expect(pExp, equals(0.0));
    expect(pReal, equals(0.0));
    expect(service.isStow, isTrue);
    expect(service.targetAngle, equals(0.0));

    service.dispose();
  });

  test('WebTelemetryService responde a estiba manual y viento crítico', () {
    final service = WebTelemetryService();
    service.setSimulatedHour(12.75);

    // Forzar viento de emergencia
    service.setWindKmh(55.0);
    expect(service.windKmh, equals(55.0));
    expect(service.isStow, isTrue);
    expect(service.targetAngle, equals(0.0));
    expect(service.scadaData['code'], equals(104));

    // Desactivar viento forzado y probar estiba manual
    service.setWindKmh(null);
    service.setManualStow(true);
    expect(service.manualStow, isTrue);
    expect(service.isStow, isTrue);
    expect(service.targetAngle, equals(0.0));

    service.dispose();
  });
}
