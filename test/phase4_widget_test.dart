import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/providers.dart';
import 'package:lexiflow/core/services/course_study_service.dart';
import 'package:lexiflow/features/courses/course_screens.dart';

void main(){
  late Directory folder;late AppDatabase db;
  setUp((){folder=Directory.systemTemp.createTempSync('phase4-widget-');db=AppDatabase(path:'${folder.path}/db.sqlite');});
  tearDown((){db.close();folder.deleteSync(recursive:true);});
  Widget app(Widget screen)=>ProviderScope(overrides:[appDatabaseProvider.overrideWithValue(db)],child:MaterialApp(home:screen));
  testWidgets('course library creates an actual persisted course',(tester)async{
    await tester.pumpWidget(app(const CoursesScreen()));await tester.pumpAndSettle();
    await tester.tap(find.text('Create course'));await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField,'Title'),'My course');
    await tester.tap(find.text('Save'));await tester.pumpAndSettle();
    expect((await db.db).select('SELECT title,structured_mode FROM courses').single['title'],'My course');
    expect(find.text('My course'),findsOneWidget);
  });
  testWidgets('lesson opening leaves activity incomplete and checkbox persists explicit evidence',(tester)async{
    final s=CourseStudyService(db);final c=await s.saveCourse(title:'Course');final u=await s.saveUnit(c,'Unit');final l=await s.saveLesson(c,u,'Lesson');await s.addActivity(l,'Read passage','reading');
    await tester.pumpWidget(app(CourseLessonScreen(lessonId:l)));await tester.pumpAndSettle();
    expect((await db.db).select('SELECT * FROM course_activity_evidence'),isEmpty);
    await tester.tap(find.byType(CheckboxListTile));await tester.pumpAndSettle();
    expect((await db.db).select('SELECT * FROM course_activity_evidence'),hasLength(1));
    await tester.tap(find.byType(CheckboxListTile));await tester.pumpAndSettle();
    expect((await db.db).select('SELECT * FROM course_activity_evidence'),isEmpty);
  });
}
