import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/drift/database.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/presentation/formatting.dart';
import 'package:spendwise/providers/expense_provider.dart';
import 'package:spendwise/repositories/drift_expense_repository.dart';
import 'package:spendwise/repositories/expense_repository.dart';
import 'package:spendwise/services/expense_storage.dart';

import '../support/date_texts.dart';
import '../support/fake_expense_storage.dart';

Expense _e(String id, int cents) =>
    expenseAt(id, cents, '2026-10-10T12:00:00.000');

List<Map<String, dynamic>> _maps(List<Expense> es) =>
    es.map((e) => e.toMap()).toList();

Future<(FakeExpenseStorage, ExpenseProvider)> _loaded(
  List<Expense> seed, {
  DateTime Function()? clock,
}) async {
  final storage = FakeExpenseStorage(
    data: seed.isEmpty ? null : encodeExpenses(seed),
  );
  final provider = ExpenseProvider(storage: storage, clock: clock);
  await provider.loadExpenses();
  return (storage, provider);
}

void main() {
  group('updateExpense', () {
    test('replaces the record in place, persists it and notifies', () async {
      final (storage, provider) = await _loaded([_e('a', 1), _e('b', 2)]);
      var notified = 0;
      provider.addListener(() => notified++);
      final edited = provider.expenses.first.edited(
        amount: Money.fromCents(150),
        description: 'edited',
      );

      await provider.updateExpense(provider.expenses.first, edited);

      expect(_maps(provider.expenses), _maps([edited, _e('b', 2)]));
      expect(storage.data, encodeExpenses([edited, _e('b', 2)]));
      expect(notified, greaterThan(0));
      expect(provider.isReady, isTrue);
    });

    test('the shown list changes only after the write succeeded', () async {
      final (storage, provider) = await _loaded([_e('a', 1)]);
      final original = provider.expenses.single;
      List<Expense>? shownDuringWrite;
      storage.beforeWrite = () => shownDuringWrite = provider.expenses;

      await provider.updateExpense(original, _e('a', 5));

      expect(_maps(shownDuringWrite!), _maps([original]));
      expect(provider.expenses.single.amount.cents, 5);
    });

    test('an identical replacement writes nothing', () async {
      final (storage, provider) = await _loaded([_e('a', 1)]);

      await provider.updateExpense(
        provider.expenses.single,
        provider.expenses.single.edited(),
      );

      expect(storage.writeCount, 0);
      expect(provider.isReady, isTrue);
    });

    test('a change in another tab refuses the update, pauses edits and '
        'reload shows the stored data', () async {
      final (storage, provider) = await _loaded([_e('a', 1)]);
      final otherTab = encodeExpenses([_e('a', 7)]);
      storage.data = otherTab;

      await expectLater(
        provider.updateExpense(provider.expenses.single, _e('a', 5)),
        throwsA(isA<ExpenseConflictException>()),
      );

      expect(provider.hasConflict, isTrue);
      expect(provider.isReady, isFalse);
      expect(_maps(provider.expenses), _maps([_e('a', 1)]));
      expect(storage.data, otherTab);
      expect(storage.writeCount, 0);

      await provider.reload();
      expect(provider.hasConflict, isFalse);
      expect(_maps(provider.expenses), _maps([_e('a', 7)]));

      // A deliberate retry on the reloaded record works.
      await provider.updateExpense(provider.expenses.single, _e('a', 5));
      expect(storage.data, encodeExpenses([_e('a', 5)]));
    });

    test('a stale expected record is refused and pauses edits', () async {
      final (storage, provider) = await _loaded([_e('a', 1)]);

      await expectLater(
        provider.updateExpense(_e('a', 2), _e('a', 3)),
        throwsA(isA<ExpenseConflictException>()),
      );
      expect(provider.hasConflict, isTrue);
      expect(storage.writeCount, 0);
    });

    test('records sharing an ID are refused without pausing edits', () async {
      final (storage, provider) = await _loaded([
        _e('a', 1),
        _e('b', 2),
        _e('a', 1),
      ]);
      final before = storage.data;

      await expectLater(
        provider.updateExpense(_e('a', 1), _e('a', 9)),
        throwsA(isA<DuplicateExpenseIdException>()),
      );
      await expectLater(
        provider.deleteExpectedExpense(_e('a', 1)),
        throwsA(isA<DuplicateExpenseIdException>()),
      );

      expect(provider.duplicateIds, {'a'});
      expect(provider.hasConflict, isFalse);
      expect(provider.isReady, isTrue);
      expect(storage.data, before);
      expect(provider.expenses, hasLength(3));
    });

    test('a changed ID is refused and changes nothing', () async {
      final (storage, provider) = await _loaded([_e('a', 1)]);

      await expectLater(
        provider.updateExpense(provider.expenses.single, _e('b', 1)),
        throwsArgumentError,
      );
      expect(provider.isReady, isTrue);
      expect(storage.writeCount, 0);
    });

    test('a failed write keeps the shown list and later writes work', () async {
      final (storage, provider) = await _loaded([_e('a', 1)]);
      final original = provider.expenses.single;
      storage.failWrites = true;

      await expectLater(
        provider.updateExpense(original, _e('a', 5)),
        throwsA(isA<ExpenseStorageException>()),
      );
      expect(_maps(provider.expenses), _maps([original]));
      expect(provider.hasConflict, isFalse);
      expect(provider.isReady, isTrue);

      storage.failWrites = false;
      await provider.updateExpense(original, _e('a', 5));
      expect(provider.expenses.single.amount.cents, 5);
    });

    test('refused before loading', () async {
      final provider = ExpenseProvider(storage: FakeExpenseStorage());
      await expectLater(
        provider.updateExpense(_e('a', 1), _e('a', 2)),
        throwsStateError,
      );
      await expectLater(
        provider.deleteExpectedExpense(_e('a', 1)),
        throwsStateError,
      );
    });
  });

  group('deleteExpectedExpense', () {
    test('removes the unchanged record', () async {
      final (storage, provider) = await _loaded([_e('a', 1), _e('b', 2)]);

      await provider.deleteExpectedExpense(provider.expenses.first);

      expect(provider.expenses.map((e) => e.id), ['b']);
      expect(storage.data, encodeExpenses([_e('b', 2)]));
    });

    test('a change in another tab refuses it and pauses edits', () async {
      final (storage, provider) = await _loaded([_e('a', 1)]);
      storage.data = encodeExpenses([_e('a', 7)]);

      await expectLater(
        provider.deleteExpectedExpense(provider.expenses.single),
        throwsA(isA<ExpenseConflictException>()),
      );
      expect(provider.hasConflict, isTrue);
      expect(provider.expenses.single.amount.cents, 1);
      expect(storage.data, encodeExpenses([_e('a', 7)]));
    });

    test('a failed write keeps the record shown and stored', () async {
      final (storage, provider) = await _loaded([_e('a', 1)]);
      storage.failWrites = true;

      await expectLater(
        provider.deleteExpectedExpense(provider.expenses.single),
        throwsA(isA<ExpenseStorageException>()),
      );
      expect(provider.expenses, hasLength(1));
      expect(storage.data, encodeExpenses([_e('a', 1)]));
    });
  });

  group('missing records', () {
    test(
      'a record not in storage (JSON) is reported and pauses edits',
      () async {
        final (storage, provider) = await _loaded([_e('a', 1)]);

        await expectLater(
          provider.updateExpense(_e('zzz', 1), _e('zzz', 2)),
          throwsA(isA<ExpenseNotFoundException>()),
        );
        expect(provider.hasConflict, isTrue);
        expect(storage.writeCount, 0);
        expect(_maps(provider.expenses), _maps([_e('a', 1)]));
      },
    );

    group('Drift, another tab deleted the record', () {
      late SpendWiseDatabase db;
      setUp(() => db = SpendWiseDatabase(NativeDatabase.memory()));
      tearDown(() => db.close());

      test(
        'update and guarded delete report it; reload shows the truth',
        () async {
          final seeder = DriftExpenseRepository(db);
          await seeder.load();
          await seeder.importExpenses([_e('a', 1), _e('b', 2)]);

          final provider = ExpenseProvider(
            repository: DriftExpenseRepository(db),
          );
          await provider.loadExpenses();
          final shownA = provider.expenses.first;

          final otherTab = DriftExpenseRepository(db);
          await otherTab.load();
          await otherTab.deleteExpected(shownA);

          await expectLater(
            provider.updateExpense(shownA, shownA.edited(description: 'x')),
            throwsA(isA<ExpenseNotFoundException>()),
          );
          expect(provider.hasConflict, isTrue);
          expect(provider.isReady, isFalse);
          // Still the list as last loaded; nothing was guessed or re-added.
          expect(provider.expenses.map((e) => e.id), ['a', 'b']);

          await provider.reload();
          expect(provider.expenses.map((e) => e.id), ['b']);
          await expectLater(
            provider.deleteExpectedExpense(shownA),
            throwsA(isA<ExpenseNotFoundException>()),
          );
          expect(
            (await DriftExpenseRepository(db).load()).expenses.map((e) => e.id),
            ['b'],
          );
        },
      );

      test('an edit in another tab is a conflict, never overwritten', () async {
        final seeder = DriftExpenseRepository(db);
        await seeder.load();
        await seeder.importExpenses([_e('a', 1)]);
        final provider = ExpenseProvider(
          repository: DriftExpenseRepository(db),
        );
        await provider.loadExpenses();
        final shown = provider.expenses.single;

        final otherTab = DriftExpenseRepository(db);
        await otherTab.load();
        await otherTab.update(shown, shown.edited(description: 'other tab'));

        await expectLater(
          provider.updateExpense(shown, shown.edited(description: 'mine')),
          throwsA(isA<ExpenseConflictException>()),
        );
        await provider.reload();
        expect(provider.expenses.single.description, 'other tab');
      });
    });
  });

  group('write queue', () {
    test('add, update and delete run in call order', () async {
      final (storage, provider) = await _loaded([_e('a', 1)]);
      final a = provider.expenses.single;
      final b = _e('b', 2);
      final a2 = a.edited(description: 'a2');
      final b2 = b.edited(amount: Money.fromCents(20));

      // Started without awaiting: each must see the previous one's result.
      final writes = [
        provider.addExpense(b),
        provider.updateExpense(a, a2),
        provider.updateExpense(b, b2),
        provider.deleteExpectedExpense(a2),
        provider.addExpense(_e('c', 3)),
      ];
      await Future.wait(writes);

      expect(_maps(provider.expenses), _maps([b2, _e('c', 3)]));
      expect(storage.data, encodeExpenses([b2, _e('c', 3)]));
      expect(storage.writeCount, 5);
    });

    test(
      'operations queued behind a conflict are refused, none written',
      () async {
        final (storage, provider) = await _loaded([_e('a', 1), _e('b', 2)]);
        final a = provider.expenses.first;
        final b = provider.expenses.last;
        storage.data = encodeExpenses([_e('a', 1), _e('b', 2), _e('x', 9)]);

        final outcomes = await Future.wait([
          for (final write in [
            provider.updateExpense(a, a.edited(description: '1')),
            provider.deleteExpectedExpense(b),
            provider.addExpense(_e('c', 3)),
            provider.deleteExpense('a'),
          ])
            write.then<Object?>((_) => null, onError: (Object e) => e),
        ]);

        expect(outcomes, everyElement(isA<ExpenseConflictException>()));
        expect(storage.writeCount, 0);
        expect(provider.hasConflict, isTrue);
        expect(provider.expenses.map((e) => e.id), ['a', 'b']);
      },
    );

    test('a failed write does not stop the next queued one', () async {
      final (storage, provider) = await _loaded([_e('a', 1)]);
      final a = provider.expenses.single;
      var failNext = true;
      storage.beforeWrite = () {
        if (failNext) {
          failNext = false;
          throw ExpenseStorageException('injected');
        }
      };

      final failing = provider.updateExpense(a, _e('a', 5));
      final next = provider.addExpense(_e('b', 2));

      await expectLater(failing, throwsA(isA<ExpenseStorageException>()));
      await next;
      expect(_maps(provider.expenses), _maps([a, _e('b', 2)]));
      expect(storage.data, encodeExpenses([a, _e('b', 2)]));
      expect(provider.isReady, isTrue);
    });

    test('the ID-only delete keeps working unchanged', () async {
      final (storage, provider) = await _loaded([_e('a', 1), _e('b', 2)]);
      await provider.deleteExpense('a');
      expect(provider.expenses.map((e) => e.id), ['b']);
      await provider.deleteExpense('zzz');
      expect(storage.data, encodeExpenses([_e('b', 2)]));
    });
  });

  group('currentMonthTotal uses the displayed local day', () {
    final october = DateTime(2026, 10, 15, 12);

    test(
      'instants near midnight count in the month they are shown in',
      () async {
        final lastOfOctober = DateTime(2026, 10, 31, 23, 30);
        final firstOfOctober = DateTime(2026, 10, 1, 0, 15);
        final lastOfSeptember = DateTime(2026, 9, 30, 23, 45);
        final firstOfNovember = DateTime(2026, 11, 1, 0, 30);
        final seed = <Expense>[];
        var n = 0;
        for (final (instant, cents) in [
          (lastOfOctober, 100),
          (firstOfOctober, 10000),
          (lastOfSeptember, 1),
          (firstOfNovember, 7),
        ]) {
          for (final text in dateTextVariants(instant)) {
            seed.add(expenseAt('e${n++}', cents, text));
          }
        }
        final (storage, provider) = await _loaded(seed, clock: () => october);

        final variants = dateTextVariants(lastOfOctober).length;
        expect(provider.currentMonthTotal.cents, (100 + 10000) * variants);
        for (final e in provider.expenses) {
          final shownInOctober = formatExpenseDate(e.date)
              .startsWith('2026-10-');
          expect(
            shownInOctober,
            e.amount.cents == 100 || e.amount.cents == 10000,
            reason: e.dateText,
          );
        }
        // Presentation only: stored texts are untouched.
        expect(storage.writeCount, 0);
        expect(
          provider.expenses.map((e) => e.dateText),
          seed.map((e) => e.dateText),
        );
      },
    );

    test('regression: a Z text late on the 31st local is this month', () async {
      final local = DateTime(2026, 10, 31, 23, 30);
      final zText = local.toUtc().toIso8601String();
      final (_, provider) = await _loaded([
        expenseAt('z', 1250, zText),
      ], clock: () => october);

      expect(formatExpenseDate(provider.expenses.single.date), '2026-10-31');
      expect(provider.currentMonthTotal.cents, 1250);
    });

    test('year boundary in every text form', () async {
      final seed = <Expense>[];
      var n = 0;
      for (final text in dateTextVariants(
        DateTime(2026, 12, 31, 23, 59, 59, 999),
      )) {
        seed.add(expenseAt('dec${n++}', 1, text));
      }
      for (final text in dateTextVariants(DateTime(2027, 1, 1))) {
        seed.add(expenseAt('jan${n++}', 100, text));
      }
      final perInstant = dateTextVariants(DateTime(2027)).length;

      final (_, december) = await _loaded(
        seed,
        clock: () => DateTime(2026, 12, 15),
      );
      expect(december.currentMonthTotal.cents, perInstant);
      final (_, january) = await _loaded(
        seed,
        clock: () => DateTime(2027, 1, 15),
      );
      expect(january.currentMonthTotal.cents, 100 * perInstant);
    });

    test('a UTC clock is read in local time as well', () async {
      final (_, provider) = await _loaded([
        expenseAt('a', 5, '2027-01-01T00:30:00.000'),
      ], clock: () => DateTime(2027, 1, 1, 0, 45).toUtc());
      expect(provider.currentMonthTotal.cents, 5);
    });

    test('every month of a year: total equals the sum of records shown in '
        'that month (incl. this machine\'s daylight-saving changes)', () async {
      final seed = <Expense>[];
      var n = 0;
      var instant = DateTime.utc(2025, 12, 31);
      while (instant.isBefore(DateTime.utc(2027, 1, 2))) {
        for (final text in dateTextVariants(instant)) {
          seed.add(expenseAt('r${n++}', n % 1000 + 1, text));
        }
        instant = instant.add(const Duration(hours: 5, minutes: 17));
      }

      for (var month = 1; month <= 12; month++) {
        final (_, provider) = await _loaded(
          seed,
          clock: () => DateTime(2026, month, 10),
        );
        final prefix = '2026-${month.toString().padLeft(2, '0')}-';
        final shown = provider.expenses.where(
          (e) => formatExpenseDate(e.date).startsWith(prefix),
        );
        expect(
          provider.currentMonthTotal,
          Money.sum(shown.map((e) => e.amount)),
          reason: prefix,
        );
      }
    });
  });
}
