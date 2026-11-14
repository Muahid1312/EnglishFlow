import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:lexiflow/core/backup/backup_service.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/ai_teacher_service.dart';
import 'package:lexiflow/core/services/course_study_service.dart';

import 'stability_services_test.dart' as fixtures;
import 'support/phase2_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase database;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('lexiflow-final-');
    database = AppDatabase(path: '${directory.path}/learning.sqlite');
  });
  tearDown(() {
    database.close();
    directory.deleteSync(recursive: true);
  });

  test('new assessment certificates require keyed answers, not stored flags', () async {
    await database.insertAssessmentDefinition({'id': 'assessment', 'title': 'Real test', 'category': 'grammar'});
    await database.insertAssessmentQuestion({'id': 'question', 'assessment_id': 'assessment', 'question_type': 'mc', 'prompt': 'Question', 'correct_answer': 'Yes'});
    await database.saveAssessmentAttempt({'id': 'attempt', 'assessment_id': 'assessment', 'score': 1, 'max_score': 1, 'passed': 1, 'self_assessed': 0, 'started_at': '2026-01-01', 'completed_at': '2026-01-01'});
    expect(await database.certificateEvidence('assessment', 'assessment'), isNull);
    final d = await database.db;
    d.execute('UPDATE assessment_attempts SET answers_json=?', ['{"question":"No"}']);
    expect(await database.certificateEvidence('assessment', 'assessment'), isNull);
    d.execute('UPDATE assessment_attempts SET answers_json=?', ['{"question":"Yes"}']);
    expect((await database.certificateEvidence('assessment', 'assessment'))!['score'], 1);
    d.execute('UPDATE assessment_attempts SET max_score=100');
    expect(await database.certificateEvidence('assessment', 'assessment'), isNull);
  });

  test('tightened eligibility does not alter historical certificate metadata', () async {
    final d = await database.db;
    d.execute("INSERT INTO completion_records(id,target_type,target_id,target_title,verification_type,completed_at) VALUES('completion','assessment','missing','Old title','assessment_pass','2025-01-01')");
    d.execute("INSERT INTO certificates(id,completion_id,learner_name,title,ref_number,verification_type,issued_at) VALUES('certificate','completion','Learner','Old title','LF-HISTORY','assessment_pass','2025-01-01')");
    final before = (await database.getCertificates()).single;
    expect(await database.certificateEvidence('assessment', 'missing'), isNull);
    expect((await database.getCertificates()).single, before);
  });

  test('snapshot media added during export preflight cannot leak outside files', () async {
    final outside = Directory.systemTemp.createTempSync('lexiflow-private-');
    addTearDown(() => outside.deleteSync(recursive: true));
    final privateFile = File('${outside.path}/private.pdf')..writeAsStringSync('Private test fixture');
    final destination = File('${directory.path}/backup.lexiflowbackup');
    var injected = false;
    final backup = BackupService(database, directory, availableBytes: () async {
      if (!injected) {
        injected = true;
        (await database.db).execute('INSERT INTO imported_books(id,title,file_path) VALUES(?,?,?)', ['raced', 'Concurrent import', privateFile.path]);
      }
      return 1 << 34;
    });
    await expectLater(backup.create(destination), throwsA(isA<BackupFailure>()));
    expect(destination.existsSync(), isFalse);
    expect(privateFile.readAsStringSync(), 'Private test fixture');
    expect(directory.listSync().any((f) => f.path.contains('.backup-work-')), isFalse);
    expect((await database.db).select('SELECT * FROM imported_books'), hasLength(1));
  });

  test('custom endpoint changes require explicit key re-entry', () async {
    final transport = MockAiTransport();
    final ai = SecureAiTeacherService(storage: fixtures.TestSecureStorage(), transport: transport);
    const original = AiConfiguration(provider: AiProvider.custom, model: 'test', endpoint: 'https://first.example/v1/chat');
    const changed = AiConfiguration(provider: AiProvider.custom, model: 'test', endpoint: 'https://second.example/v1/chat');
    await ai.saveConfiguration(original, apiKey: 'dummy-first-key');
    await expectLater(ai.saveConfiguration(changed), throwsA(isA<AiFailure>()));
    expect((await ai.getConfiguration()).endpoint, original.endpoint);
    expect(transport.calls, 0);
    await ai.complete(const [AiMessage('user', 'Test request')]);
    expect(transport.uri!.host, 'first.example');
    await ai.saveConfiguration(changed, apiKey: 'dummy-second-key');
    await ai.complete(const [AiMessage('user', 'Test request')]);
    expect(transport.uri!.host, 'second.example');
    expect(transport.headers!['Authorization'], 'Bearer dummy-second-key');
  });

  test('nonfinite course threshold cannot partially edit course metadata', () async {
    final service = CourseStudyService(database);
    final id = await service.saveCourse(title: 'Preserved title');
    for (final invalid in [double.nan, double.infinity, -1.0, 1.1]) {
      await expectLater(service.saveCourse(id: id, title: 'Must not save', minimumScore: invalid), throwsArgumentError);
    }
    final row = (await database.db).select('SELECT title,minimum_score FROM courses WHERE id=?', [id]).single;
    expect(row['title'], 'Preserved title');
    expect(row['minimum_score'], 0.7);
    await service.saveCourse(id: id, title: 'Changed together', minimumScore: 0.9);
    expect((await database.db).select('SELECT minimum_score FROM courses WHERE id=?', [id]).single['minimum_score'], 0.9);
  });
  test('corrupt rollback snapshot cannot erase a surviving installation', () async {
    await database.saveArticle('Retained writing', 'Keep the surviving database.');
    final path = await database.databasePath;
    database.close();
    final live = File(path);
    final before = sha256.convert(live.readAsBytesSync()).toString();
    File('$path.previous').writeAsStringSync('corrupt snapshot');
    final journal = File('$path.restore-pending')..writeAsStringSync('pending');
    expect(() => AppDatabase.recoverReplacement(path), throwsA(anything));
    expect(sha256.convert(live.readAsBytesSync()).toString(), before);
    expect(journal.existsSync(), isTrue);
  });

  test('empty SQLite rollback snapshot is rejected before replacement', () async {
    await database.saveArticle('Keep', 'Do not replace this with an empty DB.');
    final path = await database.databasePath;
    database.close();
    sqlite3.open('$path.previous').dispose();
    File('$path.restore-pending').writeAsStringSync('pending');
    final before = sha256.convert(File(path).readAsBytesSync()).toString();
    expect(() => AppDatabase.recoverReplacement(path), throwsStateError);
    expect(sha256.convert(File(path).readAsBytesSync()).toString(), before);
    expect(File('$path.restore-pending').existsSync(), isTrue);
  });

  test('valid rollback stages previous data and retains its recovery copy', () async {
    await database.saveArticle('Before restore', 'The saved recovery record.');
    final path = await database.databasePath;
    await database.snapshot('$path.previous');
    await database.saveArticle('Later data', 'Replaced only by a verified rollback.');
    database.close();
    File('$path.restore-pending').writeAsStringSync('pending');
    AppDatabase.recoverReplacement(path);
    database = AppDatabase(path: path);
    expect((await database.getArticles()).single['title'], 'Before restore');
    expect(File('$path.previous').existsSync(), isTrue);
    expect(File('$path.restore-pending').existsSync(), isFalse);
    expect(directory.listSync().any((f) => f.path.contains('.recovering-')), isFalse);
  });

}
