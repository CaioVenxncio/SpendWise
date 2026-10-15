import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../app/backend.dart';
import '../app/tab_coordinator.dart';
import '../backup/expense_backup.dart';
import '../platform/platform_services.dart';
import '../repositories/expense_repository.dart';
import '../services/expense_storage.dart';
import 'json_to_drift_migration.dart';

enum MigrationPhase { checking, ready, running, finished, error }

/// Result of [MigrationController.savePreMigrationBackup].
enum BackupSaveResult {
  /// The file was handed to the browser. Whether it was actually stored
  /// is unknown; the user must confirm that.
  handedToBrowser,

  /// The data changed since it was checked; it was checked again.
  sourceChanged,

  /// The file could not be created or offered.
  failed,
}

/// UI state for the JSON → SQLite migration.
class MigrationController with ChangeNotifier {
  MigrationController(
    this._backend, {
    DateTime Function()? clock,
    TabCoordinator? tabs,
  }) : _clock = clock ?? DateTime.now,
       _tabs = tabs {
    final t = tabs;
    if (t != null) {
      // Another tab (any version) changed the JSON data, or another tab of
      // this version completed a migration: check again.
      _subs.add(t.sourceChanges.listen((_) => _refreshUnlessRunning()));
      _subs.add(t.migrationsElsewhere.listen((_) => _refreshUnlessRunning()));
      // The list of other tabs is shown on the migration screen.
      t.addListener(_notify);
    }
  }

  final AppBackend _backend;
  final DateTime Function() _clock;
  final TabCoordinator? _tabs;
  final _subs = <StreamSubscription<void>>[];

  /// Fingerprint of the source the pre-migration backup was made from.
  String? _backupFingerprint;
  String? _backupFileName;
  bool _backupConfirmed = false;

  MigrationPhase _phase = MigrationPhase.checking;
  MigrationResult? _status;
  MigrationResult? _outcome;
  int _snapshotCount = 0;
  bool _disposed = false;

  MigrationPhase get phase => _phase;

  /// Last result of [refresh]: what a migration would do.
  MigrationResult? get status => _status;

  /// Result of the last [migrate] call.
  MigrationResult? get outcome => _outcome;

  int get snapshotCount => _snapshotCount;

  StorageSafety get storageSafety => _backend.storageSafety;

  /// Browser storage mode chosen by Drift, if reported.
  String? get storageImplementation => _backend.storageReport?.implementation;

  JsonToDriftMigration get _migration => _backend.migration!;

  /// Whether there is something the user could migrate (before the
  /// backup and storage requirements).
  bool get hasPendingRecords {
    final s = _status;
    if (_phase != MigrationPhase.ready || s == null) return false;
    if (s.blockReason != null) return false;
    return (s.status == MigrationStatus.notStarted ||
            s.status == MigrationStatus.sourceChanged) &&
        s.newRecords > 0;
  }

  /// Whether the storage mode allows migrating at all.
  bool get storageAllowsMigration => storageSafety.allowsMigration;

  /// Name of the backup file offered for the current source, if any.
  String? get backupFileName =>
      _backupFingerprint == _status?.fingerprint ? _backupFileName : null;

  /// Whether a backup of the current source was offered for download.
  bool get backupOffered => backupFileName != null;

  /// Whether the user confirmed having saved that backup.
  bool get backupConfirmed => backupOffered && _backupConfirmed;

  /// Whether the user may start a migration now: something to move, safe
  /// storage, and a confirmed backup of exactly this source.
  bool get canMigrate =>
      hasPendingRecords && storageAllowsMigration && backupConfirmed;

  /// Whether the app may show SQLite data without a migration first.
  bool get mayOpenApp {
    final s = _status;
    if (s == null) return false;
    return switch (s.status) {
      MigrationStatus.alreadyMigrated ||
      MigrationStatus.sourceChanged ||
      MigrationStatus.completed => true,
      // Nothing to migrate (fresh installation).
      MigrationStatus.notStarted => s.sourceRecords == 0,
      MigrationStatus.blocked || MigrationStatus.failed => false,
    };
  }

  /// Other tabs of this version using the same data set.
  List<PeerTab> get otherTabs => _tabs?.peers ?? const [];

