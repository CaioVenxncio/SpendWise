import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backup/expense_backup.dart';
import '../domain/calendar.dart';
import '../domain/money.dart';
import '../models/expense.dart';
import '../repositories/expense_repository.dart';
import '../repositories/json_expense_repository.dart';
import '../services/expense_storage.dart';

enum ExpenseLoadStatus { notLoaded, loading, ready, failed }

class ExpenseProvider with ChangeNotifier {
  /// Uses [repository], or a JSON repository over [storage] (by default
  /// shared_preferences).
  ExpenseProvider({
    ExpenseRepository? repository,
    ExpenseStorage? storage,
    DateTime Function()? clock,
  }) : _repository =
           repository ??
           JsonExpenseRepository(storage ?? SharedPreferencesExpenseStorage()),
       _clock = clock ?? DateTime.now;

  final ExpenseRepository _repository;
  final DateTime Function() _clock;

  List<Expense> _expenses = [];
  Set<String> _duplicateIds = const {};
  ExpenseLoadStatus _status = ExpenseLoadStatus.notLoaded;
  Object? _loadError;
  Future<void>? _loading;
  bool _hasConflict = false;
  bool _disposed = false;

  /// Tail of the write queue. Writes run one at a time so that each one
  /// persists the result of all previous writes.
  Future<void> _writeQueue = Future.value();

  List<Expense> get expenses => List.unmodifiable(_expenses);

  ExpenseLoadStatus get status => _status;

  /// Whether expenses are loaded and may be changed.
  bool get isReady => _status == ExpenseLoadStatus.ready && !_hasConflict;

  /// The error that caused the last load to fail, if any.
  Object? get loadError => _loadError;

  /// IDs shared by several stored records. Those records cannot be deleted.
  Set<String> get duplicateIds => _duplicateIds;

  /// Whether stored data was changed elsewhere (e.g. another tab) since it
  /// was loaded. Changes are refused until [reload] succeeds.
  bool get hasConflict => _hasConflict;

  /// The current time from the injected clock (display of "this month").
  DateTime get now => _clock();

  /// Exact sum of expenses whose local calendar date (as displayed, see
  /// [localCalendarDate]) is in the current local month.
  ///
  /// Throws [MoneyOverflowException] if the sum leaves the supported range.
  Money get currentMonthTotal {
    final now = _clock();
    return Money.sum(
      _expenses
          .where((e) => isInSameLocalMonth(e.date, now))
          .map((e) => e.amount),
    );
  }

