import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/review_schedule.dart';
import 'package:lexiflow/core/services/vocabulary_intelligence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppDatabase db;
  late VocabularyIntelligence practice;
  late DateTime now;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('lexiflow-vocabulary-v2-');
    db = AppDatabase(path: '${dir.path}/test.sqlite');
    now = DateTime.utc(2026, 11, 14, 10);
    practice = VocabularyIntelligence(db, now: () => now);
  });
  tearDown(() {
    db.close();
    dir.deleteSync(recursive: true);
  });
  Future<String> word(String text,
      {String? definition, String? sentence}) async {
    final id = await db.saveVocabulary(
        word: text,
        definition: definition,
        sentence: sentence,
        source: 'Saved article');
    (await db.db).execute(
        "UPDATE vocabulary_reviews SET next_review_at='2026-11-10T10:00:00Z' WHERE entry_id=?",
        [id]);
    return id;
  }

  test('rich fields edit without losing original reading context or schedules',
      () async {
    final id = await word('preserve',
        definition: 'keep safe', sentence: 'Preserve your original context.');
    await db.saveVocabulary(
        id: id,
        word: 'Preserve',
        definition: 'keep intact',
        translation: 'حفظ کردن',
        usageExample: 'Preserve this text.',
        collocations: 'preserve evidence',
        pronunciation: '/prɪˈzɜrv/',
        personalNotes: 'My own note',
        partOfSpeech: 'verb');
    final entry = (await db.getVocabulary()).single;
    expect(entry['translation'], 'حفظ کردن');
    expect(entry['collocations'], 'preserve evidence');
    expect(entry['personal_notes'], 'My own note');
    expect(
        (jsonDecode(entry['contexts_json'] as String) as List)
            .single['sentence'],
        'Preserve your original context.');
    expect((await db.getDueVocabulary(now: now)).single['id'], id);
    final same = await db.saveVocabulary(
        word: '  PRESERVE ',
        sentence: 'Preserve this second context.',
        source: 'Second article',
        personalNotes: '',
        collocations: '');
    expect(same, id);
    expect(await db.getVocabulary(), hasLength(1));
    expect((await db.getVocabulary()).single['personal_notes'], 'My own note');
    expect(
        (jsonDecode(
                (await db.getVocabulary()).single['contexts_json'] as String)
            as List),
        hasLength(2));
  });
  test(
      'duplicate editing is rejected and prefix search treats wildcard characters literally',
      () async {
    await word('alpha');
    final beta = await word('beta');
    await expectLater(
        db.saveVocabulary(id: beta, word: ' ALPHA '), throwsStateError);
    await word('percent%');
    expect(await db.getVocabulary(search: 'percent%'), hasLength(1));
    expect(await db.getVocabulary(search: '%'), isEmpty);
    expect(await db.getVocabulary(search: 'al', limit: 1), hasLength(1));
  });
  for (final limit in [5, 10, 15, 0]) {
    test('$limit-word queue persists deterministic unique due items', () async {
      for (var i = 0; i < 17; i++) {
        await word('word$i');
      }
      final session = await practice.open(limit: limit);
      final before = await practice.items(session);
      expect(before.length, limit == 0 ? 17 : limit);
      expect(before.map((r) => r['id']).toSet().length, before.length);
      db.close();
      db = AppDatabase(path: '${dir.path}/test.sqlite');
      practice = VocabularyIntelligence(db, now: () => now);
      final resumed = await practice.open(limit: 15);
      expect(resumed, session);
      expect(await practice.state(session), 'paused');
      expect(
          (await practice.items(session)).map((r) => r['review_id']).toList(),
          before.map((r) => r['review_id']).toList());
    });
  }
  test('review rating, durable item state and history commit exactly once',
      () async {
    final id = await word('resilient');
    final session = await practice.open();
    final item = (await practice.items(session)).single;
    await expectLater(
        practice.rate(session, item, ReviewRating.good), throwsStateError);
    await practice.reveal(session, item['position'] as int);
    await practice.rate(session, item, ReviewRating.again);
    await practice.rate(session, item, ReviewRating.again);
    expect(await db.getReviewHistory(id), hasLength(1));
    expect((await practice.items(session)).single['item_state'], 'reviewed');
    expect(await practice.state(session), 'completed');
    final history = (await db.getReviewHistory(id)).single;
    expect(DateTime.parse(history['next_due'] as String),
        now.add(const Duration(minutes: 10)));
    expect(await db.getDueVocabulary(now: now), isEmpty);
    now = now.add(const Duration(minutes: 10));
    expect(await db.getDueVocabulary(now: now), hasLength(1));
  });
  test('paused sessions cannot be rated; reveal state survives restarts',
      () async {
    await word('pause');
    final id = await practice.open();
    final item = (await practice.items(id)).single;
    await practice.reveal(id, 0);
    await practice.pause(id);
    await expectLater(
        practice.rate(id, item, ReviewRating.good), throwsStateError);
    expect((await practice.items(id)).single['revealed'], 1);
    await practice.pause(id, resume: true);
    await practice.rate(id, item, ReviewRating.good);
    expect(await practice.state(id), 'completed');
  });
  test(
      'removed words and independently reviewed words skip without duplicate reviews',
      () async {
    final first = await word('first');
    final second = await word('second');
    final id = await practice.open();
    (await db.db).execute(
        'UPDATE vocabulary_entries SET is_saved=0 WHERE id=?', [first]);
    await db.reviewVocabulary(
        entryId: second,
        reviewId: 'external-review',
        rating: ReviewRating.easy,
        expectedReviewCount: 0,
        now: now);
    final items = await practice.items(id);
    expect(items.every((r) => r['item_state'] == 'skipped'), isTrue);
    expect(await practice.state(id), 'completed');
    expect(await db.getReviewHistory(second), hasLength(1));
  });
  test(
      'overdue, repeated failures, recent failure and stable IDs determine priority',
      () async {
    final old = await word('overdue');
    final failed = await word('frequently forgotten');
    for (var i = 0; i < 2; i++) {
      await db.reviewVocabulary(
          entryId: failed,
          reviewId: 'failure-$i',
          rating: ReviewRating.again,
          expectedReviewCount: i,
          now: now);
      now = now.add(const Duration(minutes: 10));
    }
    // Due today is after genuinely overdue material, even when failed repeatedly.
    final id = await practice.open();
    final items = await practice.items(id);
    expect(items.first['id'], old);
    expect(items.last['id'], failed);
  });
  test(
      'UTC due boundary is inclusive and does not depend on local display dates',
      () async {
    final id = await word('boundary');
    (await db.db).execute(
        'UPDATE vocabulary_reviews SET next_review_at=? WHERE entry_id=?',
        [now.toIso8601String(), id]);
    expect(
        await db.getDueVocabulary(
            now: now.subtract(const Duration(microseconds: 1000))),
        isEmpty);
    expect(await db.getDueVocabulary(now: now), hasLength(1));
  });
  test(
      'all ratings preserve valid existing scheduler semantics and nonnegative intervals',
      () {
    for (final rating in ReviewRating.values) {
      final next = scheduleReview(
          now: now, rating: rating, intervalDays: 0, ease: 250, streak: 0);
      expect(next.due.isAfter(now), isTrue);
      expect(next.intervalDays, greaterThanOrEqualTo(0));
    }
    expect(
        scheduleReview(
                now: now,
                rating: ReviewRating.good,
                intervalDays: 0,
                ease: 250,
                streak: 0)
            .intervalDays,
        1);
    expect(
        scheduleReview(
                now: now,
                rating: ReviewRating.good,
                intervalDays: 1,
                ease: 250,
                streak: 1)
            .intervalDays,
        3);
    expect(
        scheduleReview(
                now: now,
                rating: ReviewRating.hard,
                intervalDays: 0,
                ease: 250,
                streak: 0)
            .intervalDays,
        2);
    expect(
        scheduleReview(
                now: now,
                rating: ReviewRating.easy,
                intervalDays: 0,
                ease: 250,
                streak: 0)
            .intervalDays,
        4);
  });
  test('analytics count unique persisted ratings and exclude removed words',
      () async {
    final first = await word('one');
    final second = await word('two');
    await db.reviewVocabulary(
        entryId: first,
        reviewId: 'good',
        rating: ReviewRating.good,
        expectedReviewCount: 0,
        now: now);
    await db.reviewVocabulary(
        entryId: first,
        reviewId: 'good',
        rating: ReviewRating.good,
        expectedReviewCount: 0,
        now: now);
    await db.reviewVocabulary(
        entryId: second,
        reviewId: 'hard',
        rating: ReviewRating.hard,
        expectedReviewCount: 0,
        now: now);
    final stats = await practice.insights();
    expect(stats['reviews'], 2);
    expect(stats['reviewed'], 2);
    expect(stats['successRate'], 0.5);
    expect(stats['trend'], isNull);
    (await db.db).execute(
        'UPDATE vocabulary_entries SET is_saved=0 WHERE id=?', [first]);
    final filtered = await practice.insights();
    expect(filtered['saved'], 1);
    expect(filtered['reviews'], 1);
    expect(filtered['successRate'], 0);
  });
  test(
      'legacy review counters count reviewed words without fabricating logged ratings',
      () async {
    final id = await word('legacy');
    (await db.db).execute(
        'UPDATE vocabulary_reviews SET review_count=4 WHERE entry_id=?', [id]);
    final stats = await practice.insights();
    expect(stats['reviewed'], 1);
    expect(stats['reviews'], 0);
    expect(stats['successRate'], isNull);
  });
  test(
      'challenges use saved content, reject ambiguous meanings and do not change schedules',
      () async {
    await word('preserve',
        definition: 'keep safe', sentence: 'Preserve the source sentence.');
    await word('learn',
        definition: 'gain knowledge', sentence: 'We learn every day.');
    final words = await db.getVocabulary();
    for (final type in VocabularyChallengeType.values) {
      final first = vocabularyChallenges(words, type);
      final second = vocabularyChallenges(words.reversed.toList(), type);
      expect(first, hasLength(2));
      expect(first.map((q) => q.prompt).toList(),
          second.map((q) => q.prompt).toList());
      expect(
          first.first.matches(' ${first.first.answer.toUpperCase()} '), isTrue);
      expect(first.first.matches('invented'), isFalse);
    }
    await word('protect', definition: ' KEEP SAFE ');
    final ambiguous = vocabularyChallenges(
        await db.getVocabulary(), VocabularyChallengeType.recall);
    expect(ambiguous.map((q) => q.answer), ['learn']);
    expect((await practice.insights())['reviews'], 0);
  });
  test('context challenge rejects repeated and substring occurrences',
      () async {
    await word('cat', sentence: 'The caterpillar sleeps.');
    await word('again', sentence: 'Again and again.');
    expect(
        vocabularyChallenges(
            await db.getVocabulary(), VocabularyChallengeType.context),
        isEmpty);
  });
  test('identical blank prompts with different saved answers are rejected',
      () async {
    await word('cat', sentence: 'I have a cat.');
    await word('dog', sentence: 'I have a dog.');
    expect(
        vocabularyChallenges(
            await db.getVocabulary(), VocabularyChallengeType.context),
        isEmpty);
  });
}
