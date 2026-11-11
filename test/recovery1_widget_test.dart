import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/providers.dart';
import 'package:lexiflow/features/reading/reading_screen.dart';
import 'package:lexiflow/features/vocabulary/vocabulary_screen.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('recovery-widget-');
    db = AppDatabase(path: '${dir.path}/test.sqlite');
    await db.getPreferences();
  });
  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });
  Widget app(Widget page) => ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(home: page));
  testWidgets(
      'reader selection menu saves the selected word and original sentence',
      (tester) async {
    const body = 'Curiosity helps us learn. Read another sentence.';
    final id = await db.saveArticle('Title', body);
    await tester.pumpWidget(app(ArticleReaderScreen(articleId: id)));
    await tester.pumpAndSettle();
    await tester.longPressAt(
        tester.getTopLeft(find.byType(SelectableText)) + const Offset(40, 10));
    await tester.pumpAndSettle();
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    editable.controller.selection =
        const TextSelection(baseOffset: 0, extentOffset: 9);
    await tester.pump();
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    state.showToolbar();
    await tester.pumpAndSettle();
    expect(find.text('Save word'), findsOneWidget);
    await tester.tap(find.text('Save word'));
    await tester.pumpAndSettle();
    final word = (await db.getVocabulary()).single;
    expect(word['word'], 'Curiosity');
    expect(word['example_sentence'], 'Curiosity helps us learn.');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(app(const VocabularyScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start review'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    expect(find.text('“Curiosity helps us learn.”'), findsOneWidget);
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();
    expect((await db.getReviewHistory(word['id'] as String)).single['rating'],
        'good');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
      'reading position restores after reader disposal and database reopen',
      (tester) async {
    final text = List.generate(
            200, (i) => 'Paragraph $i contains some text for offline reading.')
        .join('\n\n');
    final id = await db.saveArticle('Long article', text);
    await tester.pumpWidget(app(ArticleReaderScreen(articleId: id)));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final offset = (await db.getArticle(id))!['scroll_offset'] as num;
    expect(offset, greaterThan(100));
    db.close();
    db = AppDatabase(path: '${dir.path}/test.sqlite');
    await tester.pumpWidget(app(ArticleReaderScreen(articleId: id)));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scroll.position.pixels, closeTo(offset.toDouble(), 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
      'manual vocabulary creation and flashcard review persist through UI',
      (tester) async {
    await tester.pumpWidget(app(const VocabularyScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add word'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Word'), 'resilient');
    await tester.enterText(
        find.widgetWithText(TextField, 'Definition (optional)'),
        'Able to recover');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect((await db.getVocabulary()).single['word'], 'resilient');
    await tester.tap(find.text('Start review'));
    await tester.pumpAndSettle();
    expect(find.text('Able to recover'), findsNothing);
    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    expect(find.text('Able to recover'), findsOneWidget);
    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();
    final word = (await db.getVocabulary()).single;
    expect((await db.getReviewHistory(word['id'] as String)).single['rating'],
        'good');
    expect(await db.getDueReviewCount(), 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
