import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/providers.dart';
import '../../../core/services/shadowing_controller.dart';
import '../../../core/widgets/common_widgets.dart';

class ShadowingScreen extends ConsumerStatefulWidget {
  const ShadowingScreen(
      {super.key,
      required this.lessonId,
      required this.title,
      this.controller});
  final String lessonId, title;
  final ShadowingController? controller;
  @override
  ConsumerState<ShadowingScreen> createState() => _ShadowingScreenState();
}

class _ShadowingScreenState extends ConsumerState<ShadowingScreen>
    with WidgetsBindingObserver {
  late final ShadowingController _controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = widget.controller ??
        ShadowingController(ref.read(appDatabaseProvider), widget.lessonId,
            study: ref.read(studySessionServiceProvider));
    _controller.addListener(_changed);
    _controller.initialize();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.onResumed();
    } else if (state != AppLifecycleState.inactive ||
        (!_controller.busy &&
            (_controller.recording ||
                _controller.reference.playing ||
                _controller.playback.playing))) {
      unawaited(_controller.onPaused().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _delete(String id) async {
    final accepted = await showConfirmDialog(context,
        title: 'Delete attempt?',
        message: 'This removes the recording and its saved attempt.');
    if (accepted == true) await _controller.deleteTake(id);
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final locked = c.busy || c.recording || c.pending != null;
    return Scaffold(
        appBar: AppBar(title: const Text('Shadowing')),
        body: c.loading
            ? const LoadingView()
            : ListView(padding: const EdgeInsets.all(20), children: [
                Text(widget.title,
                    style: Theme.of(context).textTheme.titleLarge),
                const Text(
                    'Choose a segment. Listen, record, compare, then save your attempt. No automatic pronunciation score is claimed.'),
                if (c.error != null)
                  ErrorView(message: c.error!, onRetry: c.initialize),
                if (c.totalMs > 0) ...[
                  const SectionHeader(title: 'Reference segment'),
                  Text(
                      '${(c.startMs / 1000).toStringAsFixed(1)}–${(c.endMs / 1000).toStringAsFixed(1)} seconds'),
                  RangeSlider(
                      values: RangeValues(
                          c.startMs.toDouble().clamp(0, c.totalMs.toDouble()),
                          c.endMs.toDouble().clamp(0, c.totalMs.toDouble())),
                      min: 0,
                      max: c.totalMs.toDouble(),
                      onChanged: locked
                          ? null
                          : (v) =>
                              c.setSegment(v.start.round(), v.end.round())),
                  OutlinedButton.icon(
                      onPressed: c.busy || c.recording ? null : c.playReference,
                      icon: Icon(
                          c.reference.playing ? Icons.pause : Icons.play_arrow),
                      label: Text(c.reference.playing
                          ? 'Pause reference'
                          : 'Play reference')),
                  PrimaryButton(
                      label: c.recording ? 'Stop recording' : 'Record segment',
                      icon: c.recording ? Icons.stop : Icons.mic,
                      onPressed: c.busy || (c.pending != null && !c.recording)
                          ? null
                          : c.recording
                              ? c.stopRecording
                              : c.startRecording),
                ],
                if (c.pending != null)
                  LexiCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                            'Unsaved take · ${(c.pending!.durationMs / 1000).toStringAsFixed(1)} seconds'),
                        const Text(
                            'This draft is stored locally so an interruption will not discard it.'),
                        Wrap(spacing: 8, children: [
                          OutlinedButton(
                              onPressed: c.busy
                                  ? null
                                  : () => c.playTake(c.pending!.path),
                              child: const Text('Replay your recording')),
                          FilledButton(
                              onPressed: c.busy ? null : c.saveTake,
                              child: const Text('Save attempt'))
                        ]),
                      ])),
                const SizedBox(height: 20),
                const SectionHeader(title: 'Attempt history'),
                if (c.history.isEmpty) const Text('No attempts recorded yet.'),
                for (final a in c.history)
                  ListTile(
                      onTap: locked
                          ? null
                          : () => c.setSegment(a['segment_start_ms'] as int,
                              a['segment_end_ms'] as int? ?? c.totalMs),
                      title: Text(
                          '${a['saved'] == 1 ? 'Saved' : 'Draft'} · ${a['created_at']}'),
                      subtitle: Text(
                          '${(a['segment_start_ms'] as int) / 1000}–${(a['segment_end_ms'] as int? ?? 0) / 1000}s · ${((a['duration_ms'] as int) / 1000).toStringAsFixed(1)}s recorded'),
                      leading: IconButton(
                          tooltip: 'Replay attempt',
                          onPressed:
                              c.busy || c.recording || a['audio_path'] == null
                                  ? null
                                  : () => c.playTake(a['audio_path'] as String),
                          icon: const Icon(Icons.play_arrow)),
                      trailing: IconButton(
                          tooltip: 'Delete attempt',
                          onPressed: c.busy || c.recording
                              ? null
                              : () => _delete(a['id'] as String),
                          icon: const Icon(Icons.delete_outline))),
              ]));
  }
}
