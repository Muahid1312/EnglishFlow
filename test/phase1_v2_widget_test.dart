import 'dart:io';
import 'support/settle_io.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/maintenance_controller.dart';
import 'package:lexiflow/core/services/providers.dart';
import 'package:lexiflow/core/services/study_session_service.dart';
import 'package:lexiflow/features/daily_plan/daily_plan_screen.dart';
import 'package:lexiflow/features/reading/reading_screen.dart';

void main() {
  late Directory dir;
  late AppDatabase db;
  late StudySessionService sessions;
  var providerOwnsSessions = false;
  setUp(() async {
    providerOwnsSessions = false;
    dir = Directory.systemTemp.createTempSync('lexiflow-phase1-widget-');
    db = AppDatabase(path: '${dir.path}/test.sqlite');
    sessions = StudySessionService(db);
    await db.saveArticle('مقاله آموزشی', 'A real saved article to read.');
    await db.updatePreferences(
        {'onboarding_completed': 1, 'daily_target_minutes': 15});
  });
  tearDown(() {
    if (!providerOwnsSessions) sessions.dispose();
    db.close();
    dir.deleteSync(recursive: true);
  });

  testWidgets('daily plan opens the real saved article and pauses on return',
      (tester) async {
    providerOwnsSessions = true;
    final router = GoRouter(initialLocation: '/plan', routes: [
      GoRoute(path: '/plan', builder: (_, __) => const DailyPlanScreen()),
      GoRoute(
          path: '/learn/reading/:id',
          builder: (_, s) =>
              ArticleReaderScreen(articleId: s.pathParameters['id']!)),
    ]);
    await tester.pumpWidget(ProviderScope(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      studySessionServiceProvider.overrideWith((ref) => sessions),
    ], child: MaterialApp.router(routerConfig: router)));
    await waitForContent(tester, find.text('15 min'));
    expect(find.text('15 min'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('مقاله آموزشی'), 250,
        scrollable: find.byType(Scrollable).first);
    final start = find.text('Start').first;
    await tester.ensureVisible(start);
    await tester.tap(start);
    await waitForContent(tester, find.byType(SelectableText));
    expect(
        find.textContaining('A real saved article to read.'), findsOneWidget);
    expect(sessions.isRunning, isTrue);
    router.pop();
    await waitForContent(tester, find.text('Continue'));
    expect(sessions.isRunning, isFalse);
    expect(find.text('Continue'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });

  testWidgets('narrow RTL plan supports goal selection and explicit skip state',
      (tester) async {
    providerOwnsSessions = true;
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          studySessionServiceProvider.overrideWith((ref) => sessions),
        ],
        child: MaterialApp(
            theme: ThemeData.dark(),
            home: const Directionality(
                textDirection: TextDirection.rtl, child: DailyPlanScreen()))));
    await waitForContent(tester, find.byType(ListView));
    await tester.scrollUntilVisible(find.text('30 min'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('30 min'));
    await waitForContent(
        tester,
        find.byWidgetPredicate((w) =>
            w is TextButton &&
            w.onPressed != null &&
            w.child is Text &&
            (w.child as Text).data == 'Skip'));
    expect((await db.getPreferences()).dailyTargetMinutes, 30);
    await tester.ensureVisible(find.text('Skip').first);
    await tester.tap(find.text('Skip').first);
    await tester.pumpAndSettle();
    final skipped = (await db.db)
        .select("SELECT state FROM planned_activities WHERE state='skipped'");
    expect(skipped, hasLength(1));
    // Removing the action buttons shrinks this card above the viewport.
    await tester.scrollUntilVisible(find.text('مقاله آموزشی'), -250,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('skipped'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('restore maintenance disposes editors before replacement work',
      (tester) async {
    final controller = MaintenanceController();
    var disposed = false;
    await tester.pumpWidget(MaterialApp(
        home: AnimatedBuilder(
            animation: controller,
            builder: (_, __) => controller.active
                ? const Text('Restoring')
                : _Editor(onDispose: () => disposed = true))));
    var disposedBeforeAction = false;
    final action = controller.run(() async {
      disposedBeforeAction = disposed;
    });
    await tester.pump();
    await action;
    expect(disposedBeforeAction, isTrue);
    expect(controller.done, isTrue);
    expect(controller.failed, isFalse);
    expect(find.text('Restoring'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

class _Editor extends StatefulWidget {
  const _Editor({required this.onDispose});
  final VoidCallback onDispose;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  @override
  Widget build(BuildContext context) => const Text('Editor');
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}
