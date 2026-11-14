import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../database/app_database.dart';
import '../utils/id_utils.dart';
import 'backup_zip.dart';

class BackupFailure implements Exception {
  const BackupFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Backups contain only a SQLite snapshot and explicitly referenced learning
/// files. Secure storage, shared preferences, caches and arbitrary folders are
/// never enumerated. Restore stages all data and retains the previous database
/// and media for recovery; the multi-file procedure is not claimed atomic.
class BackupService {
  BackupService(this.database, this.documents,
      {Future<int> Function()? availableBytes, this.fault})
      : _availableBytes = availableBytes ?? (() async =>
          (await const MethodChannel('lexiflow/backup')
              .invokeMethod<int>('availableBytes', {'path': documents.path}))!);

  final AppDatabase database;
  final Directory documents;
  final Future<int> Function() _availableBytes;
  final void Function(String point)? fault;
  bool _busy = false;
  static const formatVersion = 1;
  static const _mediaColumns = {
    'imported_books': ['file_path'],
    'courses': ['cover_path'],
    'listening_lessons': ['audio_path', 'transcript_path'],
    'speaking_recordings': ['audio_path'],
  };

  static Future<String> checksum(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<void> _space(int needed) async {
    if (await _availableBytes() < needed + 16 * 1024 * 1024) {
      throw const BackupFailure('Not enough free storage. Free some space and retry.');
    }
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_busy) throw const BackupFailure('Another backup operation is running.');
    _busy = true;
    try {
      return await action();
    } on FileSystemException {
      throw const BackupFailure('Could not read or write backup files. Check storage and file access.');
    } on SqliteException {
      throw const BackupFailure('The learning database could not be validated. Reopen learning data to recover any pending replacement.');
    } finally {
      _busy = false;
    }
  }

  static List<Map<String, String>> _references(Database db) {
    final refs = <Map<String, String>>[];
    for (final table in _mediaColumns.entries) {
      for (final row in db.select('SELECT * FROM ${table.key} ORDER BY id')) {
        for (final column in table.value) {
          if (!row.keys.contains(column)) continue;
          final value = row[column] as String?;
          if (value == null || value.isEmpty) continue;
          refs.add({'table': table.key, 'id': row['id'] as String,
            'column': column, 'path': value});
        }
      }
    }
    return refs;
  }

  Future<File> _checkedMedia(String path) async {
    final file = File(path);
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.file ||
        !p.isWithin(await documents.resolveSymbolicLinks(),
            await file.resolveSymbolicLinks())) {
      throw const BackupFailure(
          'A referenced media file is missing or outside managed storage. Restore access before backing up.');
    }
    return file;
  }

  Future<void> _validateDatabase(File file, {bool allowLegacy=false}) async {
    final candidate = sqlite3.open(file.path, mode: OpenMode.readOnly);
    AppDatabase? template;
    try {
      candidate.execute('PRAGMA trusted_schema=OFF');
      final version=candidate.select('PRAGMA user_version').single['user_version'] as int;
      if (version != AppDatabase.schemaVersion && !(allowLegacy && [7,8,9,10].contains(version))) {
        throw const BackupFailure('This backup needs a compatible LexiFlow version.');
      }
      template=AppDatabase.schemaTemplate(version);
      final expected = await template.db;
      List<String> schema(Database db) => db.select(
          "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY type,name")
          .map((r) => jsonEncode(r.values.toList())).toList();
      if (jsonEncode(schema(candidate)) != jsonEncode(schema(expected))) {
        throw const BackupFailure('Unexpected database structure in backup.');
      }
      if (candidate.select('PRAGMA integrity_check').single.values.single != 'ok' ||
          candidate.select('PRAGMA foreign_key_check').isNotEmpty ||
          candidate.select('SELECT id FROM user_preferences').length != 1) {
        throw const BackupFailure('Backup database integrity check failed.');
      }
      final prefs = UserPreference.fromRow(candidate.select('SELECT * FROM user_preferences').single);
      if (prefs.dailyTargetMinutes <= 0 || jsonDecode(prefs.learningPriorities) is! List ||
          candidate.select('SELECT id FROM study_sessions WHERE duration_seconds<0').isNotEmpty) {
        throw const BackupFailure('Backup contains invalid learning preferences or study durations.');
      }
      for (final row in candidate.select('SELECT contexts_json FROM vocabulary_entries')) {
        if (jsonDecode(row['contexts_json'] as String) is! List) {
          throw const BackupFailure('Backup contains invalid vocabulary context.');
        }
      }
      for (final row in candidate.select('SELECT last_success_at FROM backup_metadata')) {
        if (DateTime.tryParse(row['last_success_at'] as String) == null) {
          throw const BackupFailure('Backup contains invalid backup history.');
        }
      }
    } finally {
      candidate.dispose();
      template?.close();
    }
  }

