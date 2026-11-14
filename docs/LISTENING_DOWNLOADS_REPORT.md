# In-app offline listening downloads — build 13

LexiFlow downloads authorized audio inside the existing Listening Studio and
plays completed files through its existing local-file player. The app does not
extract audio from video services or protected/provider-only streams.

## Supported sources

The first catalogue contains four original LexiFlow recordings. Scripts were
written for this project and speech was synthesized with CMU Flite SLT/RMS voice
models. The catalogue explicitly labels synthetic American English speech and
B1/B2 curriculum targets; it does not claim human presenters or certified CEFR
levels. The publisher permission and upstream notices are in `listening_catalog/`.

| Original lesson | Target | Voice | Actual duration |
| --- | --- | --- | --- |
| Planning a Short Study Session | B1 | Flite SLT, synthetic | 65.832 s |
| Clarifying a Work Request | B1 | Flite RMS, synthetic | 78.528 s |
| The Evidence Behind a Confident Claim | B2 | Flite SLT, synthetic | 89.880 s |
| Testing a Change Before Expanding It | B2 | Flite RMS, synthetic | 104.304 s |

The files total 2,709,296 bytes. All four published HTTPS URLs were fetched and
matched their size/SHA-256 metadata. Real range requests returned HTTP 206 with
correct `Content-Range` and matching bytes. FFmpeg decoded every source recording
successfully. URLs are pinned to immutable publisher commit `b888f7e`; see
`assets/listening/catalog_v1.json` for full URLs, hashes, transcripts, and questions.
Audio is downloaded on request, not included inside the APK as preloaded media.

VOA Learning English, BBC Learning English, British Council LearnEnglish, and
ELLLO are **online-only provider resource links**. They are not falsely offered
as downloadable lesson feeds. Their sites are blocked by this cloud environment,
so current redistribution/download terms and specific media links could not be
verified. No third-party audio is copied, scraped, or extracted. Browser-downloaded
permitted audio can be imported through Android's existing file picker.

## Download and storage behavior

A single-worker queue persists available, queued, downloading, paused, downloaded,
and failed states. Progress comes from real committed byte counts against verified
publisher file sizes; percentages are never simulated. Duplicate requests for the
same catalogue ID reuse the existing job/lesson.

HTTPS destinations are restricted to the publisher host, with immutable repository
paths and permission metadata. Redirects are validated individually with a bounded
redirect count. HTTP, credentials in URLs, custom ports, local-file schemes,
unapproved hosts, and content encodings are rejected. HTML/JSON pages, invalid
headers, wrong sizes, invalid ranges, and SHA-256 mismatches cannot be finalized.

Pause/resume is offered after the server advertises byte ranges. Resume checks
`Content-Range`, total size, and an available strong ETag. If a server ignores
Range and returns HTTP 200, the partial file is truncated and restarted. A final
SHA-256 check also protects resumed data. Failed protocol/integrity checks discard
the partial copy; recoverable network interruptions retain a resumable prefix.
Cancellation removes its partial transfer. Jobs survive app restarts.

Downloads run **in the foreground**. Moving the app out of the foreground stops
the active connection; resumable transfers can be resumed and other interruptions
retried. There is no Android WorkManager/foreground-service implementation and
no promise of reliable background downloading or background notifications.

Files are stored under app-private documents in `media/listening_downloads/`.
Temporary and completed files share a filesystem so final rename can be atomic
where supported. Registration of the local lesson, keyed questions, and verified
download status is a SQLite transaction. Files are never automatically written
to public Downloads, exported to other apps, or registered in public media storage.
No Android storage permission was added. Private storage is **not DRM** and does
not make files impossible to extract from a device.

The library reports actual managed audio storage usage and supports refresh.
Transfers are limited to 128 MiB per file with a 16-MiB free-space reserve. Imports
check supported file headers/size and preserve the chosen original. Header checks
are not a guarantee that every third-party codec can be decoded on every device;
the existing player reports decoder failures.

## Integration and data preservation

Downloaded Lessons opens the existing player with an absolute local path. Seeking,
speed changes, transcripts, comprehension, shadowing, and actual study timing use
the existing implementations. Original starter lessons include transcripts and
four keyed comprehension questions each. Listening lessons enter the existing
Daily Plan selection once a verified local file is available.

Deleting audio clears only the file reference and download state, preserving the
lesson, position, bookmarks, transcript, questions, answers, and study history.
Redownloading reuses that lesson without overwriting learner edits or adding
questions again. Managed deletion validates private paths and checks other media
references before removing a file.

Database schema 12 adds `listening_downloads`; schema 11 upgrades are additive.
Existing schemas 7–11 keep explicit backup validation/migration support. Finished
audio is already covered by the backup's listening-media inventory; restore rewrites
those paths normally. Partial files are not exported and unfinished jobs are reset
in the exported snapshot. Backup/restore UI suspends active transfers before work
begins. Existing recovery-media retention rules still apply after restoring backups.

## Main changed files

- `lib/core/services/listening_downloads.dart`: source policy, HTTPS transport,
  queue, progress, resume/retry, verification, storage, import, and audio removal
- `lib/features/listening_speaking/listening/listening_library_screen.dart`:
  discovery, Downloaded Lessons, management controls, and provider resources
- Database migration, service providers, and Backup & Restore service/UI
- Android `MainActivity.kt`: allowlisted HTTPS provider-page opening
- `assets/listening/catalog_v1.json` and `listening_catalog/` original sources/audio
- `scripts/author_listening_starters.py`, `scripts/verify_listening_catalog.py`,
  APK asset verifier, and build workflow
- `test/listening_downloads_test.dart`, `test/listening_downloads_widget_test.dart`,
  and updated import/schema compatibility fixtures

## Verification and APK

Local catalogue size/hash/codec checks passed. Flutter/Dart SDK downloads remain
blocked in this cloud machine, so executable Flutter checks and the debug APK
build run with the pinned GitHub Actions toolchain. Results and the build 13
artifact will be recorded here after verification. No physical Android device
or emulator acceptance test has been performed.
