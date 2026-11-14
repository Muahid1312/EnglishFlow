import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/providers.dart';
import '../../core/services/practice_timer.dart';
import '../../core/services/vocabulary_intelligence.dart';
import '../../core/widgets/common_widgets.dart';
import '../dashboard/dashboard_provider.dart';

class VocabularyChallengeScreen extends ConsumerStatefulWidget {
  const VocabularyChallengeScreen({super.key});
  @override
  ConsumerState<VocabularyChallengeScreen> createState() =>
      _VocabularyChallengeScreenState();
}

class _VocabularyChallengeScreenState
    extends ConsumerState<VocabularyChallengeScreen>
    with WidgetsBindingObserver {
  VocabularyChallengeType _type = VocabularyChallengeType.context;
  List<VocabularyChallenge>? _questions;
  Map<String, dynamic>? _stats;
  late final PracticeTimer _timer;
  final _answer = TextEditingController();
  int _index = 0, _matched = 0;
  bool _started = false, _revealed = false, _paused = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = PracticeTimer(ref.read(studySessionServiceProvider), 'vocabulary');
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _questions = null);
    try {
      await _timer.pause();
      final db = ref.read(appDatabaseProvider);
      final stats = await VocabularyIntelligence(db).insights();
      final questions = vocabularyChallenges(await db.getVocabulary(), _type);
      if (mounted)
        setState(() {
          _stats = stats;
          _questions = questions;
          _index = 0;
          _matched = 0;
          _revealed = false;
          _started = false;
          _paused = false;
          _answer.clear();
          _error = null;
        });
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Could not load vocabulary practice.');
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
      if (mounted)
        setState(
            () => _error = 'Could not save the study timer. Please retry.');
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
    final stats = _stats;
    final q = _questions != null && _index < _questions!.length
        ? _questions![_index]
        : null;
    return Scaffold(
        appBar: AppBar(title: const Text('Vocabulary practice & insights')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          if (stats != null)
            LexiCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      '${stats['saved']} saved · ${stats['due']} due · ${stats['reviewed']} reviewed words'),
                  Text(stats['successRate'] == null
                      ? 'Review success: more practice needed'
                      : 'Review success: ${((stats['successRate'] as double) * 100).toStringAsFixed(0)}%'),
                  const Text(
                      'Success = Good or Easy ratings / all ratings on currently saved canonical words. Hard and Again are not counted as successes.'),
                  Text(stats['trend'] == null
                      ? 'Retention trend: needs 20 reviews.'
                      : 'Recent rating trend: ${((stats['trend'] as double) * 100).toStringAsFixed(0)} percentage points (last 10 vs previous 10). This is a rating trend, not a memory test.'),
                  for (final row in stats['forgotten'] as List)
                    Text('${row['word']} · ${row['failures']} Again ratings'),
                  const SizedBox(height: 8),
                  const Text('Recent review activity'),
                  for (final row in stats['recent'] as List)
                    Text(
                        '${row['word']} · ${row['reviewed_at']} · ${row['rating']}'),
                ])),
          const SizedBox(height: 16),
          DropdownButtonFormField<VocabularyChallengeType>(
              value: _type,
              items: const [
                DropdownMenuItem(
                    value: VocabularyChallengeType.context,
                    child: Text('Context Challenge')),
                DropdownMenuItem(
                    value: VocabularyChallengeType.meaning,
                    child: Text('Meaning Match')),
                DropdownMenuItem(
                    value: VocabularyChallengeType.recall,
                    child: Text('Recall Challenge'))
              ],
              onChanged: _started
                  ? null
                  : (type) {
                      _type = type!;
                      _load();
                    }),
          const SizedBox(height: 12),
          const Text(
              'Recall the saved wording. A different valid synonym is not automatically graded as grammatically wrong. These challenges do not change review schedules.'),
          if (_error != null) ErrorView(message: _error!, onRetry: _load),
          if (_questions == null && _error == null) const LoadingView(),
          if (_questions?.isEmpty == true)
            const EmptyState(
                icon: Icons.lightbulb_outline,
                title: 'More vocabulary needed',
                message:
                    'Add distinct English definitions for meaning/recall, or a source sentence containing the word exactly once for context practice.'),
          if (q != null) ...[
            Text('Question ${_index + 1} of ${_questions!.length}'),
            LexiCard(
                child: Text(q.prompt,
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
              if (q.options.isEmpty)
                TextField(
                    controller: _answer,
                    readOnly: _revealed,
                    decoration: const InputDecoration(labelText: 'Your answer'))
              else
                for (final option in q.options)
                  RadioListTile<String>(
                      value: option,
                      groupValue: _answer.text,
                      title: Text(option),
                      onChanged: _revealed
                          ? null
                          : (v) => setState(() => _answer.text = v!)),
              if (!_revealed)
                FilledButton(
                    onPressed: () {
                      if (_answer.text.trim().isEmpty) return;
                      setState(() {
                        _revealed = true;
                        if (q.matches(_answer.text)) _matched++;
                      });
                    },
                    child: const Text('Check saved answer'))
              else ...[
                Text(q.matches(_answer.text)
                    ? 'Matches your saved answer.'
                    : 'Saved answer: ${q.answer}'),
                FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _action(() async {
                              if (_index + 1 == _questions!.length) {
                                await _timer.finish();
                                ref.invalidate(dashboardProvider);
                              }
                              if (mounted)
                                setState(() {
                                  _index++;
                                  _revealed = false;
                                  _answer.clear();
                                });
                            }),
                    child: const Text('Continue')),
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
          if (_questions?.isNotEmpty == true && q == null)
            Text(
                '$_matched of ${_questions!.length} matched saved answers. Practice time was saved without changing SRS ratings.'),
          if (_questions?.isNotEmpty == true &&
              q == null &&
              _timer.sessions.hasActive)
            const Text(
                'Finish the paused shared study timer when ready to include its minutes in completed-day progress.'),
        ]));
  }
}
