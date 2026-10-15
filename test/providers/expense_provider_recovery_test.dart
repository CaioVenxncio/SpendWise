import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/backup/expense_backup.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/providers/expense_provider.dart';
import 'package:spendwise/repositories/expense_repository.dart';
import 'package:spendwise/services/expense_storage.dart';

import '../support/fake_expense_storage.dart';

Expense _e(String id, int cents) => Expense(
  id: id,
  amount: Money.fromCents(cents),
  description: 'Expense $id',
  category: 'General',
  date: DateTime(2024, 3, 1),
);

Uint8List _backupOf(List<Expense> es) => Uint8List.fromList(
  utf8.encode(encodeBackup(es, exportedAt: DateTime.utc(2026))),
);

Future<(FakeExpenseStorage, ExpenseProvider)> _ready(List<Expense> es) async {
  final storage = FakeExpenseStorage(
    data: es.isEmpty ? null : encodeExpenses(es),
  );
  final provider = ExpenseProvider(
    storage: storage,
    clock: () => DateTime.utc(2026, 10, 15),
  );
  await provider.loadExpenses();
  return (storage, provider);
}

void main() {
  group('cross-tab conflicts', () {
    test('a conflicting write pauses changes until reload', () async {
      final (storage, provider) = await _ready([_e('a', 1)]);
      final external = encodeExpenses([_e('a', 1), _e('tab-b', 7)]);
      storage.data = external;
      var notified = 0;
      provider.addListener(() => notified++);

      await expectLater(
        provider.addExpense(_e('mine', 2)),
        throwsA(isA<ExpenseConflictException>()),
      );

      expect(provider.hasConflict, isTrue);
      expect(provider.isReady, isFalse);
      expect(notified, greaterThan(0));
      expect(storage.data, external);
      await expectLater(
        provider.deleteExpense('a'),
        throwsA(isA<ExpenseConflictException>()),
      );
      expect(storage.writeCount, 0);

      await provider.reload();

      expect(provider.hasConflict, isFalse);
      expect(provider.expenses.map((e) => e.id), ['a', 'tab-b']);
      await provider.addExpense(_e('mine', 2));
      expect(decodeExpenses(storage.data!).expenses.map((e) => e.id), [
        'a',
        'tab-b',
        'mine',
      ]);
    });
  });

  group('duplicate IDs', () {
    test('are exposed and cannot be deleted', () async {
      final (storage, provider) = await _ready([
        _e('a', 1),
        _e('a', 2),
        _e('b', 3),
      ]);

      expect(provider.duplicateIds, {'a'});
      expect(provider.expenses, hasLength(3));
      await expectLater(
        provider.deleteExpense('a'),
        throwsA(isA<DuplicateExpenseIdException>()),
      );
      expect(provider.expenses, hasLength(3));
      expect(storage.writeCount, 0);

      await provider.deleteExpense('b');
      expect(provider.expenses.map((e) => e.id), ['a', 'a']);
    });
  });

  group('backup', () {
    test('export round-trips through preview and import', () async {
      final (_, source) = await _ready([_e('a', 1250), _e('b', -3)]);
      final file = Uint8List.fromList(utf8.encode(source.exportBackup()));

      final (storage, target) = await _ready([_e('a', 1250)]);
      final preview = target.previewBackup(file);
      expect(preview.newExpenses.map((e) => e.id), ['b']);
      expect(preview.alreadyPresent, 1);

      final outcome = await target.importBackup(preview);

      expect(outcome.added, 1);
      expect(target.expenses.map((e) => e.id), ['a', 'b']);
      expect(decodeExpenses(storage.data!).expenses, hasLength(2));
    });

    test('preview changes nothing', () async {
      final (storage, provider) = await _ready([_e('a', 1)]);
      final before = storage.data;

      provider.previewBackup(_backupOf([_e('b', 2)]));

      expect(provider.expenses.map((e) => e.id), ['a']);
      expect(storage.data, before);
      expect(storage.writeCount, 0);
    });

    test('an invalid file is rejected without changes', () async {
      final (storage, provider) = await _ready([_e('a', 1)]);

      expect(
        () => provider.previewBackup(Uint8List.fromList(utf8.encode('{}'))),
        throwsA(isA<BackupFormatException>()),
      );
      expect(storage.writeCount, 0);
    });

    test('import re-checks stored data at write time', () async {
      final (storage, provider) = await _ready([]);
      final preview = provider.previewBackup(_backupOf([_e('a', 1)]));
      // Another tab adds a different record with the same ID meanwhile.
      storage.data = encodeExpenses([_e('a', 999)]);

      await expectLater(
        provider.importBackup(preview),
        throwsA(isA<ExpenseConflictException>()),
      );
      expect(decodeExpenses(storage.data!).expenses.single.amount.cents, 999);
    });

    test('preview and export are refused before loading succeeds', () async {
      final provider = ExpenseProvider(
        storage: FakeExpenseStorage(data: 'corrupt'),
      );
      await provider.loadExpenses();

      expect(
        () => provider.previewBackup(_backupOf([_e('a', 1)])),
        throwsStateError,
      );
      expect(provider.exportBackup, throwsStateError);
    });
  });

  group('raw export', () {
    test('works when loading failed and leaves data untouched', () async {
      const corrupt = '[{"id":"a","amount":1.005}]';
      final storage = FakeExpenseStorage(data: corrupt)..legacyBackup = '[old]';
      final provider = ExpenseProvider(storage: storage);
      await provider.loadExpenses();
      expect(provider.status, ExpenseLoadStatus.failed);

      final text = await provider.exportRawData();
      final map = json.decode(text) as Map<String, dynamic>;

      expect((map['storage'] as Map)['expenses'], corrupt);
      expect((map['storage'] as Map)['expenses_legacy_backup'], '[old]');
      expect(storage.data, corrupt);
      expect(storage.writeCount, 0);
    });
  });

  test('load failures never log stored content', () async {
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logs.add('$message');
    addTearDown(() => debugPrint = original);

    final provider = ExpenseProvider(
      storage: FakeExpenseStorage(
        data:
            '[{"id":"a","amount":12.345,"description":"SECRET-PAYEE",'
            '"category":"y","date":"2024-03-10T12:00:00.000"}]',
      ),
    );
    await provider.loadExpenses();

    expect(provider.status, ExpenseLoadStatus.failed);
    expect(logs, isNotEmpty);
    expect(logs.join('\n'), isNot(contains('SECRET')));
    expect(logs.join('\n'), isNot(contains('12.345')));
  });
}
