import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/services/providers.dart';
import '../../../core/services/recording_service.dart';
import '../../../core/utils/id_utils.dart';
import '../../../core/widgets/common_widgets.dart';

class SpeakingStudioScreen extends ConsumerStatefulWidget {
  const SpeakingStudioScreen({super.key});

  @override
  ConsumerState<SpeakingStudioScreen> createState() =>
      _SpeakingStudioScreenState();
}

class _SpeakingStudioScreenState extends ConsumerState<SpeakingStudioScreen> {
  List<Map<String, dynamic>> _prompts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    await db.seedBuiltinPromptsIfEmpty();
    final rows = await db.getSpeakingPrompts();
    if (mounted)
      setState(() {
        _prompts = rows;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    final categories = <String>{};
    for (final p in _prompts) {
      categories.add(p['category'] as String);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Speaking Studio')),
      body: _loading
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Practice speaking with prompts. Recordings stay on your device unless you choose to send text to AI later.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (_prompts.isEmpty)
                  const EmptyState(
                    icon: Icons.mic_none,
                    title: 'No prompts',
                    message: 'Starter prompts will appear here.',
                  )
                else
                  ...categories.map((cat) {
                    final items =
                        _prompts.where((p) => p['category'] == cat).toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionHeader(title: _labelCat(cat)),
                        ...items.map((p) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: ModuleTile(
                                icon: Icons.record_voice_over_outlined,
                                iconColor: AppColors.teal,
                                title: '${p['title']}',
                                subtitle:
                                    '${p['difficulty']} · ${p['suggested_seconds']}s suggested',
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          PromptRecordScreen(prompt: p),
                                    ),
                                  );
                                },
                              ),
                            )),
                        const SizedBox(height: 8),
                      ],
                    );
                  }),
              ],
            ),
    );
  }

  String _labelCat(String c) {
    switch (c) {
      case 'everyday':
        return 'Everyday conversation';
      case 'university':
        return 'University life';
      case 'technology':
        return 'Technology & programming';
      case 'job_interview':
        return 'Job interview';
      case 'opinion':
        return 'Giving opinions';
      case 'experience':
        return 'Describing experiences';
      default:
        return c;
    }
  }
}

class PromptRecordScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> prompt;
  const PromptRecordScreen({super.key, required this.prompt});

  @override
  ConsumerState<PromptRecordScreen> createState() => _PromptRecordScreenState();
}

class _PromptRecordScreenState extends ConsumerState<PromptRecordScreen> {
  final _recorder = RecordingService();
  final _player = AudioPlayer();
  bool _recording = false;
  String? _lastPath;
  int _lastMs = 0;
  List<Map<String, dynamic>> _history = [];
  String? _permissionError;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final rows = await ref
        .read(appDatabaseProvider)
        .getRecordings(promptId: widget.prompt['id'] as String);
    if (mounted) setState(() => _history = rows);
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      final result = await _recorder.stop();
      setState(() => _recording = false);
      if (result == null) return;
      _lastPath = result.path;
      _lastMs = result.durationMs;
      final id = newId();
      await ref.read(appDatabaseProvider).insertRecording({
        'id': id,
        'prompt_id': widget.prompt['id'],
        'lesson_id': null,
        'mode': 'prompt',
        'audio_path': result.path,
        'duration_ms': result.durationMs,
        'self_rating': null,
        'notes': null,
      });
      await _loadHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording saved locally')));
      }
      return;
    }

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      setState(() =>
          _permissionError = 'Microphone permission is required to record.');
      return;
    }
    setState(() => _permissionError = null);
    final path = await _recorder.start();
    if (path == null) {
      setState(() => _permissionError = 'Could not start recording.');
      return;
    }
    setState(() => _recording = true);
  }

  Future<void> _play(String path) async {
    if (!File(path).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Recording file missing')));
      }
      return;
    }
    await _player.setFilePath(path);
    await _player.play();
  }

  Future<void> _delete(String id, String path) async {
    await ref.read(appDatabaseProvider).deleteRecording(id);
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await _loadHistory();
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.prompt;
    return Scaffold(
      appBar: AppBar(title: Text('${p['title']}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          LexiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p['prompt_text']}',
                    style: Theme.of(context).textTheme.bodyLarge),
                if (p['guidance'] != null) ...[
                  const SizedBox(height: 10),
                  Text('Guidance: ${p['guidance']}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 8),
                Text(
                    'Suggested: ${p['suggested_seconds']}s · ${p['difficulty']}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_permissionError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_permissionError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          Center(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _recording ? AppColors.error : AppColors.teal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              ),
              onPressed: _toggleRecord,
              icon: Icon(_recording ? Icons.stop : Icons.mic),
              label: Text(_recording ? 'Stop & save' : 'Record'),
            ),
          ),
          if (_lastPath != null) ...[
            const SizedBox(height: 12),
            Center(
              child: Text('Last take: ${(_lastMs / 1000).toStringAsFixed(1)}s',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
          const SizedBox(height: 24),
          SectionHeader(title: 'Previous attempts'),
          if (_history.isEmpty)
            Text('No recordings yet.',
                style: Theme.of(context).textTheme.bodySmall)
          else
            ..._history.map((r) {
              final path = r['audio_path'] as String;
              final ms = r['duration_ms'] as int? ?? 0;
              return LexiCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => _play(path),
                      icon: const Icon(Icons.play_arrow),
                    ),
                    Expanded(
                      child: Text(
                        '${(ms / 1000).toStringAsFixed(1)}s · ${r['created_at']}'
                            .substring(0,
                                30.clamp(0, '${r['created_at']}'.length + 10)),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _delete(r['id'] as String, path),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
