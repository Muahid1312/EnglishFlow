import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/services/providers.dart';
import '../../core/utils/date_utils.dart';

class DashboardData {
  final String? displayName;
  final int dailyTargetMinutes;
  final int completedMinutesToday;
  final int streak;
  final int dueReviews;
  final int savedWords;
  final List<LearningActivity> recentActivities;
  final bool onboardingCompleted;
  final int readingTarget;
  final int vocabularyTarget;
  final int listeningTarget;
  final int grammarTarget;

  const DashboardData({
    this.displayName,
    required this.dailyTargetMinutes,
    required this.completedMinutesToday,
    required this.streak,
    required this.dueReviews,
    required this.savedWords,
    required this.recentActivities,
    required this.onboardingCompleted,
    required this.readingTarget,
    required this.vocabularyTarget,
    required this.listeningTarget,
    required this.grammarTarget,
  });

  double get progress => dailyTargetMinutes <= 0
      ? 0
      : (completedMinutesToday / dailyTargetMinutes).clamp(0.0, 1.0);

  bool get goalMet => completedMinutesToday >= dailyTargetMinutes;
}

final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final prefs = await db.getPreferences();
  final today = localDateString();
  final totalSec = await db.getTotalSecondsForDate(today);
  final completedMin = (totalSec / 60).floor();
  final dates = await db.getCompletedStudyDates();
  final streak = calculateStreak(dates);
  final due = await db.getDueReviewCount();
  final words = await db.getSavedWordCount();
  final activities = await db.getRecentActivities(limit: 8);

  return DashboardData(
    displayName: prefs.displayName,
    dailyTargetMinutes: prefs.dailyTargetMinutes,
    completedMinutesToday: completedMin,
    streak: streak,
    dueReviews: due,
    savedWords: words,
    recentActivities: activities,
    onboardingCompleted: prefs.onboardingCompleted,
    readingTarget: prefs.readingMinutes,
    vocabularyTarget: prefs.vocabularyMinutes,
    listeningTarget: prefs.listeningSpeakingMinutes,
    grammarTarget: prefs.grammarWritingMinutes,
  );
});
