# LexiFlow 2.0 final engineering audit

Current build 13 verification is recorded in
[LISTENING_DOWNLOADS_REPORT.md](LISTENING_DOWNLOADS_REPORT.md): clean analysis,
307 passing full-suite tests, verified foreground audio downloads, and a signed
debug APK. The 1,000-word / 100-article library remains included. This supersedes
the historical build 11 results below. Device and production-signing acceptance
remain unverified.

## GitHub build follow-up

The local-environment results below are the original Phase 5 baseline. Subsequent
GitHub Actions execution is recorded here; the earlier zero-test/no-APK statements
must not be read as the current GitHub build result.

Code is pushed on branch `lexiflow-2.0-final`. Run
https://github.com/Muahid1312/EnglishFlow/actions/runs/43582434776 built application
commit `8379d63` successfully with Flutter 3.24.5 and Java 21. Package/signature
verification and artifact upload also succeeded. The workflow remains failed
because formatting/analyzer/regression checks are not all clean: the full suite
reported **254 passed, 17 failed**. Production/device readiness is not established.

Build troubleshooting restored the export screen's missing share_plus import,
removed an intl/Flutter TextDirection collision, and supplied the database's B1
listening-difficulty default when callers omit that optional map value. No schema
or historical learner records were changed by those fixes.

The uploaded artifact is `LexiFlow-2.0.0-build11-debug`:
https://github.com/Muahid1312/EnglishFlow/actions/runs/43582434776/artifacts/14109555932

Sign into GitHub and extract `LexiFlow-2.0.0-build11-debug.apk` from the ZIP. It
contains package/version output, debug-signature verification, size and APK SHA-256
metadata. GitHub displays the artifact as 105 MB and its **artifact archive digest**
as `07e1101eddde8d2a8266bbf12f0748619183e778fa65ba81ab0a43ad80a1b0c2`;
this is not asserted to be the APK's checksum. Artifact retention is 14 days.

This cloud workspace could inspect the public run and upload result, but the
artifact download requires a GitHub login and the GitHub API is blocked here.
No local copy of the binary or physical-device validation is claimed. The source
push and GitHub-hosted debug artifact are verified; the remaining failing checks
and original release-signing requirements still block a production release.

## Baseline recorded before Phase 5 edits

Source preservation: /workspace/phase5-validation/pre-phase5-source.tar.gz,
SHA-256 inventory, original Git status and binary diff. Existing Phase 1–4
uncommitted work is retained. Only disposable fixtures may be restored/tested.

Version 2.0.0+10; schema 10; package/namespace com.lexiflow.lexiflow.
Android: compileSdk 35, minSdk 23, targetSdk inherited from Flutter, AGP 8.6.1,
Kotlin 1.8.22, Gradle 8.7, NDK 26.1.10909125, Java 21 installed.
Dart constraint ^3.5.4; Flutter/Dart executables absent. SDK installation blocked
by storage.googleapis.com proxy HTTP 403; current enforced revision 1 has no
custom host grants. No accepted Flutter baseline, APK or AAB exists.

Release build explicitly uses debug signing (DEFECTIVE). No installed Android
versionCode or original signing certificate has been verified. Source versionCode
10 is known; the learner's installed value is unknown. Do not assert update
compatibility or generate a replacement signing key.

| Major area | Baseline classification | Evidence/limit |
| --- | --- | --- |
| Startup, onboarding, navigation, themes | NOT VERIFIED | Source/tests present; no Flutter execution |
| Backups/restore and maintenance | NOT VERIFIED | Archive, validation, recovery code and fixtures present; no Dart restore executed |
| Daily Plan and session/day accounting | NOT VERIFIED | Source and midnight/restart tests present |
| Reading and vocabulary/SRS/intelligence | NOT VERIFIED | Local storage, scheduling and learning screens present |
| Listening/transcripts/comprehension | NOT VERIFIED | Source and mock tests present; native playback untested |
| Shadowing/speaking | NOT VERIFIED | Recording/playback state code present; hardware untested |
| AI conversations/providers | NOT VERIFIED | Secure storage/HTTPS/mock tests present; no live provider call authorized |
| Writing/revisions/mistake journal | NOT VERIFIED | Autosave, revision and correction tests present |
| Books/structured courses/assessments | NOT VERIFIED | Schema 10 and CRUD/evidence source present |
| Certificates and PDF export | NOT VERIFIED | Eligibility/PDF/history source present; platform export untested |
| Analytics and recommendations | NOT VERIFIED | Real-data SQL present; Flutter results unavailable |
| Android release signing | DEFECTIVE | Release variant selects debug key |
| Production artifacts/device acceptance | INCOMPLETE | No build or device evidence |

