import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/providers.dart';
import 'package:lexiflow/features/grammar_writing/writing/writing_studio_screen.dart';
import 'package:lexiflow/features/mistake_coach/mistake_practice_screen.dart';
import 'package:lexiflow/features/vocabulary/word_detail_screen.dart';
import 'package:lexiflow/features/vocabulary/word_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase db;
  final calls = <MethodCall>[];
  const speech = MethodChannel('lexiflow/pronunciation');
  setUp(() {
    dir = Directory.systemTemp.createTempSync('lexiflow-phase2-ui-');
    db = AppDatabase(path: '${dir.path}/db.sqlite');
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(speech, (call) async {
      calls.add(call);
      return call.method == 'speak'
          ? {'locale': 'en-US', 'offlineVoice': true}
          : null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(speech, null);
    db.close();
    dir.deleteSync(recursive: true);
  });
  Widget app(Widget child) => ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(home: child));

  testWidgets(
      'word detail calls pronunciation adapter with real word and handles unavailable engine',
      (tester) async {
    final id = await db.saveVocabulary(
        word: 'resilient',
        definition: 'recover after difficulty',
        translation: 'تاب‌آور');
    await tester.pumpWidget(app(WordDetailScreen(entryId: id)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pronounce'));
    await tester.pumpAndSettle();
    expect(calls.single.arguments, {'text': 'resilient'});
    expect(find.textContaining('Played en-US'), findsOneWidget);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(speech, (call) async {
      if (call.method == 'speak') throw PlatformException(code: 'ENGINE');
      return null;
    });
    await tester.tap(find.text('Pronounce'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pronunciation unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'rich vocabulary editor preserves original context while saving notes',
      (tester) async {
    final id = await db.saveVocabulary(
        word: 'preserve',
        sentence: 'Preserve the original context.',
        source: 'Original article');
    final entry = (await db.getVocabulary()).single;
    await tester.pumpWidget(app(Scaffold(
        body: Builder(
            builder: (context) => FilledButton(
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => WordEditorDialog(db: db, entry: entry)),
                child: const Text('Edit word'))))));
    await tester.tap(find.text('Edit word'));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.widgetWithText(TextField, 'Personal notes'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Personal notes'), 'My offline note');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final saved = (await db.getVocabulary()).single;
    expect(saved['id'], id);
    expect(saved['personal_notes'], 'My offline note');
    expect(saved['contexts_json'], contains('Preserve the original context.'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'writing correction requires edited confirmation and leaves the draft intact',
      (tester) async {
    (await db.db).execute(
        "INSERT INTO writing_entries(id,title,body) VALUES('draft','Journal','She have a book.')");
    await tester.pumpWidget(app(const WritingEditorScreen(entryId: 'draft')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('Save a confirmed correction'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save a confirmed correction'));
    await tester.pumpAndSettle();
    expect(await db.getWritingMistakes(), isEmpty);
    await tester.enterText(find.widgetWithText(TextField, 'Corrected sentence'),
        'She has a book.');
    await tester.tap(find.text('Save mistake'));
    await tester.pumpAndSettle();
    final mistake = (await db.getWritingMistakes()).single;
    expect(mistake['entry_id'], 'draft');
    expect(mistake['correction'], 'She has a book.');
    expect((await db.getWritingEntry('draft'))!['body'], 'She have a book.');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('open mistake rewrite records only explicit self assessment',
      (tester) async {
    await db.saveWritingMistake({
      'id': 'm',
      'original_sentence': 'I is learning.',
      'correction': 'I am learning.',
      'grammar_topic': 'Verb tenses'
    });
    await tester.pumpWidget(app(const MistakePracticeScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start practice'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Your response'), 'I am studying now.');
    await tester.ensureVisible(find.text('Reveal correction'));
    await tester.tap(find.text('Reveal correction'));
    await tester.pumpAndSettle();
    expect((await db.db).select('SELECT * FROM mistake_practice_attempts'),
        isEmpty);
    await tester.ensureVisible(find.text('I understand this correction'));
    await tester.tap(find.text('I understand this correction'));
    await tester.pumpAndSettle();
    expect(
        (await db.db)
            .select('SELECT mode FROM mistake_practice_attempts')
            .single['mode'],
        'self');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
