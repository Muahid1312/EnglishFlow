import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/listening_downloads.dart';
import 'package:lexiflow/core/services/providers.dart';
import 'package:lexiflow/features/listening_speaking/listening/listening_library_screen.dart';

import 'listening_downloads_test.dart' as f;
import 'support/settle_io.dart';

void main() {
  late Directory directory;
  late AppDatabase database;
  late ListeningDownloads downloads;
  late ListeningCatalog catalog;
  late f.FakeAudioTransport transport;
  var providerOwns = false;
  setUp(() async {
    providerOwns = false;
    directory =
        Directory.systemTemp.createTempSync('lexiflow-download-widget-');
    database = AppDatabase(path: '${directory.path}/data.sqlite');
    catalog = ListeningCatalog.parse(
        await File('assets/listening/catalog_v1.json').readAsString());
    final bytes =
        await File('listening_catalog/media/${catalog.lessons.first['file']}')
            .readAsBytes();
    transport = f.FakeAudioTransport(
        (uri, headers) => f.reply(bytes, headers: {'accept-ranges': 'bytes'}));
    downloads = ListeningDownloads(database,
        catalog: () async => catalog,
        documents: () async => Directory('${directory.path}/documents'),
        availableBytes: () async => 1 << 34,
        transport: transport,
        observeLifecycle: false);
    await downloads.initialize();
  });
  tearDown(() {
    if (!providerOwns) { downloads.dispose(); }
    database.close();
    directory.deleteSync(recursive: true);
  });
  Widget app(Widget page) {
    providerOwns = true;
    return ProviderScope(overrides: [
      appDatabaseProvider.overrideWithValue(database),
      listeningDownloadsProvider.overrideWith((ref) => downloads)
    ], child: MaterialApp(home: page));
  }

  testWidgets(
      'discovery shows real metadata and never offers external provider downloads',
      (tester) async {
    await tester.pumpWidget(app(const ListeningLibraryScreen()));
    await waitForContent(tester, find.text('Planning a Short Study Session'));
    expect(find.textContaining('SLT synthetic voice'), findsOneWidget);
    expect(find.textContaining('American'), findsWidgets);
    expect(await database.getListeningLessons(), isEmpty);
    await tester.scrollUntilVisible(find.text('VOA Learning English'), 400,
        scrollable: find.byType(Scrollable).first);
    final provider = find.widgetWithText(ListTile, 'VOA Learning English');
    expect(find.descendant(of: provider, matching: find.text('Listen Online')),
        findsOneWidget);
    expect(find.descendant(of: provider, matching: find.text('Download')),
        findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
      'download becomes playable only after verified local storage and navigation passes the saved lesson',
      (tester) async {
    final router = GoRouter(initialLocation: '/library', routes: [
      GoRoute(
          path: '/library', builder: (_, __) => const ListeningLibraryScreen()),
      GoRoute(
          path: '/learn/listening/player/:id',
          builder: (_, s) =>
              Scaffold(body: Text('Player: ${s.pathParameters['id']}'))),
    ]);
    addTearDown(router.dispose);
    providerOwns = true;
    await tester.pumpWidget(ProviderScope(overrides: [
      appDatabaseProvider.overrideWithValue(database),
      listeningDownloadsProvider.overrideWith((ref) => downloads)
    ], child: MaterialApp.router(routerConfig: router)));
    await waitForContent(tester, find.text('Planning a Short Study Session'));
    final card =
        find.byKey(const ValueKey('catalog-planning-a-short-study-session'));
    await tester
        .tap(find.descendant(of: card, matching: find.text('Download')));
    await waitForContent(
        tester, find.descendant(of: card, matching: find.text('Downloaded')));
    final saved = (await database.getListeningLessons()).single;
    expect(File(saved['audio_path'] as String).existsSync(), isTrue);
    await tester
        .tap(find.descendant(of: card, matching: find.text('Play offline')));
    await tester.pumpAndSettle();
    expect(find.text('Player: ${saved['id']}'), findsOneWidget);
    expect(transport.requests, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  testWidgets(
      'downloaded audio deletion preserves the lesson and its study position',
      (tester) async {
    await downloads.enqueue(catalog.lessons.first['id'] as String);
    await downloads.waitUntilIdle().timeout(const Duration(seconds: 15));
    final saved = (await database.getListeningLessons()).single;
    await database.updateLessonPosition(saved['id'] as String, 12000);
    await tester.pumpWidget(app(const ListeningLibraryScreen()));
    await waitForContent(tester, find.text('Delete audio'));
    await tester.tap(find.text('Delete audio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await waitForContent(tester,
        find.textContaining('Audio unavailable; study records retained'));
    expect(
        (await database
            .getListeningLesson(saved['id'] as String))!['last_position_ms'],
        12000);
    expect(await database.getQuestions(saved['id'] as String), hasLength(4));
    expect(File(saved['audio_path'] as String).existsSync(), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
