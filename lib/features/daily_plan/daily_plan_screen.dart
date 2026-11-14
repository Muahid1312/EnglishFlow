import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/services/providers.dart';
import '../../core/services/builtin_content_service.dart';
import '../../core/utils/date_utils.dart';
import '../../core/widgets/common_widgets.dart';
import '../dashboard/dashboard_provider.dart';

class DailyPlanScreen extends ConsumerStatefulWidget {
  const DailyPlanScreen({super.key});
  @override
  ConsumerState<DailyPlanScreen> createState() => _DailyPlanScreenState();
}

class _DailyPlanScreenState extends ConsumerState<DailyPlanScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>>? _activities;
  List<Map<String, dynamic>> _history = [];
  String _date = localDateString();
  String _observedToday = localDateString();
  int _goal = 30;
  int _daySeconds = 0;
  String? _error;
  bool _busy = false;
  Timer? _dayTimer;
  Map<String,dynamic>? _dailyArticle;
  int _dailyWordCount=0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _dayTimer = Timer.periodic(const Duration(seconds:30), (_) {
      if (_observedToday != localDateString()) {
        _observedToday = localDateString();
        _load();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state==AppLifecycleState.resumed) _load();
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _load({int? goal, String? date}) async {
    try {
      final service = ref.read(dailyPlanServiceProvider);
      final activities = date == null ? await service.today(goal:goal) : await service.activities(date);
      final history = await service.history();
      final selected = date ?? localDateString();
      final plan = history.singleWhere((p) => p['local_date']==selected);
      final seconds = await ref.read(appDatabaseProvider).getTotalSecondsForDate(selected);
      final library=BuiltinContentService(ref.read(appDatabaseProvider));
      final prefs=await ref.read(appDatabaseProvider).getPreferences();
      final article=selected==localDateString()?await library.nextArticle(prefs.englishLevel=='B2'?'B2':'B1'):null;
      final words=selected==localDateString()?await library.recommendedWords(level:prefs.englishLevel,count:10):<Map<String,dynamic>>[];
      if (mounted) setState(() {
        _dailyArticle=article;_dailyWordCount=words.length;
        _activities = activities;
        _date = selected;
        _goal = plan['goal_minutes'] as int;
        _history = history;
        _daySeconds = seconds;
        _error = null;
      });
      ref.invalidate(dashboardProvider);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the plan. Your existing records have been kept.');
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy=true);
    try {
      await action();
      if (mounted) await _load(date:_date);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$error')));
    } finally {
      if (mounted) setState(() => _busy=false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(studySessionServiceProvider);
    final activities = _activities;
    final isToday = _date==localDateString();
    return Scaffold(
      appBar: AppBar(title:const Text('Daily learning plan')),
      body: activities==null ? (_error!=null ? ErrorView(message:_error!,onRetry:_load) : const LoadingView()) :
      RefreshIndicator(onRefresh:() => _load(date:isToday ? null : _date), child:ListView(
        padding:const EdgeInsets.all(20),
        children:[
          if(isToday)LexiCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Daily offline content'),
            if(_dailyArticle!=null)TextButton(onPressed:()=>context.push('/learn/reading/${Uri.encodeComponent('builtin:${_dailyArticle!['id']}')}'),child:Text('${_dailyArticle!['title']} · reading + 4-question challenge')),
            if(_dailyWordCount>0)TextButton(onPressed:()=>context.push('/learn/vocabulary/library?daily=true'),child:Text('$_dailyWordCount vocabulary entries selected for today')),
            TextButton(onPressed:()=>context.push('/learn/vocabulary'),child:const Text('Review due personal cards')),
            const Text('Optional recommendations do not add study minutes or completion records.'),
          ])),
          Text(DateFormat('EEEE, MMMM d, y').format(parseLocalDate(_date)),style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:12),
          if (isToday) Wrap(spacing:8,children:[for(final minutes in [15,30,60])
            ChoiceChip(label:Text('$minutes min'),selected:_goal==minutes,
              onSelected:_busy ? null : (_) => _action(() => _load(goal:minutes))),
          ]),
          const SizedBox(height:12),
          LexiCard(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('${activities.fold<int>(0,(n,a)=>n+(a['minutes'] as int))} min planned · $_goal min goal',style:Theme.of(context).textTheme.titleMedium),
            const SizedBox(height:8),
            Text('${_daySeconds~/60} completed study minutes ${isToday ? 'today' : 'on this date'} · ${activities.where((a)=>!['completed','skipped'].contains(a['state'])).length} activities remaining'),
            const SizedBox(height:8),
            const Text('Minutes come from the study timer, not completion checkboxes. Pause whenever you take a break.'),
          ])),
          const SizedBox(height:16),
          if (_error!=null) Text(_error!),
          if (activities.isEmpty) const Text('No activities are available. Import an article or audio lesson, or create a writing entry from Learn.'),
          for(final a in activities) Padding(padding:const EdgeInsets.only(bottom:12),child:LexiCard(
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(a['title'] as String,style:Theme.of(context).textTheme.titleMedium),
              const SizedBox(height:4),
              Text('${a['minutes']} min · ${a['state']} · ${(a['actual_ms'] as int)~/60000} min tracked'),
              const SizedBox(height:6),
              Text(a['reason'] as String),
              if (isToday && !['completed','skipped'].contains(a['state'])) ...[
                const SizedBox(height:10),
                Wrap(spacing:8,runSpacing:4,children:[
                  FilledButton.icon(icon:const Icon(Icons.play_arrow),label:Text(a['state']=='active' ? 'Continue' : 'Start'),
                    onPressed:_busy ? null : () => _action(() async {
                      await ref.read(dailyPlanServiceProvider).start(a['id'] as String);
                      if (!context.mounted) return;
                      try { await context.push(a['route'] as String); }
                      finally { await session.pause(); }
                    })),
                  OutlinedButton(onPressed:_busy ? null : () => _action(() => ref.read(dailyPlanServiceProvider).complete(a['id'] as String)),child:const Text('Finish')),
                  TextButton(onPressed:_busy ? null : () => _action(() => ref.read(dailyPlanServiceProvider).complete(a['id'] as String,skip:true)),child:const Text('Skip')),
                ]),
              ],
            ]),
          )),
          const SizedBox(height:8),
          const Text('For more variety, import articles, PDF books and audio from Learn. Recommendations use your local records; no AI is required.'),
          if (_history.length>1) ...[
            const SizedBox(height:24),
            const SectionHeader(title:'Plan history'),
            for(final day in _history) ListTile(
              title:Text(day['local_date'] as String),subtitle:Text('${day['goal_minutes']} min goal'),
              trailing:const Icon(Icons.chevron_right),onTap:_busy ? null : () => _load(date:day['local_date'] as String)),
            if (!isToday) TextButton(onPressed:() => _load(),child:const Text('Return to today')),
          ],
        ],
      )),
    );
  }
}
