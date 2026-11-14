import 'dart:io';
import 'support/settle_io.dart';
import 'package:lexiflow/core/services/listening_downloads.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/ai_teacher_service.dart';
import 'package:lexiflow/core/services/article_import_service.dart';
import 'package:lexiflow/features/reading/reading_screen.dart';
import 'package:lexiflow/features/vocabulary/vocabulary_screen.dart';
import 'package:lexiflow/core/services/providers.dart';
import 'package:lexiflow/features/assessments/assessments_screen.dart';
import 'package:lexiflow/features/grammar_writing/grammar/grammar_lesson_screen.dart';
import 'package:lexiflow/features/grammar_writing/writing/writing_studio_screen.dart';
import 'package:lexiflow/features/listening_speaking/ai_conversation/ai_conversation_screen.dart';
import 'package:lexiflow/features/listening_speaking/listening/listening_library_screen.dart';
import 'package:lexiflow/features/settings/settings_screen.dart';

class FaultDatabase extends AppDatabase {
  FaultDatabase(String path) : super(path: path);
  bool failWrite = false;
  bool failImport = false;
  @override
  Future<void> upsertWritingEntry(Map<String, Object?> m) async {
    if (failWrite) throw StateError('test write failure');
    await super.upsertWritingEntry(m);
  }

  @override
  Future<void> saveAssessmentAttempt(Map<String, Object?> m) async {
    if (failWrite) throw StateError('test write failure');
    await super.saveAssessmentAttempt(m);
  }

  @override
  Future<void> saveGrammarAttempt(Map<String, Object?> m) async {
    if (failWrite) throw StateError('test write failure');
    await super.saveGrammarAttempt(m);
  }

  @override
  Future<void> insertListeningLesson(Map<String, Object?> m) async {
    if (failImport) throw StateError('test write failure');
    await super.insertListeningLesson(m);
  }
}

class FakeAi extends AiTeacherService {
  bool storageFailure = false;
  @override
  Future<AiStatus> checkStatus() async => AiStatus(
      availability:
          storageFailure ? AiAvailability.error : AiAvailability.unavailable);
  @override
  Future<AiProvider> getConfiguredProvider() async {
    if (storageFailure) throw StateError('storage unavailable');
    return AiProvider.none;
  }

  @override
  Future<void> saveApiKey(AiProvider provider, String key) async {}
  @override
  Future<void> clearCredentials() async {}
  @override
  Future<bool> hasCredentials() async => false;
}

class TestPicker extends FilePicker {
  String? path;
  @override
  Future<FilePickerResult?> pickFiles(
      {String? dialogTitle,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Function(FilePickerStatus)? onFileLoading,
      bool allowCompression = true,
      int compressionQuality = 30,
      bool allowMultiple = false,
      bool withData = false,
      bool withReadStream = false,
      bool lockParentWindow = false,
      bool readSequential = false}) async {
    if (path == null) throw PlatformException(code: 'picker-failed');
    return FilePickerResult(
        [PlatformFile(name: 'audio.mp3', size: 3, path: path)]);
  }
}