Dependency baseline is pubspec.yaml plus the preserved pubspec.lock; no upgrades
are assumed safe. Vulnerability database validation has not been performed.

## A. Version 2.0 feature audit after hardening

All major learning features in the baseline table remain **NOT VERIFIED** at
runtime. Their code/tests exist; that does not establish WORKING status. Release
signing fallback was DEFECTIVE and is now removed in source, with Gradle execution
still NOT VERIFIED. Android artifacts and device acceptance remain INCOMPLETE.
No unrelated feature, redesign, dependency upgrade or schema migration was added.

## B. Confirmed defects addressed

Verification below distinguishes source/SQL evidence from unexecuted regressions.

| Severity | Root cause | Change | Verification status |
| --- | --- | --- | --- |
| P0 | Crash rollback deleted the live DB before validating/copying its previous snapshot | Read-only integrity/FK/preferences/version checks, durable staged copy, rename, and retain journal/live data on validation/copy failure | Three disposable-DB regression cases added; Dart execution blocked |
| P1 | New legacy/standalone certificates trusted stored score/pass flags | Every new certificate path now regrades persisted responses against stored keys; require normalized max_score=1 and finite valid thresholds | Added forged/missing-answer/denominator regression; SQL prepares; Flutter test blocked |
| P1 | Release variant selected the debug signing configuration | Explicit original-key signing config and task-graph guard reject packaging without credentials; app identity unchanged | Static config assertion passed; Gradle/signature validation blocked |
| P1 | Custom endpoint edits silently reused a previously stored API key | A changed endpoint requires explicit key re-entry; rejected changes preserve prior settings | Mock-only regression added; not executed |
| P1 | Backup media preflight could differ from the later SQLite snapshot | Revalidate references from the actual snapshot before hashing/exporting files | Concurrent-import/outside-file regression added; not executed |
| P1 | Startup failures occurred before runApp with no recovery UI | Safe retry screen, sanitized diagnostic with stack, deterministic closure of bootstrap DB | Injected platform-failure widget test added; not executed |
| P1 | Assessment/PDF loading failures escaped asynchronous init callbacks | Retryable assessment load errors and visible PDF load/save errors; mounted guards on PDF callbacks | Two injected-storage widget tests added; not executed |
| P2 | Nonfinite course score input passed UI checks; title/score saved in separate writes | Validate finite bounds in the service and save metadata/score in one SQL statement | Atomic-edit regression added; SQL prepares; Dart test blocked |
| P2 | Native PDF extraction checked text length only after allocating the full result | Bounded Writer stops extraction at one million characters | Source inspected; Kotlin/native integration NOT TESTED |

Android cleartext traffic is explicitly disabled. INTERNET and RECORD_AUDIO are
the only main-manifest permissions; both serve existing functions. Android cloud
backup remains disabled to avoid exporting secure storage accidentally. No key,
keystore or password was added to source. Existing ignored signing exclusions
were extended to all repository paths. No live AI requests were made.

Tightened certificate rules intentionally prevent *new* certificates from legacy
attempts with missing/inconsistent answers. The learner can retake an assessment.
Existing attempts, issued completion records, certificate references and files
were not rewritten. Legacy test fixtures now include real keyed answers and
scores consistent with their one-question fixtures; assertions were not weakened.

## C. Remaining issues and release blockers

- **P0 acceptance blocker:** the modified rollback path has not run in Dart or on
  Android. Its regression tests and an isolated restore must pass before release.
- **P1:** Flutter/Dart are absent. SDK downloads fail at the managed proxy with
  CONNECT HTTP 403 for storage.googleapis.com. Current enforced revision 1 does
  not include that custom host. The saved draft includes it but is not applied.
- **P1:** original signing credentials, deployed certificate fingerprint and
  installed versionCode are unavailable. Production update compatibility is
  unknown. Source build number increased from 10 to **11**, not an assertion
  that 11 exceeds an unknown installed build.
- **P1:** analyzer, full tests, debug build, native Gradle/Kotlin compilation,
  successful backup restore and the complete learning workflows are unverified.
- **P2:** cold start, memory use, native audio/PDF interruptions, large data lists,
  responsive/large-text/RTL and light/dark rendering need executable/device checks.
- **P2:** a lockfile inventory is available (118 packages), but dependency security
  advisories and resolved dependency compatibility are NOT VERIFIED. No speculative
  upgrades were made.
- **P3:** layout/accessibility polish has not been visually accepted. No general
  UI redesign or unsubstantiated performance improvement is claimed.

No keystore was generated or replaced. Do not distribute a debug APK as a release.

## D. Data safety

