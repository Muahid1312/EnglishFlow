import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/services/article_import_service.dart';
import '../../core/services/providers.dart';
import '../../core/utils/id_utils.dart';
import '../../core/utils/date_utils.dart';
import '../../core/widgets/common_widgets.dart';
import '../dashboard/dashboard_provider.dart';

class ReadingScreen extends ConsumerStatefulWidget {
  const ReadingScreen({super.key});
  @override
  ConsumerState<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<ReadingScreen> {
  List<Map<String, dynamic>> _articles = [];
  bool _loading = true;
  bool _importing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await ref.read(appDatabaseProvider).getArticles();
      if (mounted) {
        setState(() {
          _articles = rows;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load articles.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    final db = ref.read(appDatabaseProvider);
    try {
      final picked = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['txt', 'pdf']);
      if (picked == null || picked.files.single.path == null) return;
      final id = await ArticleImportService(db).importFile(
          File(picked.files.single.path!),
          name: picked.files.single.name);
      if (!mounted) return;
      await context.push('/learn/reading/$id');
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is FormatException
                ? error.message
                : 'Import failed. Check the file and available storage.')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Reading')),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: _importing ? null : _import,
            icon: const Icon(Icons.upload_file),
            label: Text(_importing ? 'Importing…' : 'Import article')),
        body: _loading
            ? const LoadingView()
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                    children: [
                      const SectionHeader(
                          title: 'Library',
                          subtitle:
                              'Offline articles · TXT and selectable-text PDF'),
                      if (_error != null) ErrorView(message: _error!),
                      if (_articles.isEmpty)
                        const EmptyState(
                            icon: Icons.menu_book_outlined,
                            title: 'No articles yet',
                            message:
                                'Import a UTF-8 TXT file or a PDF with selectable text. Scanned PDFs require OCR and are not supported.'),
                      for (final article in _articles)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ModuleTile(
                                icon: Icons.article_outlined,
                                title: article['title'] as String,
                                subtitle: article['source_name'] as String? ??
                                    'Saved locally',
                                onTap: () async {
                                  await context
                                      .push('/learn/reading/${article['id']}');
                                  if (mounted) await _load();
                                })),
                    ])),
      );
}

class ArticleReaderScreen extends ConsumerStatefulWidget {
  const ArticleReaderScreen({super.key, required this.articleId});
  final String articleId;
  @override
  ConsumerState<ArticleReaderScreen> createState() =>
      _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends ConsumerState<ArticleReaderScreen>
    with WidgetsBindingObserver {
  late final AppDatabase _db;
  final _scroll = ScrollController();
  Timer? _debounce;
  Map<String, dynamic>? _article;
  String? _error;
  bool _loading = true;
  bool _savingWord = false;
  double _offset = 0;
  @override
  void initState() {
    super.initState();
    _db = ref.read(appDatabaseProvider);
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_positionChanged);
    _load();
  }

  Future<void> _load() async {
    try {
      final article = await _db.getArticle(widget.articleId);
      if (!mounted) return;
      if (article != null) {
        await _db.logActivity(
            id: newId(),
            type: 'reading_opened',
            module: 'reading',
            localDate: localDateString());
      }
      if (!mounted) return;
      setState(() {
        _article = article;
        _loading = false;
        if (article == null) _error = 'Article not found.';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients && article != null) {
          _scroll.jumpTo((article['scroll_offset'] as num)
              .toDouble()
              .clamp(0, _scroll.position.maxScrollExtent));
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not open article.';
        });
      }
    }
  }

  void _positionChanged() {
    _offset = _scroll.offset;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _savePosition);
  }

  Future<void> _savePosition() async {
    if (_article == null) return;
    try {
      await _db.saveReadingPosition(widget.articleId, _offset);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save reading position.')));
      }
    }
  }

  Future<void> _saveWord(String body, TextSelection selection) async {
    if (_savingWord || !selection.isValid || selection.isCollapsed) return;
    final word = selection.textInside(body).trim();
    if (word.isEmpty || word.length > 100) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Select a word or short phrase (up to 100 characters).')));
      return;
    }
    _savingWord = true;
    try {
      await _db.saveVocabulary(
          word: word,
          sentence: sourceSentence(body, selection.start, selection.end),
          source: _article!['title'] as String,
          articleId: widget.articleId);
      if (!mounted) return;
      ref.invalidate(dashboardProvider);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved “$word” with its source sentence.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save word.')));
      }
    } finally {
      _savingWord = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _debounce?.cancel();
      unawaited(_savePosition());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    unawaited(_savePosition());
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = _article?['body'] as String? ?? '';
    return Scaffold(
        appBar: AppBar(title: Text(_article?['title'] as String? ?? 'Reading')),
        body: _loading
            ? const LoadingView()
            : _error != null
                ? ErrorView(message: _error!)
                : SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                              'Select a word, then choose Save word. Definitions can be added in Vocabulary.'),
                          const SizedBox(height: 16),
                          SelectableText(body,
                              style: Theme.of(context).textTheme.bodyLarge,
                              contextMenuBuilder: (context, state) {
                            final selection = state.textEditingValue.selection;
                            return AdaptiveTextSelectionToolbar.buttonItems(
                                anchors: state.contextMenuAnchors,
                                buttonItems: [
                                  ...state.contextMenuButtonItems,
                                  ContextMenuButtonItem(
                                      label: 'Save word',
                                      onPressed: () {
                                        state.hideToolbar();
                                        _saveWord(body, selection);
                                      }),
                                ]);
                          }),
                        ])));
  }
}
