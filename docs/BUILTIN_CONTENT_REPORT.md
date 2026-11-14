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
- `scripts/content_author.py`, `scripts/validate_content.py`
- `lib/core/services/builtin_content_service.dart`
- `lib/features/content/builtin_library_screen.dart`
- `lib/features/content/builtin_comprehension_panel.dart`
- Existing database, backup, router, Reading Studio, Vocabulary, Daily Plan,
  and analytics services/screens
- `test/builtin_content_test.dart`, `test/builtin_content_widget_test.dart`,
  and updated Daily Plan/schema regression expectations
- `.github/workflows/android-debug-apk.yml`, `scripts/ci_diagnostics.py`

## Verification and APK

Local strict content validation passes. The actual v6–v11 SQL migration statements
retain fixture learner records and pass SQLite integrity/foreign-key checks; 410
feature SQL statements prepare successfully. This SQL check does not execute Dart
migration callbacks. All Dart files parse using a local syntax parser.

Flutter and Dart SDK downloads remain blocked by the running cloud machine's
network policy. GitHub Actions runs the pinned Flutter 3.24.5 toolchain, analysis,
service/widget regressions, full tests, and `flutter build apk --debug`. The new
complete-content build is version 2.0.0+12; its executable results and artifact
link will be recorded after the run completes. Syntax/SQL checks alone do not
establish Flutter test success. No physical Android device test has been run.
