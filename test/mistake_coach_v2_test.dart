import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/daily_plan_service.dart';
import 'package:lexiflow/core/services/mistake_coach.dart';
import 'package:lexiflow/core/services/practice_timer.dart';
import 'package:lexiflow/core/services/study_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase db;
  late MistakeCoach coach;
  late DateTime now;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('lexiflow-mistakes-v2-');
    db = AppDatabase(path: '${dir.path}/db.sqlite');
    now = DateTime(2026, 11, 14, 12);
    coach = MistakeCoach(db, now: () => now);
  });
  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });
  Future<Map<String, dynamic>> mistake(String id,
      {String category = 'Verb tenses'}) async {
    await db.saveWritingMistake({
      'id': id,
      'original_sentence': 'He go to school $id.',
      'correction': 'He goes to school $id.',
      'grammar_topic': category,
      'explanation': 'Third-person present simple.',
      'source_label': 'Manual'
    });
    return (await db.getWritingMistakes()).singleWhere((r) => r['id'] == id);
  }

  test('creation, editing, manual category, source and date persist', () async {
    final first = await mistake('one');
    await db.saveWritingMistake({
      ...first,
      'grammar_topic': 'Subject–verb agreement',
      'explanation': 'Edited explanation'
    });
    final edited = (await db.getWritingMistakes()).single;
    expect(edited['created_at'], first['created_at']);
    expect(edited['source_label'], 'Manual');
    expect(edited['grammar_topic'], 'Subject–verb agreement');
    expect(edited['revision'], (first['revision'] as int) + 1);
    db.close();
    db = AppDatabase(path: '${dir.path}/db.sqlite');
    expect((await db.getWritingMistakes()).single['explanation'],
        'Edited explanation');
  });
  test('normalized duplicate corrections are rejected without overwriting data',
      () async {
    final first = await mistake('one');
    await expectLater(
        db.saveWritingMistake({
          ...first,
          'id': 'duplicate',
          'original_sentence': ' He   go to school one. ',
          'correction': ' He goes to school one. '
        }),
        throwsStateError);
    expect(await db.getWritingMistakes(), hasLength(1));
    final other = await mistake('two');
    await expectLater(
        db.saveWritingMistake({
          ...other,
          'original_sentence': first['original_sentence'],
          'correction': first['correction']
        }),
        throwsStateError);
    expect(
        (await db.getWritingMistakes())
            .singleWhere((r) => r['id'] == 'two')['original_sentence'],
        other['original_sentence']);
  });
  test('confirmed writing correction links source without changing the draft',
      () async {
    final d = await db.db;
    d.execute(
        "INSERT INTO writing_entries(id,title,body) VALUES('draft','Journal','The original writing stays untouched.')");
    await db.saveWritingMistake({
      'id': 'from-writing',
      'entry_id': 'draft',
      'source_label': 'Writing: Journal',
      'original_sentence': 'She have a book.',
      'correction': 'She has a book.',
      'grammar_topic': 'Subject–verb agreement'
    });
    expect((await db.getWritingEntry('draft'))!['body'],
        'The original writing stays untouched.');
    expect((await db.getWritingMistakes()).single['entry_id'], 'draft');
    await db.deleteWritingEntry('draft');
    expect((await db.getWritingMistakes()).single['entry_id'], isNull);
    expect((await db.getWritingMistakes()).single['source_label'],
        'Writing: Journal');
  });
  test(
      'objective matching is explicit and attempts commit once with immutable snapshots',
      () async {
    final m = await mistake('one');
    await coach.answer(
        attemptId: 'attempt',
        mistakeId: 'one',
        expectedRevision: m['revision'] as int,
        response: ' He   goes to school one. ');
    await coach.answer(
        attemptId: 'attempt',
        mistakeId: 'one',
        expectedRevision: m['revision'] as int,
        response: ' He   goes to school one. ');
    expect((await db.getWritingMistakes()).single['repetitions'], 1);
    expect(
        (await db.getWritingMistakes()).single['review_status'], 'understood');
    final d = await db.db;
    final attempt = d.select('SELECT * FROM mistake_practice_attempts').single;
    expect(attempt['mode'], 'exact');
    expect(attempt['is_correct'], 1);
    await db.saveWritingMistake(
        {...m, 'correction': 'He usually goes to school one.'});
    expect(
        d
            .select('SELECT * FROM mistake_practice_attempts')
            .single['correction_snapshot'],
        'He goes to school one.');
    await expectLater(
        coach.answer(
            attemptId: 'new',
            mistakeId: 'one',
            expectedRevision: m['revision'] as int,
            response: 'old wording'),
        throwsStateError);
  });
  test(
      'self assessment is recorded separately and does not inflate objective improvement',
      () async {
    final m = await mistake('one');
    await coach.answer(
        attemptId: 'self',
        mistakeId: 'one',
        expectedRevision: m['revision'] as int,
        response: 'A different natural rewrite.',
        selfAssessment: true);
    final attempt =
        (await db.db).select('SELECT * FROM mistake_practice_attempts').single;
    expect(attempt['mode'], 'self');
    expect(attempt['is_correct'], 1);
    expect((await coach.insights())['attempts'], 0);
    expect((await coach.insights())['trend'], isNull);
  });
  test(
      'capitalization corrections remain meaningful during matching and duplicate checks',
      () async {
    await db.saveWritingMistake({
      'id': 'case',
      'original_sentence': 'i am learning.',
      'correction': 'I am learning.',
      'grammar_topic': 'Other'
    });
    final row = (await db.getWritingMistakes()).single;
    await coach.answer(
        attemptId: 'case-answer',
        mistakeId: 'case',
        expectedRevision: row['revision'] as int,
        response: 'i am learning.');
    expect(
        (await db.db)
            .select('SELECT is_correct FROM mistake_practice_attempts')
            .single['is_correct'],
        0);
    expect((await db.getWritingMistakes()).single['review_status'], 'open');
  });
  test(
      'deleting hides mistakes while preserving attempt history and foreign keys',
      () async {
    final m = await mistake('one');
    await coach.answer(
        attemptId: 'a',
        mistakeId: 'one',
        expectedRevision: m['revision'] as int,
        response: 'wrong');
    await db.deleteWritingMistake('one');
    expect(await db.getWritingMistakes(), isEmpty);
    expect(await coach.practice(), isEmpty);
    expect((await db.db).select('SELECT * FROM mistake_practice_attempts'),
        hasLength(1));
    expect((await db.db).select('PRAGMA foreign_key_check'), isEmpty);
    expect(await coach.categories(), isEmpty);
  });
  test('weakness recommendation requires evidence and never one correct answer',
      () async {
    final one = await mistake('one');
    await coach.answer(
        attemptId: 'single',
        mistakeId: 'one',
        expectedRevision: one['revision'] as int,
        response: one['correction'] as String);
    expect(await coach.weaknesses(), isEmpty);
    await mistake('two');
    await mistake('three');
    final weak = await coach.weaknesses();
    expect(weak.single['records'], 3);
    expect(weak.single['category'], 'Verb tenses');
  });
  test('repeated objective errors support a category and practice stays short',
      () async {
    final m = await mistake('one');
    for (var i = 0; i < 3; i++) {
      await coach.answer(
          attemptId: 'wrong$i',
          mistakeId: 'one',
          expectedRevision: m['revision'] as int,
          response: 'Not the saved correction.');
      now = now.add(const Duration(minutes: 1));
    }
    expect((await coach.weaknesses()).single['errors'], 3);
    for (var i = 0; i < 8; i++) {
      await mistake('extra$i');
    }
    expect(await coach.practice(), hasLength(5));
    expect((await coach.categories()).single['repeated'], 1);
  });
  test(
      'daily plan uses a real evidenced mistake category and existing timer only once',
      () async {
    for (final id in ['one', 'two', 'three']) {
      await mistake(id);
    }
    final sessions = StudySessionService(db, now: () => now);
    try {
      final rows =
          await DailyPlanService(db, sessions, now: () => now).today(goal: 30);
      final activity =
          rows.singleWhere((r) => r['module'] == 'grammar_writing');
      expect(activity['route'],
          '/learn/grammar/mistakes/practice?category=Verb+tenses');
      final plan = DailyPlanService(db, sessions, now: () => now);
      await plan.start(activity['id'] as String);
      final timer = PracticeTimer(sessions, 'grammar_writing');
      await timer.start();
      now = now.add(const Duration(minutes: 2));
      await timer.finish();
      expect(sessions.hasActive, isTrue); // reused plan timer remains paused
      expect(sessions.isRunning, isFalse);
      await plan.complete(activity['id'] as String);
      expect(await db.getTotalSecondsForDate('2026-11-14'), 120);
      expect(
          (await db.db).select('SELECT * FROM study_sessions'), hasLength(1));
    } finally {
      sessions.dispose();
    }
  });
}
