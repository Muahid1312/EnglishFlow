import 'dart:io';
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

class AudioLoopRange {
  AudioLoopRange(this.startMs, this.endMs, int durationMs) {
    if (startMs < 0 || endMs <= startMs || endMs > durationMs) {
      throw ArgumentError('Choose A before B within the audio duration.');
    }
  }
  final int startMs, endMs;
  bool shouldRepeat(int positionMs) => positionMs >= endMs;
}

/// Thin wrapper around just_audio with speed, seek, and position hooks.
class AudioPlayerController extends ChangeNotifier with WidgetsBindingObserver {
  AudioPlayerController() {
    WidgetsBinding.instance.addObserver(this);
    _loopSubscription = _player.positionStream.listen((position) {
      final loop = _loop;
      if (loop != null &&
          _player.playing &&
          loop.shouldRepeat(position.inMilliseconds) &&
          !_loopSeeking) {
        _loopSeeking = true;
        unawaited(_repeat(loop));
      }
    });
  }

  bool _disposed = false;
  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;
  String? _error;
  AudioLoopRange? _loop;
  StreamSubscription<Duration>? _loopSubscription;
  bool _loopSeeking = false;
  AudioLoopRange? get loop => _loop;
  Future<void> _repeat(AudioLoopRange loop) async {
    try {
      await _player.seek(Duration(milliseconds: loop.startMs));
      if (!_disposed &&
          _loop == loop &&
          _player.processingState == ProcessingState.completed) await play();
    } catch (_) {
      _error = 'Segment replay failed. Pause and retry playback.';
      if (!_disposed) await _player.pause().catchError((Object _) {});
      _notify();
    } finally {
      _loopSeeking = false;
    }
  }

  void setABLoop(int? startMs, int? endMs) {
    _loop = startMs == null || endMs == null
        ? null
        : AudioLoopRange(startMs, endMs, _player.duration?.inMilliseconds ?? 0);
    _notify();
  }

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
      _loop = null;
      if (_disposed) return;
      if (path.isEmpty || !File(path).existsSync()) {
        _error = 'Audio file is missing or was moved.';
        _notify();
        return;
      }
      await (await AudioSession.instance)
          .configure(const AudioSessionConfiguration.speech());
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
      await _player.seek(Duration(milliseconds: _loop?.startMs ?? 0));
    }
    unawaited(_player.play().catchError((Object _) {
      _error =
          'Playback failed. This device may not support the selected audio codec.';
      if (!_disposed) unawaited(_player.pause().catchError((Object _) {}));
      _notify();
    }));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_player.pause().catchError((Object _) {}));
    }
  }

  Future<void> pause() => _player.pause();

  Future<void> stop() async {
    await _player.stop();
    await _player.seek(Duration.zero);
  }

  Future<void> seek(Duration d) {
    final duration = _player.duration;
    return _player.seek(d < Duration.zero
        ? Duration.zero
        : duration != null && d > duration
            ? duration
            : d);
  }

  Future<void> skip(int seconds) async {
    final next = _player.position + Duration(seconds: seconds);
    final total = _player.duration ?? next;
    final clamped =
        next < Duration.zero ? Duration.zero : (next > total ? total : next);
    await _player.seek(clamped);
  }

  Future<void> setSpeed(double s) {
    if (![0.75, 1.0, 1.25, 1.5].contains(s)) {
      throw ArgumentError('Unsupported playback speed.');
    }
    return _player.setSpeed(s);
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _loopSubscription?.cancel();
    unawaited(_player.dispose().catchError((Object _) {}));
    super.dispose();
  }
}
