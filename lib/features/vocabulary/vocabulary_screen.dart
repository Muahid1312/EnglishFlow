import '../../core/widgets/ai_help_button.dart';
import '../../core/services/ai_teacher_service.dart';
import 'dart:convert';
import 'dart:async';
import 'word_editor.dart';
import 'word_detail_screen.dart';
import 'vocabulary_challenge_screen.dart';
import '../../core/services/vocabulary_intelligence.dart';
import '../../core/services/practice_timer.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_theme.dart';
import '../../core/database/app_database.dart';
import '../../core/services/providers.dart';
import '../../core/services/review_schedule.dart';
import '../../core/widgets/common_widgets.dart';
import '../dashboard/dashboard_provider.dart';

class VocabularyScreen extends ConsumerStatefulWidget {
  const VocabularyScreen({super.key});
  @override
  ConsumerState<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends ConsumerState<VocabularyScreen> {
  List<Map<String, dynamic>> _words = [];
  int _due = 0;
  bool _unfinished=false;
  int _limit=5;
  String _query='';
  int _total=0,_visibleLimit=100,_loadVersion=0;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final version=++_loadVersion;
    try {
      final db = ref.read(appDatabaseProvider);
      final words = await db.getVocabulary(search:_query,limit:_visibleLimit);
      final total=await db.getSavedWordCount();
      final due = await db.getDueReviewCount();
      final unfinished=(await db.db).select("SELECT id FROM vocabulary_practice_sessions WHERE state IN ('active','paused') LIMIT 1").isNotEmpty;
      if (mounted && version==_loadVersion) {
        setState(() {
          _total=total;
          _unfinished=unfinished;
          _words = words;
          _due = due;
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && version==_loadVersion) {
        setState(() {
          _error = 'Could not load vocabulary.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit([Map<String, dynamic>? entry]) async {
    final db = ref.read(appDatabaseProvider);
    await showDialog<bool>(
        context: context, builder: (_) => WordEditorDialog(db: db, entry: entry));
    if (!mounted) return;
    ref.invalidate(dashboardProvider);
    await _load();
  }

  Future<void> _review({bool fresh=false}) async {
    final db = ref.read(appDatabaseProvider);
    await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => FlashcardReviewScreen(db: db,limit:_limit,fresh:fresh)));
    if (!mounted) return;
    ref.invalidate(dashboardProvider);
    await _load();
  }

  Future<void> _history(Map<String, dynamic> word) async {
    final rows = await ref
        .read(appDatabaseProvider)
        .getReviewHistory(word['id'] as String,limit:50);
    if (!mounted) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.65,
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Text('Review history: ${word['word']}',
                      style: Theme.of(context).textTheme.titleLarge),
                  if (rows.isEmpty) const Text('No reviews yet.'),
                  if(rows.length>=50)const Text('Showing the latest 50 reviews. Complete history is retained.'),
                  for (final r in rows)
                    ListTile(
                        title: Text('${r['rating']} · ${r['reviewed_at']}'),
                        subtitle: Text('Next review: ${r['next_due']}')),
                ]))));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Vocabulary'), actions: [
          IconButton(
              tooltip: 'Add word',
              onPressed: () => _edit(),
              icon: const Icon(Icons.add))
        ]),
        body: _loading
            ? const LoadingView()
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(padding: const EdgeInsets.all(20), children: [
                  Row(children: [
                    Expanded(
                        child: LexiCard(
                            child: Column(children: [
                      Text('$_total',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: AppColors.violet)),
                      const Text('Saved words')
                    ]))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: LexiCard(
                            child: Column(children: [
                      Text('$_due',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(color: AppColors.teal)),
                      const Text('Due reviews')
                    ])))
                  ]),
                  const SizedBox(height: 20),
                  if (_error != null) ErrorView(message: _error!),
                  TextField(decoration:const InputDecoration(labelText:'Search saved words',prefixIcon:Icon(Icons.search)),
                    onChanged:(value){_query=value.trim();_visibleLimit=100;_load();}),
                  const SizedBox(height:12),
                  Wrap(spacing:8,children:[for(final size in [5,10,15,0]) ChoiceChip(
                    label:Text(size==0?'All due':'$size words'),selected:_limit==size,onSelected:(_)=>setState(()=>_limit=size))]),
                  TextButton(onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const VocabularyChallengeScreen())),child:const Text('Vocabulary challenges & insights')),
                  if (_due > 0)
                    PrimaryButton(
                        label: 'Start review',
                        icon: Icons.replay,
                        onPressed: ()=>_review(fresh:true)),
                  if(_unfinished) TextButton(onPressed:()=>_review(),child:const Text('Continue unfinished review')),
                  if (_words.isEmpty)
                    const EmptyState(
                        icon: Icons.style_outlined,
                        title: 'No saved words',
                        message:
                            'Add a word or save a selection while reading. Meanings and translations are entered by you; they are not invented offline.'),
                  if(_words.length>=_visibleLimit) TextButton(onPressed:(){_visibleLimit+=100;_load();},child:const Text('Load more saved words')),
                  for (final word in _words)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: LexiCard(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Expanded(
                                    child: InkWell(onTap:() async {
                                      await Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>WordDetailScreen(entryId:word['id'] as String)));
                                      if(mounted) await _load();
                                    },child: Text(word['word'] as String,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium))),
                                IconButton(
                                    tooltip: 'Review history',
                                    onPressed: () => _history(word),
                                    icon: const Icon(Icons.history)),
                                IconButton(
                                    tooltip: 'Edit word',
                                    onPressed: () => _edit(word),
                                    icon: const Icon(Icons.edit_outlined))
                              ]),
                              AiHelpButton(
                                  task: AiTask.vocabulary,
                                  label: 'Explain with AI',
                                  content: () =>
                                      '${word['word']}\n${word['contexts_json']}'),
                              if ((word['definition'] as String?)?.isNotEmpty ==
                                  true)
                                Text(word['definition'] as String),
                              if ((word['translation'] as String?)
                                      ?.isNotEmpty ==
                                  true)
                                Text(word['translation'] as String),
                              for (final item
                                  in jsonDecode(word['contexts_json'] as String)
                                      as List)
                                Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                        '“${item['sentence']}”\n${item['source'] ?? 'Source'}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall)),
                            ]))),
                ])),
      );
}

