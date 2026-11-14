import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/ai_teacher_service.dart';
import '../../../core/services/providers.dart';
import '../../../core/utils/id_utils.dart';
import '../../../core/widgets/ai_help_button.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/services/practice_timer.dart';

class ComprehensionScreen extends ConsumerStatefulWidget {
  const ComprehensionScreen({super.key, required this.lessonId});
  final String lessonId;
  @override
  ConsumerState<ComprehensionScreen> createState() =>
      _ComprehensionScreenState();
}

class _ComprehensionScreenState extends ConsumerState<ComprehensionScreen> {
  List<Map<String, dynamic>> _questions = [], _attempts = [];
  Map<String, dynamic>? _lesson;
  final _answers = <String, String>{};
  bool _loading = true, _busy = false, _reveal = false, _submitted = false;
  late final PracticeTimer _timer;
  String? _error;
  String _submission = newId();
  late final AppDatabase _db = ref.read(appDatabaseProvider);
  @override
  void initState() {
    super.initState();
    final active = ref.read(studySessionServiceProvider).active;
    _timer = PracticeTimer(
        ref.read(studySessionServiceProvider),
        active?.module == 'listening_speaking'
            ? 'listening_speaking'
            : 'listening');
    _load();
  }

  Future<void> _load() async {
    try {
      final token = await _db.comprehensionSubmission(widget.lessonId);
      final lesson = await _db.getListeningLesson(widget.lessonId);
      final questions = await _db.getQuestions(widget.lessonId);
      final attempts = await _db.getComprehensionAttempts(widget.lessonId);
      if (!mounted) return;
      final draft = lesson?['comprehension_draft'] as String? ?? '{}';
      final saved = jsonDecode(draft) as Map<String, dynamic>;
      setState(() {
        _submission = token;
        _submitted = attempts.any((a) => a['submission_id'] == token);
        _lesson = lesson;
        _questions = questions;
        _attempts = attempts;
        _answers
          ..clear()
          ..addAll(saved.map((k, v) => MapEntry(k, '$v')));
        _reveal = lesson?['transcript_revealed'] == 1;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load comprehension practice.';
        });
      }
    }
  }

  Future<void> _change(String id, String answer) async {
    if (_submitted) return;
    await _timer.start();
    if (!mounted) {
      await _timer.pause();
      return;
    }
    setState(() => _answers[id] = answer);
    try {
      await _db.saveComprehensionDraft(widget.lessonId, Map.of(_answers));
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not save answers. Keep this page open and retry submission.');
      }
    }
  }

  Future<void> _submit() async {
    if (_busy || _submitted) return;
    setState(() => _busy = true);
    try {
      await _db.submitComprehension(
          widget.lessonId, _submission, Map.of(_answers));
      await _timer.finish();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Answers saved. Review the results below. Short answers require your self-assessment.')));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError
            ? error.message.toString()
            : 'Could not save answers. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? question]) async {
    await showDialog<void>(
        context: context,
        builder: (_) => _QuestionEditor(
            db: _db, lessonId: widget.lessonId, question: question));
    if (mounted) await _load();
  }

  Future<void> _revealTranscript() async {
    try {
      await _db.revealTranscript(widget.lessonId);
      if (mounted) setState(() => _reveal = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save transcript reveal.');
    }
  }

  List<String> _choices(Map<String, dynamic> question) {
    try {
      return (jsonDecode(question['choices'] as String? ?? '[]') as List)
          .map((v) => '$v')
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    unawaited(_timer.pause().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    if (_lesson == null) {
      return Scaffold(
          appBar: AppBar(),
          body: ErrorView(
              message: _error ?? 'Lesson not found.', onRetry: _load));
    }
    final latest = _attempts.isEmpty
        ? <Map<String, dynamic>>[]
        : _attempts
            .where(
                (a) => a['submission_id'] == _attempts.first['submission_id'])
            .toList();
    final objective = latest
        .where((a) => a['self_assessed'] == 0 && a['is_correct'] != null)
        .toList();
    return Scaffold(
        appBar: AppBar(title: const Text('Comprehension'), actions: [
          IconButton(
              tooltip: 'Add question',
              onPressed: _busy ? null : () => _edit(),
              icon: const Icon(Icons.add))
        ]),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          if (_submitted)
            TextButton(
                onPressed: _busy
                    ? null
                    : () async {
                        await _db.comprehensionSubmission(widget.lessonId,
                            retry: true);
                        await _load();
                      },
                child: const Text('Start a new attempt')),
          const Text(
              'Listen to the audio first. Saved questions and answers work offline.'),
          if (_error != null) ErrorView(message: _error!),
          if (_questions.isEmpty)
            EmptyState(
                icon: Icons.quiz_outlined,
                title: 'No questions saved',
                message:
                    'Create your own questions and answer keys. No answers or scores are generated offline.',
                action: OutlinedButton(
                    onPressed: () => _edit(),
                    child: const Text('Create question'))),
          for (final q in _questions)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: LexiCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        Expanded(
                            child: Text(
                                '${q['question_type']} · ${q['question']}',
                                style: Theme.of(context).textTheme.titleSmall)),
                        IconButton(
                            tooltip: 'Edit question',
                            onPressed: _busy ? null : () => _edit(q),
                            icon: const Icon(Icons.edit_outlined))
                      ]),
                      if (q['question_type'] == 'short' || _choices(q).isEmpty)
                        TextFormField(
                            key: ValueKey('answer-$_submission-${q['id']}'),
                            readOnly: _submitted || _busy,
                            initialValue: _answers[q['id']] ?? '',
                            decoration: const InputDecoration(
                                labelText: 'Your short answer'),
                            maxLines: 3,
                            onChanged: (text) =>
                                _change(q['id'] as String, text))
                      else
                        for (final option in _choices(q))
                          RadioListTile<String>(
                              title: Text(option),
                              value: option,
                              groupValue: _answers[q['id']],
                              onChanged: _busy || _submitted
                                  ? null
                                  : (value) =>
                                      _change(q['id'] as String, value ?? '')),
                    ]))),
          if (_questions.isNotEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: PrimaryButton(
                    label: 'Submit answers',
                    onPressed: _busy || _submitted ? null : _submit)),
          if (latest.isNotEmpty) ...[
            const SectionHeader(title: 'Latest results'),
            Text(objective.isEmpty
                ? 'Self-assessment only; no objective score.'
                : '${objective.where((a) => a['is_correct'] == 1).length}/${objective.length} objective answers correct'),
            for (final a in latest) _attemptCard(a),
          ],
          const SizedBox(height: 20),
          if (!_reveal)
            OutlinedButton(
                onPressed: _revealTranscript,
                child: const Text('Reveal transcript'))
          else
            LexiCard(
                child: SelectableText((_lesson!['transcript'] as String?)
                            ?.trim()
                            .isNotEmpty ==
                        true
                    ? _lesson!['transcript'] as String
                    : 'No transcript saved. Add one from the audio player.')),
          if ((_lesson!['transcript'] as String?)?.isNotEmpty == true)
            AiHelpButton(
                task: AiTask.comprehension,
                label: 'Ask AI about this lesson',
                content: () =>
                    'Transcript:\n${_lesson!['transcript']}\nQuestions:\n${_questions.map((q) => q['question']).join('\n')}'),
          if (_attempts.length > latest.length)
            ExpansionTile(title: const Text('Earlier attempts'), children: [
              for (final a in _attempts.skip(latest.length)) _attemptCard(a)
            ]),
        ]));
  }

  Widget _attemptCard(Map<String, dynamic> attempt) {
    Map<String, dynamic> q = {};
    try {
      q = jsonDecode(attempt['question_snapshot'] as String? ?? '{}')
          as Map<String, dynamic>;
    } catch (_) {}
    final self = attempt['self_assessed'] == 1;
    return ListTile(
        title: Text(q['question'] as String? ?? 'Saved question'),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your answer: ${attempt['learner_response']}'),
          if (!self)
            Text(attempt['is_correct'] == 1
                ? 'Correct'
                : 'Incorrect · Answer: ${q['correct_answer'] ?? 'Unavailable for this legacy attempt'}'),
          if (self) ...[
            Text(attempt['is_correct'] == null
                ? 'Not yet self-assessed'
                : 'Self-assessed: ${attempt['is_correct'] == 1 ? 'Met goal' : 'Needs practice'}'),
            Wrap(children: [
              for (final met in [false, true])
                TextButton(
                    onPressed: () async {
                      await _db.selfAssessComprehension(
                          attempt['id'] as String, met);
                      if (mounted) await _load();
                    },
                    child: Text(met ? 'Met goal' : 'Needs practice'))
            ])
          ],
        ]));
  }
}

