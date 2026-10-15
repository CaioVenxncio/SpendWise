import '../models/expense.dart';
import '../services/expense_storage.dart';
import 'expense_repository.dart';

/// [ExpenseRepository] storing all expenses as one JSON string.
///
/// Every mutation runs under [ExpenseStorage.exclusive] and first re-reads
/// storage. If the stored text differs from what this instance last read or
/// wrote, the mutation is refused with [ExpenseConflictException] instead of
/// overwriting another tab's changes.
///
/// How strong that is depends on [ExpenseStorage.lockKind]: with Web Locks,
/// the check and write are exclusive among tabs running this code; without
/// them, a write from another tab can still land between the check and the
/// write.
class JsonExpenseRepository implements ExpenseRepository {
  JsonExpenseRepository(this._storage);

  final ExpenseStorage _storage;

  bool _loaded = false;
  List<Expense> _expenses = const [];

  /// Stored text as last read or written by this instance.
  String? _knownRaw;

  /// The loaded text, if it contained legacy-format records that have not
  /// yet been backed up. Backed up before the first rewrite.
  String? _pendingLegacyBackup;

  @override
  Future<ExpenseSnapshot> load() => _storage.exclusive(() async {
    final raw = await _storage.read();
    final decoded = raw == null ? null : decodeExpenses(raw);
    _expenses = List.unmodifiable(decoded?.expenses ?? const <Expense>[]);
    _knownRaw = raw;
    _pendingLegacyBackup = decoded != null && decoded.hasLegacyRecords
        ? raw
        : null;
    _loaded = true;
    return ExpenseSnapshot(
      _expenses,
      duplicateIds: decoded?.duplicateIds ?? const {},
    );
  });

  @override
  Future<List<Expense>> add(Expense expense) => _mutate((current) {
    if (current.any((e) => e.id == expense.id)) {
      throw DuplicateExpenseIdException(expense.id);
    }
    return [...current, expense];
  });

  @override
  Future<List<Expense>> delete(String id) => _mutate((current) {
    final matches = current.where((e) => e.id == id).length;
    if (matches == 0) return null;
    if (matches > 1) throw DuplicateExpenseIdException(id);
    return current.where((e) => e.id != id).toList();
  });

  @override
  Future<List<Expense>> deleteExpected(Expense expected) => _mutate((current) {
    final index = _indexOfExpected(current, expected);
    return [...current]..removeAt(index);
  });

  @override
  Future<List<Expense>> update(Expense expected, Expense replacement) async {
    if (replacement.id != expected.id) {
      throw ArgumentError.value(
        replacement.id,
        'replacement.id',
        'must equal the expected ID',
      );
    }
    return _mutate((current) {
      final index = _indexOfExpected(current, expected);
      if (sameExpense(current[index], replacement)) return null;
      return [...current]..[index] = replacement;
    });
  }

  /// Position of the only record with `expected.id`, which must still be
  /// exactly [expected].
  static int _indexOfExpected(List<Expense> current, Expense expected) {
    var index = -1;
    for (var i = 0; i < current.length; i++) {
      if (current[i].id != expected.id) continue;
      if (index != -1) throw DuplicateExpenseIdException(expected.id);
      index = i;
    }
    if (index == -1) throw ExpenseNotFoundException(expected.id);
    if (!sameExpense(current[index], expected)) {
      throw const ExpenseConflictException();
    }
    return index;
  }

  @override
  Future<ImportOutcome> importExpenses(List<Expense> incoming) async {
    var added = 0;
    var alreadyPresent = 0;
    final expenses = await _mutate((current) {
      final byId = <String, Expense>{};
      for (final e in current) {
        byId.putIfAbsent(e.id, () => e);
      }
      final storedIds = current.map((e) => e.id).toList();
      final incomingIds = <String>{};
      final conflicts = <String>[];
      final toAdd = <Expense>[];
      for (final e in incoming) {
        if (!incomingIds.add(e.id)) throw DuplicateExpenseIdException(e.id);
        final existing = byId[e.id];
        if (existing == null) {
          toAdd.add(e);
        } else if (storedIds.where((id) => id == e.id).length == 1 &&
            sameExpense(existing, e)) {
          alreadyPresent++;
        } else {
          conflicts.add(e.id);
        }
      }
      if (conflicts.isNotEmpty) throw ImportConflictException(conflicts);
      added = toAdd.length;
      return toAdd.isEmpty ? null : [...current, ...toAdd];
    });
    return ImportOutcome(
      expenses: expenses,
      added: added,
      alreadyPresent: alreadyPresent,
    );
  }

  @override
  Future<RawExpenseData> readRaw() async =>
      RawExpenseData.fromStored(await _storage.readStoredText());

  /// Applies [change] under the storage lock. [change] returns the new list,
  /// or `null` when nothing needs to be written.
  Future<List<Expense>> _mutate(
    List<Expense>? Function(List<Expense> current) change,
  ) => _storage.exclusive(() async {
    if (!_loaded) {
      throw StateError('Expenses must be loaded before they are changed');
    }
    final raw = await _storage.read();
    if (raw != _knownRaw) throw const ExpenseConflictException();

    final updated = change(_expenses);
    if (updated == null) return _expenses;

    final legacy = _pendingLegacyBackup;
    if (legacy != null) {
      // Legacy data is only rewritten in the cents format after an
      // untouched copy has been saved.
      await _storage.backupLegacyData(legacy);
      _pendingLegacyBackup = null;
    }
    final encoded = encodeExpenses(updated);
    await _storage.write(encoded);
    _knownRaw = encoded;
    _expenses = List.unmodifiable(updated);
    return _expenses;
  });
}
