import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/backup/backup_service.dart';
import 'package:lexiflow/core/backup/backup_zip.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase db;
  late BackupService service;
  late File archive;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('lexiflow-backup-v2-');
    db = AppDatabase(path: '${dir.path}/live.sqlite');
    service = BackupService(db, dir,
        availableBytes: () async => 8 * 1024 * 1024 * 1024);
    archive = File('${dir.path}/learning.lexiflowbackup');
    await db.saveArticle('Dari متن', 'A durable article.');
    await db.saveVocabulary(
        word: 'preserve', sentence: 'Preserve the original context.');
    final d = await db.db;
    d.execute(
        "INSERT INTO writing_entries(id,title,body) VALUES('writing','Journal','Keep my writing')");
    final media = Directory('${dir.path}/media')..createSync();
    File('${media.path}/book.pdf').writeAsBytesSync([37, 80, 68, 70, 1, 2, 3]);
    File('${media.path}/audio.mp3').writeAsBytesSync([1, 3, 5, 7]);
    File('${media.path}/record.m4a').writeAsBytesSync([2, 4, 6, 8]);
    d.execute(
        "INSERT INTO imported_books(id,title,file_path) VALUES('book','My book',?)",
        ['${media.path}/book.pdf']);
    d.execute(
        "INSERT INTO listening_lessons(id,title,audio_path) VALUES('audio','My audio',?)",
        ['${media.path}/audio.mp3']);
    d.execute(
        "INSERT INTO speaking_recordings(id,audio_path) VALUES('record',?)",
        ['${media.path}/record.m4a']);
  });
  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });

  void reopen() {
    db.close();
    db = AppDatabase(path: '${dir.path}/live.sqlite');
    service = BackupService(db, dir,
        availableBytes: () async => 8 * 1024 * 1024 * 1024);
  }

  Future<Map<String, File>> unpack() async {
    final target = await Directory(
            '${dir.path}/unpack-${DateTime.now().microsecondsSinceEpoch}')
        .create();
    return BackupZip.extract(archive, target);
  }

  Future<void> rewrite(Future<void> Function(Map<String, File>) modify,
      {bool rehash = false}) async {
    final files = await unpack();
    await modify(files);
    if (rehash) {
      final manifest = jsonDecode(await files['manifest.json']!.readAsString())
          as Map<String, dynamic>;
      for (final entry
          in files.entries.where((e) => e.key != 'manifest.json')) {
        (manifest['files'] as Map)[entry.key] = {
          'size': await entry.value.length(),
          'sha256': await BackupService.checksum(entry.value)
        };
      }
      await files['manifest.json']!.writeAsString(jsonEncode(manifest));
    }
    await BackupZip.write(archive, files);
  }

  Future<void> unchangedAfterFailure(File bad) async {
    await db.saveArticle(
        'Current installation', 'Must survive rejected restore.');
    await expectLater(service.restore(bad), throwsA(anything));
    reopen();
    expect(
        (await db.getArticles())
            .any((a) => a['title'] == 'Current installation'),
        isTrue);
    expect(await db.getVocabulary(), hasLength(1));
  }

  test(
      'WAL snapshot, records, Unicode and media survive validated portable restore',
      () async {
    (await db.db).execute('PRAGMA journal_mode=WAL');
    await service.create(archive);
    final files = await unpack();
    expect(files.keys, containsAll(['manifest.json', 'database.sqlite']));
    expect(files.keys.where((k) => k.startsWith('media/')), hasLength(3));
    await db.saveArticle('Added later', 'Replaced only after a valid restore.');
    final old = db;
    await service.restore(archive);
    await expectLater(old.getArticles(), throwsStateError);
    reopen();
    expect(await db.getArticles(), hasLength(1));
    expect((await db.getArticles()).single['title'], 'Dari متن');
    expect((await db.getVocabulary()).single['word'], 'preserve');
    final d = await db.db;
    expect(d.select('SELECT body FROM writing_entries').single['body'],
        'Keep my writing');
    for (final table in [
      'imported_books',
      'listening_lessons',
      'speaking_recordings'
    ]) {
      final column = table == 'imported_books' ? 'file_path' : 'audio_path';
      final path =
          d.select('SELECT $column FROM $table').single[column] as String;
      expect(File(path).existsSync(), isTrue);
      expect(path, contains('restored-media-'));
    }
    expect(await service.hasRecovery(), isTrue);
    await service.recoverPrevious();
    reopen();
    expect(await db.getArticles(), hasLength(2));
    expect(File('${dir.path}/media/book.pdf').existsSync(), isTrue);
  });

  test('no secure storage, cache, logs or arbitrary documents are exported',
      () async {
    File('${dir.path}/credentials.json').writeAsStringSync('secret');
    File('${dir.path}/debug.log').writeAsStringSync('private log');
    await service.create(archive);
    final files = await unpack();
    expect(files.length, 5);
    expect(
        files.keys.any((k) => k.contains('credentials') || k.contains('log')),
        isFalse);
  });

  test('missing media rejects export and does not record success', () async {
    File('${dir.path}/media/audio.mp3').deleteSync();
    await expectLater(service.create(archive), throwsA(isA<BackupFailure>()));
    expect(await archive.exists(), isFalse);
    expect((await db.db).select('SELECT * FROM backup_metadata'), isEmpty);
  });

  test('insufficient storage rejects export and restore before replacement',
      () async {
    await service.create(archive);
    service = BackupService(db, dir, availableBytes: () async => 0);
    await expectLater(service.create(File('${dir.path}/second.lexiflowbackup')),
        throwsA(isA<BackupFailure>()));
    await unchangedAfterFailure(archive);
  });

  test(
      'interrupted export cleans partial file and preserves an existing destination',
      () async {
    service = BackupService(db, dir,
        availableBytes: () async => 1 << 34,
        fault: (point) {
          if (point == 'export-written') {
            throw StateError('simulated interruption');
          }
        });
    await expectLater(service.create(archive), throwsStateError);
    expect(await archive.exists(), isFalse);
    expect(
        dir.listSync().where((e) =>
            e.path.contains('partial') || e.path.contains('backup-work')),
        isEmpty);
    archive.writeAsStringSync('existing file');
    await expectLater(service.create(archive), throwsA(isA<BackupFailure>()));
    expect(archive.readAsStringSync(), 'existing file');
  });

  test('corrupted database records fail integrity validation', () async {
    final d = await db.db;
    d.execute('PRAGMA foreign_keys=OFF');
    d.execute(
        "INSERT INTO vocabulary_reviews(id,entry_id,next_review_at) VALUES('orphan','missing','2020-01-01')");
    await expectLater(service.create(archive), throwsA(isA<BackupFailure>()));
    expect(archive.existsSync(), isFalse);
  });

  test('invalid archive preserves the installation', () async {
    archive.writeAsStringSync('not a ZIP archive');
    await unchangedAfterFailure(archive);
  });

  test('truncated archive and CRC corruption preserve the installation',
      () async {
    await service.create(archive);
    final bytes = await archive.readAsBytes();
    final corrupted = File('${dir.path}/bad.lexiflowbackup');
    corrupted.writeAsBytesSync(bytes.sublist(0, bytes.length - 5));
    await unchangedAfterFailure(corrupted);
    bytes[60] ^= 1;
    corrupted.writeAsBytesSync(bytes);
    await expectLater(service.restore(corrupted), throwsA(anything));
  });

  test('valid ZIP with altered media fails SHA256 validation', () async {
    await service.create(archive);
    await rewrite((files) async {
      await files.entries
          .firstWhere((e) => e.key.startsWith('media/'))
          .value
          .writeAsBytes([9]);
    });
    await unchangedAfterFailure(archive);
  });

  test('incompatible backup version cannot overwrite data', () async {
    await service.create(archive);
    await rewrite((files) async {
      final f = files['manifest.json']!;
      final manifest =
          jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      manifest['version'] = 999;
      await f.writeAsString(jsonEncode(manifest));
    });
    await unchangedAfterFailure(archive);
  });

  test('unexpected SQLite triggers rejected even with recomputed checksums',
      () async {
    await service.create(archive);
    await rewrite((files) async {
      final d = sqlite3.open(files['database.sqlite']!.path);
      d.execute(
          "CREATE TRIGGER unsafe AFTER INSERT ON reading_articles BEGIN DELETE FROM vocabulary_entries; END");
      d.dispose();
    }, rehash: true);
    await unchangedAfterFailure(archive);
  });

  test('arbitrary media paths rejected even with checksums', () async {
    await service.create(archive);
    await rewrite((files) async {
      final d = sqlite3.open(files['database.sqlite']!.path);
      d.execute("UPDATE imported_books SET file_path='/etc/passwd'");
      d.dispose();
    }, rehash: true);
    await unchangedAfterFailure(archive);
  });

  for (final point in [
    'restore-staged',
    'restore-replaced',
    'restore-validated'
  ]) {
    test('failure at $point preserves current records and media', () async {
      await service.create(archive);
      service = BackupService(db, dir,
          availableBytes: () async => 1 << 34,
          fault: (p) {
            if (p == point) throw StateError('injected failure');
          });
      await unchangedAfterFailure(archive);
      expect(
          File('${dir.path}/media/audio.mp3').readAsBytesSync(), [1, 3, 5, 7]);
      expect(File('${dir.path}/live.sqlite.restore-pending').existsSync(),
          isFalse);
    });
  }

  test('process restart recovers a pending database replacement', () async {
    await db.snapshot('${dir.path}/live.sqlite.previous');
    await db.saveArticle(
        'Uncommitted replacement', 'Should roll back on restart.');
    db.close();
    File('${dir.path}/live.sqlite.restore-pending')
        .writeAsStringSync('pending', flush: true);
    db = AppDatabase(path: '${dir.path}/live.sqlite');
    expect(await db.getArticles(), hasLength(1));
    expect(
        File('${dir.path}/live.sqlite.restore-pending').existsSync(), isFalse);
  });

  test(
      'SQLite snapshot contains WAL transactions without requiring a checkpoint',
      () async {
    final d = await db.db;
    d.execute('PRAGMA journal_mode=WAL');
    d.execute('PRAGMA wal_autocheckpoint=0');
    await db.saveArticle('In WAL', 'Newest committed transaction.');
    final output = File('${dir.path}/snapshot.sqlite');
    await db.snapshot(output.path);
    final snapshot = sqlite3.open(output.path, mode: OpenMode.readOnly);
    expect(snapshot.select('SELECT * FROM reading_articles'), hasLength(2));
    expect(
        snapshot.select('PRAGMA integrity_check').single.values.single, 'ok');
    snapshot.dispose();
  });

  test(
      'ZIP profile rejects traversal, links, compression and oversized entries before payload extraction',
      () async {
    for (final name in [
      '../escape',
      '/etc/passwd',
      'media/../escape',
      'media/x\\y',
      'media//x'
    ]) {
      expect(() => BackupZip.checkName(name), throwsFormatException);
    }
    await service.create(archive);
    final original = await archive.readAsBytes();
    final end = ByteData.sublistView(original, original.length - 22);
    final central = end.getUint32(16, Endian.little);
    for (final mutate in <void Function(ByteData)>[
      (b) => b.setUint16(central + 10, 8, Endian.little),
      (b) => b.setUint32(central + 38, 0xa1ff0000, Endian.little),
      (b) =>
          b.setUint32(central + 24, BackupZip.maxFileBytes + 1, Endian.little),
      (b) => b.setUint32(central + 42, 1, Endian.little),
    ]) {
      final bytes = Uint8List.fromList(original);
      mutate(ByteData.sublistView(bytes));
      final unsafe = File('${dir.path}/unsafe.lexiflowbackup')
        ..writeAsBytesSync(bytes);
      final stage = Directory(
          '${dir.path}/unsafe-${DateTime.now().microsecondsSinceEpoch}')
        ..createSync();
      await expectLater(
          BackupZip.extract(unsafe, stage), throwsFormatException);
    }
  });
}
