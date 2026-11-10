import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/services/audio_player_controller.dart';
import '../../../core/services/providers.dart';
import '../../../core/utils/id_utils.dart';
import '../../../core/widgets/common_widgets.dart';

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
    _transcriptCtrl.text = (lesson['transcript'] as String?) ?? '';
    await _ctrl.load(
      lesson['audio_path'] as String,
      startMs: (lesson['last_position_ms'] as int?) ?? 0,
    );
    // Persist position periodically
    _ctrl.positionStream.listen((pos) async {
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
                    max: maxMs,
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
          SectionHeader(title: 'Playback speed'),
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
            SectionHeader(title: 'Bookmarks'),
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
              onPressed: () =>
                  setState(() => _showTranscript = !_showTranscript),
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'Add questions from the lesson menu in a future update. You can still track listening time from Learn.')),
              );
            },
          ),
          const SizedBox(height: 10),
          ModuleTile(
            icon: Icons.record_voice_over_outlined,
            title: 'Shadowing practice',
            subtitle: 'Listen, then record yourself',
            onTap: () {
              context_push_shadow();
            },
          ),
        ],
      ),
    );
  }

  void context_push_shadow() {
    // Navigate via go_router if route exists; otherwise snackbar
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShadowingScreen(
            lessonId: widget.lessonId, title: '${_lesson!['title']}'),
      ),
    );
  }
}

/// Minimal shadowing UI (offline).
class ShadowingScreen extends ConsumerStatefulWidget {
  final String lessonId;
  final String title;
  const ShadowingScreen(
      {super.key, required this.lessonId, required this.title});

  @override
  ConsumerState<ShadowingScreen> createState() => _ShadowingScreenState();
}

class _ShadowingScreenState extends ConsumerState<ShadowingScreen> {
  final _player = AudioPlayerController();
  bool _recording = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final lesson =
        await ref.read(appDatabaseProvider).getListeningLesson(widget.lessonId);
    if (lesson != null) {
      await _player.load(lesson['audio_path'] as String);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shadowing')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '1. Play a short segment of the reference.\n2. Pause and record yourself repeating it.\n3. Replay both and compare.\n\nNo automatic pronunciation score is claimed — rate yourself honestly.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          SectionHeader(title: 'Reference audio'),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () =>
                    _player.playing ? _player.pause() : _player.play(),
                icon: Icon(_player.playing ? Icons.pause : Icons.play_arrow),
                label: Text(_player.playing ? 'Pause' : 'Play'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                  onPressed: () => _player.skip(-5), child: const Text('-5s')),
              const SizedBox(width: 8),
              OutlinedButton(
                  onPressed: () => _player.skip(5), child: const Text('+5s')),
            ],
          ),
          const SizedBox(height: 24),
          SectionHeader(title: 'Your recording'),
          Text(
            _status ??
                'Recording UI uses the Speaking Studio recorder. Open a speaking prompt to capture attempts, or use the full recorder from Speaking Studio.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            label: _recording
                ? 'Stop (open Speaking Studio)'
                : 'Open Speaking Studio',
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
