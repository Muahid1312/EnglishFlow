import 'review_schedule.dart' show normalizeWord;
import 'dart:convert';
import 'package:flutter/services.dart';
import '../database/app_database.dart';
import '../utils/date_utils.dart';
import 'assessment_grading.dart';

/// Immutable bundled teaching material. Opening it never fills the personal
/// vocabulary queue or creates an imported/user-authored article.
class BuiltinCatalog {
  BuiltinCatalog._(this.version, this.words, this.articles);
  final String version;
  final List<Map<String, dynamic>> words, articles;
  static Future<BuiltinCatalog>? _cached;
  static BuiltinCatalog? _loaded;
  static Future<BuiltinCatalog> load() {
    final loaded = _loaded;
    // Return a fresh future for completed data, so callers in a later async
    // scope do not depend on the scheduling zone of the original asset load.
    if (loaded != null) return Future.value(loaded);
    return _cached ??= read(rootBundle.loadString).then((catalog) {
      _loaded = catalog;
      return catalog;
    }).catchError((Object error, StackTrace stack) {
      _cached = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  static Future<BuiltinCatalog> read(
      Future<String> Function(String) loader) async {
    final manifest = jsonDecode(await loader('assets/content/v1/manifest.json'))
        as Map<String, dynamic>;
    if (manifest['schema_version'] != 1) {
      throw const FormatException('Unsupported content library.');
    }
    Future<List<Map<String, dynamic>>> batches(String key, String field) async {
      final result = <Map<String, dynamic>>[];
      for (final path in manifest[key] as List) {
        if (!RegExp(r'^assets/content/v1/[a-z0-9_]+\.json$')
            .hasMatch(path as String)) {
          throw const FormatException('Invalid content path.');
        }
        final batch = jsonDecode(await loader(path)) as Map<String, dynamic>;
        if (batch['version'] != 1) {
          throw const FormatException('Unsupported content batch.');
        }
        result.addAll((batch[field] as List)
            .map((e) => Map<String, dynamic>.unmodifiable(e as Map)));
      }
      return List.unmodifiable(result);
    }

    return BuiltinCatalog._(
        manifest['content_version'] as String,
        await batches('vocabulary_files', 'entries'),
        await batches('article_files', 'articles'));
  }

  Map<String, dynamic> word(String id) => words.firstWhere((w) => w['id'] == id,
      orElse: () => throw StateError('Built-in word not found.'));
  Map<String, dynamic> article(String id) =>
      articles.firstWhere((a) => a['id'] == id,
          orElse: () => throw StateError('Built-in article not found.'));
}

class BuiltinContentService {
  BuiltinContentService(this.database,
      {Future<BuiltinCatalog> Function()? catalog, DateTime Function()? now})
      : _catalog = catalog ?? BuiltinCatalog.load,
        _now = now ?? DateTime.now;
  final AppDatabase database;
  final DateTime Function() _now;
  final Future<BuiltinCatalog> Function() _catalog;
  Future<List<Map<String, dynamic>>> states() async =>
      (await database.db).select('SELECT * FROM builtin_article_state');
  Future<Map<String, dynamic>> openArticle(String id) async {
    final article = (await _catalog()).article(id);
    final d = await database.db;
    d.execute(
        'INSERT INTO builtin_article_state(article_id,last_opened_at) VALUES(?,?) ON CONFLICT(article_id) DO UPDATE SET last_opened_at=excluded.last_opened_at',
        [id, _now().toUtc().toIso8601String()]);
    return {
      ...article,
      ...d.select(
          'SELECT * FROM builtin_article_state WHERE article_id=?', [id]).single
    };
  }

  Future<void> savePosition(String id, double offset) async {
    if (!offset.isFinite || offset < 0) return;
    (await database.db).execute(
        'UPDATE builtin_article_state SET scroll_offset=? WHERE article_id=?',
        [offset, id]);
  }

  Future<void> bookmark(String id, bool saved) async {
    (await _catalog()).article(id);
    (await database.db).execute(
        'INSERT INTO builtin_article_state(article_id,bookmarked) VALUES(?,?) ON CONFLICT(article_id) DO UPDATE SET bookmarked=excluded.bookmarked',
        [id, saved ? 1 : 0]);
  }

  Future<String> saveWord(String id,
      {String? sentence, String? source, String? articleId}) async {
    final word = (await _catalog()).word(id);
    final entry = await database.saveVocabulary(
        word: word['word'] as String,
        definition: word['definition'] as String,
        translation: word['translation'] as String,
        sentence: sentence ?? word['example'] as String,
        source: source ?? 'Built-in library · ${word['level']} target',
        articleId: articleId,
        usageExample: word['example'] as String,
        collocations: word['collocation'] as String,
        partOfSpeech: word['part_of_speech'] as String);
    (await database.db).execute(
        'UPDATE vocabulary_entries SET definition=COALESCE(definition,?),translation=COALESCE(translation,?),level=COALESCE(level,?) WHERE id=?',
        [word['definition'], word['translation'], word['level'], entry]);
    (await database.db).execute(
        'INSERT INTO builtin_word_saves(word_id,entry_id,saved_at) VALUES(?,?,?) ON CONFLICT(word_id) DO UPDATE SET entry_id=excluded.entry_id',
        [id, entry, _now().toUtc().toIso8601String()]);
    return entry;
  }

  Future<
      List<
          Map<String,
              dynamic>>> history(String id) async => (await database.db).select(
      'SELECT * FROM builtin_reading_attempts WHERE article_id=? ORDER BY completed_at DESC LIMIT 20',
      [id]);
  Future<Map<String, dynamic>> submit(
      {required String id,
      required String token,
      required String startedAt,
      required Map<String, String> answers,
      required bool readConfirmed}) async {
    final catalog = await _catalog();
    final article = catalog.article(id);
    final d = await database.db;
    final existing =
        d.select('SELECT * FROM builtin_reading_attempts WHERE id=?', [token]);
    if (existing.isNotEmpty) {
      if (existing.single['article_id'] != id) {
        throw StateError('Submission belongs to another article.');
      }
      return existing.single;
    }
    if (!readConfirmed) {
      throw StateError('Confirm that you finished reading before submitting.');
    }
    final questions = (article['questions'] as List).map((q) {
      final m = q as Map;
      final choices = m['choices'] as List;
      return <String, dynamic>{
        'id': m['id'],
        'question_type': 'mc',
        'correct_answer': choices[m['answer'] as int]
      };
    }).toList();
    final grade = gradeAssessment(questions, answers, writingReviewed: false);
    final now = _now().toUtc().toIso8601String();
    d.execute('BEGIN IMMEDIATE');
    try {
      d.execute(
          'INSERT INTO builtin_reading_attempts(id,article_id,content_version,questions_json,answers_json,correct,total,started_at,completed_at) VALUES(?,?,?,?,?,?,?,?,?)',
          [
            token,
            id,
            catalog.version,
            jsonEncode(article['questions']),
            jsonEncode(answers),
            grade.correct,
            grade.objectiveCount,
            startedAt,
            now
          ]);
      d.execute(
          'INSERT INTO builtin_article_state(article_id,read_confirmed,completed_at) VALUES(?,1,?) ON CONFLICT(article_id) DO UPDATE SET read_confirmed=1,completed_at=excluded.completed_at',
          [id, now]);
      d.execute(
          'INSERT OR IGNORE INTO learning_activities(id,type,module,metadata,local_date) VALUES(?,?,?,?,?)',
          [
            'builtin-reading:$token',
            'builtin_reading_completed',
            'reading',
            jsonEncode({
              'article_id': id,
              'correct': grade.correct,
              'total': grade.objectiveCount
            }),
            localDateString(_now())
          ]);
      d.execute('COMMIT');
    } catch (_) {
      d.execute('ROLLBACK');
      rethrow;
    }
    return d.select(
        'SELECT * FROM builtin_reading_attempts WHERE id=?', [token]).single;
  }

  Future<List<Map<String, dynamic>>> recommendedWords(
      {int count = 10, String? level}) async {
    final catalog = await _catalog();
    final d = await database.db;
    final saved = d
        .select('SELECT word FROM vocabulary_entries WHERE is_saved=1')
        .map((r) => normalizeWord(r['word'] as String))
        .toSet();
    final target = ['B1', 'B2'].contains(level) ? level! : 'B1';
    final today = localDateString(_now());
    final previous = d.select(
        'SELECT word_ids_json FROM builtin_daily_words WHERE local_date=? AND level=?',
        [today, target]);
    if (previous.isNotEmpty) {
      final ids =
          (jsonDecode(previous.single['word_ids_json'] as String) as List)
              .cast<String>();
      return catalog.words.where((w) => ids.contains(w['id'])).toList();
    }
    final selected = catalog.words
        .where((w) =>
            w['level'] == target &&
            !saved.contains(normalizeWord(w['word'] as String)))
        .take(count)
        .toList();
    d.execute(
        'INSERT OR IGNORE INTO builtin_daily_words(local_date,level,word_ids_json) VALUES(?,?,?)',
        [today, target, jsonEncode(selected.map((w) => w['id']).toList())]);
    return selected;
  }

  Future<Map<String, dynamic>?> nextArticle(String level) async {
    final catalog = await _catalog();
    final d = await database.db;
    final done = d
        .select(
            'SELECT article_id FROM builtin_article_state WHERE completed_at IS NOT NULL')
        .map((r) => r['article_id'])
        .toSet();
    final started = d
        .select(
            'SELECT article_id FROM builtin_article_state WHERE completed_at IS NULL AND last_opened_at IS NOT NULL ORDER BY last_opened_at DESC')
        .map((r) => r['article_id'])
        .toList();
    final available = catalog.articles
        .where((a) => a['level'] == level && !done.contains(a['id']))
        .toList();
    for (final id in started) {
      for (final article in available) {
        if (article['id'] == id) return article;
      }
    }
    return available.isEmpty ? null : available.first;
  }
}
