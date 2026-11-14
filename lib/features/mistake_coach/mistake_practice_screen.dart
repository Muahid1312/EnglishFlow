import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/mistake_coach.dart';
import '../../core/services/practice_timer.dart';
import '../../core/services/providers.dart';
import '../../core/utils/id_utils.dart';
import '../../core/widgets/common_widgets.dart';
import '../dashboard/dashboard_provider.dart';

class MistakePracticeScreen extends ConsumerStatefulWidget {
  const MistakePracticeScreen({super.key, this.category});
  final String? category;
  @override
  ConsumerState<MistakePracticeScreen> createState() =>
      _MistakePracticeScreenState();
}

class _MistakePracticeScreenState extends ConsumerState<MistakePracticeScreen>
    with WidgetsBindingObserver {
  late final MistakeCoach _coach;
  late final PracticeTimer _timer;
  List<Map<String, dynamic>>? _queue;
  final _answer = TextEditingController();
  int _index = 0;
  String _attempt = newId();
  String? _error;
  bool _started = false,
      _self = false,
      _revealed = false,
      _saved = false,
      _busy = false,
      _paused = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _coach = MistakeCoach(ref.read(appDatabaseProvider));
    _timer =
        PracticeTimer(ref.read(studySessionServiceProvider), 'grammar_writing');
    _load();
  }

  Future<void> _load() async {
    try {
      await _timer.pause();
      final rows = await _coach.practice(category: widget.category);
      if (mounted) {
        setState(() {
          _queue = rows;
          _index = 0;
          _attempt = newId();
          _started = false;
          _saved = false;
          _revealed = false;
          _paused = false;
          _answer.clear();
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load saved corrections.');
    }
  }

  Future<void> _save(Map<String, dynamic> item, {bool? selfAssessment}) async {
    if (_busy || _saved || _paused || _answer.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await _coach.answer(
          attemptId: _attempt,
          mistakeId: item['id'] as String,
          expectedRevision: item['revision'] as int,
          response: _answer.text,
          selfAssessment: selfAssessment);
      if (mounted) {
        setState(() {
          _saved = true;
          _revealed = true;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is StateError
            ? e.message.toString()
            : 'Could not save this practice attempt.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (mounted) setState(() => _paused = true);
      unawaited(_timer.pause().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_timer.pause().catchError((Object _) {}));
    _answer.dispose();
    super.dispose();
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Could not save the study timer. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
        studySessionServiceProvider.select((s) => (s.active?.id, s.isRunning)));
    final paused = _paused ||
        (_started &&
            (_timer.sessions.active?.id != _timer.id ||
                !_timer.sessions.isRunning));
    final item =
        _queue != null && _index < _queue!.length ? _queue![_index] : null;
    return Scaffold(
        appBar: AppBar(title: const Text('Personal Mistake Coach')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          if (_error != null) ErrorView(message: _error!, onRetry: _load),
          if (_queue == null && _error == null) const LoadingView(),
          if (_queue?.isEmpty == true)
            const EmptyState(
                icon: Icons.checklist,
                title: 'No confirmed corrections yet',
                message:
                    'Add a mistake and corrected sentence in your journal or confirm a correction from Writing Studio.'),
          if (item != null) ...[
            Text(
                'Practice ${_index + 1} of ${_queue!.length} · ${item['grammar_topic']}'),
            LexiCard(
                child: Text(item['original_sentence'] as String,
                    style: Theme.of(context).textTheme.titleLarge)),
            if (!_started)
              FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _action(() async {
                            await _timer.start();
                            if (mounted) {
                              setState(() => _started = true);
                            } else {
                              await _timer.pause();
                            }
                          }),
                  child: const Text('Start practice')),
            if (_started && !paused) ...[
              SwitchListTile(
                  title: const Text('Open rewrite / explain (self-assessed)'),
                  value: _self,
                  onChanged: _saved || _revealed
                      ? null
                      : (v) => setState(() => _self = v)),
              Text(_self
                  ? 'Rewrite naturally or explain your correction. You will assess your own answer.'
                  : 'Reproduce your saved corrected sentence. Case and punctuation must match; extra whitespace is ignored. Only saved wording is checked; other valid wording is not automatically judged wrong.'),
              TextField(
                  controller: _answer,
                  minLines: 2,
                  maxLines: 5,
                  readOnly: _revealed,
                  decoration:
                      const InputDecoration(labelText: 'Your response')),
              if (!_revealed)
                FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            if (_answer.text.trim().isEmpty) return;
                            if (_self) {
                              setState(() => _revealed = true);
                            } else {
                              _save(item);
                            }
                          },
                    child: Text(
                        _self ? 'Reveal correction' : 'Check saved wording')),
              if (_revealed) ...[
                Text('Saved correction: ${item['correction']}'),
                if (item['explanation'] != null)
                  Text(item['explanation'] as String),
                if (_self && !_saved)
                  Wrap(spacing: 8, children: [
                    OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _save(item, selfAssessment: false),
                        child: const Text('Needs more practice')),
                    FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _save(item, selfAssessment: true),
                        child: const Text('I understand this correction')),
                  ]),
                if (_saved) ...[
                  Text(_self
                      ? 'Self-assessment saved. This is not automatic grading.'
                      : 'Wording comparison saved. This does not establish grammar mastery.'),
                  FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _action(() async {
                                if (_index + 1 == _queue!.length) {
                                  await _timer.finish();
                                  ref.invalidate(dashboardProvider);
                                }
                                if (mounted) {
                                  setState(() {
                                    _index++;
                                    _attempt = newId();
                                    _answer.clear();
                                    _revealed = false;
                                    _saved = false;
                                  });
                                }
                              }),
                      child: const Text('Next')),
                ],
              ],
            ],
            if (_started)
              TextButton(
                  onPressed: _busy
                      ? null
                      : () => _action(() async {
                            if (paused) {
                              await _timer.start();
                            } else {
                              await _timer.pause();
                            }
                            if (mounted) setState(() => _paused = !paused);
                          }),
                  child: Text(paused ? 'Resume' : 'Pause')),
          ],
          if (_queue?.isNotEmpty == true && item == null)
            const Text(
                'Practice saved. Revisit recurring categories over time; one correct answer is not mastery.'),
          if (_queue?.isNotEmpty == true &&
              item == null &&
              _timer.sessions.hasActive)
            const Text(
                'The shared study timer is paused. Finish the active study activity when ready to record completed-day minutes.'),
        ]));
  }
}
