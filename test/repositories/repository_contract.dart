import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/backup/expense_backup.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/repositories/expense_repository.dart';

/// A backend under test, created fresh for every test.
abstract class RepositoryHarness {
  /// Creates storage containing [seed] (in order) and returns a repository
  /// on it that has not been loaded yet.
  Future<ExpenseRepository> open({List<Expense> seed = const []});

  /// Another repository on the same storage, as a second tab would have.
  ExpenseRepository secondInstance();

  /// While on, every write fails after its changes were prepared.
  void failWrites(bool on);

  /// A counter that grows with every persisted change (storage writes,
  /// changed rows), to prove that an operation wrote nothing.
  Future<int> persistentWrites();

  Future<void> dispose();
}

Expense contractExpense(
  String id,
  int cents, {
  String description = 'd',
  String? dateText,
}) {
  final text = dateText ?? '2024-03-01T12:00:00.000';
  return Expense(
    id: id,
    amount: Money.fromCents(cents),
    description: description,
    category: 'General',
    date: DateTime.parse(text),
    dateText: text,
  );
}

List<String> _ids(List<Expense> es) => es.map((e) => e.id).toList();

List<Map<String, dynamic>> _maps(List<Expense> es) =>
    es.map((e) => e.toMap()).toList();

/// `null` if [operation] succeeds, otherwise the error it threw.
Future<Object?> _outcome(Future<Object?> operation) =>
    operation.then<Object?>((_) => null, onError: (Object e) => e);

