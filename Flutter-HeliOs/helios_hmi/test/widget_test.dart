import 'package:flutter_test/flutter_test.dart';
import 'package:helios_hmi/main.dart';

void main() {
  testWidgets('Smoke test de inicialización', (WidgetTester tester) async {
    await tester.pumpWidget(const HeliosApp());
  });
}
