import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/ai_teacher_service.dart';
import 'package:lexiflow/core/services/providers.dart';
import 'package:lexiflow/core/services/study_session_service.dart';
import 'package:lexiflow/core/services/analytics_service.dart';
import 'package:lexiflow/features/dashboard/dashboard_provider.dart';
import 'package:lexiflow/core/services/recording_service.dart';
import 'package:lexiflow/core/services/shadowing_controller.dart';
import 'package:lexiflow/core/widgets/common_widgets.dart';
import 'package:lexiflow/features/listening_speaking/listening/comprehension_screen.dart';
import 'package:lexiflow/features/listening_speaking/listening/shadowing_screen.dart';
import 'package:lexiflow/features/listening_speaking/ai_conversation/ai_conversation_screen.dart';
import 'package:lexiflow/features/grammar_writing/writing/writing_studio_screen.dart';

import 'stability_services_test.dart' as f;
import 'support/phase2_fakes.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  late MockAiTransport transport;
  late SecureAiTeacherService ai;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('phase2-widget-');
    db = AppDatabase(path: '${dir.path}/db.sqlite');
    await db.getPreferences();
    transport = MockAiTransport();
    ai = SecureAiTeacherService(
        storage: f.TestSecureStorage(), transport: transport);
    await ai.saveApiKey(AiProvider.openAi, 'dummy-test-key');
  });
  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });
  Widget app(Widget page) => ProviderScope(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        aiTeacherServiceProvider.overrideWithValue(ai)
      ], child: MaterialApp(home: page));
  Future<void> lesson() async => db.insertListeningLesson({
        'id': 'lesson',
        'title': 'Lesson',
        'audio_path': 'local.mp3',
        'difficulty': 'B1',
        'transcript': 'The speaker wants to learn English.'
      });

  testWidgets(
      'B: comprehension question creation, grading, incorrect review and transcript reveal',
      (tester) async {
    await lesson();
    await tester.pumpWidget(app(const ComprehensionScreen(lessonId: 'lesson')));
    await tester.pumpAndSettle();
    expect(find.text('The speaker wants to learn English.'), findsNothing);
    await tester.tap(find.byTooltip('Add question'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Question'),
        'What does the speaker want?');
    await tester.enterText(
        find.widgetWithText(TextField, 'Choices (one per line)'),
        'Learn English\nGo shopping');
    await tester.enterText(
        find.widgetWithText(TextField, 'Correct answer (exact choice text)'),
        'Learn English');
    await tester.tap(find.text('Save question'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go shopping'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Submit answers'));
    await tester.tap(find.text('Submit answers'));
    await tester.pumpAndSettle();
    expect(
        (await db.getComprehensionAttempts('lesson')).single['is_correct'], 0);
    expect(find.textContaining('Incorrect · Answer: Learn English'),
        findsOneWidget);
    await Scrollable.ensureVisible(
        tester.element(find.text('Reveal transcript')),
        alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reveal transcript'));
    await tester.pumpAndSettle();
    expect(find.text('The speaker wants to learn English.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    db.close();
    db = AppDatabase(path: '${dir.path}/db.sqlite');
    await tester.pumpWidget(app(const ComprehensionScreen(lessonId: 'lesson')));
    await tester.pumpAndSettle();
    expect((await db.getListeningLesson('lesson'))!['transcript_revealed'], 1);
    expect((await db.getComprehensionAttempts('lesson')).length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'C: integrated shadowing can record, compare and save a linked attempt with platform mocks',
      (tester) async {
    await lesson();
    final native = f.FakeRecorder();
    final c = ShadowingController(db, 'lesson',
        reference: MockPracticePlayer(),
        playback: MockPracticePlayer(),
        recorder: RecordingService(
            recorder: native, storage: f.FakeStorage('${dir.path}/take.m4a')));
    await tester.pumpWidget(app(
        ShadowingScreen(lessonId: 'lesson', title: 'Lesson', controller: c)));
    await tester.pumpAndSettle();
    Future<void> action(String label) async {
      var done = false;
      final dynamic callback = tester
          .widget<PrimaryButton>(find.widgetWithText(PrimaryButton, label))
          .onPressed;
      final Future<void> work = callback();
      work.whenComplete(() => done = true);
      for (var i = 0; i < 100 && !done; i++) {
        await tester.pump();
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)));
      }
      expect(done, isTrue);
      await work;
      await tester.pumpAndSettle();
    }

    await action('Record segment');
    expect(c.recording, isTrue);
    await action('Stop recording');
    expect(c.pending, isNotNull);
    await Scrollable.ensureVisible(
        tester.element(find.text('Replay your recording')),
        alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replay your recording'));
    await tester.pumpAndSettle();
    expect(c.playback.playing, isTrue);
    await tester.tap(find.text('Save attempt'));
    await tester.pumpAndSettle();
    expect((await db.getShadowingHistory('lesson')).single['saved'], 1);
    expect(find.textContaining('accuracy'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets(
      'D: explicit AI writing feedback preserves original revision and restoration backs up current text',
      (tester) async {
    await db.upsertWritingEntry({
      'id': 'w',
      'title': 'Writing',
      'body': 'My original writing.',
      'word_count': 3
    });
    await tester.pumpWidget(app(const WritingEditorScreen(entryId: 'w')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Request AI feedback'));
    await tester.tap(find.text('Request AI feedback'));
    await tester.pumpAndSettle();
    expect(transport.calls, 0);
    await tester.tap(find.text('Send text'));
    await tester.pumpAndSettle();
    expect(transport.calls, 1);
    expect((await db.getWritingFeedback('w')).single['source'], 'ai');
    expect((await db.getWritingRevisions('w')).single['body'],
        'My original writing.');
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField).last);
    await tester.enterText(
        find.byType(TextField).last, 'A newer draft to preserve.');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump();
    await tester.tap(find.byTooltip('Revision history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submitted for AI feedback'));
    await tester.pumpAndSettle();
    expect(find.text('Current draft'), findsOneWidget);
    await tester.tap(find.text('Restore this revision'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect((await db.getWritingEntry('w'))!['body'], 'My original writing.');
    expect(
        (await db.getWritingRevisions('w'))
            .any((r) => r['body'] == 'A newer draft to preserve.'),
        isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
      'E: mistake creation, editing, review and confirmed deletion are real persisted actions',
      (tester) async {
    await tester.pumpWidget(app(const MistakeJournalScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add mistake'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Original sentence'), 'He go.');
    await tester.enterText(
        find.widgetWithText(TextField, 'Corrected sentence'), 'He goes.');
    await tester.enterText(
        find.widgetWithText(TextField, 'Grammar category'), 'Present tense');
    await tester.tap(find.text('Save mistake'));
    await tester.pumpAndSettle();
    expect((await db.getWritingMistakes()).single['correction'], 'He goes.');
    await tester.tap(find.byTooltip('Edit mistake'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Corrected sentence'), 'He went.');
    await tester.tap(find.text('Save mistake'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark understood'));
    await tester.pumpAndSettle();
    expect(
        (await db.getWritingMistakes()).single['review_status'], 'understood');
    await tester.tap(find.byTooltip('Delete mistake'));
    await tester.pumpAndSettle();
    expect((await db.getWritingMistakes()).length, 1);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(await db.getWritingMistakes(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'F: AI teacher sends once, restores an actual response, and manages saved conversations',
      (tester) async {
    await tester.pumpWidget(app(const AiConversationScreen()));
    await tester.pumpAndSettle();
    expect(transport.calls, 0);
    await tester.enterText(find.byType(TextField), 'Help me practice English.');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    expect(transport.calls, 1);
    final conversation = (await db.getAiConversations()).single;
    expect((await db.getAiMessages(conversation['id'] as String)).length, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    db.close();
    db = AppDatabase(path: '${dir.path}/db.sqlite');
    await tester.pumpWidget(app(const AiConversationScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Helpful B1–B2 feedback.'), findsOneWidget);
    expect(find.text('Local note — not a live model reply'), findsNothing);
    expect(transport.calls, 1);
    await tester.tap(find.byTooltip('Conversations'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rename conversation'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Title'), 'Renamed practice');
    await tester.tap(find.text('Save title'));
    await tester.pumpAndSettle();
    expect((await db.getAiConversations()).single['title'], 'Renamed practice');
    await tester.tap(find.byTooltip('Delete conversation'));
    await tester.pumpAndSettle();
    expect((await db.getAiConversations()).length, 1);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(await db.getAiConversations(), isEmpty);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New conversation'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Title'), 'Empty but valid');
    await tester.tap(find.text('Save title'));
    await tester.pumpAndSettle();
    expect((await db.getAiConversations()).single['message_count'], 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'interrupted conversation retries its saved message without duplicates and fits the keyboard',
      (tester) async {
    await db.insertAiConversation('interrupted');
    await db.beginAiRequest('interrupted', 'My saved question');
    await tester.pumpWidget(app(const AiConversationScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Request: interrupted'), findsOneWidget);
    expect(transport.calls, 0);
    await tester.tap(find.text('Retry last request'));
    await tester.pumpAndSettle();
    expect(transport.calls, 1);
    expect((await db.getAiMessages('interrupted')).length, 2);
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test(
      'H: timed activity reaches dashboard and progress without duplicate or AI waiting minutes',
      () async {
    var now = DateTime.now();
    final timer = StudySessionService(db, now: () => now);
    await timer.start('writing');
    now = now.add(const Duration(seconds: 60));
    await timer.withoutAiWaitingTime(() async {
      now = now.add(const Duration(minutes: 5));
    });
    now = now.add(const Duration(seconds: 60));
    await timer.finish();
    await timer.finish();
    final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)]);
    final dashboard = await container.read(dashboardProvider.future);
    final progress = await AnalyticsService(db).build();
    expect(dashboard.completedMinutesToday, 2);
    expect(progress.todayMinutes, 2);
    expect(progress.weekMinutes, 2);
    expect(progress.totalMinutes, 2);
    expect(
        (await db.db)
            .select('SELECT COUNT(*) n FROM study_sessions')
            .single['n'],
        1);
    container.dispose();
    timer.dispose();
  });
}
