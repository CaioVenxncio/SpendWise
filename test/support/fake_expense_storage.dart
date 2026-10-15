import 'dart:async';

import 'package:spendwise/platform/platform_services.dart';
import 'package:spendwise/services/expense_storage.dart';

/// In-memory [ExpenseStorage] with controllable failures and delays.
///
/// Setting [data] directly simulates a write by another tab.
class FakeExpenseStorage implements ExpenseStorage {
  FakeExpenseStorage({this.data});

  String? data;
  String? legacyBackup;
  int writeCount = 0;
  int backupCount = 0;
  bool failReads = false;
  bool failWrites = false;
  bool failBackups = false;

  /// When set, reads wait for this completer before returning.
  Completer<void>? readGate;

  /// Called inside [write] just before data is stored, e.g. to simulate a
  /// concurrent writer.
  void Function()? beforeWrite;

  final _lock = InProcessLock();

  @override
  String get sourceKey => 'expenses';

  @override
  Set<String> get watchKeys => {
    'flutter.expenses',
    'flutter.expenses_legacy_backup',
  };

  @override
  LockKind get lockKind => _lock.kind;

  @override
  Future<T> exclusive<T>(Future<T> Function() action) =>
      _lock.run('test', action);

  @override
  Future<String?> read() async {
    if (readGate != null) await readGate!.future;
    if (failReads) throw Exception('read failed');
    return data;
  }

  @override
  Future<String?> readLegacyBackup() async => legacyBackup;

  @override
  Future<void> write(String data) async {
    // Yield so overlapping writes would interleave if not serialized.
    await Future<void>.delayed(Duration.zero);
    if (failWrites) throw ExpenseStorageException('write failed');
    beforeWrite?.call();
    writeCount++;
    this.data = data;
  }

  @override
  Future<void> backupLegacyData(String data) async {
    await Future<void>.delayed(Duration.zero);
    if (failBackups) throw ExpenseStorageException('backup failed');
    backupCount++;
    legacyBackup ??= data;
  }

  @override
  Future<StoredExpenseText> readStoredText() async =>
      StoredExpenseText(expenses: data, legacyBackup: legacyBackup);
}
