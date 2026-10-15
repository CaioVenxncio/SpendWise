import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../data/drift/database.dart';
import '../domain/money.dart';
import '../models/expense.dart';
import '../repositories/expense_repository.dart';
import '../services/expense_storage.dart';

/// Version of the migration rules below; recorded with every run.
const migrationAlgorithmVersion = 1;

/// Fingerprint of an absent source key.
const absentSourceFingerprint = 'absent';

/// Fingerprint of a JSON source: SHA-256 over its exact UTF-8 text.
///
/// Identical text means the same source (a retry). Any change, even
/// whitespace, is a different source and needs explicit approval.
String sourceFingerprint(String? raw) => raw == null
    ? absentSourceFingerprint
    : 'sha256:${sha256.convert(utf8.encode(raw))}';

enum MigrationStatus {
  /// No migration has been recorded in the database.
  notStarted,

  /// This call migrated the source.
  completed,

  /// The current source was migrated before; nothing was written.
  alreadyMigrated,

  /// An earlier, different source was migrated and the current source has
  /// changed since. Importing it needs explicit approval.
  sourceChanged,

  /// The data cannot be migrated as is; nothing was written.
  blocked,

  /// Something unexpected went wrong; everything was rolled back.
  failed,
}

enum MigrationBlockReason {
  /// The source is not a valid expense collection (corrupt JSON, invalid
  /// record, or an amount that cannot be converted exactly).
  invalidSource,

  /// The source has different records sharing an ID.
  conflictingDuplicateIds,

  /// A source record has the same ID as a different database row.
  targetConflict,
}

/// Points inside the migration transaction, for fault-injection tests.
enum MigrationStep { snapshotStored, rowsInserted, verified, markerWritten }

/// Result of [JsonToDriftMigration.status] or [JsonToDriftMigration.migrate].
class MigrationResult {
  MigrationResult(
    this.status, {
    required this.fingerprint,
    this.blockReason,
    this.sourceRecords = 0,
    this.newRecords = 0,
    this.alreadyPresent = 0,
    this.duplicatesCollapsed = 0,
    this.conflictingIds = const [],
    this.totalCents,
    this.newTotalCents,
    this.message,
  });

  final MigrationStatus status;

  /// Fingerprint of the source as read.
  final String fingerprint;

  final MigrationBlockReason? blockReason;

  /// Records in the source before collapsing identical duplicates.
  final int sourceRecords;

  /// Records written (for [MigrationStatus.completed]) or that would be
  /// written (for a dry run).
  final int newRecords;

  /// Source records identical to rows already in the database.
  final int alreadyPresent;

  /// Source records repeating an earlier record exactly; counted once.
  final int duplicatesCollapsed;

  /// IDs behind [MigrationBlockReason.conflictingDuplicateIds] or
  /// [MigrationBlockReason.targetConflict].
  final List<String> conflictingIds;

  /// Exact total of the source records in cents (after collapsing).
  final BigInt? totalCents;

  /// Exact total of the [newRecords] in cents: what is (or was) added.
  final BigInt? newTotalCents;

  /// Diagnostic text. Never contains record content.
  final String? message;

  @override
  String toString() =>
      'MigrationResult($status${blockReason != null ? ', $blockReason' : ''}, '
      'source: $sourceRecords, new: $newRecords, present: $alreadyPresent, '
      'collapsed: $duplicatesCollapsed)';
}

/// A stored copy of a migrated source.
class MigrationSnapshot {
  MigrationSnapshot({
    required this.fingerprint,
    required this.sourceKey,
    required this.rawText,
    required this.legacyBackupText,
    required this.capturedAt,
  });

  final String fingerprint;
  final String sourceKey;
  final String? rawText;
  final String? legacyBackupText;
  final String capturedAt;

  /// For [encodeRawExport]: recovery export of this snapshot, which needs
  /// no decoding and works for any stored text.
  RawExpenseData toRawData() =>
      RawExpenseData(expenses: rawText, legacyBackup: legacyBackupText);
}

/// Thrown inside the transaction when verification fails.
class MigrationVerificationException implements Exception {
  MigrationVerificationException(this.message);

  final String message;

  @override
  String toString() => 'MigrationVerificationException: $message';
}

/// Thrown inside the transaction when the source changed while migrating.
class SourceChangedDuringMigrationException implements Exception {
  const SourceChangedDuringMigrationException();

  @override
  String toString() =>
      'SourceChangedDuringMigrationException: the JSON source changed';
}