  Future<File> create(File destination, {void Function(String)? progress}) =>
      _exclusive(() async {
    if (await destination.exists()) throw const BackupFailure('Choose a new backup filename.');
    final live = await database.db;
    var estimated = (live.select('PRAGMA page_count').single.values.single as int) *
        (live.select('PRAGMA page_size').single.values.single as int);
    for (final ref in _references(live)) {
      final file = await _checkedMedia(ref['path']!);
      estimated += await file.length();
    }
    if (estimated > BackupZip.maxBytes - 1024 * 1024) {
      throw const BackupFailure('This backup exceeds the 512 MiB format limit.');
    }
    await _space(estimated * 4);
    final work = await Directory(p.join(documents.path, '.backup-work-${newId()}')).create();
    final partial = File('${destination.path}.partial-${newId()}');
    try {
      progress?.call('Taking a consistent database snapshot…');
      final snapshot = File(p.join(work.path, 'database.sqlite'));
      await database.snapshot(snapshot.path);
      await _validateDatabase(snapshot);
      final files = <String, File>{'database.sqlite': snapshot};
      final mapping = <Map<String, String>>[];
      final copy = sqlite3.open(snapshot.path);
      try {
        // Pending deletions and generated certificate paths are installation-local.
        copy.execute('DELETE FROM pending_file_deletions');
        copy.execute('UPDATE certificates SET file_path=NULL');
        for (final ref in _references(copy)) {
          final name = 'media/${mapping.length}${p.extension(ref['path']!).replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '')}';
          BackupZip.checkName(name);
          // Validate the actual snapshot, not just the earlier live preflight:
          // an import may have committed while the space check was awaiting IO.
          files[name] = await _checkedMedia(ref['path']!);
          mapping.add({...ref, 'path': name});
          copy.execute('UPDATE ${ref['table']} SET ${ref['column']}=? WHERE id=?', [name, ref['id']]);
        }
      } finally {
        copy.dispose();
      }
      final checks = <String, Object?>{};
      for (final item in files.entries) {
        checks[item.key] = {'size': await item.value.length(), 'sha256': await checksum(item.value)};
      }
      final manifest = File(p.join(work.path, 'manifest.json'));
      await manifest.writeAsString(jsonEncode({
        'format': 'lexiflow', 'version': formatVersion,
        'databaseVersion': AppDatabase.schemaVersion,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'files': checks, 'media': mapping,
      }), flush: true);
      files['manifest.json'] = manifest;
      progress?.call('Writing and verifying backup…');
      await BackupZip.write(partial, files);
      fault?.call('export-written');
      final check = await Directory(p.join(work.path, 'verification')).create();
      await _validate(partial, check);
      await partial.rename(destination.path);
      return destination;
    } finally {
      if (await partial.exists()) await partial.delete();
      await work.delete(recursive: true);
    }
  });

  Future<Map<String, File>> _validate(File archive, Directory stage) async {
    final files = await BackupZip.extract(archive, stage);
    if (!files.containsKey('manifest.json') || !files.containsKey('database.sqlite')) {
      throw const BackupFailure('Backup is missing its manifest or learning database.');
    }
    final manifest = jsonDecode(await files['manifest.json']!.readAsString()) as Map<String, dynamic>;
    if (manifest['format'] != 'lexiflow' || manifest['version'] != formatVersion ||
        ![7,8,9,10,AppDatabase.schemaVersion].contains(manifest['databaseVersion'])) {
      throw const BackupFailure('Unsupported backup version. Update LexiFlow or select a compatible backup.');
    }
    DateTime.parse(manifest['createdAt'] as String);
    final checks = manifest['files'] as Map<String, dynamic>;
    if (checks.length != files.length - 1 || checks.containsKey('manifest.json')) {
      throw const BackupFailure('Backup file inventory is incomplete.');
    }
    for (final entry in files.entries.where((e) => e.key != 'manifest.json')) {
      final check = checks[entry.key] as Map<String, dynamic>?;
      if (check == null || check['size'] != await entry.value.length() ||
          check['sha256'] != await checksum(entry.value)) {
        throw const BackupFailure('Backup file checksum failed. No learning data was replaced.');
      }
    }
    await _validateDatabase(files['database.sqlite']!,allowLegacy:true);
    final db = sqlite3.open(files['database.sqlite']!.path, mode: OpenMode.readOnly);
    try {
      if(db.select('PRAGMA user_version').single['user_version']!=manifest['databaseVersion']) {
        throw const BackupFailure('Manifest and database schema versions disagree.');
      }
      final refs = _references(db);
      if (jsonEncode(refs) != jsonEncode(manifest['media'])) {
        throw const BackupFailure('Backup media references are inconsistent.');
      }
      final used = refs.map((r) => r['path']).toSet();
      if (used.length != files.length - 2 || used.any((name) => !files.containsKey(name))) {
        throw const BackupFailure('Backup has missing or unexpected media.');
      }
      if (db.select('SELECT path FROM pending_file_deletions').isNotEmpty ||
          db.select('SELECT id FROM certificates WHERE file_path IS NOT NULL').isNotEmpty) {
        throw const BackupFailure('Backup contains installation-local paths.');
      }
    } finally {
      db.dispose();
    }
    return files;
  }