class _QuestionEditor extends StatefulWidget {
  const _QuestionEditor(
      {required this.db, required this.lessonId, this.question});
  final AppDatabase db;
  final String lessonId;
  final Map<String, dynamic>? question;
  @override
  State<_QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<_QuestionEditor> {
  final _question = TextEditingController(),
      _choices = TextEditingController(),
      _correct = TextEditingController();
  String _type = 'mc';
  String? _error;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    final q = widget.question;
    if (q != null) {
      _question.text = q['question'] as String;
      _type = q['question_type'] as String;
      try {
        _choices.text =
            (jsonDecode(q['choices'] as String? ?? '[]') as List).join('\n');
      } catch (_) {}
      _correct.text = q['correct_answer'] as String? ?? '';
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.db.saveComprehensionQuestion(
          id: widget.question?['id'] as String?,
          lessonId: widget.lessonId,
          question: _question.text,
          type: _type,
          choices: _choices.text.split('\n'),
          correct: _correct.text.trim());
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is ArgumentError
            ? error.message.toString()
            : 'Could not save question.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _question.dispose();
    _choices.dispose();
    _correct.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Comprehension question'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Question type'),
                items: const [
                  DropdownMenuItem(value: 'mc', child: Text('Multiple choice')),
                  DropdownMenuItem(
                      value: 'true_false', child: Text('True / false')),
                  DropdownMenuItem(
                      value: 'main_idea', child: Text('Main idea')),
                  DropdownMenuItem(
                      value: 'details', child: Text('Specific details')),
                  DropdownMenuItem(
                      value: 'intention', child: Text('Speaker intention')),
                  DropdownMenuItem(
                      value: 'short',
                      child: Text('Short answer (self-assessed)'))
                ],
                onChanged: (v) => setState(() {
                      _type = v ?? 'mc';
                      if (_type == 'true_false') {
                        _choices.text = 'True\nFalse';
                        _correct.text = 'True';
                      }
                    })),
            TextField(
                controller: _question,
                decoration: const InputDecoration(labelText: 'Question'),
                maxLines: 3),
            if (_type != 'short') ...[
              TextField(
                  controller: _choices,
                  decoration: const InputDecoration(
                      labelText: 'Choices (one per line)'),
                  minLines: 2,
                  maxLines: 6),
              TextField(
                  controller: _correct,
                  decoration: const InputDecoration(
                      labelText: 'Correct answer (exact choice text)'))
            ],
            if (_type == 'short')
              const Text(
                  'Short answers are self-assessed. No automatic score will be invented.'),
            if (_error != null) Text(_error!),
          ])),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Save question'))
          ]);
}
