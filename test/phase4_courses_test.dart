import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/course_study_service.dart';
import 'package:lexiflow/core/services/analytics_service.dart';
import 'package:lexiflow/core/backup/backup_service.dart';
import 'package:lexiflow/core/services/daily_plan_service.dart';
import 'package:lexiflow/core/services/study_session_service.dart';
import 'package:lexiflow/core/services/certificate_service.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;late AppDatabase database;late CourseStudyService service;
  setUp((){folder=Directory.systemTemp.createTempSync('phase4-');database=AppDatabase(path:'${folder.path}/test.sqlite');service=CourseStudyService(database);});
  tearDown((){database.close();folder.deleteSync(recursive:true);});
  Future<List<String>> course()async{
    final c=await service.saveCourse(title:'Real course');final u=await service.saveUnit(c,'Unit one');final l=await service.saveLesson(c,u,'Lesson one');
    return [c,u,l];
  }
  Future<void> assessment(String courseId,{String? key='yes',String answer='yes',double score=1,int passed=1})async{
    final d=await database.db;
    d.execute("INSERT INTO assessment_definitions(id,title,category,course_id) VALUES('test','Final','course',?)",[courseId]);
    d.execute("INSERT INTO assessment_questions(id,assessment_id,question_type,prompt,correct_answer) VALUES('q','test','recall','Answer?',?)",[key]);
    await database.setCompletionRequirements('course',courseId,['test']);
    await database.saveAssessmentAttempt({'id':'attempt','assessment_id':'test','score':score,'max_score':1,'passed':passed,'self_assessed':0,'answers_json':jsonEncode({'q':answer}),'started_at':'2026-01-01','completed_at':'2026-01-01'});
  }
  test('create edit and reorder are persisted after restart',()async{
    final ids=await course();final second=await service.saveLesson(ids[0],ids[1],'Second');await service.moveLesson(second,-1);
    await service.saveCourse(id:ids[0],title:'Edited');await service.saveUnit(ids[0],'Renamed unit',id:ids[1]);
    database.close();database=AppDatabase(path:'${folder.path}/test.sqlite');final d=await database.db;
    expect(d.select('SELECT title FROM courses').single['title'],'Edited');expect(d.select('SELECT title FROM course_units').single['title'],'Renamed unit');
    expect(d.select('SELECT id FROM lessons ORDER BY order_index').first['id'],second);
  });
  test('empty lessons and opening a lesson cannot complete a course',()async{
    final ids=await course();final d=await database.db;d.execute('UPDATE lessons SET completed=1,last_studied_at=? WHERE id=?',['2026-01-01',ids[2]]);
    await assessment(ids[0]);expect(await database.certificateEvidence('course',ids[0]),isNull);
    expect(CourseStudyService.progress(d,ids[0])['completed_lessons'],0);
  });
  test('completion uses activity evidence and persisted keyed answers',()async{
    final ids=await course();await service.addActivity(ids[2],'Read passage','reading');final d=await database.db;final activity=d.select('SELECT id FROM course_activities').single['id'] as String;
    await assessment(ids[0]);expect(await database.certificateEvidence('course',ids[0]),isNull);
    await service.completeActivity(activity,true);expect((await database.certificateEvidence('course',ids[0]))!['score'],1);
    expect(CourseStudyService.progress(d,ids[0])['state'],'Self-reported completion');
    await service.completeActivity(activity,false);expect(await database.certificateEvidence('course',ids[0]),isNull);
  });
  test('forged pass and missing keys cannot authorize a certificate',()async{
    final ids=await course();await service.addActivity(ids[2],'Read','reading');final d=await database.db;await service.completeActivity(d.select('SELECT id FROM course_activities').single['id'] as String,true);
    await assessment(ids[0],answer:'wrong');expect(await database.certificateEvidence('course',ids[0]),isNull);
    d.execute("UPDATE assessment_attempts SET answers_json=?",[jsonEncode({'q':'yes'})]);d.execute('UPDATE assessment_questions SET correct_answer=NULL');expect(await database.certificateEvidence('course',ids[0]),isNull);
  });
  test('PDF page bounds and cross-course units reject invalid links',()async{
    final ids=await course();await expectLater(service.saveLesson(ids[0],ids[1],'Bad',start:1,end:2),throwsArgumentError);
    final other=await service.saveCourse(title:'Other');await expectLater(service.saveLesson(other,ids[1],'Wrong unit'),throwsArgumentError);
  });
  test('deletion leaves learning materials and completion history intact',()async{
    final ids=await course();final d=await database.db;d.execute("INSERT INTO imported_books(id,title,file_path) VALUES('book','Keep','/keep.pdf')");d.execute("UPDATE courses SET book_id='book',deleted=1,is_active=0 WHERE id=?",[ids[0]]);
    expect(d.select('SELECT * FROM imported_books'),hasLength(1));expect(d.select('SELECT * FROM lessons'),hasLength(1));expect(await database.certificateEvidence('course',ids[0]),isNull);
  });
  test('missing evidence never becomes a weakness or fake percentage',()async{
    final snapshot=await AnalyticsService(database).build();expect(snapshot.skills['Grammar'],contains('Not enough data.'));expect(snapshot.skills['Listening'],contains('Not enough data.'));expect(snapshot.skills['Vocabulary'],contains('Not enough data.'));
    expect(snapshot.insights.any((i)=>i.message.contains('below 60%')),isFalse);
  });
  test('next lesson recommendation uses a real saved lesson',()async{
    final ids=await course();final snapshot=await AnalyticsService(database).build();expect(snapshot.insights.any((i)=>i.route=='/learn/courses/lesson/${ids[2]}'),isTrue);
  });
  test('historical PDF renders without current course eligibility',()async{
    final bytes=await CertificateService.historicalPdf({'learner_name':'Learner','title':'Historical course','ref_number':'LF-TEST','issued_at':'2025-01-01','score_text':'80% assessment score','verification_type':'lessons_and_assessments'});
    expect(ascii.decode(bytes.take(4).toList()),'%PDF');expect(bytes.length,greaterThan(1000));
  });
  test('schema nine upgrade keeps books and adds course evidence tables',()async{
    final old=AppDatabase.schemaTemplate(9);final d=await old.db;
    d.execute("INSERT INTO imported_books(id,title,file_path) VALUES('old','Original','/original.pdf')");
    d.execute('VACUUM INTO ?',['${folder.path}/legacy.sqlite']);old.close();
    final upgraded=AppDatabase(path:'${folder.path}/legacy.sqlite');try{final current=await upgraded.db;expect(current.select('PRAGMA user_version').single.values.single,10);expect(current.select('SELECT title FROM imported_books').single['title'],'Original');expect(current.select('PRAGMA foreign_key_check'),isEmpty);}finally{upgraded.close();}
  });
  test('backup roundtrip retains structured evidence, notes and cover media',()async{
    final ids=await course();await service.addActivity(ids[2],'Read','reading');final d=await database.db;
    final cover=File('${folder.path}/cover.png')..writeAsBytesSync([1,2,3]);
    d.execute('UPDATE courses SET cover_path=? WHERE id=?',[cover.path,ids[0]]);
    d.execute("UPDATE lessons SET notes='Keep these notes' WHERE id=?",[ids[2]]);
    await service.completeActivity(d.select('SELECT id FROM course_activities').single['id'] as String,true);
    final backup=BackupService(database,folder,availableBytes:()async=>1<<34);
    final archive=await backup.create(File('${folder.path}/saved.lexiflowbackup'));
    await backup.restore(archive);database.close();database=AppDatabase(path:'${folder.path}/test.sqlite');
    final restored=await database.db;
    expect(restored.select('SELECT notes FROM lessons').single['notes'],'Keep these notes');
    expect(restored.select('SELECT * FROM course_activity_evidence'),hasLength(1));
    expect(File(restored.select('SELECT cover_path FROM courses').single['cover_path'] as String).readAsBytesSync(),[1,2,3]);
  });
  test('daily plan recommends persisted unfinished course lesson',()async{
    final ids=await course();final sessions=StudySessionService(database);
    try{final plan=await DailyPlanService(database,sessions).today(goal:15);expect(plan.any((p)=>p['route']=='/learn/courses/lesson/${ids[2]}'),isTrue);}finally{sessions.dispose();}
  });

}
