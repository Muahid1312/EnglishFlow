import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/app_database.dart';
import '../utils/date_utils.dart';
import '../utils/id_utils.dart';
import '../utils/study_days.dart';

enum SessionState { idle, running, paused, finished }

const _unchanged = Object();

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

  int get elapsedSeconds => elapsedSecondsAt(DateTime.now());

  int elapsedSecondsAt(DateTime now) {
    if (state == SessionState.running && runStartedAt != null) {
      final extra = now.difference(runStartedAt!).inSeconds;
      return accumulatedSeconds + (extra > 0 ? extra : 0);
    }
    return accumulatedSeconds;
  }

  ActiveSession copyWith({
    int? accumulatedSeconds,
    Object? runStartedAt = _unchanged,
    SessionState? state,
  }) {
    return ActiveSession(
      id: id,
      module: module,
      startedAt: startedAt,
      accumulatedSeconds: accumulatedSeconds ?? this.accumulatedSeconds,
      runStartedAt: identical(runStartedAt, _unchanged)
          ? this.runStartedAt
          : runStartedAt as DateTime?,
      state: state ?? this.state,
    );
  }
}

class StudySessionService extends ChangeNotifier {
  StudySessionService(this._db, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  final AppDatabase _db;
  ActiveSession? _active;
  Timer? _ticker;
  Future<void>? _finishing;
  Future<ActiveSession?>? _recovering;
  Future<void> _starting = Future.value();
  final _days = <String, int>{};
  DateTime? _checkpointAt;
  bool _disposed = false;
  int _aiWaits = 0;
  int _transition = 0;
  String? _resumeAfterAi;
  int? _resumeAiTransition;
  bool get isAwaitingAi => _aiWaits > 0;

  ActiveSession? get active => _active;
  bool get isRunning => _active?.state == SessionState.running;
  bool get hasActive =>
      _active != null && _active!.state != SessionState.finished;

  /// Reopening a practice screen after another module interrupted its timer
  /// retains the original active plan association, only on the same local day.
  Future<bool> continuePlanActivity(String previousId, String nextId) async {
    final database = await _db.db;
    database.execute(
        '''INSERT OR IGNORE INTO plan_sessions(session_id,activity_id)
      SELECT ?,a.id FROM plan_sessions p JOIN planned_activities a ON a.id=p.activity_id
      JOIN study_sessions s ON s.id=? WHERE p.session_id=? AND a.local_date=?
        AND a.state='active' AND s.module=a.module''',
        [nextId, nextId, previousId, localDateString(_now())]);
    return database.select(
        'SELECT activity_id FROM plan_sessions WHERE session_id=?',
        [nextId]).isNotEmpty;
  }

  Future<ActiveSession> start(String module) {
    if (_disposed) {
      return Future.error(StateError('Study controller is closed.'));
    }
    final result = _starting.then((_) => _start(module));
    _starting =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<ActiveSession> _start(String module) async {
    if (_disposed) throw StateError('Study controller is closed.');
    if (_recovering != null) await _recovering;
    if (_active != null && _active!.state != SessionState.finished) {
      await finish(interrupted: true);
    }

    final id = newId();
    final now = _now().toUtc();
    final local = localDateString(_now());

    await _db.insertSession(
        id: id, module: module, startedAt: now, localDate: local);
    if (_disposed) {
      await _db.checkpointSession(id, const {},
          completed: true, interrupted: true, endedAt: _now());
      throw StateError('Study controller closed while starting.');
    }

    _days.clear();
    _checkpointAt = _now();
    _active = ActiveSession(
      id: id,
      module: module,
      startedAt: now,
      accumulatedSeconds: 0,
      runStartedAt: _now(),
      state: SessionState.running,
    );
    _startTicker();
    if (!_disposed) notifyListeners();
    return _active!;
  }

  Future<void> pause() async {
    _transition++;
    if (_active == null || _active!.state != SessionState.running) return;
    _allocate();
    final elapsed = _days.values.fold<int>(0, (a, b) => a + b) ~/ 1000;
    _active = _active!.copyWith(
      accumulatedSeconds: elapsed,
      runStartedAt: null,
      state: SessionState.paused,
    );
    _stopTicker();
    try {
      await _db.checkpointSession(_active!.id, Map.of(_days));
    } finally {
      // A screen can pause during unmount. Notify after the asynchronous
      // checkpoint so consumers have finished detaching from the old screen.
      if (!_disposed) notifyListeners();
    }
  }

  void resume() {
    if (_disposed) return;
    if (isAwaitingAi) return;
    _transition++;
    if (_active == null || _active!.state != SessionState.paused) return;
    if (_finishing != null) return;
    _checkpointAt = _now();
    _active = _active!.copyWith(
      runStartedAt: _now(),
      state: SessionState.running,
    );
    _startTicker();
    notifyListeners();
  }

  Future<void> onAppPaused() async {
    await pause();
  }

  Future<T> withoutAiWaitingTime<T>(Future<T> Function() action) async {
    final outermost = _aiWaits++ == 0;
    try {
      if (outermost && isRunning) {
        _resumeAfterAi = _active!.id;
        await pause();
        _resumeAiTransition = _transition;
      }
      if (!_disposed) notifyListeners();
      return await action();
    } finally {
      _aiWaits--;
      if (_aiWaits == 0) {
        final shouldResume = _resumeAfterAi != null &&
            _active?.id == _resumeAfterAi &&
            _resumeAiTransition == _transition;
        _resumeAfterAi = null;
        _resumeAiTransition = null;
        if (shouldResume && !_disposed) resume();
      }
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> finish({bool interrupted = false}) {
    return _finishing ??=
        _finish(interrupted: interrupted).whenComplete(() => _finishing = null);
  }

  Future<void> _finish({required bool interrupted}) async {
    if (_active == null || _active!.state == SessionState.finished) return;

    _allocate();
    final active = _active!;
    final seconds = _days.values.fold<int>(0, (a, b) => a + b) ~/ 1000;
    _active = active.copyWith(
        accumulatedSeconds: seconds,
        runStartedAt: null,
        state: SessionState.paused);
    _stopTicker();
    await _db.checkpointSession(active.id, Map.of(_days),
        completed: true, interrupted: interrupted, endedAt: _now());
    _active = null;
    if (!_disposed) notifyListeners();
  }

  void _allocate() {
    if (_active?.state != SessionState.running || _checkpointAt == null) return;
    final now = _now();
    if (!now.isAfter(_checkpointAt!)) return;
    final split = splitStudyDays(_checkpointAt!, now);
    for (final item in split.entries) {
      _days.update(item.key, (value) => value + item.value,
          ifAbsent: () => item.value);
    }
    _checkpointAt = now;
  }

  Future<ActiveSession?> recoverInterrupted() {
    return _recovering ??= _recover().whenComplete(() => _recovering = null);
  }

  Future<ActiveSession?> _recover() async {
    if (_disposed) return null;
    if (hasActive) return _active;
    final row = await _db.getActiveInterruptedSession();
    if (row == null || hasActive || _disposed) return _active;
    _days
      ..clear()
      ..addAll(await _db.getSessionDays(row['id'] as String));
    _checkpointAt = null;
    _active = ActiveSession(
      id: row['id'] as String,
      module: row['module'] as String,
      startedAt: DateTime.parse(row['started_at'] as String),
      accumulatedSeconds: row['duration_seconds'] as int,
      state: SessionState.paused,
    );
    if (!_disposed) notifyListeners();
    return _active;
  }

  void _startTicker() {
    if (_disposed) return;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_active?.state == SessionState.running) {
        final active = _active!;
        _allocate();
        unawaited(_db
            .checkpointSession(active.id, Map.of(_days))
            .catchError((Object error) {
          if (!_disposed) {
            _stopTicker();
            _active = active.copyWith(
                accumulatedSeconds: active.elapsedSecondsAt(_now()),
                runStartedAt: null,
                state: SessionState.paused);
            notifyListeners();
          }
        }));
        notifyListeners();
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTicker();
    super.dispose();
  }
}
