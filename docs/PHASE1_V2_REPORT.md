# LexiFlow 2.0, Phase 1 implementation and validation

Status: implementation present; **not release-ready or cleared for Phase 2**.
Flutter validation and the requested debug APK remain blocked by SDK access.
No real user database was used for destructive validation.

## Features

- Settings → Backup & Restore: consistent SQLite snapshot, referenced book/audio/
  recording files, versioned manifest, CRC/SHA-256 checks, strict bounded ZIP
  extraction, Android document save with destination readback, explicit restore
  confirmation, staging, previous-database recovery, and app-state reload.
- Home → Daily learning plan: persisted 15/30/60-minute goals, deterministic local
  recommendations, reasons, estimates, actual tracked time, completed/skipped
  states, history, and navigation to existing learning screens.
- Recommendations inspect due reviews, saved articles, unfinished book lessons,
  available audio, speaking prompts/recording history, grammar errors, writing
  drafts, recent sessions and learning priorities. Missing media is never
  presented as playable. An empty installation offers real offline writing
  creation and explains importing material for variety.
- Initial allocations are 5/5/5 for 15 minutes, 10/7/8/5 for 30 minutes and
  18/12/18/12 for 60 minutes. Missing groups redistribute their time to real
  alternatives; due reviews and weaknesses can alter weights. A short plan has
  at most three new activities. Existing records survive goal changes; preserved
  work can exceed a reduced goal rather than being deleted.
- Uses the existing StudySessionService, including cumulative checkpoints,
  background pause, midnight day splits, AI-wait exclusion and idempotent finish.
  Each session belongs to at most one planned activity. Returning from an
  activity pauses it. The persistent session dock supports pause/resume/finish;
  pointer interaction and focused text edits reset a two-minute inactivity pause.
  Reading without interaction for two minutes therefore requires an explicit
  resume, a deliberate conservative timing tradeoff.
- Calendar-date keys and creation-time UTC offsets preserve previous plan
  identities. Revisiting a date does not regenerate its completed plan. Per-task
  tracked time is the lifetime total for its linked sessions; the daily summary
  uses the existing completed-session totals for that local calendar day.

## Database migration

Schema 6 → 7 adds `daily_plans`, `planned_activities`, `plan_sessions`,
`backup_metadata`, and an activity-date index. Existing
`user_preferences.daily_target_minutes` is reused for the duration preference.
Migration runs in the existing transaction; no table resets or destructive
rebuilds are introduced. Newer, unsupported database versions are rejected.

## Files

- `lib/core/backup/backup_zip.dart`: strict streaming ZIP profile.
- `lib/core/backup/backup_service.dart`: snapshot/export/restore/recovery.
- `lib/core/services/daily_plan_service.dart`: planning, persistence, session links.
- `lib/core/services/maintenance_controller.dart`: disposal before restore.
- `lib/core/widgets/study_session_dock.dart`: persistent timing controls.
- `lib/features/backup/backup_screen.dart`: backup and recovery UI.
- `lib/features/daily_plan/daily_plan_screen.dart`: daily plan and history UI.
- `lib/core/database/app_database.dart`: additive migration, WAL-safe snapshot,
  crash recovery and retired-handle protection.
- `lib/core/services/providers.dart`, `lib/app/app.dart`,
  `lib/app/router/app_router.dart`, `lib/main.dart`: lifecycle/provider/navigation
  integration and post-restore reload.
- `lib/features/settings/settings_screen.dart`,
  `lib/features/dashboard/dashboard_screen.dart`: feature entry points.
- `android/app/src/main/kotlin/com/lexiflow/lexiflow/MainActivity.kt`: available
  storage and verified system document save. Existing PDF extraction remains.
- `pubspec.yaml` / `pubspec.lock`: promote existing pinned crypto 3.0.8 from a
  transitive to a direct dependency; no dependency version upgrade. App version
  metadata advances from 1.0.1+6 to 2.0.0+7.
- `test/backup_v2_test.dart`, `test/daily_plan_v2_test.dart`,
  `test/phase1_v2_widget_test.dart`: new temporary-fixture service/UI suites.
