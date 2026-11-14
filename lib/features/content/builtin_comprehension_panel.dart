import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/providers.dart';
import '../../core/services/builtin_content_service.dart';
import '../../core/utils/id_utils.dart';

class BuiltinComprehensionPanel extends ConsumerStatefulWidget {
  const BuiltinComprehensionPanel({super.key, required this.article});
  final Map<String, dynamic> article;
  @override
  ConsumerState<BuiltinComprehensionPanel> createState() => _PanelState();
}

class _PanelState extends ConsumerState<BuiltinComprehensionPanel> {
  final Map<String, String> _answers = {};
  String _token = newId();
  String _started = DateTime.now().toUtc().toIso8601String();
  bool _read = false, _busy = false;
  String? _error;
  Map<String, dynamic>? _result;
  List<Map<String, dynamic>> _history = [];
  BuiltinContentService get service =>
      BuiltinContentService(ref.read(appDatabaseProvider));
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final history = await service.history(widget.article['id'] as String);
      if (mounted) setState(() => _history = history);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load reading history.');
    }
  }

  Future<void> _submit() async {
    if (_busy || _result != null) return;
    setState(() => _busy = true);
    try {
      final result = await service.submit(
          id: widget.article['id'] as String,
          token: _token,
          startedAt: _started,
          answers: _answers,
          readConfirmed: _read);
      if (mounted) {
        setState(() {
          _result = result;
          _error = null;
        });
        await _load();
      }
    } catch (error) {
      if (mounted)
        setState(() => _error = error is StateError
            ? '${error.message}'
            : 'Could not save answers. Your selections are retained.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(Map<String, dynamic> attempt) async {
    final questions = jsonDecode(attempt['questions_json'] as String) as List;
    final answers = jsonDecode(attempt['answers_json'] as String) as Map;
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(
                    'Saved result: ${attempt['correct']}/${attempt['total']}'),
                content: SizedBox(
                    width: 480,
                    child: SingleChildScrollView(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(
                              'Submitted ${attempt['completed_at']} · content ${attempt['content_version']}'),
                          for (final q in questions) ...[
                            const SizedBox(height: 16),
                            Text(q['prompt'] as String),
                            Text('Your answer: ${answers[q['id']]}'),
                            Text(
                                'Correct: ${(q['choices'] as List)[q['answer'] as int]}'),
                            Text(q['explanation'] as String)
                          ],
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'))
                ]));
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.article['questions'] as List;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Divider(),
      Text('Important vocabulary',
          style: Theme.of(context).textTheme.titleLarge),
      FutureBuilder<BuiltinCatalog>(
          future: BuiltinCatalog.load(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            return Column(children: [
              for (final id in widget.article['vocabulary'] as List)
                ListTile(
                    title: Text(
                        snapshot.data!.word(id as String)['word'] as String),
                    subtitle:
                        Text(snapshot.data!.word(id)['definition'] as String),
                    trailing: IconButton(
                        tooltip: 'Save to personal vocabulary',
                        icon: const Icon(Icons.bookmark_add_outlined),
                        onPressed: () async {
                          try {
                            await service.saveWord(id);
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Saved to personal vocabulary.')));
                          } catch (_) {
                            if (mounted)
                              setState(() => _error = 'Could not save word.');
                          }
                        }))
            ]);
          }),
      Text('Comprehension', style: Theme.of(context).textTheme.titleLarge),
      const Text(
          'Opening this article does not complete it. Confirm you have read it and submit all four answers. Scores measure these questions, not your CEFR level.'),
      if (_result == null) ...[
        for (final q in questions)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(q['prompt'] as String),
                        for (final choice in q['choices'] as List)
                          RadioListTile<String>(
                              title: Text(choice as String),
                              value: choice,
                              groupValue: _answers[q['id']],
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(
                                      () => _answers[q['id'] as String] = v!))
                      ]))),
        CheckboxListTile(
            title: const Text('I finished reading this article'),
            value: _read,
            onChanged: _busy ? null : (v) => setState(() => _read = v == true)),
        FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? 'Saving…' : 'Submit answers')),
      ] else ...[
        Text(
            'Saved result: ${_result!['correct']}/${_result!['total']} correct. Reading and question submission completed.'),
        TextButton(
            onPressed: () => _review(_result!),
            child: const Text('Review answers and explanations')),
        TextButton(
            onPressed: () => setState(() {
                  _answers.clear();
                  _token = newId();
                  _started = DateTime.now().toUtc().toIso8601String();
                  _read = false;
                  _result = null;
                }),
            child: const Text('Try a new attempt')),
      ],
      if (_error != null) Text(_error!),
      for (final attempt in _history)
        TextButton(
            onPressed: () => _review(attempt),
            child: Text(
                '${attempt['completed_at']} · ${attempt['correct']}/${attempt['total']} · review saved answers')),
      if ((widget.article['references'] as List? ?? []).isNotEmpty) ...[
        const Divider(),
        const Text(
            'Background reading (online references; the article works offline):'),
        for (final ref in widget.article['references'] as List)
          SelectableText('${ref['title']}\n${ref['url']}'),
      ],
    ]);
  }
}
