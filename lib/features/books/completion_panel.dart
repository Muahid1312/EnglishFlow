export '../courses/course_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/content/assessment_bank.dart';
import '../../core/services/certificate_service.dart';
import '../../core/services/course_study_service.dart';
import '../../core/services/providers.dart';
import '../../core/widgets/common_widgets.dart';

class CompletionPanel extends ConsumerStatefulWidget {
  const CompletionPanel({super.key, required this.type, required this.id});
  final String type;
  final String id;
  @override
  ConsumerState<CompletionPanel> createState() => _CompletionPanelState();
}

class _CompletionPanelState extends ConsumerState<CompletionPanel> {
  List<Map<String, dynamic>> _assessments = [];
  List<String> _required = [];
  bool _busy = false;
  Map<String, bool> _passes = {};
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = ref.read(appDatabaseProvider);
      await AssessmentBank.seedIfEmpty(db);
      final assessments = await db.getAssessments();
      final required =
          await db.getCompletionRequirements(widget.type, widget.id);
      final d = await db.db;
      final passes = <String, bool>{
        for (final id in required)
          id: CourseStudyService.passingScore(d, id, 0) != null
      };
      if (mounted) {
        setState(() {
          _passes = passes;
          _assessments = assessments;
          _required = required;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load completion requirements.');
      }
    }
  }

  Future<void> _configure() async {
    final selected = _required.toSet();
    final ok = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: const Text('Required assessments'),
                    content: SizedBox(
                        width: 400,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              const Text(
                                  'Certificates require every lesson and all selected assessments. Select at least one assessment.'),
                              for (final a in _assessments)
                                CheckboxListTile(
                                    title: Text(a['title'] as String),
                                    value: selected.contains(a['id']),
                                    onChanged: (value) => update(() {
                                          if (value == true) {
                                            selected.add(a['id'] as String);
                                          } else {
                                            selected.remove(a['id']);
                                          }
                                        })),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: selected.isEmpty
                              ? null
                              : () => Navigator.pop(context, true),
                          child: const Text('Save requirements'))
                    ])));
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(appDatabaseProvider)
          .setCompletionRequirements(widget.type, widget.id, selected.toList());
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save requirements.');
    }
  }

  Future<void> _issue() async {
    if (_busy) return;
    setState(() => _busy = true);
    final db = ref.read(appDatabaseProvider);
    try {
      final prefs = await db.getPreferences();
      await CertificateService(db).issue(
          learnerName: prefs.displayName ?? 'Learner',
          targetType: widget.type,
          targetId: widget.id,
          targetTitle: '',
          verificationType: '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Certificate saved. Open Progress → Certificates to share it.')));
      }
    } on StateError {
      if (mounted) {
        setState(() => _error =
            'Finish every lesson and pass all required assessments before issuing a certificate.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not generate certificate. Check available storage.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LexiCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: 'Completion requirements'),
        const Text(
            'Every lesson must be complete and every required assessment must have a saved passing result.'),
        TextButton(
            onPressed: _busy ? null : _configure,
            child: const Text('Choose required assessments')),
        if (_required.isEmpty)
          const Text(
              'Requirements are not configured. Certificates are unavailable.'),
        for (final a in _assessments.where((a) => _required.contains(a['id'])))
          TextButton(
              onPressed: () => context.push('/progress/assessments/${a['id']}'),
              child: Text(
                  '${a['title']} · ${_passes[a['id']] == true ? 'Keyed pass saved' : 'Pass required'}')),
        PrimaryButton(
            label: _busy ? 'Generating…' : 'Issue certificate if eligible',
            onPressed: _busy ? null : _issue),
        if (_error != null)
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]));
}
