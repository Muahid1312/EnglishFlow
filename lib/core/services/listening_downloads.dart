import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import '../utils/id_utils.dart';

class AudioDownloadFailure implements Exception {
  const AudioDownloadFailure(this.message);
  final String message;
  @override String toString() => message;
}

/// Only publisher-owned, immutable assets are downloadable. Provider resource
/// pages are separate and never interpreted as media URLs.
class ListeningCatalog {
  ListeningCatalog(this.lessons, this.providers);
  final List<Map<String, dynamic>> lessons, providers;
  static ListeningCatalog? _value;
  static Future<ListeningCatalog>? _pending;
  static Future<ListeningCatalog> load() {
    if (_value != null) return Future.value(_value!);
    return _pending ??= rootBundle.loadString('assets/listening/catalog_v1.json').then((text) {
      final result = parse(text);
      _value = result;
      return result;
    }).catchError((Object error, StackTrace stack) {
      _pending = null;
      Error.throwWithStackTrace(error, stack);
    });
  }
  static ListeningCatalog parse(String text) {
    final data = jsonDecode(text) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('Unsupported listening catalogue.');
    final lessons = (data['lessons'] as List).map((r) => Map<String, dynamic>.unmodifiable(r as Map)).toList();
    final ids = <String>{};
    for (final row in lessons) {
      final id = row['id'] as String;
      if (!RegExp(r'^[a-z0-9-]{1,80}$').hasMatch(id) || !ids.add(id) ||
          row['download_allowed'] != true || !['B1', 'B2'].contains(row['level']) ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['sha256'] as String) ||
          (row['bytes'] as int) < 1024 || (row['bytes'] as int) > maxAudioBytes) {
        throw const FormatException('Invalid authorized listening metadata.');
      }
      final uri = checkedMediaUri(row['audio_url'] as String);
      if (!RegExp(r'^/Muahid1312/EnglishFlow/[0-9a-f]{40}/listening_catalog/media/[a-z0-9-]+\.mp3$').hasMatch(uri.path)) {
        throw const FormatException('Audio must be pinned to a verified publisher revision.');
      }
      final permission = Uri.parse(row['permission_url'] as String);
      if (permission.scheme != 'https' || permission.host != 'github.com' ||
          permission.path != '/Muahid1312/EnglishFlow/blob/${uri.pathSegments[2]}/listening_catalog/PERMISSION.md') {
        throw const FormatException('Missing publisher permission.');
      }
    }
    return ListeningCatalog(List.unmodifiable(lessons), List.unmodifiable((data['online_providers'] as List).map((r) => Map<String, dynamic>.from(r as Map))));
  }
  Map<String, dynamic> lesson(String id) => lessons.firstWhere((l) => l['id'] == id,
      orElse: () => throw const AudioDownloadFailure('This lesson is not in the authorized catalogue.'));
}

const maxAudioBytes = 128 * 1024 * 1024;
Uri checkedMediaUri(String value) {
  final uri = Uri.parse(value);
  if (uri.scheme != 'https' || !['raw.githubusercontent.com'].contains(uri.host) ||
      uri.port != 443 || uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    throw const AudioDownloadFailure('This audio destination is not authorized.');
  }
  return uri;
}

class AudioResponse {
  AudioResponse(this.status, this.headers, this.body);
  final int status;
  final Map<String, String> headers;
  final Stream<List<int>> body;
}
class AudioConnection {
  AudioConnection(this.response, this.close);
  final Future<AudioResponse> response;
  final void Function() close;
}
abstract class AudioTransport {
  AudioConnection open(Uri uri, Map<String, String> headers);
}
class HttpsAudioTransport implements AudioTransport {
  @override AudioConnection open(Uri uri, Map<String, String> headers) {
    final client = HttpClient()..autoUncompress = false;
    client.connectionTimeout = const Duration(seconds: 20);
    final response = () async {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      final reply = await request.close().timeout(const Duration(seconds: 30));
      final values = <String, String>{};
      reply.headers.forEach((name, value) => values[name.toLowerCase()] = value.join(','));
      return AudioResponse(reply.statusCode, values, reply.timeout(const Duration(seconds: 30)));
    }();
    return AudioConnection(response, () => client.close(force: true));
  }
}

