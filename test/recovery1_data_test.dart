import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/article_import_service.dart';
import 'package:lexiflow/core/services/analytics_service.dart';
import 'package:lexiflow/core/services/certificate_service.dart';
import 'package:lexiflow/core/services/review_schedule.dart';
import 'package:lexiflow/core/services/study_session_service.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase db;
  late String path;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('lexiflow-recovery-');
    path = '${dir.path}/test.sqlite';
    db = AppDatabase(path: path);
  });
  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });

  test(
      'TXT import stores text and reading position independently of source file',
      () async {
    final file = File('${dir.path}/An article.txt');
    file.writeAsStringSync(
        '\uFEFFCuriosity helps learning.\r\nRead more today.');
    final id = await ArticleImportService(db).importFile(file);
    await db.saveReadingPosition(id, 340.5);
    file.deleteSync();
    db.close();
    db = AppDatabase(path: path);
    final article = (await db.getArticle(id))!;
    expect(article['title'], 'An article');
    expect(article['body'], 'Curiosity helps learning.\nRead more today.');
    expect(article['scroll_offset'], 340.5);
  });
  test(
      'empty, invalid UTF-8, unsupported and oversized TXT imports create no records',
      () async {
    final file = File('${dir.path}/a.txt')..writeAsStringSync('  ');
    await expectLater(
        ArticleImportService(db).importFile(file), throwsFormatException);
    file.writeAsBytesSync([255, 255]);
    await expectLater(
        ArticleImportService(db).importFile(file), throwsFormatException);
    file.writeAsStringSync('valid');
    await expectLater(ArticleImportService(db).importFile(file, name: 'a.exe'),
        throwsFormatException);
    final random = file.openSync(mode: FileMode.write);
    random.truncateSync(10 * 1024 * 1024 + 1);
    random.closeSync();
    await expectLater(
        ArticleImportService(db).importFile(file), throwsFormatException);
    expect(await db.getArticles(), isEmpty);
  });
  test('PDF channel saves extracted text; scanned PDFs report unsupported OCR',
      () async {
    final file = File('${dir.path}/text.pdf')..writeAsStringSync('%PDF-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(ArticleImportService.channel,
        (call) async {
      expect(call.method, 'extract');
      expect(call.arguments['path'], file.path);
      return 'Extracted selectable text.';
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(ArticleImportService.channel, null));
    final id = await ArticleImportService(db).importFile(file);
    expect((await db.getArticle(id))!['body'], 'Extracted selectable text.');
    messenger.setMockMethodCallHandler(
        ArticleImportService.channel, (call) async => '  ');
    await expectLater(
        ArticleImportService(db).importFile(file),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('OCR'))));
    expect((await db.getArticles()).length, 1);
  });
  test(
      'selected word saves complete sentence and duplicate source contexts survive editing',
      () async {
    const text = 'Read often. Curiosity helps learning! Try today.';
    final start = text.indexOf('Curiosity');
    final sentence = sourceSentence(text, start, start + 9);
    expect(sentence, 'Curiosity helps learning!');
    final articleId = await db.saveArticle('Article', text);
    final id = await db.saveVocabulary(
        word: 'Curiosity',
        sentence: sentence,
        source: 'Article',
        articleId: articleId);
    final duplicate = await db.saveVocabulary(
        word: ' curiosity ',
        sentence: 'A second original context.',
        source: 'Second');
    expect(duplicate, id);
    await db.saveVocabulary(
        id: id,
        word: 'CURIOSITY',
        definition: 'A desire to learn',
        translation: 'Manual translation');
    db.close();
    db = AppDatabase(path: path);
    final word = (await db.getVocabulary()).single;
    expect(word['example_sentence'], sentence);
    expect((jsonDecode(word['contexts_json'] as String) as List).length, 2);
    expect(word['definition'], 'A desire to learn');
    expect(await db.getDueReviewCount(), 1);
    final other = await db.saveVocabulary(word: 'other');
    await expectLater(
        db.saveVocabulary(id: other, word: 'curiosity'), throwsStateError);
    expect((await db.getVocabulary()).length, 2);
  });
  test(
      'review schedule and append-only history persist; replay cannot double count',
      () async {
    final id = await db.saveVocabulary(word: 'learn');
    final now = DateTime.now().toUtc().add(const Duration(seconds: 1));
    await db.reviewVocabulary(
        entryId: id,
        reviewId: 'event-1',
        rating: ReviewRating.again,
        expectedReviewCount: 0,
        now: now);
    await db.reviewVocabulary(
        entryId: id,
        reviewId: 'event-1',
        rating: ReviewRating.again,
        expectedReviewCount: 0,
        now: now);
    expect(await db.getDueVocabulary(now: now), isEmpty);
    final due = now.add(const Duration(minutes: 10));
    expect((await db.getDueVocabulary(now: due)).length, 1);
    await db.reviewVocabulary(
        entryId: id,
        reviewId: 'event-2',
        rating: ReviewRating.good,
        expectedReviewCount: 1,
        now: due);
    await expectLater(
        db.reviewVocabulary(
            entryId: id,
            reviewId: 'event-3',
            rating: ReviewRating.easy,
            expectedReviewCount: 1,
            now: due),
        throwsStateError);
    db.close();
    db = AppDatabase(path: path);
    final history = await db.getReviewHistory(id);
    expect(history.length, 2);
    expect(history.first['next_interval'], 1);
    expect(history.first['rating'], 'good');
    expect(await db.getDueReviewCount(), 0);
  });
  for (final rating in ReviewRating.values) {
    test('deterministic ${rating.name} scheduling and ease bounds', () {
      final now = DateTime.utc(2026, 11, 10, 10);
      final next = scheduleReview(
          now: now, rating: rating, intervalDays: 0, ease: 250, streak: 0);
      final durations = {
        ReviewRating.again: const Duration(minutes: 10),
        ReviewRating.hard: const Duration(days: 2),
        ReviewRating.good: const Duration(days: 1),
        ReviewRating.easy: const Duration(days: 4)
      };
      expect(next.due, now.add(durations[rating]!));
      expect(next.ease, inInclusiveRange(130, 350));
      expect(next.streak, rating == ReviewRating.again ? 0 : 1);
      final repeated = scheduleReview(
          now: now, rating: rating, intervalDays: 10, ease: 130, streak: 3);
      expect(repeated.ease, greaterThanOrEqualTo(130));
    });
  }
  test(
      'migration v4 preserves legacy records, duplicate words, contexts and certificates',
      () async {
    final raw = sqlite3.open(path);
    raw.execute(File('test/fixtures/schema_v4.sql').readAsStringSync());
    raw.execute(
        "INSERT INTO vocabulary_entries(id,word,example_sentence) VALUES('a','Learn','First context'),('b',' learn ','Second context')");
    raw.execute(
        "INSERT INTO vocabulary_reviews(id,entry_id,next_review_at) VALUES('r','b','2000-01-01')");
    raw.execute(
        "INSERT INTO study_sessions(id,module,started_at,local_date,duration_seconds,completed) VALUES('s','reading','2026-11-10','2026-11-10',120,1)");
    raw.execute(
        "INSERT INTO completion_records(id,target_type,target_id,target_title,verification_type,completed_at) VALUES('old','book','b','Legacy','legacy','2026-01-01')");
    raw.execute(
        "INSERT INTO certificates(id,completion_id,learner_name,title,ref_number,verification_type,issued_at) VALUES('cert','old','Name','Legacy','LF-OLD','legacy','2026-01-01')");
    raw.dispose();
    expect(await db.getSavedWordCount(), 1);
    expect((await db.getVocabulary()).single['word'], 'Learn');
    expect(
        (jsonDecode((await db.getVocabulary()).single['contexts_json']
                as String) as List)
            .length,
        2);
    expect(await db.getDueReviewCount(), 1);
    expect(await db.getTotalStudySeconds(), 120);
    expect((await db.getCertificates()).single['ref_number'], 'LF-OLD');
    expect(
        (await db.db)
            .select('SELECT COUNT(*) c FROM vocabulary_entries')
            .first['c'],
        2);
    expect((await db.db).select('PRAGMA foreign_key_check'), isEmpty);
    db.close();
    db = AppDatabase(path: path);
    expect(await db.getTotalStudySeconds(), 120);
    expect((await db.getCertificates()).length, 1);
  });
  test(
      'midnight session checkpoints recover without counting downtime or duplicating finish',
      () async {
    var now = DateTime(2026, 11, 10, 23, 59, 30);
    final service = StudySessionService(db, now: () => now);
    final active = await service.start('reading');
    now = now.add(const Duration(seconds: 90));
    await service.pause();
    service.dispose();
    db.close();
    db = AppDatabase(path: path);
    now = now.add(const Duration(hours: 8));
    final recovered = StudySessionService(db, now: () => now);
    await recovered.recoverInterrupted();
    expect(recovered.active!.accumulatedSeconds, 90);
    recovered.resume();
    now = now.add(const Duration(seconds: 30));
    await Future.wait([recovered.finish(), recovered.finish()]);
    expect(await db.getTotalSecondsForDate('2026-11-10'), 30);
    expect(await db.getTotalSecondsForDate('2026-11-11'), 90);
    expect(await db.getTotalStudySeconds(), 120);
    final days = await db.getSessionDays(active.id);
    expect(days, {'2026-11-10': 30000, '2026-11-11': 90000});
    expect(
        (await db.db)
            .select('SELECT COUNT(*) c FROM learning_activities')
            .first['c'],
        1);
    expect(
        (await db.db).select('SELECT COUNT(*) c FROM daily_goals').first['c'],
        2);
    recovered.dispose();
  });
  test('weekly and total analytics retain subsecond time across local days',
      () async {
    final now = DateTime.now();
    String date(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final yesterday = date(DateTime(now.year, now.month, now.day - 1));
    final today = date(now);
    await db.insertSession(
        id: 's', module: 'reading', startedAt: now, localDate: yesterday);
    await db.checkpointSession('s', {yesterday: 59999, today: 1},
        completed: true, interrupted: false, endedAt: now);
    final summary = await AnalyticsService(db).build();
    expect(summary.totalMinutes, 1);
    expect(summary.weekMinutes, 1);
    expect(await db.getTotalStudySeconds(), 60);
    expect(
        summary.last7Days
            .fold<int>(0, (total, row) => total + (row['total_ms'] as int)),
        60000);
  });
  test(
      'certificate evidence is revalidated inside the final database transaction',
      () async {
    final d = await db.db;
    d.execute(
        "INSERT INTO courses(id,title,total_lessons) VALUES('c','Course',1)");
    d.execute(
        "INSERT INTO lessons(id,course_id,title,completed) VALUES('l','c','Lesson',1)");
    await db.insertAssessmentDefinition(
        {'id': 'a', 'title': 'Assessment', 'category': 'grammar'});
    await db.insertAssessmentQuestion({
      'id': 'q',
      'assessment_id': 'a',
      'question_type': 'mc',
      'prompt': 'P',
      'correct_answer': 'A'
    });
    await db.setCompletionRequirements('course', 'c', ['a']);
    await db.saveAssessmentAttempt({
      'id': 'pass',
      'assessment_id': 'a',
      'score': 1,
      'max_score': 1,
      'passed': 1,
      'started_at': '2026-01-01',
      'completed_at': '2026-01-01'
    });
    final evidence = (await db.certificateEvidence('course', 'c'))!;
    d.execute("UPDATE lessons SET completed=0 WHERE id='l'");
    await expectLater(
        db.saveCertificateWithCompletion({
          'id': 'completion',
          'target_type': 'course',
          'target_id': 'c',
          'target_title': evidence['title'],
          'assessment_score': evidence['score'],
          'verification_type': evidence['verification_type']
        }, {}),
        throwsStateError);
    expect(await db.getCompletionRecords(), isEmpty);
    expect(await db.getCertificates(), isEmpty);
  });

  for (final type in ['book', 'course']) {
    test(
        '$type certificate needs all persisted lessons and every required assessment',
        () async {
      final d = await db.db;
      if (type == 'book') {
        await db.insertImportedBook(
            {'id': 'target', 'title': 'Book title', 'file_path': 'local.pdf'});
        await db.insertBookUnit(
            {'id': 'unit', 'book_id': 'target', 'title': 'Unit'});
        await db.insertBookLesson({
          'id': 'lesson',
          'unit_id': 'unit',
          'book_id': 'target',
          'title': 'Lesson'
        });
      } else {
        d.execute(
            "INSERT INTO courses(id,title,total_lessons) VALUES('target','Course title',1)");
        d.execute(
            "INSERT INTO lessons(id,course_id,title) VALUES('lesson','target','Lesson')");
      }
      expect(await db.certificateEvidence(type, 'target'), isNull);
      for (final id in ['a', 'b']) {
        await db.insertAssessmentDefinition(
            {'id': id, 'title': id, 'category': 'grammar'});
        await db.insertAssessmentQuestion({
          'id': 'q$id',
          'assessment_id': id,
          'question_type': 'mc',
          'prompt': 'P',
          'correct_answer': 'A'
        });
      }
      await db.setCompletionRequirements(type, 'target', ['a', 'b']);
      Future<void> pass(String id, {int self = 0}) => db.saveAssessmentAttempt({
            'id': 'pass$id$self',
            'assessment_id': id,
            'score': 0.8,
            'max_score': 1,
            'passed': 1,
            'self_assessed': self,
            'started_at': '2026-01-01',
            'completed_at': '2026-01-01'
          });
      await pass('a');
      await pass('b', self: 1);
      final table = type == 'book' ? 'book_lessons' : 'lessons';
      d.execute('UPDATE $table SET completed=1');
      expect(await db.certificateEvidence(type, 'target'), isNull);
      await pass('b');
      expect(
          (await db.certificateEvidence(type, 'target'))!['verification_type'],
          'lessons_and_assessments');
      db.close();
      db = AppDatabase(path: path);
      expect(await db.certificateEvidence(type, 'target'), isNotNull);
      (await db.db).execute('UPDATE $table SET completed=0');
      await expectLater(
          CertificateService(db).issue(
              learnerName: 'Name',
              targetType: type,
              targetId: 'target',
              targetTitle: 'Fake',
              verificationType: 'fake',
              eligible: true),
          throwsStateError);
      expect(await db.getCertificates(), isEmpty);
      (await db.db).execute('UPDATE $table SET completed=1');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path);
      addTearDown(() => messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'), null));
      final file = await CertificateService(db).issue(
          learnerName: 'Name',
          targetType: type,
          targetId: 'target',
          targetTitle: 'Fake',
          verificationType: 'fake',
          assessmentScore: 0);
      expect(File(file).existsSync(), isTrue);
      final cert = (await db.getCertificates()).single;
      expect(cert['title'], type == 'book' ? 'Book title' : 'Course title');
      expect(cert['verification_type'], 'lessons_and_assessments');
    });
  }
  test('requirements update rolls back on an invalid assessment', () async {
    final d = await db.db;
    d.execute("INSERT INTO courses(id,title) VALUES('c','Course')");
    await db.insertAssessmentDefinition(
        {'id': 'a', 'title': 'A', 'category': 'grammar'});
    await db.setCompletionRequirements('course', 'c', ['a']);
    await expectLater(db.setCompletionRequirements('course', 'c', ['missing']),
        throwsA(isA<SqliteException>()));
    expect(await db.getCompletionRequirements('course', 'c'), ['a']);
  });
}
