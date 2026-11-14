import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/providers.dart';
import '../../features/dashboard/dashboard_provider.dart';

/// Controls remain reachable from every learning screen. Foreground inactivity
/// pauses after two minutes; reading can be resumed explicitly without counting
/// a long idle interval. Backgrounding is handled by the existing lifecycle hook.
class StudySessionDock extends ConsumerStatefulWidget {
  const StudySessionDock({super.key,required this.child});
  final Widget child;
  @override
  ConsumerState<StudySessionDock> createState()=>_StudySessionDockState();
}

class _StudySessionDockState extends ConsumerState<StudySessionDock> {
  Timer? _idle;
  String? _running;
  bool _busy=false;
  TextEditingController? _editing;
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_focusChanged);
  }
  void _focusChanged() {
    _editing?.removeListener(_touch);
    _editing=FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>()?.widget.controller;
    _editing?.addListener(_touch);
    _touch();
  }
  void _touch() {
    _idle?.cancel();
    if (ref.read(studySessionServiceProvider).isRunning) {
      _idle=Timer(const Duration(minutes:2),() async {
        try { await ref.read(studySessionServiceProvider).pause(); } catch (_) {}
      });
    }
  }
  @override
  void dispose() {
    _idle?.cancel();
    FocusManager.instance.removeListener(_focusChanged);
    _editing?.removeListener(_touch);
    super.dispose();
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(()=>_busy=true);
    try {
      final sessions=ref.read(studySessionServiceProvider);
      final active=sessions.active;
      if (active==null) return;
      final db=await ref.read(appDatabaseProvider).db;
      final linked=db.select('SELECT activity_id FROM plan_sessions WHERE session_id=?',[active.id]);
      if (linked.isEmpty) { await sessions.finish(); }
      else { await ref.read(dailyPlanServiceProvider).complete(linked.single['activity_id'] as String); }
      ref.invalidate(dashboardProvider);
    } finally { if (mounted) setState(()=>_busy=false); }
  }

  @override
  Widget build(BuildContext context) {
    final sessions=ref.watch(studySessionServiceProvider);
    final token=sessions.isRunning ? sessions.active?.id : null;
    if (token!=_running) {
      _running=token;
      WidgetsBinding.instance.addPostFrameCallback((_) { if(mounted) _touch(); });
    }
    return Listener(onPointerDown:(_)=>_touch(),onPointerMove:(_)=>_touch(),
      child:Column(children:[
        Expanded(child:widget.child),
        if (sessions.hasActive) Material(color:Theme.of(context).colorScheme.surfaceContainerHighest,
          child:SafeArea(top:false,child:Padding(padding:const EdgeInsetsDirectional.only(start:16,end:8),
            child:Row(children:[
              Expanded(child:Text('${sessions.active!.module.replaceAll('_',' ')} · ${sessions.active!.elapsedSeconds~/60}:${(sessions.active!.elapsedSeconds%60).toString().padLeft(2,'0')}\n${sessions.isRunning ? 'Studying · auto-pause after 2 min idle' : 'Paused — resume when ready'}',style:Theme.of(context).textTheme.bodySmall)),
              IconButton(tooltip:sessions.isRunning?'Pause':'Resume',icon:Icon(sessions.isRunning?Icons.pause:Icons.play_arrow),
                onPressed:_busy?null:() async {
                  if(sessions.isRunning) { await sessions.pause(); } else { sessions.resume(); }
                  _touch();
                }),
              IconButton(tooltip:'Finish activity',icon:const Icon(Icons.check),onPressed:_busy?null:() async {
                try { await _finish(); } catch (_) {
                  if(context.mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content:Text('Could not finish the activity. Please retry after studying.')));
                }
              }),
            ]),
          )),
        ),
      ]),
    );
  }
}
