import '../models/expense.dart';

/// [expenses] in display order: newest first.
///
/// Presentation only: the stored order (JSON list, Drift `seq`) is never
/// changed. Expenses are compared by instant ([Expense.date], which orders
/// local calendar days the same way); equal instants keep the later-stored
/// record first, so the order is deterministic and stable across reloads.
List<Expense> newestFirst(List<Expense> expenses) {
  final indices = List<int>.generate(expenses.length, (i) => i);
  indices.sort((a, b) {
    final byDate = expenses[b].date.compareTo(expenses[a].date);
    return byDate != 0 ? byDate : b.compareTo(a);
  });
  return [for (final i in indices) expenses[i]];
}
