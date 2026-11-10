import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/services/ai_teacher_service.dart';
import '../../../core/services/providers.dart';
import '../../../core/utils/id_utils.dart';
import '../../../core/widgets/common_widgets.dart';

const _categories = [
  'journal',
  'opinion',
  'essay',
  'email',
  'story',
  'academic',
  'free',
];

const _prompts = [
  ('Describe a challenge you overcame and what you learned.', 'journal'),
  ('Should remote work be the default? Give two reasons.', 'opinion'),
  ('Write a short email requesting a deadline extension.', 'email'),
  ('Explain a simple programming idea to a beginner.', 'academic'),
];

class WritingStudioScreen extends ConsumerStatefulWidget {
  const WritingStudioScreen({super.key});

  @override
  ConsumerState<WritingStudioScreen> createState() =>
      _WritingStudioScreenState();
}

class _WritingStudioScreenState extends ConsumerState<WritingStudioScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref.read(appDatabaseProvider).getWritingEntries();
    if (mounted)
      setState(() {
        _entries = rows;
        _loading = false;
      });
  }

  Future<void> _newEntry({String? prompt, String category = 'free'}) async {
    final id = newId();
    final title = prompt == null
        ? 'Untitled'
        : (prompt.length > 40 ? '${prompt.substring(0, 40)}…' : prompt);
    await ref.read(appDatabaseProvider).upsertWritingEntry({
      'id': id,
      'title': title,
      'category': category,
      'body': prompt == null ? '' : '',
      'word_count': 0,
      'prompt_id': null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    if (mounted) context.push('/learn/grammar/writing/$id');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Writing Studio')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newEntry(),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('New entry'),
      ),
      body: _loading
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                SectionHeader(title: 'Prompts'),
                ..._prompts.map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ModuleTile(
                        icon: Icons.lightbulb_outline,
                        title: p.$1,
                        subtitle: p.$2,
                        onTap: () => _newEntry(prompt: p.$1, category: p.$2),
                      ),
                    )),
                const SizedBox(height: 16),
                SectionHeader(title: 'Your writing'),
                if (_entries.isEmpty)
                  const EmptyState(
                    icon: Icons.edit_note,
                    title: 'No entries yet',
                    message:
                        'Start a free write or pick a prompt. Drafts autosave offline.',
                  )
                else
                  ..._entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: LexiCard(
                          onTap: () =>
                              context.push('/learn/grammar/writing/${e['id']}'),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${e['title']}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall),
                                    Text(
                                        '${e['category']} · ${e['word_count']} words',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      )),
                const SizedBox(height: 12),
                ModuleTile(
                  icon: Icons.report_outlined,
                  title: 'Mistake journal',
                  subtitle: 'Review saved writing mistakes',
                  onTap: () => context.push('/learn/grammar/mistakes'),
                ),
              ],
            ),
    );
  }
}

class WritingEditorScreen extends ConsumerStatefulWidget {
  final String entryId;
  const WritingEditorScreen({super.key, required this.entryId});

  @override
  ConsumerState<WritingEditorScreen> createState() =>
      _WritingEditorScreenState();
}

