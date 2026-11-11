import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/recording_service.dart';
import 'package:lexiflow/core/services/shadowing_controller.dart';
import 'package:lexiflow/core/services/study_session_service.dart';

import 'stability_services_test.dart' as f;
import 'support/phase2_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase db;
  late f.FakeRecorder native;
  late MockPracticePlayer reference, playback;
  late ShadowingController controller;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('shadow-test-');
    db = AppDatabase(path: '${dir.path}/db.sqlite');
    await db.insertListeningLesson({
      'id': 'lesson',
      'title': 'Lesson',
      'audio_path': 'reference.mp3',
      'difficulty': 'B1'
    });
    native = f.FakeRecorder();
    reference = MockPracticePlayer();
    playback = MockPracticePlayer();
    controller = ShadowingController(db, 'lesson',
        reference: reference,
        playback: playback,
        recorder: RecordingService(
            recorder: native, storage: f.FakeStorage('${dir.path}/take.m4a')));
    await controller.initialize();
  });
  tearDown(() async {
    await controller.close();
    controller.dispose();
    db.close();
    dir.deleteSync(recursive: true);
  });
  test(
      'segment playback, recording, comparison, save and deletion use real persisted attempts',
      () async {
    controller.setSegment(1000, 4000);
    await controller.playReference();
    expect(reference.playing, isTrue);
    expect(reference.start, 1000);
    expect(reference.end, 4000);
    await controller.startRecording();
    expect(reference.playing, isFalse);
    expect(controller.recording, isTrue);
    await controller.stopRecording();
    expect(controller.pending, isNotNull);
    final draft = (await db.getShadowingHistory('lesson')).single;
    expect(draft['saved'], 0);
    await controller.playTake(controller.pending!.path);
    expect(playback.playing, isTrue);
    await controller.playReference();
    expect(playback.playing, isFalse);
    await controller.saveTake();
    expect(controller.pending, isNull);
    final saved = (await db.getShadowingHistory('lesson')).single;
    expect(saved['saved'], 1);
    expect((await db.getRecordings()).length, 1);
    final file = File(saved['audio_path'] as String);
    expect(file.existsSync(), isTrue);
    await controller.deleteTake(saved['id'] as String);
    expect(await db.getShadowingHistory('lesson'), isEmpty);
    expect(file.existsSync(), isFalse);
    expect(await db.pendingFileDeletions(), isEmpty);
  });
  test('permission refusal never creates a fake recording or attempt',
      () async {
    native.permitted = false;
    await controller.startRecording();
    expect(controller.recording, isFalse);
    expect(controller.error, contains('permission'));
    expect(await db.getShadowingHistory('lesson'), isEmpty);
    expect(await db.getRecordings(), isEmpty);
  });
  test(
      'rapid starts and interruptions are serialized and preserve a stopped draft',
      () async {
    native.starting = Completer<void>();
    final start = controller.startRecording();
    await Future<void>.delayed(Duration.zero);
    final duplicate = controller.startRecording();
    final interruption = controller.onPaused();
    native.starting!.complete();
    await start;
    await duplicate;
    await interruption;
    expect(native.starts, 1);
    expect(controller.recording, isFalse);
    expect((await db.getShadowingHistory('lesson')).single['saved'], 0);
    expect(controller.foreground, isFalse);
  });
  test(
      'draft survives controller close and database reopen without deleting audio',
      () async {
    await controller.startRecording();
    await controller.close();
    final draft = (await db.getShadowingHistory('lesson')).single;
    expect(draft['saved'], 0);
    expect(File(draft['audio_path'] as String).existsSync(), isTrue);
    controller.dispose();
    db.close();
    db = AppDatabase(path: '${dir.path}/db.sqlite');
    reference = MockPracticePlayer();
    playback = MockPracticePlayer();
    controller = ShadowingController(db, 'lesson',
        reference: reference,
        playback: playback,
        recorder: RecordingService(
            recorder: f.FakeRecorder(),
            storage: f.FakeStorage('${dir.path}/next.m4a')));
    await controller.initialize();
    expect(controller.pending!.id, draft['id']);
    await controller.saveTake();
    expect((await db.getShadowingHistory('lesson')).single['saved'], 1);
  });
  test('native recording failure recovers without producing placeholder files',
      () async {
    native.failStart = true;
    await controller.startRecording();
    expect(controller.recording, isFalse);
    expect(controller.error, isNotNull);
    expect(File('${dir.path}/take.m4a').existsSync(), isFalse);
    native.failStart = false;
    await controller.startRecording();
    await controller.stopRecording();
    await controller.saveTake();
    expect((await db.getShadowingHistory('lesson')).length, 1);
  });
  test(
      'an existing timed session is reused rather than double-counting recording time',
      () async {
    await controller.close();
    controller.dispose();
    final study = StudySessionService(db);
    final existing = await study.start('listening_speaking');
    controller = ShadowingController(db, 'lesson',
        study: study,
        reference: MockPracticePlayer(),
        playback: MockPracticePlayer(),
        recorder: RecordingService(
            recorder: f.FakeRecorder(),
            storage: f.FakeStorage('${dir.path}/other.m4a')));
    await controller.initialize();
    await controller.startRecording();
    await controller.stopRecording();
    await controller.saveTake();
    expect(study.active!.id, existing.id);
    expect(
        (await db.db)
            .select('SELECT COUNT(*) n FROM study_sessions')
            .single['n'],
        1);
    await study.finish();
    study.dispose();
  });
}
