import 'dart:io';
import 'support/settle_io.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/builtin_content_service.dart';
import 'package:lexiflow/core/services/providers.dart';
import 'package:lexiflow/features/content/builtin_library_screen.dart';
import 'package:lexiflow/features/reading/reading_screen.dart';

void main() {
  late Directory directory;
  late AppDatabase database;
  late BuiltinCatalog catalog;
  setUp(() async {
    directory = Directory.systemTemp.createTempSync('lexiflow-library-widget-');
    database = AppDatabase(path: '${directory.path}/learning.sqlite');
    await database.db;
    catalog = await BuiltinCatalog.load();
  });
  tearDown(() {
    database.close();
    directory.deleteSync(recursive: true);
  });
  Widget app(Widget screen) => ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp(home: screen),
      );

  testWidgets(
      'offline article library filters, bookmarks, and opens the existing reader',
      (tester) async {
    final router = GoRouter(initialLocation: '/library', routes: [
      GoRoute(
          path: '/library', builder: (_, __) => const BuiltinLibraryScreen()),
      GoRoute(
          path: '/learn/reading/:id',
          builder: (_, state) =>
              ArticleReaderScreen(articleId: state.pathParameters['id']!)),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: MaterialApp.router(routerConfig: router)));
    await waitForContent(tester, find.text('100 articles'));
    expect(find.text('100 articles'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'B2'));
    await tester.pumpAndSettle();
    expect(find.text('50 articles'), findsOneWidget);
    final article = catalog.articles.firstWhere((a) => a['level'] == 'B2');
    await tester.enterText(find.byType(TextField), article['title'] as String);
    await tester.pumpAndSettle();
    expect(find.text('1 articles'), findsOneWidget);
    await tester.tap(find.byTooltip('Bookmark article'));
    await waitForContent(tester, find.byTooltip('Remove bookmark'));
    await tester.tap(find.widgetWithText(FilterChip, 'Bookmarked'));
    await tester.pumpAndSettle();
    final articleTile = find.widgetWithText(ListTile, article['title'] as String);
    expect(articleTile, findsOneWidget);
    await tester.tap(articleTile);
    await waitForContent(tester, find.byType(SelectableText));
    expect(find.widgetWithText(SelectableText, article['body'] as String),
        findsOneWidget);
    expect(
        (await BuiltinContentService(database).states()).single['completed_at'],
        isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'built-in word save creates one personal SRS card on a small screen',
      (tester) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(const BuiltinLibraryScreen(vocabulary: true)));
    await waitForContent(tester, find.text('1000 words'));
    expect(await database.getVocabulary(), isEmpty);
    await tester.enterText(find.byType(TextField), 'infrastructure');
    await tester.pumpAndSettle();
    final save = find.text('Save to personal vocabulary');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await waitForContent(tester, find.text('In personal vocabulary'));
    final personal = (await database.getVocabulary()).single;
    expect(personal['word'], 'infrastructure');
    expect(
        personal['definition'], catalog.word('v_infrastructure')['definition']);
    expect((await database.db).select('SELECT * FROM vocabulary_reviews'),
        hasLength(1));
    expect(find.text('In personal vocabulary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'offline reader requires explicit reading and grades actual choices with answer review',
      (tester) async {
    final article = catalog.articles.first;
    await tester.pumpWidget(
        app(ArticleReaderScreen(articleId: 'builtin:${article['id']}')));
    await waitForContent(tester, find.byType(SelectableText));
    expect(find.widgetWithText(SelectableText, article['body'] as String),
        findsOneWidget);
    expect((await database.db).select('SELECT * FROM builtin_reading_attempts'),
        isEmpty);
    for (final question in article['questions'] as List) {
      final correct =
          (question['choices'] as List)[question['answer'] as int] as String;
      final radio = find.widgetWithText(RadioListTile<String>, correct);
      await tester.ensureVisible(radio);
      await tester.tap(radio);
      await tester.pumpAndSettle();
    }
    final confirmed = find.widgetWithText(
        CheckboxListTile, 'I finished reading this article');
    await tester.ensureVisible(confirmed);
    await tester.tap(confirmed);
    final submit = find.widgetWithText(FilledButton, 'Submit answers');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await waitForContent(tester, find.textContaining('4/4 correct.'));
    expect(
        (await database.db)
            .select('SELECT correct,total FROM builtin_reading_attempts')
            .single,
        {'correct': 4, 'total': 4});
    final review = find.text('Review answers and explanations');
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pumpAndSettle();
    expect(find.text('Saved result: 4/4'), findsOneWidget);
    expect(
        find.text(((article['questions'] as List).first as Map)['explanation']
            as String),
        findsOneWidget);
    expect((await database.db).select('SELECT * FROM study_sessions'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
