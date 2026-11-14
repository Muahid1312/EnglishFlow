import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/practice_timer.dart';
import '../../../core/services/transcript_parser.dart';
import 'synchronized_transcript.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/services/audio_player_controller.dart';
import '../../../core/services/providers.dart';
import '../../../core/utils/id_utils.dart';
import '../../../core/widgets/common_widgets.dart';
import 'comprehension_screen.dart';
import 'shadowing_screen.dart';

class AudioPlayerScreen extends ConsumerStatefulWidget {
  final String lessonId;
  const AudioPlayerScreen(
      {super.key, required this.lessonId, this.initialPositionMs});
  final int? initialPositionMs;

  @override
  ConsumerState<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends ConsumerState<AudioPlayerScreen>
    with WidgetsBindingObserver {
  final _ctrl = AudioPlayerController();
  Map<String, dynamic>? _lesson;
  List<Map<String, dynamic>> _bookmarks = [];
  bool _showTranscript = false;
  bool _loading = true;
  double _speed = 1.0;
  late final AppDatabase _db;
  late final PracticeTimer _timer;
  StreamSubscription<PlayerState>? _stateSubscription;
  ParsedTranscript? _parsed;
  String _format = 'auto';
  String? _notice;
  bool _autoScroll = true, _busy = false, _foreground = true;
  int? _loopA, _loopB;
  int _lastSaved = -5000;
  double? _seekPreview;
  GoRouter? _router;
  bool _routeVisible = true;
  StreamSubscription<Duration>? _positionSubscription;
  final _transcriptCtrl = TextEditingController();

  static const _speeds = [0.75, 1.0, 1.25, 1.5];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _db = ref.read(appDatabaseProvider);
    final active = ref.read(studySessionServiceProvider).active;
    _timer = PracticeTimer(
        ref.read(studySessionServiceProvider),
        active?.module == 'listening_speaking'
            ? 'listening_speaking'
            : 'listening');
    _ctrl.addListener(_changed);
    _init().catchError((Object _) {
      if (mounted)
        setState(() {
          _loading = false;
          _notice = 'Could not load this listening lesson.';
        });
    });
  }

