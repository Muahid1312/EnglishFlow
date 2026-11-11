import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/certificate_service.dart';
import 'package:lexiflow/core/services/study_session_service.dart';
import 'package:lexiflow/core/utils/date_utils.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String path;
  late AppDatabase db;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('lexiflow-test-');
    path = '${dir.path}/test.sqlite';
    db = AppDatabase(path: path);
  });
  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });

  test('concurrent first access shares one migrated connection and preference',
      () async {
    final connections = await Future.wait(List.generate(20, (_) => db.db));
    expect(connections.every((d) => identical(d, connections.first)), isTrue);
    expect(
        connections.first.select('PRAGMA user_version').first['user_version'],
        6);
    expect(
        connections.first
            .select('SELECT COUNT(*) c FROM user_preferences')
            .first['c'],
        1);
    expect(connections.first.select('PRAGMA foreign_key_check'), isEmpty);
  });

  test('v1 upgrade preserves user records and adds all later tables', () async {
    final d = sqlite3.open(path);
    d.execute(File('test/fixtures/schema_v1.sql').readAsStringSync());
    d.execute("UPDATE user_preferences SET display_name='Preserve me'");
    d.execute(
        "INSERT INTO vocabulary_entries(id,word) VALUES ('word','persist')");
    d.dispose();
    db.close();
    db = AppDatabase(path: path);
    expect((await db.getPreferences()).displayName, 'Preserve me');
    expect(await db.getSavedWordCount(), 1);
    expect(await db.getWritingEntries(), isEmpty);
    expect(await db.getCertificates(), isEmpty);
    expect((await db.db).select('PRAGMA foreign_key_check'), isEmpty);
  });

  test('failed migration rolls back schema and version and can be retried',
      () async {
    final raw = sqlite3.open(path);
    raw.execute('CREATE TABLE playback_bookmarks (broken TEXT)');
    raw.dispose();
    await expectLater(db.db, throwsA(isA<SqliteException>()));
    final check = sqlite3.open(path);
    expect(check.select('PRAGMA user_version').first['user_version'], 0);
    expect(
        check.select(
            "SELECT name FROM sqlite_master WHERE name='user_preferences'"),
        isEmpty);
    check.execute('DROP TABLE playback_bookmarks');
    check.dispose();
    expect((await db.getPreferences()).dailyTargetMinutes, 60);
  });

  test('writing and revisions survive reopen; deleting draft preserves mistake',
      () async {
    await db.upsertWritingEntry({
      'id': 'draft',
      'title': 'Title',
      'body': 'Original text',
      'word_count': 2
    });
    await db.saveWritingRevision({
      'id': 'rev',
      'entry_id': 'draft',
      'body': 'Original text',
      'word_count': 2
    });
    await db.upsertWritingEntry(
        {'id': 'draft', 'title': 'Title', 'body': 'New text', 'word_count': 2});
    await db.saveWritingMistake({
      'id': 'mistake',
      'entry_id': 'draft',
      'original_sentence': 'Sentence',
      'correction': 'Corrected sentence'
    });
    db.close();
    db = AppDatabase(path: path);
    expect((await db.getWritingEntry('draft'))!['body'], 'New text');
    expect((await db.getWritingRevisions('draft')).single['body'],
        'Original text');
    await db.deleteWritingEntry('draft');
    expect((await db.getWritingMistakes()).single['entry_id'], isNull);
  });

  test('seven-day totals exclude eighth day and future dates', () async {
    final now = DateTime.now();
    for (final offset in [-7, -6, 0, 1]) {
      await db.insertSession(
          id: 's$offset',
          module: 'reading',
          startedAt: now,
          localDate:
              localDateString(DateTime(now.year, now.month, now.day + offset)));
      await db.updateSession('s$offset', completed: true, durationSeconds: 60);
    }
    final rows = await db.getSessionsLastDays(7);
    expect(rows.length, 2);
    expect(
        rows.fold<int>(0, (sum, r) => sum + (r['total_seconds'] as int)), 120);
  });

  test('due review count uses real dates and ignores unsaved words', () async {
    final d = await db.db;
    d.execute(
        "INSERT INTO vocabulary_entries(id,word,is_saved) VALUES ('a','a',1),('b','b',0)");
    final future = '${localDateString()} 23:59:59';
    d.execute(
        "INSERT INTO vocabulary_reviews(id,entry_id,next_review_at) VALUES ('r1','a','2000-01-01'),('r2','a','2000-01-01'),('r3','b','2000-01-01')");
    expect(await db.getDueReviewCount(), 1);
    d.execute(
        'UPDATE vocabulary_reviews SET next_review_at = ? WHERE entry_id = ?',
        [future, 'a']);
    expect(await db.getDueReviewCount(), 0);
  });

  test('ungraded grammar attempts do not lower accuracy', () async {
    final d = await db.db;
    d.execute(
        "INSERT INTO grammar_lessons(id,title,cefr_level,topic_key,objective,explanation,examples,common_mistakes) VALUES ('l','t','B1','k','o','e','e','m')");
    d.execute(
        "INSERT INTO grammar_exercises(id,lesson_id,question_type,prompt,explanation) VALUES ('e','l','text','p','e')");
    for (final item in [('a', 1), ('b', null)]) {
      await db.saveGrammarAttempt({
        'id': item.$1,
        'exercise_id': 'e',
        'lesson_id': 'l',
        'is_correct': item.$2
      });
    }
    expect(await db.grammarAccuracy(), 1);
  });

  test('certificate rejects UI eligibility without a persisted pass', () async {
    await expectLater(
        CertificateService(db).issue(
            learnerName: 'Name',
            targetType: 'assessment',
            targetId: 'missing',
            targetTitle: 'Fake',
            verificationType: 'assessment_pass',
            assessmentScore: 1,
            eligible: true),
        throwsStateError);
    expect(await db.getCertificates(), isEmpty);
    expect(await db.getCompletionRecords(), isEmpty);
  });

  test(
      'certificate evidence rejects failed, unfinished and self-assessed attempts',
      () async {
    await db.insertAssessmentDefinition(
        {'id': 'a', 'title': 'Real title', 'category': 'grammar'});
    await db.insertAssessmentQuestion({
      'id': 'q',
      'assessment_id': 'a',
      'question_type': 'mc',
      'prompt': 'p',
      'correct_answer': 'A'
    });
    Future<void> attempt(String id, double score,
            {int self = 0, String? completed = '2026-01-01'}) =>
        db.saveAssessmentAttempt({
          'id': id,
          'assessment_id': 'a',
          'score': score,
          'max_score': 1,
          'passed': 1,
          'self_assessed': self,
          'started_at': '2026-01-01',
          'completed_at': completed
        });
    await attempt('fail', 0.5);
    await attempt('self', 1, self: 1);
    await attempt('unfinished', 1, completed: null);
    expect(await db.certificateEvidence('assessment', 'a'), isNull);
    await attempt('pass', 0.8);
    expect((await db.certificateEvidence('assessment', 'a'))!['title'],
        'Real title');
    expect(await db.certificateEvidence('book', 'a'), isNull);
  });

  test('certificate PDF fits long text and persists matching records',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => dir.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null));
    await db.insertAssessmentDefinition({
      'id': 'a',
      'title': List.filled(30, 'Long course title').join(' '),
      'category': 'grammar'
    });
    await db.insertAssessmentQuestion({
      'id': 'q',
      'assessment_id': 'a',
      'question_type': 'mc',
      'prompt': 'p',
      'correct_answer': 'A'
    });
    await db.saveAssessmentAttempt({
      'id': 'pass',
      'assessment_id': 'a',
      'score': 0.8,
      'max_score': 1,
      'passed': 1,
      'started_at': '2026-01-01',
      'completed_at': '2026-01-01'
    });
    final output = await CertificateService(db).issue(
        learnerName: List.filled(30, 'Long learner name').join(' '),
        targetType: 'assessment',
        targetId: 'a',
        targetTitle: 'Caller title',
        verificationType: 'assessment_pass');
    final file = File(output);
    expect(file.existsSync(), isTrue);
    expect(String.fromCharCodes(file.readAsBytesSync().take(5)), '%PDF-');
    expect((await db.getCertificates()).length, 1);
    expect((await db.getCompletionRecords()).length, 1);
    expect((await db.db).select('PRAGMA foreign_key_check'), isEmpty);
  });

  test('session finish is idempotent and pause checkpoints survive restart',
      () async {
    final service = StudySessionService(db);
    await service.start('reading');
    await service.pause();
    final row = await db.getActiveInterruptedSession();
    expect(row, isNotNull);
    final recovered = StudySessionService(db);
    await recovered.recoverInterrupted();
    expect(recovered.active!.state, SessionState.paused);
    await Future.wait([recovered.finish(), recovered.finish()]);
    final d = await db.db;
    expect(
        d.select('SELECT COUNT(*) c FROM learning_activities').first['c'], 1);
    expect(d.select('SELECT completed FROM study_sessions').single['completed'],
        1);
    service.dispose();
    recovered.dispose();
  });

  test('session timing excludes background pause and counts resumed time once',
      () async {
    var now = DateTime(2026, 11, 10, 10);
    final service = StudySessionService(db, now: () => now);
    await service.start('reading');
    now = now.add(const Duration(seconds: 65));
    await service.onAppPaused();
    now = now.add(const Duration(hours: 2));
    service.resume();
    now = now.add(const Duration(seconds: 60));
    await service.finish();
    expect(await db.getTotalStudySeconds(), 125);
    expect(await db.getTotalSecondsForDate('2026-11-10'), 125);
    service.dispose();
  });

  test('paused copy clears run timestamp', () {
    final active = ActiveSession(
        id: 'a',
        module: 'reading',
        startedAt: DateTime.now(),
        accumulatedSeconds: 3,
        runStartedAt: DateTime.now(),
        state: SessionState.running);
    expect(
        active
            .copyWith(runStartedAt: null, state: SessionState.paused)
            .runStartedAt,
        isNull);
  });
}
