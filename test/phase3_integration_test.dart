import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/backup/backup_service.dart';
import 'package:lexiflow/core/backup/backup_zip.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/analytics_service.dart';
import 'package:lexiflow/core/services/daily_plan_service.dart';
import 'package:lexiflow/core/services/study_session_service.dart';
import 'package:lexiflow/core/services/shadowing_controller.dart';
import 'package:lexiflow/core/services/recording_service.dart';
import 'package:lexiflow/core/services/practice_timer.dart';

import 'stability_services_test.dart' as fixtures;
import 'support/phase2_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase db;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('lexiflow-phase3-integration-');
    db = AppDatabase(path: '${dir.path}/live.sqlite');
  });
  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });
  Future<void> lesson() async {
    final audio = File('${dir.path}/source.mp3')..writeAsBytesSync([1, 2, 3]);
    await db.insertListeningLesson({
      'id': 'lesson',
      'title': 'Imported audio',
      'audio_path': audio.path,
      'duration_ms': 30000
    });
  }

  test(
      'true/false and written answers persist with a restart-safe submission and objective-only accuracy',
      () async {
    await lesson();
    await db.saveComprehensionQuestion(
        lessonId: 'lesson',
        question: 'Is the statement true?',
        type: 'true_false',
        correct: 'True');
    await db.saveComprehensionQuestion(
        lessonId: 'lesson', question: 'Explain in your words.', type: 'short');
    final questions = await db.getQuestions('lesson');
    final answers = {
      for (final q in questions)
        q['id'] as String:
            q['question_type'] == 'short' ? 'My own explanation.' : 'True'
    };
    final token = await db.comprehensionSubmission('lesson');
    await db.saveComprehensionDraft('lesson', answers);
    await db.submitComprehension('lesson', token, answers);
    db.close();
    db = AppDatabase(path: '${dir.path}/live.sqlite');
    expect(await db.comprehensionSubmission('lesson'), token);
    await db.submitComprehension('lesson', token, answers);
    expect(await db.getComprehensionAttempts('lesson'), hasLength(2));
    final stats = await AnalyticsService(db).listening();
    expect(stats['comprehensionExercises'], 1);
    expect(stats['graded'], 1);
    expect(stats['correct'], 1);
    expect(stats['accuracy'], 1);
    final next = await db.comprehensionSubmission('lesson', retry: true);
    expect(next, isNot(token));
    expect(
        (await db.getListeningLesson('lesson'))!['comprehension_draft'], '{}');
  });
  test(
      'daily plan points to the real bookmarked section without invented material',
      () async {
    await lesson();
    await db.addBookmark('bookmark', 'lesson', 7000,
        label: 'Difficult sentence');
    final study = StudySessionService(db);
    try {
      final plan = await DailyPlanService(db, study).today(goal: 15);
      final item = plan.singleWhere((a) => a['module'] == 'listening_speaking');
      expect(item['route'], '/learn/listening/player/lesson?startMs=7000');
      expect(item['reason'], contains('real bookmarked'));
    } finally {
      study.dispose();
    }
  });
  test(
      'shadowing resumes an existing paused plan timer and does not create another timer',
      () async {
    await lesson();
    var now = DateTime(2026, 11, 14, 12);
    final study = StudySessionService(db, now: () => now);
    final plans = DailyPlanService(db, study, now: () => now);
    final item = (await plans.today(goal: 15))
        .singleWhere((a) => a['module'] == 'listening_speaking');
    await plans.start(item['id'] as String);
    await study.pause();
    final controller = ShadowingController(db, 'lesson',
        study: study,
        reference: MockPracticePlayer(),
        playback: MockPracticePlayer(),
        recorder: RecordingService(
            recorder: fixtures.FakeRecorder(),
            storage: fixtures.FakeStorage('${dir.path}/take.m4a')));
    try {
      await controller.initialize();
      await controller.startRecording();
      expect(study.isRunning, isTrue);
      now = now.add(const Duration(seconds: 90));
      await controller.stopRecording();
      expect(study.isRunning, isFalse);
      await controller.saveTake();
      await plans.complete(item['id'] as String);
      expect(await db.getTotalSecondsForDate('2026-11-14'), 90);
      expect(
          (await db.db).select('SELECT * FROM study_sessions'), hasLength(1));
      expect(await db.getShadowingHistory('lesson'), hasLength(1));
    } finally {
      await controller.close();
      controller.dispose();
      study.dispose();
    }
  });
  test(
      'returning to interrupted practice retains its plan link without counting another module',
      () async {
    await lesson();
    var now = DateTime(2026, 11, 14, 12);
    final study = StudySessionService(db, now: () => now);
    final plans = DailyPlanService(db, study, now: () => now);
    try {
      final activity = (await plans.today(goal: 15))
          .singleWhere((r) => r['module'] == 'listening_speaking');
      await plans.start(activity['id'] as String);
      final timer = PracticeTimer(study, 'listening_speaking');
      await timer.start();
      now = now.add(const Duration(seconds: 60));
      await study.start('vocabulary');
      now = now.add(const Duration(seconds: 20));
      await timer.start();
      now = now.add(const Duration(seconds: 40));
      await timer.finish();
      await plans.complete(activity['id'] as String);
      expect(await db.getTotalSecondsForDate('2026-11-14'), 120);
      expect(
          (await plans.activities('2026-11-14'))
              .singleWhere((a) => a['id'] == activity['id'])['actual_ms'],
          100000);
      expect((await db.db).select('SELECT * FROM plan_sessions'), hasLength(2));
    } finally {
      study.dispose();
    }
  });
  test('disposing while a study start is pending never launches a ghost timer',
      () async {
    final delayed = _DelayedDatabase('${dir.path}/delayed.sqlite');
    final study = StudySessionService(delayed);
    try {
      final start = study.start('listening');
      final assertion = expectLater(start, throwsStateError);
      await delayed.entered.future;
      study.dispose();
      delayed.release.complete();
      await assertion;
      expect(study.isRunning, isFalse);
      final row =
          (await delayed.db).select('SELECT * FROM study_sessions').single;
      expect(row['completed'], 1);
      expect(row['interrupted'], 1);
      expect(row['duration_seconds'], 0);
    } finally {
      delayed.close();
    }
  });
  test(
      'schema 9 playback, transcript and conversation data survive a full backup roundtrip',
      () async {
    await lesson();
    await db.saveListeningPreferences('lesson',
        speed: 0.75,
        startMs: 2000,
        endMs: 5000,
        transcript: 'WEBVTT\n\n00:02.000 --> 00:05.000\nReal saved text.',
        transcriptFormat: 'vtt');
    await db.insertAiConversation('chat',
        title: 'Travel', scenarioId: 'travel');
    final request = await db.beginAiRequest('chat', 'Original message.');
    await db.finishAiRequest(request, 'Mocked provider reply.');
    final feedback = await db.beginAiRequest('chat', 'Requested summary.',
        purpose: 'feedback');
    await db.finishAiRequest(feedback, 'A saved summary.');
    final backup = BackupService(db, dir, availableBytes: () async => 1 << 34);
    final archive = File('${dir.path}/phase3.lexiflowbackup');
    await backup.create(archive);
    await backup.restore(archive);
    db.close();
    db = AppDatabase(path: '${dir.path}/live.sqlite');
    final row = (await db.getListeningLesson('lesson'))!;
    expect(row['playback_speed'], 0.75);
    expect(row['loop_start_ms'], 2000);
    expect(row['transcript_format'], 'vtt');
    expect(File(row['audio_path'] as String).existsSync(), isTrue);
    expect((await db.getAiConversations()).single['scenario_id'], 'travel');
    expect(
        (await db.getAiMessages('chat'))
            .where((m) => m['purpose'] == 'feedback'),
        hasLength(2));
    expect((await db.db).select('PRAGMA foreign_key_check'), isEmpty);
  });
  test(
      'migration recovers exact old scenario markers without guessing user-defined titles',
      () async {
    final legacy = AppDatabase.schemaTemplate(8);
    final path = '${dir.path}/scenario-upgrade.sqlite';
    try {
      final old = await legacy.db;
      old.execute(
          "INSERT INTO ai_conversations(id,title,started_at) VALUES('generated','Conversation · technology','2026-01-01'),('custom','My technical interview','2026-01-01')");
      await legacy.snapshot(path);
    } finally {
      legacy.close();
    }
    final upgraded = AppDatabase(path: path);
    try {
      expect((await upgraded.getAiConversation('generated'))!['scenario_id'],
          'technology');
      expect((await upgraded.getAiConversation('custom'))!['scenario_id'],
          'everyday');
      expect((await upgraded.getAiConversation('custom'))!['title'],
          'My technical interview');
    } finally {
      upgraded.close();
    }
  });
  for (final version in [7, 8, 9]) {
    test(
        'schema $version archive validates before staged upgrade to current schema',
        () async {
      final legacy = AppDatabase.schemaTemplate(version);
      final database = File('${dir.path}/database.sqlite');
      final audio = File('${dir.path}/audio.mp3')..writeAsBytesSync([1, 2, 3]);
      try {
        final old = await legacy.db;
        old.execute(
            "INSERT INTO listening_lessons(id,title,audio_path) VALUES('old','Original audio','media/0.mp3')");
        old.execute(
            "INSERT INTO ai_conversations(id,title,started_at) VALUES('old-chat','Original conversation','2026-01-01')");
        old.execute(
            "INSERT INTO ai_messages(id,conversation_id,role,content,is_local) VALUES('old-message','old-chat','user','Original learner text.',0)");
        await legacy.snapshot(database.path);
      } finally {
        legacy.close();
      }
      final manifest = File('${dir.path}/manifest.json');
      manifest.writeAsStringSync(jsonEncode({
        'format': 'lexiflow',
        'version': 1,
        'databaseVersion': version,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'files': {
          'database.sqlite': {
            'size': await database.length(),
            'sha256': await BackupService.checksum(database)
          },
          'media/0.mp3': {
            'size': await audio.length(),
            'sha256': await BackupService.checksum(audio)
          }
        },
        'media': [
          {
            'table': 'listening_lessons',
            'id': 'old',
            'column': 'audio_path',
            'path': 'media/0.mp3'
          }
        ]
      }));
      final archive = File('${dir.path}/old.lexiflowbackup');
      await BackupZip.write(archive, {
        'database.sqlite': database,
        'media/0.mp3': audio,
        'manifest.json': manifest
      });
      await BackupService(db, dir, availableBytes: () async => 1 << 34)
          .restore(archive);
      db.close();
      db = AppDatabase(path: '${dir.path}/live.sqlite');
      expect((await db.db).select('PRAGMA user_version').single['user_version'],
          AppDatabase.schemaVersion);
      expect((await db.getAiMessages('old-chat')).single['content'],
          'Original learner text.');
      expect((await db.getAiMessages('old-chat')).single['purpose'],
          'conversation');
      expect((await db.getListeningLesson('old'))!['playback_speed'], 1);
      expect(
          (await db.getListeningLesson('old'))!['transcript_format'], 'auto');
    });
  }
}

class _DelayedDatabase extends AppDatabase {
  _DelayedDatabase(String path) : super(path: path);
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<void> insertSession(
      {required String id,
      required String module,
      required DateTime startedAt,
      required String localDate}) async {
    entered.complete();
    await release.future;
    await super.insertSession(
        id: id, module: module, startedAt: startedAt, localDate: localDate);
  }
}
