# JSON → SQLite migration (M2 Stage 3)

`lib/migration/json_to_drift_migration.dart` copies expenses from the
shared_preferences JSON store into the Drift/SQLite database.

**Status:** implemented and tested, **not activated**. The app still reads
and writes JSON through `JsonExpenseRepository`. Running the migration in
production and switching backends are separate, later steps.

## What it never does

* Write, rewrite, or delete the JSON keys `expenses` or
  `expenses_legacy_backup`.
* Round, convert loosely, drop, merge, or overwrite records.
* Import JSON changes made after a migration without explicit approval.
* Resolve conflicts automatically.

## Metadata (schema v2)

| Table | Purpose |
|---|---|
| `migration_snapshots` | `fingerprint` (UNIQUE), `source_key`, exact `raw_text` (NULL if the key was absent), `legacy_backup_text`, `captured_at` |
| `migration_runs` | completion marker: `snapshot_id` (UNIQUE, FK), `algorithm_version`, `source_records`, `imported_records`, `already_present`, `duplicates_collapsed`, `had_legacy_records`, exact `total_cents` (decimal string), `approved_changed_source`, `completed_at` |

A migration counts as done only if a `migration_runs` row exists. Both rows
and all expense rows are written in one transaction, so they exist together
or not at all.

## Fingerprint: retry vs. changed source

`fingerprint = "sha256:" + SHA-256(UTF-8 bytes of the exact stored text)`,
or `"absent"` when the key does not exist.

* **Same fingerprint as a completed run → retry.** Nothing is written;
  result `alreadyMigrated`.
* **Different fingerprint while a run exists → changed source.** Any byte
  difference counts, including reformatting. Result `sourceChanged`;
  nothing is written. `status()` previews what importing it would add. Only
  `migrate(approvedChangedFingerprint: <that fingerprint>)`, called after
  the user approved that preview, imports it, using the same rules:
  identical rows are skipped, conflicting rows block, and records missing
  from the new source are **not** deleted from SQLite.

## Rules for records

1. The source is decoded with the same strict rules as the app
   (`decodeExpenses`): legacy decimal amounts are converted exactly or the
   source is rejected; `amountCents` must be an integral, in-range number.
2. Any invalid record blocks the whole migration (`blocked` /
   `invalidSource`).
3. **Duplicate IDs in the source:** records with the same ID and identical
   content (same cents, description, category, and exact date text; a
   legacy `12.5` equals `amountCents: 1250`) are collapsed to the first
   occurrence and counted in `duplicates_collapsed`. Records with the same
   ID and any difference block the migration (`conflictingDuplicateIds`).
4. **Existing rows in SQLite:** a row with the same ID and identical
   content is skipped and counted (`already_present`). A row with the same
   ID and different content blocks the migration (`targetConflict`).
   Unrelated rows are kept; migrated rows are appended after them in source
   order.
5. Original IDs, descriptions, categories and ISO date strings are kept
   exactly; order follows the source.

## Transaction

Inside one SQLite transaction:

1. compare the source with existing rows;
2. insert the snapshot (unique fingerprint);
3. insert the new expense rows;
4. read them back and verify count, IDs, order, every field, and the exact
   total (BigInt in Dart, never SQL `SUM`), and that every source ID is
   present exactly once;
5. re-read the JSON source and abort if it changed;
6. insert the `migration_runs` marker.

Any exception rolls back all of it. Tests inject failures after each step
and check that the database is left empty and a retry succeeds.

## States (`MigrationStatus`)

| State | Meaning | Written? |
|---|---|---|
| `notStarted` | no completed run (from `status()`) | no |
| `completed` | this call migrated the source | yes |
| `alreadyMigrated` | this exact source was migrated before | no |
| `sourceChanged` | the source differs from every migrated snapshot | no |
| `blocked` | invalid source, conflicting duplicates, or target conflict | no |
| `failed` | unexpected error; everything rolled back | no |

## Concurrency and other tabs

* `migrate()` runs under the same storage lock as JSON writes
  (`spendwise.expenses`, Web Locks in supporting browsers). Tabs running
  this version cannot change the JSON source in the meantime.
* SQLite is the final guard: the unique fingerprint means a second
  attempt for the same source cannot commit. If two attempts overlap
  without a shared lock, one completes; the other's insert fails, it finds
  the winner's marker and reports `alreadyMigrated` (it polls briefly for
  up to about one second; if the winner has not committed by then it reports
  `failed`, which is safe — nothing was written).
* **Limitations:**
  * A tab running an older version (M1 or earlier) does not take the lock
    and can change the JSON source at any time. A change during a migration
    is detected (step 5) and rolls it back; a change afterwards shows up as
    `sourceChanged`.
  * Where Web Locks are unavailable, JSON writes from other tabs are not
    excluded during the migration; the re-check in step 5 still detects
    them, but a write landing between that re-check and the commit is not
    seen until `status()` is called again (it then reports
    `sourceChanged`).

## Recovery

* The JSON keys are never touched, so the original data and the Stage 1
  "Export raw data" path remain available.
* `snapshots()` returns every migrated source text exactly, without
  decoding it, even if the JSON key is later corrupted or removed.
  `snapshot.toRawData()` feeds the existing raw-export envelope.

## Rolling back from SQLite to JSON

Changing a backend flag is **not** enough once new transactions have
happened in SQLite: the JSON store still holds the data as it was at
migration time. The supported path, covered by a test:

