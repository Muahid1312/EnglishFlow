import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../database/app_database.dart';
import '../utils/id_utils.dart';
import 'media_storage.dart';
import 'recording_service.dart';
import 'study_session_service.dart';

abstract class PracticePlayer {
  Duration? get duration;
  bool get playing;
  Stream<bool> get playingChanges;
  Stream<String> get errors;
  Future<void> load(String path);
  Future<void> segment(int startMs, int endMs);
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
}

class NativePracticePlayer implements PracticePlayer {
  final _player = AudioPlayer();
  final _errors = StreamController<String>.broadcast();
  @override
  Duration? get duration => _player.duration;
  @override
  bool get playing => _player.playing;
  @override
  Stream<bool> get playingChanges => _player.playingStream;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  Future<void> load(String path) async {
    if (!await File(path).exists()) throw StateError('Audio file is missing.');
    await _player.setFilePath(path);
  }

  @override
  Future<void> segment(int startMs, int endMs) async {
    await _player.setClip(
        start: Duration(milliseconds: startMs),
        end: Duration(milliseconds: endMs));
    await _player.seek(Duration.zero);
  }

  @override
  Future<void> play() async {
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    unawaited(_player.play().catchError((Object _) {
      if (!_errors.isClosed) _errors.add('Audio playback failed.');
    }));
  }

  @override
  Future<void> stop() => _player.pause();
  @override
  Future<void> dispose() async {
    await _player.dispose();
    await _errors.close();
  }
}

class ShadowingTake {
  const ShadowingTake(
      this.id, this.path, this.durationMs, this.startMs, this.endMs);
  final String id, path;
  final int durationMs, startMs, endMs;
}

