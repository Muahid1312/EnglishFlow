# Vocabulary Intelligence and Personal Mistake Coach

## Existing behavior retained

There is one canonical vocabulary table, one SRS schedule/history implementation,
and one study-session timer. The Phase 2 queue tables organize practice; they do
not create an independent scheduler. Reading continues to save selected words,
source article IDs and original sentences. The original `example_sentence` is
preserved; the new editable example is `usage_example`.

## Scheduling and review queues

Scheduling is unchanged for existing valid records:

- Again: due in 10 minutes, interval 0, successful streak reset, ease −20.
- Hard: `ceil(max(previous interval, 1) × 1.2)`, at least one day, ease −15.
- Good: first successful review 1 day, second 3 days, later
  `round(previous interval × ease / 100)`, at least one day.
- Easy: first successful review 4 days; later the larger of previous interval + 1
  and `round(max(previous interval, 1) × ease / 100 × 1.3)`, ease +15.
- Ease stays between 130 and 350. Due times are UTC instants; one scheduled day
  means 24 elapsed hours, not local midnight. Local formatting does not alter
  due counts. Due comparison is inclusive, using the same SQLite Julian-day
  comparison as the existing scheduler. Overdue ratings schedule from the actual
  review time. No review history or valid existing schedule is reset.

A short queue contains 5, 10, 15, or all currently due canonical saved words.
Priority is deterministic: at least 24 hours overdue first, then lifetime logged
Again count descending, latest logged Again descending, earliest due instant,
then stable entry ID. IDs are persisted; there is no shuffle on each visit.

Each queue stores item position, the expected schedule count, a stable review
request ID, reveal state, result, and active/paused/completed/ended state. Rating,
SRS update, history insertion and queue advancement occur in one SQLite
transaction. Retrying the same review request cannot create a second rating.
Paused queues cannot be graded. A restarted queue resumes paused. Deleted or
independently reviewed words become skipped queue items without invented ratings.
Starting a new sized session explicitly ends the old queue while retaining its
records; “Continue unfinished review” restores the existing queue and its size.

The timer reuses a running/paused session of the same module, including a Daily
Plan session. A practice screen finishes timers it created and pauses shared
ones. Shared timers remain available in the persistent study controls and must
be finished to enter completed-day totals. Pauses, app backgrounding and the
existing inactivity guard exclude idle time. Queue progress remains durable even
if the user ends a study timer separately.

## Context and deletion

Manual offline fields include definition, Dari/Persian translation, editable
example, collocations, part of speech, pronunciation notes and personal notes.
An additional source sentence can carry an article/book label; structured
article/book IDs in saved contexts link to the real screens. Editing does not
replace original Reading sentences. Adding a duplicate word appends context and
reactivates the existing canonical word without erasing its enrichment or SRS
progress. Explicit edit can clear text with an empty string; omitted optional
meaning/translation values preserve their prior values.

Deleting a saved word removes it from saved lists and due counts (`is_saved=0`)
while preserving review history. Saving it again reuses that record/progress.
Deleting a mistake similarly hides it while retaining its practice attempts.
These retained records remain covered by database backups.

## Challenges and pronunciation

Context challenges mask one literal whole-word/phrase occurrence in a real saved
sentence/example. Repeated occurrences, substring matches and identical blank
prompts with competing saved answers are rejected. Meaning Match requires at
least two distinct, unambiguous saved English meanings. Recall also rejects
meanings shared by multiple words. Questions and options have stable order, with
at most five questions per routine. Checks compare to the saved answer; another
linguistically valid synonym is not claimed to be grammatically wrong. Challenges
do not silently produce SRS ratings or alter schedules.

