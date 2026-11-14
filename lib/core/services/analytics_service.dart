import '../database/app_database.dart';
import 'mistake_coach.dart';
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
  final Map<String, num> activityCounts;
  final Map<String,String> skills;

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
    this.activityCounts = const {},
    this.skills = const {},
  });
}

class AnalyticsService {
  AnalyticsService(this._db);
  final AppDatabase _db;

  Future<Map<String,dynamic>> listening() async {
    final db=await _db.db;
    int count(String sql,[List<Object?> parameters=const []])=>db.select(sql,parameters).single.values.single as int;
    int seconds(String module)=>count('SELECT COALESCE(SUM(duration_seconds),0) FROM study_sessions WHERE completed=1 AND module=?',[module]);
    final graded=count('SELECT COUNT(*) FROM comprehension_attempts WHERE self_assessed=0 AND is_correct IS NOT NULL');
    final correct=count('SELECT COUNT(*) FROM comprehension_attempts WHERE self_assessed=0 AND is_correct=1');
    return {
      'listeningSeconds':seconds('listening'),
      'combinedSeconds':seconds('listening_speaking'),
      'shadowingStudySeconds':seconds('shadowing'),
      'aiStudySeconds':seconds('ai_conversation'),
      'comprehensionExercises':count('SELECT COUNT(DISTINCT submission_id) FROM comprehension_attempts WHERE submission_id IS NOT NULL'),
      'graded':graded,'correct':correct,'accuracy':graded==0?null:correct/graded,
      'shadowingAttempts':count('SELECT COUNT(*) FROM shadowing_attempts WHERE saved=1'),
      'speakingTakes':count("SELECT COUNT(*) FROM speaking_recordings WHERE mode!='shadowing'"),
      'recordedSeconds':count('SELECT COALESCE(SUM(duration_ms),0)/1000 FROM speaking_recordings'),
      'aiConversations':count("SELECT COUNT(DISTINCT conversation_id) FROM ai_messages WHERE role='assistant' AND is_local=0 AND purpose='conversation'"),
      'recent':db.select("SELECT * FROM learning_activities WHERE module IN ('listening','listening_speaking','shadowing','speaking','ai_teacher','ai_conversation') ORDER BY created_at DESC,id DESC LIMIT 10"),
    };
  }