class ShadowingController extends ChangeNotifier {
  ShadowingController(this.db, this.lessonId,
      {RecordingService? recorder,
      PracticePlayer? reference,
      PracticePlayer? playback,
      this.study})
      : recorder = recorder ?? RecordingService(),
        reference = reference ?? NativePracticePlayer(),
        playback = playback ?? NativePracticePlayer() {
    _subscriptions.add(this.reference.playingChanges.listen((_) => _notify()));
    _subscriptions.add(this.playback.playingChanges.listen((_) => _notify()));
    _subscriptions.add(this.reference.errors.listen((value) {
      error = value;
      _notify();
    }));
    _subscriptions.add(this.playback.errors.listen((value) {
      error = value;
      _notify();
    }));
  }
  final AppDatabase db;
  final String lessonId;
  final RecordingService recorder;
  final PracticePlayer reference, playback;
  final StudySessionService? study;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool loading = true, busy = false, recording = false, foreground = true;
  bool _closed = false;
  String? error;
  String? _ownedSession;
  Future<void>? _operation;
  int startMs = 0, endMs = 5000, totalMs = 0;
  ShadowingTake? pending;
  List<Map<String, dynamic>> history = [];
  void _notify() {
    if (!_closed) notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy || _closed) return;
    busy = true;
    error = null;
    _notify();
    final operation = () async {
      try {
        await action();
      } catch (_) {
        error =
            'Could not complete shadowing. Check files, microphone access, storage and attempt history before retrying. Unsaved takes remain available when possible.';
      } finally {
        busy = false;
        _notify();
      }
    }();
    _operation = operation;
    await operation;
    if (identical(_operation, operation)) _operation = null;
  }

  Future<void> initialize() => _run(() async {
        final lesson = await db.getListeningLesson(lessonId);
        if (lesson == null) throw StateError('Lesson not found.');
        await reference.load(lesson['audio_path'] as String);
        totalMs = reference.duration?.inMilliseconds ??
            lesson['duration_ms'] as int? ??
            0;
        if (totalMs <= 0) throw StateError('Audio duration unavailable.');
        endMs = totalMs < 5000 ? totalMs : 5000;
        await _history();
        final drafts =
            history.where((r) => r['saved'] == 0 && r['audio_path'] != null);
        if (drafts.isNotEmpty) {
          final d = drafts.first;
          pending = ShadowingTake(
              d['id'] as String,
              d['audio_path'] as String,
              d['duration_ms'] as int,
              d['segment_start_ms'] as int,
              d['segment_end_ms'] as int);
          startMs = pending!.startMs;
          endMs = pending!.endMs;
        }
        loading = false;
        await drainDeletedFiles();
      }).whenComplete(() {
        loading = false;
        _notify();
      });
  void setSegment(int start, int end) {
    if (busy ||
        recording ||
        pending != null ||
        start < 0 ||
        end <= start ||
        end > totalMs) return;
    startMs = start;
    endMs = end;
    _notify();
  }

  Future<void> playReference() => _run(() async {
        if (!foreground || recording || totalMs <= 0) return;
        await playback.stop();
        if (reference.playing) {
          await reference.stop();
          return;
        }
        await reference.segment(startMs, endMs);
        await reference.play();
      });
  Future<void> startRecording() => _run(() async {
        if (!foreground || recording || pending != null || endMs <= startMs) {
          return;
        }
        await reference.stop();
        await playback.stop();
        final path = await recorder.start();
        if (path == null) {
          error = 'Microphone permission is required to record.';
          return;
        }
        recording = true;
        if (_closed || !foreground) {
          await _stop();
          return;
        }
        if (study != null) {
          await study!.recoverInterrupted();
          if(!study!.hasActive || !['shadowing','listening_speaking'].contains(study!.active!.module)) {
            _ownedSession = (await study!.start('shadowing')).id;
          } else {study!.resume();}
        }
      });
  Future<void> _finishTimer() async {
    if (_ownedSession != null && study?.active?.id == _ownedSession) {
      await study!.finish();
    } else if(study?.active!=null && ['shadowing','listening_speaking'].contains(study!.active!.module)) {
      await study!.pause();
    }
    _ownedSession = null;
  }

  Future<void> _persistDraft() async {
    final take = pending;
    if (take == null) return;
    await db.saveShadowingRecording(
        attemptId: take.id,
        lessonId: lessonId,
        path: take.path,
        startMs: take.startMs,
        endMs: take.endMs,
        durationMs: take.durationMs,
        saved: false);
  }

  Future<void> _stop() async {
    if (!recording) return;
    try {
      final result = await recorder.stop();
      recording = false;
      if (result == null) {
        error = 'No audio was produced. Please try again.';
        return;
      }
      pending = ShadowingTake(
          newId(), result.path, result.durationMs, startMs, endMs);
      await _persistDraft();
      await _history();
    } finally {
      recording = false;
      await _finishTimer();
    }
  }

  Future<void> stopRecording() => _run(_stop);
  Future<void> saveTake() => _run(() async {
        if (pending == null) return;
        await _persistDraft();
        await db.confirmShadowingAttempt(pending!.id);
        pending = null;
        await _history();
      });
  Future<void> playTake(String path) => _run(() async {
        if (!foreground || recording) return;
        await reference.stop();
        await playback.stop();
        await playback.load(path);
        await playback.play();
      });
  Future<void> deleteTake(String id) => _run(() async {
        if (recording) return;
        await playback.stop();
        await db.deleteShadowingAttempt(id);
        if (pending?.id == id) {
          (await db.db).execute('INSERT OR IGNORE INTO pending_file_deletions(path) VALUES(?)',[pending!.path]);
          pending = null;
        }
        await drainDeletedFiles();
        await _history();
      });
  Future<void> _history() async {
    history = await db.getShadowingHistory(lessonId);
  }

  Future<void> drainDeletedFiles() async {
    for (final path in await db.pendingFileDeletions()) {
      try {
        await MediaStorage().deleteFile(path);
        await db.completeFileDeletion(path);
      } catch (_) {
        error =
            'A deleted recording is queued for file cleanup. Retry when storage is available.';
      }
    }
  }

  Future<void> onPaused() async {
    foreground = false;
    await reference.stop();
    await playback.stop();
    if (busy) await _operation;
    if (recording) await stopRecording();
  }

  void onResumed() {
    foreground = true;
    _notify();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (_operation != null) await _operation;
    try {
      if (recording) await _stop();
    } finally {
      for (final s in _subscriptions) {
        await s.cancel();
      }
      await Future.wait(
          [recorder.dispose(), reference.dispose(), playback.dispose()]);
    }
  }

  @override
  void dispose() {
    unawaited(close().catchError((Object _) {}));
    super.dispose();
  }
}
