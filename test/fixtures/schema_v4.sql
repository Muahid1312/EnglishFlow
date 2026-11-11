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
CREATE TABLE IF NOT EXISTS daily_goals (
          local_date TEXT PRIMARY KEY,
          target_minutes INTEGER NOT NULL,
          completed_minutes INTEGER NOT NULL DEFAULT 0,
          goal_met INTEGER NOT NULL DEFAULT 0,
          updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
CREATE TABLE IF NOT EXISTS learning_activities (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          module TEXT,
          metadata TEXT,
          local_date TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
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
CREATE TABLE IF NOT EXISTS ai_conversations (
          id TEXT PRIMARY KEY,
          provider TEXT,
          title TEXT,
          message_count INTEGER NOT NULL DEFAULT 0,
          started_at TEXT NOT NULL,
          last_message_at TEXT,
          is_active INTEGER NOT NULL DEFAULT 1
        );
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
CREATE TABLE IF NOT EXISTS playback_bookmarks (
          id TEXT PRIMARY KEY,
          lesson_id TEXT NOT NULL,
          position_ms INTEGER NOT NULL,
          label TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (lesson_id) REFERENCES listening_lessons(id) ON DELETE CASCADE
        );
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
CREATE TABLE IF NOT EXISTS ai_messages (
          id TEXT PRIMARY KEY,
          conversation_id TEXT NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (conversation_id) REFERENCES ai_conversations(id) ON DELETE CASCADE
        );
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
CREATE TABLE IF NOT EXISTS writing_revisions (
          id TEXT PRIMARY KEY,
          entry_id TEXT NOT NULL,
          body TEXT NOT NULL,
          word_count INTEGER NOT NULL DEFAULT 0,
          label TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (entry_id) REFERENCES writing_entries(id) ON DELETE CASCADE
        );
CREATE TABLE IF NOT EXISTS writing_feedback (
          id TEXT PRIMARY KEY,
          entry_id TEXT NOT NULL,
          source TEXT NOT NULL DEFAULT 'ai',
          content TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (entry_id) REFERENCES writing_entries(id) ON DELETE CASCADE
        );
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
CREATE TABLE IF NOT EXISTS imported_books (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          file_path TEXT NOT NULL,
          page_count INTEGER NOT NULL DEFAULT 0,
          current_page INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
CREATE TABLE IF NOT EXISTS book_units (
          id TEXT PRIMARY KEY,
          book_id TEXT NOT NULL,
          title TEXT NOT NULL,
          order_index INTEGER NOT NULL DEFAULT 0,
          completed INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (book_id) REFERENCES imported_books(id) ON DELETE CASCADE
        );
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
CREATE TABLE IF NOT EXISTS book_bookmarks (
          id TEXT PRIMARY KEY,
          book_id TEXT NOT NULL,
          page INTEGER NOT NULL,
          label TEXT,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (book_id) REFERENCES imported_books(id) ON DELETE CASCADE
        );
CREATE TABLE IF NOT EXISTS assessment_definitions (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          category TEXT NOT NULL,
          description TEXT,
          time_limit_seconds INTEGER,
          pass_threshold REAL NOT NULL DEFAULT 0.7,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
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
INSERT INTO user_preferences DEFAULT VALUES;
PRAGMA user_version=4;