  void _refreshUnlessRunning() {
    if (_phase != MigrationPhase.running) refresh();
  }

  Future<void> refresh() async {
    _phase = MigrationPhase.checking;
    _notify();
    try {
      _status = await _migration.status();
      _snapshotCount = (await _migration.snapshots()).length;
      if (_status?.fingerprint != _backupFingerprint) {
        // A backup only counts for the exact data it was made from.
        _backupConfirmed = false;
      }
      _phase = MigrationPhase.ready;
    } catch (e) {
      debugPrint('Migration status failed: ${e.runtimeType}');
      _phase = MigrationPhase.error;
    }
    _notify();
  }

  /// Creates a backup of the current JSON data (the importable backup
  /// format, amounts in exact cents) and offers it as a download.
  ///
  /// The file is built from the data as read now; if that differs from
  /// what the user reviewed, nothing is offered and the status is
  /// refreshed. Offering a download is not proof that it was stored, so
  /// [backupConfirmed] stays false until [setBackupConfirmed].
  Future<BackupSaveResult> savePreMigrationBackup(FileTransfer files) async {
    final reviewed = _status;
    if (!hasPendingRecords || reviewed == null) return BackupSaveResult.failed;
    try {
      final raw = await _backend.jsonStorage.read();
      if (sourceFingerprint(raw) != reviewed.fingerprint) {
        await refresh();
        return BackupSaveResult.sourceChanged;
      }
      final expenses = raw == null
          ? const <Never>[]
          : decodeExpenses(raw).expenses;
      final now = _clock();
      final name = preMigrationBackupFileName(now);
      await files.saveText(name, encodeBackup(expenses, exportedAt: now));
      _backupFingerprint = reviewed.fingerprint;
      _backupFileName = name;
      _backupConfirmed = false;
      _notify();
      return BackupSaveResult.handedToBrowser;
    } catch (e) {
      debugPrint('Pre-migration backup failed: ${e.runtimeType}');
      return BackupSaveResult.failed;
    }
  }

  /// Records the user's statement that the backup file is saved.
  void setBackupConfirmed(bool confirmed) {
    if (!backupOffered) return;
    _backupConfirmed = confirmed;
    _notify();
  }

  /// Runs the migration the user confirmed. For a changed source, approves
  /// exactly the fingerprint the user was shown.
  Future<MigrationResult?> migrate() async {
    final shown = _status;
    if (!canMigrate || shown == null) return null;
    _phase = MigrationPhase.running;
    _outcome = null;
    _notify();
    final result = await _migration.migrate(
      approvedChangedFingerprint: shown.status == MigrationStatus.sourceChanged
          ? shown.fingerprint
          : null,
    );
    _outcome = result;
    _phase = MigrationPhase.finished;
    if (result.status == MigrationStatus.completed) {
      _tabs?.announceMigration();
      _backupConfirmed = false;
    }
    _notify();
    // Re-read the state, e.g. to show "already migrated" afterwards.
    try {
      _status = await _migration.status();
      _snapshotCount = (await _migration.snapshots()).length;
    } catch (_) {}
    _notify();
    return result;
  }

  /// The JSON source exactly as stored, in the raw-export envelope.
  Future<String> exportJsonSource() async {
    final storage = _backend.jsonStorage;
    return encodeRawExport(
      RawExpenseData.fromStored(await storage.readStoredText()),
      exportedAt: _clock(),
    );
  }

  /// All migration snapshots, exactly as stored.
  Future<String> exportSnapshots() async {
    final snapshots = await _migration.snapshots();
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'spendwise-migration-snapshots',
      'formatVersion': 1,
      'exportedAt': _clock().toUtc().toIso8601String(),
      'note':
          'Unmodified JSON data as it was when it was moved to SQLite. '
          'Values are the exact stored text.',
      'snapshots': [
        for (final s in snapshots)
          {
            'fingerprint': s.fingerprint,
            'sourceKey': s.sourceKey,
            'capturedAt': s.capturedAt,
            'rawText': s.rawText,
            'legacyBackupText': s.legacyBackupText,
          },
      ],
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _tabs?.removeListener(_notify);
    super.dispose();
  }
}
