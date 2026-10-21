import 'package:flutter_test/flutter_test.dart';
import 'package:anuwad/main.dart';

void main() {
  testWidgets('Anuwad app launches', (WidgetTester tester) async {
    await tester.pumpWidget(const AnuwadApp());

    expect(find.text('Anuwad'), findsOneWidget);
  });
}