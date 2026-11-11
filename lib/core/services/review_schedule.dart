import 'dart:math' as math;

enum ReviewRating { again, hard, good, easy }

String normalizeWord(String word) =>
    word.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class ReviewSchedule {
  const ReviewSchedule(this.due, this.intervalDays, this.ease, this.streak);
  final DateTime due;
  final int intervalDays;
  final int ease;
  final int streak;
}

/// Fixed, offline scheduling. Again: 10 minutes; first Good: 1 day;
/// second Good: 3 days; first Hard: 2 days; first Easy: 4 days.
/// Later intervals use saved ease.
ReviewSchedule scheduleReview(
    {required DateTime now,
    required ReviewRating rating,
    required int intervalDays,
    required int ease,
    required int streak}) {
  var nextEase = ease.clamp(130, 350);
  var nextStreak = streak + 1;
  int days;
  switch (rating) {
    case ReviewRating.again:
      return ReviewSchedule(now.toUtc().add(const Duration(minutes: 10)), 0,
          math.max(130, nextEase - 20), 0);
    case ReviewRating.hard:
      days = math.max(1, (math.max(intervalDays, 1) * 1.2).ceil());
      nextEase = math.max(130, nextEase - 15);
    case ReviewRating.good:
      days = streak == 0
          ? 1
          : (streak == 1
              ? 3
              : math.max(1, (intervalDays * nextEase / 100).round()));
    case ReviewRating.easy:
      days = streak == 0
          ? 4
          : math.max(intervalDays + 1,
              (math.max(intervalDays, 1) * nextEase / 100 * 1.3).round());
      nextEase = math.min(350, nextEase + 15);
  }
  return ReviewSchedule(
      now.toUtc().add(Duration(days: days)), days, nextEase, nextStreak);
}
