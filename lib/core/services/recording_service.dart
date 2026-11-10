import 'package:record/record.dart';

import 'media_storage.dart';

class RecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  final MediaStorage _storage = MediaStorage();
  String? _currentPath;
  DateTime? _startedAt;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<String?> start() async {
    if (!await _recorder.hasPermission()) return null;
    final path = await _storage.recordingPath();
    await _recorder.start(
      const RecordConfig(
          encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
      path: path,
    );
    _currentPath = path;
    _startedAt = DateTime.now();
    return path;
  }

  Future<({String path, int durationMs})?> stop() async {
    final path = await _recorder.stop();
    final started = _startedAt;
    _startedAt = null;
    if (path == null) return null;
    final ms =
        started == null ? 0 : DateTime.now().difference(started).inMilliseconds;
    _currentPath = null;
    return (path: path, durationMs: ms);
  }

  Future<void> cancel() async {
    await _recorder.cancel();
    if (_currentPath != null) {
      await _storage.deleteFile(_currentPath);
      _currentPath = null;
    }
    _startedAt = null;
  }

  Future<bool> get isRecording => _recorder.isRecording();

  void dispose() {
    _recorder.dispose();
  }
}