class FlashcardReviewScreen extends ConsumerStatefulWidget {
  const FlashcardReviewScreen({super.key,required this.db,this.limit=5,this.entryId,this.fresh=false});
  final AppDatabase db;
  final int limit;
  final String? entryId;
  final bool fresh;
  @override
  ConsumerState<FlashcardReviewScreen> createState()=>_FlashcardReviewScreenState();
}
class _FlashcardReviewScreenState extends ConsumerState<FlashcardReviewScreen> with WidgetsBindingObserver {
  late final VocabularyIntelligence _service;
  String? _session;
  List<Map<String,dynamic>>? _items;
  String? _error;
  bool _paused=false,_saving=false;
  late final PracticeTimer _timing;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service=VocabularyIntelligence(widget.db);
    _timing=PracticeTimer(ref.read(studySessionServiceProvider),'vocabulary');
    _load();
  }
  Future<void> _load() async {
    try {
      _session ??= await _service.open(limit:widget.limit,entryId:widget.entryId,fresh:widget.fresh);
      final rows=await _service.items(_session!);
      final paused=await _service.state(_session!)=='paused';
      if(!mounted) return;
      setState(() { _items=rows; _paused=paused; _error=null; });
      if(!paused && rows.any((r)=>r['item_state']=='pending')) await _timer();
    } catch(e) { if(mounted) setState(()=>_error=e is StateError?e.message.toString():'Could not load review cards.'); }
  }
  Future<void> _timer() async {
    await _timing.start();
    if(!mounted)await _timing.pause();
  }
  Future<void> _pause({bool resume=false}) async {
    if(_session==null) return;
    if(!resume) {
      // Block grading immediately, including while the checkpoint awaits IO.
      if(mounted) setState(()=>_paused=true);
      await _service.pause(_session!);
      await _timing.pause();
    } else {
      await _timer();
      await _service.pause(_session!,resume:true);
      if(mounted) setState(()=>_paused=false);
    }
  }
  Future<void> _rate(Map<String,dynamic> card,ReviewRating rating) async {
    if(_saving || _paused) return;
    setState(()=>_saving=true);
    try {
      await _service.rate(_session!,card,rating);
      final rows=await _service.items(_session!);
      if(mounted) setState(() { _items=rows; _error=null; });
      if(rows.every((r)=>r['item_state']!='pending')) {
        await _timing.finish();
        ref.invalidate(dashboardProvider);
      }
    } catch(e) { if(mounted) setState(()=>_error=e is StateError?e.message.toString():'Could not save review. Retry safely.'); }
    finally { if(mounted) setState(()=>_saving=false); }
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if(state==AppLifecycleState.paused || state==AppLifecycleState.inactive) {
      unawaited(_pause().catchError((Object _) {}));
    }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final id=_session;
    if(id!=null) unawaited(_service.pause(id).catchError((Object _) {}));
    unawaited(_timing.pause().catchError((Object _) {}));
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    ref.watch(studySessionServiceProvider.select((s)=>(s.active?.id,s.isRunning)));
    final paused=_paused || (_timing.id!=null && (_timing.sessions.active?.id!=_timing.id || !_timing.sessions.isRunning));
    final pending=_items?.where((r)=>r['item_state']=='pending').toList();
    final remaining=pending?.length ?? 0;
    final card=pending==null || pending.isEmpty?null:pending.first;
    return Scaffold(appBar:AppBar(title:const Text('Flashcards')),
      body:Padding(padding:const EdgeInsets.all(20),child:_items==null?
        (_error==null?const LoadingView():ErrorView(message:_error!,onRetry:_load)):
        card==null?ListView(children:[
          const Icon(Icons.check_circle_outline,size:48),
          const Text('Reviews saved',style:TextStyle(fontSize:24)),
          Text('${_items!.where((r)=>r['item_state']=='reviewed').length} rated · ${_items!.where((r)=>r['item_state']=='skipped').length} unavailable or already reviewed'),
          for(final rating in ReviewRating.values) Text('${rating.name}: ${_items!.where((r)=>r['rating']==rating.name).length}'),
          const Text('Your review history and next review dates are stored offline.'),
          if(_error!=null) Text(_error!),
          if(_timing.sessions.hasActive) const Text('The shared study timer is paused. Finish your active study activity to include its minutes in completed-day progress.'),
        ]):ListView(children:[
          Text('${_items!.length-remaining} of ${_items!.length} finished'),
          LinearProgressIndicator(value:(_items!.length-remaining)/_items!.length),
          const SizedBox(height:20),
          LexiCard(child:Column(children:[
            Text(card['word'] as String,style:Theme.of(context).textTheme.headlineMedium),
            if(card['revealed']==1) ...[
              const SizedBox(height:16),
              Text((card['definition'] as String?)?.isNotEmpty==true?card['definition'] as String:'No definition added.'),
              if((card['translation'] as String?)?.isNotEmpty==true) Text(card['translation'] as String),
              for(final context in jsonDecode(card['contexts_json'] as String) as List) Text('“${context['sentence']}”'),
            ],
          ])),
          const SizedBox(height:16),
          if(paused) FilledButton(onPressed:_saving?null:()=>_pause(resume:true),child:const Text('Resume review'))
          else ...[
            TextButton(onPressed:_saving?null:()=>_pause(),child:const Text('Pause review')),
            if(card['revealed']!=1) PrimaryButton(label:'Show answer',onPressed:() async {
              await _service.reveal(_session!,card['position'] as int);
              final rows=await _service.items(_session!);
              if(mounted) setState(()=>_items=rows);
            }) else Wrap(spacing:8,runSpacing:8,children:[for(final rating in ReviewRating.values)
              OutlinedButton(onPressed:_saving?null:()=>_rate(card,rating),child:Text(switch(rating) {
                ReviewRating.again=>'Again',ReviewRating.hard=>'Hard',ReviewRating.good=>'Good',ReviewRating.easy=>'Easy'}))]),
          ],
          if(_error!=null) Text(_error!),
        ])));
  }
}
