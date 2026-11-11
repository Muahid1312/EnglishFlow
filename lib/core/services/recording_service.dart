import 'dart:async';
import 'dart:io';

import 'package:record/record.dart';

import 'media_storage.dart';

class RecordingService {
  RecordingService({AudioRecorder? recorder, MediaStorage? storage})
      : _recorder = recorder ?? AudioRecorder(),
        _storage = storage ?? MediaStorage();
  final AudioRecorder _recorder;
  final MediaStorage _storage;
  final _elapsed = Stopwatch();
  String? _currentPath;
  bool _disposed = false;
  Future<void> _pending = Future.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<bool> hasPermission() async =>
      !_disposed && await _recorder.hasPermission();

  Future<String?> start() => _serial(() async {
        if (_disposed) throw StateError('Recorder is disposed.');
        if (_currentPath != null) {
          throw StateError('A recording is already active.');
        }
        if (!await _recorder.hasPermission() || _disposed) return null;
        final path = await _storage.recordingPath();
        _currentPath = path;
        try {
          await _recorder.start(
              const RecordConfig(
                  encoder: AudioEncoder.aacLc,
                  bitRate: 128000,
                  sampleRate: 44100),
              path: path);
          if (_disposed) {
            await _cancelActive();
            return null;
          }
          _elapsed
            ..reset()
            ..start();
          return path;
        } catch (_) {
          try {
            await _cancelActive();
          } catch (_) {}
          rethrow;
        }
      });

  Future<({String path, int durationMs})?> stop() => _serial(() async {
        final current = _currentPath;
        if (current == null) return null;
        try {
          final path = await _recorder.stop();
          _elapsed.stop();
          if (path == null ||
              !await File(path).exists() ||
              await File(path).length() == 0) {
            await _storage.deleteFile(current);
            return null;
          }
          if (path != current) await _storage.deleteFile(current);
          return (path: path, durationMs: _elapsed.elapsedMilliseconds);
        } catch (_) {
          try {
            await _storage.deleteFile(current);
          } catch (_) {}
          rethrow;
        } finally {
          _elapsed.stop();
          _currentPath = null;
        }
      });

  Future<void> _cancelActive() async {
    final path = _currentPath;
    if (path == null) return;
    try {
      await _recorder.cancel();
    } finally {
      _elapsed.stop();
      _currentPath = null;
      await _storage.deleteFile(path);
    }
  }

  Future<void> cancel() => _serial(_cancelActive);
  Future<bool> get isRecording async =>
      !_disposed && await _recorder.isRecording();

  Future<void> dispose() {
    _disposed = true;
    return _serial(() async {
      try {
        await _cancelActive();
      } finally {
        await _recorder.dispose();
      }
    });
  }
}