Android pronunciation uses the actual system TextToSpeech API. It prefers an
installed offline US English voice, then other available US/English voices. It
checks language availability, voice metadata and synthesis errors. `QUEUE_FLUSH`
and utterance IDs prevent overlapping TTS requests or stale completion replies.
Playback can be stopped, is stopped when the detail screen is disposed, and the
engine is shut down with the Activity. A timeout also stops synthesis. There is
no pronunciation score. Offline synthesis depends on the installed engine and
voice data; UI reports that condition rather than guaranteeing offline playback.
No new TTS package or credential was introduced.

## Mistake Coach evidence and grading

A mistake contains its original/corrected sentence, explanation, manually chosen
category, source label/optional writing-entry ID, creation date, review status,
revision and computed repetition count. Writing Studio opens a confirmation
editor containing the selected sentence (or draft text) before any correction is
saved. The user must enter/confirm the correction; the original draft is not
modified and AI suggestions are never saved automatically.

Duplicate prevention hashes the original/corrected pair after whitespace
normalization, preserving case because capitalization corrections are meaningful.
Legacy duplicate rows are retained. New duplicates are rejected inside the write
transaction. Identical original/corrected sentences are not accepted as new
corrections. Editing confirmed wording reopens its review status; all historical
attempt snapshots remain unchanged. Removing a writing entry detaches its source
foreign key through the existing `ON DELETE SET NULL` behavior.

Practice uses up to five real confirmed corrections. Exact practice ignores extra
whitespace but preserves case and punctuation; its result is a saved-wording
comparison, not a general grammatical evaluator. Natural rewrites/explanations
require explicit self-assessment. Attempts record that distinction, the actual
response, result and immutable original/correction/category snapshots. Stable
attempt IDs make retries idempotent. Deleted or edited questions cannot be graded
using stale revisions. A successful attempt can mark the record reviewed, but
neither that label nor a single response is presented as topic mastery.

A weak-category recommendation needs either three distinct confirmed correction
pairs or at least three exact-wording attempts containing two mismatches. Attempt
evidence must still match the current correction/category. Self-assessments do
not supply objective error evidence. Category names are not inferred from text
or invented by an offline model. The Daily Plan uses those actual categories and
the existing vocabulary due records; it creates no duplicate timing stream.

## Metric definitions

Vocabulary metrics cover currently saved canonical words only:

- Saved: count of `is_saved=1 AND duplicate_of IS NULL` entries.
- Due: the existing due queue's distinct canonical entries.
- Reviewed: entries with logged history or a positive preserved legacy schedule
  review counter. Legacy counters do not invent historical rating outcomes.
- Success rate: Good/Easy logged ratings divided by all logged ratings. Hard and
  Again are not counted as successes. No history means insufficient data.
- Frequently forgotten: at least two persisted Again ratings, ordered by count.
- Recent activity: latest ten logged ratings, with word and timestamp.
- Retention trend: descriptive Good/Easy rating-rate difference between the latest
  ten and previous ten logged ratings, shown only with at least twenty. This is
  a rating trend, not an independent test of memory retention.

Mistake metrics cover nondeleted records: counts per manual category, marked
reviewed records, and repetition counts from actual attempts. “Repeated” means
at least two saved attempts marked needs-practice/mismatch. Improvement is the
exact-wording match-rate difference between the latest five and previous five
objective attempts, with at least ten required. Self-assessments are excluded.
Charts show raw category counts/proportions rather than invented weakness scores.

## Schema and backup compatibility

Migration 7 → 8 adds four word metadata fields, vocabulary practice sessions/items,
mistake source/deletion/revision/dedup fields, mistake attempts and query indexes.
It runs inside the existing migration transaction. Old words, schedules, histories,
mistakes and valid duplicate legacy rows remain intact; no database reset occurs.

The database snapshot includes all new fields/tables. Format-1 schema-7 backups
are validated against an explicitly generated trusted schema-7 template before a
staged migration to schema 8. Schema-8 backups validate against schema 8. Original
archive checksums are verified before staging changes; the live database is never
migrated from an unvalidated archive. The previous-database recovery copy and
retired-handle protections remain in effect. See `BACKUP_FORMAT.md` for limits.
