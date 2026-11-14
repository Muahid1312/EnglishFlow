# LexiFlow 2.0 — Phase 2 implementation report

Status: code and regression suites are present, but **Phase 2 acceptance is not
complete**. No Flutter tests, analysis or APK build have succeeded in this
instance. Phase 1 Flutter/device verification was already blocked before this
work and remains outstanding. Phase 2 was implemented at the user's explicit
request while preserving that limitation.

## A. Features implemented

- Rich word editing/details, original context/source links, history/status/next
  review date, confirmed removal, bounded prefix search and recent history views.
- Real Android TTS pronunciation with American English preference, engine/voice
  availability checks, stop/overlap handling, completion/error replies, timeout,
  page disposal and Activity resource cleanup. Offline availability is conditional
  on the installed engine/voice data, not claimed as device-verified.
- Persisted 5/10/15/all-due queues, deterministic urgency/failure ordering, reveal,
  pause/resume, durable grading/progress/summary and atomic history advancement.
- Context, Meaning Match and Recall challenges from saved data, with ambiguity
  checks and useful insufficient-data states. No fabricated definitions or SRS
  changes from challenge answers.
- Enhanced Mistake Journal/Coach: manual categories/source, repetitions,
  duplicate guards, writing correction confirmation, short exact/self-assessed
  practice, immutable attempt snapshots and evidence-based recommendations.
- Defined vocabulary/mistake analytics and compact category bars; bounded recent
  history queries avoid loading the full review log for trend calculations.
- Daily Plan integration with real due vocabulary and confirmed mistake-category
  evidence, reusing existing study sessions rather than a second timer.
- Schema-7 Phase 1 backup validation/staged upgrade and schema-8 snapshot coverage.

These describe implemented code paths, not claims of successful runtime/device
verification. `LEARNING_INTELLIGENCE.md` documents algorithms and metric formulas.

## B. Existing functionality preserved

The canonical vocabulary table, normalized-word uniqueness, original context,
existing SRS algorithm, due comparisons and append-only review history remain.
No valid prior learning schedule is reset. Reading, Daily Plan, Backup & Restore,
listening/speaking, writing drafts/revisions, books, AI transport/secure key storage,
certificates and existing study-session/day accounting are retained. Integration
points were extended; unrelated modules were not redesigned. Preservation is
supported by code inspection and added fixtures, not a claim that the unrun full
regression suite passed.

## C. Database changes and files

Schema **7 → 8** is additive and transactional. It adds:

- `usage_example`, `collocations`, `pronunciation`, `personal_notes` to existing
  vocabulary records; existing part-of-speech/context fields are reused.
- `vocabulary_practice_sessions` / `vocabulary_practice_items` for queue state,
  stable review IDs, reveal/progress and expected SRS revision counts.
- Source label, deletion flag, revision and normalized correction fingerprint on
  existing mistakes. Legacy duplicate mistakes remain; new accidental duplicates
  are rejected. Removed words/mistakes are hidden while retaining histories.
- `mistake_practice_attempts`, including assessment mode and immutable snapshots.
- Due-date, word-search, review-history, mistake category/dedup/attempt indexes.

App version metadata is **2.0.0+8**. No dependency version upgrade or new TTS
package is introduced.

Phase 2 changes:

- `lib/core/database/app_database.dart`
- `lib/core/services/vocabulary_intelligence.dart`, `mistake_coach.dart`,
  `practice_timer.dart`, `pronunciation_service.dart`, `daily_plan_service.dart`
- `lib/features/vocabulary/vocabulary_screen.dart`, `word_editor.dart`,
  `word_detail_screen.dart`, `vocabulary_challenge_screen.dart`
- `lib/features/mistake_coach/mistake_practice_screen.dart`
- `lib/features/grammar_writing/writing/writing_history_screens.dart`,
  `writing_studio_screen.dart`
- `lib/app/router/app_router.dart`, `lib/core/backup/backup_service.dart`
- Android `MainActivity.kt` and `AndroidManifest.xml`, plus `pubspec.yaml`
- `test/vocabulary_intelligence_v2_test.dart`, `mistake_coach_v2_test.dart`,
  `phase2_backup_compatibility_test.dart`, `phase2_intelligence_widget_test.dart`
- This report, `LEARNING_INTELLIGENCE.md`, and backup compatibility documentation.

Earlier Phase 1 edits remain in the working tree and are not silently discarded.

## D. Exact validation results

Passed limited checks in this instance:

- Tree-sitter syntax parsing of the Dart source/tests (not Dart compilation).
- Android manifest XML parsing.
- Actual v6/v7/v8 migration DDL executed against the checked-in v5 fixture in
  SQLite. Existing learner, word and correction data remained; foreign keys and
  SQLite integrity checks passed. This does **not** execute Dart callbacks such
  as dedup-key backfill; those are covered by written, currently unrun tests.
- Feature SQL preparation against schema 8 and execution of escaped prefix-search
  behavior. See `/workspace/phase2-validation/sql.log` for the current count.
- `git diff --check`.

Required commands were attempted and each exited **127** before its runner could
start, because the executables are absent:

| Command | Result |
|---|---|
| `dart format lib test` | Blocked: `dart: command not found` |
| `flutter analyze` | Blocked: `flutter: command not found` |
| Targeted four new test files | Blocked: `flutter: command not found` |
| `flutter test` | Blocked: `flutter: command not found` |
| `flutter build apk --debug` | Blocked: `flutter: command not found` |

**Executed Flutter tests: none. Passed Flutter tests: not established.** The
written tests cover CRUD, context/metadata preservation, duplicate prevention,
all ratings, due boundaries, repeated failures, urgency, queue persistence,
exactly-once reviews, stale/deleted cards, challenge ambiguity/matching, legacy
review metrics, mistake source/duplicates/revisions/deletion, exact versus self
assessment, case-sensitive corrections, evidence thresholds, Daily Plan timing,
schema-7 backup upgrade, schema-8 data/queue roundtrip and UI adapter/confirmation
flows. TTS widget tests mock the channel and do not verify an Android voice.

**APK: not produced.** Expected path after a successful build:
`build/app/outputs/flutter-apk/app-debug.apk`.

## E. Remaining problems and verification limitations

The active network policy still rejects Flutter release/engine downloads from
`storage.googleapis.com` with HTTP 403. Flutter 3.24.5 / Dart 3.5.4 are absent.
The saved domain grant must reach the running environment before installation
can resume. No TLS/checksum verification or network-policy restriction was
bypassed. Android SDK packages were installed during Phase 1 setup, but that does
not establish Flutter build readiness.

After access is fixed: install the SDK, run formatting, analyze, run the four
new targeted suites, run the full suite (including Phase 1), then build one debug
APK. Fix any revealed compiler/test failures before release. Native TTS and
English voice availability, offline synthesis, document-picker backup roundtrip,
RTL/narrow-layout accessibility, and Android lifecycle/audio interactions still
need actual device/emulator validation.

A shared/manual or recovered study timer stays paused when a routine ends and
must be finished through the existing study controls to enter completed-day
minutes. This avoids silently ending a broader planned study activity. Challenge
answers do not masquerade as SRS ratings; open rewrites use explicit self-report.
Backup size/storage/encryption/retained-media limitations remain documented in
`BACKUP_FORMAT.md`.

## F. Phase 3 readiness

**Not cleared.** Phase 1 and Phase 2 Flutter analysis/tests, debug APK generation,
and Android verification are unresolved. No Listening/AI Conversation Phase 3
implementation was started. This report does not claim the app is bug-free.
