import '../../core/widgets/ai_help_button.dart';
import '../../core/services/ai_teacher_service.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/database/app_database.dart';
import '../../core/services/providers.dart';
import '../../core/services/review_schedule.dart';
import '../../core/utils/id_utils.dart';
import '../../core/widgets/common_widgets.dart';
import '../dashboard/dashboard_provider.dart';

class VocabularyScreen extends ConsumerStatefulWidget {
  const VocabularyScreen({super.key});
  @override
  ConsumerState<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends ConsumerState<VocabularyScreen> {
  List<Map<String, dynamic>> _words = [];
  int _due = 0;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final words = await db.getVocabulary();
      final due = await db.getDueReviewCount();
      if (mounted) {
        setState(() {
          _words = words;
          _due = due;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load vocabulary.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit([Map<String, dynamic>? entry]) async {
    final db = ref.read(appDatabaseProvider);
    await showDialog<bool>(
        context: context, builder: (_) => _WordEditor(db: db, entry: entry));
    if (!mounted) return;
    ref.invalidate(dashboardProvider);
    await _load();
  }

  Future<void> _review() async {
    final db = ref.read(appDatabaseProvider);
    await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => FlashcardReviewScreen(db: db)));
    if (!mounted) return;
    ref.invalidate(dashboardProvider);
    await _load();
  }

  Future<void> _history(Map<String, dynamic> word) async {
    final rows = await ref
        .read(appDatabaseProvider)
        .getReviewHistory(word['id'] as String);
    if (!mounted) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.65,
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Text('Review history: ${word['word']}',
                      style: Theme.of(context).textTheme.titleLarge),
                  if (rows.isEmpty) const Text('No reviews yet.'),
                  for (final r in rows)
                    ListTile(
                        title: Text('${r['rating']} · ${r['reviewed_at']}'),
                        subtitle: Text('Next review: ${r['next_due']}')),
                ]))));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Vocabulary'), actions: [
          IconButton(
              tooltip: 'Add word',
              onPressed: () => _edit(),
              icon: const Icon(Icons.add))
        ]),
        body: _loading
            ? const LoadingView()
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Row(children: [
                    Expanded(
                        child: LexiCard(
                            child: Column(children: [
                      Text('${_words.length}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: AppColors.violet)),
                      const Text('Saved words')
                    ]))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: LexiCard(
                            child: Column(children: [
                      Text('$_due',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: AppColors.teal)),
                      const Text('Due reviews')
                    ])))
                  ]),
                  const SizedBox(height: 20),
                  if (_error != null) ErrorView(message: _error!),
                  if (_due > 0)
                    PrimaryButton(
                        label: 'Start review',
                        icon: Icons.replay,
                        onPressed: _review),
                  if (_words.isEmpty)
                    const EmptyState(
                        icon: Icons.style_outlined,
                        title: 'No saved words',
                        message:
                            'Add a word or save a selection while reading. Meanings and translations are entered by you; they are not invented offline.'),
                  for (final word in _words)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: LexiCard(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Expanded(
                                    child: Text(word['word'] as String,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium)),
                                IconButton(
                                    tooltip: 'Review history',
                                    onPressed: () => _history(word),
                                    icon: const Icon(Icons.history)),
                                IconButton(
                                    tooltip: 'Edit word',
                                    onPressed: () => _edit(word),
                                    icon: const Icon(Icons.edit_outlined))
                              ]),
                              AiHelpButton(
                                  task: AiTask.vocabulary,
                                  label: 'Explain with AI',
                                  content: () =>
                                      '${word['word']}\n${word['contexts_json']}'),
                              if ((word['definition'] as String?)?.isNotEmpty ==
                                  true)
                                Text(word['definition'] as String),
                              if ((word['translation'] as String?)
                                      ?.isNotEmpty ==
                                  true)
                                Text(word['translation'] as String),
                              for (final item
                                  in jsonDecode(word['contexts_json'] as String)
                                      as List)
                                Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                        '“${item['sentence']}”\n${item['source'] ?? 'Source'}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall)),
                            ]))),
                ])),
      );
}

class _WordEditor extends StatefulWidget {
  const _WordEditor({required this.db, this.entry});
  final AppDatabase db;
  final Map<String, dynamic>? entry;
  @override
  State<_WordEditor> createState() => _WordEditorState();
}

