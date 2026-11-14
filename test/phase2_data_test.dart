import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/analytics_service.dart';
import 'package:lexiflow/core/services/study_session_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late String path;
  late AppDatabase db;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('lexiflow-phase2-');
    path = '${dir.path}/db.sqlite';
    db = AppDatabase(path: path);
  });
  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });
  Future<void> lesson() async => db.insertListeningLesson({
        'id': 'lesson',
        'title': 'Lesson',
        'difficulty': 'B1',
        'audio_path': 'local.mp3',
        'transcript': 'A private transcript.'
      });
  Future<void> objective(String id, {String type = 'mc'}) =>
      db.saveComprehensionQuestion(
          id: null,
          lessonId: 'lesson',
          question: id,
          type: type,
          choices: ['A', 'B'],
          correct: 'A');
  test(
      'all question types persist, grade deterministically, and retain answer snapshots',
      () async {
    await lesson();
    for (final type in ['mc', 'main_idea', 'details', 'intention']) {
      await objective(type, type: type);
    }
    await db.saveComprehensionQuestion(
        lessonId: 'lesson', question: 'Explain it', type: 'short');
    final questions = await db.getQuestions('lesson');
    final answers = <String, String>{};
    for (var i = 0; i < questions.length; i++) {
      answers[questions[i]['id'] as String] = i == 0
          ? 'B'
          : i == 4
              ? 'My own summary'
              : 'A';
    }
    await db.submitComprehension('lesson', 'submission', answers);
    await db.submitComprehension('lesson', 'submission', answers);
    final attempts = await db.getComprehensionAttempts('lesson');
    expect(attempts.length, 5);
    expect(
        attempts
            .where((a) => a['self_assessed'] == 0 && a['is_correct'] == 1)
            .length,
        3);
    final short = attempts.singleWhere((a) => a['self_assessed'] == 1);
    expect(short['is_correct'], isNull);
    await db.selfAssessComprehension(short['id'] as String, true);
    final first = questions.first;
    await db.saveComprehensionQuestion(
        id: first['id'] as String,
        lessonId: 'lesson',
        question: 'Edited after grading',
        type: 'mc',
        choices: ['X', 'Y'],
        correct: 'X');
    final old = attempts.singleWhere((a) => a['question_id'] == first['id']);
    expect((jsonDecode(old['question_snapshot'] as String) as Map)['question'],
        'mc');
    final stats = await db.activityStatistics();
    expect(stats['Objective graded'], 4);
    expect(stats['Objective correct'], 3);
    expect(
        (await db.db)
            .select(
                "SELECT COUNT(*) n FROM learning_activities WHERE type='comprehension_submitted'")
            .single['n'],
        1);
  });
  test(
      'question and submission validation reject invented or empty answer keys',
      () async {
    await lesson();
    await expectLater(
        db.saveComprehensionQuestion(
            lessonId: 'lesson',
            question: 'Question',
            type: 'mc',
            choices: ['A'],
            correct: 'A'),
        throwsArgumentError);
    await expectLater(
        db.saveComprehensionQuestion(
            lessonId: 'lesson',
            question: 'Question',
            type: 'mc',
            choices: ['A', 'B'],
            correct: 'C'),
        throwsArgumentError);
    await expectLater(
        db.submitComprehension('lesson', 's', {}), throwsStateError);
    expect(await db.getComprehensionAttempts('lesson'), isEmpty);
  });
  test('saved answers and transcript reveal survive an offline restart',
      () async {
    await lesson();
    await objective('Question');
    final q = (await db.getQuestions('lesson')).single['id'] as String;
    expect((await db.getListeningLesson('lesson'))!['transcript_revealed'], 0);
    await db.saveComprehensionDraft('lesson', {q: 'A'});
    await db.revealTranscript('lesson');
    db.close();
    db = AppDatabase(path: path);
    final saved = (await db.getListeningLesson('lesson'))!;
    expect(saved['transcript_revealed'], 1);
    expect((jsonDecode(saved['comprehension_draft'] as String) as Map)[q], 'A');
    expect((await db.getQuestions('lesson')).length, 1);
  });
  test(
      'mistakes support validation, editing, review and deletion without placeholder cleanup',
      () async {
    final d = await db.db;
    d.execute(
        "INSERT INTO writing_mistakes(id,original_sentence) VALUES('legacy','Add your sentence here')");
    await expectLater(
        db.saveWritingMistake(
            {'id': 'bad', 'original_sentence': '', 'correction': 'Correct'}),
        throwsArgumentError);
    expect((await db.getWritingMistakes()).single['id'], 'legacy');
    await db.saveWritingMistake({
      'id': 'legacy',
      'original_sentence': 'He go yesterday.',
      'correction': 'He went yesterday.',
      'grammar_topic': 'past tense',
      'explanation': 'Use the past tense.'
    });
    await db.markMistakeReviewed('legacy');
    db.close();
    db = AppDatabase(path: path);
    final m = (await db.getWritingMistakes()).single;
    expect(m['correction'], 'He went yesterday.');
    expect(m['review_status'], 'understood');
    await db.deleteWritingMistake('legacy');
    expect(await db.getWritingMistakes(), isEmpty);
  });
  test(
      'revision restore preserves current content, empty drafts, labels and immutable originals',
      () async {
    await db.upsertWritingEntry(
        {'id': 'draft', 'title': 'Draft', 'body': 'Original', 'word_count': 1});
    await db.saveWritingRevision({
      'id': 'old',
      'entry_id': 'draft',
      'body': 'Original',
      'word_count': 1,
      'label': 'Original label'
    });
    await db.saveWritingRevision({
      'id': 'duplicate',
      'entry_id': 'draft',
      'body': 'Original',
      'word_count': 1,
      'label': 'Original label'
    });
    expect((await db.getWritingRevisions('draft')).length, 1);
    await db.upsertWritingEntry(
        {'id': 'draft', 'title': 'Draft', 'body': '', 'word_count': 0});
    await db.restoreWritingRevision('draft', 'old');
    final history = await db.getWritingRevisions('draft');
    expect(history.length, 2);
    expect(history.first['body'], '');
    expect(history.last['id'], 'old');
    expect(history.last['label'], 'Original label');
    expect((await db.getWritingEntry('draft'))!['body'], 'Original');
    await db.restoreWritingRevision('draft', 'old');
    expect((await db.getWritingRevisions('draft')).length, 2);
    db.close();
    db = AppDatabase(path: path);
    expect((await db.getWritingRevisions('draft')).length, 2);
    await expectLater(
        db.restoreWritingRevision('missing', 'old'), throwsStateError);
  });
  test(
      'AI writing feedback preserves the submitted draft without overwriting newer edits',
      () async {
    await db.upsertWritingEntry({
      'id': 'draft',
      'title': 'Draft',
      'body': 'Newer text',
      'word_count': 2
    });
    await db.saveAiWritingFeedback(
        'draft', 'Earlier text', 'Actual mocked AI feedback');
    expect((await db.getWritingEntry('draft'))!['body'], 'Newer text');
    expect(
        (await db.getWritingRevisions('draft')).single['body'], 'Earlier text');
    final feedback = (await db.getWritingFeedback('draft')).single;
    expect(feedback['source'], 'ai');
    expect(feedback['body_snapshot'], 'Earlier text');
  });
  test(
      'conversation management and interrupted requests preserve ordering and prevent duplicates',
      () async {
    await db.insertAiConversation('c', title: 'Old title');
    await db.renameAiConversation('c', 'New title');
    final request =
        await db.beginAiRequest('c', 'My English message', id: 'request');
    await db.setAiRequestState(request, 'interrupted');
    expect(
        (await db.getAiMessages('c')).single['request_state'], 'interrupted');
    await db.finishAiRequest(request, 'An actual mocked response');
    await db.finishAiRequest(
        request, 'Duplicate must not replace the response');
    final messages = await db.getAiMessages('c');
    expect(messages.length, 2);
    expect(messages.first['role'], 'user');
    expect(messages.last['is_local'], 0);
    expect(messages.last['content'], 'An actual mocked response');
    expect((await db.getAiConversations()).single['message_count'], 2);
    db.close();
    db = AppDatabase(path: path);
    expect((await db.getAiConversations()).single['title'], 'New title');
    await db.deleteAiConversation('c');
    await db.finishAiRequest(request, 'Late response after deletion');
    expect(await db.getAiMessages('c'), isEmpty);
    expect(await db.getAiConversations(), isEmpty);
  });
  test(
      'shadowing drafts, confirmation, deletion queue and history remain transactional',
      () async {
    await lesson();
    await db.saveShadowingRecording(
        attemptId: 'attempt',
        lessonId: 'lesson',
        path: 'recording.m4a',
        startMs: 1000,
        endMs: 3000,
        durationMs: 1700,
        saved: false);
    expect((await db.getShadowingHistory('lesson')).single['saved'], 0);
    expect((await db.activityStatistics())['Shadowing attempts'], 0);
    await db.confirmShadowingAttempt('attempt');
    await db.confirmShadowingAttempt('attempt');
    expect((await db.activityStatistics())['Shadowing attempts'], 1);
    expect(
        (await db.db)
            .select(
                "SELECT COUNT(*) n FROM learning_activities WHERE type='shadowing_saved'")
            .single['n'],
        1);
    db.close();
    db = AppDatabase(path: path);
    expect((await db.getShadowingHistory('lesson')).single['audio_path'],
        'recording.m4a');
    await db.deleteShadowingAttempt('attempt');
    expect(await db.getShadowingHistory('lesson'), isEmpty);
    expect(await db.getRecordings(), isEmpty);
    expect(await db.pendingFileDeletions(), ['recording.m4a']);
  });
  test('real activity counters never invent study minutes', () async {
    await lesson();
    await objective('Question');
    final q = (await db.getQuestions('lesson')).single['id'] as String;
    await db.submitComprehension('lesson', 's', {q: 'A'});
    await db.insertAiConversation('c');
    await db.beginAiRequest('c', 'Saved practice');
    await db.saveWritingMistake(
        {'id': 'm', 'original_sentence': 'He go.', 'correction': 'He goes.'});
    final snapshot = await AnalyticsService(db).build();
    expect(snapshot.activityCounts['Comprehension answers'], 1);
    expect(snapshot.activityCounts['AI practice messages'], 1);
    expect(snapshot.activityCounts['Open mistakes'], 1);
    expect(snapshot.totalMinutes, 0);
  });
  test('AI waiting time is excluded, including waiting across midnight',
      () async {
    var now = DateTime(2026, 11, 10, 23, 59, 50);
    final timer = StudySessionService(db, now: () => now);
    await timer.start('ai_teacher');
    now = now.add(const Duration(seconds: 5));
    await timer.withoutAiWaitingTime(() async {
      expect(timer.isRunning, isFalse);
      expect(timer.isAwaitingAi, isTrue);
      now = now.add(const Duration(seconds: 70));
      timer.resume();
      expect(timer.isRunning, isFalse);
    });
    expect(timer.isRunning, isTrue);
    now = now.add(const Duration(seconds: 5));
    await timer.finish();
    expect(await db.getTotalStudySeconds(), 10);
    expect(await db.getTotalSecondsForDate('2026-11-10'), 5);
    expect(await db.getTotalSecondsForDate('2026-11-11'), 5);
    timer.dispose();
  });
  test(
      'overlapping AI requests and app interruption cannot resume a background timer',
      () async {
    var now = DateTime(2026, 11, 11, 10);
    final timer = StudySessionService(db, now: () => now);
    await timer.start('ai_teacher');
    now = now.add(const Duration(seconds: 10));
    final a = Completer<void>(), b = Completer<void>();
    final first = timer.withoutAiWaitingTime(() => a.future);
    final second = timer.withoutAiWaitingTime(() => b.future);
    await Future<void>.delayed(Duration.zero);
    now = now.add(const Duration(minutes: 2));
    b.complete();
    await second;
    expect(timer.isRunning, isFalse);
    await timer.onAppPaused();
    a.complete();
    await first;
    expect(timer.isRunning, isFalse);
    await timer.finish();
    expect(await db.getTotalStudySeconds(), 10);
    timer.dispose();
  });
  test(
      'schema v5 upgrade preserves prior content, history, timers and certificates',
      () async {
    final raw = sqlite3.open(path);
    raw.execute(File('test/fixtures/schema_v5.sql').readAsStringSync());
    raw.execute(
        "INSERT INTO writing_entries(id,title,body) VALUES('w','Title','Keep my draft')");
    raw.execute(
        "INSERT INTO writing_revisions(id,entry_id,body) VALUES('r','w','Keep my original')");
    raw.execute(
        "INSERT INTO writing_mistakes(id,original_sentence) VALUES('legacy','Add your sentence here')");
    raw.execute(
        "INSERT INTO ai_conversations(id,title,started_at) VALUES('c','Keep chat','2026-01-01')");
    raw.execute(
        "INSERT INTO ai_messages(id,conversation_id,role,content) VALUES('a','c','assistant','Legacy local note')");
    raw.execute(
        "INSERT INTO reading_articles(id,title,body,created_at,updated_at) VALUES('article','Article','Keep text','2026-01-01','2026-01-01')");
    raw.execute(
        "INSERT INTO study_sessions(id,module,started_at,local_date,duration_seconds,completed) VALUES('s','reading','2026-01-01','2026-01-01',30,1)");
    raw.execute(
        "INSERT INTO study_session_days VALUES('s','2026-01-01',30000)");
    raw.execute(
        "INSERT INTO completion_records(id,target_type,target_id,target_title,verification_type,completed_at) VALUES('old','book','b','Legacy','legacy','2026-01-01')");
    raw.execute(
        "INSERT INTO certificates(id,completion_id,learner_name,title,ref_number,verification_type,issued_at) VALUES('cert','old','Name','Legacy','LF-OLD','legacy','2026-01-01')");
    raw.dispose();
    expect((await db.getWritingEntry('w'))!['body'], 'Keep my draft');
    expect(
        (await db.getWritingRevisions('w')).single['body'], 'Keep my original');
    expect((await db.getWritingMistakes()).single['id'], 'legacy');
    expect((await db.getAiMessages('c')).single['is_local'], 1);
    expect((await db.getArticle('article'))!['body'], 'Keep text');
    expect(await db.getTotalStudySeconds(), 30);
    expect((await db.getCertificates()).single['ref_number'], 'LF-OLD');
    expect((await db.db).select('PRAGMA user_version').single['user_version'],
        AppDatabase.schemaVersion);
    expect((await db.db).select('PRAGMA foreign_key_check'), isEmpty);
  });
}