The pre-Phase-5 source snapshot, SHA-256 inventory, Git status and binary diff are
outside the checkout at `/workspace/phase5-validation`. No pre-existing source
file was removed. Real learner databases/files were neither reset nor restored.
Schema remains **10**; no additional migration or destructive fallback was added.

Persisted learner text (vocabulary, reviews/history, reading, writing/revisions,
mistakes, conversations, settings, sessions/day splits, plans, course/evidence,
assessments and certificates) lives in SQLite. User media dependencies are imported
book PDFs, audio/transcripts, speaking/shadowing recordings and course covers.
Certificate PDFs are generated from retained issued metadata. The backup uses a
WAL-consistent SQLite snapshot plus these explicit media references. Credentials
remain in secure storage and are excluded, along with caches and arbitrary files.
Original media, previous recovery database and journals are retained as documented;
archives contain sensitive learner data and are not encrypted by this format.

Executed host-SQL checks: representative v1/v4/v5 fixtures upgrade via extracted
actual DDL through v10, retain words/preferences, pass integrity/foreign keys;
failed DDL transaction retains the old schema/version. Existing v6–v10 DDL checks
retain learner/word/mistake/audio/AI fixture data. **These do not execute Dart
migration callbacks.** Application backup validation, checksums, archive attacks,
interrupted restore and rollback have test sources but **no successful Dart
restore was executed**. Backup safety is therefore NOT VERIFIED.

## E. Performance

Measured the existing exact course aggregate on host SQLite with 100 units,
5,000 lessons and 25,000 activities, five runs: median **25.13 ms**, max **41.95 ms**.
This excludes Dart grouping, screen rebuilds, PDF/audio decode and Android IO.
See `migration-benchmark.json`; this is synthetic fixture data only.

No before/after speedup or native cold-start result is claimed. Existing indexes
cover course/lesson/activity/evidence lookups. The PDF text bound addresses a
confirmed allocation path, but native memory improvement remains unmeasured.

## F. Automated verification

**Flutter tests executed: 0. Passed: 0. Assertion failures: 0.** The runner never
started; this is not a passing suite. Eight service/data regression cases in
`phase5_test.dart` replace the previous local helper/string-only checks, and three
widget regressions are in `phase5_widget_test.dart`. Existing certificate fixtures
were corrected to contain actual graded evidence.

| Command | Result |
| --- | --- |
| Targeted Flutter suites (hardening, backup, migration, sessions, courses, AI) | Exit 127: flutter absent |
| flutter pub get | Exit 127: flutter absent |
| dart format --output=none --set-exit-if-changed lib test | Exit 127: dart absent |
| flutter analyze | Exit 127: flutter absent |
| flutter test | Exit 127: flutter absent |
| flutter build apk --debug | Exit 127: flutter absent |
| flutter build apk --release | NOT RUN: original signing unavailable; Flutter absent |
| flutter build appbundle --release | NOT RUN: original signing unavailable; Flutter absent |

There were six SDK command-launch failures, no Dart test assertion results, and
an additional ADB initialization failure. No Gradle/Maven build reached dependency
download or source compilation; do not classify these results as Gradle source or
Maven HTTP failures. Flutter SDK download denial is a separate environment issue.

Executed static checks: 103 Dart source/test files parse without syntax errors;
388 literal feature SQL statements prepare against schema 10; exact course
aggregation behaves correctly for empty/opened/explicit-completion fixtures;
Git whitespace checks pass; package identity, permissions, no debug release
fallback, signing ignore patterns and artifact inventory were inspected.
Syntax parsing is **not** Dart type analysis, Kotlin compilation or Flutter tests.
Logs, commands/exit codes, fixture scripts and dependency inventory are in
`/workspace/phase5-validation`.

## G. End-to-end acceptance

| Workflow | Result | Missing execution |
| --- | --- | --- |
| A. Onboarding → Dashboard → Daily Plan | NOT TESTED | Flutter/UI runner |
| B. Import article → Read → Save vocabulary → Review | NOT TESTED | UI/import integration |
| C. Vocabulary review → Scheduling → History → Restart | NOT TESTED | Dart/service/restart execution |
| D. Import audio → Listen → Comprehension → Results | NOT TESTED | Flutter/native playback |
| E. Segment → Shadowing → Record → Replay | NOT TESTED | Microphone/audio integration |
| F. AI conversation → Send → Save → Restore | NOT TESTED | Mock-provider/persistence suite; no live calls |
| G. Writing → Autosave → Revision → Restore | NOT TESTED | Widget/autosave suite |
| H. Mistake journal → Create → Edit → Review | NOT TESTED | Widget/service suite |
| I. Import book → Create course → Complete lessons | NOT TESTED | PDF/course integration |
| J. Assessment → Eligibility → Certificate PDF | NOT TESTED | Dart grader/PDF/platform export |
| K. Backup → Validate → Isolated restore | NOT TESTED | Actual Dart archive/restore success |
| L. Session → Dashboard → Accurate analytics | NOT TESTED | Timer/date/analytics integration |

