import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/content/assessment_bank.dart';
import '../../core/services/certificate_service.dart';
import '../../core/services/providers.dart';
import '../../core/utils/id_utils.dart';
import '../../core/services/assessment_grading.dart';
import '../../core/widgets/common_widgets.dart';

class AssessmentsScreen extends ConsumerStatefulWidget {
  const AssessmentsScreen({super.key});

  @override
  ConsumerState<AssessmentsScreen> createState() => _AssessmentsScreenState();
}

class _AssessmentsScreenState extends ConsumerState<AssessmentsScreen> {
  String? _loadError;

  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _loadError=null;
      final db = ref.read(appDatabaseProvider);
      await AssessmentBank.seedIfEmpty(db);
      final rows = await db.getAssessments();
      if (mounted) {
        setState(() {
          _items = rows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loadError='Could not load learning records. Check storage and retry.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if(_loadError!=null)return Scaffold(appBar:AppBar(title:const Text('Learning records')),body:ErrorView(message:_loadError!,onRetry:_load));
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
  String? _loadError;

  Map<String, dynamic>? _def;
  List<Map<String, dynamic>> _questions = [];
  final Map<String, String> _answers = {};
  bool _loading = true;
  bool _done = false;
  bool _submitting = false;
  final _startedAt = DateTime.now().toUtc().toIso8601String();
  double? _score;
  bool _selfReviewed = false;
  final _attemptId = newId();
  List<Map<String,dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _loadError=null;
      final db = ref.read(appDatabaseProvider);
      final def = await db.getAssessment(widget.assessmentId);
      final qs = await db.getAssessmentQuestions(widget.assessmentId);
      final history = (await db.db).select('SELECT * FROM assessment_attempts WHERE assessment_id=? ORDER BY completed_at DESC LIMIT 20', [widget.assessmentId]);
      if (mounted) {
        setState(() {
          _history = history;
          _def = def;
          _questions = qs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loadError='Could not load learning records. Check storage and retry.'; });
    }
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
    if (_questions.isEmpty || _done || _submitting) return;
    setState(() => _submitting = true);
    try {
      final grade=gradeAssessment(_questions,_answers,writingReviewed:_selfReviewed);
      final hasOpen=grade.hasWriting;
      final score=grade.score;
      final threshold=(_def?['pass_threshold'] as num?)?.toDouble()??0.7;
      final passed=grade.passes(threshold);
      final started = DateTime.now().toUtc().toIso8601String();
      await ref.read(appDatabaseProvider).saveAssessmentAttempt({
        'id': _attemptId,
        'assessment_id': widget.assessmentId,
        'score': score,
        'max_score': 1.0,
        'passed': passed ? 1 : 0,
        'self_assessed': grade.objectiveCount==0 ? 1 : 0,
        'answers_json': jsonEncode({..._answers, if(hasOpen) '_writing_self_assessed': true}),
        'started_at': _startedAt,
        'completed_at': started,
      });
      if (!mounted) return;
      setState(() {
        _done = true;
        _submitting = false;
        _score = score;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Could not save assessment. ${error is StateError?error.message:'Check storage and retry.'} Your answers are retained.')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool _issuing = false;

  Future<void> _maybeCertificate() async {
    if (_issuing) return;
    _issuing = true;
    try {
      await _issueCertificate();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Certificate could not be saved. Check eligibility and storage.')));
      }
    } finally {
      _issuing = false;
    }
  }

  Future<void> _issueCertificate() async {
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
    if(_loadError!=null)return Scaffold(appBar:AppBar(title:const Text('Learning records')),body:ErrorView(message:_loadError!,onRetry:_load));
    if (_loading) return const Scaffold(body: LoadingView());
    if (_def == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const ErrorView(message: 'Assessment not found'));
    }

    if (_done) {
      return Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_score==null?'Writing self-assessment saved; no objective score.':'Objective score: ${(_score! * 100).round()}%',
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('Practice result only — not an accredited CEFR exam.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 20),
              PrimaryButton(
                  label: 'Issue certificate if eligible',
                  onPressed: _score==null?null:_maybeCertificate),
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
                  if (_choices(q).isEmpty) TextFormField(initialValue:_answers[q['id']], maxLines:q['question_type']=='short'?4:1, decoration:const InputDecoration(labelText:'Your answer'), onChanged:(v)=>_answers[q['id'] as String]=v),
                  if(q['question_type']=='short') Text('Self-assessment rubric: ${q['explanation']??'Review clarity, grammar and task coverage.'}'),
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
          if(_questions.any((q)=>q['question_type']=='short'||q['question_type']=='writing')) CheckboxListTile(title:const Text('I reviewed my writing against the rubric (self-assessment only)'),value:_selfReviewed,onChanged:(v)=>setState(()=>_selfReviewed=v==true)),
          const Text('Objective score uses only questions with stored answer keys. Open writing is self-assessed.'),
          for(final attempt in _history) Text('Previous attempt: ${attempt['completed_at']} · objective score ${attempt['score']} · ${attempt['passed']==1?'Passed':'Not passed / self-assessed'}'),
          PrimaryButton(
              label: 'Submit', onPressed: _submitting ? null : _submit),
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
  String? _loadError;

  List<Map<String, dynamic>> _certs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _loadError=null;
      final rows = await ref.read(appDatabaseProvider).getCertificates();
      if (mounted) setState(() => _certs = rows);
    } catch (_) {
      if (mounted) setState(() { _loadError='Could not load learning records. Check storage and retry.'; });
    }
  }

  Future<void> _export(Map<String,dynamic> record,String action) async {
    try {
      final bytes=await CertificateService.historicalPdf(record);
      final filename='${record['ref_number']}.pdf';
      if(action=='preview') { await Printing.layoutPdf(onLayout:(_)async=>bytes,name:filename); }
      else if(action=='save') { await FilePicker.platform.saveFile(dialogTitle:'Save certificate PDF',fileName:filename,bytes:bytes,type:FileType.custom,allowedExtensions:['pdf']); }
      else { await Printing.sharePdf(bytes:bytes,filename:filename); }
    } catch (_) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not export certificate. Please check storage and try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if(_loadError!=null)return Scaffold(appBar:AppBar(title:const Text('Learning records')),body:ErrorView(message:_loadError!,onRetry:_load));
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
                      Wrap(children:[
                        TextButton(onPressed:()=>_export(c,'preview'),child:const Text('Preview / print')),
                        TextButton(onPressed:()=>_export(c,'save'),child:const Text('Save PDF')),
                        TextButton(onPressed:()=>_export(c,'share'),child:const Text('Share PDF')),
                      ]),
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
              'Shares a JSON summary of study dates, total study time, completed grammar lessons, and writing counts. API keys and writing text are excluded.',
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
