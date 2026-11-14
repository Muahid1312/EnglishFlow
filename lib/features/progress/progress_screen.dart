import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/analytics_service.dart';
import '../../core/services/providers.dart';
import '../../core/widgets/common_widgets.dart';

class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});

  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  ProgressSnapshot? _snap;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap=await AnalyticsService(ref.read(appDatabaseProvider)).build();
      if(mounted)setState((){_snap=snap;_loading=false;_error=null;});
    } catch (_) {
      if(mounted)setState((){_error='Could not load progress. Your learning records have not been changed.';_loading=false;});
    }
  }

  @override
  Widget build(BuildContext context) {
    if(_error!=null)return Scaffold(appBar:AppBar(title:const Text('Progress')),body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[Text(_error!),TextButton(onPressed:_load,child:const Text('Retry'))])));
    if (_loading || _snap == null) {
      return const Scaffold(body: LoadingView(message: 'Loading progress…'));
    }
    final s = _snap!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Progress'),
        actions: [
          IconButton(
            tooltip: 'Assessments',
            onPressed: () => context.push('/progress/assessments'),
            icon: const Icon(Icons.quiz_outlined),
          ),
          IconButton(
            tooltip: 'Certificates',
            onPressed: () => context.push('/progress/certificates'),
            icon: const Icon(Icons.workspace_premium_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            LexiCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text('${s.streak}',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          color: AppColors.violet,
                          fontWeight: FontWeight.w700)),
                  const Text('Day streak'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _kv('Today', '${s.todayMinutes} min'),
                      _kv('7 days', '${s.weekMinutes} min'),
                      _kv('Total', '${s.totalMinutes} min'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionHeader(title: '7-day activity (real sessions)'),
            LexiCard(
              child: s.last7Days.isEmpty
                  ? Text('No completed sessions in the last 7 days.',
                      style: Theme.of(context).textTheme.bodySmall)
                  : Column(
                      children: s.last7Days.map((r) {
                        final mins = ((r['total_seconds'] as int?) ?? 0) ~/ 60;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              SizedBox(
                                  width: 100,
                                  child: Text('${r['local_date']}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall)),
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: (mins / 60).clamp(0.0, 1.0),
                                  minHeight: 8,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('$mins m',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            const SizedBox(height: 16),
            const SectionHeader(title:'Skills · observed learning activity'),
            const Text('These metrics describe saved activity, not a validated CEFR level. Objective percentages need at least 5 answers.'),
            for(final entry in s.skills.entries) LexiCard(child:ListTile(title:Text(entry.key),subtitle:Text(entry.value))),
            const SizedBox(height: 20),
            const SectionHeader(title: 'Recommendations'),
            if (s.insights.isEmpty)
              Text('Keep practicing — no urgent recommendations right now.',
                  style: Theme.of(context).textTheme.bodyMedium)
            else
              ...s.insights.map((i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: LexiCard(
                      onTap: () => context.push(i.route),
                      child: Row(
                        children: [
                          const Icon(Icons.lightbulb_outline,
                              color: AppColors.warning),
                          const SizedBox(width: 12),
                          Expanded(child: Text(i.message)),
                          Flexible(child:Text(i.actionLabel,
                              style: const TextStyle(
                                  color: AppColors.violet,
                                  fontWeight: FontWeight.w600))),
                        ],
                      ),
                    ),
                  )),
            const SizedBox(height: 16),
            SecondaryButton(
              label: 'Export learning data (JSON)',
              onPressed: () => context.push('/progress/export'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
        children: [
          Text(v,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          Text(k, style: const TextStyle(fontSize: 12)),
        ],
      );

  Widget _chip(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleMedium),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}