void main() {
  late Directory dir;
  late FaultDatabase db;
  late FakeAi ai;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('lexiflow-widget-fault-');
    db = FaultDatabase('${dir.path}/db.sqlite');
    await db.getPreferences();
    ai = FakeAi();
  });
  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });
  Widget app(Widget page, {ListeningDownloads? downloads}) =>
      ProviderScope(overrides: [
        if (downloads != null)
          listeningDownloadsProvider.overrideWith((ref) => downloads),
        appDatabaseProvider.overrideWithValue(db),
        aiTeacherServiceProvider.overrideWithValue(ai)
      ], child: MaterialApp(home: page));
  testWidgets(
      'TXT import to reading to vocabulary review survives a database restart',
      (tester) async {
    final source = File('${dir.path}/article.txt')
      ..writeAsStringSync(
          'Curiosity helps learning.\n\n${List.filled(100, 'Read another paragraph for offline practice.').join('\n\n')}');
    final id = (await tester
        .runAsync(() => ArticleImportService(db).importFile(source)))!;
    await tester.pumpWidget(app(ArticleReaderScreen(articleId: id)));
    await tester.pumpAndSettle();
    await tester.longPressAt(
        tester.getTopLeft(find.byType(SelectableText)) + const Offset(40, 10));
    await tester.pumpAndSettle();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    editable.controller.selection =
        const TextSelection(baseOffset: 0, extentOffset: 9);
    await tester.pump();
    tester.state<EditableTextState>(find.byType(EditableText)).showToolbar();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save word'));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.pumpWidget(app(const VocabularyScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    source.deleteSync();
    db.close();
    db = FaultDatabase('${dir.path}/db.sqlite');
    final word = (await db.getVocabulary()).single;
    expect(word['word'], 'Curiosity');
    expect(word['example_sentence'], 'Curiosity helps learning.');
    expect((await db.getReviewHistory(word['id'] as String)).single['rating'],
        'good');
    expect(await db.getDueReviewCount(), 0);
    final article = (await db.getArticle(id))!;
    expect(article['body'], contains('Curiosity helps learning.'));
    expect(article['scroll_offset'], greaterThan(100));
    expect(tester.takeException(), isNull);
  });
  testWidgets('secure storage outage does not block offline Settings',
      (tester) async {
    ai.storageFailure = true;
    await tester.pumpWidget(app(const SettingsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('existing local conversation is restored on re-entry',
      (tester) async {
    await db.insertAiConversation('history', title: 'Conversation · free');
    await db.insertAiMessage(
        'm1', 'history', 'user', 'My persisted practice message');
    await db.insertAiMessage('m2', 'history', 'assistant', 'Offline note');
    await tester.pumpWidget(app(const AiConversationScreen()));
    await tester.pumpAndSettle();
    expect(find.text('My persisted practice message'), findsOneWidget);
    expect(find.text('Local note — not a live model reply'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(app(const AiConversationScreen()));
    await tester.pumpAndSettle();
    expect(find.text('My persisted practice message'), findsOneWidget);
    expect((await db.getAiConversations()).length, 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('offline messages save even when secure credential storage fails',
      (tester) async {
    ai.storageFailure = true;
    await tester.pumpWidget(app(const AiConversationScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), 'Practice during a storage outage');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    final conversation = (await db.getAiConversations()).single;
    final messages = await db.getAiMessages(conversation['id'] as String);
    expect(
        messages.any((m) => m['content'] == 'Practice during a storage outage'),
        isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('empty mistake form cannot fabricate journal records',
      (tester) async {
    await tester.pumpWidget(app(const MistakeJournalScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save mistake'));
    await tester.pumpAndSettle();
    expect(await db.getWritingMistakes(), isEmpty);
    expect(find.textContaining('required'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed writing autosave retains draft and supports retry',
      (tester) async {
    await db.upsertWritingEntry(
        {'id': 'draft', 'title': 'Title', 'body': 'Original'});
    await tester.pumpWidget(app(const WritingEditorScreen(entryId: 'draft')));
    await tester.pumpAndSettle();
    db.failWrite = true;
    await tester.enterText(find.byType(TextField).last, 'New unsaved writing');
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pump();
    expect(find.textContaining('Draft could not be saved'), findsOneWidget);
    expect((await db.getWritingEntry('draft'))!['body'], 'Original');
    expect(tester.takeException(), isNull);
    db.failWrite = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect((await db.getWritingEntry('draft'))!['body'], 'New unsaved writing');
    expect(find.textContaining('Draft could not be saved'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('failed assessment save retains answers and allows retry',
      (tester) async {
    await db.insertAssessmentDefinition(
        {'id': 'a', 'title': 'Assessment', 'category': 'grammar'});
    await db.insertAssessmentQuestion({
      'id': 'q',
      'assessment_id': 'a',
      'question_type': 'mc',
      'prompt': 'Choose A',
      'choices': '["A","B"]',
      'correct_answer': 'A'
    });
    await tester.pumpWidget(app(const AssessmentTakeScreen(assessmentId: 'a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A'));
    await tester.pump();
    db.failWrite = true;
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save assessment'), findsOneWidget);
    expect(await db.getAssessmentAttempts(), isEmpty);
    expect(tester.takeException(), isNull);
    db.failWrite = false;
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();
    expect((await db.getAssessmentAttempts()).single['passed'], 1);
    expect(find.text('Objective score: 100%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed grammar write cannot show successful answer or advance',
      (tester) async {
    await db.insertGrammarLesson({
      'id': 'g',
      'title': 'Grammar',
      'cefr_level': 'B1',
      'topic_key': 't',
      'objective': 'Objective',
      'explanation': 'Explanation',
      'examples': 'Examples',
      'common_mistakes': 'Mistakes'
    });
    await db.insertGrammarExercise({
      'id': 'e',
      'lesson_id': 'g',
      'question_type': 'mc',
      'prompt': 'Choose A',
      'choices': '["A","B"]',
      'correct_answer': 'A',
      'explanation': 'A is correct'
    });
    await tester.pumpWidget(app(const GrammarLessonScreen(lessonId: 'g')));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(find.text('A')),
        alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('A'));
    await tester.pump();
    await tester.ensureVisible(find.text('Check answer'));
    db.failWrite = true;
    await tester.tap(find.text('Check answer'));
    await tester.pumpAndSettle();
    expect(find.text('Finish lesson'), findsNothing);
    expect(await db.countGrammarAttempts(), 0);
    expect(tester.takeException(), isNull);
    db.failWrite = false;
    await tester.tap(find.text('Check answer'));
    await tester.pumpAndSettle();
    expect(find.text('Finish lesson'), findsOneWidget);
    expect(await db.countGrammarAttempts(), 1);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'failed audio import cleans its copy and preserves the selected file',
      (tester) async {
    FilePicker? oldPicker;
    try {
      oldPicker = FilePicker.platform;
    } catch (_) {}
    final picker = TestPicker();
    FilePicker.platform = picker;
    addTearDown(() => FilePicker.platform = oldPicker ?? TestPicker());
    final source =
        File('listening_catalog/media/planning-a-short-study-session.mp3')
            .copySync('${dir.path}/source.mp3');
    picker.path = source.path;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => '${dir.path}/documents');
    addTearDown(() => messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null));
    final downloads = ListeningDownloads(db,
        documents: () async => Directory('${dir.path}/documents'),
        availableBytes: () async => 1 << 34,
        observeLifecycle: false);
    await tester.runAsync(downloads.initialize);
    db.failImport = true;
    await tester
        .pumpWidget(app(const ListeningLibraryScreen(), downloads: downloads));
    await waitForContent(tester, find.text('Planning a Short Study Session'));
    await tester.runAsync(() async {
      final dynamic action = tester
          .widget<IconButton>(find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'Import audio'))
          .onPressed;
      await action();
    });
    await tester.pumpAndSettle();
    expect(await db.getListeningLessons(), isEmpty);
    final copies = Directory('${dir.path}/documents/media/listening_downloads');
    expect(copies.existsSync(), isTrue);
    expect(copies.listSync(), isEmpty);
    expect(source.existsSync(), isTrue);
    expect(tester.takeException(), isNull);
    picker.path = null;
    await tester.tap(find.byTooltip('Import audio'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
