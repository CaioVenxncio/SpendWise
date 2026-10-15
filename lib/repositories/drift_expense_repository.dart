import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../data/drift/database.dart';
import '../domain/money.dart';
import '../models/expense.dart';
import '../services/expense_storage.dart';
import 'expense_repository.dart';

/// [ExpenseRepository] backed by the Drift/SQLite [SpendWiseDatabase].
///
/// The database is the source of truth: every mutation runs in one SQL
/// transaction and returns the rows as committed, in insertion order. IDs
/// are unique by constraint, so the duplicate states the JSON store may
/// contain cannot exist here. Writes from other tabs are not conflicts for
/// [add], [delete] and [importExpenses]: they are simply part of the data
/// the next operation returns. [update] and [deleteExpected] are guarded
/// per record instead: the row must still hold the expected values, checked
/// before and again in the statement's `WHERE` (affected rows must be 1).
///
/// Amounts are read as integer cents; totals are left to [Money] in Dart.
class DriftExpenseRepository implements ExpenseRepository {
  DriftExpenseRepository(this._db);

  final SpendWiseDatabase _db;

  bool _loaded = false;

  /// Test hook: called inside each write transaction after its statements
  /// ran and before commit. Throwing from it must roll everything back.
  @visibleForTesting
  void Function()? beforeCommit;

  @override
  Future<ExpenseSnapshot> load() async {
    final expenses = await _all();
    _loaded = true;
    return ExpenseSnapshot(expenses);
  }

  @override
  Future<List<Expense>> add(Expense expense) => _write(() async {
    if (await _find(expense.id) != null) {
      throw DuplicateExpenseIdException(expense.id);
    }
    await _db.into(_db.expenseRows).insert(_companion(expense));
  });

  @override
  Future<List<Expense>> delete(String id) => _write(() async {
    await (_db.delete(_db.expenseRows)..where((r) => r.id.equals(id))).go();
  });

  @override
  Future<List<Expense>> deleteExpected(Expense expected) => _write(() async {
    await _requireExpected(expected);
    final removed = await (_db.delete(
      _db.expenseRows,
    )..where((r) => _matches(r, expected))).go();
    if (removed != 1) throw const ExpenseConflictException();
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
    return _write(() async {
      final current = await _requireExpected(expected);
      if (sameExpense(current, replacement)) return;
      // UPDATE in place keeps `seq`, so the record keeps its position.
      final changed =
          await (_db.update(
            _db.expenseRows,
          )..where((r) => _matches(r, expected))).write(
            ExpenseRowsCompanion(
              amountCents: Value(replacement.amount.cents),
              description: Value(replacement.description),
              category: Value(replacement.category),
              occurredAt: Value(replacement.dateText),
            ),
          );
      if (changed != 1) throw const ExpenseConflictException();
    });
  }

  /// The stored record with `expected.id`, which must still be exactly
  /// [expected].
  Future<Expense> _requireExpected(Expense expected) async {
    final current = await _find(expected.id);
    if (current == null) throw ExpenseNotFoundException(expected.id);
    if (!sameExpense(current, expected)) {
      throw const ExpenseConflictException();
    }
    return current;
  }

  /// Optimistic-concurrency condition: the row still holds every field of
  /// [expected]. `IS` instead of `=` so a NULL would compare correctly; all
  /// expense columns are NOT NULL today.
  static Expression<bool> _matches($ExpenseRowsTable r, Expense expected) =>
      r.id.isValue(expected.id) &
      r.amountCents.isValue(expected.amount.cents) &
      r.description.isValue(expected.description) &
      r.category.isValue(expected.category) &
      r.occurredAt.isValue(expected.dateText);

  @override
  Future<ImportOutcome> importExpenses(List<Expense> incoming) async {
    var added = 0;
    var alreadyPresent = 0;
    final expenses = await _write(() async {
      final incomingIds = <String>{};
      final conflicts = <String>[];
      final toAdd = <Expense>[];
      for (final e in incoming) {
        if (!incomingIds.add(e.id)) throw DuplicateExpenseIdException(e.id);
        final existing = await _find(e.id);
        if (existing == null) {
          toAdd.add(e);
        } else if (sameExpense(existing, e)) {
          alreadyPresent++;
        } else {
          conflicts.add(e.id);
        }
      }
      if (conflicts.isNotEmpty) throw ImportConflictException(conflicts);
      await _db.batch((b) {
        b.insertAll(_db.expenseRows, toAdd.map(_companion).toList());
      });
      added = toAdd.length;
    });
    return ImportOutcome(
      expenses: expenses,
      added: added,
      alreadyPresent: alreadyPresent,
    );
  }

  /// All rows as JSON, read column by column without building [Expense]s,
  /// so it works even for rows the app cannot interpret.
  @override
  Future<RawExpenseData> readRaw() async {
    final rows = await _db
        .customSelect(
          'SELECT id, amount_cents, description, category, occurred_at '
          'FROM expenses ORDER BY seq',
        )
        .get();
    return RawExpenseData(
      expenses: json.encode([for (final r in rows) r.data]),
      legacyBackup: null,
    );
  }

  Future<List<Expense>> _write(Future<void> Function() statements) async {
    if (!_loaded) {
      throw StateError('Expenses must be loaded before they are changed');
    }
    return _db.transaction(() async {
      await statements();
      beforeCommit?.call();
      return _all();
    });
  }

  Future<List<Expense>> _all() async {
    final rows = await (_db.select(
      _db.expenseRows,
    )..orderBy([(r) => OrderingTerm.asc(r.seq)])).get();
    return List.unmodifiable(rows.map(_toExpense));
  }

  Future<Expense?> _find(String id) async {
    final row = await (_db.select(
      _db.expenseRows,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toExpense(row);
  }

  static Expense _toExpense(ExpenseRow row) {
    final DateTime date;
    try {
      date = DateTime.parse(row.occurredAt);
    } on FormatException {
      throw FormatException('Expense row ${row.seq}: invalid date');
    }
    return Expense(
      id: row.id,
      amount: Money.fromCents(row.amountCents),
      description: row.description,
      category: row.category,
      date: date,
      dateText: row.occurredAt,
    );
  }

  static ExpenseRowsCompanion _companion(Expense e) =>
      ExpenseRowsCompanion.insert(
        id: e.id,
        amountCents: e.amount.cents,
        description: e.description,
        category: e.category,
        occurredAt: e.dateText,
      );
}
