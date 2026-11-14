import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/utils/id_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/providers.dart';
import '../../core/services/course_study_service.dart';
import '../../core/services/ai_teacher_service.dart';
import '../../core/widgets/ai_help_button.dart';
import '../books/completion_panel.dart' show CompletionPanel;
import 'course_assessment_editor.dart';

Future<List<String>?> courseFields(BuildContext context, String title,
    Map<String,String> fields) async {
  final controllers = fields.values.map((s)=>TextEditingController(text:s)).toList();
  final result = await showDialog<List<String>>(context:context,builder:(context)=>AlertDialog(
    title:Text(title),content:SizedBox(width:440,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      for(var i=0;i<controllers.length;i++) Padding(padding:const EdgeInsets.only(bottom:12),child:TextField(controller:controllers[i],decoration:InputDecoration(labelText:fields.keys.elementAt(i)),maxLines:fields.keys.elementAt(i).contains('notes')?3:1)),
    ]))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,controllers.map((c)=>c.text).toList()),child:const Text('Save'))]));
  // Dialog fields finish their closing animation before their controllers retire.
  await Future<void>.delayed(const Duration(milliseconds:300));
  for(final c in controllers) { c.dispose(); }
  return result;
}

class CoursesScreen extends ConsumerStatefulWidget {
  const CoursesScreen({super.key});
  @override ConsumerState<CoursesScreen> createState()=>_CoursesState();
}
class _CoursesState extends ConsumerState<CoursesScreen> {
  List<Map<String,dynamic>> _rows=[];
  String? _error;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {try {final rows=(await ref.read(appDatabaseProvider).db).select('SELECT * FROM courses WHERE deleted=0 ORDER BY is_active DESC,title');if(mounted)setState(()=>_rows=rows);}catch(_){if(mounted)setState(()=>_error='Could not load courses.');}}
  Future<void> _create() async {
    final values=await courseFields(context,'Create course',{'Title':'','Description':'','Target level':'B1'});
    if(values==null)return;
    try{await CourseStudyService(ref.read(appDatabaseProvider)).saveCourse(title:values[0],description:values[1],level:values[2]);await _load();}catch(e){if(mounted)setState(()=>_error=e.toString());}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Courses')),floatingActionButton:FloatingActionButton.extended(onPressed:_create,icon:const Icon(Icons.add),label:const Text('Create course')),body:ListView(padding:const EdgeInsets.fromLTRB(20,20,20,100),children:[
    if(_error!=null)Text(_error!),if(_rows.isEmpty)const Text('Create a course, then organize your own units, lessons and activities. Existing PDFs can be linked from course settings.'),
    for(final c in _rows)ListTile(leading:const Icon(Icons.school_outlined),title:Text('${c['title']}'),subtitle:Text(c['is_active']==1?'${c['level'] ?? ''}':'Archived'),onTap:()async{await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>CourseDetailScreen(course:c)));await _load();}),
  ]));
}
class CourseDetailScreen extends ConsumerStatefulWidget {
  const CourseDetailScreen({super.key,required this.course});
  final Map<String,dynamic> course;
  @override ConsumerState<CourseDetailScreen> createState()=>_CourseState();
}
class _CourseState extends ConsumerState<CourseDetailScreen> {
  late Map<String,dynamic> _course;
  List<Map<String,dynamic>> _units=[],_lessons=[];
  Map<String,dynamic> _progress={};String? _error;
  String get id=>widget.course['id'] as String;
  CourseStudyService get service=>CourseStudyService(ref.read(appDatabaseProvider));
  @override void initState(){super.initState();_course=widget.course;_load();}
  Future<void> _run(Future<void> Function() action)async{try{await action();await _load();}catch(e){if(mounted)setState(()=>_error=e.toString());}}
  Future<void> _load()async{try{final d=await ref.read(appDatabaseProvider).db;final c=d.select('SELECT * FROM courses WHERE id=?',[id]).single;final units=d.select('SELECT * FROM course_units WHERE course_id=? ORDER BY order_index,id',[id]);final lessons=d.select('SELECT * FROM lessons WHERE course_id=? ORDER BY order_index,id',[id]);final progress=CourseStudyService.progress(d,id);if(c['structured_mode']==1 && CourseStudyService.certificateEvidence(d,id)!=null)progress['state']='Completed · activities self-reported, assessments passed';if(mounted)setState((){_course=c;_units=units;_lessons=lessons;_progress=progress;});}catch(e){if(mounted)setState(()=>_error=e.toString());}}
  Future<void> _settings()async{
    final v=await courseFields(context,'Course settings',{'Title':'${_course['title']}','Description':'${_course['description']??''}','Target level':'${_course['level']??'B1'}','Minimum objective score (0–1)':'${_course['minimum_score']}'});
    if(v==null)return;
    await _run(()async{final minimum=double.tryParse(v[3]);if(minimum==null||!minimum.isFinite||minimum<0||minimum>1)throw ArgumentError('Score must be between 0 and 1.');await service.saveCourse(id:id,title:v[0],description:v[1],level:v[2],bookId:_course['book_id'] as String?,minimumScore:minimum);});
  }
  Future<void> _cover()async{
    await _run(()async{
      final pick=await FilePicker.platform.pickFiles(type:FileType.image);
      if(pick==null)return;
      final source=File(pick.files.single.path!);
      if(await source.length()>10*1024*1024)throw StateError('Choose a cover smaller than 10 MB.');
      final folder=Directory('${(await getApplicationDocumentsDirectory()).path}/media/course_covers');await folder.create(recursive:true);
      final path='${folder.path}/${newId()}.image';await source.copy(path);
      try{(await ref.read(appDatabaseProvider).db).execute('UPDATE courses SET cover_path=? WHERE id=?',[path,id]);}catch(_){await File(path).delete();rethrow;}
    });
  }
  Future<void> _pdf()async{
    final d=await ref.read(appDatabaseProvider).db;final books=d.select('SELECT id,title FROM imported_books ORDER BY title');if(!mounted)return;
    final selected=await showDialog<String>(context:context,builder:(context)=>SimpleDialog(title:const Text('Link existing PDF'),children:[SimpleDialogOption(onPressed:()=>Navigator.pop(context,''),child:const Text('No PDF')),for(final b in books)SimpleDialogOption(onPressed:()=>Navigator.pop(context,b['id']),child:Text('${b['title']}'))]));
    if(selected==null)return;
    await _run(()async{if(selected!=(_course['book_id']??'')&&_lessons.any((l)=>l['page_start']!=null))throw StateError('Remove lesson page ranges before changing the PDF.');d.execute('UPDATE courses SET book_id=? WHERE id=?',[selected.isEmpty?null:selected,id]);});
  }
  Future<void> _unit([Map<String,dynamic>? unit])async{final v=await courseFields(context,unit==null?'New unit':'Edit unit',{'Title':'${unit?['title']??''}'});if(v!=null)await _run(()async{await service.saveUnit(id,v[0],id:unit?['id'] as String?);});}
  Future<void> _lesson(Map<String,dynamic> unit,[Map<String,dynamic>? lesson])async{
    final v=await courseFields(context,lesson==null?'New lesson':'Edit lesson',{'Title':'${lesson?['title']??''}','Objective':'${lesson?['objective']??''}','Lesson notes':'${lesson?['notes']??''}','PDF start page':'${lesson?['page_start']??''}','PDF end page':'${lesson?['page_end']??''}'});
    if(v!=null)await _run(()async{if((v[3].isNotEmpty&&int.tryParse(v[3])==null)||(v[4].isNotEmpty&&int.tryParse(v[4])==null))throw ArgumentError('Enter whole page numbers.');await service.saveLesson(id,unit['id'] as String,v[0],id:lesson?['id'] as String?,objective:v[1],notes:v[2],start:int.tryParse(v[3]),end:int.tryParse(v[4]));});
  }
  Future<void> _remove()async{final ok=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:const Text('Delete course?'),content:const Text('The course will be hidden. Imported books, learning records and issued certificates are retained.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Delete course'))]));if(ok==true)await _run(()async{(await ref.read(appDatabaseProvider).db).execute('UPDATE courses SET deleted=1,is_active=0 WHERE id=?',[id]);if(mounted)Navigator.pop(context);});}
  Future<void> _resume()async{
    await _run(()async{
      final d=await ref.read(appDatabaseProvider).db;
      final rows=d.select('''SELECT l.* FROM lessons l LEFT JOIN course_units u ON u.id=l.unit_id WHERE l.course_id=?
        AND (NOT EXISTS(SELECT 1 FROM course_activities a WHERE a.lesson_id=l.id)
        OR EXISTS(SELECT 1 FROM course_activities a LEFT JOIN course_activity_evidence e ON e.activity_id=a.id WHERE a.lesson_id=l.id AND e.activity_id IS NULL))
        ORDER BY l.last_studied_at DESC,u.order_index,l.order_index,l.id LIMIT 1''',[id]);
      if(mounted)await _open(rows.isEmpty?_lessons.last:rows.single);
    });
  }
  Future<void> _open(Map<String,dynamic> lesson)async{await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>CourseLessonScreen(lessonId:lesson['id'] as String)));await _load();}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text('${_course['title']}'),actions:[IconButton(tooltip:'Course settings',onPressed:_settings,icon:const Icon(Icons.edit_outlined))]),body:ListView(padding:const EdgeInsets.all(20),children:[
    if(_error!=null)Text(_error!),Text('${_course['description']??''}'),Text('${_progress['state']??''} · ${_progress['completed_lessons']??0}/${_progress['lessons']??0} lessons · ${_progress['completed_units']??0}/${_progress['units']??0} units'),Text('${_progress['remaining']??0} remaining activities. Activity completion is self-reported.'),if(_progress['last']!=null)Text('Last studied: ${_progress['last']}'),
    if(_course['cover_path']!=null && File(_course['cover_path'] as String).existsSync()) Image.file(File(_course['cover_path'] as String),height:180,fit:BoxFit.contain,errorBuilder:(_,__,___)=>const Text('Cover unavailable')),
    TextButton(onPressed:_cover,child:const Text('Choose cover image')),
    TextButton(onPressed:_pdf,child:Text(_course['book_id']==null?'Link imported PDF':'Change linked PDF')),
    if(_lessons.isNotEmpty)FilledButton(onPressed:_resume,child:const Text('Resume learning')),
    if(_course['structured_mode']==1) TextButton(onPressed:()=>_unit(),child:const Text('Add unit')),
    if(_course['structured_mode']==0) const Text('Legacy course: lesson checkboxes remain self-reported. Create a new structured course to track activities.'),
    for(final u in _units)...[
      ListTile(title:Text('${u['title']}'),onTap:()=>_unit(u),trailing:IconButton(tooltip:'Add lesson',icon:const Icon(Icons.add),onPressed:()=>_lesson(u))),
      Wrap(children:[TextButton(onPressed:()=>_run(()=>service.moveUnit(u['id'] as String,-1)),child:const Text('Move unit up')),TextButton(onPressed:()=>_run(()=>service.moveUnit(u['id'] as String,1)),child:const Text('Move unit down'))]),
      for(final l in _lessons.where((l)=>l['unit_id']==u['id']))Card(child:Column(children:[ListTile(title:Text('${l['title']}'),subtitle:Text('${l['objective']??''}'),onTap:()=>_open(l)),Wrap(children:[TextButton(onPressed:()=>_lesson(u,l),child:const Text('Edit')),IconButton(tooltip:'Move lesson up',onPressed:()=>_run(()=>service.moveLesson(l['id'] as String,-1)),icon:const Icon(Icons.arrow_upward)),IconButton(tooltip:'Move lesson down',onPressed:()=>_run(()=>service.moveLesson(l['id'] as String,1)),icon:const Icon(Icons.arrow_downward))])])),
    ],
    for(final l in _lessons.where((l)=>l['unit_id']==null))CheckboxListTile(title:Text('${l['title']} (self-reported legacy lesson)'),value:l['completed']==1,onChanged:(value)=>_run(()async{(await ref.read(appDatabaseProvider).db).execute('UPDATE lessons SET completed=?,completed_at=? WHERE id=?',[value==true?1:0,value==true?DateTime.now().toUtc().toIso8601String():null,l['id']]);})),
    FilledButton.tonal(onPressed:()async{await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>CourseAssessmentEditor(courseId:id,units:_units)));await _load();},child:const Text('Author assessment')),
    CompletionPanel(type:'course',id:id),
    TextButton(onPressed:()=>_run(()async{(await ref.read(appDatabaseProvider).db).execute('UPDATE courses SET is_active=? WHERE id=?',[_course['is_active']==1?0:1,id]);}),child:Text(_course['is_active']==1?'Archive course':'Unarchive course')),
    TextButton(onPressed:_remove,child:const Text('Delete course')),
  ]));
}

