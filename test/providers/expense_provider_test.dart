import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/providers/expense_provider.dart';
import 'package:spendwise/services/expense_storage.dart';

import '../support/fake_expense_storage.dart';

Expense _expense(String id, int cents, DateTime date) => Expense(
  id: id,
  amount: Money.fromCents(cents),
  description: 'Expense $id',
  category: 'General',
  date: date,
);

/// One stored legacy record whose `amount` JSON value is [amount].
String _legacyRecord(String amount) =>
    '[{"id":"a","amount":$amount,"description":"x","category":"y",'
    '"date":"2024-03-10T12:00:00.000"}]';

/// One stored current-format record whose `amountCents` JSON value is
/// [cents].
String _currentRecord(String cents) =>
    '[{"id":"a","amountCents":$cents,"description":"x","category":"y",'
    '"date":"2024-03-10T12:00:00.000"}]';

/// Stored data in the exact format written by the original app.
const _legacyData =
    '[{"id":"a","amount":12.5,"description":"Lunch","category":"Food",'
    '"date":"2024-03-10T12:00:00.000"}]';

void main() {
  group('loadExpenses', () {
    test('starts empty when nothing is stored', () async {
      final provider = ExpenseProvider(storage: FakeExpenseStorage());

      await provider.loadExpenses();

      expect(provider.status, ExpenseLoadStatus.ready);
      expect(provider.expenses, isEmpty);
    });

    test('reads data stored by the original app format', () async {
      final provider = ExpenseProvider(
        storage: FakeExpenseStorage(data: _legacyData),
      );

      await provider.loadExpenses();

      expect(provider.expenses, hasLength(1));
      expect(provider.expenses.single.description, 'Lunch');
      expect(provider.expenses.single.amount, Money.fromCents(1250));
    });

    test('concurrent calls share one load', () async {
      final storage = FakeExpenseStorage(data: _legacyData)
        ..readGate = Completer<void>();
      final provider = ExpenseProvider(storage: storage);

      final first = provider.loadExpenses();
      final second = provider.loadExpenses();
      expect(identical(first, second), isTrue);

      storage.readGate!.complete();
      await Future.wait([first, second]);
      expect(provider.expenses, hasLength(1));
    });

    for (final corrupt in [
      'not json',
      '{"id":"a"}',
      '[{"id":"a","amount":"12"}]',
      '[1, 2, 3]',
      _legacyRecord('12.345'),
      _legacyRecord('1e21'),
      _legacyRecord('0.30000000000000004'),
      _legacyRecord('"12.50"'),
      _currentRecord('12.5'),
      _currentRecord('9007199254740992'),
    ]) {
      test('corrupted data "$corrupt" fails without overwriting it', () async {
        final storage = FakeExpenseStorage(data: corrupt);
        final provider = ExpenseProvider(storage: storage);

        await provider.loadExpenses();

        expect(provider.status, ExpenseLoadStatus.failed);
        expect(provider.loadError, isA<FormatException>());
        await expectLater(
          provider.addExpense(_expense('x', 1, DateTime(2024))),
          throwsStateError,
        );
        await expectLater(provider.deleteExpense('a'), throwsStateError);
        expect(storage.data, corrupt);
        expect(storage.writeCount, 0);
      });
    }

    test('read failure fails, and retry can succeed', () async {
      final storage = FakeExpenseStorage(data: _legacyData)..failReads = true;
      final provider = ExpenseProvider(storage: storage);

      await provider.loadExpenses();
      expect(provider.status, ExpenseLoadStatus.failed);

      storage.failReads = false;
      await provider.loadExpenses();
      expect(provider.status, ExpenseLoadStatus.ready);
      expect(provider.expenses, hasLength(1));
      expect(storage.writeCount, 0);
    });

    test('writes before loading completes are refused', () async {
      final storage = FakeExpenseStorage(data: _legacyData)
        ..readGate = Completer<void>();
      final provider = ExpenseProvider(storage: storage);

      final load = provider.loadExpenses();
      await expectLater(
        provider.addExpense(_expense('x', 1, DateTime(2024))),
        throwsStateError,
      );
      storage.readGate!.complete();
      await load;

      expect(storage.data, _legacyData);
    });
  });

  group('mutations', () {
    late FakeExpenseStorage storage;
    late ExpenseProvider provider;

    setUp(() async {
      storage = FakeExpenseStorage();
      provider = ExpenseProvider(storage: storage);
      await provider.loadExpenses();
    });

    test('addExpense updates state, persists, and notifies', () async {
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.addExpense(_expense('1', 5, DateTime(2024)));

      expect(provider.expenses.map((e) => e.id), ['1']);
      expect(decodeExpenses(storage.data!).expenses.map((e) => e.id), ['1']);
      expect(notifications, 1);
    });

    test('deleteExpense removes only the matching expense', () async {
      await provider.addExpense(_expense('1', 5, DateTime(2024)));
      await provider.addExpense(_expense('2', 6, DateTime(2024)));

      await provider.deleteExpense('1');

      expect(provider.expenses.map((e) => e.id), ['2']);
      expect(decodeExpenses(storage.data!).expenses.map((e) => e.id), ['2']);
    });

    test('failed save leaves state and storage unchanged', () async {
      await provider.addExpense(_expense('1', 5, DateTime(2024)));
      final before = storage.data;
      storage.failWrites = true;

      await expectLater(
        provider.addExpense(_expense('2', 6, DateTime(2024))),
        throwsA(isA<ExpenseStorageException>()),
      );
      await expectLater(
        provider.deleteExpense('1'),
        throwsA(isA<ExpenseStorageException>()),
      );

      expect(provider.expenses.map((e) => e.id), ['1']);
      expect(storage.data, before);
    });

    test('a failed save does not block later saves', () async {
      storage.failWrites = true;
      await expectLater(
        provider.addExpense(_expense('1', 5, DateTime(2024))),
        throwsA(isA<ExpenseStorageException>()),
      );

      storage.failWrites = false;
      await provider.addExpense(_expense('2', 6, DateTime(2024)));

      expect(provider.expenses.map((e) => e.id), ['2']);
    });

    test('concurrent writes are serialized and none are lost', () async {
      await Future.wait([
        provider.addExpense(_expense('1', 1, DateTime(2024))),
        provider.addExpense(_expense('2', 2, DateTime(2024))),
        provider.addExpense(_expense('3', 3, DateTime(2024))),
      ]);

      expect(provider.expenses.map((e) => e.id), ['1', '2', '3']);
      expect(decodeExpenses(storage.data!).expenses.map((e) => e.id), [
        '1',
        '2',
        '3',
      ]);
    });

    test('expenses list cannot be modified externally', () {
      expect(
        () => provider.expenses.add(_expense('x', 1, DateTime(2024))),
        throwsUnsupportedError,
      );
    });
  });

  group('currentMonthTotal', () {
    Future<ExpenseProvider> load(List<Expense> expenses, DateTime now) async {
      final provider = ExpenseProvider(
        storage: FakeExpenseStorage(data: encodeExpenses(expenses)),
        clock: () => now,
      );
      await provider.loadExpenses();
      return provider;
    }

    test('sums only the current calendar month', () async {
      final provider = await load([
        _expense('1', 1025, DateTime(2024, 3, 1)),
        _expense('2', 475, DateTime(2024, 3, 31, 23, 59, 59)),
        _expense('3', 10000, DateTime(2024, 2, 29, 23, 59, 59)),
        _expense('4', 10000, DateTime(2024, 4, 1)),
        _expense('5', 10000, DateTime(2023, 3, 15)),
      ], DateTime(2024, 3, 15));

      expect(provider.currentMonthTotal, Money.fromCents(1500));
    });

    test('is exact where double arithmetic drifts', () async {
      final provider = await load([
        for (var i = 0; i < 10; i++) _expense('$i', 10, DateTime(2024, 3, 2)),
      ], DateTime(2024, 3, 15));

      // Ten 0.1 doubles sum to 0.9999999999999999.
      expect(provider.currentMonthTotal, Money.fromCents(100));
    });

    test('handles the December to January boundary', () async {
      final expenses = [
        _expense('dec', 300, DateTime(2023, 12, 31, 23, 59)),
        _expense('jan', 700, DateTime(2024, 1, 1)),
      ];

      expect(
        (await load(expenses, DateTime(2023, 12, 1))).currentMonthTotal,
        Money.fromCents(300),
      );
      expect(
        (await load(expenses, DateTime(2024, 1, 31))).currentMonthTotal,
        Money.fromCents(700),
      );
    });

    test('is zero with no expenses this month', () async {
      final provider = await load([
        _expense('1', 500, DateTime(2024, 2, 1)),
      ], DateTime(2024, 3, 15));

      expect(provider.currentMonthTotal, Money.zero);
    });

    test('combines legacy and current records exactly', () async {
      final storage = FakeExpenseStorage(
        data:
            '[{"id":"a","amount":0.1,"description":"x","category":"y",'
            '"date":"2024-03-01T00:00:00.000"},'
            '{"id":"b","amount":0.2,"description":"x","category":"y",'
            '"date":"2024-03-02T00:00:00.000"},'
            '{"id":"c","amountCents":5,"description":"x","category":"y",'
            '"date":"2024-03-03T00:00:00.000"}]',
      );
      final provider = ExpenseProvider(
        storage: storage,
        clock: () => DateTime(2024, 3, 15),
      );
      await provider.loadExpenses();

      expect(provider.currentMonthTotal, Money.fromCents(35));
    });

    test('throws on overflow instead of losing precision', () async {
      final provider = await load([
        _expense('1', Money.maxCents, DateTime(2024, 3, 1)),
        _expense('2', 1, DateTime(2024, 3, 2)),
      ], DateTime(2024, 3, 15));

      expect(
        () => provider.currentMonthTotal,
        throwsA(isA<MoneyOverflowException>()),
      );
    });
  });

  group('legacy data migration', () {
    test('loading legacy data does not write anything', () async {
      final storage = FakeExpenseStorage(data: _legacyData);
      await ExpenseProvider(storage: storage).loadExpenses();

      expect(storage.data, _legacyData);
      expect(storage.writeCount, 0);
      expect(storage.backupCount, 0);
    });

    test('first write backs up the original, then stores cents', () async {
      final storage = FakeExpenseStorage(data: _legacyData);
      final provider = ExpenseProvider(storage: storage);
      await provider.loadExpenses();

      await provider.addExpense(_expense('b', 199, DateTime(2024, 3, 11)));

      expect(storage.legacyBackup, _legacyData);
      final stored = decodeExpenses(storage.data!);
      expect(stored.hasLegacyRecords, isFalse);
      expect(stored.expenses.map((e) => e.amount.cents), [1250, 199]);
      expect(storage.data, isNot(contains('"amount":')));
    });

    test('backs up only once', () async {
      final storage = FakeExpenseStorage(data: _legacyData);
      final provider = ExpenseProvider(storage: storage);
      await provider.loadExpenses();

      await provider.addExpense(_expense('b', 1, DateTime(2024)));
      await provider.deleteExpense('b');

      expect(storage.backupCount, 1);
    });

    test('a failed backup aborts the write and keeps the original', () async {
      final storage = FakeExpenseStorage(data: _legacyData)..failBackups = true;
      final provider = ExpenseProvider(storage: storage);
      await provider.loadExpenses();

      await expectLater(
        provider.addExpense(_expense('b', 1, DateTime(2024))),
        throwsA(isA<ExpenseStorageException>()),
      );

      expect(storage.data, _legacyData);
      expect(storage.writeCount, 0);
      expect(provider.expenses, hasLength(1));

      storage.failBackups = false;
      await provider.addExpense(_expense('b', 1, DateTime(2024)));
      expect(storage.legacyBackup, _legacyData);
      expect(provider.expenses, hasLength(2));
    });

    test('current-format data is never backed up', () async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([_expense('a', 1, DateTime(2024))]),
      );
      final provider = ExpenseProvider(storage: storage);
      await provider.loadExpenses();

      await provider.addExpense(_expense('b', 1, DateTime(2024)));

      expect(storage.backupCount, 0);
    });

    test('an invalid record fails the whole load and names it', () async {
      const data =
          '[{"id":"a","amount":1.5,"description":"x","category":"y",'
          '"date":"2024-03-10T12:00:00.000"},'
          '{"id":"b","amount":2.005,"description":"x","category":"y",'
          '"date":"2024-03-10T12:00:00.000"}]';
      final storage = FakeExpenseStorage(data: data);
      final provider = ExpenseProvider(storage: storage);

      await provider.loadExpenses();

      expect(provider.status, ExpenseLoadStatus.failed);
      expect(
        (provider.loadError! as FormatException).message,
        contains('index 1'),
      );
      expect(provider.expenses, isEmpty);
      expect(storage.data, data);
      expect(storage.backupCount, 0);
    });
  });

  group('SharedPreferencesExpenseStorage', () {
    test('reads existing data from the original "expenses" key', () async {
      SharedPreferences.setMockInitialValues({'expenses': _legacyData});

      final provider = ExpenseProvider(
        storage: SharedPreferencesExpenseStorage(),
      );
      await provider.loadExpenses();

      expect(provider.expenses.single.id, 'a');
    });

    test('persists writes under the "expenses" key', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ExpenseProvider(
        storage: SharedPreferencesExpenseStorage(),
      );
      await provider.loadExpenses();

      await provider.addExpense(_expense('1', 5, DateTime(2024)));

      final prefs = await SharedPreferences.getInstance();
      final stored = decodeExpenses(prefs.getString('expenses')!);
      expect(stored.expenses.single.id, '1');
      expect(stored.hasLegacyRecords, isFalse);
    });

    test('backs up legacy data once under its own key', () async {
      SharedPreferences.setMockInitialValues({'expenses': _legacyData});
      final storage = SharedPreferencesExpenseStorage();

      await storage.backupLegacyData(_legacyData);
      await storage.backupLegacyData('[]');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('expenses_legacy_backup'), _legacyData);
      expect(prefs.getString('expenses'), _legacyData);
    });
  });
}
