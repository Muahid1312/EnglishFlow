import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiflow/core/content/grammar_curriculum.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/daily_plan_service.dart';
import 'package:lexiflow/core/services/study_session_service.dart';
import 'package:lexiflow/core/services/providers.dart';
import 'package:lexiflow/features/dashboard/dashboard_provider.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase db;
  late StudySessionService sessions;
  late DailyPlanService plans;
  late DateTime now;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('lexiflow-plan-v2-');
    db = AppDatabase(path: '${dir.path}/learning.sqlite');
    now = DateTime(2026, 11, 14, 10);
    sessions = StudySessionService(db, now: () => now);
    plans = DailyPlanService(db, sessions, now: () => now);
    await db.saveArticle('A real saved article', 'Read and save words.');
    await db.saveVocabulary(word: 'practice');
    // Saved, but not due: keep the default distribution for baseline tests.
    (await db.db)
        .execute("UPDATE vocabulary_reviews SET next_review_at='2030-01-01'");
    final audio = File('${dir.path}/lesson.mp3')..writeAsBytesSync([1, 2, 3]);
    await db.insertListeningLesson({
      'id': 'listening',
      'title': 'Imported lesson',
      'audio_path': audio.path,
      'difficulty': 'B1'
    });
    await GrammarCurriculum.seedIfEmpty(db);
  });
  tearDown(() {
    sessions.dispose();
    db.close();
    dir.deleteSync(recursive: true);
  });

  for (final goal in [15, 30, 60]) {
    test('$goal minute plan uses exact baseline targets and real content',
        () async {
      final rows = await plans.today(goal: goal);
      final expected = goal == 15
          ? [5, 5, 5]
          : goal == 30
              ? [10, 7, 8, 5]
              : [18, 12, 18, 12];
      expect(rows.map((r) => r['minutes']).toList(), expected);
      expect(rows.fold<int>(0, (n, r) => n + (r['minutes'] as int)), goal);
      expect(rows.every((r) => (r['route'] as String).startsWith('/learn/')),
          isTrue);
      expect(rows.first['title'], 'A real saved article');
      expect((await db.getPreferences()).dailyTargetMinutes, goal);
    });
  }

  test(
      'due vocabulary is first with an explainable priority and a bounded budget',
      () async {
    (await db.db)
        .execute("UPDATE vocabulary_reviews SET next_review_at='2020-01-01'");
    final rows = await plans.today(goal: 15);
    expect(rows.first['module'], 'vocabulary');
    expect(rows.first['reason'], contains('due now'));
    expect(rows.fold<int>(0, (n, r) => n + (r['minutes'] as int)), 15);
    expect(rows.length, lessThanOrEqualTo(3));
  });

  test('concurrent plan reads generate only one set of persisted activities',
      () async {
    final requests =
        await Future.wait(List.generate(8, (_) => plans.today(goal: 30)));
    final first = requests.first.map((r) => r['id']).toList();
    for (final result in requests) {
      expect(result.map((r) => r['id']).toList(), first);
    }
    expect((await db.db).select('SELECT * FROM daily_plans'), hasLength(1));
    expect(
        (await db.db).select('SELECT * FROM planned_activities'), hasLength(4));
  });

  test('missing audio does not fabricate a playable lesson', () async {
    File('${dir.path}/lesson.mp3').deleteSync();
    final rows = await plans.today(goal: 30);
    expect(rows.any((r) => r['module'] == 'listening_speaking'), isFalse);
    expect(rows.fold<int>(0, (n, r) => n + (r['minutes'] as int)), 30);
    expect(rows.any((r) => r['module'] == 'grammar_writing'), isTrue);
  });

  test(
      'fresh installation recommends real offline reading and vocabulary without imports',
      () async {
    final empty = AppDatabase(path: '${dir.path}/empty.sqlite');
    final emptySessions = StudySessionService(empty, now: () => now);
    try {
      final rows = await DailyPlanService(empty, emptySessions, now: () => now)
          .today(goal: 15);
      expect(rows, hasLength(3));
      expect(rows.first['route'], startsWith('/learn/reading/builtin'));
      expect(
          rows.any((r) => r['route'] == '/learn/vocabulary/library?daily=true'),
          isTrue);
      expect(rows.any((r) => r['route'] == '/learn/grammar/writing'), isTrue);
      expect(rows.fold<int>(0, (sum, r) => sum + (r['minutes'] as int)), 15);
      expect(await empty.getVocabulary(), isEmpty);
      expect((await empty.db).select('SELECT * FROM builtin_reading_attempts'),
          isEmpty);
    } finally {
      emptySessions.dispose();
      empty.close();
    }
  });

  test('plan survives restart without regenerating identifiers or states',
      () async {
    final before = await plans.today(goal: 30);
    await plans.complete(before.first['id'] as String, skip: true);
    sessions.dispose();
    db.close();
    db = AppDatabase(path: '${dir.path}/learning.sqlite');
    sessions = StudySessionService(db, now: () => now);
    plans = DailyPlanService(db, sessions, now: () => now);
    final after = await plans.today();
    expect(after.map((r) => r['id']).toList(),
        before.map((r) => r['id']).toList());
    expect(after.first['state'], 'skipped');
  });

  test(
      'pause, resume and duplicate finish count only real active study seconds',
      () async {
    final a = (await plans.today(goal: 15)).first;
    final id = a['id'] as String;
    await plans.start(id);
    now = now.add(const Duration(seconds: 70));
    await sessions.pause();
    now = now.add(const Duration(minutes: 5));
    await plans.start(id);
    now = now.add(const Duration(seconds: 50));
    await plans.complete(id);
    await plans.complete(id);
    final result = (await plans.today()).first;
    expect(result['state'], 'completed');
    expect(result['actual_ms'], 120000);
    expect(await db.getTotalSecondsForDate('2026-11-14'), 120);
    expect((await db.db).select('SELECT * FROM plan_sessions'), hasLength(1));
  });

  test(
      'goal changes preserve completed, skipped and partly practiced activity records',
      () async {
    final rows = await plans.today(goal: 30);
    final first = rows[0]['id'] as String;
    await plans.start(first);
    now = now.add(const Duration(minutes: 3));
    await plans.complete(first);
    final skipped = rows[1]['id'] as String;
    await plans.complete(skipped, skip: true);
    final partial = rows[2]['id'] as String;
    await plans.start(partial);
    now = now.add(const Duration(seconds: 20));
    await sessions.pause();
    final changed = await plans.today(goal: 15);
    expect(changed.firstWhere((r) => r['id'] == first)['state'], 'completed');
    expect(changed.firstWhere((r) => r['id'] == skipped)['state'], 'skipped');
    expect(changed.firstWhere((r) => r['id'] == partial)['actual_ms'], 20000);
    expect((await db.getPreferences()).dailyTargetMinutes, 15);
    // Existing allocations may exceed a reduced goal; historical work is not deleted.
    expect((await db.db).select('SELECT * FROM plan_sessions'), hasLength(2));
  });

  test('increasing goal adjusts untouched work and retains practiced records',
      () async {
    final rows = await plans.today(goal: 15);
    await plans.start(rows.first['id'] as String);
    now = now.add(const Duration(minutes: 1));
    await plans.complete(rows.first['id'] as String);
    final changed = await plans.today(goal: 60);
    expect(changed.first['id'], rows.first['id']);
    expect(changed.first['state'], 'completed');
    expect(changed.fold<int>(0, (n, r) => n + (r['minutes'] as int)), 60);
  });

  test(
      'unfinished plan continues paused after restart without counting downtime',
      () async {
    final id = (await plans.today(goal: 30)).first['id'] as String;
    await plans.start(id);
    now = now.add(const Duration(seconds: 75));
    await sessions.onAppPaused();
    sessions.dispose();
    db.close();
    now = now.add(const Duration(hours: 2));
    db = AppDatabase(path: '${dir.path}/learning.sqlite');
    sessions = StudySessionService(db, now: () => now);
    plans = DailyPlanService(db, sessions, now: () => now);
    await sessions.recoverInterrupted();
    expect(sessions.isRunning, isFalse);
    await plans.start(id);
    now = now.add(const Duration(seconds: 45));
    await plans.complete(id);
    expect((await plans.today()).first['actual_ms'], 120000);
  });

  test('midnight creates a new plan and splits actual session time once',
      () async {
    now = DateTime(2026, 11, 14, 23, 59, 30);
    final id = (await plans.today(goal: 15)).first['id'] as String;
    await plans.start(id);
    now = DateTime(2026, 11, 15, 0, 0, 30);
    await plans.complete(id);
    final next = await plans.today();
    expect(next.first['local_date'], '2026-11-15');
    expect(next.any((r) => r['id'] == id), isFalse);
    expect(await db.getTotalSecondsForDate('2026-11-14'), 30);
    expect(await db.getTotalSecondsForDate('2026-11-15'), 30);
    expect((await plans.activities('2026-11-14')).first['state'], 'completed');
    expect(await plans.history(), hasLength(2));
  });

  test(
      'returning to an existing calendar date preserves its history and offset',
      () async {
    final original = await plans.today(goal: 15);
    final offset = (await plans.history()).first['utc_offset_minutes'];
    now = now.add(const Duration(days: 1));
    await plans.today();
    now = now.subtract(const Duration(days: 1));
    final returned = await plans.today();
    expect(returned.first['id'], original.first['id']);
    expect((await plans.history()).last['utc_offset_minutes'], offset);
  });

  test('skip without practice is distinct from completion and adds no minutes',
      () async {
    final id = (await plans.today(goal: 15)).first['id'] as String;
    await expectLater(plans.complete(id), throwsStateError);
    await plans.complete(id, skip: true);
    expect((await plans.today()).first['state'], 'skipped');
    expect(await db.getTotalSecondsForDate('2026-11-14'), 0);
  });

  test('switching planned activity never double counts a session', () async {
    final rows = await plans.today(goal: 15);
    await plans.start(rows[0]['id'] as String);
    now = now.add(const Duration(seconds: 60));
    await plans.start(rows[1]['id'] as String);
    now = now.add(const Duration(seconds: 30));
    await plans.complete(rows[1]['id'] as String);
    await plans.complete(rows[0]['id'] as String);
    expect(await db.getTotalSecondsForDate('2026-11-14'), 90);
    expect(
        (await plans.today())
            .fold<int>(0, (n, r) => n + (r['actual_ms'] as int)),
        90000);
  });

  test(
      'finished plan study updates the existing dashboard using session totals',
      () async {
    // Dashboard uses the real local day, so keep this integration fixture on it.
    final today = DateTime.now();
    now = DateTime(today.year, today.month, today.day, 12);
    final activity = (await plans.today(goal: 30)).first;
    await plans.start(activity['id'] as String);
    now = now.add(const Duration(minutes: 2));
    await plans.complete(activity['id'] as String);
    final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)]);
    try {
      final dashboard = await container.read(dashboardProvider.future);
      expect(dashboard.completedMinutesToday, 2);
      expect(dashboard.dailyTargetMinutes, 30);
      expect(dashboard.savedWords, 1);
    } finally {
      container.dispose();
    }
  });

  test('unfinished real book lesson takes the reading slot and keeps its file',
      () async {
    final file = File('${dir.path}/book.pdf')
      ..writeAsBytesSync([37, 80, 68, 70]);
    final d = await db.db;
    d.execute(
        "INSERT INTO imported_books(id,title,file_path) VALUES('book','Book title',?)",
        [file.path]);
    d.execute(
        "INSERT INTO book_units(id,book_id,title) VALUES('unit','book','Unit')");
    d.execute(
        "INSERT INTO book_lessons(id,unit_id,book_id,title) VALUES('lesson','unit','book','Unfinished lesson')");
    final rows = await plans.today(goal: 30);
    expect(rows.first['route'], '/learn/books/book/read');
    expect(rows.first['reason'], contains('Unfinished lesson'));
    expect(file.existsSync(), isTrue);
  });

  test('grammar weakness chooses an existing exercise lesson', () async {
    final d = await db.db;
    final exercise = d
        .select('SELECT * FROM grammar_exercises ORDER BY id DESC LIMIT 1')
        .single;
    await db.saveGrammarAttempt({
      'id': 'weak',
      'exercise_id': exercise['id'],
      'lesson_id': exercise['lesson_id'],
      'learner_response': 'wrong',
      'is_correct': 0,
      'self_assessed': 0
    });
    final rows = await plans.today(goal: 30);
    final grammar = rows.singleWhere((r) => r['module'] == 'grammar_writing');
    expect(grammar['route'], '/learn/grammar/lesson/${exercise['lesson_id']}');
    expect(grammar['reason'], contains('incorrect answers'));
  });

  for (final version in [1, 4, 5]) {
    test(
        'schema $version migration preserves original data and adds versioned plan tables',
        () async {
      final path = '${dir.path}/legacy-$version.sqlite';
      final connection = sqlite3.open(path);
      connection.execute(
          File('test/fixtures/schema_v$version.sql').readAsStringSync());
      connection.execute(
          "UPDATE user_preferences SET display_name='Original learner'");
      connection.dispose();
      final old = AppDatabase(path: path);
      try {
        final d = await old.db;
        expect(d.select('PRAGMA user_version').single['user_version'],
            AppDatabase.schemaVersion);
        expect((await old.getPreferences()).displayName, 'Original learner');
        expect(d.select('SELECT * FROM daily_plans'), isEmpty);
        expect(d.select('SELECT * FROM planned_activities'), isEmpty);
        expect(d.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        old.close();
      }
    });
  }
}
