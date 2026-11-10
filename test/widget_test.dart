import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/utils/date_utils.dart';
import 'package:lexiflow/core/utils/id_utils.dart';

/// Lightweight smoke tests that do not require full app bootstrap
/// (avoids path_provider / sqlite native bindings in unit test isolate).
void main() {
  test('newId produces unique non-empty ids', () {
    final a = newId();
    final b = newId();
    expect(a, isNotEmpty);
    expect(b, isNotEmpty);
    expect(a, isNot(equals(b)));
  });

  test('localDateString is stable format', () {
    final s = localDateString(DateTime(2026, 11, 10));
    expect(s, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(s, '2026-11-10');
  });
}
