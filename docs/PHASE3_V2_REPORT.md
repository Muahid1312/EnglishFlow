# LexiFlow 2.0 — Phase 3 implementation report

Status: Phase 3 code and targeted regression suites are present, but acceptance
is **not complete**. Flutter/Dart remain unavailable, no automated Flutter suite
has executed, and no debug APK has been produced. Earlier Phase 1/2 verification
remains unresolved. Phase 3 was implemented at the user's explicit request; this
report does not turn those earlier unverified results into passes.

## A. Implemented features

### Listening and transcripts

The existing player now supports persisted speed (0.75/1/1.25/1.5), absolute A–B
positions, replay, bookmarks, saved playhead checkpoints, and pause on app or
router navigation changes. Seeking is clamped to the actual media duration;
slider seeks commit on release rather than starting a native seek on every drag
update. Playback failures remain visible and do not hide stored transcripts or
questions. Missing audio does not reset the saved playhead to zero.

SRT/WebVTT import and pasted timed text use actual provided timestamps. Parsing
checks syntax, bounds, increasing/nonoverlapping cues, and nonempty text. UTF-8
BOM/line endings, optional cue IDs, basic text tags/entities, WebVTT header/NOTE/
STYLE/REGION blocks and cue settings are handled. Unsupported overlapping cues
are rejected rather than silently reordered. Limits are 1,000,000 characters and
5,000 cues. Plain TXT is explicitly unsynchronized.

The transcript viewer highlights the playhead cue, seeks on tap, shows complete
cue text on long press, and supports persisted auto-scroll/hide/reveal. Cue lookup
is binary search; visible rows change on cue transitions rather than rebuilding
the whole player on every audio tick. Timed and plain views are bounded/lazy;
raw transcript editing/import is placed in an expandable section. Position writes
are checkpointed around every five seconds plus pause/navigation/disposal.

A–B repeat uses guarded absolute-position seeks. It is not advertised as
sample-accurate or gapless; actual device/codec seek latency is unmeasured.

### Comprehension and shadowing

True/false is added to existing multiple-choice, main-idea, details, intention
and self-assessed short-answer types. Keys, immutable question snapshots and
objective-only scoring continue through the existing database implementation.
The current submission ID is durable, so reopening or retrying an already-saved
submission cannot create another attempt. A new attempt explicitly clears the
answer draft and allocates a new ID. Compatible legacy draft/submission state is
recovered conservatively. Manual question authoring remains available offline;
existing explicit AI comprehension help is retained, without automatic grading
of model guesses or automatic AI question insertion.

The existing ShadowingController/RecordingService still perform reference listen,
record, stop, compare, save/discard and confirmed deletion. The selected A–B range
can initialize shadowing without replacing a recovered pending draft. There is
an explicit discard control. Deletion queues pending files even when an earlier
draft write failed. Recording resumes a compatible paused plan timer and pauses
it afterwards; separately owned recording timers still finish normally. No
pronunciation percentage, waveform, or speech-recognition result is fabricated.

### AI Conversation Coach

Eight trusted scenario definitions now supply real system instructions: everyday
American English, interview, university presentation, software engineering,
travel/directions, workplace, debate/opinions and free conversation. Each has a
B1–B2 target, goal and concise follow-up instruction. The scenario is persisted;
only exact older app-generated scenario-title markers are recovered during
migration, with unknown/custom titles left intact and defaulted to everyday.

The existing provider implementation retains secure credentials, HTTPS, disabled
redirects, model/endpoint configuration, bounded context/responses, timeouts,
authentication/rate-limit/network errors and retry cooldowns. Coached turns avoid
constant unsolicited corrections. After three real nonlocal assistant replies,
an explicit feedback action confirms sending context to the disclosed provider
and requests a short correction/expression/vocabulary/practice summary. Original
learner messages remain unchanged; feedback requests/replies are separately typed.
There is no validated level/proficiency score.

Cancellation reaches the HTTPS client's per-request connection and also supplies
logical cancellation for adapters that cannot abort their transport. A late
reply cannot overwrite a cancelled request. Cancellation does not promise that
the remote provider has not already processed/billed the operation. Stable
request IDs share in-flight work; duplicate pending submissions are blocked per
conversation and completed requests are not resent from stale retry controls.

History retains create/open/continue/rename/confirmed delete and message paging.
Title/content search and bounded history loading are added. Opening a thread
outside the first 100 results fetches that exact ID rather than switching back
to the newest thread. Pending requests are recovered as interrupted when no
operation is active. Failures preserve the local learner message and retry ID.

