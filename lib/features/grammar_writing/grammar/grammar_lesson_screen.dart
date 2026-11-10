import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/services/providers.dart';
import '../../../core/utils/id_utils.dart';
import '../../../core/widgets/common_widgets.dart';

class GrammarLessonScreen extends ConsumerStatefulWidget {
  final String lessonId;
  const GrammarLessonScreen({super.key, required this.lessonId});

  @override
  ConsumerState<GrammarLessonScreen> createState() =>
      _GrammarLessonScreenState();
}

class _GrammarLessonScreenState extends ConsumerState<GrammarLessonScreen> {
  Map<String, dynamic>? _lesson;
  List<Map<String, dynamic>> _exercises = [];
  bool _loading = true;
  int _exIndex = 0;
  final _answerCtrl = TextEditingController();
  String? _selectedChoice;
  bool _submitted = false;
  bool? _correct;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    final lesson = await db.getGrammarLesson(widget.lessonId);
    final exercises = await db.getGrammarExercises(widget.lessonId);
    if (mounted) {
      setState(() {
        _lesson = lesson;
        _exercises = exercises;
        _loading = false;
      });
    }
  }

  List<String> _choices(Map<String, dynamic> ex) {
    final raw = ex['choices'] as String?;
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => '$e').toList();
    } catch (_) {
      return [];
    }
  }

  List<String> _alternatives(Map<String, dynamic> ex) {
    final raw = ex['alternatives'] as String?;
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => '$e').toList();
    } catch (_) {
      return [];
    }
  }

  bool _matches(String learner, Map<String, dynamic> ex) {
    final correct =
        (ex['correct_answer'] as String?)?.trim().toLowerCase() ?? '';
    final a = learner.trim().toLowerCase();
    if (a == correct) return true;
    for (final alt in _alternatives(ex)) {
      if (a == alt.trim().toLowerCase()) return true;
    }
    return false;
  }

  Future<void> _submit() async {
    if (_exercises.isEmpty) return;
    final ex = _exercises[_exIndex];
    final type = ex['question_type'] as String;
    final response = type == 'mc' ? (_selectedChoice ?? '') : _answerCtrl.text;
    if (response.trim().isEmpty) return;
    final isCorrect = _matches(response, ex);
    setState(() {
      _submitted = true;
      _correct = isCorrect;
    });
    await ref.read(appDatabaseProvider).saveGrammarAttempt({
      'id': newId(),
      'exercise_id': ex['id'],
      'lesson_id': widget.lessonId,
      'learner_response': response,
      'is_correct': isCorrect ? 1 : 0,
      'self_assessed': 0,
    });
  }

  void _next() {
    if (_exIndex >= _exercises.length - 1) {
      ref.read(appDatabaseProvider).markGrammarLessonComplete(widget.lessonId);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lesson marked complete')));
      return;
    }
    setState(() {
      _exIndex++;
      _submitted = false;
      _correct = null;
      _selectedChoice = null;
      _answerCtrl.clear();
    });
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    if (_lesson == null) {
      return Scaffold(
          appBar: AppBar(), body: const ErrorView(message: 'Lesson not found'));
    }
    final l = _lesson!;
    final hasEx = _exercises.isNotEmpty;
    final ex = hasEx ? _exercises[_exIndex] : null;

    return Scaffold(
      appBar: AppBar(title: Text('${l['title']}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('${l['cefr_level']}',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: AppColors.violet)),
          const SizedBox(height: 8),
          Text('${l['objective']}',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          SectionHeader(title: 'Explanation'),
          Text('${l['explanation']}',
              style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          SectionHeader(title: 'Examples'),
          LexiCard(child: Text('${l['examples']}')),
          const SizedBox(height: 16),
          SectionHeader(title: 'Common mistakes'),
          LexiCard(child: Text('${l['common_mistakes']}')),
          if (hasEx) ...[
            const SizedBox(height: 24),
            SectionHeader(
                title: 'Practice ${_exIndex + 1} / ${_exercises.length}'),
            LexiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${ex!['prompt']}',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  if (ex['question_type'] == 'mc')
                    ..._choices(ex).map((c) => RadioListTile<String>(
                          title: Text(c),
                          value: c,
                          groupValue: _selectedChoice,
                          onChanged: _submitted
                              ? null
                              : (v) => setState(() => _selectedChoice = v),
                        ))
                  else
                    TextField(
                      controller: _answerCtrl,
                      enabled: !_submitted,
                      decoration:
                          const InputDecoration(hintText: 'Your answer'),
                    ),
                  if (_submitted) ...[
                    const SizedBox(height: 12),
                    Text(
                      _correct == true ? 'Correct' : 'Not quite',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _correct == true
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Answer: ${ex['correct_answer']}'),
                    const SizedBox(height: 4),
                    Text('${ex['explanation']}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (!_submitted)
              PrimaryButton(label: 'Check answer', onPressed: _submit)
            else
              PrimaryButton(
                label: _exIndex >= _exercises.length - 1
                    ? 'Finish lesson'
                    : 'Next exercise',
                onPressed: _next,
              ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
