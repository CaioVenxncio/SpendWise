import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/repositories/expense_repository.dart';
import 'package:spendwise/repositories/json_expense_repository.dart';
import 'package:spendwise/services/expense_storage.dart';

import '../support/fake_expense_storage.dart';

Expense _e(String id, int cents, {String description = 'x'}) => Expense(
  id: id,
  amount: Money.fromCents(cents),
  description: description,
  category: 'General',
  date: DateTime(2024, 3, 1),
);

Future<(FakeExpenseStorage, JsonExpenseRepository)> _loaded(
  List<Expense> expenses,
) async {
  final storage = FakeExpenseStorage(
    data: expenses.isEmpty ? null : encodeExpenses(expenses),
  );
  final repo = JsonExpenseRepository(storage);
  await repo.load();
  return (storage, repo);
}

List<String> _ids(List<Expense> es) => es.map((e) => e.id).toList();

void main() {
  group('load', () {
    test(
      'keeps every record and reports duplicate IDs without writing',
      () async {
        final storage = FakeExpenseStorage(
          data: encodeExpenses([_e('a', 1), _e('b', 2), _e('a', 3)]),
        );
        final before = storage.data;

        final snapshot = await JsonExpenseRepository(storage).load();

        expect(_ids(snapshot.expenses), ['a', 'b', 'a']);
        expect(snapshot.duplicateIds, {'a'});
        expect(storage.data, before);
        expect(storage.writeCount, 0);
      },
    );

    test('mutations before load are refused', () async {
      final repo = JsonExpenseRepository(FakeExpenseStorage());
      await expectLater(repo.add(_e('a', 1)), throwsStateError);
    });
  });

  group('add', () {
    test('appends and persists', () async {
      final (storage, repo) = await _loaded([_e('a', 1)]);

      final result = await repo.add(_e('b', 2));

      expect(_ids(result), ['a', 'b']);
      expect(_ids(decodeExpenses(storage.data!).expenses), ['a', 'b']);
    });

    test('refuses an existing ID without writing', () async {
      final (storage, repo) = await _loaded([_e('a', 1)]);

      await expectLater(
        repo.add(_e('a', 999)),
        throwsA(isA<DuplicateExpenseIdException>()),
      );
      expect(storage.writeCount, 0);
    });
  });

  group('delete', () {
    test('removes exactly one matching record', () async {
      final (storage, repo) = await _loaded([_e('a', 1), _e('b', 2)]);

      expect(_ids(await repo.delete('a')), ['b']);
      expect(_ids(decodeExpenses(storage.data!).expenses), ['b']);
    });

    test('refuses an ID shared by several records', () async {
      final (storage, repo) = await _loaded([
        _e('a', 1),
        _e('b', 2),
        _e('a', 3),
      ]);
      final before = storage.data;

      await expectLater(
        repo.delete('a'),
        throwsA(isA<DuplicateExpenseIdException>()),
      );
      expect(storage.data, before);
      expect(storage.writeCount, 0);
    });

    test('a missing ID is a no-op without writing', () async {
      final (storage, repo) = await _loaded([_e('a', 1)]);

      expect(_ids(await repo.delete('zzz')), ['a']);
      expect(storage.writeCount, 0);
    });
  });

  group('conflict detection', () {
    test('another writer after load blocks add, delete and import', () async {
      final (storage, repo) = await _loaded([_e('a', 1)]);
      final external = encodeExpenses([_e('a', 1), _e('other-tab', 5)]);
      storage.data = external;

      for (final op in <Future<Object?> Function()>[
        () => repo.add(_e('b', 2)),
        () => repo.delete('a'),
        () => repo.importExpenses([_e('c', 3)]),
      ]) {
        await expectLater(op(), throwsA(isA<ExpenseConflictException>()));
      }
      expect(storage.data, external);
      expect(storage.writeCount, 0);
    });

    test('data removed elsewhere is a conflict', () async {
      final (storage, repo) = await _loaded([_e('a', 1)]);
      storage.data = null;

      await expectLater(
        repo.add(_e('b', 2)),
        throwsA(isA<ExpenseConflictException>()),
      );
      expect(storage.data, isNull);
    });

    test('data created elsewhere after an empty load is a conflict', () async {
      final (storage, repo) = await _loaded([]);
      storage.data = encodeExpenses([_e('other-tab', 5)]);

      await expectLater(
        repo.add(_e('b', 2)),
        throwsA(isA<ExpenseConflictException>()),
      );
    });

    test("this instance's own writes are not conflicts", () async {
      final (_, repo) = await _loaded([]);

      await repo.add(_e('a', 1));
      await repo.add(_e('b', 2));
      await repo.delete('a');

      expect(_ids((await repo.load()).expenses), ['b']);
    });

    test(
      'two instances on one storage (two tabs): second writer is blocked',
      () async {
        final storage = FakeExpenseStorage(data: encodeExpenses([_e('a', 1)]));
        final tabA = JsonExpenseRepository(storage);
        final tabB = JsonExpenseRepository(storage);
        await tabA.load();
        await tabB.load();

        await tabA.add(_e('from-a', 1));
        await expectLater(
          tabB.add(_e('from-b', 2)),
          throwsA(isA<ExpenseConflictException>()),
        );

        expect(_ids(decodeExpenses(storage.data!).expenses), ['a', 'from-a']);

        // After reloading, tab B can write and keeps tab A's record.
        await tabB.load();
        await tabB.add(_e('from-b', 2));
        expect(_ids(decodeExpenses(storage.data!).expenses), [
          'a',
          'from-a',
          'from-b',
        ]);
      },
    );

    test('a failed write can be retried without a false conflict', () async {
      final (storage, repo) = await _loaded([_e('a', 1)]);
      storage.failWrites = true;
      await expectLater(
        repo.add(_e('b', 2)),
        throwsA(isA<ExpenseStorageException>()),
      );

      storage.failWrites = false;
      expect(_ids(await repo.add(_e('b', 2))), ['a', 'b']);
    });
  });

  group('importExpenses', () {
    test('adds only new records in a single write', () async {
      final (storage, repo) = await _loaded([_e('a', 1)]);

      final outcome = await repo.importExpenses([
        _e('a', 1),
        _e('b', 2),
        _e('c', 3),
      ]);

      expect(outcome.added, 2);
      expect(outcome.alreadyPresent, 1);
      expect(_ids(outcome.expenses), ['a', 'b', 'c']);
      expect(storage.writeCount, 1);
    });

    test('a conflicting record blocks the whole import', () async {
      final (storage, repo) = await _loaded([_e('a', 1)]);
      final before = storage.data;

      await expectLater(
        repo.importExpenses([_e('b', 2), _e('a', 999)]),
        throwsA(
          isA<ImportConflictException>().having(
            (e) => e.conflictingIds,
            'ids',
            ['a'],
          ),
        ),
      );
      expect(storage.data, before);
      expect(storage.writeCount, 0);
      expect(_ids((await repo.load()).expenses), ['a']);
    });

    test(
      'an identical record whose stored ID is duplicated conflicts',
      () async {
        final (storage, repo) = await _loaded([_e('a', 1), _e('a', 1)]);

        await expectLater(
          repo.importExpenses([_e('a', 1)]),
          throwsA(isA<ImportConflictException>()),
        );
        expect(storage.writeCount, 0);
      },
    );

    test('repeated IDs in the input are refused', () async {
      final (storage, repo) = await _loaded([]);

      await expectLater(
        repo.importExpenses([_e('b', 2), _e('b', 2)]),
        throwsA(isA<DuplicateExpenseIdException>()),
      );
      expect(storage.writeCount, 0);
    });

    test('nothing new means no write', () async {
      final (storage, repo) = await _loaded([_e('a', 1)]);

      final outcome = await repo.importExpenses([_e('a', 1)]);

      expect(outcome.added, 0);
      expect(storage.writeCount, 0);
    });

    test('legacy data is backed up before the import rewrites it', () async {
      const legacy =
          '[{"id":"a","amount":12.5,"description":"x","category":"y",'
          '"date":"2024-03-10T12:00:00.000"}]';
      final storage = FakeExpenseStorage(data: legacy);
      final repo = JsonExpenseRepository(storage);
      await repo.load();

      await repo.importExpenses([_e('b', 2)]);

      expect(storage.legacyBackup, legacy);
      expect(decodeExpenses(storage.data!).hasLegacyRecords, isFalse);
    });
  });

  group('update and deleteExpected', () {
    test('records sharing an ID are never updated or deleted', () async {
      final (storage, repo) = await _loaded([
        _e('a', 1),
        _e('b', 2),
        _e('a', 1),
      ]);
      final before = storage.data;

      await expectLater(
        repo.update(_e('a', 1), _e('a', 5)),
        throwsA(isA<DuplicateExpenseIdException>()),
      );
      await expectLater(
        repo.deleteExpected(_e('a', 1)),
        throwsA(isA<DuplicateExpenseIdException>()),
      );
      expect(storage.data, before);
      expect(storage.writeCount, 0);
      // The unique record next to them can still be edited.
      expect(_ids(await repo.update(_e('b', 2), _e('b', 3))), ['a', 'b', 'a']);
    });

    test(
      'legacy data is backed up before the first update rewrites it',
      () async {
        const legacy =
            '[{"id":"a","amount":12.5,"description":"x","category":"y",'
            '"date":"2024-03-10T12:00:00.000"}]';
        final storage = FakeExpenseStorage(data: legacy);
        final repo = JsonExpenseRepository(storage);
        final original = (await repo.load()).expenses.single;
        expect(original.amount.cents, 1250);

        await repo.update(original, original.edited(description: 'edited'));

        expect(storage.backupCount, 1);
        expect(storage.legacyBackup, legacy);
        expect(
          storage.data,
          '[{"id":"a","amountCents":1250,"description":"edited","category":"y",'
          '"date":"2024-03-10T12:00:00.000"}]',
        );
      },
    );

    test('an identical update of legacy data writes no backup', () async {
      const legacy =
          '[{"id":"a","amount":12.5,"description":"x","category":"y",'
          '"date":"2024-03-10T12:00:00.000"}]';
      final storage = FakeExpenseStorage(data: legacy);
      final repo = JsonExpenseRepository(storage);
      final original = (await repo.load()).expenses.single;

      await repo.update(original, original.edited());

      expect(storage.data, legacy);
      expect(storage.backupCount, 0);
      expect(storage.writeCount, 0);
    });

    test('a failed legacy backup blocks the update', () async {
      const legacy =
          '[{"id":"a","amount":12.5,"description":"x","category":"y",'
          '"date":"2024-03-10T12:00:00.000"}]';
      final storage = FakeExpenseStorage(data: legacy)..failBackups = true;
      final repo = JsonExpenseRepository(storage);
      final original = (await repo.load()).expenses.single;

      await expectLater(
        repo.update(original, original.edited(description: 'edited')),
        throwsA(isA<ExpenseStorageException>()),
      );
      expect(storage.data, legacy);
      expect(storage.writeCount, 0);
    });

    test('a write by another tab refuses even an update of another record '
        'and leaves memory and storage unchanged', () async {
      final (storage, repo) = await _loaded([_e('a', 1), _e('b', 2)]);
      final mine = storage.data;
      final other = encodeExpenses([_e('a', 1), _e('b', 2), _e('c', 3)]);
      storage.data = other;

      await expectLater(
        repo.update(_e('a', 1), _e('a', 9)),
        throwsA(isA<ExpenseConflictException>()),
      );
      await expectLater(
        repo.deleteExpected(_e('a', 1)),
        throwsA(isA<ExpenseConflictException>()),
      );
      // A no-op is refused too: this instance's view is out of date.
      await expectLater(
        repo.update(_e('a', 1), _e('a', 1)),
        throwsA(isA<ExpenseConflictException>()),
      );
      expect(storage.data, other);
      expect(storage.writeCount, 0);

      // The in-memory view was not replaced: once storage holds what this
      // instance last saw again, it continues from that state.
      storage.data = mine;
      expect(_ids(await repo.update(_e('a', 1), _e('a', 9))), ['a', 'b']);
    });

    test('a write after this instance\'s update stops its next one', () async {
      final (storage, repo) = await _loaded([_e('a', 1)]);
      await repo.update(_e('a', 1), _e('a', 2));
      storage.data = encodeExpenses([_e('a', 7)]);

      await expectLater(
        repo.update(_e('a', 2), _e('a', 3)),
        throwsA(isA<ExpenseConflictException>()),
      );
      expect(storage.data, encodeExpenses([_e('a', 7)]));
    });
  });

  test('readRaw returns stored text even when it cannot be decoded', () async {
    final storage = FakeExpenseStorage(data: '{not json')
      ..legacyBackup = '[legacy]';
    final repo = JsonExpenseRepository(storage);
    await expectLater(repo.load(), throwsFormatException);

    final raw = await repo.readRaw();

    expect(raw.expenses, '{not json');
    expect(raw.legacyBackup, '[legacy]');
    expect(storage.writeCount, 0);
  });
}
