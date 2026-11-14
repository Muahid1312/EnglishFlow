import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import '../database/app_database.dart';
import '../utils/id_utils.dart';
import 'assessment_grading.dart';

/// Structured courses extend the original course/lesson records. Materials and
/// historical certificates are never deleted when a course is removed.
class CourseStudyService {
  CourseStudyService(this.database);
  final AppDatabase database;

  Future<String> saveCourse(
      {String? id,
      required String title,
      String description = '',
      String level = 'B1',
      String? bookId,
      double? minimumScore}) async {
    if (title.trim().isEmpty) throw ArgumentError('A title is required.');
    if (minimumScore != null &&
        (!minimumScore.isFinite || minimumScore < 0 || minimumScore > 1)) {
      throw ArgumentError('Minimum score must be between 0 and 1.');
    }
    final d = await database.db;
    if (bookId != null) {
      final books = d
          .select('SELECT page_count FROM imported_books WHERE id=?', [bookId]);
      if (books.isEmpty) throw ArgumentError('The linked PDF does not exist.');
      if (id != null &&
          d.select('SELECT id FROM lessons WHERE course_id=? AND page_end>?',
              [id, books.first['page_count']]).isNotEmpty) {
        throw ArgumentError('Existing lesson page ranges exceed this PDF.');
      }
    } else if (id != null &&
        d.select(
            'SELECT id FROM lessons WHERE course_id=? AND page_start IS NOT NULL',
            [id]).isNotEmpty) {
      throw ArgumentError(
          'Remove lesson page ranges before unlinking the PDF.');
    }
    final key = id ?? newId();
    if (id == null) {
      d.execute(
          'INSERT INTO courses(id,title,description,level,book_id,structured_mode,minimum_score) VALUES(?,?,?,?,?,1,?)',
          [key, title.trim(), description, level, bookId, minimumScore ?? 0.7]);
    } else {
      d.execute(
          'UPDATE courses SET title=?,description=?,level=?,book_id=?,minimum_score=COALESCE(?,minimum_score) WHERE id=?',
          [title.trim(), description, level, bookId, minimumScore, id]);
    }
    return key;
  }

  Future<String> saveUnit(String courseId, String title, {String? id}) async {
    if (title.trim().isEmpty) throw ArgumentError('A title is required.');
    final d = await database.db;
    final key = id ?? newId();
    if (id == null) {
      d.execute(
          'INSERT INTO course_units(id,course_id,title,order_index) VALUES(?,?,?,(SELECT COALESCE(MAX(order_index),-1)+1 FROM course_units WHERE course_id=?))',
          [key, courseId, title.trim(), courseId]);
    } else {
      d.execute('UPDATE course_units SET title=? WHERE id=? AND course_id=?',
          [title.trim(), id, courseId]);
    }
    return key;
  }

  Future<String> saveLesson(String courseId, String unitId, String title,
      {String? id,
      String objective = '',
      String notes = '',
      int? start,
      int? end}) async {
    final d = await database.db;
    if (title.trim().isEmpty ||
        d.select('SELECT id FROM course_units WHERE id=? AND course_id=?',
            [unitId, courseId]).isEmpty) {
      throw ArgumentError('Choose a unit and title.');
    }
    final books = d.select(
        'SELECT b.page_count FROM courses c JOIN imported_books b ON b.id=c.book_id WHERE c.id=?',
        [courseId]);
    final validRange = (start == null && end == null) ||
        (start != null &&
            end != null &&
            start >= 1 &&
            end >= start &&
            books.isNotEmpty &&
            end <= (books.first['page_count'] as int));
    if (!validRange) {
      throw ArgumentError('Page range must be inside the linked PDF.');
    }
    final key = id ?? newId();
    if (id == null) {
      d.execute(
          'INSERT INTO lessons(id,course_id,unit_id,title,objective,notes,page_start,page_end,order_index) VALUES(?,?,?,?,?,?,?,?,(SELECT COALESCE(MAX(order_index),-1)+1 FROM lessons WHERE unit_id=?))',
          [
            key,
            courseId,
            unitId,
            title.trim(),
            objective,
            notes,
            start,
            end,
            unitId
          ]);
    } else {
      d.execute(
          'UPDATE lessons SET title=?,objective=?,notes=?,page_start=?,page_end=? WHERE id=? AND course_id=? AND unit_id=?',
          [title.trim(), objective, notes, start, end, id, courseId, unitId]);
    }
    return key;
  }

