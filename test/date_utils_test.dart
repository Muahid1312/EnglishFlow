import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/utils/date_utils.dart';

void main() {
  group('localDateString', () {
    test('formats date as YYYY-MM-DD', () {
      final d = DateTime(2026, 3, 5);
      expect(localDateString(d), '2026-03-05');
    });

    test('pads single digit month and day', () {
      final d = DateTime(2026, 1, 9);
      expect(localDateString(d), '2026-01-09');
    });
  });

  group('calculateStreak', () {
    test('empty list returns 0', () {
      expect(calculateStreak([]), 0);
    });

    test('today only returns 1', () {
      final today = localDateString();
      expect(calculateStreak([today]), 1);
    });

    test('yesterday only returns 1', () {
      final yesterday =
          localDateString(DateTime.now().subtract(const Duration(days: 1)));
      expect(calculateStreak([yesterday]), 1);
    });

    test('consecutive days ending today', () {
      final today = DateTime.now();
      final dates = List.generate(
          5, (i) => localDateString(today.subtract(Duration(days: i))));
      expect(calculateStreak(dates), 5);
    });

    test('gap breaks streak', () {
      final today = DateTime.now();
      final dates = [
        localDateString(today),
        localDateString(today.subtract(const Duration(days: 1))),
        // gap day 2
        localDateString(today.subtract(const Duration(days: 3))),
      ];
      expect(calculateStreak(dates), 2);
    });

    test('old dates only returns 0', () {
      final old =
          localDateString(DateTime.now().subtract(const Duration(days: 10)));
      expect(calculateStreak([old]), 0);
    });
  });

  group('greetingForHour', () {
    test('morning', () => expect(greetingForHour(8), 'Good morning'));
    test('afternoon', () => expect(greetingForHour(14), 'Good afternoon'));
    test('evening', () => expect(greetingForHour(20), 'Good evening'));
  });
}
