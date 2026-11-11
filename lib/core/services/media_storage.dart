import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Application-managed media storage (offline-safe copies).
class MediaStorage {
  static const _uuid = Uuid();

  Future<Directory> _audioDir(String sub) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'media', sub));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copy a picked file into app storage. Returns the new absolute path.
  Future<String> importAudio(File source, {String folder = 'listening'}) async {
    final dir = await _audioDir(folder);
    final ext = p.extension(source.path).toLowerCase();
    final safeExt =
        ['.mp3', '.m4a', '.wav', '.aac', '.ogg'].contains(ext) ? ext : '.mp3';
    final dest = File(p.join(dir.path, '${_uuid.v4()}$safeExt'));
    try {
      await source.copy(dest.path);
      return dest.path;
    } catch (_) {
      if (await dest.exists()) await dest.delete();
      rethrow;
    }
  }

  Future<String> recordingPath({String folder = 'speaking'}) async {
    final dir = await _audioDir(folder);
    return p.join(dir.path, '${_uuid.v4()}.m4a');
  }

  Future<void> deleteFile(String? path) async {
    if (path == null || path.isEmpty) return;
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
