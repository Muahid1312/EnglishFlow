import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

/// Thin wrapper around just_audio with speed, seek, and position hooks.
class AudioPlayerController extends ChangeNotifier with WidgetsBindingObserver {
  AudioPlayerController() {
    WidgetsBinding.instance.addObserver(this);
  }

  bool _disposed = false;
  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;
  String? _error;

  AudioPlayer get player => _player;
  bool get isReady => _ready;
  String? get error => _error;
  bool get playing => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;
  double get speed => _player.speed;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Future<void> load(String path, {int startMs = 0}) async {
    _error = null;
    _ready = false;
    _notify();
    try {
      await _player.stop();
      if (_disposed) return;
      if (path.isEmpty || !File(path).existsSync()) {
        _error = 'Audio file is missing or was moved.';
        _notify();
        return;
      }
      await _player.setFilePath(path);
      if (_disposed) return;
      if (startMs > 0) {
        await _player.seek(Duration(milliseconds: startMs));
      }
      _ready = true;
    } catch (e) {
      _error = 'Could not load audio. Unsupported or corrupted file.';
      _ready = false;
    }
    _notify();
  }

  Future<void> play() async {
    if (!_ready || _disposed) return;
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _player.pause();
  }

  Future<void> pause() => _player.pause();

  Future<void> stop() async {
    await _player.stop();
    await _player.seek(Duration.zero);
  }

  Future<void> seek(Duration d) => _player.seek(d);

  Future<void> skip(int seconds) async {
    final next = _player.position + Duration(seconds: seconds);
    final total = _player.duration ?? next;
    final clamped =
        next < Duration.zero ? Duration.zero : (next > total ? total : next);
    await _player.seek(clamped);
  }

  Future<void> setSpeed(double s) => _player.setSpeed(s);

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    super.dispose();
  }
}