Assistant output can open the existing editable word/correction dialogs. Selected
vocabulary retains its actual source sentence; corrections show an actual prior
learner message and require review/edit/Save. Nothing is added automatically.
A selected short reply phrase can use the existing Android TTS bridge, with stop
and disposal. TTS/voice data may require network access. STT is unavailable;
there is no fake microphone transcription or claimed full voice conversation.

### Analytics and Daily Plan

The existing AnalyticsService reports real comprehension submission counts,
objective answer accuracy, saved shadowing attempts, speaking takes, conversations
with real replies, and recent activity. Active minutes come only from completed
study sessions. New standalone listening/AI timers are identified separately;
older/planned combined listening–speaking timers remain a separately labelled
bucket, never added again to specific-module totals. Recording duration, including
drafts, is reported separately and is not added to study time.

The plan can continue a real bookmarked audio position, with player access to
looping/shadowing. A saved conversation can be recommended when no local listening
or speaking content is available and AI is configured; the reason explicitly
states its internet/provider requirement, without asserting connectivity.

Practice reuses the existing timer. Returning after another module interrupted a
practice timer retains its active same-day plan association without attributing
the other module's seconds to that activity. Disposing while timer startup is
pending cannot launch a ghost ticker. A shared timer remains paused when a
routine ends; explicit Finish completes the broader activity. AI waiting remains
excluded through the existing service guard.

These are implemented code paths, not claims that playback, device recording,
provider access or the unexecuted tests passed.

## B. Reused existing components

- `AudioPlayerController`, just_audio and audio_session.
- `MediaStorage`, `RecordingService`, ShadowingController and its player adapters.
- Existing listening lessons, bookmarks, comprehension questions/attempts and
  recording/shadowing records.
- `SecureAiTeacherService`, secure storage, HTTPS transport and conversation tables.
- Phase 2 WordEditorDialog, MistakeEditorDialog and Android TTS bridge.
- `StudySessionService`, PracticeTimer, AnalyticsService, DailyPlanService,
  providers and existing navigation routes.
- Phase 1 SQLite snapshot/strict archive/staging/recovery machinery.

No duplicate chatbot, scheduler, repository layer or audio library was created.
No dependency version was upgraded and no new package was required. Unrelated
books, writing, grammar, vocabulary history and certificate behavior was retained
by inspection; full regression preservation is not yet test-verified.

## C. Database and file changes

App version is **2.0.0+9**; schema **8 → 9** is additive inside the existing
migration transaction. No table is reset and no new application table is added.

- Listening lessons: `playback_speed`, `loop_start_ms`, `loop_end_ms`,
  `transcript_auto_scroll`, `transcript_format`, `comprehension_submission_id`.
- Conversations: `scenario_id` and an active/recent-history index.
- Messages: `purpose` (`conversation` / `feedback`).
- Speed, loop order, auto-scroll and transcript format have bounded/enum checks.
- Existing learner text, lesson files, recordings and histories remain intact.

Timed transcript files are read into the existing transcript field; source audio
is not re-encoded or overwritten. Full database snapshots include the new settings,
scenario and feedback fields automatically. Format-1 schema 7/8 archives validate
against their exact trusted schema before a staged migration to 9. Original
archive hashes are checked before staging edits; the live DB is never open during
replacement. Recovery copies/retired handles remain in use.

Main Phase 3 files:

- New: `lib/core/services/transcript_parser.dart`,
  `lib/core/content/conversation_scenarios.dart`,
  `lib/features/listening_speaking/listening/synchronized_transcript.dart`.
- Extended: database, audio/AI/shadowing/study/analytics services, PracticeTimer,
  DailyPlanService/providers, listening/player/comprehension/shadowing/chat screens,
  router query parameters, and shared confirmation editors.
- Backup compatibility and app version metadata were updated.
- New suites: `phase3_transcript_test.dart`, `phase3_conversation_test.dart`,
  `phase3_integration_test.dart`, `phase3_widget_test.dart`.
- The Phase 2 backup test follows the current schema version while retaining its
  explicit legacy backup fixture coverage. All earlier working-tree edits remain.

## D. AI provider configuration requirements

