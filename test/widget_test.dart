import 'package:flutter_test/flutter_test.dart';
import 'package:sweets_app/app.dart';

void main() {
  testWidgets('SweetsApp builds', (tester) async {
    await tester.pumpWidget(const SweetsApp());
    expect(find.textContaining('Sweets'), findsOneWidget);
  });
}
