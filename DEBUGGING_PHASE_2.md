# LexiFlow — Debugging Phase 2 verification

## Completed repairs

- Reverified Phase 1 import/persistence, selected-word context, deterministic SRS/review history, certificate evidence, and local-day/DST session accounting. Preserved those repairs and the existing architecture.
- Comprehension: create/edit saved questions (multiple choice, main idea, details, intention, self-assessed short answer), persisted answer drafts, deterministic objective grading, immutable question snapshots per attempt, attempt/incorrect-answer history, persisted transcript reveal. Short answers never receive an invented objective score.
- Shadowing: integrated existing listening lessons with segment selection, native just_audio reference/recording playback, actual record microphone adapter, serialized record/stop/save actions, durable drafts, linked history, confirmation/deletion, queued file cleanup, permission/interruption handling and resource disposal. No pronunciation scores. Selecting a historical attempt selects its segment when no take is pending.
- AI: implemented actual HTTPS OpenAI, Anthropic, and custom OpenAI-compatible protocols through the existing service. Provider/model/endpoint and user key stored securely. Explicit send/consent for conversation, writing, grammar, vocabulary and comprehension assistance. Bounded context/response size, HTTPS validation, redirects disabled, timeout/auth/network/429 handling, Retry-After cooldown, and duplicate in-flight request protection. Configured status explicitly does not assert connectivity.
- Conversations: persisted real replies, stable ordering and pagination, restore/new/open/rename/confirmed delete, empty conversations, durable interrupted/error states and retry without duplicate user messages. Legacy local assistant notes remain labelled. Small-screen/keyboard overflow repaired.
- Writing: real validated mistake editor, category/explanation, edit/delete/review; legacy placeholders remain editable/removable. Revision labels/timestamps, browse/compare/restore, current-draft backup including empty drafts, immutable history, no duplicate autosave revisions. AI feedback stores the submitted text and revision without overwriting newer edits.
- Analytics: real persisted action counters and objective-only comprehension accuracy; saved shadowing and speaking duration separated. Existing timed-session day totals remain authoritative. AI waiting pauses active time and safely handles overlapping requests and background interruptions; shadowing reuses an existing session instead of duplicating it.
- SQLite v6 upgrade is transactional and additive, preserves prior records/certificates, adds request/attempt state and indexes. Upgrade fixtures for v1/v4/v5 and foreign-key/data preservation regressions pass. No existing database was reset.

## Verification

- Flutter 3.24.5 / Dart 3.5.4, Temurin JDK 17, existing Gradle 8.7 and supported configured repositories/caches.
- `flutter pub get`: PASS. No Phase 2 dependency upgrades.
- `flutter analyze`: PASS, no issues.
- `flutter test`: PASS, **127 tests**, including **20 widget tests** and 107 service/domain/database tests. 44 new Phase 2 tests. All actual SQLite/file tests use disposable fixtures, never the user's database.
- Focused Phase 1 verification: 23 passed before Phase 2. New AI, database, shadowing and UI tests were run before the broad suite.
- First broad run: 126 passed / 1 failed because the pre-existing grammar test tapped a partially obscured answer after the AI control was added. Scrolled the actual answer into view, verified that focused regression, then reran the broad suite: 127 passed / 0 failed.
- AI tests use a mocked transport; microphone/player tests use platform adapters with mocks. No real paid API requests were sent. Physical microphone/speaker, real-provider connectivity and instrumented Android tests were **NOT TESTED**.
- Static security inspection: no sensitive logging or certificate-verification bypass introduced; HTTPS-only AI endpoints, no credential redirects, no automatic audio/document upload, private application media storage, backup disabled, existing minimal microphone/network permissions retained. User data remains local unless explicitly sent to the configured provider.
- Full evidence is in `/workspace/work/phase2/`: pub-get-final.log, analyze-final.log, full-tests-final.log, focused test logs, build logs, APK metadata/signature output and adb-devices.txt.

## Acceptance workflows

Statuses refer to the evidence described; they do not assert physical-device execution.

| Workflow | Status | Evidence and limit |
|---|---|---|
| A Reading → save word → flashcard review | PASS | Widget selects real reader text, saves original context, opens flashcards and persists Good review; import/restart/SRS tests also pass. |
| B Listening → comprehension → transcript | NOT TESTED | Comprehension UI/question authoring/incorrect grading/reveal/restart PASS; full imported-audio playback on Android remains pending. |
| C Listening → shadowing → save recording | NOT TESTED | Integrated UI/controller/file persistence/deletion/permission/interruption tests PASS with recorder/player mocks; actual microphone and speaker sequence pending. |
| D Writing → AI feedback → revision history | PASS | Explicit consent, mocked provider response, saved submitted revision, comparison and restoration with current-draft backup verified through UI. Live provider pending. |
| E Mistake journal → create → edit → review | PASS | Real persisted UI CRUD, validation, review and confirmed deletion. |
| F AI teacher → send → restart → restore | PASS | Mocked HTTPS response persisted; DB/widget reopen restores ordered real-response record; new/rename/delete and interrupted retry verified. Full Android process restart/live provider pending. |
| G Book → lessons → assessment → certificate | PASS | Real database/service tests require every persisted lesson and required passing assessment and revalidate eligibility inside issuance transaction; caller flags cannot bypass it. |
| H Study activity → dashboard → progress | PASS | Real session service/DB/dashboard provider/analytics: 2 active minutes + 5 AI-wait minutes yields exactly 2 minutes; duplicate finish, midnight, DST and recovery regressions pass. |

