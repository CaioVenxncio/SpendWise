import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/drift/database.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/repositories/drift_expense_repository.dart';
import 'package:spendwise/repositories/expense_repository.dart';

Expense _e(
  String id,
  int cents, {
  String dateText = '2024-03-01T12:00:00.000',
}) => Expense(
  id: id,
  amount: Money.fromCents(cents),
  description: 'd',
  category: 'General',
  date: DateTime.parse(dateText),
  dateText: dateText,
);

Future<Map<String, int>> _seqs(SpendWiseDatabase db) async {
  final rows = await db
      .customSelect('SELECT id, seq FROM expenses ORDER BY seq')
      .get();
  return {for (final r in rows) r.read<String>('id'): r.read<int>('seq')};
}

Future<DriftExpenseRepository> _loaded(
  SpendWiseDatabase db, [
  List<Expense> seed = const [],
]) async {
  final repo = DriftExpenseRepository(db);
  await repo.load();
  if (seed.isNotEmpty) await repo.importExpenses(seed);
  return repo;
}

void main() {
  group('in memory', () {
    late SpendWiseDatabase db;
    setUp(() => db = SpendWiseDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test(
      'update keeps the row\'s seq; guarded delete renumbers nothing',
      () async {
        final repo = await _loaded(db, [_e('a', 1), _e('b', 2), _e('c', 3)]);
        final before = await _seqs(db);

        await repo.update(_e('b', 2), _e('b', 20));
        expect(await _seqs(db), before);

        await repo.deleteExpected(_e('a', 1));
        expect(await _seqs(db), {'b': before['b'], 'c': before['c']});

        // A later insert still goes after every existing row.
        await repo.add(_e('d', 4));
        expect((await _seqs(db))['d'], greaterThan(before['c']!));
      },
    );

    test('an injected failure rolls the update back, seq included', () async {
      final repo = await _loaded(db, [_e('a', 1), _e('b', 2)]);
      final before = await _seqs(db);
      repo.beforeCommit = () => throw StateError('injected');

      await expectLater(repo.update(_e('a', 1), _e('a', 5)), throwsStateError);
      await expectLater(repo.deleteExpected(_e('b', 2)), throwsStateError);

      repo.beforeCommit = null;
      final stored = (await repo.load()).expenses;
      expect(stored.map((e) => e.amount.cents), [1, 2]);
      expect(await _seqs(db), before);
    });

    test('expected values are compared on every column', () async {
      final repo = await _loaded(db, [_e('a', 1)]);
      final variants = [
        _e('a', 2),
        Expense(
          id: 'a',
          amount: Money.fromCents(1),
          description: 'other',
          category: 'General',
          date: DateTime.parse('2024-03-01T12:00:00.000'),
        ),
        Expense(
          id: 'a',
          amount: Money.fromCents(1),
          description: 'd',
          category: 'Food',
          date: DateTime.parse('2024-03-01T12:00:00.000'),
        ),
        _e('a', 1, dateText: '2024-03-01T12:00:00'),
      ];
      for (final stale in variants) {
        await expectLater(
          repo.update(stale, _e('a', 9)),
          throwsA(isA<ExpenseConflictException>()),
        );
        await expectLater(
          repo.deleteExpected(stale),
          throwsA(isA<ExpenseConflictException>()),
        );
      }
      expect((await repo.load()).expenses.single.amount.cents, 1);
    });
  });

  group('two connections to one database file', () {
    late Directory dir;
    late SpendWiseDatabase first;
    late SpendWiseDatabase second;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('spendwise_repo_');
      final file = File('${dir.path}/spendwise.sqlite');
      first = SpendWiseDatabase(NativeDatabase(file));
      second = SpendWiseDatabase(NativeDatabase(file));
    });

    tearDown(() async {
      await first.close();
      await second.close();
      dir.deleteSync(recursive: true);
    });

    test('a stale tab cannot update or delete a record edited in another '
        'tab', () async {
      final original = _e('a', 1);
      final tabA = await _loaded(first, [original]);
      final tabB = await _loaded(second);
      final seq = (await _seqs(first))['a'];

      final fromB = original.edited(description: 'from B');
      await tabB.update(original, fromB);

      await expectLater(
        tabA.update(original, original.edited(description: 'from A')),
        throwsA(isA<ExpenseConflictException>()),
      );
      await expectLater(
        tabA.deleteExpected(original),
        throwsA(isA<ExpenseConflictException>()),
      );
      final stored = (await tabA.load()).expenses.single;
      expect(stored.toMap(), fromB.toMap());
      expect((await _seqs(first))['a'], seq);
    });

    test('a record deleted in another tab is reported missing', () async {
      final original = _e('a', 1);
      final tabA = await _loaded(first, [original]);
      final tabB = await _loaded(second);

      await tabB.deleteExpected(original);

      await expectLater(
        tabA.update(original, _e('a', 2)),
        throwsA(isA<ExpenseNotFoundException>()),
      );
      await expectLater(
        tabA.deleteExpected(original),
        throwsA(isA<ExpenseNotFoundException>()),
      );
      expect((await tabA.load()).expenses, isEmpty);
    });

    test('a no-op update changes no row on either connection', () async {
      final original = _e('a', 1);
      final tabA = await _loaded(first, [original]);
      Future<int> changes(SpendWiseDatabase db) async =>
          (await db.customSelect('SELECT total_changes() AS n').getSingle())
              .read<int>('n');
      final before = await changes(first);

      await tabA.update(original, original.edited());

      expect(await changes(first), before);
      expect(await changes(second), 0);
    });
  });
}