class _WordEditorState extends State<_WordEditor> {
  final _word = TextEditingController();
  final _definition = TextEditingController();
  final _translation = TextEditingController();
  final _sentence = TextEditingController();
  String? _error;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _word.text = widget.entry?['word'] as String? ?? '';
    _definition.text = widget.entry?['definition'] as String? ?? '';
    _translation.text = widget.entry?['translation'] as String? ?? '';
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.db.saveVocabulary(
          id: widget.entry?['id'] as String?,
          word: _word.text,
          definition: _definition.text.trim(),
          translation: _translation.text.trim(),
          sentence: _sentence.text,
          source: 'Manual');
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError
            ? error.message.toString()
            : error is ArgumentError
                ? error.message.toString()
                : 'Could not save this word.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _word.dispose();
    _definition.dispose();
    _translation.dispose();
    _sentence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.entry == null ? 'Add word' : 'Edit word'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _word,
                decoration: const InputDecoration(labelText: 'Word'),
                maxLength: 100),
            TextField(
                controller: _definition,
                decoration:
                    const InputDecoration(labelText: 'Definition (optional)')),
            TextField(
                controller: _translation,
                decoration:
                    const InputDecoration(labelText: 'Translation (optional)')),
            TextField(
                controller: _sentence,
                decoration: const InputDecoration(
                    labelText: 'Add context sentence (optional)'),
                maxLines: 3),
            if (widget.entry != null)
              const Text('Original source sentences are preserved.'),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ])),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save'))
          ]);
}

class FlashcardReviewScreen extends StatefulWidget {
  const FlashcardReviewScreen({super.key, required this.db});
  final AppDatabase db;
  @override
  State<FlashcardReviewScreen> createState() => _FlashcardReviewScreenState();
}

class _FlashcardReviewScreenState extends State<FlashcardReviewScreen> {
  List<Map<String, dynamic>>? _queue;
  int _index = 0;
  bool _revealed = false;
  bool _saving = false;
  String? _error;
  String _reviewId = newId();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await widget.db.getDueVocabulary();
      if (mounted) setState(() => _queue = rows);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load review cards.');
    }
  }

  Future<void> _rate(ReviewRating rating) async {
    if (_saving || !_revealed || _queue == null || _index >= _queue!.length) {
      return;
    }
    setState(() => _saving = true);
    final card = _queue![_index];
    try {
      await widget.db.reviewVocabulary(
          entryId: card['id'] as String,
          reviewId: _reviewId,
          rating: rating,
          expectedReviewCount: card['review_count'] as int);
      if (mounted) {
        setState(() {
          _index++;
          _revealed = false;
          _reviewId = newId();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError
            ? error.message.toString()
            : 'Could not save review. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card =
        _queue != null && _index < _queue!.length ? _queue![_index] : null;
    return Scaffold(
        appBar: AppBar(title: const Text('Flashcards')),
        body: Padding(
            padding: const EdgeInsets.all(20),
            child: _queue == null
                ? (_error == null
                    ? const LoadingView()
                    : ErrorView(message: _error!))
                : card == null
                    ? const EmptyState(
                        icon: Icons.check_circle_outline,
                        title: 'Reviews saved',
                        message:
                            'Your review history and next review dates are stored offline.')
                    : ListView(children: [
                        Text('Card ${_index + 1} of ${_queue!.length}'),
                        const SizedBox(height: 24),
                        LexiCard(
                            child: Column(children: [
                          Text(card['word'] as String,
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          if (_revealed) ...[
                            const SizedBox(height: 20),
                            Text((card['definition'] as String?)?.isNotEmpty ==
                                    true
                                ? card['definition'] as String
                                : 'No definition added.'),
                            if ((card['translation'] as String?)?.isNotEmpty ==
                                true)
                              Text(card['translation'] as String),
                            for (final c
                                in jsonDecode(card['contexts_json'] as String)
                                    as List)
                              Text('“${c['sentence']}”')
                          ]
                        ])),
                        const SizedBox(height: 20),
                        if (!_revealed)
                          PrimaryButton(
                              label: 'Show answer',
                              onPressed: () => setState(() => _revealed = true))
                        else
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final rating in ReviewRating.values)
                              OutlinedButton(
                                  onPressed:
                                      _saving ? null : () => _rate(rating),
                                  child: Text(switch (rating) {
                                    ReviewRating.again => 'Again',
                                    ReviewRating.hard => 'Hard',
                                    ReviewRating.good => 'Good',
                                    ReviewRating.easy => 'Easy'
                                  }))
                          ]),
                        if (_error != null) Text(_error!),
                      ])));
  }
}
