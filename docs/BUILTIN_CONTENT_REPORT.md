# Built-in offline English library — content version 1.0.0

The complete catalogue contains exactly **1,000 unique vocabulary entries**
(500 B1 targets, 500 B2 targets), **100 original reading articles**
(50 B1 targets, 50 B2 targets), and **400 keyed comprehension questions**.
B1/B2 are curriculum targets, not officially validated word-level CEFR ratings.

## Content and validation

Vocabulary has ten topics with 100 entries each (50 per level): communication,
education, technology, science, work, health, environment, society, critical
thinking, and academic English. Each entry specifies the taught meaning, part of
speech, English definition, Dari/Persian translation, original example,
collocation, topic, and stable ID.

B1 articles contain 274–316 words; B2 articles contain 352–390 words. All have
6–8 valid vocabulary links whose expressions occur in the text. Each article has
one main-idea, detail, inference, and context-vocabulary question, with four
choices, a correct answer, and an explanation. Correct answer positions are
mixed deterministically (99/112/96/93 across positions 1/2/3/4).

Run `python3 scripts/validate_content.py` from the repository root. The strict
complete-library check passes with zero errors. It checks exact counts and level
distributions, unique words/IDs/titles/text, UTF-8/JSON, required fields, article
lengths, reading-time estimates, question keys and types, distinct choices,
vocabulary references and occurrence, and repeated long paragraphs. The optional
`--partial` mode supports authoring batches; the APK workflow uses strict mode.
No incomplete catalogue passes the content gate for APK distribution.

Content was written in 20 vocabulary batches of 50 and 20 article batches of
five. The authoring helper serializes individually authored text and mixes choice
positions; it does not generate filler to reach counts. Thirty articles include
real official background-reference URLs. Fictional teaching scenarios and
hypothetical comparisons are not presented as published research findings.
Reference availability has not been checked from a device. Linguistic suitability
and translation nuance still benefit from independent teacher/native-speaker
editorial review; structural validation is not a CEFR certification.

## Integration and data preservation

The versioned JSON assets load without login or network requests. Reading and
vocabulary libraries offer search, level/topic filters, article bookmarks, and
explicit word saving. The existing Reading Studio handles text selection and
reading-position persistence, followed by comprehension and saved answer review.
Opening an article never marks it complete. Completion requires explicit reading
confirmation and submission of all four answers. Question snapshots retain the
original keys and explanations after content updates.

Personal cards reuse normalized-word deduplication and existing spaced repetition.
Saving a word preserves existing personal meanings and review schedules. No
catalogue words or articles are automatically copied into personal collections.
Daily Plan uses actual unread content, stable daily word selections, and existing
due reviews. Repeated submission tokens do not create duplicate attempts or
learning activity records. Scores describe answered questions, not proficiency.
No artificial study minutes are awarded for reading opens or question submission.

Schema 11 adds only learner-state tables. Schema 10 upgrades preserve personal
content/history; full backup includes bookmarks, positions, attempts, saved-word
links, and daily selections. Bundled teaching assets are not duplicated inside
backups. Legacy schemas 7–10 retain explicit validation/migration support.

## Main files

- `assets/content/v1/manifest.json`, 20 vocabulary JSON files, 20 article JSON files
- `scripts/content_author.py`, `scripts/validate_content.py`,
  `scripts/verify_apk_content.py`
- `lib/core/services/builtin_content_service.dart`
- `lib/features/content/builtin_library_screen.dart`
- `lib/features/content/builtin_comprehension_panel.dart`
- Existing database, backup, router, Reading Studio, Vocabulary, Daily Plan,
  and analytics services/screens
- `test/builtin_content_test.dart`, `test/builtin_content_widget_test.dart`,
  `test/support/settle_io.dart`, and updated Daily Plan/schema regression expectations
- `.github/workflows/android-debug-apk.yml`, `scripts/ci_diagnostics.py`

The catalogue cache retains completed data and returns a fresh future for later
async scopes. Personal review sorting copies SQLite's read-only result rows into
a mutable list. Pausing study checkpoints real elapsed time before notifying
listeners, preventing notifications to screens that are being disposed. Existing
widget regressions retain their assertions while scrolling lazy lists and
waiting for genuine asset I/O.

The 13 built-in content service/widget tests cover exact asset counts, fresh
browsing, level/search/bookmark filtering, real Reading Studio navigation, word
saving, correct grading and answer review, restart persistence, duplicate
submission protection, daily selections, stable IDs/question snapshots, legacy
schema migration, and full backup restoration. Tests use disposable databases;
no learner installation was reset and no live AI provider was called.

## Verification and APK

Local strict content validation passes. The actual v6–v11 SQL migration statements
retain fixture learner records and pass SQLite integrity/foreign-key checks; 410
feature SQL statements prepare successfully. This SQL check does not execute Dart
migration callbacks. All Dart files parse using a local syntax parser.

Flutter and Dart SDK downloads remain blocked by the running cloud machine's
network policy. Executable checks ran in GitHub Actions with pinned Flutter
3.24.5 and Java 21 against application commit `09878b1`:

| Check | Actual result |
| --- | --- |
| Strict complete-content validation | PASS: 1,000 words, 100 articles, 400 questions; zero errors |
| `flutter analyze` | PASS: no issues found |
| Targeted integrity regressions | PASS: 131 passed, 0 failed, 0 skipped |
| Full `flutter test --machine` suite | PASS: 286 passed, 0 failed, 0 skipped |
| Built-in service/widget cases (included above) | PASS: all 13 |
| `flutter build apk --debug` | PASS |
| APK package/version and signature | PASS: `com.lexiflow.lexiflow`, 2.0.0+12, debug signed |
| Catalogue inside the actual APK | PASS: exactly 1,000 words / 100 articles / 400 questions |
| Physical Android device | Not run |

Run: https://github.com/Muahid1312/EnglishFlow/actions/runs/43601290472

Download: https://github.com/Muahid1312/EnglishFlow/actions/runs/43601290472/artifacts/14115539719

Sign into GitHub and extract `LexiFlow-2.0.0-build12-debug.apk` from the artifact
ZIP. It also contains the APK SHA-256, byte size, package output, signature
verification, and `content-counts.json`. GitHub displays the archive as 106 MB;
its archive digest is
`1c6401ff3ecb386d0ce24caf324fd10fa6bd518e74d72260db1c63927a44d463`.
That is the ZIP artifact digest, not the APK checksum. Retention is 14 days.
The binary remains hosted on GitHub; no local binary copy is claimed.

The workflow's final status is failed solely because its formatting check found
a whitespace change in the RTL test before running the remaining checks. The
runner applied that formatting before analysis, all tests, and APK compilation.
Its exact formatter patch is now committed; token comparison confirms no Dart
logic changed. The committed application and test files match the files that
passed those executable checks. The final report/format-only commit skips an
unnecessary rebuild of the same tested application.

This is a debug artifact. No emulator/physical-device acceptance or production
release-signing validation is claimed. CI debug signing keys may differ between
builds; preserve a full backup before replacing an existing installation if
Android rejects a signed update. Independent teacher/native-speaker editorial
review and reference availability checks remain advisable. B1/B2 labels remain
curriculum targets, not official CEFR certification.
