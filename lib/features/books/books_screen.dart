import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

import '../../app/theme/app_theme.dart';
import 'completion_panel.dart';
import '../../core/services/providers.dart';
import '../../core/utils/id_utils.dart';
import '../../core/widgets/common_widgets.dart';

class BooksScreen extends ConsumerStatefulWidget {
  const BooksScreen({super.key});

  @override
  ConsumerState<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends ConsumerState<BooksScreen> {
  List<Map<String, dynamic>> _books = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref.read(appDatabaseProvider).getImportedBooks();
    if (mounted) {
      setState(() {
        _books = rows;
        _loading = false;
      });
    }
  }

  bool _importing = false;
  Future<void> _importPdf() async {
    if (_importing) return;
    _importing = true;
    final db = ref.read(appDatabaseProvider);
    String? copied;
    var registered = false;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (result == null ||
          result.files.isEmpty ||
          result.files.single.path == null) return;
      final srcPath = result.files.single.path!;
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'media', 'books'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final id = newId();
      final dest = p.join(dir.path, '$id.pdf');
      copied = dest;
      await File(srcPath).copy(dest);

      int pages;
      try {
        final doc = await PdfDocument.openFile(dest);
        pages = doc.pagesCount;
        await doc.close();
        if (pages < 1) throw StateError('PDF has no pages');
      } catch (_) {
        await File(dest).delete();
        rethrow;
      }

      final title = p.basenameWithoutExtension(srcPath);
      await db.insertImportedBook({
        'id': id,
        'title': title,
        'file_path': dest,
        'page_count': pages,
        'current_page': 1,
      });
      registered = true;
      if (mounted) await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(pages > 0
                  ? 'Imported “$title” ($pages pages)'
                  : 'Imported “$title” (page count unavailable)')),
        );
      }
    } catch (e) {
      if (copied != null && !registered) {
        try {
          if (await File(copied).exists()) await File(copied).delete();
        } catch (_) {}
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not import PDF. File may be corrupted or protected.')),
        );
      }
    } finally {
      _importing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Books'), actions: [
        TextButton(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const CoursesScreen())),
            child: const Text('Courses'))
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importPdf,
        icon: const Icon(Icons.upload_file),
        label: const Text('Import PDF'),
      ),
      body: _loading
          ? const LoadingView()
          : _books.isEmpty
              ? EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: 'No books yet',
                  message:
                      'Import a PDF from your device. Files are copied into app storage for offline reading. Chapters are not auto-detected — you can add units manually.',
                  action: PrimaryButton(
                      label: 'Import PDF',
                      onPressed: _importPdf,
                      icon: Icons.upload_file),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _books.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final b = _books[i];
                    final page = b['current_page'] as int? ?? 1;
                    final total = b['page_count'] as int? ?? 0;
                    return LexiCard(
                      onTap: () async {
                        await context.push('/learn/books/${b['id']}');
                        if (mounted) await _load();
                      },
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.violet.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.picture_as_pdf,
                                color: AppColors.violet),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${b['title']}',
                                    style:
                                        Theme.of(context).textTheme.titleSmall),
                                Text(
                                  total > 0
                                      ? 'Page $page of $total'
                                      : 'Page $page',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class BookDetailScreen extends ConsumerStatefulWidget {
  final String bookId;
  const BookDetailScreen({super.key, required this.bookId});

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  Map<String, dynamic>? _book;
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _lessons = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    final book = await db.getImportedBook(widget.bookId);
    final units = await db.getBookUnits(widget.bookId);
    final lessons = await db.getBookLessons(widget.bookId);
    if (mounted) {
      setState(() {
        _book = book;
        _units = units;
        _lessons = lessons;
        _loading = false;
      });
    }
  }

  Future<void> _addUnit() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New unit'),
        content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Unit title')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await ref.read(appDatabaseProvider).insertBookUnit({
        'id': newId(),
        'book_id': widget.bookId,
        'title': ctrl.text.trim(),
        'order_index': _units.length,
        'completed': 0,
      });
      await _load();
    }
  }

  Future<void> _addLesson(String unitId) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New lesson'),
        content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Lesson title')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      await ref.read(appDatabaseProvider).insertBookLesson({
        'id': newId(),
        'unit_id': unitId,
        'book_id': widget.bookId,
        'title': ctrl.text.trim(),
        'notes': null,
        'page_start': null,
        'page_end': null,
        'objective': null,
        'completed': 0,
        'order_index': _lessons.length,
      });
      await _load();
    }
  }

  Future<void> _deleteBook() async {
    final ok = await showConfirmDialog(context,
        title: 'Remove book?',
        message: 'Deletes the local copy and learning structure.');
    if (ok != true || _book == null) return;
    final path = _book!['file_path'] as String?;
    await ref.read(appDatabaseProvider).deleteImportedBook(widget.bookId);
    if (path != null) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    if (_book == null) {
      return Scaffold(
          appBar: AppBar(), body: const ErrorView(message: 'Book not found'));
    }
    final b = _book!;
    final path = b['file_path'] as String;
    final exists = File(path).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: Text('${b['title']}'),
        actions: [
          IconButton(
              onPressed: _deleteBook, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (!exists)
            const ErrorView(message: 'PDF file is missing from device storage.')
          else
            PrimaryButton(
              label: 'Continue reading (page ${b['current_page']})',
              icon: Icons.menu_book,
              onPressed: () async {
                await context.push('/learn/books/${widget.bookId}/read');
                if (mounted) await _load();
              },
            ),
          const SizedBox(height: 20),
          CompletionPanel(type: 'book', id: widget.bookId),
          const SizedBox(height: 20),
          SectionHeader(
            title: 'Units & lessons',
            trailing:
                TextButton(onPressed: _addUnit, child: const Text('Add unit')),
          ),
          Text(
            'Structure is manual — PDFs are not auto-chaptered.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (_units.isEmpty)
            const Text('No units yet.')
          else
            ..._units.map((u) {
              final unitLessons =
                  _lessons.where((l) => l['unit_id'] == u['id']).toList();
              return LexiCard(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child: Text('${u['title']}',
                                style: Theme.of(context).textTheme.titleSmall)),
                        TextButton(
                            onPressed: () => _addLesson(u['id'] as String),
                            child: const Text('Add lesson')),
                      ],
                    ),
                    ...unitLessons.map((l) {
                      final done = (l['completed'] as int?) == 1;
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: done,
                        title: Text('${l['title']}'),
                        onChanged: (v) async {
                          await ref
                              .read(appDatabaseProvider)
                              .markBookLessonComplete(
                                  l['id'] as String, v ?? false);
                          await _load();
                        },
                      );
                    }),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class BookReaderScreen extends ConsumerStatefulWidget {
  final String bookId;
  final int? initialPage;
  const BookReaderScreen({super.key, required this.bookId, this.initialPage});

  @override
  ConsumerState<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends ConsumerState<BookReaderScreen> {
  PdfControllerPinch? _controller;
  String? _error;
  int _page = 1;
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final book =
          await ref.read(appDatabaseProvider).getImportedBook(widget.bookId);
      if (!mounted) return;
      if (book == null) {
        setState(() => _error = 'Book not found');
        return;
      }
      final path = book['file_path'] as String;
      if (!File(path).existsSync()) {
        setState(() => _error = 'PDF file missing');
        return;
      }
      final doc = await PdfDocument.openFile(path);
      if (!mounted) {
        await doc.close();
        return;
      }
      final start = (widget.initialPage ?? (book['current_page'] as int?) ?? 1)
          .clamp(1, doc.pagesCount);
      final ctrl = PdfControllerPinch(
        document: Future.value(doc),
        initialPage: start,
      );
      setState(() {
        _controller = ctrl;
        _page = start;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error =
          'Could not open PDF. Check storage and the imported file (it may be corrupted, password-protected, or unsupported).');
    }
  }

  Future<void> _persist(int page) async {
    if (!mounted) return;
    _page = page;
    try {
      await ref.read(appDatabaseProvider).updateBookProgress(
          widget.bookId, page,
          pageCount: _pageCount > 0 ? _pageCount : null);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not save your PDF position. Check storage and retry.')));
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(appBar: AppBar(), body: ErrorView(message: _error!));
    }
    if (_controller == null) {
      return const Scaffold(body: LoadingView(message: 'Opening PDF…'));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Page $_page'),
        actions: [
          IconButton(
            tooltip: 'Bookmark page',
            onPressed: () async {
              await ref
                  .read(appDatabaseProvider)
                  .addBookBookmark(newId(), widget.bookId, _page);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Bookmarked page $_page')));
              }
            },
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
        ],
      ),
      body: PdfViewPinch(
        controller: _controller!,
        onDocumentError: (_) {
          if (mounted) setState(() => _error = 'Could not open PDF.');
        },
        onDocumentLoaded: (doc) {
          if (!mounted) return;
          setState(() => _pageCount = doc.pagesCount);
          _persist(_page);
        },
        onPageChanged: (page) {
          if (!mounted) return;
          setState(() => _page = page);
          _persist(page);
        },
      ),
    );
  }
}
