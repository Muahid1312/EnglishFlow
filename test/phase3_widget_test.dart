import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/ai_teacher_service.dart';
import 'package:lexiflow/core/services/providers.dart';
import 'package:lexiflow/features/listening_speaking/ai_conversation/ai_conversation_screen.dart';
import 'package:lexiflow/features/listening_speaking/listening/comprehension_screen.dart';

import 'stability_services_test.dart' as fixtures;
import 'support/phase2_fakes.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  late MockAiTransport transport;
  late SecureAiTeacherService ai;
  setUp(() async {
    dir=Directory.systemTemp.createTempSync('lexiflow-phase3-widget-');db=AppDatabase(path:'${dir.path}/db.sqlite');
    transport=MockAiTransport();ai=SecureAiTeacherService(storage:fixtures.TestSecureStorage(),transport:transport);
    await ai.saveApiKey(AiProvider.openAi,'dummy-test-key');
  });
  tearDown((){db.close();dir.deleteSync(recursive:true);});
  Widget app(Widget page)=>ProviderScope(overrides:[appDatabaseProvider.overrideWithValue(db),aiTeacherServiceProvider.overrideWithValue(ai)],child:MaterialApp(home:page));

  testWidgets('scenario is persisted and a real service adapter sends its instruction only after Send',(tester) async {
    await tester.pumpWidget(app(const AiConversationScreen()));await tester.pumpAndSettle();
    expect(transport.calls,0);
    await tester.tap(find.byType(DropdownButtonFormField<String>));await tester.pumpAndSettle();
    await tester.tap(find.text('Job interview').last);await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField),'I is practicing.');
    await tester.tap(find.byIcon(Icons.send));await tester.pumpAndSettle();
    expect(transport.calls,1);
    expect((transport.body!['messages'] as List).first['content'],contains('Act as a job interviewer'));
    expect((await db.getAiConversations()).single['scenario_id'],'job_interview');
    expect(await db.getVocabulary(),isEmpty);expect(await db.getWritingMistakes(),isEmpty);
    await tester.ensureVisible(find.text('Save vocabulary'));
    await tester.tap(find.text('Save vocabulary'));await tester.pumpAndSettle();
    expect(await db.getVocabulary(),isEmpty);
    await tester.enterText(find.widgetWithText(TextField,'Word'),'helpful');
    await tester.enterText(find.widgetWithText(TextField,'Definition (optional)'),'providing assistance');
    await tester.tap(find.text('Save'));await tester.pumpAndSettle();
    expect((await db.getVocabulary()).single['word'],'helpful');
    await tester.ensureVisible(find.text('Confirm correction'));
    await tester.tap(find.text('Confirm correction'));await tester.pumpAndSettle();
    expect(await db.getWritingMistakes(),isEmpty);
    await tester.enterText(find.widgetWithText(TextField,'Corrected sentence'),'I am practicing.');
    await tester.tap(find.text('Save mistake'));await tester.pumpAndSettle();
    expect((await db.getWritingMistakes()).single['original_sentence'],'I is practicing.');
    expect((await db.getAiMessages((await db.getAiConversations()).single['id'] as String)).first['content'],'I is practicing.');
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
  });

  testWidgets('opening a thread beyond the first history page restores that exact thread',(tester) async {
    await db.insertAiConversation('oldest',title:'Oldest saved thread',scenarioId:'travel');
    await db.insertAiMessage('old-message','oldest','user','Original text from the oldest thread.');
    for(var i=0;i<100;i++){await db.insertAiConversation('new-$i',title:'New thread $i');}
    await tester.pumpWidget(app(const AiConversationScreen()));await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Conversations'));await tester.pumpAndSettle();
    await tester.tap(find.text('Load more conversations'));await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Oldest saved thread'),400,
      scrollable:find.descendant(of:find.byKey(const ValueKey('conversation-history-list')),matching:find.byType(Scrollable)).first);
    await tester.tap(find.text('Oldest saved thread'));await tester.pumpAndSettle();
    expect(find.text('Original text from the oldest thread.'),findsOneWidget);
    expect(transport.calls,0);
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
  });

  testWidgets('feedback requires an explicit confirmation and stays separate from original conversation',(tester) async {
    await db.insertAiConversation('conversation',title:'Real saved thread',scenarioId:'free');
    for(var i=0;i<3;i++) {
      final request=await db.beginAiRequest('conversation','Learner text $i');
      await db.finishAiRequest(request,'Persisted mocked reply $i');
    }
    await tester.pumpWidget(app(const AiConversationScreen()));await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Request AI feedback summary'));
    await tester.tap(find.text('Request AI feedback summary'));await tester.pumpAndSettle();
    expect(transport.calls,0);
    await tester.tap(find.text('Confirm'));await tester.pumpAndSettle();
    expect(transport.calls,1);
    final messages=await db.getAiMessages('conversation');
    expect(messages.where((m)=>m['purpose']=='conversation'),hasLength(6));
    expect(messages.where((m)=>m['purpose']=='feedback'),hasLength(2));
    expect(await db.getVocabulary(),isEmpty);expect(await db.getWritingMistakes(),isEmpty);
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
  });

  testWidgets('comprehension retry is explicit and cannot double-submit a completed attempt',(tester) async {
    await db.insertListeningLesson({'id':'l','title':'Lesson','audio_path':'fixture.mp3'});
    await db.saveComprehensionQuestion(lessonId:'l',question:'Is this statement true?',type:'true_false',correct:'True');
    await tester.pumpWidget(app(const ComprehensionScreen(lessonId:'l')));await tester.pumpAndSettle();
    await tester.tap(find.text('True'));await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit answers'));await tester.tap(find.text('Submit answers'));await tester.pumpAndSettle();
    expect(await db.getComprehensionAttempts('l'),hasLength(1));
    await tester.ensureVisible(find.text('Start a new attempt'));await tester.tap(find.text('Start a new attempt'));await tester.pumpAndSettle();
    expect(await db.getComprehensionAttempts('l'),hasLength(1));
    await tester.tap(find.text('False'));await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit answers'));await tester.tap(find.text('Submit answers'));await tester.pumpAndSettle();
    expect(await db.getComprehensionAttempts('l'),hasLength(2));
    await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();
  });
}
