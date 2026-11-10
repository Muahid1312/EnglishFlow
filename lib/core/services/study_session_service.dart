import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../utils/date_utils.dart';
import '../utils/id_utils.dart';

enum SessionState { idle, running, paused, finished }

class ActiveSession {
  final String id;
  final String module;
  final DateTime startedAt;
  final int accumulatedSeconds;
  final DateTime? runStartedAt;
  final SessionState state;

  const ActiveSession({
    required this.id,
    required this.module,
    required this.startedAt,
    required this.accumulatedSeconds,
    this.runStartedAt,
    required this.state,
  });

  int get elapsedSeconds {
    if (state == SessionState.running && runStartedAt != null) {
      final extra = DateTime.now().difference(runStartedAt!).inSeconds;
      return accumulatedSeconds + (extra > 0 ? extra : 0);
    }
    return accumulatedSeconds;
  }

  ActiveSession copyWith({
    int? accumulatedSeconds,
    DateTime? runStartedAt,
    SessionState? state,
  }) {
    return ActiveSession(
      id: id,
      module: module,
      startedAt: startedAt,
      accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
      runStartedAt: runStartedAt ?? this.runStartedAt,
      state: state ?? this.state,
    );
  }
}

class StudySessionService extends ChangeNotifier {
  StudySessionService(this._db);

  final AppDatabase _db;
  ActiveSession? _active;
  Timer? _ticker;

  ActiveSession? get active => _active;
  bool get isRunning => _active?.state == SessionState.running;
  bool get hasActive =>
      _active != null && _active!.state != SessionState.finished;

  Future<ActiveSession> start(String module) async {
    if (_active != null && _active!.state != SessionState.finished) {
      await finish(interrupted: true);
    }

    final id = newId();
    final now = DateTime.now().toUtc();
    final local = localDateString();

    await _db.insertSession(
        id: id, module: module, startedAt: now, localDate: local);

    _active = ActiveSession(
      id: id,
      module: module,
      startedAt: now,
      accumulatedSeconds: 0,
      runStartedAt: DateTime.now(),
      state: SessionState.running,
    );
    _startTicker();
    notifyListeners();
    return _active!;
  }

  void pause() {
    if (_active == null || _active!.state != SessionState.running) return;
    final elapsed = _active!.elapsedSeconds;
    _active = _active!.copyWith(
      accumulatedSeconds: elapsed,
      runStartedAt: null,
      state: SessionState.paused,
    );
    _stopTicker();
    notifyListeners();
  }

  void resume() {
    if (_active == null || _active!.state != SessionState.paused) return;
    _active = _active!.copyWith(
      runStartedAt: DateTime.now(),
      state: SessionState.running,
    );
    _startTicker();
    notifyListeners();
  }

  void onAppPaused() {
    if (isRunning) pause();
  }

  Future<void> finish({bool interrupted = false}) async {
    if (_active == null || _active!.state == SessionState.finished) return;

    final seconds = _active!.elapsedSeconds;
    final id = _active!.id;
    final now = DateTime.now().toUtc();

    await _db.updateSession(
      id,
      endedAt: now,
      durationSeconds: seconds,
      completed: true,
      interrupted: interrupted,
    );

    final local = localDateString();
    final prefs = await _db.getPreferences();
    final totalSec = await _db.getTotalSecondsForDate(local);
    final totalMin = (totalSec / 60).floor();
    await _db.upsertDailyGoal(
      localDate: local,
      targetMinutes: prefs.dailyTargetMinutes,
      completedMinutes: totalMin,
      goalMet: totalMin >= prefs.dailyTargetMinutes,
    );

    await _db.logActivity(
      id: newId(),
      type: interrupted ? 'session_interrupted' : 'session_completed',
      module: _active!.module,
      localDate: local,
      metadata: '{"seconds":$seconds}',
    );

    _active = _active!
        .copyWith(state: SessionState.finished, accumulatedSeconds: seconds);
    _stopTicker();
    notifyListeners();
    _active = null;
  }

  Future<ActiveSession?> recoverInterrupted() async {
    final row = await _db.getActiveInterruptedSession();
    if (row == null) return null;
    _active = ActiveSession(
      id: row['id'] as String,
      module: row['module'] as String,
      startedAt: DateTime.parse(row['started_at'] as String),
      accumulatedSeconds: row['duration_seconds'] as int,
      state: SessionState.paused,
    );
    notifyListeners();
    return _active;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_active?.state == SessionState.running) notifyListeners();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}