- `test/database_regression_test.dart`, `test/phase2_data_test.dart`: update
  expected schema version to `AppDatabase.schemaVersion`.
- `docs/BACKUP_FORMAT.md`: versioned format and recovery contract.

## Validation evidence

Passed in this instance:

- Dart syntax parsing for application code and the three new test files, using
  tree-sitter. This is not Dart analysis or compilation.
- Actual additive v6/v7 SQL executed against the checked-in v5 fixture in SQLite:
  learner/article data preserved, schema 7 present, foreign keys valid, and
  unsupported daily duration rejected.
- 42 literal plan/backup SQL statements prepared against the migrated fixture.
- `git diff --check`.

Not yet run successfully:

- `dart format` (Dart SDK unavailable).
- `flutter analyze` (Flutter SDK unavailable).
- Targeted and complete `flutter test` suites (Flutter SDK unavailable).
- `flutter build apk --debug` (Flutter SDK unavailable; no APK produced).
- Android device tests for document provider roundtrips, real audio, permissions,
  lifecycle/process termination, and visual accessibility/RTL rendering.

Tests added cover export/restore data/media preservation, WAL consistency,
missing files, storage errors, interrupted exports, CRC/SHA failures, unsafe ZIP
metadata/paths, unsupported formats, untrusted SQLite triggers, rollback at
multiple failure points, recovery on restart, duration choices, real-content
selection, due/weak-skill recommendations, concurrent plan generation,
persistence, goal changes, skip/completion, paused restart, midnight/history,
session accounting, dashboard totals, legacy migrations, actual article
navigation, narrow RTL layout, and editor disposal before replacement. These
are written tests, not claimed passing results.

## Remaining blocker and next validation

The active cloud instance still rejects CONNECT/downloads from
`storage.googleapis.com` with HTTP 403. Flutter 3.24.5 / Dart 3.5.4 downloads
cannot begin. The saved domain addition must reach the running environment, then
installation must be retried. No TLS/checksum validation has been disabled and no
network-policy bypass is used.

Android command-line tools 12.0, platform 35, build tools 35.0.0, platform tools,
and NDK 26.1.10909125 were installed successfully. SDK Manager works with its
cache under `/workspace/.android` and the inherited proxy configured through its
supported flags. The installation/start instructions were saved in the cloud
configuration draft; this does not publish or apply the draft. Android device
commands remain unverified: the installed adb attempts to create
`/home/agent/.android`, which is read-only in this instance even with Android's
workspace cache variables set. APK generation itself has not been reached.

After SDK access is fixed, use Flutter 3.24.5 and a compatible Android toolchain:

```sh
export PATH="/workspace/.tools/flutter/bin:$PATH"
export PUB_CACHE=/workspace/.pub-cache
export ANDROID_HOME=/workspace/.tools/android-sdk
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_USER_HOME=/workspace/.android
export ANDROID_SDK_HOME=/workspace
export GRADLE_USER_HOME=/workspace/.gradle
cd /workspace/EnglishFlow
flutter pub get --enforce-lockfile
dart format lib test
flutter analyze
flutter test test/backup_v2_test.dart test/daily_plan_v2_test.dart test/phase1_v2_widget_test.dart
flutter test
flutter build apk --debug
```

Expected APK location after a successful build:
`build/app/outputs/flutter-apk/app-debug.apk`. That artifact does not currently
exist. Inspect and fix any newly exposed compile/test failures before declaring
Phase 1 complete. Do not proceed to Phase 2 until these checks and Android
backup/restore device validation pass.

## Known limits

Backups are unencrypted, capped at 512 MiB total / 256 MiB per file, and require
extra staging/recovery space. The first format accepts only the current schema.
Original media is retained after restore for recovery and can consume storage.
Hardware/filesystem-failure atomicity is not claimed. Provider access, physical
recording/playback and real-device UI behavior remain unverified. Existing
release signing still uses the repository's debug configuration; this work only
requests a debug APK.
