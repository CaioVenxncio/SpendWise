import '../models/expense.dart';
import '../services/expense_storage.dart';

/// Expenses as loaded from storage.
class ExpenseSnapshot {
  ExpenseSnapshot(this.expenses, {this.duplicateIds = const {}});

  /// All records in storage order.
  final List<Expense> expenses;

  /// IDs shared by more than one stored record. Such records cannot be
  /// deleted individually, so deleting them is refused.
  final Set<String> duplicateIds;
}

/// Thrown when stored data changed since this instance last read or wrote
/// it, e.g. in another browser tab. Nothing was written.
class ExpenseConflictException implements Exception {
  const ExpenseConflictException();

  @override
  String toString() =>
      'ExpenseConflictException: stored expenses changed elsewhere';
}

/// Thrown when an operation would create, or act ambiguously on, more than
/// one record with the same ID. Nothing was written.
class DuplicateExpenseIdException implements Exception {
  DuplicateExpenseIdException(this.id);

  final String id;

  @override
  String toString() => 'DuplicateExpenseIdException: $id';
}

/// Thrown when an update or guarded delete names a record that is not
/// stored (for example deleted in another tab). Nothing was written.
class ExpenseNotFoundException implements Exception {
  ExpenseNotFoundException(this.id);

  final String id;

  @override
  String toString() => 'ExpenseNotFoundException: $id';
}

/// Thrown when an import would replace existing records with different
/// content. Nothing was written.
class ImportConflictException implements Exception {
  ImportConflictException(this.conflictingIds);

  final List<String> conflictingIds;

  @override
  String toString() =>
      'ImportConflictException: ${conflictingIds.length} conflicting IDs';
}

/// Result of [ExpenseRepository.importExpenses].
class ImportOutcome {
  ImportOutcome({
    required this.expenses,
    required this.added,
    required this.alreadyPresent,
  });

  /// All expenses after the import.
  final List<Expense> expenses;

  /// Number of records written.
  final int added;

  /// Records skipped because an identical record already existed.
  final int alreadyPresent;
}

/// Persistent store of expenses.
///
/// Contract for every implementation (JSON storage now, a database later):
///
/// * [load] must be called first; other methods throw [StateError] before
///   a successful load.
/// * Each mutation is all-or-nothing. When it throws, storage and the
///   repository's view are unchanged.
/// * Mutations return the complete list of expenses afterwards, so callers
///   never have to re-derive it.
/// * Records are never silently merged, rounded, replaced, or dropped.
abstract interface class ExpenseRepository {
  /// Reads all expenses. Throws a [FormatException] for undecodable data
  /// and never writes.
  Future<ExpenseSnapshot> load();

  /// Adds [expense]. Throws [DuplicateExpenseIdException] if its ID exists.
  Future<List<Expense>> add(Expense expense);

  /// Deletes the expense with [id]. Throws [DuplicateExpenseIdException] if
  /// several records share it. Does nothing if no record has it.
  ///
  /// Compatibility path, kept for existing callers: it checks only the ID,
  /// not the record's content. The JSON backend still refuses it with
  /// [ExpenseConflictException] when storage changed since this instance
  /// last read or wrote it; the Drift backend deletes whatever row has the
  /// ID now. New code (editing workflows) must use [deleteExpected].
  Future<List<Expense>> delete(String id);

  /// Deletes the stored record only if it is still exactly [expected]
  /// (every field, including the original date text).
  ///
  /// Throws [ExpenseNotFoundException] if no record has `expected.id`,
  /// [DuplicateExpenseIdException] if several do, and
  /// [ExpenseConflictException] if the record differs from [expected] or
  /// (JSON) storage changed since this instance last read or wrote it.
  Future<List<Expense>> deleteExpected(Expense expected);

  /// Replaces the stored record [expected] with [replacement], keeping its
  /// position in the list.
  ///
  /// `replacement.id` must equal `expected.id` (otherwise [ArgumentError]).
  /// Refuses with the same exceptions as [deleteExpected]. If [replacement]
  /// is identical to the stored record, nothing is written and the current
  /// list is returned.
  Future<List<Expense>> update(Expense expected, Expense replacement);

  /// Adds every record in [incoming] whose ID is new, in one write.
  ///
  /// Records identical to an existing one are skipped and counted. If any
  /// record shares an ID with a different existing record, or [incoming]
  /// repeats an ID, throws [ImportConflictException] or
  /// [DuplicateExpenseIdException] and writes nothing.
  Future<ImportOutcome> importExpenses(List<Expense> incoming);

  /// The stored data exactly as persisted, for recovery exports. Does not
  /// decode it and works even when [load] failed.
  Future<RawExpenseData> readRaw();
}

/// Undecoded stored data.
class RawExpenseData {
  RawExpenseData({
    required this.expenses,
    required this.legacyBackup,
    this.unreadable = const {},
  });

  /// From [ExpenseStorage.readStoredText].
  factory RawExpenseData.fromStored(StoredExpenseText stored) => RawExpenseData(
    expenses: stored.expenses,
    legacyBackup: stored.legacyBackup,
    unreadable: stored.unreadable,
  );

  /// Content of the main expense key, or `null` if absent or unreadable.
  final String? expenses;

  /// Content of the legacy backup key, or `null` if absent or unreadable.
  final String? legacyBackup;

  /// Values present (or possibly present) but unreadable, by key name.
  final Map<String, UnreadableStoredValue> unreadable;
}
