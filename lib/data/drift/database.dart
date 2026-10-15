import 'package:drift/drift.dart';

import '../../domain/money.dart';

part 'database.g.dart';

/// Expenses, one row per record.
///
/// `seq` gives a stable insertion order (AUTOINCREMENT never reuses values,
/// even after deletes). `id` is unique, so one ID can never name two rows.
@TableIndex(name: 'expenses_occurred_at', columns: {#occurredAt})
class ExpenseRows extends Table {
  @override
  String get tableName => 'expenses';

  IntColumn get seq => integer().autoIncrement()();

  TextColumn get id => text().unique()();

  IntColumn get amountCents => integer()
      .named('amount_cents')
      .check(
        // Drift's documented way to reference the column in its own CHECK.
        // ignore: recursive_getters
        amountCents.isBetweenValues(Money.minCents, Money.maxCents),
      )();

  TextColumn get description => text()();

  TextColumn get category => text()();

  /// The original ISO-8601 text, stored verbatim.
  TextColumn get occurredAt => text().named('occurred_at')();
}

/// Exact copy of a JSON source that was migrated (schema v2).
///
/// Written in the same transaction as the migrated rows and the matching
/// [MigrationRuns] marker, so it exists only for completed migrations.
class MigrationSnapshots extends Table {
  @override
  String get tableName => 'migration_snapshots';

  IntColumn get id => integer().autoIncrement()();

  /// Storage key the source was read from, e.g. `expenses`.
  TextColumn get sourceKey => text().named('source_key')();

  /// `sha256:<hex>` of the exact source text, or `absent`. Unique, so the
  /// same source can never be migrated twice.
  TextColumn get fingerprint => text().unique()();

  /// The source text exactly as read; `null` when the key was absent.
  TextColumn get rawText => text().named('raw_text').nullable()();

  /// The legacy backup key's text at migration time, if any.
  TextColumn get legacyBackupText =>
      text().named('legacy_backup_text').nullable()();

  TextColumn get capturedAt => text().named('captured_at')();
}

/// Completion marker of a migration (schema v2). Written last.
class MigrationRuns extends Table {
  @override
  String get tableName => 'migration_runs';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get snapshotId => integer()
      .named('snapshot_id')
      .unique()
      .references(MigrationSnapshots, #id)();

  /// Version of the migration algorithm that produced this run.
  IntColumn get algorithmVersion => integer().named('algorithm_version')();

  /// Records in the source, before collapsing identical duplicates.
  IntColumn get sourceRecords => integer().named('source_records')();

  IntColumn get importedRecords => integer().named('imported_records')();

  /// Records identical to rows already in the database (skipped).
  IntColumn get alreadyPresent => integer().named('already_present')();

  /// Source records that repeated an earlier record exactly.
  IntColumn get duplicatesCollapsed =>
      integer().named('duplicates_collapsed')();

  BoolColumn get hadLegacyRecords => boolean().named('had_legacy_records')();

  /// Exact total of the migrated records in cents, as a decimal string.
  TextColumn get totalCents => text().named('total_cents')();

  /// Whether the user explicitly approved importing a changed source.
  BoolColumn get approvedChangedSource =>
      boolean().named('approved_changed_source')();

  TextColumn get completedAt => text().named('completed_at')();
}

/// Thrown when the database was written by a newer app version.
class UnsupportedSchemaVersionException implements Exception {
  UnsupportedSchemaVersionException(this.found, this.supported);

  final int found;
  final int supported;

  @override
  String toString() =>
      'UnsupportedSchemaVersionException: database version $found, '
      'this app supports up to $supported';
}

@DriftDatabase(tables: [ExpenseRows, MigrationSnapshots, MigrationRuns])
class SpendWiseDatabase extends _$SpendWiseDatabase {
  SpendWiseDatabase(super.e);

  /// 1: `expenses`. 2: adds `migration_snapshots` and `migration_runs`.
  ///
  /// Every increase needs a step in [migration] and a schema dump in
  /// `drift_schemas/`.
  static const currentSchemaVersion = 2;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // Refuse instead of guessing; a newer app wrote this database.
      if (from > to) throw UnsupportedSchemaVersionException(from, to);
      if (from < 2) {
        await m.createTable(migrationSnapshots);
        await m.createTable(migrationRuns);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      final before = details.versionBefore;
      if (before != null && before > currentSchemaVersion) {
        throw UnsupportedSchemaVersionException(before, currentSchemaVersion);
      }
    },
  );
}
