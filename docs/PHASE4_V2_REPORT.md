# LexiFlow 2.0 — Phase 4 implementation report

Status: implementation and targeted test sources are present. Phase 4 acceptance
is **incomplete**: Dart/Flutter are unavailable, no Flutter test has run, and no
APK has been built. Earlier phases retain their unresolved acceptance status.
No Phase 5 work was started.

## 1. Features implemented

The existing Courses entry in the book library now supports course creation,
editing, archive/unarchive, confirmed soft deletion, opening and resuming. A
course can start without a PDF, then link a real imported PDF in its settings.
Settings preserve description, target level, optional managed cover image and
minimum objective assessment score. Linked materials are retained on deletion.

Structured courses contain manually authored units, ordered lessons and activity
records. Units and lessons can be edited and moved up/down. Lessons store
objectives, notes and validated page ranges, and can link saved articles, words,
audio, grammar lessons, writing entries and assessments. Assessment activities require a saved keyed pass before their evidence can be recorded and are rechecked for certification. General module practice is also an
explicit option. Reading opens the existing reader at the linked start page;
its regular bookmarks and saved playhead remain in use. Page-range changes are
checked against the actual imported book page count.

Starting/continuing a lesson saves a study timestamp; it does not manufacture
study minutes or completion. Activity checkboxes explicitly record self-reported
work. Opening a module/PDF never creates completion evidence. Courses show
lesson/unit totals, completed totals, remaining activities, last studied lesson
and self-reported status. Empty lessons and empty units cannot certify.

The optional passage assistant accepts at most 6,000 selected/pasted characters.
Simplification, vocabulary, grammar, summary and practice-question requests use
the existing configured provider and explicit online disclosure/consent flow.
Dari/Persian explanations are optional. Nothing reads/uploads an entire book,
fabricates its contents, or labels AI output an official answer. Offline course
organization, study, grading and recommendations require no provider.

## 2. Existing components reused

Courses/lessons, imported_books, pdfx reader/bookmarks, assessment definitions,
questions/attempts, completion requirements, certificate history/PDF assets,
AI provider and AiHelpButton, learning modules, session/day accounting,
MistakeCoach, DailyPlanService, BackupService and the existing router/design
widgets are extended. No competing book library or database was introduced.
Legacy lesson checkboxes remain available for existing unstructured courses.

## 3. Database migration and backup

Schema 10 adds course PDF/cover links, structured-mode/deletion flags and minimum
score; course_units; lesson unit/objective/notes/pages/last-study fields;
course_activities and course_activity_evidence; assessment course/unit links;
and indexes for hierarchy lookups. Legacy courses remain structured_mode=0.
No existing lesson/attempt/certificate is deleted or rewritten by this migration.

Backup format remains version 1. Trusted schemas 7, 8, 9 and 10 are accepted;
older versions validate against their original schema before staged upgrade.
All new structured records travel inside the SQLite snapshot. Course cover
images join the explicit media manifest; existing book/audio protection remains.
Generated certificate PDFs can be reconstructed from issued metadata after
restore, without generating another completion or certificate reference.

## 4. Course and assessment behavior

All current lessons and activities in a structured course are required. Adding
unfinished work changes current eligibility; previously issued certificates stay
historical. No requirements configured means certification is unavailable.
Course minimum score defaults to 0.7 and is editable from 0 through 1. Choose
required final assessments through the existing completion panel.

The assessment author supports multiple choice, true/false, vocabulary recall,
grammar, reading and short writing. Definitions can link the course or a unit.
Creation validates titles, choices, keys and thresholds and saves transactionally.
The shared deterministic grader requires every response, rejects missing objective
keys, and excludes writing from the objective denominator. Writing requires an
explicit rubric self-assessment. Writing-only submissions have no objective score
and cannot pass. Attempts retain submitted answers, score when applicable,
pass/fail, dates and a writing-review marker. Previous attempts appear on the take
screen. A submit guard and stable per-screen attempt ID prevent double tapping
from creating duplicate attempts. Unsaved answer drafts are not restart durable.

## 5. Certificate eligibility verification

