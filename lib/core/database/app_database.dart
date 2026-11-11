import 'dart:io';
import 'dart:convert';

import '../utils/id_utils.dart';
import '../services/review_schedule.dart';
import '../utils/answer_utils.dart';
import '../utils/date_utils.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';

/// Lightweight offline database for LexiFlow Phase 1.
class AppDatabase {
  AppDatabase({String? path}) : _path = path;

  final String? _path;
  Database? _db;
  Future<Database>? _opening;

  Future<Database> get db async {
    if (_db != null) return _db!;
    return _opening ??= _open().then((database) {
      _db = database;
      return database;
    }).whenComplete(() => _opening = null);
  }

  Future<Database> _open() async {
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    }
    final path = _path ??
        p.join(
            (await getApplicationDocumentsDirectory()).path, 'lexiflow.sqlite');
    final database = sqlite3.open(path);
    database.execute('PRAGMA foreign_keys = ON;');
    database.execute('BEGIN IMMEDIATE');
    try {
      await _migrate(database);
      database.execute('COMMIT');
      return database;
    } catch (_) {
      database.execute('ROLLBACK');
      database.dispose();
      rethrow;
    }
  }

  Future<void> _migrate(Database database) async {
    final version =
        database.select('PRAGMA user_version;').first['user_version'] as int;
    if (version < 1) {
      database.execute('''
        CREATE TABLE IF NOT EXISTS user_preferences (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          display_name TEXT,
          english_level TEXT NOT NULL DEFAULT 'B1',
          target_level TEXT NOT NULL DEFAULT 'B2',
          daily_target_minutes INTEGER NOT NULL DEFAULT 60,
          reading_minutes INTEGER NOT NULL DEFAULT 18,
          vocabulary_minutes INTEGER NOT NULL DEFAULT 15,
          listening_speaking_minutes INTEGER NOT NULL DEFAULT 15,
          grammar_writing_minutes INTEGER NOT NULL DEFAULT 12,
          english_preference TEXT NOT NULL DEFAULT 'American',
          translation_language TEXT NOT NULL DEFAULT 'Dari/Persian',
          learning_priorities TEXT NOT NULL DEFAULT '[]',
          onboarding_completed INTEGER NOT NULL DEFAULT 0,
          theme_mode TEXT NOT NULL DEFAULT 'system',
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS study_sessions (
          id TEXT PRIMARY KEY,
          module TEXT NOT NULL,
          started_at TEXT NOT NULL,
          ended_at TEXT,
          duration_seconds INTEGER NOT NULL DEFAULT 0,
          completed INTEGER NOT NULL DEFAULT 0,
          interrupted INTEGER NOT NULL DEFAULT 0,
          local_date TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
      ''');
      database.execute(
          'CREATE INDEX IF NOT EXISTS idx_sessions_date ON study_sessions(local_date);');
      database.execute(
          'CREATE INDEX IF NOT EXISTS idx_sessions_completed ON study_sessions(completed);');
      database.execute('''
        CREATE TABLE IF NOT EXISTS daily_goals (
          local_date TEXT PRIMARY KEY,
          target_minutes INTEGER NOT NULL,
          completed_minutes INTEGER NOT NULL DEFAULT 0,
          goal_met INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS learning_activities (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          module TEXT,
          metadata TEXT,
          local_date TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS vocabulary_entries (
          id TEXT PRIMARY KEY,
          word TEXT NOT NULL,
          definition TEXT,
          translation TEXT,
          example_sentence TEXT,
          part_of_speech TEXT,
          level TEXT,
          is_saved INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS vocabulary_reviews (
          id TEXT PRIMARY KEY,
          entry_id TEXT NOT NULL,
          next_review_at TEXT NOT NULL,
          interval_days INTEGER NOT NULL DEFAULT 1,
          ease_factor INTEGER NOT NULL DEFAULT 250,
          review_count INTEGER NOT NULL DEFAULT 0,
          last_reviewed_at TEXT,
          FOREIGN KEY (entry_id) REFERENCES vocabulary_entries(id)
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS courses (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          description TEXT,
          level TEXT,
          total_lessons INTEGER NOT NULL DEFAULT 0,
          completed_lessons INTEGER NOT NULL DEFAULT 0,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS lessons (
          id TEXT PRIMARY KEY,
          course_id TEXT NOT NULL,
          title TEXT NOT NULL,
          order_index INTEGER NOT NULL DEFAULT 0,
          completed INTEGER NOT NULL DEFAULT 0,
          completed_at TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (course_id) REFERENCES courses(id)
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS ai_conversations (
          id TEXT PRIMARY KEY,
          provider TEXT,
          title TEXT,
          message_count INTEGER NOT NULL DEFAULT 0,
          started_at TEXT NOT NULL,
          last_message_at TEXT,
          is_active INTEGER NOT NULL DEFAULT 1
        );
      ''');
      // Seed preferences
      database.execute('INSERT INTO user_preferences DEFAULT VALUES;');
      database.execute('PRAGMA user_version = 1;');
    }
    if (version < 2) {
      database.execute('''
        CREATE TABLE IF NOT EXISTS listening_lessons (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          topic TEXT,
          difficulty TEXT NOT NULL DEFAULT 'B1',
          audio_path TEXT NOT NULL,
          duration_ms INTEGER NOT NULL DEFAULT 0,
          last_position_ms INTEGER NOT NULL DEFAULT 0,
          transcript TEXT,
          transcript_path TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS playback_bookmarks (
          id TEXT PRIMARY KEY,
          lesson_id TEXT NOT NULL,
          position_ms INTEGER NOT NULL,
          label TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (lesson_id) REFERENCES listening_lessons(id) ON DELETE CASCADE
        );
      ''');
      database.execute(
          'CREATE INDEX IF NOT EXISTS idx_bookmarks_lesson ON playback_bookmarks(lesson_id);');
      database.execute('''
        CREATE TABLE IF NOT EXISTS comprehension_questions (
          id TEXT PRIMARY KEY,
          lesson_id TEXT NOT NULL,
          question TEXT NOT NULL,
          question_type TEXT NOT NULL,
          choices TEXT,
          correct_answer TEXT,
          order_index INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (lesson_id) REFERENCES listening_lessons(id) ON DELETE CASCADE
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS comprehension_attempts (
          id TEXT PRIMARY KEY,
          question_id TEXT NOT NULL,
          lesson_id TEXT NOT NULL,
          learner_response TEXT,
          is_correct INTEGER,
          self_assessed INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (question_id) REFERENCES comprehension_questions(id) ON DELETE CASCADE
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS speaking_prompts (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          difficulty TEXT NOT NULL DEFAULT 'B1',
          category TEXT NOT NULL,
          prompt_text TEXT NOT NULL,
          guidance TEXT,
          suggested_seconds INTEGER NOT NULL DEFAULT 60,
          is_builtin INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS speaking_recordings (
          id TEXT PRIMARY KEY,
          prompt_id TEXT,
          lesson_id TEXT,
          mode TEXT NOT NULL DEFAULT 'prompt',
          audio_path TEXT NOT NULL,
          duration_ms INTEGER NOT NULL DEFAULT 0,
          self_rating INTEGER,
          notes TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (prompt_id) REFERENCES speaking_prompts(id) ON DELETE SET NULL
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS shadowing_attempts (
          id TEXT PRIMARY KEY,
          lesson_id TEXT NOT NULL,
          segment_start_ms INTEGER NOT NULL DEFAULT 0,
          segment_end_ms INTEGER,
          recording_id TEXT,
          self_rating INTEGER,
          duration_ms INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (lesson_id) REFERENCES listening_lessons(id) ON DELETE CASCADE,
          FOREIGN KEY (recording_id) REFERENCES speaking_recordings(id) ON DELETE SET NULL
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS ai_messages (
          id TEXT PRIMARY KEY,
          conversation_id TEXT NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (conversation_id) REFERENCES ai_conversations(id) ON DELETE CASCADE
        );
      ''');
      database.execute(
          'CREATE INDEX IF NOT EXISTS idx_ai_messages_conv ON ai_messages(conversation_id);');
      database.execute('PRAGMA user_version = 2;');
    }
    if (version < 3) {
      database.execute('''
        CREATE TABLE IF NOT EXISTS grammar_lessons (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          cefr_level TEXT NOT NULL,
          topic_key TEXT NOT NULL,
          objective TEXT NOT NULL,
          explanation TEXT NOT NULL,
          examples TEXT NOT NULL,
          common_mistakes TEXT NOT NULL,
          order_index INTEGER NOT NULL DEFAULT 0,
          completed INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS grammar_exercises (
          id TEXT PRIMARY KEY,
          lesson_id TEXT NOT NULL,
          question_type TEXT NOT NULL,
          prompt TEXT NOT NULL,
          choices TEXT,
          correct_answer TEXT,
          alternatives TEXT,
          explanation TEXT NOT NULL,
          order_index INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (lesson_id) REFERENCES grammar_lessons(id) ON DELETE CASCADE
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS grammar_attempts (
          id TEXT PRIMARY KEY,
          exercise_id TEXT NOT NULL,
          lesson_id TEXT NOT NULL,
          learner_response TEXT,
          is_correct INTEGER,
          self_assessed INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (exercise_id) REFERENCES grammar_exercises(id) ON DELETE CASCADE
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS writing_entries (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT 'free',
          body TEXT NOT NULL DEFAULT '',
          word_count INTEGER NOT NULL DEFAULT 0,
          prompt_id TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS writing_revisions (
          id TEXT PRIMARY KEY,
          entry_id TEXT NOT NULL,
          body TEXT NOT NULL,
          word_count INTEGER NOT NULL DEFAULT 0,
          label TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (entry_id) REFERENCES writing_entries(id) ON DELETE CASCADE
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS writing_feedback (
          id TEXT PRIMARY KEY,
          entry_id TEXT NOT NULL,
          source TEXT NOT NULL DEFAULT 'ai',
          content TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (entry_id) REFERENCES writing_entries(id) ON DELETE CASCADE
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS writing_mistakes (
          id TEXT PRIMARY KEY,
          entry_id TEXT,
          grammar_topic TEXT,
          original_sentence TEXT NOT NULL,
          correction TEXT,
          explanation TEXT,
          review_status TEXT NOT NULL DEFAULT 'open',
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (entry_id) REFERENCES writing_entries(id) ON DELETE SET NULL
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS imported_books (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          file_path TEXT NOT NULL,
          page_count INTEGER NOT NULL DEFAULT 0,
          current_page INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS book_units (
          id TEXT PRIMARY KEY,
          book_id TEXT NOT NULL,
          title TEXT NOT NULL,
          order_index INTEGER NOT NULL DEFAULT 0,
          completed INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (book_id) REFERENCES imported_books(id) ON DELETE CASCADE
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS book_lessons (
          id TEXT PRIMARY KEY,
          unit_id TEXT NOT NULL,
          book_id TEXT NOT NULL,
          title TEXT NOT NULL,
          notes TEXT,
          page_start INTEGER,
          page_end INTEGER,
          objective TEXT,
          completed INTEGER NOT NULL DEFAULT 0,
          order_index INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (unit_id) REFERENCES book_units(id) ON DELETE CASCADE,
          FOREIGN KEY (book_id) REFERENCES imported_books(id) ON DELETE CASCADE
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS book_bookmarks (
          id TEXT PRIMARY KEY,
          book_id TEXT NOT NULL,
          page INTEGER NOT NULL,
          label TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (book_id) REFERENCES imported_books(id) ON DELETE CASCADE
        );
      ''');
      database.execute('PRAGMA user_version = 3;');
    }
    if (version < 4) {
      database.execute('''
        CREATE TABLE IF NOT EXISTS assessment_definitions (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          category TEXT NOT NULL,
          description TEXT,
          time_limit_seconds INTEGER,
          pass_threshold REAL NOT NULL DEFAULT 0.7,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS assessment_questions (
          id TEXT PRIMARY KEY,
          assessment_id TEXT NOT NULL,
          question_type TEXT NOT NULL,
          prompt TEXT NOT NULL,
          choices TEXT,
          correct_answer TEXT,
          explanation TEXT,
          order_index INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (assessment_id) REFERENCES assessment_definitions(id) ON DELETE CASCADE
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS assessment_attempts (
          id TEXT PRIMARY KEY,
          assessment_id TEXT NOT NULL,
          score REAL,
          max_score REAL,
          passed INTEGER NOT NULL DEFAULT 0,
          self_assessed INTEGER NOT NULL DEFAULT 0,
          answers_json TEXT,
          started_at TEXT NOT NULL,
          completed_at TEXT,
          FOREIGN KEY (assessment_id) REFERENCES assessment_definitions(id) ON DELETE CASCADE
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS completion_records (
          id TEXT PRIMARY KEY,
          target_type TEXT NOT NULL,
          target_id TEXT NOT NULL,
          target_title TEXT NOT NULL,
          verification_type TEXT NOT NULL,
          assessment_score REAL,
          completed_at TEXT NOT NULL,
          certificate_eligible INTEGER NOT NULL DEFAULT 0,
          certificate_ref TEXT
        );
      ''');
      database.execute('''
        CREATE TABLE IF NOT EXISTS certificates (
          id TEXT PRIMARY KEY,
          completion_id TEXT NOT NULL,
          learner_name TEXT NOT NULL,
          title TEXT NOT NULL,
          ref_number TEXT NOT NULL,
          score_text TEXT,
          verification_type TEXT NOT NULL,
          issued_at TEXT NOT NULL,
          file_path TEXT,
          FOREIGN KEY (completion_id) REFERENCES completion_records(id) ON DELETE CASCADE
        );
      ''');
      database.execute('PRAGMA user_version = 4;');
    }
    if (version < 5) {
      database.execute('''CREATE TABLE reading_articles (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL,
        source_name TEXT, scroll_offset REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
      database.execute(
          'ALTER TABLE vocabulary_entries ADD COLUMN normalized_word TEXT');
      database.execute(
          'ALTER TABLE vocabulary_entries ADD COLUMN duplicate_of TEXT REFERENCES vocabulary_entries(id)');
      database.execute(
          "ALTER TABLE vocabulary_entries ADD COLUMN contexts_json TEXT NOT NULL DEFAULT '[]'");
      final canonical = <String, String>{};
      for (final row in database.select(
          'SELECT * FROM vocabulary_entries ORDER BY is_saved DESC, created_at, id')) {
        final word = normalizeWord(row['word'] as String);
        final id = row['id'] as String;
        final first = canonical[word];
        database.execute(
            'UPDATE vocabulary_entries SET normalized_word = ?, duplicate_of = ?, contexts_json = ? WHERE id = ?',
            [
              first == null ? word : null,
              first,
              jsonEncode([
                if ((row['example_sentence'] as String?)?.isNotEmpty == true)
                  {
                    'sentence': row['example_sentence'],
                    'source': 'Original context'
                  }
              ]),
              id
            ]);
        canonical.putIfAbsent(word, () => id);
      }
      // Preserve legacy duplicate rows and their schedules, while exposing one
      // canonical word and all of its original source sentences.
      for (final id in canonical.values) {
        final related = database.select(
            'SELECT * FROM vocabulary_entries WHERE id=? OR duplicate_of=?',
            [id, id]);
        final contexts = <dynamic>[];
        for (final row in related) {
          for (final item
              in jsonDecode(row['contexts_json'] as String) as List) {
            if (!contexts.any((c) => c['sentence'] == item['sentence'])) {
              contexts.add(item);
            }
          }
        }
        database.execute(
            'UPDATE vocabulary_entries SET contexts_json=? WHERE id=?',
            [jsonEncode(contexts), id]);
        if (database.select(
            'SELECT id FROM vocabulary_reviews WHERE entry_id=?',
            [id]).isEmpty) {
          final schedules = database.select(
              '''SELECT r.* FROM vocabulary_reviews r JOIN vocabulary_entries e ON e.id=r.entry_id
            WHERE e.duplicate_of=? ORDER BY julianday(r.next_review_at),r.id LIMIT 1''',
              [id]);
          if (schedules.isNotEmpty) {
            final r = schedules.first;
            database.execute(
                'INSERT INTO vocabulary_reviews(id,entry_id,next_review_at,interval_days,ease_factor,review_count,last_reviewed_at) VALUES(?,?,?,?,?,?,?)',
                [
                  newId(),
                  id,
                  r['next_review_at'],
                  r['interval_days'],
                  r['ease_factor'],
                  r['review_count'],
                  r['last_reviewed_at']
                ]);
          } else {
            database.execute(
                'INSERT INTO vocabulary_reviews(id,entry_id,next_review_at,interval_days) VALUES(?,?,?,0)',
                [newId(), id, DateTime.now().toUtc().toIso8601String()]);
          }
        }
      }
      database.execute(
          'CREATE UNIQUE INDEX idx_vocabulary_normalized ON vocabulary_entries(normalized_word) WHERE normalized_word IS NOT NULL');
      database.execute(
          'ALTER TABLE vocabulary_reviews ADD COLUMN successful_streak INTEGER NOT NULL DEFAULT 0');
      database.execute(
          'UPDATE vocabulary_reviews SET successful_streak=MAX(0,review_count)');
      database.execute('''CREATE TABLE vocabulary_review_history (
        id TEXT PRIMARY KEY, entry_id TEXT NOT NULL REFERENCES vocabulary_entries(id),
        rating TEXT NOT NULL, reviewed_at TEXT NOT NULL,
        previous_due TEXT NOT NULL, next_due TEXT NOT NULL,
        previous_interval INTEGER NOT NULL, next_interval INTEGER NOT NULL,
        review_number INTEGER NOT NULL)''');
      database.execute(
          'CREATE INDEX idx_review_history_entry ON vocabulary_review_history(entry_id, reviewed_at)');
      database.execute('''CREATE TABLE completion_requirements (
        target_type TEXT NOT NULL CHECK(target_type IN ('book','course')),
        target_id TEXT NOT NULL, assessment_id TEXT NOT NULL REFERENCES assessment_definitions(id),
        PRIMARY KEY(target_type, target_id, assessment_id))''');
      database.execute('''CREATE TABLE study_session_days (
        session_id TEXT NOT NULL REFERENCES study_sessions(id) ON DELETE CASCADE,
        local_date TEXT NOT NULL, duration_ms INTEGER NOT NULL DEFAULT 0 CHECK(duration_ms >= 0),
        PRIMARY KEY(session_id, local_date))''');
      // Old active intervals cannot be reconstructed. Preserve their recorded date.
      database.execute(
          'INSERT INTO study_session_days SELECT id, local_date, MAX(0, duration_seconds) * 1000 FROM study_sessions');
      database.execute('PRAGMA user_version = 5');
    }
    if (version < 6) {
      database.execute(
          'ALTER TABLE listening_lessons ADD COLUMN transcript_revealed INTEGER NOT NULL DEFAULT 0');
      database.execute(
          "ALTER TABLE listening_lessons ADD COLUMN comprehension_draft TEXT NOT NULL DEFAULT '{}' ");
      database.execute(
          'ALTER TABLE comprehension_attempts ADD COLUMN submission_id TEXT');
      database.execute(
          'ALTER TABLE comprehension_attempts ADD COLUMN question_snapshot TEXT');
      database.execute(
          'CREATE UNIQUE INDEX idx_comprehension_submission ON comprehension_attempts(submission_id,question_id) WHERE submission_id IS NOT NULL');
      database.execute(
          'CREATE INDEX idx_comprehension_lesson ON comprehension_attempts(lesson_id,created_at)');
      database.execute(
          'ALTER TABLE ai_messages ADD COLUMN is_local INTEGER NOT NULL DEFAULT 1');
      database.execute(
          "ALTER TABLE ai_messages ADD COLUMN request_state TEXT NOT NULL DEFAULT 'complete'");
      database.execute('ALTER TABLE ai_messages ADD COLUMN error_code TEXT');
      database.execute(
          'CREATE INDEX idx_ai_message_order ON ai_messages(conversation_id,created_at)');
      database.execute(
          'ALTER TABLE shadowing_attempts ADD COLUMN saved INTEGER NOT NULL DEFAULT 1');
      database
          .execute('ALTER TABLE writing_mistakes ADD COLUMN updated_at TEXT');
      database.execute('UPDATE writing_mistakes SET updated_at=created_at');
      database.execute(
          "CREATE TABLE pending_file_deletions(path TEXT PRIMARY KEY,created_at TEXT NOT NULL DEFAULT (datetime('now')))");
      database.execute(
          'ALTER TABLE writing_feedback ADD COLUMN body_snapshot TEXT');
      database.execute('PRAGMA user_version=6');
    }
  }

  Future<List<Map<String, dynamic>>> getArticles() async => (await db)
      .select('SELECT * FROM reading_articles ORDER BY updated_at DESC');

  Future<Map<String, dynamic>?> getArticle(String id) async {
    final rows =
        (await db).select('SELECT * FROM reading_articles WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<String> saveArticle(String title, String body,
      {String? sourceName}) async {
    if (title.trim().isEmpty || body.trim().isEmpty) {
      throw ArgumentError('Article title and text are required.');
    }
    final id = newId();
    final now = DateTime.now().toUtc().toIso8601String();
    (await db).execute(
        'INSERT INTO reading_articles (id,title,body,source_name,created_at,updated_at) VALUES (?,?,?,?,?,?)',
        [id, title.trim(), body, sourceName, now, now]);
    return id;
  }

  Future<void> saveReadingPosition(String id, double offset) async {
    if (!offset.isFinite || offset < 0) return;
    (await db).execute(
        'UPDATE reading_articles SET scroll_offset = ?, updated_at = ? WHERE id = ?',
        [offset, DateTime.now().toUtc().toIso8601String(), id]);
  }

  Future<List<Map<String, dynamic>>> getVocabulary() async => (await db).select(
      'SELECT * FROM vocabulary_entries WHERE is_saved = 1 AND duplicate_of IS NULL ORDER BY word COLLATE NOCASE');

  /// Duplicate reading saves append provenance; they never overwrite the first context.
  Future<String> saveVocabulary(
      {String? id,
      required String word,
      String? definition,
      String? translation,
      String? sentence,
      String? source,
      String? articleId}) async {
    final normalized = normalizeWord(word);
    if (normalized.isEmpty || normalized.length > 100) {
      throw ArgumentError(
          'Enter a word or short phrase (up to 100 characters).');
    }
    final d = await db;
    d.execute('BEGIN IMMEDIATE');
    try {
      final matches = d.select(
          'SELECT * FROM vocabulary_entries WHERE normalized_word = ?',
          [normalized]);
      if (id != null && matches.isNotEmpty && matches.first['id'] != id) {
        throw StateError('This word already exists. Edit its existing card.');
      }
      final existing = id == null
          ? matches
          : d.select(
              'SELECT * FROM vocabulary_entries WHERE id = ? AND duplicate_of IS NULL',
              [id]);
      if (id != null && existing.isEmpty) throw StateError('Word not found.');
      final entryId =
          existing.isEmpty ? newId() : existing.first['id'] as String;
      final contexts = existing.isEmpty
          ? <dynamic>[]
          : jsonDecode(existing.first['contexts_json'] as String) as List;
      final context = sentence?.trim();
      if (context != null &&
          context.isNotEmpty &&
          !contexts.any((c) =>
              c['sentence'] == context && c['article_id'] == articleId)) {
        contexts.add({
          'sentence': context,
          'source': source ?? 'Manual',
          'article_id': articleId
        });
      }
      if (existing.isEmpty) {
        d.execute(
            'INSERT INTO vocabulary_entries (id,word,normalized_word,definition,translation,example_sentence,contexts_json) VALUES (?,?,?,?,?,?,?)',
            [
              entryId,
              word.trim(),
              normalized,
              definition,
              translation,
              context,
              jsonEncode(contexts)
            ]);
      } else if (id != null) {
        d.execute(
            'UPDATE vocabulary_entries SET word=?, normalized_word=?, definition=?, translation=?, contexts_json=?, is_saved=1 WHERE id=?',
            [
              word.trim(),
              normalized,
              definition,
              translation,
              jsonEncode(contexts),
              entryId
            ]);
      } else {
        d.execute(
            'UPDATE vocabulary_entries SET contexts_json=?, is_saved=1 WHERE id=?',
            [jsonEncode(contexts), entryId]);
      }
      if (d.select('SELECT id FROM vocabulary_reviews WHERE entry_id=?',
          [entryId]).isEmpty) {
        d.execute(
            'INSERT INTO vocabulary_reviews (id,entry_id,next_review_at,interval_days) VALUES (?,?,?,0)',
            [newId(), entryId, DateTime.now().toUtc().toIso8601String()]);
      }
      if (existing.isEmpty) {
        _activity(d, 'word:$entryId', 'word_saved', 'vocabulary');
      }
      d.execute('COMMIT');
      return entryId;
    } catch (_) {
      d.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getDueVocabulary({DateTime? now}) async =>
      (await db).select('''
    SELECT e.*, r.id AS schedule_id, r.review_count, r.next_review_at
    FROM vocabulary_entries e JOIN vocabulary_reviews r ON r.entry_id=e.id
    WHERE e.is_saved=1 AND e.duplicate_of IS NULL AND julianday(r.next_review_at)<=julianday(?)
      AND r.id=(SELECT r2.id FROM vocabulary_reviews r2 WHERE r2.entry_id=e.id ORDER BY julianday(r2.next_review_at),r2.id LIMIT 1)
    ORDER BY julianday(r.next_review_at),e.word''',
          [(now ?? DateTime.now()).toUtc().toIso8601String()]);

  Future<void> reviewVocabulary(
      {required String entryId,
      required String reviewId,
      required ReviewRating rating,
      required int expectedReviewCount,
      DateTime? now}) async {
    final d = await db;
    d.execute('BEGIN IMMEDIATE');
    try {
      if (d.select('SELECT id FROM vocabulary_review_history WHERE id=?',
          [reviewId]).isNotEmpty) {
        d.execute('COMMIT');
        return;
      }
      final rows = d.select(
          'SELECT r.* FROM vocabulary_reviews r JOIN vocabulary_entries e ON e.id=r.entry_id WHERE r.entry_id=? AND e.is_saved=1 AND e.duplicate_of IS NULL ORDER BY julianday(r.next_review_at),r.id LIMIT 1',
          [entryId]);
      if (rows.isEmpty) throw StateError('Review card not found.');
      final r = rows.first;
      if (r['review_count'] != expectedReviewCount) {
        throw StateError('Card already reviewed. Refresh the queue.');
      }
      final at = (now ?? DateTime.now()).toUtc();
      if (DateTime.parse(r['next_review_at'] as String).isAfter(at)) {
        throw StateError('Card is not due yet.');
      }
      final next = scheduleReview(
          now: at,
          rating: rating,
          intervalDays: r['interval_days'] as int,
          ease: r['ease_factor'] as int,
          streak: r['successful_streak'] as int);
      final due = next.due.toIso8601String();
      d.execute(
          'INSERT INTO vocabulary_review_history (id,entry_id,rating,reviewed_at,previous_due,next_due,previous_interval,next_interval,review_number) VALUES (?,?,?,?,?,?,?,?,?)',
          [
            reviewId,
            entryId,
            rating.name,
            at.toIso8601String(),
            r['next_review_at'],
            due,
            r['interval_days'],
            next.intervalDays,
            expectedReviewCount + 1
          ]);
      // Synchronize any legacy duplicate schedule rows without deleting their records.
      d.execute(
          'UPDATE vocabulary_reviews SET next_review_at=?, interval_days=?, ease_factor=?, successful_streak=?, review_count=?, last_reviewed_at=? WHERE entry_id=?',
          [
            due,
            next.intervalDays,
            next.ease,
            next.streak,
            expectedReviewCount + 1,
            at.toIso8601String(),
            entryId
          ]);
      _activity(d, 'review:$reviewId', 'vocabulary_reviewed', 'vocabulary');
      d.execute('COMMIT');
    } catch (_) {
      d.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getReviewHistory(String entryId) async =>
      (await db).select(
          'SELECT * FROM vocabulary_review_history WHERE entry_id=? ORDER BY reviewed_at DESC, review_number DESC',
          [entryId]);

  Future<void> setCompletionRequirements(
      String type, String id, List<String> assessmentIds) async {
    final d = await db;
    final table = type == 'book'
        ? 'imported_books'
        : (type == 'course' ? 'courses' : null);
    if (table == null ||
        d.select('SELECT id FROM $table WHERE id=?', [id]).isEmpty) {
      throw StateError('Learning material not found.');
    }
    d.execute('BEGIN IMMEDIATE');
    try {
      d.execute(
          'DELETE FROM completion_requirements WHERE target_type=? AND target_id=?',
          [type, id]);
      for (final assessment in assessmentIds.toSet()) {
        d.execute('INSERT INTO completion_requirements VALUES (?,?,?)',
            [type, id, assessment]);
      }
      d.execute('COMMIT');
    } catch (_) {
      d.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<List<String>> getCompletionRequirements(
          String type, String id) async =>
      (await db)
          .select(
              'SELECT assessment_id FROM completion_requirements WHERE target_type=? AND target_id=?',
              [type, id])
          .map((r) => r['assessment_id'] as String)
          .toList();

  /// Atomic, idempotent daily checkpoint. Each service checkpoint supplies cumulative totals.
  Future<void> checkpointSession(String id, Map<String, int> milliseconds,
      {bool completed = false,
      bool interrupted = true,
      DateTime? endedAt}) async {
    final d = await db;
    d.execute('BEGIN IMMEDIATE');
    try {
      final row =
          d.select('SELECT * FROM study_sessions WHERE id=?', [id]).single;
      if (row['completed'] == 1) {
        d.execute('COMMIT');
        return;
      }
      for (final item in milliseconds.entries) {
        d.execute(
            '''INSERT INTO study_session_days(session_id,local_date,duration_ms) VALUES (?,?,?)
          ON CONFLICT(session_id,local_date) DO UPDATE SET duration_ms=MAX(duration_ms,excluded.duration_ms)''',
            [id, item.key, item.value]);
      }
      final total = d.select(
          'SELECT COALESCE(SUM(duration_ms),0) AS t FROM study_session_days WHERE session_id=?',
          [id]).first['t'] as int;
      d.execute(
          'UPDATE study_sessions SET duration_seconds=?,completed=?,interrupted=?,ended_at=? WHERE id=?',
          [
            total ~/ 1000,
            completed ? 1 : 0,
            interrupted ? 1 : 0,
            endedAt?.toUtc().toIso8601String(),
            id
          ]);
      if (completed) {
        final target = d
            .select('SELECT daily_target_minutes FROM user_preferences LIMIT 1')
            .first['daily_target_minutes'] as int;
        for (final day in d.select(
            'SELECT local_date FROM study_session_days WHERE session_id=?',
            [id])) {
          final date = day['local_date'] as String;
          final ms = d.select(
              '''SELECT COALESCE(SUM(days.duration_ms),0) AS t FROM study_session_days days
            JOIN study_sessions s ON s.id=days.session_id WHERE s.completed=1 AND days.local_date=?''',
              [date]).first['t'] as int;
          final minutes = ms ~/ 60000;
          d.execute(
              '''INSERT INTO daily_goals(local_date,target_minutes,completed_minutes,goal_met) VALUES (?,?,?,?)
            ON CONFLICT(local_date) DO UPDATE SET target_minutes=excluded.target_minutes,completed_minutes=excluded.completed_minutes,goal_met=excluded.goal_met''',
              [date, target, minutes, minutes >= target ? 1 : 0]);
        }
        d.execute(
            'INSERT OR IGNORE INTO learning_activities(id,type,module,metadata,local_date) VALUES (?,?,?,?,?)',
            [
              'session:$id',
              interrupted ? 'session_interrupted' : 'session_completed',
              row['module'],
              jsonEncode({'seconds': total ~/ 1000}),
              row['local_date']
            ]);
      }
      d.execute('COMMIT');
    } catch (_) {
      d.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<Map<String, int>> getSessionDays(String id) async => {
        for (final row in (await db).select(
            'SELECT * FROM study_session_days WHERE session_id=?', [id]))
          row['local_date'] as String: row['duration_ms'] as int,
      };
  T _atomic<T>(Database d, T Function() action) {
    d.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      d.execute('COMMIT');
      return result;
    } catch (_) {
      d.execute('ROLLBACK');
      rethrow;
    }
  }

  void _activity(Database d, String id, String type, String module,
      {Map<String, Object?>? metadata}) {
    d.execute(
        'INSERT OR IGNORE INTO learning_activities(id,type,module,metadata,local_date) VALUES(?,?,?,?,?)',
        [id, type, module, jsonEncode(metadata ?? {}), localDateString()]);
  }

  Future<void> saveComprehensionQuestion(
      {String? id,
      required String lessonId,
      required String question,
      required String type,
      List<String> choices = const [],
      String? correct}) async {
    if (question.trim().isEmpty ||
        !['mc', 'main_idea', 'details', 'intention', 'short'].contains(type)) {
      throw ArgumentError('Enter a question and valid question type.');
    }
    final options =
        choices.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (type != 'short' &&
        (options.length < 2 ||
            options.length > 6 ||
            options.toSet().length != options.length ||
            !options.contains(correct))) {
      throw ArgumentError(
          'Provide 2–6 distinct choices and select the correct answer.');
    }
    final d = await db;
    if (d.select(
        'SELECT id FROM listening_lessons WHERE id=?', [lessonId]).isEmpty) {
      throw StateError('Lesson not found.');
    }
    if (id != null &&
        d.select(
            'SELECT id FROM comprehension_questions WHERE id=? AND lesson_id=?',
            [id, lessonId]).isEmpty) throw StateError('Question not found.');
    d.execute(
        '''INSERT INTO comprehension_questions(id,lesson_id,question,question_type,choices,correct_answer,order_index)
      VALUES(?,?,?,?,?,?,(SELECT COUNT(*) FROM comprehension_questions WHERE lesson_id=?))
      ON CONFLICT(id) DO UPDATE SET question=excluded.question,question_type=excluded.question_type,
        choices=excluded.choices,correct_answer=excluded.correct_answer''',
        [
          id ?? newId(),
          lessonId,
          question.trim(),
          type,
          jsonEncode(type == 'short' ? [] : options),
          type == 'short' ? null : correct,
          lessonId
        ]);
  }

  Future<void> saveComprehensionDraft(
          String lessonId, Map<String, String> answers) async =>
      (await db).execute(
          'UPDATE listening_lessons SET comprehension_draft=? WHERE id=?',
          [jsonEncode(answers), lessonId]);
  Future<void> revealTranscript(String lessonId) async => (await db).execute(
      'UPDATE listening_lessons SET transcript_revealed=1 WHERE id=?',
      [lessonId]);
  Future<void> submitComprehension(
      String lessonId, String submissionId, Map<String, String> answers) async {
    final d = await db;
    _atomic(d, () {
      if (d.select(
          'SELECT id FROM comprehension_attempts WHERE submission_id=?',
          [submissionId]).isNotEmpty) return;
      final questions = d.select(
          'SELECT * FROM comprehension_questions WHERE lesson_id=? ORDER BY order_index',
          [lessonId]);
      if (questions.isEmpty ||
          questions.any((q) => (answers[q['id']] ?? '').trim().isEmpty)) {
        throw StateError('Answer every saved question before submitting.');
      }
      for (final q in questions) {
        final short = q['question_type'] == 'short';
        final response = answers[q['id']]!.trim();
        final correct = short
            ? null
            : (matchesAnswer(response, q['correct_answer'] as String?) ? 1 : 0);
        d.execute(
            '''INSERT INTO comprehension_attempts(id,question_id,lesson_id,learner_response,is_correct,self_assessed,submission_id,question_snapshot)
          VALUES(?,?,?,?,?,?,?,?)''',
            [
              newId(),
              q['id'],
              lessonId,
              response,
              correct,
              short ? 1 : 0,
              submissionId,
              jsonEncode(q)
            ]);
      }
      d.execute('UPDATE listening_lessons SET comprehension_draft=? WHERE id=?',
          [jsonEncode(answers), lessonId]);
      _activity(d, 'comprehension:$submissionId', 'comprehension_submitted',
          'listening_speaking');
    });
  }

  Future<List<Map<String, dynamic>>> getComprehensionAttempts(
          String lessonId) async =>
      (await db).select(
          'SELECT * FROM comprehension_attempts WHERE lesson_id=? ORDER BY created_at DESC,rowid DESC',
          [lessonId]);
  Future<void> selfAssessComprehension(String attemptId, bool metGoal) async =>
      (await db).execute(
          'UPDATE comprehension_attempts SET is_correct=? WHERE id=? AND self_assessed=1',
          [metGoal ? 1 : 0, attemptId]);

  Future<void> renameAiConversation(String id, String title) async {
    if (title.trim().isEmpty) {
      throw ArgumentError('Enter a conversation title.');
    }
    (await db).execute(
        'UPDATE ai_conversations SET title=? WHERE id=?', [title.trim(), id]);
  }

  Future<void> deleteAiConversation(String id) async {
    final d = await db;
    _atomic(d, () {
      d.execute('DELETE FROM ai_messages WHERE conversation_id=?', [id]);
      d.execute('DELETE FROM ai_conversations WHERE id=?', [id]);
    });
  }

  Future<String> beginAiRequest(String conversationId, String text,
      {String? id}) async {
    if (text.trim().isEmpty || text.length > 20000) {
      throw ArgumentError('Enter up to 20,000 characters.');
    }
    final d = await db;
    final request = id ?? newId();
    _atomic(d, () {
      d.execute(
          "INSERT INTO ai_messages(id,conversation_id,role,content,is_local,request_state) VALUES(?,?,'user',?,0,'pending')",
          [request, conversationId, text.trim()]);
      d.execute(
          "UPDATE ai_conversations SET message_count=message_count+1,last_message_at=? WHERE id=?",
          [DateTime.now().toUtc().toIso8601String(), conversationId]);
      _activity(d, 'ai-user:$request', 'ai_practice_message', 'ai_teacher');
    });
    return request;
  }

  Future<void> setAiRequestState(String id, String state,
          {String? errorCode}) async =>
      (await db).execute(
          "UPDATE ai_messages SET request_state=?,error_code=? WHERE id=? AND role='user'",
          [state, errorCode, id]);
  Future<void> finishAiRequest(String requestId, String reply) async {
    if (reply.trim().isEmpty) throw ArgumentError('Provider returned no text.');
    final d = await db;
    _atomic(d, () {
      final rows = d.select(
          "SELECT conversation_id FROM ai_messages WHERE id=? AND role='user'",
          [requestId]);
      if (rows.isEmpty) {
        return; // A user may delete a conversation during a request.
      }
      final conversation = rows.single['conversation_id'];
      if (d.select('SELECT id FROM ai_messages WHERE id=?',
          ['reply:$requestId']).isEmpty) {
        d.execute(
            "INSERT INTO ai_messages(id,conversation_id,role,content,is_local) VALUES(?,?,'assistant',?,0)",
            ['reply:$requestId', conversation, reply.trim()]);
        d.execute(
            'UPDATE ai_conversations SET message_count=message_count+1,last_message_at=? WHERE id=?',
            [DateTime.now().toUtc().toIso8601String(), conversation]);
      }
      d.execute(
          "UPDATE ai_messages SET request_state='complete',error_code=NULL WHERE id=?",
          [requestId]);
    });
  }

  Future<void> deleteWritingMistake(String id) async =>
      (await db).execute('DELETE FROM writing_mistakes WHERE id=?', [id]);
  Future<void> saveAiWritingFeedback(
      String entryId, String submitted, String response) async {
    if (response.trim().isEmpty) {
      throw ArgumentError('No AI feedback was returned.');
    }
    final d = await db;
    _atomic(d, () {
      if (d.select(
          'SELECT id FROM writing_entries WHERE id=?', [entryId]).isEmpty) {
        throw StateError('Writing entry no longer exists.');
      }
      final latest = d.select(
          'SELECT body,label FROM writing_revisions WHERE entry_id=? ORDER BY created_at DESC,rowid DESC LIMIT 1',
          [entryId]);
      if (latest.isEmpty ||
          latest.single['body'] != submitted ||
          latest.single['label'] != 'Submitted for AI feedback') {
        final id = newId();
        d.execute(
            'INSERT INTO writing_revisions(id,entry_id,body,word_count,label) VALUES(?,?,?,?,?)',
            [
              id,
              entryId,
              submitted,
              submitted.trim().isEmpty
                  ? 0
                  : submitted.trim().split(RegExp(r'\s+')).length,
              'Submitted for AI feedback'
            ]);
        _activity(
            d, 'revision:$id', 'writing_revision_saved', 'grammar_writing');
      }
      d.execute(
          "INSERT INTO writing_feedback(id,entry_id,source,content,body_snapshot) VALUES(?,?,'ai',?,?)",
          [newId(), entryId, response, submitted]);
    });
  }

  Future<void> restoreWritingRevision(String entryId, String revisionId) async {
    final d = await db;
    _atomic(d, () {
      final entries =
          d.select('SELECT * FROM writing_entries WHERE id=?', [entryId]);
      final revisions = d.select(
          'SELECT * FROM writing_revisions WHERE id=? AND entry_id=?',
          [revisionId, entryId]);
      if (entries.isEmpty || revisions.isEmpty) {
        throw StateError('Writing entry or revision not found.');
      }
      final entry = entries.single;
      final revision = revisions.single;
      if (entry['body'] == revision['body']) return;
      final backup = newId();
      d.execute(
          'INSERT INTO writing_revisions(id,entry_id,body,word_count,label) VALUES(?,?,?,?,?)',
          [
            backup,
            entryId,
            entry['body'],
            entry['word_count'],
            'Before restoring ${revision['created_at']}'
          ]);
      d.execute(
          'UPDATE writing_entries SET body=?,word_count=?,updated_at=? WHERE id=?',
          [
            revision['body'],
            revision['word_count'],
            DateTime.now().toUtc().toIso8601String(),
            entryId
          ]);
      _activity(d, 'revision:$backup', 'writing_revision_restored',
          'grammar_writing');
    });
  }

  Future<void> saveShadowingRecording(
      {required String attemptId,
      required String lessonId,
      required String path,
      required int startMs,
      required int endMs,
      required int durationMs,
      bool saved = true}) async {
    if (startMs < 0 || endMs <= startMs || durationMs < 0 || path.isEmpty) {
      throw ArgumentError('Invalid shadowing segment or recording.');
    }
    final d = await db;
    _atomic(d, () {
      if (d.select('SELECT id FROM shadowing_attempts WHERE id=?',
          [attemptId]).isNotEmpty) return;
      if (d.select(
          'SELECT id FROM listening_lessons WHERE id=?', [lessonId]).isEmpty) {
        throw StateError('Listening lesson not found.');
      }
      final recording = newId();
      d.execute(
          "INSERT INTO speaking_recordings(id,lesson_id,mode,audio_path,duration_ms) VALUES(?,?,'shadowing',?,?)",
          [recording, lessonId, path, durationMs]);
      d.execute(
          'INSERT INTO shadowing_attempts(id,lesson_id,segment_start_ms,segment_end_ms,recording_id,duration_ms,saved) VALUES(?,?,?,?,?,?,?)',
          [
            attemptId,
            lessonId,
            startMs,
            endMs,
            recording,
            durationMs,
            saved ? 1 : 0
          ]);
      if (saved) {
        _activity(
            d, 'shadowing:$attemptId', 'shadowing_saved', 'listening_speaking',
            metadata: {'duration_ms': durationMs});
      }
    });
  }

  Future<void> confirmShadowingAttempt(String id) async {
    final d = await db;
    _atomic(d, () {
      final rows = d.select(
          'SELECT duration_ms FROM shadowing_attempts WHERE id=?', [id]);
      if (rows.isEmpty) throw StateError('Shadowing draft not found.');
      d.execute('UPDATE shadowing_attempts SET saved=1 WHERE id=?', [id]);
      _activity(d, 'shadowing:$id', 'shadowing_saved', 'listening_speaking',
          metadata: {'duration_ms': rows.single['duration_ms']});
    });
  }

  Future<List<Map<String, dynamic>>> getShadowingHistory(
          String lessonId) async =>
      (await db).select(
          '''SELECT a.*,r.audio_path FROM shadowing_attempts a LEFT JOIN speaking_recordings r ON r.id=a.recording_id
      WHERE a.lesson_id=? ORDER BY a.created_at DESC,a.rowid DESC''',
          [lessonId]);
  Future<void> deleteShadowingAttempt(String id) async {
    final d = await db;
    _atomic(d, () {
      final rows = d.select(
          'SELECT a.recording_id,r.audio_path FROM shadowing_attempts a LEFT JOIN speaking_recordings r ON r.id=a.recording_id WHERE a.id=?',
          [id]);
      if (rows.isEmpty) return;
      final row = rows.single;
      d.execute('DELETE FROM shadowing_attempts WHERE id=?', [id]);
      if (row['recording_id'] != null &&
          d.select('SELECT id FROM shadowing_attempts WHERE recording_id=?',
              [row['recording_id']]).isEmpty) {
        d.execute('DELETE FROM speaking_recordings WHERE id=?',
            [row['recording_id']]);
        if (row['audio_path'] != null) {
          d.execute(
              'INSERT OR IGNORE INTO pending_file_deletions(path) VALUES(?)',
              [row['audio_path']]);
        }
      }
    });
  }

  Future<List<String>> pendingFileDeletions() async => (await db)
      .select('SELECT path FROM pending_file_deletions')
      .map((r) => r['path'] as String)
      .toList();
  Future<void> completeFileDeletion(String path) async => (await db)
      .execute('DELETE FROM pending_file_deletions WHERE path=?', [path]);
  Future<Map<String, num>> activityStatistics() async {
    final d = await db;
    int count(String query) => d.select(query).first['n'] as int;
    return {
      'Comprehension answers':
          count('SELECT COUNT(*) n FROM comprehension_attempts'),
      'Objective correct': count(
          'SELECT COUNT(*) n FROM comprehension_attempts WHERE self_assessed=0 AND is_correct=1'),
      'Objective graded': count(
          'SELECT COUNT(*) n FROM comprehension_attempts WHERE self_assessed=0 AND is_correct IS NOT NULL'),
      'Shadowing attempts':
          count('SELECT COUNT(*) n FROM shadowing_attempts WHERE saved=1'),
      'Shadowing seconds': count(
          'SELECT COALESCE(SUM(duration_ms),0)/1000 n FROM shadowing_attempts WHERE saved=1'),
      'Speaking seconds': count(
          'SELECT COALESCE(SUM(duration_ms),0)/1000 n FROM speaking_recordings WHERE mode!=\'shadowing\''),
      'AI practice messages':
          count("SELECT COUNT(*) n FROM ai_messages WHERE role='user'"),
      'Writing revisions': count('SELECT COUNT(*) n FROM writing_revisions'),
      'Open mistakes': count(
          "SELECT COUNT(*) n FROM writing_mistakes WHERE review_status='open'"),
      'Reviewed mistakes': count(
          "SELECT COUNT(*) n FROM writing_mistakes WHERE review_status='understood'"),
      'Vocabulary reviews':
          count('SELECT COUNT(*) n FROM vocabulary_review_history'),
      'Reading opens': count(
          "SELECT COUNT(*) n FROM learning_activities WHERE type='reading_opened'"),
    };
  }

  void close() {
    _db?.dispose();
    _db = null;
  }

  // ─── Preferences ───────────────────────────────────────────────
  Future<UserPreference> getPreferences() async {
    final d = await db;
    final rows = d.select('SELECT * FROM user_preferences LIMIT 1');
    if (rows.isEmpty) {
      d.execute('INSERT INTO user_preferences DEFAULT VALUES;');
      return getPreferences();
    }
    return UserPreference.fromRow(rows.first);
  }

  Future<void> updatePreferences(Map<String, dynamic> fields) async {
    final d = await db;
    if (fields.isEmpty) return;
    final sets = fields.keys.map((k) => '$k = ?').join(', ');
    final values = [...fields.values, DateTime.now().toUtc().toIso8601String()];
    d.execute(
        'UPDATE user_preferences SET $sets, updated_at = ? WHERE id = (SELECT id FROM user_preferences LIMIT 1)',
        values);
  }

  // ─── Sessions ──────────────────────────────────────────────────
  Future<void> insertSession({
    required String id,
    required String module,
    required DateTime startedAt,
    required String localDate,
  }) async {
    final d = await db;
    d.execute(
      'INSERT INTO study_sessions (id, module, started_at, local_date) VALUES (?, ?, ?, ?)',
      [id, module, startedAt.toUtc().toIso8601String(), localDate],
    );
  }

  Future<void> updateSession(
    String id, {
    DateTime? endedAt,
    int? durationSeconds,
    bool? completed,
    bool? interrupted,
  }) async {
    final d = await db;
    final parts = <String>[];
    final values = <Object?>[];
    if (endedAt != null) {
      parts.add('ended_at = ?');
      values.add(endedAt.toUtc().toIso8601String());
    }
    if (durationSeconds != null) {
      parts.add('duration_seconds = ?');
      values.add(durationSeconds);
    }
    if (completed != null) {
      parts.add('completed = ?');
      values.add(completed ? 1 : 0);
    }
    if (interrupted != null) {
      parts.add('interrupted = ?');
      values.add(interrupted ? 1 : 0);
    }
    if (parts.isEmpty) return;
    values.add(id);
    d.execute(
        'UPDATE study_sessions SET ${parts.join(', ')} WHERE id = ?', values);
    if (durationSeconds != null) {
      final date =
          d.select('SELECT local_date FROM study_sessions WHERE id=?', [id]);
      if (date.isNotEmpty) {
        d.execute(
            '''INSERT INTO study_session_days(session_id,local_date,duration_ms) VALUES (?,?,?)
        ON CONFLICT(session_id,local_date) DO UPDATE SET duration_ms=excluded.duration_ms''',
            [id, date.first['local_date'], durationSeconds * 1000]);
      }
    }
  }

  Future<int> getTotalSecondsForDate(String localDate) async {
    final d = await db;
    final ms = d.select('''SELECT COALESCE(SUM(days.duration_ms),0) AS total
      FROM study_session_days days JOIN study_sessions s ON s.id=days.session_id
      WHERE days.local_date=? AND s.completed=1''', [localDate]).first['total']
        as int;
    return ms ~/ 1000;
  }

  Future<List<String>> getCompletedStudyDates({int limit = 400}) async {
    final d = await db;
    return d
        .select('''SELECT days.local_date FROM study_session_days days
      JOIN study_sessions s ON s.id=days.session_id
      WHERE s.completed=1 AND days.duration_ms>0 GROUP BY days.local_date
      ORDER BY days.local_date DESC LIMIT ?''', [limit])
        .map((r) => r['local_date'] as String)
        .toList();
  }

  Future<Map<String, dynamic>?> getActiveInterruptedSession() async {
    final d = await db;
    final rows = d.select(
      '''SELECT * FROM study_sessions
         WHERE completed = 0
         ORDER BY started_at DESC LIMIT 1''',
    );
    return rows.isEmpty ? null : rows.first;
  }

  // ─── Daily goals ───────────────────────────────────────────────
  Future<void> upsertDailyGoal({
    required String localDate,
    required int targetMinutes,
    required int completedMinutes,
    required bool goalMet,
  }) async {
    final d = await db;
    d.execute(
      '''INSERT INTO daily_goals (local_date, target_minutes, completed_minutes, goal_met, updated_at)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(local_date) DO UPDATE SET
           target_minutes = excluded.target_minutes,
           completed_minutes = excluded.completed_minutes,
           goal_met = excluded.goal_met,
           updated_at = excluded.updated_at''',
      [
        localDate,
        targetMinutes,
        completedMinutes,
        goalMet ? 1 : 0,
        DateTime.now().toUtc().toIso8601String()
      ],
    );
  }

  // ─── Activities ────────────────────────────────────────────────
  Future<void> logActivity({
    required String id,
    required String type,
    String? module,
    String? metadata,
    required String localDate,
  }) async {
    final d = await db;
    d.execute(
      'INSERT INTO learning_activities (id, type, module, metadata, local_date) VALUES (?, ?, ?, ?, ?)',
      [id, type, module, metadata, localDate],
    );
  }

  Future<List<LearningActivity>> getRecentActivities({int limit = 10}) async {
    final d = await db;
    final rows = d.select(
      'SELECT * FROM learning_activities ORDER BY created_at DESC LIMIT ?',
      [limit],
    );
    return rows.map(LearningActivity.fromRow).toList();
  }

  // ─── Vocabulary ────────────────────────────────────────────────
  Future<int> getSavedWordCount() async {
    final d = await db;
    final rows = d.select(
        'SELECT COUNT(*) AS c FROM vocabulary_entries WHERE is_saved = 1 AND duplicate_of IS NULL');
    return rows.first['c'] as int;
  }

  Future<int> getDueReviewCount() async {
    final d = await db;
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = d.select(
        'SELECT COUNT(DISTINCT r.entry_id) AS c FROM vocabulary_reviews r JOIN vocabulary_entries e ON e.id = r.entry_id WHERE e.is_saved = 1 AND e.duplicate_of IS NULL AND julianday(r.next_review_at) <= julianday(?)',
        [now]);
    return rows.first['c'] as int;
  }

  // ─── Phase 3: Listening ────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getListeningLessons() async {
    final d = await db;
    return d.select('SELECT * FROM listening_lessons ORDER BY created_at DESC');
  }

  Future<Map<String, dynamic>?> getListeningLesson(String id) async {
    final d = await db;
    final rows = d.select('SELECT * FROM listening_lessons WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> insertListeningLesson(Map<String, Object?> data) async {
    final d = await db;
    d.execute(
      'INSERT INTO listening_lessons (id, title, topic, difficulty, audio_path, duration_ms, last_position_ms, transcript, transcript_path) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        data['id'],
        data['title'],
        data['topic'],
        data['difficulty'],
        data['audio_path'],
        data['duration_ms'] ?? 0,
        data['last_position_ms'] ?? 0,
        data['transcript'],
        data['transcript_path'],
      ],
    );
  }

  Future<void> updateLessonPosition(String id, int positionMs,
      {int? durationMs}) async {
    final d = await db;
    if (durationMs != null) {
      d.execute(
        'UPDATE listening_lessons SET last_position_ms = ?, duration_ms = ?, updated_at = ? WHERE id = ?',
        [positionMs, durationMs, DateTime.now().toUtc().toIso8601String(), id],
      );
    } else {
      d.execute(
        'UPDATE listening_lessons SET last_position_ms = ?, updated_at = ? WHERE id = ?',
        [positionMs, DateTime.now().toUtc().toIso8601String(), id],
      );
    }
  }

  Future<void> updateLessonTranscript(String id, String transcript) async {
    final d = await db;
    d.execute(
      'UPDATE listening_lessons SET transcript = ?, updated_at = ? WHERE id = ?',
      [transcript, DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  Future<void> deleteListeningLesson(String id) async {
    final d = await db;
    d.execute('BEGIN IMMEDIATE');
    try {
      d.execute('DELETE FROM playback_bookmarks WHERE lesson_id = ?', [id]);
      d.execute('DELETE FROM comprehension_attempts WHERE lesson_id = ?', [id]);
      d.execute(
          'DELETE FROM comprehension_questions WHERE lesson_id = ?', [id]);
      d.execute('DELETE FROM shadowing_attempts WHERE lesson_id = ?', [id]);
      d.execute('DELETE FROM listening_lessons WHERE id = ?', [id]);
      d.execute('COMMIT');
    } catch (_) {
      d.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> addBookmark(String id, String lessonId, int positionMs,
      {String? label}) async {
    final d = await db;
    d.execute(
      'INSERT INTO playback_bookmarks (id, lesson_id, position_ms, label) VALUES (?, ?, ?, ?)',
      [id, lessonId, positionMs, label],
    );
  }

  Future<List<Map<String, dynamic>>> getBookmarks(String lessonId) async {
    final d = await db;
    return d.select(
      'SELECT * FROM playback_bookmarks WHERE lesson_id = ? ORDER BY position_ms',
      [lessonId],
    );
  }

  Future<void> deleteBookmark(String id) async {
    final d = await db;
    d.execute('DELETE FROM playback_bookmarks WHERE id = ?', [id]);
  }

  Future<List<Map<String, dynamic>>> getQuestions(String lessonId) async {
    final d = await db;
    return d.select(
      'SELECT * FROM comprehension_questions WHERE lesson_id = ? ORDER BY order_index',
      [lessonId],
    );
  }

  Future<void> insertQuestion(Map<String, Object?> q) async {
    final d = await db;
    d.execute(
      'INSERT INTO comprehension_questions (id, lesson_id, question, question_type, choices, correct_answer, order_index) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        q['id'],
        q['lesson_id'],
        q['question'],
        q['question_type'],
        q['choices'],
        q['correct_answer'],
        q['order_index'] ?? 0
      ],
    );
  }

  Future<void> saveAttempt(Map<String, Object?> a) async {
    final d = await db;
    d.execute(
      'INSERT INTO comprehension_attempts (id, question_id, lesson_id, learner_response, is_correct, self_assessed) VALUES (?, ?, ?, ?, ?, ?)',
      [
        a['id'],
        a['question_id'],
        a['lesson_id'],
        a['learner_response'],
        a['is_correct'],
        a['self_assessed'] ?? 0
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getSpeakingPrompts(
      {String? category}) async {
    final d = await db;
    if (category == null) {
      return d
          .select('SELECT * FROM speaking_prompts ORDER BY category, title');
    }
    return d.select(
        'SELECT * FROM speaking_prompts WHERE category = ? ORDER BY title',
        [category]);
  }

  Future<void> insertSpeakingPrompt(Map<String, Object?> p) async {
    final d = await db;
    d.execute(
      'INSERT OR IGNORE INTO speaking_prompts (id, title, difficulty, category, prompt_text, guidance, suggested_seconds, is_builtin) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        p['id'],
        p['title'],
        p['difficulty'],
        p['category'],
        p['prompt_text'],
        p['guidance'],
        p['suggested_seconds'] ?? 60,
        p['is_builtin'] ?? 0
      ],
    );
  }

  Future<int> countSpeakingPrompts() async {
    final d = await db;
    return d.select('SELECT COUNT(*) AS c FROM speaking_prompts').first['c']
        as int;
  }

  Future<void> seedBuiltinPromptsIfEmpty() async {
    final prompts = <List<Object?>>[
      [
        'sp_daily_1',
        'Introduce yourself',
        'B1',
        'everyday',
        'Introduce yourself to a new classmate. Include your name, where you are from, and one hobby.',
        'Speak for about 45–60 seconds. Use full sentences.',
        60,
        1
      ],
      [
        'sp_daily_2',
        'Describe your weekend',
        'B1',
        'everyday',
        'Describe what you did last weekend. Mention at least two activities and how you felt.',
        null,
        60,
        1
      ],
      [
        'sp_uni_1',
        'Campus life',
        'B1',
        'university',
        'Talk about a typical day on campus or at school. What do you study and where do you spend most of your time?',
        null,
        75,
        1
      ],
      [
        'sp_uni_2',
        'Group project challenge',
        'B2',
        'university',
        'Describe a time you worked on a group project. What went well and what was difficult?',
        'Use past tenses and at least one example.',
        90,
        1
      ],
      [
        'sp_tech_1',
        'Favorite app',
        'B1',
        'technology',
        'Describe an app or website you use every day. Why is it useful?',
        null,
        60,
        1
      ],
      [
        'sp_tech_2',
        'Explain a programming idea',
        'B2',
        'technology',
        'Explain a simple programming concept (for example: variables, loops, or functions) to a beginner.',
        'Avoid jargon where possible. Give one example.',
        90,
        1
      ],
      [
        'sp_job_1',
        'Why this role?',
        'B2',
        'job_interview',
        'Imagine a job interview. Answer: Why are you interested in this position?',
        'Keep your answer structured: interest, skills, goal.',
        75,
        1
      ],
      [
        'sp_job_2',
        'Strengths and growth',
        'B2',
        'job_interview',
        'Describe one professional strength and one area you want to improve. Give a short example for each.',
        null,
        90,
        1
      ],
      [
        'sp_opinion_1',
        'Remote work',
        'B2',
        'opinion',
        'Do you prefer working or studying from home or in a shared space? Give two reasons.',
        'State your opinion clearly, then support it.',
        75,
        1
      ],
      [
        'sp_exp_1',
        'A memorable trip',
        'B1',
        'experience',
        'Describe a memorable trip or outing. Where did you go and what made it special?',
        null,
        60,
        1
      ],
    ];
    for (final row in prompts) {
      await insertSpeakingPrompt({
        'id': row[0],
        'title': row[1],
        'difficulty': row[2],
        'category': row[3],
        'prompt_text': row[4],
        'guidance': row[5],
        'suggested_seconds': row[6],
        'is_builtin': row[7],
      });
    }
  }

  Future<void> insertRecording(Map<String, Object?> r) async {
    final d = await db;
    d.execute(
      'INSERT INTO speaking_recordings (id, prompt_id, lesson_id, mode, audio_path, duration_ms, self_rating, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        r['id'],
        r['prompt_id'],
        r['lesson_id'],
        r['mode'] ?? 'prompt',
        r['audio_path'],
        r['duration_ms'] ?? 0,
        r['self_rating'],
        r['notes']
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getRecordings({String? promptId}) async {
    final d = await db;
    if (promptId != null) {
      return d.select(
          'SELECT * FROM speaking_recordings WHERE prompt_id = ? ORDER BY created_at DESC',
          [promptId]);
    }
    return d
        .select('SELECT * FROM speaking_recordings ORDER BY created_at DESC');
  }

  Future<void> deleteRecording(String id) async {
    final d = await db;
    d.execute('DELETE FROM speaking_recordings WHERE id = ?', [id]);
  }

  Future<void> insertShadowingAttempt(Map<String, Object?> s) async {
    final d = await db;
    d.execute(
      'INSERT INTO shadowing_attempts (id, lesson_id, segment_start_ms, segment_end_ms, recording_id, self_rating, duration_ms) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        s['id'],
        s['lesson_id'],
        s['segment_start_ms'] ?? 0,
        s['segment_end_ms'],
        s['recording_id'],
        s['self_rating'],
        s['duration_ms'] ?? 0
      ],
    );
  }

  Future<void> insertAiConversation(String id,
      {String? provider, String? title}) async {
    final d = await db;
    d.execute(
      'INSERT INTO ai_conversations (id, provider, title, started_at) VALUES (?, ?, ?, ?)',
      [id, provider, title, DateTime.now().toUtc().toIso8601String()],
    );
  }

  Future<void> insertAiMessage(
      String id, String conversationId, String role, String content,
      {bool isLocal = true}) async {
    final d = await db;
    d.execute('BEGIN IMMEDIATE');
    try {
      d.execute(
        'INSERT INTO ai_messages (id, conversation_id, role, content,is_local) VALUES (?, ?, ?, ?,?)',
        [id, conversationId, role, content, isLocal ? 1 : 0],
      );
      d.execute(
        'UPDATE ai_conversations SET message_count = message_count + 1, last_message_at = ? WHERE id = ?',
        [DateTime.now().toUtc().toIso8601String(), conversationId],
      );
      d.execute('COMMIT');
    } catch (_) {
      d.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAiMessages(String conversationId,
      {int offset = 0}) async {
    final d = await db;
    return d
        .select(
          'SELECT * FROM ai_messages WHERE conversation_id = ? ORDER BY created_at DESC, rowid DESC LIMIT 100 OFFSET ?',
          [conversationId, offset.clamp(0, 1000000)],
        )
        .reversed
        .toList();
  }

  Future<List<Map<String, dynamic>>> getAiConversations() async {
    final d = await db;
    return d.select(
        'SELECT * FROM ai_conversations WHERE is_active = 1 ORDER BY started_at DESC, rowid DESC');
  }

  // ─── Phase 4: Grammar ──────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getGrammarLessons({String? level}) async {
    final d = await db;
    if (level == null) {
      return d.select(
          'SELECT * FROM grammar_lessons ORDER BY cefr_level, order_index');
    }
    return d.select(
        'SELECT * FROM grammar_lessons WHERE cefr_level = ? ORDER BY order_index',
        [level]);
  }

  Future<Map<String, dynamic>?> getGrammarLesson(String id) async {
    final d = await db;
    final rows = d.select('SELECT * FROM grammar_lessons WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> insertGrammarLesson(Map<String, Object?> m) async {
    final d = await db;
    d.execute(
      'INSERT OR IGNORE INTO grammar_lessons (id, title, cefr_level, topic_key, objective, explanation, examples, common_mistakes, order_index, completed) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        m['id'],
        m['title'],
        m['cefr_level'],
        m['topic_key'],
        m['objective'],
        m['explanation'],
        m['examples'],
        m['common_mistakes'],
        m['order_index'] ?? 0,
        m['completed'] ?? 0
      ],
    );
  }

  Future<void> markGrammarLessonComplete(String id) async {
    final d = await db;
    d.execute('UPDATE grammar_lessons SET completed = 1 WHERE id = ?', [id]);
  }

  Future<List<Map<String, dynamic>>> getGrammarExercises(
      String lessonId) async {
    final d = await db;
    return d.select(
        'SELECT * FROM grammar_exercises WHERE lesson_id = ? ORDER BY order_index',
        [lessonId]);
  }

  Future<void> insertGrammarExercise(Map<String, Object?> m) async {
    final d = await db;
    d.execute(
      'INSERT OR IGNORE INTO grammar_exercises (id, lesson_id, question_type, prompt, choices, correct_answer, alternatives, explanation, order_index) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        m['id'],
        m['lesson_id'],
        m['question_type'],
        m['prompt'],
        m['choices'],
        m['correct_answer'],
        m['alternatives'],
        m['explanation'],
        m['order_index'] ?? 0
      ],
    );
  }

  Future<void> saveGrammarAttempt(Map<String, Object?> a) async {
    final d = await db;
    d.execute(
      'INSERT INTO grammar_attempts (id, exercise_id, lesson_id, learner_response, is_correct, self_assessed) VALUES (?, ?, ?, ?, ?, ?)',
      [
        a['id'],
        a['exercise_id'],
        a['lesson_id'],
        a['learner_response'],
        a['is_correct'],
        a['self_assessed'] ?? 0
      ],
    );
  }

  Future<int> countGrammarLessons() async {
    final d = await db;
    return d.select('SELECT COUNT(*) AS c FROM grammar_lessons').first['c']
        as int;
  }

  // Writing
  Future<List<Map<String, dynamic>>> getWritingEntries() async {
    final d = await db;
    return d.select('SELECT * FROM writing_entries ORDER BY updated_at DESC');
  }

  Future<Map<String, dynamic>?> getWritingEntry(String id) async {
    final d = await db;
    final rows = d.select('SELECT * FROM writing_entries WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> upsertWritingEntry(Map<String, Object?> m) async {
    final d = await db;
    d.execute(
      '''INSERT INTO writing_entries (id, title, category, body, word_count, prompt_id, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, COALESCE(?, datetime('now')), ?)
         ON CONFLICT(id) DO UPDATE SET
           title = excluded.title,
           category = excluded.category,
           body = excluded.body,
           word_count = excluded.word_count,
           updated_at = excluded.updated_at''',
      [
        m['id'],
        m['title'],
        m['category'] ?? 'free',
        m['body'] ?? '',
        m['word_count'] ?? 0,
        m['prompt_id'],
        m['created_at'],
        m['updated_at'] ?? DateTime.now().toUtc().toIso8601String()
      ],
    );
  }

  Future<void> deleteWritingEntry(String id) async {
    final d = await db;
    d.execute('BEGIN IMMEDIATE');
    try {
      d.execute('DELETE FROM writing_revisions WHERE entry_id = ?', [id]);
      d.execute('DELETE FROM writing_feedback WHERE entry_id = ?', [id]);
      d.execute('DELETE FROM writing_entries WHERE id = ?', [id]);
      d.execute('COMMIT');
    } catch (_) {
      d.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> saveWritingRevision(Map<String, Object?> m) async {
    final d = await db;
    _atomic(d, () {
      final latest = d.select(
          'SELECT body,label FROM writing_revisions WHERE entry_id=? ORDER BY created_at DESC,rowid DESC LIMIT 1',
          [m['entry_id']]);
      if (latest.isNotEmpty &&
          latest.single['body'] == m['body'] &&
          latest.single['label'] == m['label']) return;
      d.execute(
          'INSERT INTO writing_revisions(id,entry_id,body,word_count,label) VALUES(?,?,?,?,?)',
          [
            m['id'],
            m['entry_id'],
            m['body'],
            m['word_count'] ?? 0,
            m['label']
          ]);
      _activity(d, 'revision:${m['id']}', 'writing_revision_saved',
          'grammar_writing');
    });
  }

  Future<List<Map<String, dynamic>>> getWritingRevisions(String entryId) async {
    final d = await db;
    return d.select(
        'SELECT * FROM writing_revisions WHERE entry_id = ? ORDER BY created_at DESC,rowid DESC',
        [entryId]);
  }

  Future<void> saveWritingFeedback(Map<String, Object?> m) async {
    final d = await db;
    d.execute(
      'INSERT INTO writing_feedback (id, entry_id, source, content) VALUES (?, ?, ?, ?)',
      [m['id'], m['entry_id'], m['source'] ?? 'ai', m['content']],
    );
  }

  Future<List<Map<String, dynamic>>> getWritingFeedback(String entryId) async {
    final d = await db;
    return d.select(
        'SELECT * FROM writing_feedback WHERE entry_id = ? ORDER BY created_at DESC,rowid DESC',
        [entryId]);
  }

  Future<void> saveWritingMistake(Map<String, Object?> m) async {
    final original = (m['original_sentence'] as String? ?? '').trim();
    final correction = (m['correction'] as String? ?? '').trim();
    if (original.isEmpty || correction.isEmpty) {
      throw ArgumentError('Original and corrected sentences are required.');
    }
    final d = await db;
    _atomic(d, () {
      final existed = d.select(
          'SELECT id FROM writing_mistakes WHERE id=?', [m['id']]).isNotEmpty;
      d.execute(
          '''INSERT INTO writing_mistakes(id,entry_id,grammar_topic,original_sentence,correction,explanation,review_status,updated_at)
        VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET grammar_topic=excluded.grammar_topic,
        original_sentence=excluded.original_sentence,correction=excluded.correction,explanation=excluded.explanation,
        review_status=excluded.review_status,updated_at=excluded.updated_at''',
          [
            m['id'],
            m['entry_id'],
            m['grammar_topic'] ?? 'general',
            original,
            correction,
            m['explanation'],
            m['review_status'] ?? 'open',
            DateTime.now().toUtc().toIso8601String()
          ]);
      if (!existed) {
        _activity(d, 'mistake:${m['id']}', 'writing_mistake_created',
            'grammar_writing');
      }
    });
  }

  Future<List<Map<String, dynamic>>> getWritingMistakes() async {
    final d = await db;
    return d.select('SELECT * FROM writing_mistakes ORDER BY created_at DESC');
  }

  Future<void> markMistakeReviewed(String id) async {
    final d = await db;
    d.execute(
        'UPDATE writing_mistakes SET review_status = ?,updated_at=? WHERE id = ?',
        ['understood', DateTime.now().toUtc().toIso8601String(), id]);
  }

  // Books
  Future<List<Map<String, dynamic>>> getImportedBooks() async {
    final d = await db;
    return d.select('SELECT * FROM imported_books ORDER BY updated_at DESC');
  }

  Future<Map<String, dynamic>?> getImportedBook(String id) async {
    final d = await db;
    final rows = d.select('SELECT * FROM imported_books WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> insertImportedBook(Map<String, Object?> m) async {
    final d = await db;
    d.execute(
      'INSERT INTO imported_books (id, title, file_path, page_count, current_page) VALUES (?, ?, ?, ?, ?)',
      [
        m['id'],
        m['title'],
        m['file_path'],
        m['page_count'] ?? 0,
        m['current_page'] ?? 1
      ],
    );
  }

  Future<void> updateBookProgress(String id, int page, {int? pageCount}) async {
    final d = await db;
    if (pageCount != null) {
      d.execute(
          'UPDATE imported_books SET current_page = ?, page_count = ?, updated_at = ? WHERE id = ?',
          [page, pageCount, DateTime.now().toUtc().toIso8601String(), id]);
    } else {
      d.execute(
          'UPDATE imported_books SET current_page = ?, updated_at = ? WHERE id = ?',
          [page, DateTime.now().toUtc().toIso8601String(), id]);
    }
  }

  Future<void> renameBook(String id, String title) async {
    final d = await db;
    d.execute(
        'UPDATE imported_books SET title = ?, updated_at = ? WHERE id = ?',
        [title, DateTime.now().toUtc().toIso8601String(), id]);
  }

  Future<void> deleteImportedBook(String id) async {
    final d = await db;
    d.execute('BEGIN IMMEDIATE');
    try {
      d.execute('DELETE FROM book_bookmarks WHERE book_id = ?', [id]);
      d.execute('DELETE FROM book_lessons WHERE book_id = ?', [id]);
      d.execute('DELETE FROM book_units WHERE book_id = ?', [id]);
      d.execute(
          "DELETE FROM completion_requirements WHERE target_type='book' AND target_id=?",
          [id]);
      d.execute('DELETE FROM imported_books WHERE id = ?', [id]);
      d.execute('COMMIT');
    } catch (_) {
      d.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> insertBookUnit(Map<String, Object?> m) async {
    final d = await db;
    d.execute(
        'INSERT INTO book_units (id, book_id, title, order_index, completed) VALUES (?, ?, ?, ?, ?)',
        [
          m['id'],
          m['book_id'],
          m['title'],
          m['order_index'] ?? 0,
          m['completed'] ?? 0
        ]);
  }

  Future<List<Map<String, dynamic>>> getBookUnits(String bookId) async {
    final d = await db;
    return d.select(
        'SELECT * FROM book_units WHERE book_id = ? ORDER BY order_index',
        [bookId]);
  }

  Future<void> insertBookLesson(Map<String, Object?> m) async {
    final d = await db;
    d.execute(
      'INSERT INTO book_lessons (id, unit_id, book_id, title, notes, page_start, page_end, objective, completed, order_index) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        m['id'],
        m['unit_id'],
        m['book_id'],
        m['title'],
        m['notes'],
        m['page_start'],
        m['page_end'],
        m['objective'],
        m['completed'] ?? 0,
        m['order_index'] ?? 0
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getBookLessons(String bookId) async {
    final d = await db;
    return d.select(
        'SELECT * FROM book_lessons WHERE book_id = ? ORDER BY order_index',
        [bookId]);
  }

  Future<void> markBookLessonComplete(String id, bool completed) async {
    final d = await db;
    d.execute('UPDATE book_lessons SET completed = ? WHERE id = ?',
        [completed ? 1 : 0, id]);
  }

  Future<void> addBookBookmark(String id, String bookId, int page,
      {String? label}) async {
    final d = await db;
    d.execute(
        'INSERT INTO book_bookmarks (id, book_id, page, label) VALUES (?, ?, ?, ?)',
        [id, bookId, page, label]);
  }

  Future<List<Map<String, dynamic>>> getBookBookmarks(String bookId) async {
    final d = await db;
    return d.select(
        'SELECT * FROM book_bookmarks WHERE book_id = ? ORDER BY page',
        [bookId]);
  }

  // ─── Phase 5: Assessments & certificates ───────────────────────
  Future<void> insertAssessmentDefinition(Map<String, Object?> m) async {
    final d = await db;
    d.execute(
      'INSERT OR IGNORE INTO assessment_definitions (id, title, category, description, time_limit_seconds, pass_threshold) VALUES (?, ?, ?, ?, ?, ?)',
      [
        m['id'],
        m['title'],
        m['category'],
        m['description'],
        m['time_limit_seconds'],
        m['pass_threshold'] ?? 0.7
      ],
    );
  }

  Future<void> insertAssessmentQuestion(Map<String, Object?> m) async {
    final d = await db;
    d.execute(
      'INSERT OR IGNORE INTO assessment_questions (id, assessment_id, question_type, prompt, choices, correct_answer, explanation, order_index) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        m['id'],
        m['assessment_id'],
        m['question_type'],
        m['prompt'],
        m['choices'],
        m['correct_answer'],
        m['explanation'],
        m['order_index'] ?? 0
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getAssessments() async {
    final d = await db;
    return d.select(
        'SELECT * FROM assessment_definitions ORDER BY category, title');
  }

  Future<Map<String, dynamic>?> getAssessment(String id) async {
    final d = await db;
    final rows =
        d.select('SELECT * FROM assessment_definitions WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getAssessmentQuestions(
      String assessmentId) async {
    final d = await db;
    return d.select(
        'SELECT * FROM assessment_questions WHERE assessment_id = ? ORDER BY order_index',
        [assessmentId]);
  }

  Future<int> countAssessments() async {
    final d = await db;
    return d
        .select('SELECT COUNT(*) AS c FROM assessment_definitions')
        .first['c'] as int;
  }

  Future<void> saveAssessmentAttempt(Map<String, Object?> m) async {
    final d = await db;
    d.execute(
      'INSERT INTO assessment_attempts (id, assessment_id, score, max_score, passed, self_assessed, answers_json, started_at, completed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        m['id'],
        m['assessment_id'],
        m['score'],
        m['max_score'],
        m['passed'] ?? 0,
        m['self_assessed'] ?? 0,
        m['answers_json'],
        m['started_at'],
        m['completed_at']
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getAssessmentAttempts() async {
    final d = await db;
    return d
        .select('SELECT * FROM assessment_attempts ORDER BY completed_at DESC');
  }

  /// Certificate evidence is read from persisted records, never a UI flag.
  Future<Map<String, dynamic>?> certificateEvidence(
      String type, String id) async {
    final d = await db;
    return _certificateEvidence(d, type, id);
  }

  Map<String, dynamic>? _certificateEvidence(
      Database d, String type, String id) {
    Map<String, dynamic>? passing(String assessmentId) {
      final rows =
          d.select('''SELECT a.score, def.title FROM assessment_attempts a
        JOIN assessment_definitions def ON def.id=a.assessment_id
        WHERE a.assessment_id=? AND a.completed_at IS NOT NULL
          AND a.self_assessed=0 AND a.passed=1 AND a.score>=def.pass_threshold
          AND a.score<=1 AND a.max_score=1 AND a.score>=0
          AND EXISTS (SELECT 1 FROM assessment_questions q WHERE q.assessment_id=def.id)
        ORDER BY a.completed_at DESC LIMIT 1''', [assessmentId]);
      return rows.isEmpty ? null : rows.first;
    }

    if (type == 'assessment') {
      final evidence = passing(id);
      return evidence == null
          ? null
          : {...evidence, 'verification_type': 'assessment_pass'};
    }
    final String table;
    final String lessons;
    final String parent;
    if (type == 'book') {
      table = 'imported_books';
      lessons = 'book_lessons';
      parent = 'book_id';
    } else if (type == 'course') {
      table = 'courses';
      lessons = 'lessons';
      parent = 'course_id';
    } else {
      return null;
    }
    final targets = d.select('SELECT * FROM $table WHERE id=?', [id]);
    if (targets.isEmpty) return null;
    final required =
        d.select('SELECT completed FROM $lessons WHERE $parent=?', [id]);
    if (required.isEmpty || required.any((r) => r['completed'] != 1)) {
      return null;
    }
    if (type == 'course' &&
        required.length < (targets.first['total_lessons'] as int)) return null;
    if (type == 'book' &&
        d.select('SELECT id FROM book_units WHERE book_id=?', [id]).isEmpty) {
      return null;
    }
    if (type == 'book' &&
        d.select('''SELECT u.id FROM book_units u WHERE u.book_id=?
      AND NOT EXISTS (SELECT 1 FROM book_lessons l WHERE l.unit_id=u.id AND l.book_id=u.book_id)''',
            [id]).isNotEmpty) return null;
    final assessments = d.select(
        'SELECT assessment_id FROM completion_requirements WHERE target_type=? AND target_id=?',
        [type, id]);
    // Unconfigured requirements are not permission to issue a certificate.
    if (assessments.isEmpty) return null;
    var score = 0.0;
    for (final requirement in assessments) {
      final pass = passing(requirement['assessment_id'] as String);
      if (pass == null) return null;
      score += (pass['score'] as num).toDouble();
    }
    return {
      'title': targets.first['title'],
      'score': score / assessments.length,
      'verification_type': 'lessons_and_assessments'
    };
  }

  Future<void> saveCertificateWithCompletion(
      Map<String, Object?> completion, Map<String, Object?> certificate) async {
    final d = await db;
    d.execute('BEGIN IMMEDIATE');
    try {
      final evidence = _certificateEvidence(
          d,
          completion['target_type'] as String,
          completion['target_id'] as String);
      if (evidence == null ||
          evidence['title'] != completion['target_title'] ||
          evidence['score'] != completion['assessment_score'] ||
          evidence['verification_type'] != completion['verification_type']) {
        throw StateError(
            'Completion evidence changed. Verify requirements before issuing.');
      }
      _insertCompletionRecord(d, completion);
      _insertCertificate(d, certificate);
      d.execute('COMMIT');
    } catch (_) {
      d.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> insertCompletionRecord(Map<String, Object?> m) async {
    final d = await db;
    _insertCompletionRecord(d, m);
  }

  void _insertCompletionRecord(Database d, Map<String, Object?> m) {
    d.execute(
      'INSERT INTO completion_records (id, target_type, target_id, target_title, verification_type, assessment_score, completed_at, certificate_eligible, certificate_ref) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        m['id'],
        m['target_type'],
        m['target_id'],
        m['target_title'],
        m['verification_type'],
        m['assessment_score'],
        m['completed_at'],
        m['certificate_eligible'] ?? 0,
        m['certificate_ref']
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getCompletionRecords() async {
    final d = await db;
    return d
        .select('SELECT * FROM completion_records ORDER BY completed_at DESC');
  }

  Future<void> insertCertificate(Map<String, Object?> m) async {
    final d = await db;
    _insertCertificate(d, m);
  }

  void _insertCertificate(Database d, Map<String, Object?> m) {
    d.execute(
      'INSERT INTO certificates (id, completion_id, learner_name, title, ref_number, score_text, verification_type, issued_at, file_path) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        m['id'],
        m['completion_id'],
        m['learner_name'],
        m['title'],
        m['ref_number'],
        m['score_text'],
        m['verification_type'],
        m['issued_at'],
        m['file_path']
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getCertificates() async {
    final d = await db;
    return d.select('SELECT * FROM certificates ORDER BY issued_at DESC');
  }

  Future<List<Map<String, dynamic>>> getSessionsLastDays(int days) async {
    final d = await db;
    if (days < 1) return [];
    final now = DateTime.now();
    final since = DateTime(now.year, now.month, now.day - days + 1);
    final start =
        '${since.year.toString().padLeft(4, '0')}-${since.month.toString().padLeft(2, '0')}-${since.day.toString().padLeft(2, '0')}';
    return d.select(
      'SELECT days.local_date, CAST(SUM(days.duration_ms)/1000 AS INTEGER) AS total_seconds, SUM(days.duration_ms) AS total_ms FROM study_session_days days JOIN study_sessions s ON s.id=days.session_id WHERE s.completed = 1 AND days.local_date >= ? AND days.local_date <= ? GROUP BY days.local_date ORDER BY days.local_date',
      [
        start,
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
      ],
    );
  }

  Future<int> getTotalStudySeconds() async {
    final d = await db;
    return d
        .select(
            'SELECT CAST(COALESCE(SUM(days.duration_ms),0)/1000 AS INTEGER) AS t FROM study_session_days days JOIN study_sessions s ON s.id=days.session_id WHERE s.completed=1')
        .first['t'] as int;
  }

  Future<int> countCompletedGrammarLessons() async {
    final d = await db;
    return d
        .select('SELECT COUNT(*) AS c FROM grammar_lessons WHERE completed = 1')
        .first['c'] as int;
  }

  Future<int> countGrammarAttempts() async {
    final d = await db;
    return d
        .select(
            'SELECT COUNT(*) AS c FROM grammar_attempts WHERE is_correct IS NOT NULL')
        .first['c'] as int;
  }

  Future<double> grammarAccuracy() async {
    final d = await db;
    final total = d
        .select(
            'SELECT COUNT(*) AS c FROM grammar_attempts WHERE is_correct IS NOT NULL')
        .first['c'] as int;
    if (total == 0) return 0;
    final correct = d
        .select(
            'SELECT COUNT(*) AS c FROM grammar_attempts WHERE is_correct = 1')
        .first['c'] as int;
    return correct / total;
  }

  Future<int> countWritingEntries() async {
    final d = await db;
    return d.select('SELECT COUNT(*) AS c FROM writing_entries').first['c']
        as int;
  }

  Future<int> countListeningLessons() async {
    final d = await db;
    return d.select('SELECT COUNT(*) AS c FROM listening_lessons').first['c']
        as int;
  }

  Future<int> countSpeakingRecordings() async {
    final d = await db;
    return d.select('SELECT COUNT(*) AS c FROM speaking_recordings').first['c']
        as int;
  }

  Future<int> countImportedBooks() async {
    final d = await db;
    return d.select('SELECT COUNT(*) AS c FROM imported_books').first['c']
        as int;
  }
}

class UserPreference {
  final int id;
  final String? displayName;
  final String englishLevel;
  final String targetLevel;
  final int dailyTargetMinutes;
  final int readingMinutes;
  final int vocabularyMinutes;
  final int listeningSpeakingMinutes;
  final int grammarWritingMinutes;
  final String englishPreference;
  final String translationLanguage;
  final String learningPriorities;
  final bool onboardingCompleted;
  final String themeMode;

  UserPreference({
    required this.id,
    this.displayName,
    required this.englishLevel,
    required this.targetLevel,
    required this.dailyTargetMinutes,
    required this.readingMinutes,
    required this.vocabularyMinutes,
    required this.listeningSpeakingMinutes,
    required this.grammarWritingMinutes,
    required this.englishPreference,
    required this.translationLanguage,
    required this.learningPriorities,
    required this.onboardingCompleted,
    required this.themeMode,
  });

  factory UserPreference.fromRow(Map<String, dynamic> r) {
    return UserPreference(
      id: r['id'] as int,
      displayName: r['display_name'] as String?,
      englishLevel: r['english_level'] as String,
      targetLevel: r['target_level'] as String,
      dailyTargetMinutes: r['daily_target_minutes'] as int,
      readingMinutes: r['reading_minutes'] as int,
      vocabularyMinutes: r['vocabulary_minutes'] as int,
      listeningSpeakingMinutes: r['listening_speaking_minutes'] as int,
      grammarWritingMinutes: r['grammar_writing_minutes'] as int,
      englishPreference: r['english_preference'] as String,
      translationLanguage: r['translation_language'] as String,
      learningPriorities: r['learning_priorities'] as String,
      onboardingCompleted: (r['onboarding_completed'] as int) == 1,
      themeMode: r['theme_mode'] as String,
    );
  }

  UserPreference copyWith({int? dailyTargetMinutes}) {
    return UserPreference(
      id: id,
      displayName: displayName,
      englishLevel: englishLevel,
      targetLevel: targetLevel,
      dailyTargetMinutes: dailyTargetMinutes ?? this.dailyTargetMinutes,
      readingMinutes: readingMinutes,
      vocabularyMinutes: vocabularyMinutes,
      listeningSpeakingMinutes: listeningSpeakingMinutes,
      grammarWritingMinutes: grammarWritingMinutes,
      englishPreference: englishPreference,
      translationLanguage: translationLanguage,
      learningPriorities: learningPriorities,
      onboardingCompleted: onboardingCompleted,
      themeMode: themeMode,
    );
  }
}

class LearningActivity {
  final String id;
  final String type;
  final String? module;
  final String? metadata;
  final String localDate;
  final String createdAt;

  LearningActivity({
    required this.id,
    required this.type,
    this.module,
    this.metadata,
    required this.localDate,
    required this.createdAt,
  });

  factory LearningActivity.fromRow(Map<String, dynamic> r) {
    return LearningActivity(
      id: r['id'] as String,
      type: r['type'] as String,
      module: r['module'] as String?,
      metadata: r['metadata'] as String?,
      localDate: r['local_date'] as String,
      createdAt: r['created_at'] as String,
    );
  }
}
