/// Local-date helpers for streaks and daily totals.
/// Always use device-local calendar date (YYYY-MM-DD) for daily aggregation.
String localDateString([DateTime? dt]) {
  final d = dt ?? DateTime.now();
  final local = d.toLocal();
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

DateTime parseLocalDate(String yyyyMmDd) {
  final parts = yyyyMmDd.split('-');
  return DateTime(
      int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

/// Calculate current streak from a list of completed local-date strings (newest first).
/// Streak counts consecutive days ending today or yesterday (if today has no study yet).
int calculateStreak(List<String> completedDatesNewestFirst) {
  if (completedDatesNewestFirst.isEmpty) return 0;

  final today = localDateString();
  final now = DateTime.now();
  final yesterday = localDateString(DateTime(now.year, now.month, now.day - 1));

  final set = completedDatesNewestFirst.toSet();
  String cursor;
  if (set.contains(today)) {
    cursor = today;
  } else if (set.contains(yesterday)) {
    cursor = yesterday;
  } else {
    return 0;
  }

  int streak = 0;
  while (set.contains(cursor)) {
    streak++;
    final date = parseLocalDate(cursor);
    final d = DateTime(date.year, date.month, date.day - 1);
    cursor = localDateString(d);
  }
  return streak;
}

String greetingForHour(int hour) {
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}
