import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/providers.dart';
import '../../core/utils/id_utils.dart';
import 'course_screens.dart' show courseFields;

class CourseAssessmentEditor extends ConsumerStatefulWidget {
  const CourseAssessmentEditor(
      {super.key, required this.courseId, required this.units});
  final String courseId;
  final List<Map<String, dynamic>> units;
  @override
  ConsumerState<CourseAssessmentEditor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<CourseAssessmentEditor> {
  final _title = TextEditingController();
  final _threshold = TextEditingController(text: '0.7');
  final List<Map<String, dynamic>> _questions = [];
  String? _unit, _error;
  bool _busy = false;
  @override
  void dispose() {
    _title.dispose();
    _threshold.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final kind = await showDialog<String>(
        context: context,
        builder: (context) =>
            SimpleDialog(title: const Text('Question type'), children: [
              for (final k in [
                'mc',
                'true_false',
                'recall',
                'grammar',
                'reading',
                'short'
              ])
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, k),
                    child: Text(
                        k == 'short' ? 'Short writing (self-assessment)' : k))
            ]));
    if (kind == null || !mounted) return;
    final v = await courseFields(context, 'Author question', {
      'Prompt': '',
      if (kind == 'mc') 'Choices separated by |': '',
      if (kind != 'short') 'Answer key': kind == 'true_false' ? 'true' : '',
      'Explanation / self-assessment rubric': ''
    });
    if (v == null) return;
    final choices = kind == 'mc'
        ? v[1]
            .split('|')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : kind == 'true_false'
            ? ['true', 'false']
            : <String>[];
    final answer = kind == 'short' ? null : v[kind == 'mc' ? 2 : 1].trim();
    if (v[0].trim().isEmpty ||
        (kind != 'short' &&
            (answer!.isEmpty ||
                (choices.isNotEmpty && !choices.contains(answer)))) ||
        (kind == 'mc' &&
            (choices.length < 2 || choices.toSet().length != choices.length))) {
      if (mounted) {
        setState(() => _error =
            'Enter a prompt, valid choices and a matching answer key.');
      }
      return;
    }
    if (mounted) {
      setState(() => _questions.add({
            'id': newId(),
            'question_type': kind,
            'prompt': v[0],
            'choices': choices.isEmpty ? null : jsonEncode(choices),
            'correct_answer': answer,
            'explanation': v.last
          }));
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final threshold = double.tryParse(_threshold.text);
      if (_title.text.trim().isEmpty ||
          _questions.isEmpty ||
          threshold == null ||
          !threshold.isFinite ||
          threshold < 0 ||
          threshold > 1) {
        throw ArgumentError(
            'Enter title, questions and a threshold between 0 and 1.');
      }
      final d = await ref.read(appDatabaseProvider).db;
      final id = newId();
      d.execute('BEGIN IMMEDIATE');
      try {
        d.execute(
            'INSERT INTO assessment_definitions(id,title,category,description,pass_threshold,course_id,unit_id) VALUES(?,?,?,?,?,?,?)',
            [
              id,
              _title.text.trim(),
              'course',
              'Learner-authored practice assessment. Not accredited.',
              threshold,
              widget.courseId,
              _unit
            ]);
        for (var i = 0; i < _questions.length; i++) {
          final q = _questions[i];
          d.execute(
              'INSERT INTO assessment_questions(id,assessment_id,question_type,prompt,choices,correct_answer,explanation,order_index) VALUES(?,?,?,?,?,?,?,?)',
              [
                q['id'],
                id,
                q['question_type'],
                q['prompt'],
                q['choices'],
                q['correct_answer'],
                q['explanation'],
                i
              ]);
        }
        d.execute('COMMIT');
      } catch (_) {
        d.execute('ROLLBACK');
        rethrow;
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Author assessment')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Assessment title')),
        TextField(
            controller: _threshold,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                const InputDecoration(labelText: 'Pass threshold (0–1)')),
        DropdownButton<String>(
            isExpanded: true,
            hint: const Text('Whole course (optional unit)'),
            value: _unit,
            items: [
              for (final u in widget.units)
                DropdownMenuItem(
                    value: u['id'] as String, child: Text('${u['title']}'))
            ],
            onChanged: (v) => setState(() => _unit = v)),
        const Text(
            'Stored keys grade objective questions. Writing responses require self-assessment and never contribute to the objective score. All questions are required. At least one objective question is needed for certification.'),
        for (var i = 0; i < _questions.length; i++)
          ListTile(
              title: Text('${_questions[i]['prompt']}'),
              subtitle: Text('${_questions[i]['question_type']}'),
              trailing: IconButton(
                  tooltip: 'Remove question',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _questions.removeAt(i)))),
        TextButton(
            onPressed: _busy ? null : _add, child: const Text('Add question')),
        if (_error != null) Text(_error!),
        FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save assessment')),
      ]));
}