  Future<void> restore(File archive, {void Function(String)? progress}) => _exclusive(() async {
    final live = await database.db;
    final liveBytes = (live.select('PRAGMA page_count').single.values.single as int) *
        (live.select('PRAGMA page_size').single.values.single as int);
    await _space(await archive.length() * 3 + liveBytes * 2);
    final stage = await Directory(p.join(documents.path, '.restore-stage-${newId()}')).create();
    try {
      progress?.call('Validating backup before changing any data…');
      final files = await _validate(archive, stage);
      final media = Directory(p.join(stage.path, 'media'));
      final finalMedia = Directory(p.join(documents.path, 'restored-media-${newId()}'));
      final snapshot = files['database.sqlite']!;
      await _upgradeStaged(snapshot);
      final db = sqlite3.open(snapshot.path);
      try {
        for (final ref in _references(db)) {
          db.execute('UPDATE ${ref['table']} SET ${ref['column']}=? WHERE id=?',
              [p.join(finalMedia.path, p.basename(ref['path']!)), ref['id']]);
        }
        // An exported running session resumes paused via the existing recovery mechanism.
        db.execute('UPDATE study_sessions SET interrupted=1 WHERE completed=0');
      } finally {
        db.dispose();
      }
      await _validateDatabase(snapshot);
      if (await media.exists()) await media.rename(finalMedia.path);
      progress?.call('Replacing learning data; keeping a recovery snapshot…');
      fault?.call('restore-staged');
      await _replace(snapshot);
    } finally {
      // Keep installed media even on failure: a recovery error must never
      // remove files that a surviving database may reference.
      await stage.delete(recursive: true);
    }
  });

  Future<void> _replace(File snapshot) async {
    final path = await database.databasePath;
    // VACUUM INTO creates a WAL-safe recovery copy without touching the live DB.
    final recovery = File('$path.previous-new');
    if (recovery.existsSync()) recovery.deleteSync();
    final previous = File('$path.previous');
    // Refuse to continue if a durable recovery copy cannot be made.
    try {
      await database.snapshot(recovery.path);
      recovery.renameSync(previous.path);
    } finally {
      if (recovery.existsSync()) recovery.deleteSync();
    }
    final journal = File('$path.restore-pending');
    journal.writeAsStringSync('rollback-to-previous', flush: true);
    // Retire this handle permanently. Late async callbacks from disposed
    // learning pages must never be able to reopen and write the restored DB.
    database.retire();
    try {
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('$path$suffix');
        if (file.existsSync()) file.deleteSync();
      }
      snapshot.copySync(path);
      final durable = File(path).openSync(mode: FileMode.append);
      try { durable.flushSync(); } finally { durable.closeSync(); }
      fault?.call('restore-replaced');
      // Prevent the normal open path from performing crash recovery while we
      // validate. Validation here is synchronous; journal removal marks commit.
      final probe = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        if (probe.select('PRAGMA integrity_check').single.values.single != 'ok' ||
            probe.select('PRAGMA foreign_key_check').isNotEmpty) {
          throw const BackupFailure('Restored database failed validation.');
        }
      } finally {
        probe.dispose();
      }
      fault?.call('restore-validated');
      journal.deleteSync();
    } catch (_) {
      AppDatabase.recoverReplacement(path);
      rethrow;
    }
    final reopened = AppDatabase(path: path);
    try {
      await reopened.db;
    } catch (_) {
      reopened.close();
      journal.writeAsStringSync('rollback-to-previous', flush: true);
      AppDatabase.recoverReplacement(path);
      rethrow;
    } finally {
      reopened.close();
    }
  }

  Future<bool> hasRecovery() async => File('${await database.databasePath}.previous').exists();

  Future<void> recoverPrevious() => _exclusive(() async {
    final previous = File('${await database.databasePath}.previous');
    if (!await previous.exists()) throw const BackupFailure('No recovery snapshot is available.');
    await _space(await previous.length() * 3);
    final stage = File(p.join(documents.path, '.recover-${newId()}.sqlite'));
    try {
      await previous.copy(stage.path);
      await _validateDatabase(stage,allowLegacy:true);
      await _upgradeStaged(stage);
      final probe = sqlite3.open(stage.path, mode: OpenMode.readOnly);
      try {
        for (final ref in _references(probe)) {
          if (!File(ref['path']!).existsSync()) throw const BackupFailure('Recovery media is missing.');
        }
      } finally {
        probe.dispose();
      }
      await _replace(stage);
    } finally {
      if (await stage.exists()) await stage.delete();
    }
  });

  Future<void> recordSavedBackup() async => (await database.db).execute(
      'INSERT INTO backup_metadata(id,last_success_at) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET last_success_at=excluded.last_success_at',
      [DateTime.now().toUtc().toIso8601String()]);

  Future<void> _upgradeStaged(File file) async {
    final staged=AppDatabase(path:file.path);
    try { await staged.db; } finally { staged.close(); }
    await _validateDatabase(file);
  }
}