/// Behaviour every [ExpenseRepository] must have.
void runRepositoryContract(
  String backend,
  RepositoryHarness Function() createHarness,
) {
  group('$backend repository contract', () {
    late RepositoryHarness h;

    setUp(() => h = createHarness());
    tearDown(() => h.dispose());

    Future<ExpenseRepository> loaded([List<Expense> seed = const []]) async {
      final repo = await h.open(seed: seed);
      await repo.load();
      return repo;
    }

    test('empty storage loads as empty', () async {
      final repo = await h.open();
      expect((await repo.load()).expenses, isEmpty);
    });

    test('exact cents and verbatim ISO dates survive a round trip', () async {
      final seed = [
        contractExpense('max', Money.maxCents),
        contractExpense('min', Money.minCents),
        contractExpense('zero', 0),
        contractExpense('cent', 1),
        contractExpense('z', 1250, dateText: '2023-12-31T23:59:59.000Z'),
        contractExpense('off', 5, dateText: '2026-10-14T00:00:00.000+02:00'),
        contractExpense('short', 7, dateText: '2024-02-29T08:00:00'),
      ];
      final repo = await loaded(seed);

      // Rewrite everything once, then read through a fresh instance.
      await repo.add(contractExpense('new', 3));
      final reread = (await h.secondInstance().load()).expenses;

      expect(_maps(reread), [
        ..._maps(seed),
        contractExpense('new', 3).toMap(),
      ]);
      expect(reread.first.amount.cents, 9007199254740991);
      expect(reread[5].dateText, '2026-10-14T00:00:00.000+02:00');
    });

    test('totals are exact in Dart and overflow is reported', () async {
      final repo = await loaded([
        contractExpense('a', 10),
        contractExpense('b', 20),
      ]);
      final expenses = (await repo.load()).expenses;
      expect(Money.sum(expenses.map((e) => e.amount)), Money.fromCents(30));

      await repo.add(contractExpense('big', Money.maxCents));
      final all = (await repo.load()).expenses;
      expect(
        () => Money.sum(all.map((e) => e.amount)),
        throwsA(isA<MoneyOverflowException>()),
      );
    });

    test('changes are refused before load', () async {
      final repo = await h.open();
      await expectLater(repo.add(contractExpense('a', 1)), throwsStateError);
    });

    test('add appends and persists', () async {
      final repo = await loaded([contractExpense('a', 1)]);

      expect(_ids(await repo.add(contractExpense('b', 2))), ['a', 'b']);
      expect(_ids((await h.secondInstance().load()).expenses), ['a', 'b']);
    });

    test('add refuses an existing ID and changes nothing', () async {
      final repo = await loaded([contractExpense('a', 1)]);

      await expectLater(
        repo.add(contractExpense('a', 999)),
        throwsA(isA<DuplicateExpenseIdException>()),
      );
      final stored = (await h.secondInstance().load()).expenses;
      expect(_maps(stored), _maps([contractExpense('a', 1)]));
    });

    test(
      'delete removes only the matching record; a missing ID is a no-op',
      () async {
        final repo = await loaded([
          contractExpense('a', 1),
          contractExpense('b', 2),
        ]);

        expect(_ids(await repo.delete('a')), ['b']);
        expect(_ids(await repo.delete('zzz')), ['b']);
        expect(_ids((await h.secondInstance().load()).expenses), ['b']);
      },
    );

    test('order is insertion order, stable across deletes', () async {
      final repo = await loaded();
      for (final id in ['a', 'b', 'c']) {
        await repo.add(contractExpense(id, 1));
      }
      await repo.delete('b');
      await repo.add(contractExpense('d', 1));
      await repo.add(contractExpense('b', 1));

      expect(_ids((await h.secondInstance().load()).expenses), [
        'a',
        'c',
        'd',
        'b',
      ]);
    });

    group('import', () {
      test('adds new records, skips identical ones', () async {
        final repo = await loaded([contractExpense('a', 1)]);

        final outcome = await repo.importExpenses([
          contractExpense('a', 1),
          contractExpense('b', 2),
          contractExpense('c', 3),
        ]);

        expect(outcome.added, 2);
        expect(outcome.alreadyPresent, 1);
        expect(_ids(outcome.expenses), ['a', 'b', 'c']);
        expect(_ids((await h.secondInstance().load()).expenses), [
          'a',
          'b',
          'c',
        ]);
      });

      test('a conflicting record blocks the whole import', () async {
        final repo = await loaded([contractExpense('a', 1)]);

        await expectLater(
          repo.importExpenses([
            contractExpense('b', 2),
            contractExpense('a', 999),
          ]),
          throwsA(
            isA<ImportConflictException>().having(
              (e) => e.conflictingIds,
              'ids',
              ['a'],
            ),
          ),
        );
        expect(_ids((await h.secondInstance().load()).expenses), ['a']);
      });

      test('a different date text for the same ID is a conflict', () async {
        final repo = await loaded([contractExpense('a', 1)]);
        await expectLater(
          repo.importExpenses([
            contractExpense('a', 1, dateText: '2024-03-01T12:00:00.000Z'),
          ]),
          throwsA(isA<ImportConflictException>()),
        );
      });

      test('repeated IDs in the input are refused', () async {
        final repo = await loaded();
        await expectLater(
          repo.importExpenses([
            contractExpense('b', 2),
            contractExpense('b', 2),
          ]),
          throwsA(isA<DuplicateExpenseIdException>()),
        );
        expect((await h.secondInstance().load()).expenses, isEmpty);
      });

      test('nothing new leaves data as it was', () async {
        final repo = await loaded([contractExpense('a', 1)]);
        final outcome = await repo.importExpenses([contractExpense('a', 1)]);
        expect(outcome.added, 0);
        expect(_ids(outcome.expenses), ['a']);
      });
    });

    group('failures roll back', () {
      test('a failed add changes nothing and later writes work', () async {
        final repo = await loaded([contractExpense('a', 1)]);
        h.failWrites(true);
        await expectLater(repo.add(contractExpense('b', 2)), throwsA(anything));
        h.failWrites(false);

        expect(_ids((await h.secondInstance().load()).expenses), ['a']);
        expect(_ids(await repo.add(contractExpense('c', 3))), ['a', 'c']);
      });

      test('a failed import writes none of its records', () async {
        final repo = await loaded([contractExpense('a', 1)]);
        h.failWrites(true);
        await expectLater(
          repo.importExpenses([
            contractExpense('b', 2),
            contractExpense('c', 3),
            contractExpense('d', 4),
          ]),
          throwsA(anything),
        );
        h.failWrites(false);

        expect(_ids((await h.secondInstance().load()).expenses), ['a']);
      });

      test('a failed delete keeps the record', () async {
        final repo = await loaded([contractExpense('a', 1)]);
        h.failWrites(true);
        await expectLater(repo.delete('a'), throwsA(anything));
        h.failWrites(false);

        expect(_ids((await h.secondInstance().load()).expenses), ['a']);
      });
    });

    group('update', () {
      test('replaces the record in place and persists it', () async {
        final seed = [
          contractExpense('a', 1),
          contractExpense('b', 2),
          contractExpense('c', 3),
        ];
        final repo = await loaded(seed);
        final edited = seed[1].edited(
          amount: Money.fromCents(250),
          description: 'new',
          category: 'Food',
        );

        final result = await repo.update(seed[1], edited);

        expect(_ids(result), ['a', 'b', 'c']);
        expect(_maps(result), _maps([seed[0], edited, seed[2]]));
        final stored = (await h.secondInstance().load()).expenses;
        expect(_maps(stored), _maps([seed[0], edited, seed[2]]));
      });

      test('an identical replacement writes nothing', () async {
        final seed = [contractExpense('a', 1)];
        final repo = await loaded(seed);
        final before = await h.persistentWrites();

        final result = await repo.update(seed[0], seed[0].edited());

        expect(_maps(result), _maps(seed));
        expect(await h.persistentWrites(), before);
      });

      test('a stale expected record is refused and nothing changes', () async {
        final seed = [contractExpense('a', 1)];
        final repo = await loaded(seed);
        final stale = contractExpense('a', 2);

        await expectLater(
          repo.update(stale, contractExpense('a', 3)),
          throwsA(isA<ExpenseConflictException>()),
        );
        expect(_maps((await h.secondInstance().load()).expenses), _maps(seed));
      });

      test('a different date text in expected is stale', () async {
        final seed = [contractExpense('a', 1)];
        final repo = await loaded(seed);
        final sameInstantOtherText = contractExpense(
          'a',
          1,
          dateText: '2024-03-01T12:00:00',
        );

        await expectLater(
          repo.update(sameInstantOtherText, contractExpense('a', 9)),
          throwsA(isA<ExpenseConflictException>()),
        );
      });

      test('an update by another instance makes this one stale; reloading '
          'allows a deliberate retry', () async {
        final original = contractExpense('a', 1);
        final tabA = await loaded([original]);
        final tabB = h.secondInstance();
        await tabB.load();

        final fromB = original.edited(description: 'from B');
        await tabB.update(original, fromB);
        await expectLater(
          tabA.update(original, original.edited(description: 'from A')),
          throwsA(isA<ExpenseConflictException>()),
        );
        expect(
          _maps((await h.secondInstance().load()).expenses),
          _maps([fromB]),
        );

        final current = (await tabA.load()).expenses.single;
        final fromA = current.edited(description: 'from A');
        expect(_maps(await tabA.update(current, fromA)), _maps([fromA]));
      });

      test('concurrent updates of one record: exactly one wins', () async {
        final original = contractExpense('a', 1);
        final tabA = await loaded([original]);
        final tabB = h.secondInstance();
        await tabB.load();
        final fromA = original.edited(amount: Money.fromCents(100));
        final fromB = original.edited(amount: Money.fromCents(200));

        final outcomes = await Future.wait([
          _outcome(tabA.update(original, fromA)),
          _outcome(tabB.update(original, fromB)),
        ]);

        expect(outcomes.where((o) => o == null), hasLength(1));
        expect(outcomes.whereType<ExpenseConflictException>(), hasLength(1));
        final winner = outcomes[0] == null ? fromA : fromB;
        expect(
          _maps((await h.secondInstance().load()).expenses),
          _maps([winner]),
        );
      });

      test('concurrent updates of different records keep both', () async {
        final a = contractExpense('a', 1);
        final b = contractExpense('b', 2);
        final tabA = await loaded([a, b]);
        final tabB = h.secondInstance();
        await tabB.load();
        final newA = a.edited(description: 'A');
        final newB = b.edited(description: 'B');

        await tabA.update(a, newA);
        try {
          await tabB.update(b, newB);
        } on ExpenseConflictException {
          // JSON refuses any stale writer; retry after reloading.
          await tabB.load();
          await tabB.update(b, newB);
        }

        expect(
          _maps((await h.secondInstance().load()).expenses),
          _maps([newA, newB]),
        );
      });

      test('a missing record is refused', () async {
        final repo = await loaded([contractExpense('a', 1)]);
        final before = await h.persistentWrites();

        await expectLater(
          repo.update(contractExpense('zzz', 1), contractExpense('zzz', 2)),
          throwsA(
            isA<ExpenseNotFoundException>().having((e) => e.id, 'id', 'zzz'),
          ),
        );
        expect(await h.persistentWrites(), before);
      });

      test('the ID cannot change', () async {
        final seed = [contractExpense('a', 1)];
        final repo = await loaded(seed);

        await expectLater(
          repo.update(seed[0], contractExpense('b', 1)),
          throwsArgumentError,
        );
        expect(_maps((await h.secondInstance().load()).expenses), _maps(seed));
      });

      test('exact Money boundaries are stored', () async {
        final original = contractExpense('a', 1);
        final repo = await loaded([original]);

        final atMax = original.edited(amount: Money.fromCents(Money.maxCents));
        await repo.update(original, atMax);
        expect(
          (await h.secondInstance().load()).expenses.single.amount.cents,
          9007199254740991,
        );
        final atMin = atMax.edited(amount: Money.fromCents(Money.minCents));
        await repo.update(atMax, atMin);
        expect(
          (await h.secondInstance().load()).expenses.single.amount.cents,
          -9007199254740991,
        );
      });

      test('original date texts survive edits that keep the day', () async {
        final seed = [
          contractExpense('z', 1, dateText: '2023-12-31T23:59:59.000Z'),
          contractExpense('off', 2, dateText: '2026-10-14T00:00:00.000+02:00'),
          contractExpense('short', 3, dateText: '2024-02-29T08:00:00'),
        ];
        final repo = await loaded(seed);

        for (final e in seed) {
          await repo.update(
            e,
            e.edited(description: 'changed', day: e.date.toLocal()),
          );
        }

        final stored = (await h.secondInstance().load()).expenses;
        expect(stored.map((e) => e.dateText), [
          '2023-12-31T23:59:59.000Z',
          '2026-10-14T00:00:00.000+02:00',
          '2024-02-29T08:00:00',
        ]);
        expect(stored.map((e) => e.description).toSet(), {'changed'});
      });

      test('a changed day is stored in the local convention', () async {
        final original = contractExpense('a', 1);
        final repo = await loaded([original]);

        final moved = original.edited(day: DateTime(2024, 3, 5));
        await repo.update(original, moved);

        final stored = (await h.secondInstance().load()).expenses.single;
        expect(stored.dateText, '2024-03-05T12:00:00.000');
      });

      test('a failed update changes nothing and later updates work', () async {
        final original = contractExpense('a', 1);
        final repo = await loaded([original]);
        final edited = original.edited(description: 'x');

        h.failWrites(true);
        await expectLater(repo.update(original, edited), throwsA(anything));
        h.failWrites(false);

        expect(
          _maps((await h.secondInstance().load()).expenses),
          _maps([original]),
        );
        expect(_maps(await repo.update(original, edited)), _maps([edited]));
      });

      test('an edited list survives a backup export and import', () async {
        final seed = [
          contractExpense('a', 1),
          contractExpense('b', 2, dateText: '2026-10-14T00:00:00.000+02:00'),
        ];
        final repo = await loaded(seed);
        await repo.update(
          seed[1],
          seed[1].edited(amount: Money.fromCents(Money.maxCents)),
        );
        final edited = (await h.secondInstance().load()).expenses;

        final file = utf8.encode(
          encodeBackup(edited, exportedAt: DateTime.utc(2026, 10, 15)),
        );
        final parsed = parseBackup(file);
        expect(_maps(parsed.expenses), _maps(edited));

        // Re-importing into the same data: everything already present.
        final again = await repo.importExpenses(parsed.expenses);
        expect(again.added, 0);
        expect(again.alreadyPresent, 2);

        // Importing into empty storage restores the edited records exactly.
        final other = createHarness();
        try {
          final empty = await other.open();
          await empty.load();
          final restored = await empty.importExpenses(parsed.expenses);
          expect(_maps(restored.expenses), _maps(edited));
        } finally {
          await other.dispose();
        }
      });
    });

    group('deleteExpected', () {
      test('removes the unchanged record and keeps order', () async {
        final seed = [
          contractExpense('a', 1),
          contractExpense('b', 2),
          contractExpense('c', 3),
        ];
        final repo = await loaded(seed);

        expect(_ids(await repo.deleteExpected(seed[1])), ['a', 'c']);
        expect(_ids((await h.secondInstance().load()).expenses), ['a', 'c']);
      });

      test('a record changed since loading is not deleted', () async {
        final original = contractExpense('a', 1);
        final tabA = await loaded([original]);
        final tabB = h.secondInstance();
        await tabB.load();
        final fromB = original.edited(amount: Money.fromCents(5));
        await tabB.update(original, fromB);

        await expectLater(
          tabA.deleteExpected(original),
          throwsA(isA<ExpenseConflictException>()),
        );
        expect(
          _maps((await h.secondInstance().load()).expenses),
          _maps([fromB]),
        );
      });

      test('a stale expected record is refused', () async {
        final repo = await loaded([contractExpense('a', 1)]);
        await expectLater(
          repo.deleteExpected(contractExpense('a', 2)),
          throwsA(isA<ExpenseConflictException>()),
        );
        expect(_ids((await h.secondInstance().load()).expenses), ['a']);
      });

      test('a missing record is refused', () async {
        final repo = await loaded([contractExpense('a', 1)]);
        await expectLater(
          repo.deleteExpected(contractExpense('zzz', 1)),
          throwsA(isA<ExpenseNotFoundException>()),
        );
        expect(_ids((await h.secondInstance().load()).expenses), ['a']);
      });

      test('concurrent update and delete: never both, never lost', () async {
        final original = contractExpense('a', 1);
        final tabA = await loaded([original]);
        final tabB = h.secondInstance();
        await tabB.load();
        final edited = original.edited(description: 'kept');

        final outcomes = await Future.wait([
          _outcome(tabA.update(original, edited)),
          _outcome(tabB.deleteExpected(original)),
        ]);

        expect(outcomes.where((o) => o == null), hasLength(1));
        expect(
          outcomes.where(
            (o) =>
                o is ExpenseConflictException || o is ExpenseNotFoundException,
          ),
          hasLength(1),
        );
        final stored = (await h.secondInstance().load()).expenses;
        if (outcomes[0] == null) {
          expect(_maps(stored), _maps([edited]));
        } else {
          expect(stored, isEmpty);
        }
      });

      test('an update after a delete elsewhere is refused', () async {
        final original = contractExpense('a', 1);
        final tabA = await loaded([original]);
        final tabB = h.secondInstance();
        await tabB.load();
        await tabB.deleteExpected(original);

        await expectLater(
          tabA.update(original, original.edited(description: 'x')),
          throwsA(
            anyOf(
              isA<ExpenseConflictException>(),
              isA<ExpenseNotFoundException>(),
            ),
          ),
        );
        expect((await h.secondInstance().load()).expenses, isEmpty);
      });

      test('a failed guarded delete keeps the record', () async {
        final original = contractExpense('a', 1);
        final repo = await loaded([original]);
        h.failWrites(true);
        await expectLater(repo.deleteExpected(original), throwsA(anything));
        h.failWrites(false);

        expect(_ids((await h.secondInstance().load()).expenses), ['a']);
        expect(await repo.deleteExpected(original), isEmpty);
      });
    });

    test('two instances never lose a committed record', () async {
      final tabA = await loaded([contractExpense('a', 1)]);
      final tabB = h.secondInstance();
      await tabB.load();

      await tabA.add(contractExpense('from-a', 1));
      try {
        await tabB.add(contractExpense('from-b', 2));
      } on ExpenseConflictException {
        // A backend may refuse a stale writer; it must then succeed after
        // reloading, keeping the other instance's record.
        await tabB.load();
        await tabB.add(contractExpense('from-b', 2));
      }

      expect(_ids((await h.secondInstance().load()).expenses), [
        'a',
        'from-a',
        'from-b',
      ]);
    });

    test('readRaw exposes stored data', () async {
      final repo = await loaded([contractExpense('a', 1250)]);
      final raw = await repo.readRaw();
      expect(raw.expenses, contains('a'));
      expect(raw.expenses, contains('1250'));
    });
  });
}
