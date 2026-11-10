import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

import '../../app/theme/app_theme.dart';
import '../../core/content/assessment_bank.dart';
import '../../core/services/certificate_service.dart';
import '../../core/services/providers.dart';
import '../../core/utils/id_utils.dart';
import '../../core/widgets/common_widgets.dart';

class AssessmentsScreen extends ConsumerStatefulWidget {
  const AssessmentsScreen({super.key});

  @override
  ConsumerState<AssessmentsScreen> createState() => _AssessmentsScreenState();
}

class _AssessmentsScreenState extends ConsumerState<AssessmentsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    await AssessmentBank.seedIfEmpty(db);
    final rows = await db.getAssessments();
    if (mounted)
      setState(() {
        _items = rows;
        _loading = false;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assessments')),
      body: _loading
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Practice assessments only. Results are not official CEFR certifications.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                ..._items.map((a) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ModuleTile(
                        icon: Icons.quiz_outlined,
                        title: '${a['title']}',
                        subtitle:
                            '${a['category']} · pass ≥ ${((a['pass_threshold'] as num?) ?? 0.7) * 100 ~/ 1}%',
                        onTap: () =>
                            context.push('/progress/assessments/${a['id']}'),
                      ),
                    )),
              ],
            ),
    );
  }
}

class AssessmentTakeScreen extends ConsumerStatefulWidget {
  final String assessmentId;
  const AssessmentTakeScreen({super.key, required this.assessmentId});

  @override
  ConsumerState<AssessmentTakeScreen> createState() =>
      _AssessmentTakeScreenState();
}

class _AssessmentTakeScreenState extends ConsumerState<AssessmentTakeScreen> {
  Map<String, dynamic>? _def;
  List<Map<String, dynamic>> _questions = [];
  final Map<String, String> _answers = {};
  bool _loading = true;
  bool _done = false;
  double? _score;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(appDatabaseProvider);
    final def = await db.getAssessment(widget.assessmentId);
    final qs = await db.getAssessmentQuestions(widget.assessmentId);
    if (mounted)
      setState(() {
        _def = def;
        _questions = qs;
        _loading = false;
      });
  }

  List<String> _choices(Map<String, dynamic> q) {
    final raw = q['choices'] as String?;
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List).map((e) => '$e').toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _submit() async {
    if (_questions.isEmpty) return;
    var correct = 0;
    for (final q in _questions) {
      final a = (_answers[q['id'] as String] ?? '').trim().toLowerCase();
      final c = ((q['correct_answer'] as String?) ?? '').trim().toLowerCase();
      if (a == c) correct++;
    }
    final score = correct / _questions.length;
    final threshold = (_def?['pass_threshold'] as num?)?.toDouble() ?? 0.7;
    final passed = score >= threshold;
    final started = DateTime.now().toUtc().toIso8601String();
    await ref.read(appDatabaseProvider).saveAssessmentAttempt({
      'id': newId(),
      'assessment_id': widget.assessmentId,
      'score': score,
      'max_score': 1.0,
      'passed': passed ? 1 : 0,
      'self_assessed': 0,
      'answers_json': jsonEncode(_answers),
      'started_at': started,
      'completed_at': started,
    });
    setState(() {
      _done = true;
      _score = score;
    });
  }

  Future<void> _maybeCertificate() async {
    if (_score == null || _def == null) return;
    final threshold = (_def!['pass_threshold'] as num?)?.toDouble() ?? 0.7;
    if (_score! < threshold) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Score below threshold — not eligible for a certificate.')));
      return;
    }
    final prefs = await ref.read(appDatabaseProvider).getPreferences();
    final path = await CertificateService(ref.read(appDatabaseProvider)).issue(
      learnerName: prefs.displayName ?? 'Learner',
      targetType: 'assessment',
      targetId: widget.assessmentId,
      targetTitle: '${_def!['title']}',
      verificationType: 'assessment_pass',
      assessmentScore: _score,
      eligible: true,
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Certificate saved: $path')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    if (_def == null)
      return Scaffold(
          appBar: AppBar(),
          body: const ErrorView(message: 'Assessment not found'));

    if (_done) {
      return Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Score: ${((_score ?? 0) * 100).round()}%',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('Practice result only — not an accredited CEFR exam.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 20),
              PrimaryButton(
                  label: 'Issue certificate if eligible',
                  onPressed: _maybeCertificate),
              const SizedBox(height: 12),
              SecondaryButton(label: 'Back', onPressed: () => context.pop()),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('${_def!['title']}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final q in _questions) ...[
            LexiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${q['prompt']}',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ..._choices(q).map((c) => RadioListTile<String>(
                        title: Text(c),
                        value: c,
                        groupValue: _answers[q['id'] as String],
                        onChanged: (v) => setState(
                            () => _answers[q['id'] as String] = v ?? ''),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          PrimaryButton(label: 'Submit', onPressed: _submit),
        ],
      ),
    );
  }
}

class CertificatesScreen extends ConsumerStatefulWidget {
  const CertificatesScreen({super.key});

  @override
  ConsumerState<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends ConsumerState<CertificatesScreen> {
  List<Map<String, dynamic>> _certs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref.read(appDatabaseProvider).getCertificates();
    if (mounted) setState(() => _certs = rows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Certificates')),
      body: _certs.isEmpty
          ? const EmptyState(
              icon: Icons.workspace_premium_outlined,
              title: 'No certificates yet',
              message:
                  'Pass an eligible assessment or complete a structured course requirement to generate one.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: _certs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final c = _certs[i];
                return LexiCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${c['title']}',
                          style: Theme.of(context).textTheme.titleSmall),
                      Text('${c['learner_name']} · ${c['ref_number']}',
                          style: Theme.of(context).textTheme.bodySmall),
                      Text('Verification: ${c['verification_type']}',
                          style: Theme.of(context).textTheme.bodySmall),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            final path = c['file_path'] as String?;
                            if (path != null)
                              Share.shareXFiles([XFile(path)],
                                  text:
                                      'LexiFlow certificate ${c['ref_number']}');
                          },
                          child: const Text('Share PDF'),
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

class ExportScreen extends ConsumerWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export data')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Exports study sessions, grammar attempts, writing metadata, and completions as JSON. API keys are never included.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Generate & share JSON',
              onPressed: () async {
                final db = ref.read(appDatabaseProvider);
                final sessions = await db.getCompletedStudyDates();
                final payload = {
                  'exported_at': DateTime.now().toUtc().toIso8601String(),
                  'schema': 'lexiflow-export-v1',
                  'completed_study_dates': sessions,
                  'total_study_seconds': await db.getTotalStudySeconds(),
                  'grammar_completed': await db.countCompletedGrammarLessons(),
                  'writing_entries': await db.countWritingEntries(),
                  'note':
                      'Does not include API credentials or full writing body by default.',
                };
                await Share.share(
                    const JsonEncoder.withIndent('  ').convert(payload),
                    subject: 'LexiFlow export');
              },
            ),
          ],
        ),
      ),
    );
  }
}