  Future<void> _init() async {
    final db = _db;
    final lesson = await db.getListeningLesson(widget.lessonId);
    if (lesson == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final bookmarks = await db.getBookmarks(widget.lessonId);
    if (!mounted) return;
    _transcriptCtrl.text = (lesson['transcript'] as String?) ?? '';
    await _ctrl.load(
      lesson['audio_path'] as String,
      startMs:
          widget.initialPositionMs ?? (lesson['last_position_ms'] as int?) ?? 0,
    );
    if (!mounted) return;
    await _checkpoint();
    _speed = (lesson['playback_speed'] as num).toDouble();
    if (_ctrl.isReady) await _ctrl.setSpeed(_speed);
    _format = lesson['transcript_format'] as String;
    _autoScroll = lesson['transcript_auto_scroll'] == 1;
    try {
      _parsed = parseTranscript(_transcriptCtrl.text,
          format: _format == 'auto' ? null : _format);
    } on FormatException catch (e) {
      _notice = e.message;
    }
    _loopA = lesson['loop_start_ms'] as int?;
    _loopB = lesson['loop_end_ms'] as int?;
    if (_ctrl.isReady && _loopA != null && _loopB != null) {
      try {
        _ctrl.setABLoop(_loopA, _loopB);
      } catch (_) {
        _notice =
            'Saved loop is outside this audio. Clear it and choose a new segment.';
      }
    }
    _positionSubscription = _ctrl.positionStream
        .distinct((a, b) => a.inSeconds == b.inSeconds)
        .listen((position) {
      if ((position.inMilliseconds - _lastSaved).abs() >= 5000) {
        _lastSaved = position.inMilliseconds;
        unawaited(_checkpoint());
      }
    });
    _stateSubscription = _ctrl.playerStateStream.listen((state) {
      final active = state.playing &&
          state.processingState == ProcessingState.ready &&
          _foreground &&
          _routeVisible;
      unawaited((active
              ? _timer.start()
              : state.processingState == ProcessingState.completed &&
                      _ctrl.loop == null
                  ? _timer.finish()
                  : _timer.pause())
          .catchError((Object _) {
        if (mounted)
          setState(() => _notice = 'Could not update the study timer.');
      }));
      if (!active) unawaited(_checkpoint());
    });
    if (mounted) {
      setState(() {
        _lesson = lesson;
        _showTranscript = lesson['transcript_revealed'] == 1;
        _bookmarks = bookmarks;
        _loading = false;
      });
    }
  }

  Future<void> _bookmark() async {
    final id = newId();
    final pos = _ctrl.position.inMilliseconds;
    await ref.read(appDatabaseProvider).addBookmark(id, widget.lessonId, pos);
    final list =
        await ref.read(appDatabaseProvider).getBookmarks(widget.lessonId);
    if (!mounted) return;
    setState(() => _bookmarks = list);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Bookmark at ${_fmt(Duration(milliseconds: pos))}')),
      );
    }
  }

  Future<void> _saveTranscript() async {
    final parsed = parseTranscript(_transcriptCtrl.text,
        format: _format == 'auto' ? null : _format);
    await _db.saveListeningPreferences(widget.lessonId,
        transcript: _transcriptCtrl.text, transcriptFormat: _format);
    if (mounted) setState(() => _parsed = parsed);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Transcript saved')));
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (router != _router) {
      _router?.routeInformationProvider.removeListener(_navigationChanged);
      _router = router;
      router?.routeInformationProvider.addListener(_navigationChanged);
    }
  }

  void _navigationChanged() {
    final segments = _router?.routeInformationProvider.value.uri.pathSegments;
    _routeVisible = segments != null &&
        segments.length == 4 &&
        segments[0] == 'learn' &&
        segments[1] == 'listening' &&
        segments[2] == 'player' &&
        segments[3] == widget.lessonId;
    if (!_routeVisible) {
      unawaited(_ctrl.pause().catchError((Object _) {}));
      unawaited(_timer.pause().catchError((Object _) {}));
      unawaited(_checkpoint());
    }
  }

  Future<void> _checkpoint() async {
    if (!_ctrl.isReady) return;
    try {
      await _db.updateLessonPosition(
          widget.lessonId, _ctrl.position.inMilliseconds,
          durationMs: _ctrl.duration?.inMilliseconds);
    } catch (_) {
      if (mounted)
        setState(() => _notice = 'Could not save playback position.');
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _notice = null);
    } catch (e) {
      if (mounted)
        setState(() => _notice = e is FormatException
            ? e.message
            : e is ArgumentError
                ? e.message.toString()
                : 'Could not complete this audio action. Check file access and storage.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importTranscript() async {
    final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'srt', 'vtt'],
        withData: false);
    if (picked == null) return;
    final file = File(picked.files.single.path ?? '');
    if (await file.length() > 1000000)
      throw const FormatException('Transcript file is too large.');
    final text = await file.readAsString();
    final extension = p.extension(file.path).toLowerCase();
    final format = extension == '.srt'
        ? 'srt'
        : extension == '.vtt'
            ? 'vtt'
            : 'plain';
    final parsed = parseTranscript(text, format: format);
    await _db.saveListeningPreferences(widget.lessonId,
        transcript: text, transcriptFormat: format);
    if (mounted)
      setState(() {
        _transcriptCtrl.text = text;
        _format = format;
        _parsed = parsed;
      });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      unawaited(_ctrl.pause().catchError((Object _) {}));
      unawaited(_timer.pause().catchError((Object _) {}));
      unawaited(_checkpoint());
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router?.routeInformationProvider.removeListener(_navigationChanged);
    _positionSubscription?.cancel();
    _stateSubscription?.cancel();
    unawaited(_checkpoint());
    unawaited(_timer.pause().catchError((Object _) {}));
    _ctrl.removeListener(_changed);
    _ctrl.dispose();
    _transcriptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    if (_lesson == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Listening')),
        body: const ErrorView(message: 'Lesson not found.'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${_lesson!['title']}'),
        actions: [
          IconButton(
            tooltip: 'Bookmark',
            onPressed:
                _busy || !_ctrl.isReady ? null : () => _action(_bookmark),
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_ctrl.error != null) ErrorView(message: _ctrl.error!),
          if (_notice != null)
            Semantics(liveRegion: true, child: Text(_notice!)),
          Text(
            '${_lesson!['difficulty']} · ${_lesson!['topic'] ?? 'General'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          StreamBuilder<Duration>(
            stream: _ctrl.positionStream,
            builder: (context, snap) {
              final pos = snap.data ?? Duration.zero;
              final total = _ctrl.duration ?? Duration.zero;
              final maxMs =
                  total.inMilliseconds.toDouble().clamp(1, double.infinity);
              return Column(
                children: [
                  Slider(
                    value: (_seekPreview ?? pos.inMilliseconds.toDouble())
                        .clamp(0, maxMs)
                        .toDouble(),
                    max: maxMs.toDouble(),
                    onChanged: _busy || !_ctrl.isReady
                        ? null
                        : (v) => setState(() => _seekPreview = v),
                    onChangeEnd: _busy || !_ctrl.isReady
                        ? null
                        : (v) async {
                            await _action(() async {
                              await _ctrl
                                  .seek(Duration(milliseconds: v.round()));
                              await _checkpoint();
                            });
                            if (mounted) setState(() => _seekPreview = null);
                          },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(pos),
                          style: Theme.of(context).textTheme.bodySmall),
                      Text(_fmt(total),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          StreamBuilder<PlayerState>(
            stream: _ctrl.playerStateStream,
            builder: (context, snap) {
              final playing = snap.data?.playing ?? false;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    iconSize: 36,
                    onPressed: _busy || !_ctrl.isReady
                        ? null
                        : () => _action(() => _ctrl.skip(-10)),
                    icon: const Icon(Icons.replay_10),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(18),
                      backgroundColor: AppColors.violet,
                    ),
                    onPressed: _busy || !_ctrl.isReady
                        ? null
                        : () => _action(
                            () => playing ? _ctrl.pause() : _ctrl.play()),
                    child: Icon(playing ? Icons.pause : Icons.play_arrow,
                        size: 36, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    iconSize: 36,
                    onPressed: _busy || !_ctrl.isReady
                        ? null
                        : () => _action(() => _ctrl.skip(10)),
                    icon: const Icon(Icons.forward_10),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Playback speed'),
          Wrap(
            spacing: 8,
            children: _speeds.map((s) {
              final selected = (_speed - s).abs() < 0.01;
              return ChoiceChip(
                label: Text('${s}x'),
                selected: selected,
                onSelected: (_) async {
                  await _action(() async {
                    await _ctrl.setSpeed(s);
                    await _db.saveListeningPreferences(widget.lessonId,
                        speed: s);
                    if (mounted) setState(() => _speed = s);
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'A–B segment loop'),
          Text(
              'A: ${_loopA == null ? 'not set' : _fmt(Duration(milliseconds: _loopA!))} · B: ${_loopB == null ? 'not set' : _fmt(Duration(milliseconds: _loopB!))}'),
          Wrap(spacing: 8, children: [
            OutlinedButton(
                onPressed: _busy || !_ctrl.isReady
                    ? null
                    : () => _action(() async {
                          _ctrl.setABLoop(null, null);
                          await _db.saveListeningPreferences(widget.lessonId,
                              clearLoop: true);
                          if (mounted)
                            setState(() {
                              _loopA = _ctrl.position.inMilliseconds;
                              _loopB = null;
                            });
                        }),
                child: const Text('Mark A')),
            OutlinedButton(
                onPressed: _busy || !_ctrl.isReady
                    ? null
                    : () => _action(() async {
                          _ctrl.setABLoop(null, null);
                          await _db.saveListeningPreferences(widget.lessonId,
                              clearLoop: true);
                          if (mounted)
                            setState(
                                () => _loopB = _ctrl.position.inMilliseconds);
                        }),
                child: const Text('Mark B')),
            FilledButton(
                onPressed: _busy || _loopA == null || _loopB == null
                    ? null
                    : () => _action(() async {
                          _ctrl.setABLoop(_loopA, _loopB);
                          await _db.saveListeningPreferences(widget.lessonId,
                              startMs: _loopA, endMs: _loopB);
                          await _ctrl.seek(Duration(milliseconds: _loopA!));
                        }),
                child: const Text('Repeat A–B')),
            TextButton(
                onPressed: _busy
                    ? null
                    : () => _action(() async {
                          _ctrl.setABLoop(null, null);
                          await _db.saveListeningPreferences(widget.lessonId,
                              clearLoop: true);
                          if (mounted)
                            setState(() {
                              _loopA = null;
                              _loopB = null;
                            });
                        }),
                child: const Text('Clear loop')),
          ]),
          if (_ctrl.loop != null)
            const Text(
                'Segment repeat is enabled. Clear it to play the full lesson.'),
          if (_bookmarks.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionHeader(title: 'Bookmarks'),
            ..._bookmarks.map((b) {
              final ms = b['position_ms'] as int;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.bookmark, color: AppColors.teal),
                title: Text(_fmt(Duration(milliseconds: ms))),
                subtitle: b['label'] != null ? Text('${b['label']}') : null,
                onTap: _busy || !_ctrl.isReady
                    ? null
                    : () => _action(() async {
                          await _ctrl.seek(Duration(milliseconds: ms));
                          await _checkpoint();
                        }),
              );
            }),
          ],
          const SizedBox(height: 20),
          SectionHeader(
            title: 'Transcript',
            trailing: TextButton(
              onPressed: _busy
                  ? null
                  : () => _action(() async {
                        final show = !_showTranscript;
                        (await _db.db).execute(
                            'UPDATE listening_lessons SET transcript_revealed=? WHERE id=?',
                            [show ? 1 : 0, widget.lessonId]);
                        if (mounted) setState(() => _showTranscript = show);
                      }),
              child: Text(_showTranscript ? 'Hide' : 'Show'),
            ),
          ),
          Text(
            'Recommended: listen first, then answer comprehension questions, then reveal the transcript.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_showTranscript) ...[
            const SizedBox(height: 12),
            ExpansionTile(
                title: const Text('Edit or import transcript'),
                children: [
                  TextField(
                    controller: _transcriptCtrl,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: 'Paste or type transcript here…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                      value: _format,
                      items: const [
                        DropdownMenuItem(
                            value: 'auto',
                            child: Text('Auto-detect transcript format')),
                        DropdownMenuItem(
                            value: 'plain',
                            child: Text('Plain TXT (not synchronized)')),
                        DropdownMenuItem(
                            value: 'srt', child: Text('SRT timestamps')),
                        DropdownMenuItem(
                            value: 'vtt', child: Text('WebVTT timestamps'))
                      ],
                      onChanged:
                          _busy ? null : (v) => setState(() => _format = v!)),
                  Wrap(spacing: 8, children: [
                    TextButton(
                        onPressed:
                            _busy ? null : () => _action(_importTranscript),
                        child: const Text('Import TXT / SRT / VTT')),
                    TextButton(
                        onPressed:
                            _busy ? null : () => _action(_saveTranscript),
                        child: const Text('Save transcript')),
                  ]),
                ]),
            if (_parsed?.synchronized == true) ...[
              SwitchListTile(
                  title: const Text('Auto-scroll transcript'),
                  value: _autoScroll,
                  onChanged: _busy
                      ? null
                      : (value) => _action(() async {
                            await _db.saveListeningPreferences(widget.lessonId,
                                autoScroll: value);
                            if (mounted) setState(() => _autoScroll = value);
                          })),
              SynchronizedTranscript(
                  transcript: _parsed!,
                  positions: _ctrl.positionStream,
                  seek: (position) => _action(() => _ctrl.seek(position)),
                  autoScroll: _autoScroll,
                  enabled: _ctrl.isReady && !_busy,
                  initialPosition: _ctrl.position),
            ] else if (_parsed != null)
              PlainTranscript(text: _parsed!.text),
          ],
          const SizedBox(height: 24),
          ModuleTile(
            icon: Icons.quiz_outlined,
            title: 'Comprehension practice',
            subtitle: 'Answer questions for this lesson',
            onTap: () {
              _ctrl.pause();
              Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) =>
                      ComprehensionScreen(lessonId: widget.lessonId)));
            },
          ),
          const SizedBox(height: 10),
          ModuleTile(
            icon: Icons.record_voice_over_outlined,
            title: 'Shadowing practice',
            subtitle: 'Listen, then record yourself',
            onTap: () {
              _pushShadow();
            },
          ),
        ],
      ),
    );
  }

  void _pushShadow() {
    // Navigate via go_router if route exists; otherwise snackbar
    _ctrl.pause();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShadowingScreen(
            lessonId: widget.lessonId,
            title: '${_lesson!['title']}',
            initialStartMs: _loopA,
            initialEndMs: _loopB),
      ),
    );
  }
}