No workflow receives PASS from source inspection or the SQL-only checks. Offline
reading/review/grammar/writing/PDF/audio/plan/progress behavior also remains NOT
TESTED. Existing source uses local data for these workflows; AI explicitly needs
online provider access. Platform mocks do not establish hardware behavior.

## H. Android artifacts and secure signing setup

Version: **2.0.0+11**. Package/namespace: **com.lexiflow.lexiflow**. Schema: **10**.

| Artifact | Actual path | Size | Signature |
| --- | --- | --- | --- |
| Debug APK | None produced | N/A | NOT VERIFIED |
| Release APK | None produced | N/A | BLOCKED: no configured original key |
| Release AAB | None produced | N/A | BLOCKED: no configured original key |

No APK/AAB was found in build output locations. Expected Flutter output paths are
not deliverables and are not evidence of success. No signature or install/update
compatibility verification has run.

1. Review/save the existing network draft in environment settings, then publish
   the environment. Confirm storage.googleapis.com is in the **applied** policy
   and rerun `/workspace/englishflow-install.sh` with inherited proxy/TLS trust.
   Do not use an insecure mirror or turn off certificate/checksum validation.
2. Obtain the **original distribution keystore** from the maintainer's protected
   storage. Do not generate a replacement for the distributed application. Do not
   send passwords or keystores in chat, commit them, or put them in app assets.
3. Locally create ignored `android/key.properties` with `storeFile` (absolute
   protected keystore path), `storePassword`, `keyAlias`, and `keyPassword`.
   Use the actual existing values; no credentials/template passwords are supplied
   here. Restrict file/keystore access (for example mode 600) and use a protected
   ephemeral build-secret mount in CI. Relative storeFile paths resolve from the
   Android project root. Debug builds do not require this file.
4. Inspect the known distributed APK with `apkanalyzer manifest version-code`
   and `apksigner verify --print-certs`. Compare public certificate SHA-256 with
   the original key and generated artifact. VersionCode **must exceed the
   installed/distributed value**; adjust the build number only after that value
   is known. Public metadata may be shared; private signing material must not be.
5. Run targeted tests, pub get, format check, analyze, full tests and debug build.
   Fix failures before release builds. Then run `flutter build apk --release` and
   `flutter build appbundle --release` with the original credentials configured.
6. Verify actual files, sizes, SHA-256 and APK certificate using Android SDK
   `apksigner`. Verify the AAB signature using `jarsigner -verify`, and validate
   its delivery path with the intended distribution service/tooling. Confirm
   package/version metadata from the built files. A debug signer does not establish
   production readiness even if it happens to match a prior development install.

The Gradle guard rejects release packaging with absent/incomplete credentials or
missing keystore rather than silently falling back to debug signing. Incorrect
passwords/key aliases still require a real Gradle signing check.

## I. Device acceptance — all pending

ADB `devices -l` aborted with exit -6 because it cannot create
`/home/agent/.android` on the read-only filesystem. No usable emulator/device was
verified. No physical test is claimed. Configure ADB access in a suitable test
environment before acceptance.

Use a disposable profile/device first. Preserve and validate a real backup before
any learner-install update. All of these checks remain pending:

- Install the app and launch it successfully.
- Complete onboarding or restore a disposable existing profile.
- Import and open a PDF, including a course page range.
- Save/review vocabulary and verify its schedule after restart.
- Play imported audio, change speed and replay a marked segment.
- Record/replay speech and test permission denial/background interruption.
- Save a writing draft and restore a revision.
- Close/reopen the app and verify all saved learning records.
- Generate a certificate from genuinely eligible disposable assessment data.
- Export a backup, validate it and restore it into an isolated test installation.
- Preview/save/share the historical PDF, including after backup restore.
- Update from the original signed app using the same signer and higher versionCode,
  then verify data retention. Do not overwrite real learner data with fixtures.
- Check light/dark themes, large text, keyboard/scrolling, screen reader labels
  and Dari/Persian RTL on the learning and error/retry screens.

## J. Final release decision

**BLOCKED — CRITICAL PROBLEMS REMAIN**

Critical integrity/eligibility fixes are present in source but have not passed
runtime regression or Android acceptance. The SDK/network gate, missing original
signing credentials, unknown deployed update metadata, no executable test baseline
and absent artifacts prevent trustworthy release. This decision does not imply
that a repaired source defect is still reproduced; it means the required release
safety gates remain unresolved. No public release readiness is claimed.