In Android app Settings choose OpenAI, Anthropic, or a compatible custom HTTPS
endpoint, select an account-supported model and enter the user's credential in
platform secure storage. Built-in endpoints retain their validated HTTPS URLs;
custom destinations must be intentionally configured. Provider/model/hostname
are disclosed before sending. No credential is hardcoded, printed or included
in backup/setup instructions. No real paid request was made during this task.

Missing credentials leave offline learning available. Actual model entitlement,
network access and secure storage must be tested on the target installation;
configuration alone does not establish a working connection. Do not paste keys
into chat or repository files.

## E. Automated test results

Limited checks passed in this instance:

- Tree-sitter parsed all current Dart application/test files without syntax
  errors. This is not Dart analysis or compilation and does not validate APIs.
- Actual v6/v7/v8/v9 migration DDL executed against a checked-in v5 SQLite fixture;
  learner, vocabulary, correction, audio and AI message records were retained,
  and integrity/foreign-key checks passed. Dart migration callbacks such as
  fingerprint/scenario backfill were not executed by that independent DDL check.
- Static literal SQL preparation against schema 9 and escaped prefix-search
  execution passed. Exact counts are in `/workspace/phase3-validation/sql.log`.
- `git diff --check` passed.

All required Flutter/Dart commands were attempted, but the runner could not start:

| Command | Result |
|---|---|
| `dart format lib test` | Exit 127: `dart: command not found` |
| `flutter analyze` | Exit 127: `flutter: command not found` |
| Four new Phase 3 suites plus existing AI/shadowing suites | Exit 127: Flutter missing |
| `flutter test` | Exit 127: Flutter missing |
| `flutter build apk --debug` | Exit 127: Flutter missing |

**Flutter tests executed: none. Passing Flutter test count: not established.**

Written tests target SRT/VTT parsing/order/bounds, unsynchronized TXT, cue seeking
and highlighting, loop validation/settings, true/false/objective versus self
assessment, durable attempts/retries, scenario prompts, feedback gating,
transport errors/cancellation, duplicate requests, persistence/order/search,
thread selection beyond a history page, confirmed vocabulary/mistake import,
plan links/time separation, disposal during startup, schema 7/8 upgrades and
schema-9 backup roundtrip. Existing shadowing permission/state/file/error/cleanup
and AI protocol tests are included in the intended targeted run. None of these
unexecuted suites is described as passing.

## F. Android APK build result

**No APK was produced.** The build command stopped before compilation with exit
127. Expected output after successful installation and a successful debug build:
`build/app/outputs/flutter-apk/app-debug.apk`.

The active instance still has an enforced policy without the required custom
`storage.googleapis.com` grant; HTTPS CONNECT/download attempts return 403.
Flutter 3.24.5 / Dart 3.5.4 remain absent. The saved environment change must reach
the running instance, then SDK installation and validation must resume. Android
SDK packages are installed, but that is not Flutter build readiness.

## G. Hardware testing limitations

No Android microphone, speaker, installed TTS voice, codec, audio focus/call,
headphone, background/process-death, or physical document-provider test passed
in this task. Hardware/transport fixtures are mocks and cannot establish those
results. Existing adb also encounters a read-only `/home/agent/.android` path;
device access remains unresolved. Test supported codecs and voice data on actual
target devices, including denied permissions and audio interruptions.

## H. Remaining issues

1. Formatting, Dart analysis, targeted/full tests, APK generation, and earlier
   Phase 1/2 regressions are unverified. Fix any compiler/test failures exposed
   after Flutter installation before declaring acceptance complete.
2. Live AI requires user configuration/account/network verification; no live
   provider success is claimed from mocked replies.
3. STT/full voice conversation is not offered. Short selection TTS is conditional
   on installed Android engine/voice data; offline synthesis is not device-verified.
4. Overlapping cues and advanced WebVTT layout are not supported; unsupported
   timelines are rejected, not silently reinterpreted. A–B looping is not gapless
   or sample-accurate. Device latency and performance are not benchmarked.
5. Legacy combined study minutes cannot be retroactively split into exact skills;
   they are explicitly labelled, not guessed. Shared timers require finishing the
   active study activity to enter completed-day totals.
6. Backup encryption/size/storage/retained-media limitations remain as documented
   in `BACKUP_FORMAT.md`. These changes do not fix release signing or establish
   production distribution readiness.

## I. Readiness for Phase 4

**Not cleared.** Resolve the environment blocker, run the required checks and
Android validation, and assess the results first. No Phase 4 work was started.
This is not a claim that the application is bug-free or production-ready.