class _WritingEditorScreenState extends ConsumerState<WritingEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _category = 'free';
  Timer? _debounce;
  bool _loading = true;
  List<Map<String, dynamic>> _feedback = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final e =
        await ref.read(appDatabaseProvider).getWritingEntry(widget.entryId);
    final fb =
        await ref.read(appDatabaseProvider).getWritingFeedback(widget.entryId);
    if (e != null && mounted) {
      _titleCtrl.text = e['title'] as String? ?? '';
      _bodyCtrl.text = e['body'] as String? ?? '';
      _category = e['category'] as String? ?? 'free';
      setState(() {
        _feedback = fb;
        _loading = false;
      });
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  int get _wordCount {
    final t = _bodyCtrl.text.trim();
    if (t.isEmpty) return 0;
    return t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  void _scheduleSave() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    await ref.read(appDatabaseProvider).upsertWritingEntry({
      'id': widget.entryId,
      'title':
          _titleCtrl.text.trim().isEmpty ? 'Untitled' : _titleCtrl.text.trim(),
      'category': _category,
      'body': _bodyCtrl.text,
      'word_count': _wordCount,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _snapshot() async {
    await _save();
    await ref.read(appDatabaseProvider).saveWritingRevision({
      'id': newId(),
      'entry_id': widget.entryId,
      'body': _bodyCtrl.text,
      'word_count': _wordCount,
      'label': 'Manual snapshot',
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Revision saved (original preserved)')));
    }
  }

  Future<void> _requestAiFeedback() async {
    final status = await ref.read(aiTeacherServiceProvider).checkStatus();
    final confirmed = await showConfirmDialog(
      context,
      title: 'Request AI feedback?',
      message: status.isReady
          ? 'Your writing text will be prepared for an AI provider. Live HTTP is not enabled in this build; a structured offline checklist will be saved instead if the provider client is unavailable.'
          : 'No AI key configured. A self-review checklist will be saved. Automated corrections are not invented offline.',
      confirmLabel: 'Continue',
    );
    if (confirmed != true) return;

    final checklist = StringBuffer()
      ..writeln('Writing self-review / AI placeholder')
      ..writeln('Words: $_wordCount')
      ..writeln('')
      ..writeln(
          '1. Overall: Check if your main idea is clear in the first sentence.')
      ..writeln(
          '2. Grammar: Scan articles (a/an/the), subject–verb agreement, and tense consistency.')
      ..writeln(
          '3. Vocabulary: Replace repeated words with more precise ones where natural.')
      ..writeln('4. Structure: Each paragraph should develop one idea.')
      ..writeln(
          '5. American English: Prefer American spelling if that is your target (color, organize, traveled).')
      ..writeln('')
      ..writeln(status.isReady
          ? 'Note: API credentials are present, but a live provider HTTP client is not wired in this build. This checklist is not model-generated feedback.'
          : 'AI unavailable offline. This is a self-review checklist, not automated correction.');

    await ref.read(appDatabaseProvider).saveWritingFeedback({
      'id': newId(),
      'entry_id': widget.entryId,
      'source': status.isReady ? 'ai_pending' : 'self_checklist',
      'content': checklist.toString(),
    });
    final fb =
        await ref.read(appDatabaseProvider).getWritingFeedback(widget.entryId);
    setState(() => _feedback = fb);
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(context,
        title: 'Delete entry?',
        message: 'This removes the entry, revisions, and feedback.');
    if (ok != true) return;
    await ref.read(appDatabaseProvider).deleteWritingEntry(widget.entryId);
    if (mounted) context.pop();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Editor'),
        actions: [
          IconButton(
              tooltip: 'Save revision',
              onPressed: _snapshot,
              icon: const Icon(Icons.history)),
          IconButton(
              tooltip: 'Delete',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Title'),
            onChanged: (_) => _scheduleSave(),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _category,
            items: _categories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) {
              setState(() => _category = v ?? 'free');
              _scheduleSave();
            },
            decoration: const InputDecoration(labelText: 'Category'),
          ),
          const SizedBox(height: 12),
          Text('$_wordCount words',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          TextField(
            controller: _bodyCtrl,
            minLines: 12,
            maxLines: 24,
            decoration: const InputDecoration(
              hintText: 'Start writing… Drafts autosave.',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              setState(() {});
              _scheduleSave();
            },
          ),
          const SizedBox(height: 16),
          PrimaryButton(
              label: 'Request feedback',
              onPressed: _requestAiFeedback,
              icon: Icons.auto_awesome),
          if (_feedback.isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionHeader(title: 'Saved feedback'),
            ..._feedback.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LexiCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${f['source']}',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: AppColors.violet)),
                        const SizedBox(height: 6),
                        Text('${f['content']}'),
                      ],
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class MistakeJournalScreen extends ConsumerStatefulWidget {
  const MistakeJournalScreen({super.key});

  @override
  ConsumerState<MistakeJournalScreen> createState() =>
      _MistakeJournalScreenState();
}

class _MistakeJournalScreenState extends ConsumerState<MistakeJournalScreen> {
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref.read(appDatabaseProvider).getWritingMistakes();
    if (mounted) setState(() => _items = rows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mistake journal')),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final id = newId();
          await ref.read(appDatabaseProvider).saveWritingMistake({
            'id': id,
            'entry_id': null,
            'grammar_topic': 'manual',
            'original_sentence': 'Add your sentence here',
            'correction': '',
            'explanation': 'Manually added',
            'review_status': 'open',
          });
          await _load();
        },
        child: const Icon(Icons.add),
      ),
      body: _items.isEmpty
          ? const EmptyState(
              icon: Icons.checklist,
              title: 'No mistakes logged',
              message:
                  'Save mistakes from writing feedback or add them manually.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final m = _items[i];
                final done = m['review_status'] == 'understood';
                return LexiCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${m['original_sentence']}',
                          style: Theme.of(context).textTheme.titleSmall),
                      if ((m['correction'] as String?)?.isNotEmpty == true)
                        Text('→ ${m['correction']}',
                            style: TextStyle(color: AppColors.teal)),
                      if (m['explanation'] != null)
                        Text('${m['explanation']}',
                            style: Theme.of(context).textTheme.bodySmall),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: done
                              ? null
                              : () async {
                                  await ref
                                      .read(appDatabaseProvider)
                                      .markMistakeReviewed(m['id'] as String);
                                  await _load();
                                },
                          child: Text(done ? 'Understood' : 'Mark understood'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