  Future<void> moveLesson(String id, int direction) async {
    final d = await database.db;
    final l = d.select('SELECT * FROM lessons WHERE id=?', [id]).single;
    final rows = d.select(
        'SELECT id FROM lessons WHERE unit_id=? ORDER BY order_index,id',
        [l['unit_id']]);
    final ids = rows.map((r) => r['id'] as String).toList();
    final from = ids.indexOf(id), to = ids.indexOf(id) + direction;
    if (to < 0 || to >= ids.length) return;
    ids.removeAt(from);
    ids.insert(to, id);
    d.execute('BEGIN IMMEDIATE');
    try {
      for (var i = 0; i < ids.length; i++) {
        d.execute('UPDATE lessons SET order_index=? WHERE id=?', [i, ids[i]]);
      }
      d.execute('COMMIT');
    } catch (_) {
      d.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> moveUnit(String id, int direction) async {
    final d = await database.db;
    final course = d.select('SELECT course_id FROM course_units WHERE id=?',
        [id]).single['course_id'];
    final ids = d
        .select(
            'SELECT id FROM course_units WHERE course_id=? ORDER BY order_index,id',
            [course])
        .map((r) => r['id'] as String)
        .toList();
    final from = ids.indexOf(id), to = ids.indexOf(id) + direction;
    if (to < 0 || to >= ids.length) return;
    ids.removeAt(from);
    ids.insert(to, id);
    d.execute('BEGIN IMMEDIATE');
    try {
      for (var i = 0; i < ids.length; i++) {
        d.execute(
            'UPDATE course_units SET order_index=? WHERE id=?', [i, ids[i]]);
      }
      d.execute('COMMIT');
    } catch (_) {
      d.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> addActivity(String lessonId, String title, String kind,
      {String? route}) async {
    if (title.trim().isEmpty ||
        ![
          'reading',
          'vocabulary',
          'listening',
          'speaking',
          'grammar',
          'writing',
          'assessment'
        ].contains(kind)) {
      throw ArgumentError('Choose an activity title and kind.');
    }
    if (route != null && !route.startsWith('/')) {
      throw ArgumentError('Invalid activity route.');
    }
    (await database.db).execute(
        'INSERT INTO course_activities(id,lesson_id,title,kind,route,order_index) VALUES(?,?,?,?,?,(SELECT COUNT(*) FROM course_activities WHERE lesson_id=?))',
        [newId(), lessonId, title.trim(), kind, route, lessonId]);
  }

  Future<void> completeActivity(String id, bool complete) async {
    final d = await database.db;
    if (d.select('SELECT id FROM course_activities WHERE id=?', [id]).isEmpty) {
      throw StateError('Activity no longer exists.');
    }
    if (complete) {
      final activity = d.select(
          'SELECT kind,route FROM course_activities WHERE id=?', [id]).single;
      if (activity['kind'] == 'assessment') {
        final route = activity['route'] as String? ?? '';
        if (!route.startsWith('/progress/assessments/') ||
            passingScore(
                    d, route.substring('/progress/assessments/'.length), 0) ==
                null) {
          throw StateError(
              'Pass this linked objective assessment first, then verify the activity.');
        }
      }
      d.execute('INSERT OR IGNORE INTO course_activity_evidence VALUES(?,?)',
          [id, DateTime.now().toUtc().toIso8601String()]);
    } else {
      d.execute(
          'DELETE FROM course_activity_evidence WHERE activity_id=?', [id]);
    }
  }

  static Map<String, dynamic> progress(Database d, String id) {
    final lessons =
        d.select('''SELECT l.*,COUNT(a.id) AS total,COUNT(e.activity_id) AS done
      FROM lessons l LEFT JOIN course_activities a ON a.lesson_id=l.id
      LEFT JOIN course_activity_evidence e ON e.activity_id=a.id
      WHERE l.course_id=? GROUP BY l.id ORDER BY l.order_index,l.id''', [id]);
    final legacy = d.select('SELECT structured_mode FROM courses WHERE id=?',
            [id]).single['structured_mode'] ==
        0;
    final completed = legacy
        ? lessons.where((l) => l['completed'] == 1).length
        : lessons
            .where((l) => (l['total'] as int) > 0 && l['done'] == l['total'])
            .length;
    final remaining = lessons.fold<int>(
        0, (sum, l) => sum + (l['total'] as int) - (l['done'] as int));
    final done = lessons.fold<int>(0, (sum, l) => sum + (l['done'] as int));
    final units =
        d.select('SELECT id FROM course_units WHERE course_id=?', [id]);
    final completedUnits = units.where((u) {
      final ls = lessons.where((l) => l['unit_id'] == u['id']).toList();
      return ls.isNotEmpty &&
          ls.every((l) => (l['total'] as int) > 0 && l['done'] == l['total']);
    }).length;
    final last = d.select(
        'SELECT id,title FROM lessons WHERE course_id=? AND last_studied_at IS NOT NULL ORDER BY last_studied_at DESC LIMIT 1',
        [id]);
    return {
      'lessons': lessons.length,
      'completed_lessons': completed,
      'units': units.length,
      'completed_units': completedUnits,
      'remaining': remaining,
      'state': completed == lessons.length && lessons.isNotEmpty
          ? 'Self-reported completion'
          : done == 0 && last.isEmpty
              ? 'Not started'
              : 'In progress',
      'last': last.isEmpty ? null : last.first['title']
    };
  }

  /// Regrade persisted answers; a passed flag or caller-supplied score alone is
  /// never sufficient for structured-course certification.
  static double? passingScore(Database d, String assessmentId, double minimum) {
    final defs = d.select(
        'SELECT * FROM assessment_definitions WHERE id=?', [assessmentId]);
    if (defs.isEmpty) return null;
    final questions = d.select(
        'SELECT * FROM assessment_questions WHERE assessment_id=?',
        [assessmentId]);
    final objective = questions
        .where((q) =>
            q['question_type'] != 'short' && q['question_type'] != 'writing')
        .toList();
    if (objective.isEmpty ||
        objective.any(
            (q) => (q['correct_answer'] as String? ?? '').trim().isEmpty)) {
      return null;
    }
    final threshold = (defs.first['pass_threshold'] as num).toDouble();
    if (!threshold.isFinite ||
        threshold < 0 ||
        threshold > 1 ||
        !minimum.isFinite ||
        minimum < 0 ||
        minimum > 1) return null;
    for (final attempt in d.select(
        'SELECT * FROM assessment_attempts WHERE assessment_id=? AND completed_at IS NOT NULL AND self_assessed=0 ORDER BY completed_at DESC',
        [assessmentId])) {
      try {
        final answers = jsonDecode(attempt['answers_json'] as String) as Map;
        final grade = gradeAssessment(
            questions, answers.map((k, v) => MapEntry(k.toString(), v)),
            writingReviewed: answers['_writing_self_assessed'] == true);
        final score = grade.score;
        if (score == null) continue;
        if (score >= threshold &&
            score >= minimum &&
            attempt['max_score'] == 1 &&
            (attempt['score'] as num?)?.toDouble() == score &&
            attempt['passed'] == 1) return score;
      } catch (_) {
        /* Invalid legacy answers cannot authorize new completion. */
      }
    }
    return null;
  }

  static Map<String, dynamic>? certificateEvidence(Database d, String id) {
    final courses =
        d.select('SELECT * FROM courses WHERE id=? AND deleted=0', [id]);
    if (courses.isEmpty) return null;
    final p = progress(d, id);
    if (p['lessons'] == 0 ||
        p['completed_lessons'] != p['lessons'] ||
        p['units'] == 0 ||
        p['completed_units'] != p['units']) return null;
    for (final activity in d.select(
        "SELECT a.route FROM course_activities a JOIN lessons l ON l.id=a.lesson_id WHERE l.course_id=? AND a.kind='assessment'",
        [id])) {
      final route = activity['route'] as String? ?? '';
      if (!route.startsWith('/progress/assessments/') ||
          passingScore(
                  d, route.substring('/progress/assessments/'.length), 0) ==
              null) return null;
    }
    final required = d.select(
        "SELECT assessment_id FROM completion_requirements WHERE target_type='course' AND target_id=?",
        [id]);
    if (required.isEmpty) return null;
    final scores = <double>[];
    for (final r in required) {
      final score = passingScore(d, r['assessment_id'] as String,
          (courses.first['minimum_score'] as num).toDouble());
      if (score == null) return null;
      scores.add(score);
    }
    return {
      'title': courses.first['title'],
      'score': scores.reduce((a, b) => a + b) / scores.length,
      'verification_type': 'self_reported_activities_and_assessments'
    };
  }
}
