import 'dart:convert';

import '../database/app_database.dart';
import '../utils/id_utils.dart';
import 'review_schedule.dart';

class VocabularyIntelligence {
  VocabularyIntelligence(this.database, {DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final AppDatabase database;
  final DateTime Function() _now;

  Future<String> open(
      {int limit = 5, bool fresh = false, String? entryId}) async {
    if (![0, 5, 10, 15].contains(limit))
      throw ArgumentError('Choose 5, 10, 15 or all due.');
    final db = await database.db;
    // The due query exposes canonical saved words and the earliest legacy schedule.
    final due = (await database.getDueVocabulary(now: _now())).toList();
    final stats = {
      for (final r in db.select(
          "SELECT entry_id,COUNT(*) failures,MAX(reviewed_at) recent FROM vocabulary_review_history WHERE rating='again' GROUP BY entry_id"))
        r['entry_id']: r
    };
    due.sort((a, b) {
      final da = DateTime.parse(a['next_review_at'] as String).toUtc();
      final dbDate = DateTime.parse(b['next_review_at'] as String).toUtc();
      // Calendar-day overdue bucket first, then persisted failure evidence.
      final overdueA = _now().toUtc().difference(da).inDays > 0;
      final overdueB = _now().toUtc().difference(dbDate).inDays > 0;
      if (overdueA != overdueB) return overdueA ? -1 : 1;
      final fa = stats[a['id']]?['failures'] as int? ?? 0;
      final fb = stats[b['id']]?['failures'] as int? ?? 0;
      if (fa != fb) return fb.compareTo(fa);
      final recent = (stats[b['id']]?['recent'] as String? ?? '')
          .compareTo(stats[a['id']]?['recent'] as String? ?? '');
      if (recent != 0) return recent;
      final date = da.compareTo(dbDate);
      return date != 0
          ? date
          : (a['id'] as String).compareTo(b['id'] as String);
    });
    final queue = due
        .where((r) => entryId == null || r['id'] == entryId)
        .take(limit == 0 ? due.length : limit)
        .toList();
    db.execute('BEGIN IMMEDIATE');
    try {
      final existing = db.select(
          "SELECT * FROM vocabulary_practice_sessions WHERE state IN ('active','paused') ORDER BY created_at,id LIMIT 1");
      if (existing.isNotEmpty && !fresh && entryId == null) {
        final id = existing.single['id'] as String;
        db.execute(
            "UPDATE vocabulary_practice_sessions SET state='paused' WHERE id=?",
            [id]);
        db.execute('COMMIT');
        return id;
      }
      if (queue.isEmpty) throw StateError('No due words are available.');
      db.execute(
          "UPDATE vocabulary_practice_sessions SET state='ended' WHERE state IN ('active','paused')");
      final id = newId();
      db.execute(
          "INSERT INTO vocabulary_practice_sessions VALUES(?,?,'active',?)",
          [id, limit, _now().toUtc().toIso8601String()]);
      for (var i = 0; i < queue.length; i++) {
        db.execute(
            'INSERT INTO vocabulary_practice_items(session_id,position,entry_id,review_id,expected_count) VALUES(?,?,?,?,?)',
            [id, i, queue[i]['id'], newId(), queue[i]['review_count']]);
      }
      db.execute('COMMIT');
      return id;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> items(String id) async {
    final db = await database.db;
    db.execute(
        """UPDATE vocabulary_practice_items SET state='skipped' WHERE session_id=? AND state='pending'
      AND (entry_id IN (SELECT id FROM vocabulary_entries WHERE is_saved=0) OR
      NOT EXISTS(SELECT 1 FROM vocabulary_reviews r WHERE r.entry_id=vocabulary_practice_items.entry_id
        AND r.review_count=vocabulary_practice_items.expected_count AND julianday(r.next_review_at)<=julianday(?)))""",
        [id, _now().toUtc().toIso8601String()]);
    db.execute(
        """UPDATE vocabulary_practice_sessions SET state='completed' WHERE id=? AND state!='ended'
      AND NOT EXISTS(SELECT 1 FROM vocabulary_practice_items WHERE session_id=? AND state='pending')""",
        [id, id]);
    return db.select(
        '''SELECT e.*,i.position,i.review_id,i.expected_count,i.state AS item_state,i.revealed,i.rating
      FROM vocabulary_practice_items i JOIN vocabulary_entries e ON e.id=i.entry_id WHERE i.session_id=? ORDER BY i.position''',
        [id]);
  }

  Future<String> state(String id) async => (await database.db).select(
      'SELECT state FROM vocabulary_practice_sessions WHERE id=?',
      [id]).single['state'] as String;
  Future<void> pause(String id, {bool resume = false}) async =>
      (await database.db).execute(
          "UPDATE vocabulary_practice_sessions SET state=? WHERE id=? AND state IN ('active','paused')",
          [resume ? 'active' : 'paused', id]);
  Future<void> reveal(String id, int position) async => (await database.db).execute(
      "UPDATE vocabulary_practice_items SET revealed=1 WHERE session_id=? AND position=? AND state='pending'",
      [id, position]);
  Future<void> rate(
          String session, Map<String, dynamic> item, ReviewRating rating) =>
      database.reviewVocabulary(
          entryId: item['id'] as String,
          reviewId: item['review_id'] as String,
          rating: rating,
          expectedReviewCount: item['expected_count'] as int,
          practiceSessionId: session,
          practicePosition: item['position'] as int,
          now: _now());

  Future<Map<String, dynamic>> insights() async {
    final db = await database.db;
    final due = (await database.getDueVocabulary(now: _now())).length;
    final saved = db
        .select(
            'SELECT COUNT(*) n FROM vocabulary_entries WHERE is_saved=1 AND duplicate_of IS NULL')
        .single['n'];
    final counts = db.select("""SELECT COUNT(*) reviews,
      COALESCE(SUM(CASE WHEN h.rating IN ('good','easy') THEN 1 ELSE 0 END),0) successes
      FROM vocabulary_review_history h JOIN vocabulary_entries e ON e.id=h.entry_id
      WHERE e.is_saved=1 AND e.duplicate_of IS NULL""").single;
    final history = db.select(
        '''SELECT h.*,e.word FROM vocabulary_review_history h JOIN vocabulary_entries e ON e.id=h.entry_id
      WHERE e.is_saved=1 AND e.duplicate_of IS NULL ORDER BY h.reviewed_at DESC,h.id DESC LIMIT 20''');
    final reviewed = db.select(
            '''SELECT COUNT(*) n FROM vocabulary_entries e WHERE e.is_saved=1 AND e.duplicate_of IS NULL
      AND (EXISTS(SELECT 1 FROM vocabulary_review_history h WHERE h.entry_id=e.id)
        OR EXISTS(SELECT 1 FROM vocabulary_reviews r WHERE r.entry_id=e.id AND r.review_count>0))''').single[
        'n'] as int;
    final reviews = counts['reviews'] as int;
    final successes = counts['successes'] as int;
    final forgotten = db.select(
        """SELECT e.word,COUNT(*) failures FROM vocabulary_review_history h
      JOIN vocabulary_entries e ON e.id=h.entry_id WHERE e.is_saved=1 AND e.duplicate_of IS NULL AND h.rating='again'
      GROUP BY e.id HAVING COUNT(*)>=2 ORDER BY failures DESC,e.word LIMIT 5""");
    final recent = history.take(10).toList();
    double rate(List<Map<String, dynamic>> rows) =>
        rows.where((r) => ['good', 'easy'].contains(r['rating'])).length /
        rows.length;
    double? trend;
    if (history.length >= 20) {
      trend = rate(history.sublist(0, 10)) - rate(history.sublist(10, 20));
    }
    return {
      'saved': saved,
      'due': due,
      'reviewed': reviewed,
      'reviews': reviews,
      'successRate': reviews == 0 ? null : successes / reviews,
      'forgotten': forgotten,
      'recent': recent,
      'trend': trend
    };
  }
}

enum VocabularyChallengeType { context, meaning, recall }

class VocabularyChallenge {
  const VocabularyChallenge(
      this.type, this.entryId, this.prompt, this.answer, this.options);
  final VocabularyChallengeType type;
  final String entryId, prompt, answer;
  final List<String> options;
  bool matches(String response) =>
      normalizeWord(response) == normalizeWord(answer);
}

/// Practice never changes SRS state. Only explicit flashcard ratings do so.
List<VocabularyChallenge> vocabularyChallenges(
    List<Map<String, dynamic>> words, VocabularyChallengeType type) {
  final sorted = words
      .where((w) => w['is_saved'] == 1 && w['duplicate_of'] == null)
      .toList()
    ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  final meanings = <String, int>{};
  for (final w in sorted) {
    final meaning = normalizeWord(w['definition'] as String? ?? '');
    if (meaning.isNotEmpty)
      meanings.update(meaning, (n) => n + 1, ifAbsent: () => 1);
  }
  final result = <VocabularyChallenge>[];
  for (final w in sorted) {
    final word = w['word'] as String;
    final meaning = (w['definition'] as String? ?? '').trim();
    if (type == VocabularyChallengeType.context) {
      final contexts = jsonDecode(w['contexts_json'] as String) as List;
      final sentence =
          (w['usage_example'] as String?)?.trim().isNotEmpty == true
              ? w['usage_example'] as String
              : contexts.isEmpty
                  ? ''
                  : contexts.first['sentence'] as String;
      final pattern = RegExp(
          '(?<![A-Za-z0-9_])${RegExp.escape(word)}(?![A-Za-z0-9_])',
          caseSensitive: false);
      final matches = pattern.allMatches(sentence).toList();
      // One literal occurrence and no other saved word usable in this template.
      if (matches.length != 1 ||
          sorted.any((other) =>
              other['id'] != w['id'] &&
              normalizeWord(other['word'] as String) == normalizeWord(word)))
        continue;
      final m = matches.single;
      result.add(VocabularyChallenge(type, w['id'] as String,
          sentence.replaceRange(m.start, m.end, '_____'), word, const []));
    } else {
      if (meaning.isEmpty || meanings[normalizeWord(meaning)] != 1) continue;
      if (type == VocabularyChallengeType.recall) {
        result.add(VocabularyChallenge(
            type, w['id'] as String, meaning, word, const []));
      } else {
        final options = sorted
            .map((r) => (r['definition'] as String? ?? '').trim())
            .where((d) => d.isNotEmpty && meanings[normalizeWord(d)] == 1)
            .toSet()
            .take(4)
            .toList();
        if (!options.contains(meaning)) {
          if (options.isNotEmpty) options.removeLast();
          options.add(meaning);
        }
        if (options.length < 2) continue;
        options.sort((a, b) => normalizeWord(a).compareTo(normalizeWord(b)));
        result.add(VocabularyChallenge(
            type, w['id'] as String, word, meaning, options));
      }
    }
  }
  final prompts = <String, int>{};
  for (final q in result) {
    prompts.update(normalizeWord(q.prompt), (n) => n + 1, ifAbsent: () => 1);
  }
  return result
      .where((q) => prompts[normalizeWord(q.prompt)] == 1)
      .take(5)
      .toList();
}