/// Header validation supplements a full publisher SHA-256 for downloads.
/// It rejects common HTML/JSON errors and mislabeled containers. The player
/// still performs codec decoding on the device.
Future<String> audioExtension(File file) async {
  final size = await file.length();
  if (size < 128 || size > maxAudioBytes) throw const AudioDownloadFailure('Audio size is outside the supported 128-byte to 128-MiB range.');
  final handle = await file.open();
  late List<int> bytes;
  try { bytes = await handle.read(512); } finally { await handle.close(); }
  String ascii(int start, int end) => String.fromCharCodes(bytes.sublist(start, end));
  final prefix = utf8.decode(bytes, allowMalformed: true).trimLeft().toLowerCase();
  if (prefix.startsWith('<') || prefix.startsWith('{') || prefix.startsWith('[')) throw const AudioDownloadFailure('The response is a page or error message, not audio.');
  if (ascii(0, 3) == 'ID3' || (bytes[0] == 255 && (bytes[1] & 0xe0) == 0xe0 && (bytes[1] & 0x06) != 0)) return '.mp3';
  if (ascii(0, 4) == 'RIFF' && ascii(8, 12) == 'WAVE') return '.wav';
  if (ascii(4, 8) == 'ftyp') return '.m4a';
  if (ascii(0, 4) == 'OggS') return '.ogg';
  if (bytes[0] == 255 && (bytes[1] & 0xf6) == 0xf0) return '.aac';
  throw const AudioDownloadFailure('Unrecognized audio file. Import an MP3, M4A, WAV, AAC, or OGG file.');
}

class _Stopped implements Exception {}

