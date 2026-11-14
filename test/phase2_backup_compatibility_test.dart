import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/backup/backup_service.dart';
import 'package:lexiflow/core/backup/backup_zip.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/mistake_coach.dart';
import 'package:lexiflow/core/services/vocabulary_intelligence.dart';
import 'package:lexiflow/core/services/review_schedule.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase db;
  late BackupService backup;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('lexiflow-phase2-backup-');
    db = AppDatabase(path: '${dir.path}/live.sqlite');
    backup = BackupService(db, dir, availableBytes: () async => 1 << 34);
  });
  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });
  void reopen() {
    db.close();
    db = AppDatabase(path: '${dir.path}/live.sqlite');
    backup = BackupService(db, dir, availableBytes: () async => 1 << 34);
  }

  test(
      'current-schema backup restores enriched words, queue positions and mistake attempts',
      () async {
    final word = await db.saveVocabulary(
        word: 'preserve',
        definition: 'keep safe',
        translation: 'حفظ کردن',
        sentence: 'Preserve the original.',
        collocations: 'preserve context',
        personalNotes: 'My note');
    final second =
        await db.saveVocabulary(word: 'continue', definition: 'keep going');
    final now = DateTime.now().toUtc().add(const Duration(minutes: 1));
    final practice = VocabularyIntelligence(db, now: () => now);
    final session = await practice.open(limit: 5);
    final item = (await practice.items(session)).first;
    await practice.reveal(session, item['position'] as int);
    await practice.rate(session, item, ReviewRating.good);
    await practice.pause(session);
    await db.saveWritingMistake({
      'id': 'mistake',
      'original_sentence': 'He go.',
      'correction': 'He goes.',
      'grammar_topic': 'Verb tenses',
      'source_label': 'Manual'
    });
    final mistake = (await db.getWritingMistakes()).single;
    await MistakeCoach(db).answer(
        attemptId: 'answer',
        mistakeId: 'mistake',
        expectedRevision: mistake['revision'] as int,
        response: 'He goes.');
    final archive = File('${dir.path}/learning.lexiflowbackup');
    await backup.create(archive);
    await db.saveVocabulary(word: 'not in backup');
    await backup.restore(archive);
    reopen();
    final restored = await db.getVocabulary();
    expect(restored, hasLength(2));
    expect(restored.singleWhere((r) => r['id'] == word)['personal_notes'],
        'My note');
    expect(restored.any((r) => r['id'] == second), isTrue);
    final resumed = VocabularyIntelligence(db, now: () => now);
    expect(await resumed.open(), session);
    final items = await resumed.items(session);
    expect(items.where((r) => r['item_state'] == 'reviewed'), hasLength(1));
    expect(items.where((r) => r['item_state'] == 'pending'), hasLength(1));
    expect((await db.getWritingMistakes()).single['repetitions'], 1);
    expect((await db.db).select('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
      'a real Phase 1 schema 7 archive validates before staging migration to the current schema',
      () async {
    final legacy = AppDatabase.schemaTemplate(7);
    final snapshot = File('${dir.path}/database.sqlite');
    try {
      final d = await legacy.db;
      d.execute(
          "INSERT INTO vocabulary_entries(id,word,normalized_word,contexts_json) VALUES('old','original','original','[]')");
      d.execute(
          "INSERT INTO vocabulary_reviews(id,entry_id,next_review_at) VALUES('schedule','old','2026-01-01')");
      d.execute(
          "INSERT INTO writing_mistakes(id,original_sentence,correction,grammar_topic) VALUES('old-m','I is.','I am.','Verb tenses')");
      await legacy.snapshot(snapshot.path);
    } finally {
      legacy.close();
    }
    final manifest = File('${dir.path}/manifest.json');
    manifest.writeAsStringSync(jsonEncode({
      'format': 'lexiflow',
      'version': 1,
      'databaseVersion': 7,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'files': {
        'database.sqlite': {
          'size': await snapshot.length(),
          'sha256': await BackupService.checksum(snapshot)
        }
      },
      'media': []
    }));
    final archive = File('${dir.path}/phase1.lexiflowbackup');
    await BackupZip.write(
        archive, {'database.sqlite': snapshot, 'manifest.json': manifest});
    await backup.restore(archive);
    reopen();
    expect((await db.db).select('PRAGMA user_version').single['user_version'],
        AppDatabase.schemaVersion);
    expect((await db.getVocabulary()).single['word'], 'original');
    expect((await db.getVocabulary()).single['personal_notes'], isNull);
    expect((await db.getWritingMistakes()).single['correction'], 'I am.');
    expect((await db.getWritingMistakes()).single['dedup_key'], isNotNull);
  });

  test(
      'schema 7 migration retains legacy duplicate mistakes and review history',
      () async {
    final legacy = AppDatabase.schemaTemplate(7);
    final snapshot = '${dir.path}/upgrade.sqlite';
    try {
      final d = await legacy.db;
      d.execute(
          "INSERT INTO writing_mistakes(id,original_sentence,correction) VALUES('a','I is.','I am.'),('b','I is.','I am.')");
      await legacy.snapshot(snapshot);
    } finally {
      legacy.close();
    }
    final upgraded = AppDatabase(path: snapshot);
    try {
      final rows = await upgraded.getWritingMistakes();
      expect(rows, hasLength(2));
      expect(rows[0]['dedup_key'], rows[1]['dedup_key']);
      await upgraded.saveWritingMistake(
          {...rows.first, 'explanation': 'Keep both historical records.'});
      expect(await upgraded.getWritingMistakes(), hasLength(2));
      await expectLater(
          upgraded.saveWritingMistake(
              {'id': 'c', 'original_sentence': 'I is.', 'correction': 'I am.'}),
          throwsStateError);
      expect((await upgraded.db).select('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      upgraded.close();
    }
  });
}
