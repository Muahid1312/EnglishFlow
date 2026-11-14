import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/builtin_content_service.dart';
import '../../core/services/providers.dart';
import '../../core/services/review_schedule.dart' show normalizeWord;
import '../../core/widgets/common_widgets.dart';

class BuiltinLibraryScreen extends ConsumerStatefulWidget {
  const BuiltinLibraryScreen(
      {super.key, this.vocabulary = false, this.daily = false});
  final bool vocabulary, daily;
  @override
  ConsumerState<BuiltinLibraryScreen> createState() => _LibraryState();
}

class _LibraryState extends ConsumerState<BuiltinLibraryScreen> {
  BuiltinCatalog? _catalog;
  String _level = 'All', _topic = 'All', _query = '';
  bool _bookmarks = false;
  String? _error;
  Set<String> _savedWords = {};
  Map<String, Map<String, dynamic>> _states = {};
  List<Map<String, dynamic>> _daily = [];
  final Set<String> _saving = {};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final database = ref.read(appDatabaseProvider);
      final service = BuiltinContentService(database);
      final catalog = await BuiltinCatalog.load();
      final states = await service.states();
      final personal = (await database.db)
          .select('SELECT word FROM vocabulary_entries WHERE is_saved=1')
          .map((r) => normalizeWord(r['word'] as String))
          .toSet();
      final prefs = await database.getPreferences();
      final daily = widget.daily
          ? await service.recommendedWords(level: prefs.englishLevel, count: 10)
          : <Map<String, dynamic>>[];
      if (mounted)
        setState(() {
          _catalog = catalog;
          _states = {for (final s in states) s['article_id'] as String: s};
          _savedWords = personal;
          _daily = daily;
          _error = null;
        });
    } catch (_) {
      if (mounted)
        setState(
            () => _error = 'Could not load the offline library. Please retry.');
    }
  }

  Future<void> _save(Map<String, dynamic> word) async {
    final id = word['id'] as String;
    if (_saving.contains(id)) return;
    setState(() => _saving.add(id));
    try {
      await BuiltinContentService(ref.read(appDatabaseProvider)).saveWord(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Word saved to personal vocabulary.')));
        await _load();
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not save this word. Your existing cards were retained.')));
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.vocabulary
        ? (_daily.isNotEmpty || widget.daily ? _daily : _catalog?.words ?? [])
        : _catalog?.articles ?? <Map<String, dynamic>>[];
    final topics = [
      'All',
      ...(all.map((r) => r['category'] as String).toSet().toList()..sort())
    ];
    final filtered = all
        .where((r) =>
            (_level == 'All' || r['level'] == _level) &&
            (_topic == 'All' || r['category'] == _topic) &&
            ('${r['title'] ?? r['word']}'
                .toLowerCase()
                .contains(_query.toLowerCase())) &&
            (!_bookmarks || _states[r['id']]?['bookmarked'] == 1))
        .toList();
    return Scaffold(
        appBar: AppBar(
            title: Text(widget.daily
                ? 'Today’s vocabulary'
                : widget.vocabulary
                    ? 'Built-in vocabulary'
                    : 'Built-in reading')),
        body: _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : _catalog == null
                ? const LoadingView()
                : CustomScrollView(slivers: [
                    SliverToBoxAdapter(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(children: [
                              const Text(
                                  'Offline original content · B1/B2 curriculum targets, not official word-level CEFR classifications.'),
                              TextField(
                                  decoration: InputDecoration(
                                      labelText: widget.vocabulary
                                          ? 'Search built-in words'
                                          : 'Search article titles',
                                      prefixIcon: const Icon(Icons.search)),
                                  onChanged: (v) => setState(() => _query = v)),
                              Wrap(spacing: 8, children: [
                                for (final l in ['All', 'B1', 'B2'])
                                  ChoiceChip(
                                      label: Text(l),
                                      selected: _level == l,
                                      onSelected: (_) =>
                                          setState(() => _level = l))
                              ]),
                              DropdownButton<String>(
                                  isExpanded: true,
                                  value:
                                      topics.contains(_topic) ? _topic : 'All',
                                  items: [
                                    for (final t in topics)
                                      DropdownMenuItem(value: t, child: Text(t))
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _topic = v!)),
                              if (!widget.vocabulary)
                                FilterChip(
                                    label: const Text('Bookmarked'),
                                    selected: _bookmarks,
                                    onSelected: (v) =>
                                        setState(() => _bookmarks = v)),
                              Text(
                                  '${filtered.length} ${widget.vocabulary ? 'words' : 'articles'}'),
                            ]))),
                    if (filtered.isEmpty)
                      SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                              child: Text(widget.daily && _daily.isEmpty
                                  ? 'All words at your selected level are already saved. Review your due cards.'
                                  : 'No matching content.')))
                    else
                      SliverList(
                          delegate: SliverChildBuilderDelegate((context, i) {
                        final item = filtered[i];
                        final saved = _savedWords.contains(
                            normalizeWord(item['word'] as String? ?? ''));
                        if (widget.vocabulary)
                          return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            '${item['word']} · ${item['part_of_speech']} · ${item['level']}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium),
                                        Text(item['definition'] as String),
                                        Text(item['translation'] as String,
                                            textDirection: TextDirection.rtl),
                                        Text(item['example'] as String),
                                        Text(
                                            'Collocation: ${item['collocation']}'),
                                        TextButton.icon(
                                            onPressed:
                                                _saving.contains(item['id']) ||
                                                        saved
                                                    ? null
                                                    : () => _save(item),
                                            icon: Icon(saved
                                                ? Icons.check
                                                : Icons.bookmark_add_outlined),
                                            label: Text(saved
                                                ? 'In personal vocabulary'
                                                : 'Save to personal vocabulary')),
                                      ])));
                        final state = _states[item['id']];
                        return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 6),
                            title: Text(item['title'] as String),
                            subtitle: Text(
                                '${item['level']} · ${item['category']} · ${item['reading_minutes']} min · ${state?['completed_at'] != null ? 'Read + questions submitted' : state?['last_opened_at'] != null ? 'Continue reading' : 'Unread'}'),
                            trailing: IconButton(
                                tooltip: state?['bookmarked'] == 1
                                    ? 'Remove bookmark'
                                    : 'Bookmark article',
                                icon: Icon(state?['bookmarked'] == 1
                                    ? Icons.bookmark
                                    : Icons.bookmark_border),
                                onPressed: () async {
                                  try {
                                    await BuiltinContentService(
                                            ref.read(appDatabaseProvider))
                                        .bookmark(item['id'] as String,
                                            state?['bookmarked'] != 1);
                                    await _load();
                                  } catch (_) {
                                    if (mounted)
                                      setState(() => _error =
                                          'Could not save bookmark. Please retry.');
                                  }
                                }),
                            onTap: () async {
                              await context.push(
                                  '/learn/reading/${Uri.encodeComponent('builtin:${item['id']}')}');
                              if (mounted) await _load();
                            });
                      }, childCount: filtered.length)),
                  ]));
  }
}
