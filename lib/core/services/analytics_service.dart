import '../database/app_database.dart';
import '../utils/date_utils.dart';

class Insight {
  final String message;
  final String actionLabel;
  final String route;
  Insight(this.message, this.actionLabel, this.route);
}

class ProgressSnapshot {
  final int totalMinutes;
  final int todayMinutes;
  final int weekMinutes;
  final int streak;
  final int grammarCompleted;
  final double grammarAccuracy;
  final int writingEntries;
  final int listeningLessons;
  final int speakingRecordings;
  final int books;
  final int savedWords;
  final List<Map<String, dynamic>> last7Days;
  final List<Insight> insights;

  ProgressSnapshot({
    required this.totalMinutes,
    required this.todayMinutes,
    required this.weekMinutes,
    required this.streak,
    required this.grammarCompleted,
    required this.grammarAccuracy,
    required this.writingEntries,
    required this.listeningLessons,
    required this.speakingRecordings,
    required this.books,
    required this.savedWords,
    required this.last7Days,
    required this.insights,
  });
}

class AnalyticsService {
  AnalyticsService(this._db);
  final AppDatabase _db;

  Future<ProgressSnapshot> build() async {
    final totalSec = await _db.getTotalStudySeconds();
    final today = localDateString();
    final todaySec = await _db.getTotalSecondsForDate(today);
    final last7 = await _db.getSessionsLastDays(7);
    var weekSec = 0;
    for (final r in last7) {
      weekSec += (r['total_seconds'] as int?) ?? 0;
    }
    final dates = await _db.getCompletedStudyDates();
    final streak = calculateStreak(dates);
    final gDone = await _db.countCompletedGrammarLessons();
    final gAcc = await _db.grammarAccuracy();
    final writing = await _db.countWritingEntries();
    final listening = await _db.countListeningLessons();
    final speaking = await _db.countSpeakingRecordings();
    final books = await _db.countImportedBooks();
    final words = await _db.getSavedWordCount();
    final prefs = await _db.getPreferences();

    final insights = <Insight>[];
    if (todaySec < prefs.dailyTargetMinutes * 60 * 0.5) {
      insights.add(Insight(
        'You are under halfway to today’s ${prefs.dailyTargetMinutes}-minute goal.',
        'Start a session',
        '/learn',
      ));
    }
    if (gAcc > 0 && gAcc < 0.6) {
      insights.add(Insight(
        'Grammar accuracy is below 60%. A short review lesson may help.',
        'Open Grammar Studio',
        '/learn/grammar/studio',
      ));
    }
    if (listening == 0) {
      insights.add(Insight(
        'No listening lessons imported yet.',
        'Listening Studio',
        '/learn/listening/library',
      ));
    }
    if (speaking == 0) {
      insights.add(Insight(
        'No speaking recordings yet. Try a prompt when you have a quiet minute.',
        'Speaking Studio',
        '/learn/listening/speaking',
      ));
    }
    if (words == 0) {
      insights.add(Insight(
        'Vocabulary bank is empty. Save words while reading or listening.',
        'Vocabulary',
        '/learn/vocabulary',
      ));
    }

    return ProgressSnapshot(
      totalMinutes: totalSec ~/ 60,
      todayMinutes: todaySec ~/ 60,
      weekMinutes: weekSec ~/ 60,
      streak: streak,
      grammarCompleted: gDone,
      grammarAccuracy: gAcc,
      writingEntries: writing,
      listeningLessons: listening,
      speakingRecordings: speaking,
      books: books,
      savedWords: words,
      last7Days: last7,
      insights: insights,
    );
  }
}
