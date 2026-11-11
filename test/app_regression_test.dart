import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/app/app.dart';
import 'package:lexiflow/app/router/app_router.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/providers.dart';
import 'package:lexiflow/features/grammar_writing/writing/writing_studio_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('lexiflow-widget-');
    db = AppDatabase(path: '${dir.path}/app.sqlite');
    await db.getPreferences();
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });

  testWidgets(
      'actual app redirects onboarding, opens all non-hardware routes and switches theme',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const LexiFlowApp()));
    await tester.pumpAndSettle();
    expect(
        container.read(routerProvider).routeInformationProvider.value.uri.path,
        '/onboarding');
    await db.updatePreferences({'onboarding_completed': 1});
    final router = container.read(routerProvider);
    for (final route in [
      '/home',
      '/learn',
      '/practice',
      '/learn/reading',
      '/learn/vocabulary',
      '/learn/listening',
      '/learn/grammar',
      '/learn/grammar/studio',
      '/learn/grammar/writing',
      '/learn/grammar/mistakes',
      '/learn/books',
      '/progress',
      '/progress/assessments',
      '/progress/certificates',
      '/progress/export',
      '/settings'
    ]) {
      debugPrint('Checking $route');
      router.go(route);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: route);
      expect(router.routeInformationProvider.value.uri.path, route);
    }
    await tester.tap(find.text('Dark', skipOffstage: false));
    await tester.pumpAndSettle();
    expect((await db.getPreferences()).themeMode, 'dark');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  testWidgets('leaving editor inside debounce flushes text and survives reopen',
      (tester) async {
    await db
        .upsertWritingEntry({'id': 'draft', 'title': 'Draft', 'body': 'old'});
    await tester.pumpWidget(ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: WritingEditorScreen(entryId: 'draft'))));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.last, 'Newest unsaved sentence');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect((await db.getWritingEntry('draft'))!['body'],
        'Newest unsaved sentence');
    final path = '${dir.path}/app.sqlite';
    db.close();
    db = AppDatabase(path: path);
    expect((await db.getWritingEntry('draft'))!['body'],
        'Newest unsaved sentence');
    expect(tester.takeException(), isNull);
  });
}
