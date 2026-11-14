import 'package:flutter_test/flutter_test.dart';

/// Let real asset and platform I/O complete outside the test's fake clock,
/// then require the expected user-visible state within a bounded interval.
Future<void> waitForContent(WidgetTester tester, Finder expected) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 16));
    if (expected.evaluate().isNotEmpty) return;
  }
  expect(expected, findsWidgets, reason: 'Expected content did not finish loading.');
}