  /// Loads stored expenses.
  ///
  /// Concurrent calls share one load. After a failure, calling this again
  /// retries. If the stored data cannot be read or decoded, the provider
  /// enters [ExpenseLoadStatus.failed] and refuses all writes, so the stored
  /// data is never overwritten.
  Future<void> loadExpenses() {
    if (_status == ExpenseLoadStatus.ready) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  /// Discards the in-memory view and loads stored data again, e.g. after a
  /// conflict. Waits for pending writes first.
  Future<void> reload() {
    return _loading ??= _writeQueue
        .then((_) => _load())
        .whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    _status = ExpenseLoadStatus.loading;
    _loadError = null;
    // Deferred so listeners that call [loadExpenses] again see the pending
    // load instead of starting a second one.
    scheduleMicrotask(_notify);
    try {
      final snapshot = await _repository.load();
      _expenses = snapshot.expenses;
      _duplicateIds = snapshot.duplicateIds;
      _hasConflict = false;
      _status = ExpenseLoadStatus.ready;
    } catch (error) {
      _loadError = error;
      _status = ExpenseLoadStatus.failed;
      // Only the type and message: stored content must never be logged.
      debugPrint(
        'Failed to load expenses: ${error.runtimeType}'
        '${error is FormatException ? ': ${error.message}' : ''}',
      );
    }
    _notify();
  }

  /// Records that another tab changed the stored data. Changes are paused
  /// (as after a detected conflict) until [reload].
  void markExternalChange() {
    if (_status != ExpenseLoadStatus.ready || _hasConflict) return;
    _hasConflict = true;
    _notify();
  }

  /// Called once when this provider is disposed.
  VoidCallback? onDispose;

  /// Adds [expense] and persists it. Throws if saving fails, in which case
  /// the in-memory list is left unchanged.
  Future<void> addExpense(Expense expense) =>
      _write(() => _repository.add(expense));

  /// Deletes the expense with [id] and persists the change. Throws if saving
  /// fails, in which case the in-memory list is left unchanged. Refuses
  /// IDs shared by several records with [DuplicateExpenseIdException].
  ///
  /// Compatibility path that checks only the ID (see
  /// [ExpenseRepository.delete]). Editing workflows must use
  /// [deleteExpectedExpense].
  Future<void> deleteExpense(String id) => _write(() => _repository.delete(id));

  /// Replaces [expected] (the record as shown) with [replacement] and
  /// persists it. The list changes only after the write succeeded.
  ///
  /// Throws [ExpenseConflictException] if the record or (JSON) storage
  /// changed elsewhere, and [ExpenseNotFoundException] if the record no
  /// longer exists; both also pause edits until [reload], because the shown
  /// list is out of date. Throws [DuplicateExpenseIdException] for IDs shared
  /// by several records and [ArgumentError] if the IDs differ; those change
  /// nothing else.
  Future<void> updateExpense(Expense expected, Expense replacement) =>
      _write(() => _repository.update(expected, replacement));

  /// Deletes [expected] only if the stored record is still exactly that.
  /// Same failure behaviour as [updateExpense].
  Future<void> deleteExpectedExpense(Expense expected) =>
      _write(() => _repository.deleteExpected(expected));

  /// Validates [bytes] as a backup and compares it with current expenses.
  /// Changes nothing. Throws [BackupFormatException] for invalid files.
  ImportPreview previewBackup(Uint8List bytes) {
    _ensureWritable();
    return previewImport(parseBackup(bytes), _expenses);
  }

  /// Imports the new records of [preview] in one all-or-nothing write. The
  /// comparison is repeated against stored data at write time.
  Future<ImportOutcome> importBackup(ImportPreview preview) async {
    late ImportOutcome outcome;
    await _write(() async {
      outcome = await _repository.importExpenses(preview.newExpenses);
      return outcome.expenses;
    });
    return outcome;
  }

  /// A backup file of all loaded expenses.
  String exportBackup() {
    if (_status != ExpenseLoadStatus.ready) {
      throw StateError('Expenses are not loaded');
    }
    return encodeBackup(_expenses, exportedAt: _clock());
  }

  /// The stored data, undecoded, in a JSON envelope. Works when loading
  /// failed.
  Future<String> exportRawData() async =>
      encodeRawExport(await _repository.readRaw(), exportedAt: _clock());

  void _ensureWritable() {
    if (_status != ExpenseLoadStatus.ready) {
      throw StateError(
        'Expenses have not been loaded; refusing to write so stored data '
        'is not overwritten.',
      );
    }
    if (_hasConflict) throw const ExpenseConflictException();
  }

  Future<void> _write(Future<List<Expense>> Function() operation) {
    final result = _writeQueue.then((_) async {
      _ensureWritable();
      try {
        _expenses = await operation();
      } on ExpenseConflictException {
        _markStale();
        rethrow;
      } on ExpenseNotFoundException {
        // Deleted elsewhere: the shown list is out of date. Same treatment
        // as a conflict; the user reloads to see what is stored now.
        _markStale();
        rethrow;
      } on ExpenseStorageUnreadableException catch (e) {
        // Stored data became unreadable after loading (nothing was
        // written). Same state as a failed load: no further writes, and
        // the recovery view with the raw export.
        _loadError = e;
        _status = ExpenseLoadStatus.failed;
        _notify();
        rethrow;
      }
      _notify();
    });
    // Keep the queue alive after a failed write; the caller still receives
    // the error through [result].
    _writeQueue = result.catchError((Object _) {});
    return result;
  }

  void _markStale() {
    _hasConflict = true;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    onDispose?.call();
    super.dispose();
  }
}