## Remaining issues and required checks

- **High, production distribution:** release signing still uses the existing Android debug certificate. A successful release build is a test artifact, not a production-ready signed release.
- **Medium, verification:** no connected Android device/emulator (`adb devices -l` empty). Install/launch, real playback/microphone, denied/revoked permissions, audio focus/calls/headphones, background/resume/process death and old-install upgrade need device checks.
- **Medium, verification:** live provider credentials/model availability/connectivity and Android secure-storage integration require explicit user-configured provider testing. Automated tests cover request/response/error protocols without paid requests.
- Scanned PDF OCR and automatic pronunciation scoring are not implemented or claimed; selectable-text PDF support and self-assessment remain explicit.
- No further confirmed critical software defect remains in the tested scope. This is not a claim that the application is bug-free.

## Secure production signing setup

The existing `android/app/build.gradle` release block explicitly uses `signingConfigs.debug`. Before distribution:

1. Create/obtain the organization's release/upload keystore outside this repository and keep encrypted backups. Use Play App Signing where appropriate.
2. Supply keystore path, alias and passwords using protected CI secrets or an untracked `android/key.properties`; load those values into a dedicated Gradle `signingConfigs.release` and assign it to the release build. Fail production CI when required values are missing rather than silently falling back to debug signing.
3. Keep all keystores and passwords out of source control and logs; existing Android ignore rules cover `key.properties`, `*.jks` and `*.keystore`.
4. Rebuild release and verify `apksigner verify --verbose --print-certs` against the expected release/upload certificate, then install/launch and test upgrades on an Android device. Do not use the current debug-signed artifact for production distribution.

No signing credentials were invented or committed. These verification results precede publication; see the repository history and GitHub release for publication details.

## Final readiness

**CONDITIONAL — IMPORTANT VERIFICATION PENDING.** Automated software verification passes; real Android audio/lifecycle, live AI and production signing remain pending.

## Android artifacts

- Debug: PASS, 33.7 seconds; `/workspace/work/lexiflow/build/app/outputs/flutter-apk/app-debug.apk` (241,525,126 bytes).
- Release: PASS, 150.8 seconds; `/workspace/work/lexiflow/build/app/outputs/flutter-apk/app-release.apk` (71,931,386 bytes). R8 remains enabled; existing optional JP2 decoder suppression remains narrowly scoped.
- Both packages: `com.lexiflow.lexiflow`, version `1.0.0` / code `5`, min SDK 23, target SDK 34, compile SDK 35.
- Both signatures verified with Android `apksigner`: Android Debug certificate, v1/v2 signatures. Release is **not production signed**.
- Manifest permissions: INTERNET, RECORD_AUDIO, ACCESS_NETWORK_STATE, generated package-scoped DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION. No broad external-storage permissions introduced.
- No dependency outage occurred in these builds; verified existing Gradle artifacts/caches were reused, with normal TLS verification. No insecure mirror or unrelated dependency upgrade.
- Device list empty: installation/launch/hardware checks pending.

SHA-256 checksums:

```text
0716c42aef9187713a89d2a3b02faaef7fed9f6273703ed6b77d10f969c78c20  build/app/outputs/flutter-apk/app-debug.apk
b5bf669c8b1a2708fd86436f15507a27924468c67dc28f93acc5462609764a4b  build/app/outputs/flutter-apk/app-release.apk
```

## Changed files in Phase 2

- `lib/core/database/app_database.dart`
- `lib/core/services/ai_teacher_service.dart`
- `lib/core/services/analytics_service.dart`
- `lib/core/services/shadowing_controller.dart`
- `lib/core/services/study_session_service.dart`
- `lib/core/widgets/ai_help_button.dart`
- `lib/features/dashboard/learn_hub_screen.dart`
- `lib/features/grammar_writing/grammar/grammar_lesson_screen.dart`
- `lib/features/grammar_writing/writing/writing_history_screens.dart`
- `lib/features/grammar_writing/writing/writing_studio_screen.dart`
- `lib/features/listening_speaking/ai_conversation/ai_conversation_screen.dart`
- `lib/features/listening_speaking/listening/audio_player_screen.dart`
- `lib/features/listening_speaking/listening/comprehension_screen.dart`
- `lib/features/listening_speaking/listening/shadowing_screen.dart`
- `lib/features/progress/progress_screen.dart`
- `lib/features/reading/reading_screen.dart`
- `lib/features/settings/settings_screen.dart`
- `lib/features/vocabulary/vocabulary_screen.dart`
- `test/ai_service_test.dart`
- `test/database_regression_test.dart`
- `test/fixtures/schema_v5.sql`
- `test/phase2_ai_test.dart`
- `test/phase2_data_test.dart`
- `test/phase2_shadowing_test.dart`
- `test/phase2_widget_test.dart`
- `test/recovery1_widget_test.dart`
- `test/stability_services_test.dart`
- `test/stability_widget_test.dart`
- `test/support/phase2_fakes.dart`
- `DEBUGGING_PHASE_2.md`
