import '../database/app_database.dart';

const mistakeCategories = [
  'Articles',
  'Verb tenses',
  'Prepositions',
  'Word order',
  'Subject–verb agreement',
  'Vocabulary choice',
  'Sentence structure',
  'Other'
];

class MistakeCoach {
  MistakeCoach(this.database, {DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final AppDatabase database;
  final DateTime Function() _now;
  Future<List<Map<String, dynamic>>> practice({String? category}) async =>
      (await database.db).select('''
    SELECT m.*,(SELECT COUNT(*) FROM mistake_practice_attempts a WHERE a.mistake_id=m.id) repetitions
    FROM writing_mistakes m WHERE m.deleted=0 AND LENGTH(TRIM(COALESCE(m.correction,'')))>0
      AND TRIM(m.original_sentence)!=TRIM(m.correction)
      AND (? IS NULL OR COALESCE(m.grammar_topic,'Other')=?)
    ORDER BY CASE WHEN m.review_status='open' THEN 0 ELSE 1 END,
      (SELECT COUNT(*) FROM mistake_practice_attempts a WHERE a.mistake_id=m.id),m.created_at,m.id LIMIT 5''',
          [category, category]);

  Future<void> answer(
      {required String attemptId,
      required String mistakeId,
      required int expectedRevision,
      required String response,
      bool? selfAssessment}) async {
    if (response.trim().isEmpty) {
      throw ArgumentError('Enter a response before reviewing.');
    }
    final db = await database.db;
    db.execute('BEGIN IMMEDIATE');
    try {
      final previous = db.select(
          'SELECT * FROM mistake_practice_attempts WHERE id=?', [attemptId]);
      if (previous.isNotEmpty) {
        final row = previous.single;
        if (row['mistake_id'] != mistakeId ||
            row['response'] != response ||
            row['mode'] != (selfAssessment == null ? 'exact' : 'self')) {
          throw StateError('This attempt ID has already been used.');
        }
        db.execute('COMMIT');
        return;
      }
      final rows = db.select(
          'SELECT * FROM writing_mistakes WHERE id=? AND deleted=0',
          [mistakeId]);
      if (rows.isEmpty || rows.single['revision'] != expectedRevision) {
        throw StateError(
            'This correction changed. Reload practice before answering.');
      }
      final row = rows.single;
      final correction = (row['correction'] as String? ?? '').trim();
      if (correction.isEmpty) {
        throw StateError('Add a confirmed correction before practice.');
      }
      final correct = selfAssessment ??
          (AppDatabase.normalizeCorrection(response) ==
              AppDatabase.normalizeCorrection(correction));
      db.execute(
          'INSERT INTO mistake_practice_attempts VALUES(?,?,?,?,?,?,?,?,?)', [
        attemptId,
        mistakeId,
        selfAssessment == null ? 'exact' : 'self',
        response,
        correct ? 1 : 0,
        row['original_sentence'],
        correction,
        row['grammar_topic'] ?? 'Other',
        _now().toUtc().toIso8601String()
      ]);
      db.execute(
          'UPDATE writing_mistakes SET review_status=?,updated_at=? WHERE id=?',
          [
            correct ? 'understood' : 'open',
            _now().toUtc().toIso8601String(),
            mistakeId
          ]);
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> categories() async =>
      (await database.db).select('''
    SELECT COALESCE(grammar_topic,'Other') category,COUNT(*) total,
      SUM(CASE WHEN review_status='understood' THEN 1 ELSE 0 END) reviewed,
      SUM(CASE WHEN (SELECT COUNT(*) FROM mistake_practice_attempts a WHERE a.mistake_id=m.id AND a.is_correct=0)>=2 THEN 1 ELSE 0 END) repeated
    FROM writing_mistakes m WHERE deleted=0 GROUP BY COALESCE(grammar_topic,'Other') ORDER BY total DESC,category''');

  Future<List<Map<String, dynamic>>> weaknesses() async =>
      (await database.db).select('''
    SELECT COALESCE(m.grammar_topic,'Other') category,COUNT(DISTINCT COALESCE(m.dedup_key,m.id)) records,
      COUNT(a.id) attempts,SUM(CASE WHEN a.is_correct=0 THEN 1 ELSE 0 END) errors
    FROM writing_mistakes m LEFT JOIN mistake_practice_attempts a ON a.mistake_id=m.id AND a.mode='exact'
      AND a.original_snapshot=m.original_sentence AND a.correction_snapshot=m.correction
      AND a.category_snapshot=COALESCE(m.grammar_topic,'Other')
    WHERE m.deleted=0 AND LENGTH(TRIM(COALESCE(m.correction,'')))>0
      AND TRIM(m.original_sentence)!=TRIM(m.correction) GROUP BY m.grammar_topic
    HAVING COUNT(DISTINCT COALESCE(m.dedup_key,m.id))>=3 OR (COUNT(a.id)>=3 AND SUM(CASE WHEN a.is_correct=0 THEN 1 ELSE 0 END)>=2)
    ORDER BY errors DESC,records DESC,category''');

  Future<Map<String, dynamic>> insights() async {
    final db = await database.db;
    final cats = await categories();
    final attempts = db.select(
        '''SELECT a.* FROM mistake_practice_attempts a JOIN writing_mistakes m ON m.id=a.mistake_id
      WHERE m.deleted=0 AND a.mode='exact' ORDER BY a.created_at DESC,a.id DESC LIMIT 10''');
    double rate(List<Map<String, dynamic>> rows) =>
        rows.where((r) => r['is_correct'] == 1).length / rows.length;
    final count = db
        .select(
            "SELECT COUNT(*) n FROM mistake_practice_attempts a JOIN writing_mistakes m ON m.id=a.mistake_id WHERE m.deleted=0 AND a.mode='exact'")
        .single['n'];
    return {
      'categories': cats,
      'attempts': count,
      'trend': attempts.length < 10
          ? null
          : rate(attempts.sublist(0, 5)) - rate(attempts.sublist(5, 10))
    };
  }
}