/// Foreground-only single-worker queue. All progress is received byte counts;
/// a lesson becomes playable only after length/header/hash checks and commit.
class ListeningDownloads extends ChangeNotifier with WidgetsBindingObserver {
  ListeningDownloads(this.database, {Future<ListeningCatalog> Function()? catalog,
      Future<Directory> Function()? documents, Future<int> Function()? availableBytes,
      AudioTransport? transport, bool observeLifecycle = true})
      : _catalog = catalog ?? ListeningCatalog.load,
        _documents = documents ?? getApplicationDocumentsDirectory,
        _space = availableBytes ?? (() async => (await const MethodChannel('lexiflow/backup').invokeMethod<int>('availableBytes'))!),
        _transport = transport ?? HttpsAudioTransport(), _observes = observeLifecycle {
    if (_observes) WidgetsBinding.instance.addObserver(this);
  }
  final AppDatabase database;
  final Future<ListeningCatalog> Function() _catalog;
  final Future<Directory> Function() _documents;
  final Future<int> Function() _space;
  final AudioTransport _transport;
  final bool _observes;
  final Map<String, Map<String, dynamic>> _jobs = {};
  final Set<String> _enqueueing = {};
  ListeningCatalog? catalog;
  late Directory _docs, _folder;
  bool _initialized = false, _closed = false, _suspended = false, _foreground = true;
  Future<void>? _initializing, _worker;
  Completer<void>? _activeDone;
  AudioConnection? _connection;
  String? _active, _intent;
  Map<String, Map<String, dynamic>> get jobs => Map.unmodifiable(_jobs);
  bool get busy => _active != null;
  void _notify() { if (!_closed) notifyListeners(); }
  Future<void> initialize() {
    if (_initialized) return Future.value();
    return _initializing ??= _initialize().whenComplete(() => _initializing = null);
  }
  Future<void> _initialize() async {
    catalog = await _catalog(); if (_closed) return;
    _docs = await _documents(); if (_closed) return;
    await _docs.create(recursive: true);
    _folder = Directory(p.join(_docs.path, 'media', 'listening_downloads'));
    await _folder.create(recursive: true);
    final root = await _docs.resolveSymbolicLinks();
    if (!p.isWithin(root, await _folder.resolveSymbolicLinks())) throw const AudioDownloadFailure('Unsafe audio storage directory.');
    if (_closed) return;
    final d = await database.db;
    if (_closed) return;
    for (final row in d.select('SELECT * FROM listening_downloads')) {
      _jobs[row['catalog_id'] as String] = Map<String, dynamic>.from(row);
    }
    if (_closed) return;
    for (final id in _jobs.keys.toList()) {
      if (!catalog!.lessons.any((l) => l['id'] == id)) continue;
      final row = _jobs[id]!;
      if (row['status'] == 'downloaded') {
        final lesson = row['lesson_id'] == null ? null : await database.getListeningLesson(row['lesson_id'] as String);
        final path = lesson?['audio_path'] as String? ?? '';
        try {
          if (!await _managed(path)) throw const AudioDownloadFailure('Audio is missing. Download it again.');
          await _verify(File(path), catalog!.lesson(id));
        } catch (_) { await _set(id, {'status':'failed','error':'Stored audio is missing or invalid. Retry the download.'}); }
      } else if (['downloading','paused','failed'].contains(row['status'])) {
        final part = _part(id);
        final length = await part.exists() ? await part.length() : 0;
        if (length > 0 && row['supports_resume'] == 1 && length <= catalog!.lesson(id)['bytes']) {
          await _set(id, {'status':'paused','bytes_received':length,'error':'Interrupted transfer. Resume when ready.'});
        } else {
          await _erasePart(id);
          await _set(id, {'status':'failed','bytes_received':0,'supports_resume':0,'error':'Interrupted transfer. Retry from the beginning.'});
        }
      }
    }
    _initialized = true; _notify(); _kick();
  }
  File _part(String id) => File(p.join(_folder.path, '$id.part'));
  File _final(Map<String, dynamic> lesson) => File(p.join(_folder.path, '${lesson['id']}-${(lesson['sha256'] as String).substring(0, 12)}.mp3'));
  Future<void> _set(String id, Map<String, Object?> values) async {
    if (_closed) return;
    final d = await database.db; if (_closed) return;
    d.execute('INSERT OR IGNORE INTO listening_downloads(catalog_id) VALUES(?)', [id]);
    const allowed = {'status','lesson_id','bytes_received','total_bytes','supports_resume','etag','verified_sha256','error'};
    if (!values.keys.every(allowed.contains)) throw StateError('Invalid transfer update.');
    d.execute('UPDATE listening_downloads SET ${values.keys.map((k) => '$k=?').join(',')},updated_at=? WHERE catalog_id=?', [...values.values,DateTime.now().toUtc().toIso8601String(),id]);
    _jobs[id] = Map<String, dynamic>.from(d.select('SELECT * FROM listening_downloads WHERE catalog_id=?',[id]).single);
    _notify();
  }
  Future<void> enqueue(String id) async {
    if (!_enqueueing.add(id)) return;
    try {
      await initialize(); catalog!.lesson(id);
      if (['queued','downloading','downloaded'].contains(_jobs[id]?['status'])) return;
      await _set(id, {'status':'queued','error':null}); _kick();
    } finally { _enqueueing.remove(id); }
  }
  void _kick() {
    if (_closed || !_initialized || _suspended || !_foreground || _worker != null || !_jobs.values.any((j) => j['status']=='queued')) return;
    _worker = _drain().catchError((Object _) { _suspended = true; }).whenComplete(() { _worker = null; _kick(); });
  }
  Future<void> _drain() async {
    while (!_closed && !_suspended && _foreground) {
      final queued = _jobs.entries.where((e) => e.value['status'] == 'queued');
      if (queued.isEmpty) return;
      final id = queued.first.key; _active = id; _intent = null; _activeDone = Completer<void>();
      try { await _download(id); } finally {
        _connection?.close(); _connection = null; _active = null;
        _activeDone?.complete(); _activeDone = null;
      }
    }
  }
  Future<void> waitUntilIdle() async { await _worker; }
  void _check() { if (_closed || _intent != null || !_foreground || _suspended) throw _Stopped(); }
  Future<void> _erasePart(String id) async {
    final part = _part(id);
    if (await FileSystemEntity.type(part.path, followLinks: false) == FileSystemEntityType.link) { await Link(part.path).delete(); return; }
    if (await part.exists()) await part.delete();
  }
  Future<void> _free(int remaining) async {
    if (await _space() < remaining + 16 * 1024 * 1024) throw const AudioDownloadFailure('Not enough free storage. Free space and retry.');
  }
  Future<void> _verify(File file, Map<String, dynamic> lesson) async {
    if (await file.length() != lesson['bytes'] || await audioExtension(file) != '.mp3' ||
        (await sha256.bind(file.openRead()).first).toString() != lesson['sha256']) {
      throw const AudioDownloadFailure('Audio verification failed. Retry the download.');
    }
  }
  Future<void> _download(String id) async {
    final lesson = catalog!.lesson(id); final part = _part(id);
    RandomAccessFile? output;
    try {
      _check();
      final finalFile = _final(lesson);
      if (await FileSystemEntity.type(finalFile.path, followLinks:false) == FileSystemEntityType.link) throw const AudioDownloadFailure('Unsafe audio file.');
      if (await finalFile.exists()) {
        try {
          await _verify(finalFile, lesson); _check();
          await _register(id, finalFile); return;
        } on AudioDownloadFailure {
          await finalFile.delete();
        }
      }
      if (await FileSystemEntity.type(part.path, followLinks: false) == FileSystemEntityType.link) { await Link(part.path).delete(); return; }
      var offset = await part.exists() ? await part.length() : 0;
      if (_jobs[id]?['supports_resume'] != 1 || offset > lesson['bytes']) { await _erasePart(id); offset = 0; }
      if (offset == lesson['bytes'] && offset > 0) {
        await _verify(part,lesson); _check();
        await part.rename(finalFile.path); await _register(id,finalFile); return;
      }
      await _free((lesson['bytes'] as int) - offset); _check();
      var uri = checkedMediaUri(lesson['audio_url'] as String);
      AudioResponse? response;
      final headers = <String, String>{'Accept-Encoding':'identity'};
      if (offset > 0) {
        headers['Range'] = 'bytes=$offset-';
        final etag = _jobs[id]?['etag'] as String?;
        if (etag != null && !etag.startsWith('W/') && etag.length <= 256) headers['If-Range'] = etag;
      }
      await _set(id, {'status':'downloading','bytes_received':offset,'total_bytes':lesson['bytes'],'error':null});
      for (var redirects = 0; redirects <= 4; redirects++) {
        _check(); _connection = _transport.open(uri, headers);
        response = await _connection!.response; _check();
        if (![301,302,303,307,308].contains(response.status)) break;
        final location = response.headers['location']; _connection!.close();
        if (location == null || redirects == 4) throw const AudioDownloadFailure('Invalid audio redirect.');
        uri = checkedMediaUri(uri.resolve(location).toString());
      }
      final reply = response!;
      if (reply.status != 200 && reply.status != 206) throw const AudioDownloadFailure('The audio server could not complete this download. Retry later.');
      final type = (reply.headers['content-type'] ?? '').split(';').first.toLowerCase();
      if (!['audio/mpeg','audio/mp3','application/octet-stream'].contains(type) ||
          !['','identity'].contains(reply.headers['content-encoding'] ?? '')) throw const AudioDownloadFailure('The server returned an unsupported audio response.');
      if (reply.status == 200) offset = 0;
      if (reply.status == 206) {
        final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(reply.headers['content-range'] ?? '');
        if (range == null || int.parse(range[1]!) != offset || int.parse(range[3]!) != lesson['bytes'] || int.parse(range[2]!) != (lesson['bytes'] as int)-1) throw const AudioDownloadFailure('The server returned an invalid resume range.');
      }
      final length = int.tryParse(reply.headers['content-length'] ?? '');
      if (length != null && length != (lesson['bytes'] as int)-offset) throw const AudioDownloadFailure('The audio size changed. Retry from the beginning.');
      final resume = reply.headers['accept-ranges']?.toLowerCase() == 'bytes' || reply.status == 206;
      final etag = reply.headers['etag'];
      await _set(id, {'supports_resume':resume?1:0,'etag':etag != null && etag.length<=256 ? etag : null,'bytes_received':offset});
      output = await part.open(mode:offset == 0 ? FileMode.write : FileMode.append);
      var received = offset, checkpoint = offset;
      await for (final chunk in reply.body) {
        _check(); received += chunk.length;
        if (received > lesson['bytes'] || received > maxAudioBytes) throw const AudioDownloadFailure('The audio exceeds its authorized size.');
        await output.writeFrom(chunk);
        if (received-checkpoint >= 64*1024) {
          await _free((lesson['bytes'] as int)-received);
          await output.flush();
          await _set(id, {'bytes_received':received}); checkpoint = received;
        }
      }
      await output.flush(); await output.close(); output = null; _check();
      await _set(id, {'bytes_received':received});
      await _verify(part, lesson); _check();
      await part.rename(finalFile.path); _check();
      await _register(id, finalFile);
    } catch (error) {
      if (output != null) { try { await output.close(); } catch (_) {} }
      if (_closed) return;
      final keep = (error is _Stopped || error is SocketException || error is HttpException || error is TimeoutException) && _intent != 'cancel' && _jobs[id]?['supports_resume'] == 1 && await part.exists() && await part.length() <= lesson['bytes'];
      if (!keep) await _erasePart(id);
      final paused = _intent == 'pause' && keep;
      await _set(id, {'status':_intent == 'cancel' ? 'available' : paused ? 'paused' : 'failed',
        'bytes_received':keep ? await part.length() : 0,
        if (!keep) 'supports_resume':0,
        'error':_intent == 'cancel' ? null : paused ? 'Paused. Resume when ready.' : error is AudioDownloadFailure ? error.message : error is FileSystemException ? 'Could not write audio. Check free storage and retry.' : 'Transfer interrupted. Retry when a connection is available.'});
    }
  }
  Future<void> _register(String id, File file) async {
    _check(); final row = catalog!.lesson(id); final d = await database.db; _check();
    final lessonId = _jobs[id]?['lesson_id'] as String? ?? 'download:$id';
    d.execute('BEGIN IMMEDIATE');
    try {
      final existing = d.select('SELECT id FROM listening_lessons WHERE id=?',[lessonId]);
      if (existing.isEmpty) {
        d.execute('INSERT INTO listening_lessons(id,title,topic,difficulty,audio_path,duration_ms,transcript) VALUES(?,?,?,?,?,?,?)', [lessonId,row['title'],row['topic'],row['level'],file.path,row['duration_ms'],row['transcript']]);
        var index = 0;
        for (final question in row['questions'] as List) {
          d.execute('INSERT INTO comprehension_questions(id,lesson_id,question,question_type,choices,correct_answer,order_index) VALUES(?,?,?,?,?,?,?)', ['$lessonId-q${index+1}',lessonId,question['prompt'],'mc',jsonEncode(question['choices']),question['answer'],index]); index++;
        }
      } else {
        d.execute('UPDATE listening_lessons SET audio_path=? WHERE id=?',[file.path,lessonId]);
      }
      d.execute("UPDATE listening_downloads SET status='downloaded',lesson_id=?,bytes_received=?,total_bytes=?,verified_sha256=?,error=NULL WHERE catalog_id=?", [lessonId,row['bytes'],row['bytes'],row['sha256'],id]);
      d.execute('COMMIT');
    } catch (_) { d.execute('ROLLBACK'); rethrow; }
    _jobs[id] = Map<String, dynamic>.from(d.select('SELECT * FROM listening_downloads WHERE catalog_id=?',[id]).single);
    _notify();
  }
  Future<void> pause(String id) async {
    await initialize();
    if (_active != id || _jobs[id]?['supports_resume'] != 1) return;
    _intent = 'pause'; _connection?.close(); await _activeDone?.future;
  }
  Future<void> cancel(String id) async {
    await initialize(); catalog!.lesson(id);
    if (_jobs[id]?['status'] == 'downloaded') return;
    if (_active == id) { _intent = 'cancel'; _connection?.close(); await _activeDone?.future; }
    else { await _erasePart(id); await _set(id, {'status':'available','bytes_received':0,'supports_resume':0,'error':null}); }
  }
  Future<void> suspend() async {
    _suspended = true;
    if (_active != null) { _intent = 'pause'; _connection?.close(); await _activeDone?.future; }
  }
  void resumeQueue() { _suspended = false; _kick(); }
  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) { unawaited(suspend()); } else { resumeQueue(); }
  }
  Future<bool> _managed(String path) async {
    if (path.isEmpty || !await File(path).exists()) return false;
    if (await FileSystemEntity.type(path, followLinks:false) != FileSystemEntityType.file) return false;
    final root = await _docs.resolveSymbolicLinks(); final real = await File(path).resolveSymbolicLinks();
    if (!p.isWithin(root, real)) return false;
    final first = p.split(p.relative(real,from:root)).first;
    return first == 'media' || first.startsWith('restored-media-');
  }
  Future<void> removeAudio(String lessonId) async {
    await initialize();
    final linked = _jobs.entries.where((e) => e.value['lesson_id'] == lessonId).toList();
    for (final row in linked) { if (_active == row.key) await cancel(row.key); }
    final lesson = await database.getListeningLesson(lessonId); if (lesson == null) return;
    final path = lesson['audio_path'] as String;
    final managed = await _managed(path); final d = await database.db;
    d.execute('UPDATE listening_lessons SET audio_path=? WHERE id=?',['',lessonId]);
    for (final row in linked) { await _set(row.key, {'status':'available','bytes_received':0,'supports_resume':0,'verified_sha256':null,'error':null}); }
    final used = d.select('''SELECT id FROM listening_lessons WHERE audio_path=? OR transcript_path=?
      UNION ALL SELECT id FROM speaking_recordings WHERE audio_path=?
      UNION ALL SELECT id FROM imported_books WHERE file_path=?
      UNION ALL SELECT id FROM courses WHERE cover_path=?''',[path,path,path,path,path]);
    if (managed && used.isEmpty) await File(path).delete();
    _notify();
  }
  Future<String> importFile(File source, String title) async {
    await initialize(); final extension = await audioExtension(source);
    await _free(await source.length());
    final target = File(p.join(_folder.path,'import-${newId()}$extension'));
    final part = File('${target.path}.part');
    try {
      await source.copy(part.path); await audioExtension(part);
      if (await part.length() != await source.length()) throw const AudioDownloadFailure('Import did not finish.');
      await part.rename(target.path);
      final id = newId();
      await database.insertListeningLesson({'id':id,'title':title,'topic':'Imported','difficulty':'B1','audio_path':target.path});
      return id;
    } catch (_) { if (await part.exists()) await part.delete(); if (await target.exists()) await target.delete(); rethrow; }
  }
  Future<int> storageBytes() async {
    await initialize(); var total = 0;
    await for (final entry in _folder.list(followLinks:false)) { if (entry is File) total += await entry.length(); }
    // Restored audio lives in its own managed directory, not the new-download folder.
    for (final lesson in await database.getListeningLessons()) {
      final path = lesson['audio_path'] as String;
      if (!p.isWithin(_folder.path,path) && await _managed(path)) total += await File(path).length();
    }
    return total;
  }
  @override void dispose() {
    _closed = true; _connection?.close();
    if (_observes) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
