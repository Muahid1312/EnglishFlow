import 'dart:async';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/content/assessment_bank.dart';
import 'package:lexiflow/core/content/grammar_curriculum.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/ai_teacher_service.dart';
import 'package:lexiflow/core/services/media_storage.dart';
import 'package:lexiflow/core/services/recording_service.dart';
import 'package:record/record.dart';
import 'package:sqlite3/sqlite3.dart';

class FakeRecorder extends AudioRecorder {
  bool permitted = true;
  bool disposed = false;
  bool active = false;
  bool failStart = false;
  bool failStop = false;
  bool emptyStop = false;
  int starts = 0;
  String? path;
  Completer<void>? starting;
  @override
  Future<bool> hasPermission() async => permitted;
  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    starts++;
    this.path = path;
    File(path).writeAsBytesSync([1, 2, 3]);
    if (failStart) throw StateError('start failed');
    if (starting != null) await starting!.future;
    active = true;
  }

  @override
  Future<String?> stop() async {
    if (failStop) throw StateError('stop failed');
    active = false;
    return emptyStop ? null : path;
  }

  @override
  Future<void> cancel() async {
    active = false;
  }

  @override
  Future<bool> isRecording() async => active;
  @override
  Future<void> dispose() async {
    disposed = true;
    active = false;
  }
}

class FakeStorage extends MediaStorage {
  FakeStorage(this.path);
  final String path;
  @override
  Future<String> recordingPath({String folder = 'speaking'}) async => path;
}

