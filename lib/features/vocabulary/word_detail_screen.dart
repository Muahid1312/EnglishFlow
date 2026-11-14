import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/services/providers.dart';
import '../../core/services/pronunciation_service.dart';
import '../../core/widgets/common_widgets.dart';
import '../dashboard/dashboard_provider.dart';
import 'word_editor.dart';
import 'vocabulary_screen.dart';

class WordDetailScreen extends ConsumerStatefulWidget {
  const WordDetailScreen({super.key, required this.entryId});
  final String entryId;
  @override
  ConsumerState<WordDetailScreen> createState() => _WordDetailScreenState();
}

class _WordDetailScreenState extends ConsumerState<WordDetailScreen> {
  final _speech = PronunciationService();
  Map<String, dynamic>? _word;
  List<Map<String, dynamic>> _history = [];
  String? _error, _speechStatus;
  bool _loading = true, _speaking = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = await ref.read(appDatabaseProvider).db;
      final rows = db.select(
          '''SELECT e.*,(SELECT MIN(julianday(next_review_at)) FROM vocabulary_reviews WHERE entry_id=e.id) due_julian,
        (SELECT next_review_at FROM vocabulary_reviews WHERE entry_id=e.id ORDER BY julianday(next_review_at),id LIMIT 1) next_review_at,
        (SELECT MAX(review_count) FROM vocabulary_reviews WHERE entry_id=e.id) review_count
        FROM vocabulary_entries e WHERE e.id=? AND e.is_saved=1 AND e.duplicate_of IS NULL''',
          [widget.entryId]);
      final history = db.select(
          'SELECT * FROM vocabulary_review_history WHERE entry_id=? ORDER BY reviewed_at DESC,review_number DESC LIMIT 50',
          [widget.entryId]);
      if (mounted) {
        setState(() {
          _word = rows.isEmpty ? null : rows.single;
          _history = history;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load this word.';
        });
      }
    }
  }

  Future<void> _speak() async {
    setState(() => _speaking = true);
    try {
      final result = await _speech.speak(_word!['word'] as String);
      if (mounted) {
        setState(() => _speechStatus = result['stopped'] == true
            ? 'Playback stopped.'
            : 'Played ${result['locale']}. ${result['offlineVoice'] == true ? 'The engine reports an installed offline voice; availability depends on its voice data.' : 'This voice may require network access.'}');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _speechStatus =
            'Pronunciation unavailable. Check Android text-to-speech settings and install an English voice.');
      }
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  Future<void> _delete() async {
    final database = ref.read(appDatabaseProvider);
    final confirmed = await showConfirmDialog(context,
        title: 'Delete saved word?',
        message:
            'Remove it from saved words and due reviews? Existing review history will be retained.');
    if (confirmed != true || !mounted) return;
    try {
      (await database.db).execute(
          'UPDATE vocabulary_entries SET is_saved=0 WHERE id=?',
          [widget.entryId]);
      if (!mounted) return;
      ref.invalidate(dashboardProvider);
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not remove this word. Your records have been kept.');
      }
    }
  }

  @override
  void dispose() {
    unawaited(_speech.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = _word;
    final next = word?['next_review_at'] as String?;
    final due = next != null && !DateTime.parse(next).isAfter(DateTime.now());
    return Scaffold(
        appBar: AppBar(title: const Text('Word details')),
        body: _loading
            ? const LoadingView()
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : word == null
                    ? const EmptyState(
                        icon: Icons.style_outlined,
                        title: 'Word not available',
                        message:
                            'It may have been removed from your saved words.')
                    : ListView(padding: const EdgeInsets.all(20), children: [
                        Text(word['word'] as String,
                            style: Theme.of(context).textTheme.headlineLarge),
                        Wrap(spacing: 8, children: [
                          FilledButton.icon(
                              onPressed:
                                  _speaking ? () => _speech.stop() : _speak,
                              icon: Icon(
                                  _speaking ? Icons.stop : Icons.volume_up),
                              label: Text(_speaking
                                  ? 'Stop pronunciation'
                                  : 'Pronounce')),
                          TextButton(
                              onPressed: () async {
                                await showDialog<bool>(
                                    context: context,
                                    builder: (_) => WordEditorDialog(
                                        db: ref.read(appDatabaseProvider),
                                        entry: word));
                                if (mounted) await _load();
                              },
                              child: const Text('Edit')),
                          TextButton(
                              onPressed: _delete, child: const Text('Delete')),
                        ]),
                        if (_speechStatus != null)
                          Semantics(
                              liveRegion: true, child: Text(_speechStatus!)),
                        const SizedBox(height: 16),
                        for (final item in const {
                          'definition': 'English meaning',
                          'translation': 'Dari/Persian translation',
                          'usage_example': 'Example',
                          'collocations': 'Collocations',
                          'part_of_speech': 'Part of speech',
                          'pronunciation': 'Pronunciation notes',
                          'personal_notes': 'Personal notes'
                        }.entries)
                          if ((word[item.key] as String?)?.isNotEmpty == true)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: LexiCard(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(item.value,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall),
                                      Text(word[item.key] as String,
                                          textDirection:
                                              item.key == 'translation'
                                                  ? TextDirection.rtl
                                                  : null),
                                    ]))),
                        const SectionHeader(title: 'Original context'),
                        if ((jsonDecode(word['contexts_json'] as String)
                                as List)
                            .isEmpty)
                          const Text(
                              'No source context recorded. Add a sentence with Edit or save a word from Reading Studio.'),
                        for (final c
                            in jsonDecode(word['contexts_json'] as String)
                                as List)
                          ListTile(
                              title: Text(c['sentence'] as String),
                              subtitle: Text(
                                  c['source'] as String? ?? 'Saved context'),
                              trailing: c['article_id'] != null ||
                                      c['book_id'] != null
                                  ? const Icon(Icons.open_in_new)
                                  : null,
                              onTap: c['article_id'] != null
                                  ? () => context.push(
                                      '/learn/reading/${Uri.encodeComponent(c['article_id'] as String)}')
                                  : c['book_id'] != null
                                      ? () => context.push(
                                          '/learn/books/${Uri.encodeComponent(c['book_id'] as String)}/read')
                                      : null),
                        const SizedBox(height: 16),
                        Text(
                            'Status: ${due ? 'Due' : (word['review_count'] as int? ?? 0) > 0 ? 'Scheduled' : 'New'} · ${word['review_count'] ?? 0} reviews'),
                        Text(next == null
                            ? 'No review schedule'
                            : 'Next review: ${DateFormat.yMMMd().add_jm().format(DateTime.parse(next).toLocal())}'),
                        FilledButton(
                            onPressed: due
                                ? () async {
                                    await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                            builder: (_) =>
                                                FlashcardReviewScreen(
                                                    db: ref.read(
                                                        appDatabaseProvider),
                                                    entryId: widget.entryId)));
                                    if (mounted) await _load();
                                  }
                                : null,
                            child: const Text('Start review')),
                        const SizedBox(height: 16),
                        const SectionHeader(title: 'Review history'),
                        if (_history.isEmpty) const Text('No reviews yet.'),
                        for (final h in _history)
                          ListTile(
                              title: Text(h['rating'] as String),
                              subtitle: Text(
                                  '${h['reviewed_at']} · next ${h['next_due']}')),
                        if (_history.length >= 50)
                          const Text(
                              'Showing the latest 50 reviews. Complete history is retained in the database and backups.'),
                      ]));
  }
}
