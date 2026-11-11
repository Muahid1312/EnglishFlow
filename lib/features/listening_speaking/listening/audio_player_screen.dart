import 'dart:async';

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
  const AudioPlayerScreen({super.key, required this.lessonId});

  @override
  ConsumerState<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

class _AudioPlayerScreenState extends ConsumerState<AudioPlayerScreen> {
  final _ctrl = AudioPlayerController();
  Map<String, dynamic>? _lesson;
  List<Map<String, dynamic>> _bookmarks = [];
  bool _showTranscript = false;
  bool _loading = true;
  double _speed = 1.0;
  StreamSubscription<Duration>? _positionSubscription;
  final _transcriptCtrl = TextEditingController();

  static const _speeds = [0.75, 1.0, 1.25, 1.5];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final db = ref.read(appDatabaseProvider);
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
      startMs: (lesson['last_position_ms'] as int?) ?? 0,
    );
    if (!mounted) return;
    // Keep and cancel the subscription before disposing the controller.
    _positionSubscription = _ctrl.positionStream
        .distinct((a, b) => a.inSeconds == b.inSeconds)
        .listen((pos) async {
      final dur = _ctrl.duration;
      await ref.read(appDatabaseProvider).updateLessonPosition(
            widget.lessonId,
            pos.inMilliseconds,
            durationMs: dur?.inMilliseconds,
          );
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
    await ref.read(appDatabaseProvider).updateLessonTranscript(
          widget.lessonId,
          _transcriptCtrl.text.trim(),
        );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Transcript saved')));
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
    _positionSubscription?.cancel();
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
    if (_ctrl.error != null) {
      return Scaffold(
        appBar: AppBar(title: Text('${_lesson!['title']}')),
        body: ErrorView(message: _ctrl.error!),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('${_lesson!['title']}'),
        actions: [
          IconButton(
            tooltip: 'Bookmark',
            onPressed: _bookmark,
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
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
                    value:
                        pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble(),
                    max: maxMs.toDouble(),
                    onChanged: (v) =>
                        _ctrl.seek(Duration(milliseconds: v.round())),
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
                    onPressed: () => _ctrl.skip(-10),
                    icon: const Icon(Icons.replay_10),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(18),
                      backgroundColor: AppColors.violet,
                    ),
                    onPressed: () => playing ? _ctrl.pause() : _ctrl.play(),
                    child: Icon(playing ? Icons.pause : Icons.play_arrow,
                        size: 36, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    iconSize: 36,
                    onPressed: () => _ctrl.skip(10),
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
                  setState(() => _speed = s);
                  await _ctrl.setSpeed(s);
                },
              );
            }).toList(),
          ),
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
                onTap: () => _ctrl.seek(Duration(milliseconds: ms)),
              );
            }),
          ],
          const SizedBox(height: 20),
          SectionHeader(
            title: 'Transcript',
            trailing: TextButton(
              onPressed: () async {
                if (!_showTranscript) {
                  await ref
                      .read(appDatabaseProvider)
                      .revealTranscript(widget.lessonId);
                }
                if (mounted) setState(() => _showTranscript = !_showTranscript);
              },
              child: Text(_showTranscript ? 'Hide' : 'Show'),
            ),
          ),
          Text(
            'Recommended: listen first, then answer comprehension questions, then reveal the transcript.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_showTranscript) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _transcriptCtrl,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: 'Paste or type transcript here…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SecondaryButton(
                label: 'Save transcript', onPressed: _saveTranscript),
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
            lessonId: widget.lessonId, title: '${_lesson!['title']}'),
      ),
    );
  }
}
