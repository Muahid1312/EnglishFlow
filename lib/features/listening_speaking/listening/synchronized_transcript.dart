import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/services/transcript_parser.dart';

class SynchronizedTranscript extends StatefulWidget {
  const SynchronizedTranscript(
      {super.key,
      required this.transcript,
      required this.positions,
      required this.seek,
      required this.autoScroll,
      this.enabled = true,
      this.initialPosition = Duration.zero});
  final Duration initialPosition;
  final ParsedTranscript transcript;
  final Stream<Duration> positions;
  final Future<void> Function(Duration) seek;
  final bool autoScroll, enabled;
  @override
  State<SynchronizedTranscript> createState() => _SynchronizedTranscriptState();
}

class _SynchronizedTranscriptState extends State<SynchronizedTranscript> {
  final _scroll = ScrollController();
  final _active = ValueNotifier<int>(-1);
  StreamSubscription<Duration>? _subscription;
  @override
  void initState() {
    super.initState();
    _active.value =
        widget.transcript.activeIndex(widget.initialPosition.inMilliseconds);
    _listen();
    _scrollTo(_active.value);
  }

  void _scrollTo(int index) {
    if (!widget.autoScroll || index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
            (index * 104.0)
                .clamp(0, _scroll.position.maxScrollExtent)
                .toDouble(),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut);
      }
    });
  }

  void _listen() {
    _subscription?.cancel();
    _subscription = widget.positions.listen((position) {
      final next = widget.transcript.activeIndex(position.inMilliseconds);
      if (next == _active.value) return;
      _active.value = next;
      _scrollTo(next);
    });
  }

  @override
  void didUpdateWidget(covariant SynchronizedTranscript old) {
    super.didUpdateWidget(old);
    if (old.transcript != widget.transcript ||
        old.positions != widget.positions) {
      _active.value =
          widget.transcript.activeIndex(widget.initialPosition.inMilliseconds);
      _listen();
    }
    if (widget.autoScroll && !old.autoScroll) _scrollTo(_active.value);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scroll.dispose();
    _active.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
      height: 320,
      child: ValueListenableBuilder<int>(
        valueListenable: _active,
        builder: (context, active, _) => ListView.builder(
            controller: _scroll,
            itemExtent: 104,
            itemCount: widget.transcript.cues.length,
            itemBuilder: (context, index) {
              final cue = widget.transcript.cues[index];
              return ListTile(
                selected: index == active,
                selectedTileColor:
                    Theme.of(context).colorScheme.primaryContainer,
                title: Text(cue.text,
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${(cue.startMs / 1000).toStringAsFixed(2)}–${(cue.endMs / 1000).toStringAsFixed(2)}s'),
                onTap: widget.enabled
                    ? () => widget.seek(Duration(milliseconds: cue.startMs))
                    : null,
                onLongPress: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                            content: SingleChildScrollView(
                                child: SelectableText(cue.text)),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Close'))
                            ])),
              );
            }),
      ));
}

class PlainTranscript extends StatelessWidget {
  const PlainTranscript({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return const Text(
          'No transcript yet. Expand Edit or import transcript to add TXT, SRT or WebVTT.');
    }
    final chunks = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = (start + 2000).clamp(0, text.length).toInt();
      if (end < text.length) {
        final space = text.lastIndexOf(' ', end);
        if (space > start) end = space + 1;
      }
      chunks.add(text.substring(start, end));
      start = end;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Plain transcript — no timestamp synchronization.'),
      SizedBox(
          height: 320,
          child: ListView.builder(
              itemCount: chunks.length,
              itemBuilder: (_, index) => SelectableText(chunks[index]))),
    ]);
  }
}
