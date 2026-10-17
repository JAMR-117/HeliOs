import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Validar adaptación de datos TMY a métricas eléctricas de HeliOs', () {
    final file = File('lib/database/tmy_data.json');
    expect(file.existsSync(), isTrue);

    final jsonStr = file.readAsStringSync();
    final Map<String, dynamic> data = json.decode(jsonStr);

    expect(data.isNotEmpty, isTrue);

    // Comprobar estructura de los registros
    final firstKey = data.keys.first;
    final firstRecord = data[firstKey] as Map<String, dynamic>;
    expect(firstRecord.containsKey('ghi'), isTrue);
    expect(firstRecord.containsKey('dni'), isTrue);
    expect(firstRecord.containsKey('dhi'), isTrue);
    expect(firstRecord.containsKey('temp_air'), isTrue);

    // Probar conversión de un punto con sol
    const double pPeak = 39600.0;
    int daytimeCount = 0;

    for (final entry in data.entries.take(500)) {
      final record = entry.value as Map<String, dynamic>;
      final double ghi = (record['ghi'] as num?)?.toDouble() ?? 0.0;
      final double dni = (record['dni'] as num?)?.toDouble() ?? 0.0;
      final double dhi = (record['dhi'] as num?)?.toDouble() ?? 0.0;
      final double tempAir = (record['temp_air'] as num?)?.toDouble() ?? 25.0;

      if (ghi > 0) {
        daytimeCount++;
        final double tempFactor = 1.0 - 0.0038 * (tempAir - 25.0);
        final double effectiveGhi = dni > 0 ? (dni * 0.82 + dhi) : ghi;
        final double irradRatio = (effectiveGhi / 1000.0).clamp(0.0, 1.25);
        final double pExp = pPeak * irradRatio * tempFactor;
        final double pReal = pExp * 0.973;

        expect(pExp, greaterThan(0));
        expect(pReal, greaterThan(0));
        expect(pReal, lessThanOrEqualTo(pExp));
      }
    }

    expect(daytimeCount, greaterThan(0));
  });
}
