import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/presentation/expense_order.dart';

import '../support/date_texts.dart';

void main() {
  test('newest first by instant, whatever the text form', () {
    final stored = [
      expenseAt('old', 1, '2026-10-01T09:00:00.000'),
      expenseAt('z', 1, '2026-10-05T10:00:00.000Z'),
      expenseAt('new', 1, '2026-10-09T09:00:00.000'),
      expenseAt('off', 1, '2026-10-03T12:00:00.000+02:00'),
    ];
    final ids = newestFirst(stored).map((e) => e.id).toList();
    expect(ids, ['new', 'z', 'off', 'old']);
  });

  test('equal instants: the later-stored record comes first', () {
    final stored = [
      expenseAt('first', 1, '2026-10-01T09:00:00.000'),
      expenseAt('second', 1, '2026-10-01T09:00:00.000'),
      // Same instant, different text.
      expenseAt('third', 1, DateTime(2026, 10, 1, 9).toUtc().toIso8601String()),
    ];
    expect(newestFirst(stored).map((e) => e.id), ['third', 'second', 'first']);
  });

  test('is presentation only: the input list is not reordered', () {
    final stored = [
      expenseAt('a', 1, '2026-10-01T09:00:00.000'),
      expenseAt('b', 1, '2026-10-02T09:00:00.000'),
    ];
    final before = stored.map((e) => e.id).toList();
    newestFirst(stored);
    expect(stored.map((e) => e.id), before);
  });

  test('is deterministic across repeated calls', () {
    final stored = [
      for (var i = 0; i < 50; i++)
        expenseAt(
          'e$i',
          i,
          '2026-10-${(i % 5 + 1).toString().padLeft(2, '0')}T09:00:00.000',
        ),
    ];
    final first = newestFirst(stored).map((e) => e.id).toList();
    for (var i = 0; i < 5; i++) {
      expect(newestFirst(stored).map((e) => e.id), first);
    }
  });

  test('empty stays empty', () {
    expect(newestFirst(const []), isEmpty);
  });
}