  Future<ProgressSnapshot> build() async {
    final totalSec = await _db.getTotalStudySeconds();
    final today = localDateString();
    final todaySec = await _db.getTotalSecondsForDate(today);
    final last7 = await _db.getSessionsLastDays(7);
    var weekMs = 0;
    for (final r in last7) {
      weekMs += (r['total_ms'] as int?) ?? 0;
    }
    final weekSec = weekMs ~/ 1000;
    final dates = await _db.getCompletedStudyDates();
    final streak = calculateStreak(dates);
    final gDone = await _db.countCompletedGrammarLessons();
    final writing = await _db.countWritingEntries();
    final listening = await _db.countListeningLessons();
    final speaking = await _db.countSpeakingRecordings();
    final books = await _db.countImportedBooks();
    final words = await _db.getSavedWordCount();
    final prefs = await _db.getPreferences();

    final d=await _db.db;
    int count(String sql)=>d.select(sql).single.values.single as int;
    final grammarN=count('SELECT COUNT(*) FROM grammar_attempts WHERE self_assessed=0 AND is_correct IS NOT NULL');
    final grammarCorrect=count('SELECT COUNT(*) FROM grammar_attempts WHERE self_assessed=0 AND is_correct=1');
    final objectiveGrammar=grammarN==0?0.0:grammarCorrect/grammarN;
    final listeningN=count('SELECT COUNT(*) FROM comprehension_attempts WHERE self_assessed=0 AND is_correct IS NOT NULL');
    final listeningCorrect=count('SELECT COUNT(*) FROM comprehension_attempts WHERE self_assessed=0 AND is_correct=1');
    final reviews=count('SELECT COUNT(*) FROM vocabulary_review_history');
    final successful=count("SELECT COUNT(*) FROM vocabulary_review_history WHERE rating IN ('good','easy')");
    final due=(await _db.getDueVocabulary()).length;
    String accuracy(int correct,int total)=>total<5?'Not enough data. ($total objective answers; minimum 5)':'${(100*correct/total).round()}% correct across $total objective answers';
    final skills=<String,String>{
      'Reading':'${count('SELECT COUNT(*) FROM reading_articles')==0?'Not enough data. ':''}${count('SELECT COUNT(*) FROM reading_articles')} saved articles; ${count("SELECT COUNT(*) FROM study_sessions WHERE module='reading' AND completed=1 AND duration_seconds>0")} completed reading sessions; ${count('SELECT COUNT(*) FROM builtin_article_state WHERE completed_at IS NOT NULL')} built-in articles read with questions submitted. Activity counts, not proficiency.',
      'Vocabulary':reviews<5?'Not enough data. $reviews reviews; $due due cards.':'${(100*successful/reviews).round()}% good/easy ratings across $reviews reviews; $due due cards. Self-rated recall.',
      'Listening':accuracy(listeningCorrect,listeningN),
      'Speaking':speaking==0?'Not enough data. No saved recordings.':'$speaking saved recordings. Practice frequency, not speaking proficiency.',
      'Grammar':accuracy(grammarCorrect,grammarN),
      'Writing':writing==0?'Not enough data. No saved drafts.':'$writing drafts; ${count('SELECT COUNT(*) FROM writing_revisions')} saved revisions.',
      'Courses':'${count('SELECT COUNT(*) FROM courses WHERE deleted=0')} courses; ${count("SELECT COUNT(*) FROM completion_records WHERE target_type='course'")} issued course completion records.',
    };
    final insights = <Insight>[];
    for(final weak in await MistakeCoach(_db).weaknesses()) {
      insights.add(Insight('${weak['category']}: ${weak['records']} confirmed correction records, ${weak['errors']??0} errors in ${weak['attempts']} exact practice attempts. Minimum: 3 distinct records or 3 attempts with 2 errors.',
        'Review corrections','/learn/grammar/mistakes/practice?category=${Uri.encodeComponent(weak['category'] as String)}'));
    }
    final next=d.select('''SELECT l.id,l.title FROM lessons l JOIN courses c ON c.id=l.course_id
      WHERE c.structured_mode=1 AND c.is_active=1 AND c.deleted=0
      AND (NOT EXISTS(SELECT 1 FROM course_activities a WHERE a.lesson_id=l.id)
      OR EXISTS(SELECT 1 FROM course_activities a LEFT JOIN course_activity_evidence e ON e.activity_id=a.id WHERE a.lesson_id=l.id AND e.activity_id IS NULL))
      ORDER BY l.last_studied_at DESC,c.created_at,l.order_index,l.id LIMIT 1''');
    if(next.isNotEmpty)insights.add(Insight('Saved lesson “${next.single['title']}” has unfinished activity evidence.','Continue lesson','/learn/courses/lesson/${next.single['id']}'));
    if(due>0)insights.add(Insight('$due saved vocabulary cards are due now.','Review words','/learn/vocabulary'));
    if(listeningN>=5 && listeningCorrect/listeningN<0.6)insights.add(Insight('Listening: $listeningCorrect of $listeningN objective answers correct (minimum 5).','Practice listening','/learn/listening/library'));
    if(reviews>=5 && successful/reviews<0.6)insights.add(Insight('Fewer than 60% good/easy ratings across $reviews vocabulary reviews.','Review words','/learn/vocabulary'));
    final pending=d.select('''SELECT a.id,a.title FROM assessment_definitions a JOIN courses c ON c.id=a.course_id
      WHERE c.deleted=0 AND c.is_active=1 AND NOT EXISTS(SELECT 1 FROM assessment_attempts t WHERE t.assessment_id=a.id AND t.passed=1 AND t.self_assessed=0 AND t.completed_at IS NOT NULL) ORDER BY a.created_at LIMIT 1''');
    if(pending.isNotEmpty)insights.add(Insight('Course assessment “${pending.single['title']}” has no saved passing attempt.','Take assessment','/progress/assessments/${pending.single['id']}'));
    final revision=d.select('SELECT id,title FROM writing_entries ORDER BY updated_at LIMIT 1');
    if(revision.isNotEmpty)insights.add(Insight('Revisit your saved writing “${revision.single['title']}”.','Revise writing','/learn/grammar/writing/${revision.single['id']}'));

    if (todaySec < prefs.dailyTargetMinutes * 60 * 0.5) {
      insights.add(Insight(
        'You are under halfway to today’s ${prefs.dailyTargetMinutes}-minute goal.',
        'Start a session',
        '/learn',
      ));
    }
    if (grammarN >= 5 && objectiveGrammar < 0.6) {
      insights.add(Insight(
        'Grammar accuracy is below 60% across $grammarN objective answers (minimum 5). A review may help.',
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
      grammarAccuracy: objectiveGrammar,
      writingEntries: writing,
      listeningLessons: listening,
      speakingRecordings: speaking,
      books: books,
      savedWords: words,
      last7Days: last7,
      insights: insights,
      activityCounts: await _db.activityStatistics(),
      skills:skills,
    );
  }
}
