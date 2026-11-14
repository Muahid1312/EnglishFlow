# LexiFlow local backup format, version 1

A `.lexiflowbackup` is a ZIP-compatible archive using the STORE method (no
compression). It is an offline, unencrypted export of learning data. Checksums
provide integrity, not authentication or encryption. Keep backups private.

Version 1 accepts only this strict ZIP profile: UTF-8 names, regular files, no
extra fields/comments, encryption, symlinks, data descriptors, multiple disks,
ZIP64, trailing data, overlapping entries, or duplicate names. Local and central
headers must agree. Other ZIP profiles are deliberately rejected. This bounds
extraction work and avoids decompression bombs. Ordinary ZIP tools can inspect
exports; re-zipping with a different profile may make them incompatible.

Limits: 512 MiB total payload, 256 MiB per file, 2,000 entries, 200-byte ASCII
entry names, and 1 MiB for the manifest. Names are restricted to `manifest.json`,
`database.sqlite`, and `media/<safe filename>`. Absolute paths, backslashes,
`..`, and directory entries are rejected before extraction. Extraction uses a
new private staging directory.

## Manifest

`manifest.json` is UTF-8 JSON with these fields:

```json
{
  "format": "lexiflow",
  "version": 1,
  "databaseVersion": 12,
  "createdAt": "2026-11-14T10:00:00.000Z",
  "files": {
    "database.sqlite": {"size": 123456, "sha256": "<64 lowercase hex digits>"},
    "media/0.pdf": {"size": 1234, "sha256": "<64 lowercase hex digits>"}
  },
  "media": [
    {"table": "imported_books", "id": "<record ID>", "column": "file_path", "path": "media/0.pdf"}
  ]
}
```

Sizes and hashes describe the exact uncompressed bytes. The manifest is covered
by ZIP CRC32; every other entry must appear exactly once in the checksum
inventory. The media inventory must match every nonempty managed-media reference
in the database. The database and all attachments must pass validation before
replacement. Format 1 accepts database schemas 7, 8, 9, 10, 11 and 12. Older schemas are validated against
their exact trusted template before migration to schema 12 in staging. Future schemas
need an explicit compatibility policy rather than silent merge.

## Snapshot contents

`database.sqlite` is created with SQLite `VACUUM INTO`, not a live-file copy. It
contains a consistent committed snapshot, including transactions that reside in
WAL. Article text, vocabulary, schedules/history, writing/revisions, books/lesson
progress, AI conversation content, study sessions/day splits, certificates,
preferences, daily plans, enriched word fields, vocabulary practice queues and
mistake-practice attempts, timed transcripts/player settings, conversation
scenarios and requested feedback remain in the database.

Managed files are collected only from `imported_books.file_path`,
`listening_lessons.audio_path/transcript_path`, and
`speaking_recordings.audio_path`. Export rejects missing files and sources outside
the application documents directory. Duplicate source references are copied as
separate entries so each record has an independently checked mapping. Paths in
the snapshot become archive-relative paths; live database paths are unchanged.

Platform secure storage, API keys/provider credentials, authentication settings,
shared-preference files, caches, debug logs, and arbitrary document directories
are never enumerated. Pending file-deletion work is cleared in the exported copy.
Generated certificate file paths are cleared; certificate records remain intact.
The original imported reading source is not retained by the existing application;
its saved article text is preserved in SQLite. App fonts and bundled content are
not duplicated as attachments.

Export validates SQLite integrity, foreign keys, expected schema, essential
preferences/context records, ZIP headers/CRCs, SHA-256 inventory, and referenced
media. It flushes and re-reads a temporary archive before completing the local
export. Android's document-save workflow streams that archive to the chosen
system document provider and verifies the destination length and SHA-256 by
reopening it. A cancelled/failed/unreadable destination never records a successful
backup. Last-success metadata is updated only after destination verification.

## Restore and recovery

1. The Android document picker supplies the selected archive. The UI explains
   replacement and requires explicit confirmation.
2. The running study session is checkpointed/finished. Maintenance UI replaces
   the router, disposing editors before replacement starts.
3. Available space is checked for staging, verification, and the current database
   recovery copy. Missing space rejects the operation; it never skips recovery.
4. The archive is extracted into a new staging directory and validated. SQLite
   tables, indexes and SQL definitions must match the trusted declared schema;
   unexpected triggers, views, tables or schema changes are rejected. All media
   references must match the manifest and the actual archive inventory.
5. Media is installed into a new unique managed directory. Staged database
   references are rewritten to those new absolute paths. Unfinished exported
   sessions recover paused through the existing session architecture.
6. A WAL-safe `lexiflow.sqlite.previous` snapshot of the current database is made
   before replacement. Existing media is retained, including media from prior
   restores. The old database handle is permanently retired so late asynchronous
   callbacks cannot reopen it and write into restored data.
7. A flushed `lexiflow.sqlite.restore-pending` recovery marker is created. The
   closed database and its old WAL/SHM sidecars are replaced; the new database is
   flushed and checked. The marker is removed after synchronous validation. A
   fresh database handle is opened to validate normal application initialization;
   a failure triggers rollback.
8. On a process restart with a pending marker, `AppDatabase` restores the previous
   database before normal initialization. A missing recovery snapshot is an
   explicit error, never a reason to reset the database. The recovery copy remains
   available through Settings → Backup & Restore → Recover previous installation.
9. Returning from maintenance recreates the database-dependent providers/router,
   reloads restored preferences/theme, recovers sessions paused, and queries
   dashboard/progress totals from restored study records.

This is a controlled replacement with rollback, **not an atomic multi-file
transaction** or a guarantee against hardware/filesystem failure. Old media and
media installed during a failed replacement are deliberately retained because a
surviving/recovery database may reference them. A future cleanup feature must
check both active and recovery references before removing anything. A new
successful restore replaces the single previous-database recovery slot; it does
not delete older media. Archive validation failures never modify the live DB.

Callers of `BackupService.restore` / `recoverPrevious` must discard the old
`AppDatabase` and rebuild application state after any replacement attempt. The
production maintenance workflow does this; service tests reopen temporary DBs.

Schema 10 includes structured course units, lesson page ranges/notes, activities,
self-reported activity evidence and linked assessment definitions. Course cover
images join the media manifest. Hiding/deleting a course retains its PDF and
historical certificates. Legacy schema 7–9 archives validate against their own
template before the additive migration; generated certificate PDFs can be
recreated from their immutable issued metadata.

Schema 11 adds built-in article bookmarks, reading positions, explicit reading
completion, immutable question/answer snapshots, saved-word links, and stable
daily word selections. These learner records are included in the database
snapshot. The versioned 1,000-word and 100-article catalogue stays bundled in the
application assets; it is not copied into personal articles or automatically
inserted into personal vocabulary. Legacy schema 10 archives validate against
their own trusted template before the additive migration to schema 11.

Schema 12 adds the listening download queue. Its verified final files are included
through `listening_lessons.audio_path`; download rows retain the linked lesson ID
rather than a second absolute final path. Unfinished jobs are reset in exported
snapshots, and unregistered partial files are not included in the media inventory.
Restore rewrites completed lesson paths as usual. Removing offline audio retains
lesson history and progress. The Backup UI suspends transfers before export or
restore; no reliable background-download behavior is promised.
