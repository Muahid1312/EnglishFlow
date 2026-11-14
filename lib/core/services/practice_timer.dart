import 'study_session_service.dart';

/// A practice screen reuses an active session for its module (including plans),
/// and only finishes sessions it created. It never adds a second timing stream.
class PracticeTimer {
  PracticeTimer(this.sessions,this.module);
  final StudySessionService sessions;
  final String module;
  String? id;
  bool _owned=false;
  Future<void>? _starting;
  Future<void> start() => _starting ??= _start().whenComplete(()=>_starting=null);
  Future<void> _start() async {
    await sessions.recoverInterrupted();
    if(sessions.hasActive && sessions.active!.module==module) {
      if(id!=sessions.active!.id) _owned=false;
      id=sessions.active!.id; sessions.resume();
    } else {
      final previous=id;
      id=(await sessions.start(module)).id;_owned=true;
      if(previous!=null && await sessions.continuePlanActivity(previous,id!))_owned=false;
    }
  }
  Future<void> pause() async {
    try {if(_starting!=null)await _starting;}catch(_){/* Still pause any timer that did start. */}
    if(id!=null && sessions.active?.id==id) await sessions.pause();}
  Future<void> finish() async {
    if(id!=null && sessions.active?.id==id) {
      if(_owned) {await sessions.finish();} else {await sessions.pause();}
    }
  }
}
