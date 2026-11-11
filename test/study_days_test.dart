import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/utils/study_days.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  tzdata.initializeTimeZones();
  Map<String, int> split(DateTime start, DateTime end, tz.Location zone) =>
      splitStudyDays(start, end,
          localize: (utc) => tz.TZDateTime.from(utc, zone),
          nextMidnight: (local) =>
              tz.TZDateTime(zone, local.year, local.month, local.day + 1));
  test('spring-forward day contains 23 actual hours', () {
    final zone = tz.getLocation('America/New_York');
    final start = tz.TZDateTime(zone, 2026, 3, 8);
    final end = tz.TZDateTime(zone, 2026, 3, 9);
    expect(split(start, end, zone), {'2026-03-08': 23 * 60 * 60 * 1000});
  });
  test('fall-back day contains 25 actual hours', () {
    final zone = tz.getLocation('America/New_York');
    expect(
        split(tz.TZDateTime(zone, 2026, 11, 1),
            tz.TZDateTime(zone, 2026, 11, 2), zone),
        {'2026-11-01': 25 * 60 * 60 * 1000});
  });
  test(
      'Kabul calendar dates use its half-hour offset and preserve milliseconds',
      () {
    final zone = tz.getLocation('Asia/Kabul');
    expect(
        split(DateTime.utc(2026, 11, 10, 19, 29, 59, 500),
            DateTime.utc(2026, 11, 10, 19, 30, 0, 500), zone),
        {'2026-11-10': 500, '2026-11-11': 500});
  });
  test('multiple days and empty/backward intervals never inflate time', () {
    final zone = tz.getLocation('UTC');
    final start = DateTime.utc(2026, 11, 10, 23, 59);
    final end = DateTime.utc(2026, 11, 12, 0, 1);
    final result = split(start, end, zone);
    expect(result.values.fold<int>(0, (a, b) => a + b),
        end.difference(start).inMilliseconds);
    expect(split(end, start, zone), isEmpty);
    expect(split(start, start, zone), isEmpty);
  });
}
