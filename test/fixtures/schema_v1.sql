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
INSERT INTO user_preferences DEFAULT VALUES;
PRAGMA user_version=1;