class CourseLessonScreen extends ConsumerStatefulWidget {
  const CourseLessonScreen({super.key,required this.lessonId});final String lessonId;
  @override ConsumerState<CourseLessonScreen> createState()=>_LessonState();
}
class _LessonState extends ConsumerState<CourseLessonScreen>{
  Map<String,dynamic>? _lesson;List<Map<String,dynamic>> _activities=[];String? _book;String? _error;
  final _passage=TextEditingController();bool _dari=false;String _task='Simpler English explanation';
  @override void initState(){super.initState();_load();}
  @override void dispose(){_passage.dispose();super.dispose();}
  Future<void> _load()async{try{final d=await ref.read(appDatabaseProvider).db;final l=d.select('SELECT l.*,u.title AS unit_title,c.book_id FROM lessons l JOIN courses c ON c.id=l.course_id LEFT JOIN course_units u ON u.id=l.unit_id WHERE l.id=?',[widget.lessonId]).single;final a=d.select('SELECT a.*,e.completed_at FROM course_activities a LEFT JOIN course_activity_evidence e ON e.activity_id=a.id WHERE a.lesson_id=? ORDER BY a.order_index,a.id',[widget.lessonId]);if(mounted)setState((){_lesson=l;_book=l['book_id'] as String?;_activities=a;});}catch(e){if(mounted)setState(()=>_error=e.toString());}}
  Future<void> _run(Future<void> Function() fn)async{try{await fn();await _load();}catch(e){if(mounted)setState(()=>_error=e.toString());}}
  Future<void> _add()async{
    const routes={'reading':'/learn/reading','vocabulary':'/learn/vocabulary','listening':'/learn/listening','speaking':'/learn/listening/speaking','grammar':'/learn/grammar','writing':'/learn/grammar/writing','assessment':'/progress/assessments'};
    final kind=await showDialog<String>(context:context,builder:(context)=>SimpleDialog(title:const Text('Activity module'),children:[for(final k in routes.keys)SimpleDialogOption(onPressed:()=>Navigator.pop(context,k),child:Text(k))]));if(kind==null||!mounted)return;
    final d=await ref.read(appDatabaseProvider).db;
    final queries=<String,String>{'reading':'SELECT id,title FROM reading_articles ORDER BY title','listening':'SELECT id,title FROM listening_lessons ORDER BY title','grammar':'SELECT id,title FROM grammar_lessons ORDER BY title','writing':'SELECT id,title FROM writing_entries ORDER BY title','vocabulary':'SELECT id,word AS title FROM vocabulary_entries WHERE is_saved=1 AND duplicate_of IS NULL ORDER BY word','assessment':'SELECT id,title FROM assessment_definitions ORDER BY title'};
    final targets=queries.containsKey(kind)?d.select(queries[kind]!):<Map<String,dynamic>>[];
    if(!mounted)return;
    final target=await showDialog<String>(context:context,builder:(context)=>SimpleDialog(title:const Text('Link learning activity'),children:[if(kind!='assessment')SimpleDialogOption(onPressed:()=>Navigator.pop(context,''),child:const Text('Practice in this module')),for(final t in targets)SimpleDialogOption(onPressed:()=>Navigator.pop(context,t['id']),child:Text('${t['title']}'))]));
    if(target==null||!mounted)return;
    var route=routes[kind]!;
    if(target.isNotEmpty){route=switch(kind){'reading'=>'/learn/reading/$target','listening'=>'/learn/listening/player/$target','grammar'=>'/learn/grammar/lesson/$target','writing'=>'/learn/grammar/writing/$target','vocabulary'=>'/learn/vocabulary/word/$target','assessment'=>'/progress/assessments/$target',_=>route};}
    final v=await courseFields(context,'Add activity',{'Title':''});if(v!=null)await _run(()=>CourseStudyService(ref.read(appDatabaseProvider)).addActivity(widget.lessonId,v[0],kind,route:route));
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text('${_lesson?['title']??'Lesson'}')),body:ListView(padding:const EdgeInsets.all(20),children:[
    if(_error!=null)Text(_error!),if(_lesson!=null)...[
      Text('${_lesson!['unit_title']??''}'),Text('${_lesson!['objective']??''}'),
      FilledButton(onPressed:()=>_run(()async{(await ref.read(appDatabaseProvider).db).execute('UPDATE lessons SET last_studied_at=? WHERE id=?',[DateTime.now().toUtc().toIso8601String(),widget.lessonId]);}),child:const Text('Start / continue lesson')),
      if(_book!=null)TextButton(onPressed:()=>context.push('/learn/books/$_book/read${_lesson!['page_start']==null?'':'?page=${_lesson!['page_start']}'}'),child:Text('Open PDF · pages ${_lesson!['page_start']??'—'}–${_lesson!['page_end']??'—'}')),
      Text('Notes: ${_lesson!['notes']??''}'),TextButton(onPressed:()async{final v=await courseFields(context,'Lesson notes',{'Lesson notes':'${_lesson!['notes']??''}'});if(v!=null)await _run(()async{(await ref.read(appDatabaseProvider).db).execute('UPDATE lessons SET notes=? WHERE id=?',[v[0],widget.lessonId]);});},child:const Text('Save notes')),
      const Text('Check an activity only after doing the work. These records are self-reported; opening a page does not complete it.'),
      for(final a in _activities)Card(child:Column(children:[CheckboxListTile(title:Text('${a['title']}'),subtitle:Text('${a['kind']} · ${a['completed_at']??'Not completed'}${a['kind']=='assessment'?' · Requires a saved objective pass':''}'),value:a['completed_at']!=null,onChanged:(value)=>_run(()=>CourseStudyService(ref.read(appDatabaseProvider)).completeActivity(a['id'] as String,value==true))),if(a['route']!=null)TextButton(onPressed:()=>context.push(a['route'] as String),child:const Text('Open learning module'))])),
      TextButton(onPressed:_add,child:const Text('Add activity')),
      const Divider(),const Text('Optional online study assistant · AI explanations are not official textbook answers.'),
      TextField(controller:_passage,maxLines:5,maxLength:6000,decoration:const InputDecoration(labelText:'Paste only the passage you select')),
      DropdownButton<String>(isExpanded:true,value:_task,items:[for(final task in ['Simpler English explanation','Vocabulary explanation','Grammar explanation','Short summary','Practice questions'])DropdownMenuItem(value:task,child:Text(task))],onChanged:(v)=>setState(()=>_task=v!)),
      SwitchListTile(title:const Text('Explain in Dari/Persian'),value:_dari,onChanged:(v)=>setState(()=>_dari=v)),
      AiHelpButton(task:AiTask.comprehension,beforeSend:()async=>_passage.text.trim().isNotEmpty,content:()=>'$_task for a B1–B2 English learner. ${_dari?'Explain in Dari/Persian.':''} Use only this passage; do not invent pages or official answers.\n${_passage.text}',label:'Send selected passage to AI'),
    ]
  ]));
}
