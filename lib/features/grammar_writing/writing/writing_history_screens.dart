import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/id_utils.dart';
import '../../../core/widgets/common_widgets.dart';

class MistakeEditorDialog extends StatefulWidget {
  const MistakeEditorDialog({super.key, required this.db, this.mistake});
  final AppDatabase db;
  final Map<String, dynamic>? mistake;
  @override
  State<MistakeEditorDialog> createState() => _MistakeEditorDialogState();
}

class _MistakeEditorDialogState extends State<MistakeEditorDialog> {
  final _original = TextEditingController(),
      _correction = TextEditingController(),
      _explanation = TextEditingController(),
      _category = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final m = widget.mistake;
    _original.text = m?['original_sentence'] as String? ?? '';
    _correction.text = m?['correction'] as String? ?? '';
    _explanation.text = m?['explanation'] as String? ?? '';
    _category.text = m?['grammar_topic'] as String? ?? 'general';
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.db.saveWritingMistake({
        'id': widget.mistake?['id'] ?? newId(),
        'entry_id': widget.mistake?['entry_id'],
        'original_sentence': _original.text,
        'correction': _correction.text,
        'explanation': _explanation.text.trim(),
        'grammar_topic':
            _category.text.trim().isEmpty ? 'general' : _category.text.trim(),
        'review_status': widget.mistake?['review_status'] ?? 'open'
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is ArgumentError
            ? error.message.toString()
            : 'Could not save mistake.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _original.dispose();
    _correction.dispose();
    _explanation.dispose();
    _category.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.mistake == null ? 'New mistake' : 'Edit mistake'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: _original,
                decoration:
                    const InputDecoration(labelText: 'Original sentence'),
                maxLines: 3),
            TextField(
                controller: _correction,
                decoration:
                    const InputDecoration(labelText: 'Corrected sentence'),
                maxLines: 3),
            TextField(
                controller: _explanation,
                decoration:
                    const InputDecoration(labelText: 'Explanation (optional)'),
                maxLines: 3),
            TextField(
                controller: _category,
                decoration:
                    const InputDecoration(labelText: 'Grammar category')),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ])),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Save mistake'))
          ]);
}

class RevisionLabelDialog extends StatefulWidget {
  const RevisionLabelDialog({super.key});
  @override
  State<RevisionLabelDialog> createState() => _RevisionLabelDialogState();
}

class _RevisionLabelDialogState extends State<RevisionLabelDialog> {
  final _label = TextEditingController(text: 'Manual snapshot');
  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Save revision'),
          content: TextField(
              controller: _label,
              decoration: const InputDecoration(
                  labelText: 'Revision label (optional)')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, _label.text.trim()),
                child: const Text('Save revision'))
          ]);
}

class RevisionHistoryScreen extends StatefulWidget {
  const RevisionHistoryScreen(
      {super.key, required this.db, required this.entryId});
  final AppDatabase db;
  final String entryId;
  @override
  State<RevisionHistoryScreen> createState() => _RevisionHistoryScreenState();
}

class _RevisionHistoryScreenState extends State<RevisionHistoryScreen> {
  List<Map<String, dynamic>>? _revisions;
  Map<String, dynamic>? _entry;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final entry = await widget.db.getWritingEntry(widget.entryId);
      final revisions = await widget.db.getWritingRevisions(widget.entryId);
      if (mounted) {
        setState(() {
          _entry = entry;
          _revisions = revisions;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load revision history.');
    }
  }

  Future<void> _compare(Map<String, dynamic> revision) async {
    final restore = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Compare revision'),
                content: SizedBox(
                    width: 500,
                    child: SingleChildScrollView(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('Current draft',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          SelectableText(_entry?['body'] as String? ?? ''),
                          const Divider(),
                          Text('Selected revision · ${revision['created_at']}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          SelectableText(revision['body'] as String),
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Close')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Restore this revision'))
                ]));
    if (restore != true || !mounted) return;
    final confirmed = await showConfirmDialog(context,
        title: 'Restore revision?',
        message:
            'Your current draft will be preserved as a new revision before restoring. Historical revisions will not be overwritten.',
        confirmLabel: 'Restore');
    if (confirmed != true) return;
    try {
      await widget.db
          .restoreWritingRevision(widget.entryId, revision['id'] as String);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not restore revision. Current writing is unchanged.');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Revision history')),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _revisions == null
              ? const LoadingView()
              : ListView(padding: const EdgeInsets.all(20), children: [
                  if (_revisions!.isEmpty)
                    const EmptyState(
                        icon: Icons.history,
                        title: 'No revisions yet',
                        message:
                            'Save a snapshot from the editor. Autosave does not create duplicate revisions.'),
                  for (final r in _revisions!)
                    ListTile(
                        title: Text((r['label'] as String?)?.isNotEmpty == true
                            ? r['label'] as String
                            : 'Unlabeled revision'),
                        subtitle: Text(
                            '${r['created_at']} · ${r['word_count']} words'),
                        trailing: const Icon(Icons.compare_arrows),
                        onTap: () => _compare(r)),
                ]));
}
