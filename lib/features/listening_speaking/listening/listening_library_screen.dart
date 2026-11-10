import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_theme.dart';
import '../../../core/services/media_storage.dart';
import '../../../core/services/providers.dart';
import '../../../core/utils/id_utils.dart';
import '../../../core/widgets/common_widgets.dart';

class ListeningLibraryScreen extends ConsumerStatefulWidget {
  const ListeningLibraryScreen({super.key});

  @override
  ConsumerState<ListeningLibraryScreen> createState() =>
      _ListeningLibraryScreenState();
}

class _ListeningLibraryScreenState
    extends ConsumerState<ListeningLibraryScreen> {
  List<Map<String, dynamic>> _lessons = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final db = ref.read(appDatabaseProvider);
      final rows = await db.getListeningLessons();
      if (mounted)
        setState(() {
          _lessons = rows;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = 'Could not load lessons.';
          _loading = false;
        });
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'wav', 'aac', 'ogg'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access the selected file.')),
        );
      }
      return;
    }
    try {
      final storage = MediaStorage();
      final dest = await storage.importAudio(File(path));
      final title = p.basenameWithoutExtension(path);
      final id = newId();
      await ref.read(appDatabaseProvider).insertListeningLesson({
        'id': id,
        'title': title,
        'topic': 'Imported',
        'difficulty': 'B1',
        'audio_path': dest,
        'duration_ms': 0,
        'last_position_ms': 0,
        'transcript': null,
        'transcript_path': null,
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio imported and saved offline.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Import failed. Try another file format.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Listening Studio'),
        actions: [
          IconButton(
            tooltip: 'Import audio',
            onPressed: _import,
            icon: const Icon(Icons.file_upload_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _import,
        icon: const Icon(Icons.add),
        label: const Text('Import'),
      ),
      body: _loading
          ? const LoadingView(message: 'Loading lessons…')
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _lessons.isEmpty
                  ? EmptyState(
                      icon: Icons.headphones_outlined,
                      title: 'No listening lessons yet',
                      message:
                          'Import an MP3, M4A, or WAV file from your device. Files are copied into app storage for offline use.',
                      action: PrimaryButton(
                          label: 'Import audio',
                          onPressed: _import,
                          icon: Icons.file_upload_outlined),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(20),
                        itemCount: _lessons.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final l = _lessons[i];
                          final pos = (l['last_position_ms'] as int?) ?? 0;
                          final dur = (l['duration_ms'] as int?) ?? 0;
                          final progress =
                              dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
                          return LexiCard(
                            onTap: () => context
                                .push('/learn/listening/player/${l['id']}'),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppColors.violet
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(Icons.headphones,
                                      color: AppColors.violet),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('${l['title']}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${l['difficulty'] ?? 'B1'} · ${l['topic'] ?? 'General'}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      if (dur > 0) ...[
                                        const SizedBox(height: 6),
                                        LinearProgressIndicator(
                                            value: progress,
                                            minHeight: 4,
                                            borderRadius:
                                                BorderRadius.circular(2)),
                                      ],
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.4)),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
