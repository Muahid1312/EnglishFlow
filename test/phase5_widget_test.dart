import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/providers.dart';
import 'package:lexiflow/features/assessments/assessments_screen.dart';
import 'package:lexiflow/features/books/books_screen.dart';
import 'package:lexiflow/main.dart' as application;

class _UnavailableDatabase extends AppDatabase {
  _UnavailableDatabase() : super(path: ':memory:');
  @override
  Future<List<Map<String, dynamic>>> getAssessmentQuestions(String assessmentId) async => throw StateError('fixture storage unavailable');
  @override
  Future<Map<String, dynamic>?> getAssessment(String id) async => throw StateError('fixture storage unavailable');
  @override
  Future<Map<String, dynamic>?> getImportedBook(String id) async => throw StateError('fixture storage unavailable');
}

void main() {
  testWidgets('startup failure shows safe retry and reports diagnostics', (tester) async {
    final previous = FlutterError.onError;
    final errors = <FlutterErrorDetails>[];
    FlutterError.onError = errors.add;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if(call.method=='SystemChrome.setPreferredOrientations')throw PlatformException(code:'fixture');
      return null;
    });
    addTearDown(() {
      FlutterError.onError = previous;
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await application.main();
    await tester.pumpAndSettle();
    expect(find.textContaining('Your learning data has not been reset'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(errors.single.library, 'LexiFlow startup');
  });

  testWidgets('assessment storage failure ends spinner and offers retry', (tester) async {
    final database = _UnavailableDatabase();
    addTearDown(database.close);
    await tester.pumpWidget(ProviderScope(overrides: [appDatabaseProvider.overrideWithValue(database)], child: const MaterialApp(home: AssessmentTakeScreen(assessmentId: 'test'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not load learning records'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('PDF storage failure becomes visible instead of an unhandled future', (tester) async {
    final database = _UnavailableDatabase();
    addTearDown(database.close);
    await tester.pumpWidget(ProviderScope(overrides: [appDatabaseProvider.overrideWithValue(database)], child: const MaterialApp(home: BookReaderScreen(bookId: 'test'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not open PDF'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
