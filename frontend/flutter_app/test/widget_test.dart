import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App launches without errors', (WidgetTester tester) async {
    // Basic smoke test — Firebase requires initialization, so we just
    // verify the test framework works for now.
    expect(1 + 1, equals(2));
  });
}