1. Export a backup from the SQLite-backed app (existing backup format).
2. Switch the app back to JSON.
3. Import that backup (preview → user confirmation). Records added in
   SQLite after the migration are added to JSON; identical records are
   skipped; any conflicting record blocks the import.

Known limitation: import never deletes, so records **deleted** in SQLite
after the migration reappear in JSON. The user must delete them again.
No automatic downgrade exists.

**Blocker (found in M3 Stage 0, open):** import never replaces either. A
record **edited** in SQLite after the migration (repository `update`, M3.1)
has the same ID as its unedited JSON original, so the backup import in
step 3 reports it as a conflict and refuses the whole import; nothing is
changed. This is covered by a test. Until a safe recovery path for edited
records is designed and approved, real-data migration stays disabled.

## Application integration (M2 Stage 4A)

The default build is unchanged: JSON storage on the user's real data.

The SQLite backend is selected only at build time:

```
flutter build web --dart-define=SPENDWISE_BACKEND=drift --dart-define=SPENDWISE_NAMESPACE=qa1
```

* `SPENDWISE_NAMESPACE` isolates everything: JSON keys become
  `spendwise_ns.<ns>.expenses` (shared_preferences stores them as
  `flutter.spendwise_ns.<ns>.expenses`), the database is
  `spendwise_ns_<ns>`, and locks are namespaced too.
* **Drift without a namespace is refused** (`AppConfig.validate`): the app
  shows a configuration error and opens no storage. Real-data migration
  needs Stage 4B approval.
* **Fail closed:** if the database cannot be opened, the app shows an error
  with *Try again* and *Export original data*. It never falls back to JSON
  or to an empty database, which could make expenses look lost.
* **Gate:** after opening, the migration status decides what the user sees:

| Status | Shown |
|---|---|
| nothing to migrate (fresh installation) | the app |
| not started, records present | migration screen (preview → confirm) |
| blocked (invalid source, conflicting IDs, target conflict) | migration screen with explanation; no way into an empty app |
| already migrated | the app |
| source changed after migration | the app with a notice; *Review* → explicit approval of that exact fingerprint |
| temporary browser storage (`inMemory`) | migration disabled, warning |

* While migrating, the screen shows progress, blocks back navigation, and
  offers no other action; the app's editing UI does not exist yet.
* Exports on the migration screen: *Export original data* (the JSON keys,
  undecoded) and *Export migration snapshots* (all stored snapshots, exact).

## Production readiness (M2 Stage 4B preparation)

Still **not enabled for real data**: Drift requires a test namespace, and
the default build does not even contain the SQLite code (`main()` passes
the Drift launcher only when built with `SPENDWISE_BACKEND=drift`, a
compile-time constant).

### Pre-migration backup (required)

Before *Move* (or *Add* for a changed source) is possible:

1. **Download backup** creates an importable backup (format v1, exact
   cents, SHA-256 checksum) from the JSON data as read at that moment. If
   that data differs from what the user reviewed, no file is offered and
   the status is checked again.
2. The user ticks **"I have saved the backup file and know where to find
   it."** Offering a download is not treated as proof that a file was
   stored.
3. The confirmation only counts for that exact data (fingerprint). Any
   change, including one made in another tab, resets it.

Cancelling at any point before the final confirmation dialog changes
nothing.

### Storage modes

| Drift mode | Meaning | Migration |
|---|---|---|
| `opfsShared` | origin-private file system, one shared worker | allowed |
| `opfsLocks` | origin-private file system with cross-tab locks (needs COOP/COEP) | allowed |
| `sharedIndexedDb` | IndexedDB in a shared worker; coordinated, slower | allowed |
| `unsafeIndexedDb` | IndexedDB, tabs not coordinated | **refused** |
| `inMemory` | lost when the tab closes | **refused** |
| anything else (in a browser) | not recognised | **refused** (fails closed) |
| native file (Android/desktop) | SQLite file on the device | allowed |

Persistent storage is requested after saves but never assumed: browsers may
refuse silently and may still clear data.

### Other tabs

* **Storage events** (`window` `storage`): fire in every other tab when the
  JSON keys change, whichever app version wrote them. A JSON-mode tab then
  pauses edits (*Reload* notice); a Drift-mode tab re-checks the source and
  shows the changed-source notice, also on the migration screen, where a
  confirmed backup is reset.
* **BroadcastChannel** `spendwise.tabs` (this version and later): tabs
  announce themselves (`hello`/`here`/`bye`, with version, backend and
  namespace) and report completed migrations (`migrated`). The migration
  screen lists other open tabs and asks to close them; a JSON-mode tab is
  told when another tab moved the data.
* **Limits:** older versions send no messages and cannot be detected
  before they write; nothing can force another tab to close or stop. A tab
  that crashes may stay listed until *Check again*. Storage events do not
  fire for writes in the same tab, nor for IndexedDB/OPFS. The source
  fingerprint and the single migration transaction remain the actual
  safeguards.

### Recovery and rollback (unchanged rules)

* Original JSON keys, legacy backups and migration snapshots are never
  modified or deleted.
* Database open failures show an error with *Try again* and *Export
  original data*; there is no fallback to another store or to an empty
  database.
* Going back from SQLite to JSON is a manual, explicit procedure: export a
  backup from the SQLite app, use a JSON build, import the backup (preview →
  confirm). **Expenses deleted after the migration reappear**, because the
  JSON data still contains them and imports never delete. Records added
  after the migration are restored; conflicting records block the import,
  which includes **any record edited after the migration** (open blocker,
  see "Rolling back from SQLite to JSON").
* There is no automatic downgrade or backend switch after errors.