For structured courses the database requires every lesson to contain completed
activity evidence, all units to contain completed lessons, at least one selected
required assessment, and persisted answers that regrade to a pass at both the
assessment threshold and course minimum. A passed flag or supplied score alone
cannot authorize certification. Certificate creation checks evidence again inside
the final save transaction after rendering, rejecting changed/incomplete work.
The verification type explicitly identifies self-reported activities and assessed
answers; this is personal learning evidence, not independently proctored work.

Existing unstructured courses/books retain their legacy eligibility rules; their
historical records are not retroactively invalidated. Legacy PDF wording explains
that lesson completion was self-reported. All PDFs retain the non-accredited
qualification disclaimer. Historical preview/print, save and share render the
original issued name/title/reference/date/score/verification metadata, without
rechecking or modifying the old completion.

## 6. Analytics implementation

Daily/weekly/total time and streak continue using existing canonical completed
session/day data. Opening lessons adds no study time. Six skill summaries show
real saved articles/sessions, vocabulary review ratings/due cards, objective
listening/grammar answers, saved recordings, and writing drafts/revisions. Course
counts are distinct from issued completion-record counts. No activity count is
presented as proficiency or a validated CEFR level.

Objective listening/grammar percentages require five answers; vocabulary review
percentages require five persisted reviews and are labelled self-rated recall.
Zero correct answers with sufficient evidence displays 0%, not missing data.
Below-60% recommendations state their denominator and evidence threshold.
Mistake recommendations reuse the existing minimum-three-record/attempt rules.
Real unfinished lessons, due cards, saved writing and unpassed authored course
assessments produce linked recommendations. The Daily Plan can select an actual
unfinished structured lesson and preserves its established session accounting.

## 7. Tests and verification

Added phase4_assessment_test.dart, phase4_courses_test.dart and
phase4_widget_test.dart. Coverage includes grading/writing exclusion, thresholds,
missing keys/responses, CRUD/order/restart persistence, page bounds/cross-course
units, explicit evidence/forged pass rejection, soft deletion, missing analytics,
real recommendations/Daily Plan, schema-9 migration, backup with cover/evidence,
historical PDF rendering, course creation and activity-checkbox widgets. Prior
backup integration now includes schema 9 and expects the current schema version.

Executed static checks: tree-sitter parses 102 Dart source/test files with no
syntax errors; independent SQLite checks execute migration DDL through schema 10,
retain fixture learner/word/mistake/audio/AI records, pass integrity/foreign-key
checks, and prepare 388 literal SQL statements. Exact course aggregation also runs against empty, opened and explicitly completed fixtures. This does not execute Dart
migration callbacks, type checking, platform plugins, UI or Flutter tests.
`git diff --check` passes. Detailed logs: /workspace/phase4-validation.

Required commands were attempted: dart format, flutter analyze, targeted tests,
full flutter test and flutter build apk --debug. Every command exited 127 because
the executable is absent. **Zero Flutter tests executed.** Formatting and analyzer
acceptance are outstanding; syntax parsing is not a substitute.

## 8. APK status

No APK produced. Flutter's storage.googleapis.com download still receives proxy
HTTP 403. The applied managed environment remains restricted at revision 1 with
no custom allowed host. Android SDK/Java installation from earlier setup remains
available, but cannot replace the missing Flutter SDK.

## 9. Known limitations

Compilation, Flutter tests, migrations/backups on Android, PDF export native
flows, themes/RTL/responsive rendering and physical-device behavior remain
unverified. PDF text selection is manual passage paste; no TOC/text extraction is
claimed. Existing learning activities retain their own lifecycle; deleting one
can leave a course link whose destination shows the existing missing-record state.
Activity completion is intentionally self-reported. Assessment answers are graded
against current stored keys; editing keys outside the authoring UI can change
future eligibility, but never rewrites attempts or issued certificates. Legacy
eligibility retains its original compatibility behavior. Lists/forms are simple
manual organization; extremely large courses and cover image decoding have not
been device-profiled. Published assessments currently have create/take/history
controls, not a revision editor. All current lessons/activities are required;
optional-lesson policies and independent/proctored verification are not provided.

## 10. Phase 5 readiness

Not ready. Review/save the existing storage.googleapis.com network addition in
environment settings and publish it; saving a draft alone does not apply policy.
Install Flutter using /workspace/englishflow-install.sh, then format/analyze, run
targeted and full suites, resolve failures, build the debug APK and verify Android
flows against a copy/backup of real learner data before Phase 4 acceptance.