/// Copies expenses from the JSON store into the SQLite database.
///
/// Never writes to the JSON store. The whole migration runs in one SQLite
/// transaction: snapshot, rows, verification, then the completion marker.
/// Any failure rolls all of it back.
///
/// See `docs/migration.md` for the rules, states and limitations.
class JsonToDriftMigration {
  JsonToDriftMigration({
    required this.source,
    required this.target,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The JSON store. Only read, never written.
  final ExpenseStorage source;

  final SpendWiseDatabase target;

  final DateTime Function() _clock;

  ExpenseStorage get _source => source;

  SpendWiseDatabase get _db => target;

  /// Fault injection for tests: called at each [MigrationStep] inside the
  /// transaction. Throwing rolls everything back.
  @visibleForTesting
  void Function(MigrationStep step)? onStep;

  /// Reports what [migrate] would do, without writing anything.
  Future<MigrationResult> status() async {
    final raw = await _source.read();
    final fingerprint = sourceFingerprint(raw);
    final migrated = await _migratedFingerprints();
    if (migrated.contains(fingerprint)) {
      return MigrationResult(
        MigrationStatus.alreadyMigrated,
        fingerprint: fingerprint,
      );
    }
    final plan = _plan(raw, fingerprint);
    final preview = plan.blocked == null
        ? await _compareWithTarget(plan)
        : null;
    final blocked = plan.blocked ?? preview!.blocked;
    if (migrated.isEmpty) {
      return blocked ?? preview!.result(MigrationStatus.notStarted);
    }
    // After a migration, any other source is reported as changed, even if
    // it could not be imported; [MigrationResult.blockReason] then says why.
    if (blocked != null) {
      return MigrationResult(
        MigrationStatus.sourceChanged,
        fingerprint: fingerprint,
        blockReason: blocked.blockReason,
        sourceRecords: blocked.sourceRecords,
        duplicatesCollapsed: blocked.duplicatesCollapsed,
        conflictingIds: blocked.conflictingIds,
      );
    }
    return preview!.result(MigrationStatus.sourceChanged);
  }

  /// Migrates the current JSON source.
  ///
  /// If a different source was migrated before, returns
  /// [MigrationStatus.sourceChanged] without writing, unless
  /// [approvedChangedFingerprint] equals the current source's fingerprint
  /// (the user reviewed [status] and approved importing it).
  Future<MigrationResult> migrate({String? approvedChangedFingerprint}) {
    // The storage lock (Web Locks in browsers) keeps writers of this app
    // version in other tabs out while the source is read and re-checked.
    return _source.exclusive(() async {
      // Unknown until the source was read successfully.
      String? fingerprint;
      try {
        final raw = await _source.read();
        final legacyBackup = await _source.readLegacyBackup();
        final fp = fingerprint = sourceFingerprint(raw);

        final migrated = await _migratedFingerprints();
        if (migrated.contains(fingerprint)) {
          return MigrationResult(
            MigrationStatus.alreadyMigrated,
            fingerprint: fingerprint,
          );
        }
        final approvedChange =
            migrated.isNotEmpty && approvedChangedFingerprint == fingerprint;
        if (migrated.isNotEmpty && !approvedChange) {
          return MigrationResult(
            MigrationStatus.sourceChanged,
            fingerprint: fingerprint,
            message: 'The JSON data changed after an earlier migration.',
          );
        }

        final plan = _plan(raw, fingerprint);
        if (plan.blocked != null) return plan.blocked!;

        return await _db.transaction(() async {
          // Comparison inside the transaction, so it sees committed rows.
          final preview = await _compareWithTarget(plan);
          if (preview.blocked != null) return preview.blocked!;

          final snapshotId = await _db
              .into(_db.migrationSnapshots)
              .insert(
                MigrationSnapshotsCompanion.insert(
                  sourceKey: _source.sourceKey,
                  fingerprint: fp,
                  rawText: Value(raw),
                  legacyBackupText: Value(legacyBackup),
                  capturedAt: _now(),
                ),
              );
          onStep?.call(MigrationStep.snapshotStored);

          await _db.batch((b) {
            b.insertAll(_db.expenseRows, [
              for (final e in preview.toInsert)
                ExpenseRowsCompanion.insert(
                  id: e.id,
                  amountCents: e.amount.cents,
                  description: e.description,
                  category: e.category,
                  occurredAt: e.dateText,
                ),
            ]);
          });
          onStep?.call(MigrationStep.rowsInserted);

          await _verify(plan, preview);
          if (await _source.read() != raw) {
            throw const SourceChangedDuringMigrationException();
          }
          onStep?.call(MigrationStep.verified);

          await _db
              .into(_db.migrationRuns)
              .insert(
                MigrationRunsCompanion.insert(
                  snapshotId: snapshotId,
                  algorithmVersion: migrationAlgorithmVersion,
                  sourceRecords: plan.sourceRecords,
                  importedRecords: preview.toInsert.length,
                  alreadyPresent: preview.alreadyPresent,
                  duplicatesCollapsed: plan.duplicatesCollapsed,
                  hadLegacyRecords: plan.hadLegacyRecords,
                  totalCents: plan.totalCents.toString(),
                  approvedChangedSource: approvedChange,
                  completedAt: _now(),
                ),
              );
          onStep?.call(MigrationStep.markerWritten);

          return preview.result(MigrationStatus.completed);
        });
      } catch (e) {
        // If a concurrent migration of the same source committed first, its
        // snapshot holds the unique fingerprint and this attempt's insert
        // failed. (Errors from a web worker do not arrive as
        // SqliteException, so check the outcome rather than the type.)
        // The winner may commit just after this attempt failed (SQLite
        // reports "busy" to one side of two overlapping write transactions),
        // so look for its marker briefly before reporting a failure.
        if (fingerprint != null &&
            e is! MigrationVerificationException &&
            e is! SourceChangedDuringMigrationException) {
          for (var i = 0; i < 10; i++) {
            try {
              if ((await _migratedFingerprints()).contains(fingerprint)) {
                return MigrationResult(
                  MigrationStatus.alreadyMigrated,
                  fingerprint: fingerprint,
                );
              }
            } catch (_) {}
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
        return _failed(fingerprint ?? 'unknown', e);
      }
    });
  }

  /// All stored source snapshots, oldest first. Works even if the JSON
  /// source can no longer be read or decoded.
  Future<List<MigrationSnapshot>> snapshots() async {
    final rows = await (_db.select(
      _db.migrationSnapshots,
    )..orderBy([(s) => OrderingTerm.asc(s.id)])).get();
    return [
      for (final r in rows)
        MigrationSnapshot(
          fingerprint: r.fingerprint,
          sourceKey: r.sourceKey,
          rawText: r.rawText,
          legacyBackupText: r.legacyBackupText,
          capturedAt: r.capturedAt,
        ),
    ];
  }

  MigrationResult _failed(String fingerprint, Object error) {
    debugPrint('JSON migration failed: ${error.runtimeType}');
    return MigrationResult(
      MigrationStatus.failed,
      fingerprint: fingerprint,
      message: error is MigrationVerificationException
          ? error.message
          : error.runtimeType.toString(),
    );
  }

  String _now() => _clock().toUtc().toIso8601String();

  Future<Set<String>> _migratedFingerprints() async {
    final query = _db.select(_db.migrationSnapshots).join([
      innerJoin(
        _db.migrationRuns,
        _db.migrationRuns.snapshotId.equalsExp(_db.migrationSnapshots.id),
      ),
    ]);
    final rows = await query.get();
    return {
      for (final r in rows) r.readTable(_db.migrationSnapshots).fingerprint,
    };
  }

  /// Validates the source and collapses exact duplicates. Pure.
  _Plan _plan(String? raw, String fingerprint) {
    if (raw == null) return _Plan.empty();
    final DecodedExpenses decoded;
    try {
      decoded = decodeExpenses(raw);
    } on FormatException catch (e) {
      return _Plan.blockedBy(
        MigrationResult(
          MigrationStatus.blocked,
          fingerprint: fingerprint,
          blockReason: MigrationBlockReason.invalidSource,
          message: e.message,
        ),
      );
    }

    final byId = <String, Expense>{};
    final unique = <Expense>[];
    final conflicting = <String>{};
    var collapsed = 0;
    for (final e in decoded.expenses) {
      final earlier = byId[e.id];
      if (earlier == null) {
        byId[e.id] = e;
        unique.add(e);
      } else if (sameExpense(earlier, e)) {
        collapsed++;
      } else {
        conflicting.add(e.id);
      }
    }
    if (conflicting.isNotEmpty) {
      return _Plan.blockedBy(
        MigrationResult(
          MigrationStatus.blocked,
          fingerprint: fingerprint,
          blockReason: MigrationBlockReason.conflictingDuplicateIds,
          sourceRecords: decoded.expenses.length,
          conflictingIds: conflicting.toList(),
        ),
      );
    }
    return _Plan(
      fingerprint: fingerprint,
      expenses: unique,
      sourceRecords: decoded.expenses.length,
      duplicatesCollapsed: collapsed,
      hadLegacyRecords: decoded.hasLegacyRecords,
    );
  }

  Future<_Preview> _compareWithTarget(_Plan plan) async {
    final existing = await _rowsWithIds(plan.expenses.map((e) => e.id));
    final toInsert = <Expense>[];
    final conflicts = <String>[];
    var alreadyPresent = 0;
    for (final e in plan.expenses) {
      final row = existing[e.id];
      if (row == null) {
        toInsert.add(e);
      } else if (_rowMatches(row, e)) {
        alreadyPresent++;
      } else {
        conflicts.add(e.id);
      }
    }
    return _Preview(plan, toInsert, alreadyPresent, conflicts);
  }

  /// Rows whose ID is in [ids], fetched in chunks so large sources need few
  /// queries and stay below SQLite's bound-parameter limit.
  Future<Map<String, ExpenseRow>> _rowsWithIds(Iterable<String> ids) async {
    const chunkSize = 500;
    final all = ids.toList();
    final rows = <String, ExpenseRow>{};
    for (var start = 0; start < all.length; start += chunkSize) {
      final chunk = all.sublist(
        start,
        start + chunkSize > all.length ? all.length : start + chunkSize,
      );
      final found = await (_db.select(
        _db.expenseRows,
      )..where((r) => r.id.isIn(chunk))).get();
      for (final r in found) {
        rows[r.id] = r;
      }
    }
    return rows;
  }

  static bool _rowMatches(ExpenseRow row, Expense e) =>
      row.amountCents == e.amount.cents &&
      row.description == e.description &&
      row.category == e.category &&
      row.occurredAt == e.dateText;

  /// Reads the inserted rows back and checks them against the plan.
  Future<void> _verify(_Plan plan, _Preview preview) async {
    final expected = preview.toInsert;
    final rows = await _rowsWithIds(expected.map((e) => e.id));
    if (rows.length != expected.length) {
      throw MigrationVerificationException(
        'Expected ${expected.length} rows, found ${rows.length}',
      );
    }
    var previousSeq = -1;
    var stored = BigInt.zero;
    for (var i = 0; i < expected.length; i++) {
      final row = rows[expected[i].id]!;
      if (row.seq <= previousSeq) {
        throw MigrationVerificationException('Row order differs at $i');
      }
      previousSeq = row.seq;
      if (!_rowMatches(row, expected[i])) {
        throw MigrationVerificationException('Row $i differs');
      }
      stored += BigInt.from(Money.fromCents(row.amountCents).cents);
    }
    // Exact totals in Dart (BigInt: no range limit, no SQL SUM).
    final planned = expected.fold<BigInt>(
      BigInt.zero,
      (sum, e) => sum + BigInt.from(e.amount.cents),
    );
    if (stored != planned) {
      throw MigrationVerificationException('Totals differ');
    }
    // Everything in the source is now present exactly once.
    final present = await _rowsWithIds(plan.expenses.map((e) => e.id));
    if (present.length != plan.expenses.length) {
      throw MigrationVerificationException('Source records missing');
    }
  }
}

class _Plan {
  _Plan({
    required this.fingerprint,
    required this.expenses,
    required this.sourceRecords,
    required this.duplicatesCollapsed,
    required this.hadLegacyRecords,
  }) : blocked = null;

  _Plan.empty()
    : fingerprint = absentSourceFingerprint,
      expenses = const [],
      sourceRecords = 0,
      duplicatesCollapsed = 0,
      hadLegacyRecords = false,
      blocked = null;

  _Plan.blockedBy(MigrationResult this.blocked)
    : fingerprint = blocked.fingerprint,
      expenses = const [],
      sourceRecords = 0,
      duplicatesCollapsed = 0,
      hadLegacyRecords = false;

  final String fingerprint;
  final List<Expense> expenses;
  final int sourceRecords;
  final int duplicatesCollapsed;
  final bool hadLegacyRecords;
  final MigrationResult? blocked;

  BigInt get totalCents =>
      expenses.fold(BigInt.zero, (sum, e) => sum + BigInt.from(e.amount.cents));
}

class _Preview {
  _Preview(this.plan, this.toInsert, this.alreadyPresent, this.conflicts);

  final _Plan plan;
  final List<Expense> toInsert;
  final int alreadyPresent;
  final List<String> conflicts;

  MigrationResult? get blocked => conflicts.isEmpty
      ? null
      : MigrationResult(
          MigrationStatus.blocked,
          fingerprint: plan.fingerprint,
          blockReason: MigrationBlockReason.targetConflict,
          sourceRecords: plan.sourceRecords,
          duplicatesCollapsed: plan.duplicatesCollapsed,
          conflictingIds: conflicts,
        );

  MigrationResult result(MigrationStatus status) => MigrationResult(
    status,
    fingerprint: plan.fingerprint,
    sourceRecords: plan.sourceRecords,
    newRecords: toInsert.length,
    alreadyPresent: alreadyPresent,
    duplicatesCollapsed: plan.duplicatesCollapsed,
    totalCents: plan.totalCents,
    newTotalCents: toInsert.fold<BigInt>(
      BigInt.zero,
      (sum, e) => sum + BigInt.from(e.amount.cents),
    ),
  );
}