class TestSecureStorage extends FlutterSecureStorage {
  final values = <String, String>{};
  bool failWrite = false;
  bool failRead = false;
  @override
  Future<void> write(
      {required String key,
      required String? value,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (failWrite) throw StateError('secure write failed');
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read(
      {required String key,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (failRead) throw StateError('secure read failed');
    return values[key];
  }

  @override
  Future<void> delete(
      {required String key,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('lexiflow-stability-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('recording start failure and cancellation delete partial files',
      () async {
    final path = '${dir.path}/take.m4a';
    final native = FakeRecorder()..failStart = true;
    final service =
        RecordingService(recorder: native, storage: FakeStorage(path));
    await expectLater(service.start(), throwsStateError);
    expect(File(path).existsSync(), isFalse);
    native.failStart = false;
    await service.start();
    await service.cancel();
    expect(File(path).existsSync(), isFalse);
    await service.dispose();
    expect(native.disposed, isTrue);
  });
  test(
      'dispose during asynchronous start cancels and releases the native recorder',
      () async {
    final path = '${dir.path}/take.m4a';
    final native = FakeRecorder()..starting = Completer<void>();
    final service =
        RecordingService(recorder: native, storage: FakeStorage(path));
    final starting = service.start();
    // Allow permission and storage futures to finish before disposal.
    await Future<void>.delayed(Duration.zero);
    final disposed = service.dispose();
    native.starting!.complete();
    expect(await starting, isNull);
    await disposed;
    expect(native.disposed, isTrue);
    expect(native.active, isFalse);
    expect(File(path).existsSync(), isFalse);
  });
  test(
      'duplicate start is rejected; successful stop retains a playable file reference',
      () async {
    final native = FakeRecorder();
    final path = '${dir.path}/take.m4a';
    final service =
        RecordingService(recorder: native, storage: FakeStorage(path));
    await service.start();
    await expectLater(service.start(), throwsStateError);
    final take = await service.stop();
    expect(take!.path, path);
    expect(take.durationMs, greaterThanOrEqualTo(0));
    expect(native.starts, 1);
    await service.dispose();
    expect(File(path).existsSync(), isTrue);
  });
  test('denied permission creates no file and failed/empty stops clean up',
      () async {
    final native = FakeRecorder()..permitted = false;
    final path = '${dir.path}/take.m4a';
    final service =
        RecordingService(recorder: native, storage: FakeStorage(path));
    expect(await service.start(), isNull);
    expect(native.starts, 0);
    native.permitted = true;
    await service.start();
    native.failStop = true;
    await expectLater(service.stop(), throwsStateError);
    expect(File(path).existsSync(), isFalse);
    native.failStop = false;
    native.emptyStop = true;
    await service.start();
    expect(await service.stop(), isNull);
    expect(File(path).existsSync(), isFalse);
    await service.dispose();
  });
  test(
      'credential update is one atomic secure write; legacy keys remain readable',
      () async {
    final storage = TestSecureStorage();
    storage.values
        .addAll({'ai_provider': 'openAi', 'ai_api_key': 'old-test-key'});
    final service = SecureAiTeacherService(storage: storage);
    expect(await service.getConfiguredProvider(), AiProvider.openAi);
    storage.failWrite = true;
    await expectLater(service.saveApiKey(AiProvider.anthropic, 'new-test-key'),
        throwsStateError);
    expect(await service.getConfiguredProvider(), AiProvider.openAi);
    expect(storage.values['ai_api_key'], 'old-test-key');
    storage.failWrite = false;
    await service.saveApiKey(AiProvider.anthropic, 'new-test-key');
    expect(await service.getConfiguredProvider(), AiProvider.anthropic);
    expect((await service.checkStatus()).isReady, isTrue);
    await service.clearCredentials();
    expect(await service.hasCredentials(), isFalse);
    storage.failRead = true;
    expect((await service.checkStatus()).availability, AiAvailability.error);
  });
  test(
      'partial curriculum, assessment and speaking seeds repair without overwriting progress',
      () async {
    final db = AppDatabase(path: '${dir.path}/test.sqlite');
    addTearDown(db.close);
    await GrammarCurriculum.seedIfEmpty(db);
    final lessons = await db.getGrammarLessons();
    final first = lessons.first['id'] as String;
    await db.markGrammarLessonComplete(first);
    final exercises = await db.getGrammarExercises(first);
    (await db.db).execute(
        'DELETE FROM grammar_exercises WHERE id=?', [exercises.first['id']]);
    await GrammarCurriculum.seedIfEmpty(db);
    expect((await db.getGrammarLesson(first))!['completed'], 1);
    expect((await db.getGrammarExercises(first)).length, exercises.length);
    await AssessmentBank.seedIfEmpty(db);
    final a = (await db.getAssessments()).first['id'] as String;
    final questions = await db.getAssessmentQuestions(a);
    (await db.db).execute(
        'DELETE FROM assessment_questions WHERE id=?', [questions.first['id']]);
    await AssessmentBank.seedIfEmpty(db);
    expect((await db.getAssessmentQuestions(a)).length, questions.length);
    await db.insertSpeakingPrompt({
      'id': 'custom',
      'title': 'Custom',
      'difficulty': 'B1',
      'category': 'custom',
      'prompt_text': 'Keep this'
    });
    await db.seedBuiltinPromptsIfEmpty();
    final count = await db.countSpeakingPrompts();
    expect(count, greaterThan(1));
    await db.seedBuiltinPromptsIfEmpty();
    expect(await db.countSpeakingPrompts(), count);
    expect(
        (await db.getSpeakingPrompts(category: 'custom')).single['prompt_text'],
        'Keep this');
  });
  test('AI history is bounded in memory and preserves full database history',
      () async {
    final db = AppDatabase(path: '${dir.path}/test.sqlite');
    addTearDown(db.close);
    await db.insertAiConversation('c', title: 'Conversation · free');
    for (var i = 0; i < 130; i++) {
      await db.insertAiMessage('m$i', 'c', 'user', 'Message $i');
    }
    final history = await db.getAiMessages('c');
    expect(history.length, 100);
    expect(history.first['content'], 'Message 30');
    expect(history.last['content'], 'Message 129');
    expect((await db.getAiConversations()).single['message_count'], 130);
    expect(
        (await db.db).select('SELECT COUNT(*) c FROM ai_messages').first['c'],
        130);
  });
  test('AI message and conversation counter roll back together', () async {
    final db = AppDatabase(path: '${dir.path}/test.sqlite');
    addTearDown(db.close);
    await db.insertAiConversation('c');
    (await db.db).execute(
        "CREATE TRIGGER fail_counter BEFORE UPDATE OF message_count ON ai_conversations BEGIN SELECT RAISE(ABORT,'test failure'); END");
    await expectLater(db.insertAiMessage('m', 'c', 'user', 'Retain input'),
        throwsA(isA<SqliteException>()));
    expect(await db.getAiMessages('c'), isEmpty);
    expect((await db.getAiConversations()).single['message_count'], 0);
  });
}
