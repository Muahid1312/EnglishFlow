import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/services/providers.dart';
import '../../../core/utils/id_utils.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../core/widgets/ai_help_button.dart';
import '../../../core/services/ai_teacher_service.dart';
import 'writing_history_screens.dart';
import '../../../core/services/mistake_coach.dart';
import '../../mistake_coach/mistake_practice_screen.dart';

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
    if (mounted) {
      setState(() {
        _entries = rows;
        _loading = false;
      });
    }
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
    if (mounted) {
      await context.push('/learn/grammar/writing/$id');
      if (mounted) await _load();
    }
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
                const SectionHeader(title: 'Prompts'),
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
                const SectionHeader(title: 'Your writing'),
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
                          onTap: () async {
                            await context
                                .push('/learn/grammar/writing/${e['id']}');
                            if (mounted) await _load();
                          },
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

class _WritingEditorScreenState extends ConsumerState<WritingEditorScreen>
    with WidgetsBindingObserver {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  String _category = 'free';
  Timer? _debounce;
  bool _loading = true;
  bool _deleted = false;
  String? _saveError;
  bool _dirty = false;
  late final AppDatabase _db;
  int _editVersion = 0;
  List<Map<String, dynamic>> _feedback = [];

  @override
  void initState() {
    super.initState();
    _db = ref.read(appDatabaseProvider);
    WidgetsBinding.instance.addObserver(this);
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
    _dirty = true;
    _editVersion++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    if (_loading || _deleted || !_dirty) return;
    final version = _editVersion;
    final data = <String, Object?>{
      'id': widget.entryId,
      'title':
          _titleCtrl.text.trim().isEmpty ? 'Untitled' : _titleCtrl.text.trim(),
      'category': _category,
      'body': _bodyCtrl.text,
      'word_count': _wordCount,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    try {
      await _db.upsertWritingEntry(data);
      if (_editVersion == version) _dirty = false;
      if (mounted && _saveError != null) setState(() => _saveError = null);
    } catch (_) {
      if (mounted) {
        setState(() => _saveError =
            'Draft could not be saved. Keep this screen open and retry.');
      }
    }
  }

  Future<void> _snapshot() async {
    await _save();
    if (!mounted || _dirty || _loading || _deleted) return;
    final label = await showDialog<String>(
        context: context, builder: (_) => const RevisionLabelDialog());
    if (label == null || !mounted) return;
    await _db.saveWritingRevision({
      'id': newId(),
      'entry_id': widget.entryId,
      'body': _bodyCtrl.text,
      'word_count': _wordCount,
      'label': label,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Revision saved (original preserved)')));
    }
  }

  Future<void> _showHistory() async {
    await _save();
    if (!mounted || _dirty) return;
    final restored = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) =>
            RevisionHistoryScreen(db: _db, entryId: widget.entryId)));
    if (restored == true && mounted) await _load();
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(context,
        title: 'Delete entry?',
        message: 'This removes the entry, revisions, and feedback.');
    if (ok != true) return;
    _debounce?.cancel();
    await _save();
    await _db.deleteWritingEntry(widget.entryId);
    _deleted = true;
    if (mounted) context.pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _debounce?.cancel();
      unawaited(_save());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    unawaited(_save());
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
              tooltip: 'Revision history',
              onPressed: _showHistory,
              icon: const Icon(Icons.restore)),
          IconButton(
              tooltip: 'Delete',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_saveError != null)
            ErrorView(message: _saveError!, onRetry: _save),
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
          OutlinedButton.icon(icon:const Icon(Icons.bookmark_add_outlined),label:const Text('Save a confirmed correction'),
            onPressed:() async {
              await _save();
              if(!context.mounted || _dirty || _deleted)return;
              final selection=_bodyCtrl.selection;
              final original=selection.isValid && !selection.isCollapsed?selection.textInside(_bodyCtrl.text):_bodyCtrl.text;
              await showDialog<bool>(context:context,builder:(_)=>MistakeEditorDialog(db:_db,sourceEntryId:widget.entryId,
                initialOriginal:original,sourceLabel:'Writing: ${_titleCtrl.text}'));
            }),
          AiHelpButton(
              label: 'Request AI feedback',
              task: AiTask.writing,
              content: () => _bodyCtrl.text,
              beforeSend: () async {
                await _save();
                return !_dirty && !_deleted;
              },
              onResponse: (response, submitted) async {
                await _db.saveAiWritingFeedback(
                    widget.entryId, submitted, response);
                final feedback = await _db.getWritingFeedback(widget.entryId);
                if (mounted) setState(() => _feedback = feedback);
              }),
          if (_feedback.isNotEmpty) ...[
            const SizedBox(height: 20),
            const SectionHeader(title: 'Saved feedback'),
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
  Map<String,dynamic>? _insights;
  List<Map<String,dynamic>> _weaknesses=[];
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final database=ref.read(appDatabaseProvider);
      final rows=await database.getWritingMistakes();
      final coach=MistakeCoach(database);
      final insights=await coach.insights();
      final weaknesses=await coach.weaknesses();
      if(mounted)setState((){_items=rows;_insights=insights;_weaknesses=weaknesses;_loadError=null;});
    } catch(_){if(mounted)setState(()=>_loadError='Could not load your mistake journal.');}
  }

  Future<void> _editMistake([Map<String, dynamic>? mistake]) async {
    final db = ref.read(appDatabaseProvider);
    await showDialog<bool>(
        context: context,
        builder: (_) => MistakeEditorDialog(db: db, mistake: mistake));
    if (mounted) await _load();
  }

  Future<void> _removeMistake(Map<String, dynamic> mistake) async {
    final db = ref.read(appDatabaseProvider);
    final accepted = await showConfirmDialog(context,
        title: 'Delete mistake?',
        message: 'Remove this mistake from the journal? Its practice history is retained in the database and backups.');
    if (accepted == true) {
      await db.deleteWritingMistake(mistake['id'] as String);
      if (mounted) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mistake journal')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add mistake',
        onPressed: () => _editMistake(),
        child: const Icon(Icons.add),
      ),
      body:ListView.builder(itemCount:_items.length+1,itemBuilder:(context,index){
        if(index==0)return Column(children:[

        if(_loadError!=null) ErrorView(message:_loadError!,onRetry:_load),
        Padding(padding:const EdgeInsets.all(20),child:LexiCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('${_items.length} recorded mistakes · ${_items.where((m)=>m['review_status']=='understood').length} marked reviewed'),
          const Text('Reviewed does not mean mastered. Repetitions count saved practice attempts.'),
          if(_insights!=null) ...[
            for(final c in _insights!['categories'] as List) Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('${c['category']}: ${c['total']} recorded · ${c['repeated']} repeated'),
              LinearProgressIndicator(value:_items.isEmpty?0:(c['total'] as int)/_items.length),
            ])),
            Text(_insights!['trend']==null?'Improvement trend needs 10 exact-wording attempts.':'Recent exact-wording trend: ${((_insights!['trend'] as double)*100).toStringAsFixed(0)} percentage points, last 5 vs previous 5. Self-assessment excluded.'),
          ],
          if(_weaknesses.isEmpty) const Text('More records or repeated practice are needed to recommend a recurring category.'),
          for(final w in _weaknesses) TextButton(onPressed:() async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>MistakePracticeScreen(category:w['category'] as String?)));
            if(mounted)await _load();
          },child:Text('Practice ${w['category']} · ${w['records']} records, ${w['errors'] ?? 0} wording mismatches')),
          FilledButton(onPressed:_items.isEmpty?null:() async {
            await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const MistakePracticeScreen()));
            if(mounted)await _load();
          },child:const Text('Practice up to 5 mistakes')),
        ]))),
          if(_items.isEmpty) const EmptyState(icon:Icons.checklist,title:'No mistakes logged',
            message:'Create a confirmed correction, or save one from Writing Studio.'),
        ]);
                final m = _items[index-1];
                final done = m['review_status'] == 'understood';
                return Padding(padding:const EdgeInsets.fromLTRB(20,0,20,8),child:LexiCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        IconButton(
                            tooltip: 'Edit mistake',
                            onPressed: () => _editMistake(m),
                            icon: const Icon(Icons.edit_outlined)),
                        IconButton(
                            tooltip: 'Delete mistake',
                            onPressed: () => _removeMistake(m),
                            icon: const Icon(Icons.delete_outline))
                      ]),
                      Text('${m['grammar_topic'] ?? 'Other'} · ${m['repetitions']} repetitions · ${m['created_at']}'),
                      if(m['source_label']!=null) Text(m['source_label'] as String),
                      Text('${m['original_sentence']}',
                          style: Theme.of(context).textTheme.titleSmall),
                      if ((m['correction'] as String?)?.isNotEmpty == true)
                        Text('→ ${m['correction']}',
                            style: const TextStyle(color: AppColors.teal)),
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
                ));
      }),
    );
  }
}
