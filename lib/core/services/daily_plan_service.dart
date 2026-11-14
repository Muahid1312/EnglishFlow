import 'dart:convert';
import 'dart:io';

import '../database/app_database.dart';
import '../utils/date_utils.dart';
import '../utils/id_utils.dart';
import 'study_session_service.dart';
import 'mistake_coach.dart';
import 'ai_teacher_service.dart';
import 'builtin_content_service.dart';

class DailyPlanService {
  DailyPlanService(this.database, this.sessions, {DateTime Function()? now,this.ai})
      : _now = now ?? DateTime.now;
  final AppDatabase database;
  final StudySessionService sessions;
  final AiTeacherService? ai;
  final DateTime Function() _now;
  bool _transitioning = false;
  Future<void> _planning = Future.value();

  static int compatibleGoal(int goal) => [15, 30, 60].contains(goal) ? goal : 30;

  Future<List<Map<String, dynamic>>> today({int? goal}) {
    final result = _planning.then((_) => _today(goal: goal));
    _planning = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<List<Map<String, dynamic>>> _today({int? goal}) async {
    final db = await database.db;
    final at = _now();
    final date = localDateString(at);
    final prefs = await database.getPreferences();
    final minutes = goal ?? compatibleGoal(prefs.dailyTargetMinutes);
    if (![15, 30, 60].contains(minutes)) throw ArgumentError('Choose 15, 30 or 60 minutes.');
    final existing = db.select('SELECT * FROM daily_plans WHERE local_date=?', [date]);
    if (existing.isEmpty || (goal != null && existing.single['goal_minutes'] != goal)) {
      final candidates = await _candidates();
      db.execute('BEGIN IMMEDIATE');
      try {
        if (existing.isEmpty) {
          db.execute('INSERT INTO daily_plans VALUES(?,?,?,?)',
              [date, minutes, at.toUtc().toIso8601String(), at.timeZoneOffset.inMinutes]);
        } else {
          db.execute('UPDATE daily_plans SET goal_minutes=? WHERE local_date=?', [minutes, date]);
          // Keep all practiced, completed and explicitly skipped records. Only
          // untouched recommendations are superseded by a changed goal.
          db.execute('''DELETE FROM planned_activities WHERE local_date=? AND state='pending'
            AND id NOT IN (SELECT activity_id FROM plan_sessions)''', [date]);
        }
        final kept = db.select('SELECT * FROM planned_activities WHERE local_date=?', [date]);
        final reserved = kept.fold<int>(0, (sum, r) => sum + (r['minutes'] as int));
        var remaining = (minutes - reserved).clamp(0, minutes).toInt();
        final groups = kept.map((r) => r['module']).toSet();
        final available = candidates.where((c) => !groups.contains(c.module)).toList();
        // At most three activities for 15 minutes, four for longer plans.
        final slots = (minutes == 15 ? 3 : 4) - kept.length;
        final selected = available.take(slots.clamp(0, 4).toInt()).toList();
        if (selected.isNotEmpty && remaining > 0) {
          final defaults = minutes == 15 ? [5,5,5,0] : minutes == 30 ? [10,7,8,5] : [18,12,18,12];
          final weights = selected.map((c) => (defaults[c.group]==0 ? 5 : defaults[c.group]) + c.boost).toList();
          final weightSum = weights.fold<int>(0, (a,b) => a+b);
          var budget = remaining;
          for (var i = 0; i < selected.length && budget > 0; i++) {
            final c = selected[i];
            final amount = i == selected.length - 1 ? budget :
                (remaining * weights[i] ~/ weightSum).clamp(1, budget).toInt();
            budget -= amount;
            db.execute('''INSERT INTO planned_activities
              (id,local_date,position,module,title,route,reason,minutes,created_at)
              VALUES(?,?,?,?,?,?,?,?,?)''', [newId(), date, kept.length+i, c.module,
                c.title,c.route,c.reason,amount,at.toUtc().toIso8601String()]);
          }
        }
        if (selected.isEmpty && remaining>0) {
          final unfinished = kept.where((r) => !['completed','skipped'].contains(r['state'])).toList();
          if (unfinished.isNotEmpty) {
            db.execute('UPDATE planned_activities SET minutes=minutes+? WHERE id=?',
                [remaining,unfinished.first['id']]);
          }
        }
        if (goal != null || ![15,30,60].contains(prefs.dailyTargetMinutes)) {
          final targets = minutes==15 ? [5,5,5,0] : minutes==30 ? [10,7,8,5] : [18,12,18,12];
          db.execute('UPDATE user_preferences SET daily_target_minutes=?,reading_minutes=?,vocabulary_minutes=?,listening_speaking_minutes=?,grammar_writing_minutes=?', [minutes,...targets]);
        }
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
    return activities(date);
  }

  Future<List<Map<String, dynamic>>> activities(String date) async => (await database.db).select('''
    SELECT a.*,COALESCE((SELECT SUM(d.duration_ms) FROM plan_sessions p
      JOIN study_session_days d ON d.session_id=p.session_id WHERE p.activity_id=a.id),0) AS actual_ms
    FROM planned_activities a WHERE a.local_date=? ORDER BY position,id''', [date]);

  Future<List<Map<String, dynamic>>> history() async => (await database.db).select(
      'SELECT * FROM daily_plans ORDER BY local_date DESC LIMIT 90');

  Future<List<_Candidate>> _candidates() async {
    final db = await database.db;
    final result = <_Candidate>[];
    int count(String sql, [List<Object?> args = const []]) => db.select(sql,args).single.values.single as int;
    final due = (await database.getDueVocabulary(now: _now())).length;
    final recent = db.select('''SELECT module,MAX(started_at) AS last_at FROM study_sessions
      WHERE duration_seconds>0 GROUP BY module''');
    String last(String module) {
      final matching = recent.where((r) => r['module']==module);
      return matching.isEmpty ? '' : matching.first['last_at'] as String;
    }
    int neglect(String module) {
      final previous = DateTime.tryParse(last(module));
      return previous!=null && _now().difference(previous).inDays>=7 ? 1 : 0;
    }
    final preferences = db.select('SELECT learning_priorities FROM user_preferences LIMIT 1').single;
    final priorities = jsonDecode(preferences['learning_priorities'] as String) as List;
    int boost(String module) => priorities.any((p) => p.toString().toLowerCase().contains(module.split('_').first)) ? 2 : 0;
    final articles = db.select('SELECT * FROM reading_articles ORDER BY updated_at,id LIMIT 1');
    final books = db.select('''SELECT b.*,l.title AS lesson_title FROM imported_books b
      JOIN book_lessons l ON l.book_id=b.id WHERE l.completed=0 ORDER BY b.updated_at,l.order_index,l.id''')
        .where((r) => File(r['file_path'] as String).existsSync()).toList();
    final courseLessons=db.select('''SELECT l.id,l.title FROM lessons l JOIN courses c ON c.id=l.course_id
      WHERE c.structured_mode=1 AND c.deleted=0 AND c.is_active=1
      AND (NOT EXISTS(SELECT 1 FROM course_activities a WHERE a.lesson_id=l.id)
        OR EXISTS(SELECT 1 FROM course_activities a LEFT JOIN course_activity_evidence e ON e.activity_id=a.id WHERE a.lesson_id=l.id AND e.activity_id IS NULL))
      ORDER BY l.last_studied_at DESC,c.created_at,l.order_index,l.id LIMIT 1''');
    if(courseLessons.isNotEmpty) {
      final l=courseLessons.single;
      result.add(_Candidate(0,'reading','Study ${l['title']}','/learn/courses/lesson/${l['id']}',
        'Next saved course lesson with unfinished activity evidence.',boost('reading')+2));
    } else if (books.isNotEmpty) {
      final b = books.first;
      result.add(_Candidate(0,'reading','Continue ${b['title']}',
        '/learn/books/${Uri.encodeComponent(b['id'] as String)}/read',
        'Unfinished book lesson: ${b['lesson_title']}', boost('reading')+neglect('reading')));
    } else if (articles.isNotEmpty) {
      final a = articles.single;
      result.add(_Candidate(0,'reading',a['title'] as String,
          '/learn/reading/${Uri.encodeComponent(a['id'] as String)}',
          last('reading').isEmpty ? 'Continue a saved article; no reading time has been tracked yet.' : 'Revisit an older saved article to keep reading active.',boost('reading')+neglect('reading')));
    }
    if(!result.any((c)=>c.module=='reading')) {
      final prefs=await database.getPreferences();
      final article=await BuiltinContentService(database).nextArticle(prefs.englishLevel=='B2'?'B2':'B1');
      if(article!=null)result.add(_Candidate(0,'reading','Read ${article['title']} + 4 questions',
        '/learn/reading/${Uri.encodeComponent('builtin:${article['id']}')}',
        'Unread offline article at your selected curriculum target. Opening does not complete it.',boost('reading')));
    }
    if (due>0 || count('SELECT COUNT(*) FROM vocabulary_entries WHERE is_saved=1 AND duplicate_of IS NULL')>0) {
      result.add(_Candidate(1,'vocabulary',due>0 ? 'Review $due due words' : 'Practice saved vocabulary',
        '/learn/vocabulary',due>0 ? 'These cards are due now; review them before adding more.' : 'Revisit your own saved words.',due>0 ? 2 : boost('vocabulary')));
    }
    if(!result.any((c)=>c.module=='vocabulary')) {
      final prefs=await database.getPreferences();
      final words=await BuiltinContentService(database).recommendedWords(level:prefs.englishLevel,count:10);
      if(words.isNotEmpty)result.add(_Candidate(1,'vocabulary','Learn ${words.length} built-in words','/learn/vocabulary/library?daily=true',
        'A saved daily selection of real unsaved words. Save only the cards you want to review.',boost('vocabulary')));
    }
    final listening = db.select('SELECT * FROM listening_lessons ORDER BY updated_at,id')
        .where((r) => File(r['audio_path'] as String).existsSync()).toList();
    final prompts = count('SELECT COUNT(*) FROM speaking_prompts');
    final recordings = count('SELECT COUNT(*) FROM speaking_recordings');
    final speakingLast = db.select("SELECT MAX(created_at) AS at FROM speaking_recordings").single['at'] as String?;
    final listeningLast = db.select('SELECT MAX(updated_at) AS at FROM listening_lessons WHERE last_position_ms>0').single['at'] as String?;
    int timestamp(String? value) => value==null ? 0 : DateTime.tryParse(value)?.millisecondsSinceEpoch ?? 0;
    if (listening.isNotEmpty && (prompts==0 || timestamp(listeningLast)<=timestamp(speakingLast))) {
      final l = listening.first;
      final bookmarks=db.select('SELECT position_ms FROM playback_bookmarks WHERE lesson_id=? ORDER BY created_at DESC,id LIMIT 1',[l['id']]);
      result.add(_Candidate(2,'listening_speaking','Listen: ${l['title']}',
        '/learn/listening/player/${Uri.encodeComponent(l['id'] as String)}${bookmarks.isEmpty?'':'?startMs=${bookmarks.single['position_ms']}'}',
        bookmarks.isEmpty?'Continue imported audio at ${(l['last_position_ms'] as int)~/1000} seconds.':'Practice a real bookmarked difficult section; use A–B repeat or Shadowing from the player.', boost('listening')));
    } else if (prompts>0) {
      result.add(_Candidate(2,'listening_speaking','Speaking practice','/learn/listening/speaking',
        'Use a saved speaking prompt; $recordings recordings so far.',boost('speaking')));
    } else if(listening.isEmpty && ai!=null) {
      try {
        final history=db.select('SELECT title FROM ai_conversations WHERE is_active=1 ORDER BY started_at DESC,rowid DESC LIMIT 1');
        if(history.isNotEmpty && (await ai!.checkStatus()).isReady) {
          result.add(_Candidate(2,'listening_speaking','Continue ${history.single['title'] ?? 'saved conversation'}',
            '/learn/listening/ai','Practice your saved scenario. A configured provider and internet are required; connection is not assumed.',boost('speaking')));
        }
      } catch(_){/* Optional AI availability must not block the offline plan. */}
    }
    final grammar = db.select('''SELECT l.*,COUNT(a.id) attempts,
      SUM(CASE WHEN a.is_correct=0 AND a.self_assessed=0 THEN 1 ELSE 0 END) errors
      FROM grammar_lessons l JOIN grammar_exercises e ON e.lesson_id=l.id
      LEFT JOIN grammar_attempts a ON a.exercise_id=e.id
      GROUP BY l.id ORDER BY errors DESC,l.completed,l.order_index,l.id LIMIT 1''');
    final writing = db.select('SELECT * FROM writing_entries ORDER BY updated_at,id LIMIT 1');
    final weaknesses=await MistakeCoach(database).weaknesses();
    if(weaknesses.isNotEmpty) {
      final weak=weaknesses.first;
      result.add(_Candidate(3,'grammar_writing','Practice saved ${weak['category']} corrections',
        '/learn/grammar/mistakes/practice?category=${Uri.encodeQueryComponent(weak['category'] as String? ?? 'Other')}',
        '${weak['records']} saved records and ${weak['errors'] ?? 0} recorded wording mismatches support this recommendation.',2+boost('grammar')));
    } else if (grammar.isNotEmpty && ((grammar.single['errors'] as int)>0 || writing.isEmpty || last('grammar_writing').isEmpty)) {
      final g = grammar.single;
      result.add(_Candidate(3,'grammar_writing','Grammar: ${g['title']}',
        '/learn/grammar/lesson/${Uri.encodeComponent(g['id'] as String)}',
        (g['errors'] as int)>0 ? 'Practice a lesson with incorrect answers in your history.' : 'Continue an existing grammar lesson.',boost('grammar')+((g['errors'] as int)>0 ? 2 : 0)));
    } else {
      result.add(_Candidate(3,'grammar_writing',writing.isEmpty ? 'Write a short journal entry' : 'Continue ${writing.single['title']}',
        writing.isEmpty ? '/learn/grammar/writing' : '/learn/grammar/writing/${Uri.encodeComponent(writing.single['id'] as String)}',
        writing.isEmpty ? 'Create your own text offline. Import reading and audio to add variety.' : 'Continue your least recently edited writing draft.',boost('writing')));
    }
    // Due cards lead the plan but weights retain the baseline balance. Other
    // groups remain stable, deterministic and easy to explain.
    if (due>0) result.sort((a,b) => (a.group==1 ? -1 : a.group).compareTo(b.group==1 ? -1 : b.group));
    return result;
  }

  Future<void> _transition(Future<void> Function() action) async {
    if (_transitioning) throw StateError('A plan action is already running.');
    _transitioning = true;
    try { await action(); } finally { _transitioning = false; }
  }

  Future<void> start(String id) => _transition(() async {
    final db = await database.db;
    final row = db.select('SELECT * FROM planned_activities WHERE id=?',[id]).single;
    if (row['local_date']!=localDateString(_now())) throw StateError('Open today’s plan to start an activity.');
    if (['completed','skipped'].contains(row['state'])) throw StateError('This activity is already finished.');
    await sessions.recoverInterrupted();
    final active = sessions.active;
    final linked = active==null ? [] : db.select('SELECT activity_id FROM plan_sessions WHERE session_id=?',[active.id]);
    if (active != null && linked.isNotEmpty && linked.single['activity_id']==id) {
      sessions.resume();
    } else {
      final started = await sessions.start(row['module'] as String);
      db.execute('INSERT INTO plan_sessions VALUES(?,?)',[started.id,id]);
    }
    db.execute("UPDATE planned_activities SET state='active' WHERE id=?",[id]);
  });

  Future<void> complete(String id, {bool skip = false}) => _transition(() async {
    final db = await database.db;
    final row = db.select('SELECT * FROM planned_activities WHERE id=?',[id]).single;
    if (['completed','skipped'].contains(row['state'])) return;
    await sessions.recoverInterrupted();
    final active = sessions.active;
    if (active != null && db.select('SELECT session_id FROM plan_sessions WHERE activity_id=? AND session_id=?',[id,active.id]).isNotEmpty) {
      await sessions.finish(interrupted:skip);
    }
    final seconds = db.select('''SELECT COALESCE(SUM(s.duration_seconds),0) n FROM plan_sessions p
      JOIN study_sessions s ON p.session_id=s.id WHERE p.activity_id=?''',[id]).single['n'] as int;
    if (!skip && seconds==0) throw StateError('Study this activity before marking it finished.');
    db.execute('UPDATE planned_activities SET state=? WHERE id=?',[skip?'skipped':'completed',id]);
  });
}

class _Candidate {
  const _Candidate(this.group,this.module,this.title,this.route,this.reason,this.boost);
  final int group;
  final String module,title,route,reason;
  final int boost;
}
