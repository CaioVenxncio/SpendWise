import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/drift/database.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/providers/expense_provider.dart';
import 'package:spendwise/repositories/drift_expense_repository.dart';
import 'package:spendwise/services/expense_storage.dart';

import '../support/date_texts.dart';
import '../support/fake_expense_storage.dart';

/// Same records, three insertion orders; partial sums leave the range in
/// some of them, the exact total (MAX − 499 cents) does not.
final _records = [
  expenseAt('max', Money.maxCents, '2026-10-01T09:00:00.000'),
  expenseAt('plus', 1, '2026-10-02T09:00:00.000'),
  expenseAt('minus', -500, '2026-10-03T09:00:00.000'),
];
final _orders = [
  [0, 1, 2],
  [1, 0, 2],
  [2, 1, 0],
];
const _expected = Money.maxCents - 499;
final _clock = DateTime(2026, 10, 15);

void main() {
  test(
    'JSON: the monthly total is the same for every insertion order',
    () async {
      for (final order in _orders) {
        final records = [for (final i in order) _records[i]];
        final storage = FakeExpenseStorage(data: encodeExpenses(records));
        final provider = ExpenseProvider(storage: storage, clock: () => _clock);
        await provider.loadExpenses();
        expect(provider.currentMonthTotal.cents, _expected, reason: '$order');
        // Read only: nothing rewritten, order kept.
        expect(storage.writeCount, 0);
        expect(provider.expenses.map((e) => e.id), records.map((e) => e.id));
      }
    },
  );

  test('Drift: the monthly total is the same for every insertion order; '
      'rows and seq untouched', () async {
    for (final order in _orders) {
      final db = SpendWiseDatabase(NativeDatabase.memory());
      try {
        final seeder = DriftExpenseRepository(db);
        await seeder.load();
        for (final i in order) {
          await seeder.add(_records[i]);
        }
        final seqBefore = await db
            .customSelect('SELECT id, seq FROM expenses ORDER BY seq')
            .get()
            .then((r) => [for (final x in r) x.data]);

        final provider = ExpenseProvider(
          repository: DriftExpenseRepository(db),
          clock: () => _clock,
        );
        await provider.loadExpenses();
        expect(provider.currentMonthTotal.cents, _expected, reason: '$order');

        final seqAfter = await db
            .customSelect('SELECT id, seq FROM expenses ORDER BY seq')
            .get()
            .then((r) => [for (final x in r) x.data]);
        expect(seqAfter, seqBefore);
        expect(provider.expenses.map((e) => e.dateText), [
          for (final i in order) _records[i].dateText,
        ]);
      } finally {
        await db.close();
      }
    }
  });
}
