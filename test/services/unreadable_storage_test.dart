// DATA-02: stored data that exists but cannot be read is never treated as
// an empty store, never overwritten, and exported exactly as found.
//
// shared_preferences on the web skips a localStorage value it cannot decode,
// as if the key were absent. These tests reproduce that with a mock
// preferences store that lacks the key plus a FakeRawStorage holding the
// localStorage text. All data is synthetic.
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spendwise/data/drift/database.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/migration/json_to_drift_migration.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/platform/platform_services.dart';
import 'package:spendwise/providers/expense_provider.dart';
import 'package:spendwise/services/expense_storage.dart';

import '../support/fake_platform_services.dart';

const _key = 'flutter.expenses';
const _legacyKey = 'flutter.expenses_legacy_backup';

/// A truncated value as it could be left in localStorage (the web plugin
/// stores strings JSON-encoded). Contains quotes, a backslash and emoji so
/// exact export can be checked.
const _damaged =
    r'"[{\"id\":\"a\",\"amountCents\":1250,\"description\":\"😀 caf';

const _legacy =
    '[{"id":"a","amount":12.5,"description":"Lunch","category":"Food",'
    '"date":"2026-10-03T12:00:00.000"}]';

Expense _e(String id, int cents) => Expense(
  id: id,
  amount: Money.fromCents(cents),
  description: 'Synthetic $id',
  category: 'General',
  date: DateTime(2026, 10, 3, 12),
);

final _valid = encodeExpenses([_e('a', 1250), _e('b', -500)]);

/// localStorage as the web plugin writes a string value.
String _stored(String text) => json.encode(text);

SharedPreferencesExpenseStorage _storage(RawStorage raw, {String? namespace}) =>
    SharedPreferencesExpenseStorage(
      lock: InProcessLock(),
      namespace: namespace,
      rawStorage: raw,
    );

Future<Set<String>> _prefsKeys() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  return prefs.getKeys();
}

Matcher _unreadable(String key, UnreadableReason reason) =>
    isA<ExpenseStorageUnreadableException>()
        .having((e) => e.key, 'key', key)
        .having((e) => e.reason, 'reason', reason);

void main() {
  group('absent versus unreadable', () {
    test('a missing key is an empty store', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = _storage(FakeRawStorage());
      expect(await storage.read(), isNull);
      expect(await storage.readLegacyBackup(), isNull);
    });

    test('a valid value is read unchanged', () async {
      SharedPreferences.setMockInitialValues({'expenses': _valid});
      final storage = _storage(FakeRawStorage({_key: _stored(_valid)}));
      expect(await storage.read(), _valid);
    });

    test('a present value the plugin could not decode is unreadable, and '
        'the error carries no stored content', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = _storage(FakeRawStorage({_key: _damaged}));
      await expectLater(
        storage.read(),
        throwsA(_unreadable('expenses', UnreadableReason.notDecodable)),
      );
      try {
        await storage.read();
      } catch (e) {
        expect(e.toString(), isNot(contains('caf')));
        expect(e.toString(), isNot(contains('1250')));
      }
    });

    test('a JSON null literal is not "absent"', () async {
      SharedPreferences.setMockInitialValues({});
      final storage = _storage(FakeRawStorage({_key: 'null'}));
      await expectLater(
        storage.read(),
        throwsA(_unreadable('expenses', UnreadableReason.notDecodable)),
      );
    });

    test('wrong-type values are unreadable, not a TypeError', () async {
      SharedPreferences.setMockInitialValues({'expenses': 123});
      await expectLater(
        _storage(FakeRawStorage({_key: '123'})).read(),
        throwsA(_unreadable('expenses', UnreadableReason.unexpectedType)),
      );

      SharedPreferences.setMockInitialValues({});
      await expectLater(
        _storage(FakeRawStorage({_key: '{"a":1}'})).read(),
        throwsA(_unreadable('expenses', UnreadableReason.unexpectedType)),
      );
    });

    test('blocked storage access is unreadable, not empty', () async {
      SharedPreferences.setMockInitialValues({});
      final raw = FakeRawStorage()..inaccessible = true;
      await expectLater(
        _storage(raw).read(),
        throwsA(_unreadable('expenses', UnreadableReason.inaccessible)),
      );
    });

    test(
      'a valid value written by another tab after the reload is read',
      () async {
        SharedPreferences.setMockInitialValues({});
        final storage = _storage(FakeRawStorage({_key: _stored(_valid)}));
        expect(await storage.read(), _valid);
      },
    );

    test('namespaced keys are checked under their own platform key', () async {
      SharedPreferences.setMockInitialValues({});
      final raw = FakeRawStorage({
        'flutter.spendwise_ns.qa.expenses': _damaged,
      });
      await expectLater(
        _storage(raw, namespace: 'qa').read(),
        throwsA(
          _unreadable(
            'spendwise_ns.qa.expenses',
            UnreadableReason.notDecodable,
          ),
        ),
      );
      // The real key is not affected by a namespace's damage.
      expect(await _storage(raw).read(), isNull);
    });

    test(
      'without raw access (native platforms) behaviour is unchanged',
      () async {
        SharedPreferences.setMockInitialValues({});
        expect(await _storage(const UnsupportedRawStorage()).read(), isNull);
      },
    );
  });

  group('no writes when integrity is uncertain', () {
    test('loading damaged data fails and every write is refused', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ExpenseProvider(
        storage: _storage(FakeRawStorage({_key: _damaged})),
      );
      await provider.loadExpenses();

      expect(provider.status, ExpenseLoadStatus.failed);
      expect(provider.loadError, isA<ExpenseStorageUnreadableException>());
      expect(provider.expenses, isEmpty);
      await expectLater(provider.addExpense(_e('n', 1)), throwsStateError);
      await expectLater(provider.deleteExpense('a'), throwsStateError);
      await expectLater(
        provider.updateExpense(_e('a', 1250), _e('a', 1)),
        throwsStateError,
      );
      expect(() => provider.exportBackup(), throwsStateError);
      expect(await _prefsKeys(), isEmpty, reason: 'nothing written');
    });

    test('damage after loading stops the next write and editing', () async {
      SharedPreferences.setMockInitialValues({'expenses': _valid});
      final raw = FakeRawStorage({_key: _stored(_valid)});
      final provider = ExpenseProvider(storage: _storage(raw));
      await provider.loadExpenses();
      expect(provider.status, ExpenseLoadStatus.ready);

      // Another tab (or anything else) leaves an undecodable value.
      SharedPreferences.setMockInitialValues({});
      raw.values[_key] = _damaged;

      await expectLater(
        provider.addExpense(_e('n', 1)),
        throwsA(isA<ExpenseStorageUnreadableException>()),
      );
      expect(provider.status, ExpenseLoadStatus.failed);
      expect(provider.loadError, isA<ExpenseStorageUnreadableException>());
      await expectLater(provider.addExpense(_e('m', 1)), throwsStateError);
      expect(await _prefsKeys(), isEmpty, reason: 'nothing written');
      expect(raw.values[_key], _damaged);
    });

    test('valid data: add, update and delete work as before', () async {
      SharedPreferences.setMockInitialValues({'expenses': _valid});
      final raw = FakeRawStorage({_key: _stored(_valid)});
      final provider = ExpenseProvider(storage: _storage(raw));
      await provider.loadExpenses();

      await provider.addExpense(_e('c', 300));
      await provider.updateExpense(_e('c', 300), _e('c', 400));
      await provider.deleteExpectedExpense(_e('b', -500));

      final prefs = await SharedPreferences.getInstance();
      final stored = decodeExpenses(prefs.getString('expenses')!).expenses;
      expect(stored.map((e) => (e.id, e.amount.cents)), [
        ('a', 1250),
        ('c', 400),
      ]);
    });

    test('an unreadable legacy backup is never replaced, and the rewrite '
        'that needed it is refused', () async {
      SharedPreferences.setMockInitialValues({'expenses': _legacy});
      final raw = FakeRawStorage({
        _key: _stored(_legacy),
        _legacyKey: _damaged,
      });
      final storage = _storage(raw);
      final provider = ExpenseProvider(storage: storage);
      await provider.loadExpenses();
      expect(provider.status, ExpenseLoadStatus.ready);

      await expectLater(
        provider.addExpense(_e('n', 1)),
        throwsA(
          _unreadable('expenses_legacy_backup', UnreadableReason.notDecodable),
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('expenses'), _legacy, reason: 'not rewritten');
      expect(prefs.containsKey('expenses_legacy_backup'), isFalse);
      expect(raw.values[_legacyKey], _damaged);

      // Called directly, it refuses too.
      await expectLater(
        storage.backupLegacyData(_legacy),
        throwsA(isA<ExpenseStorageUnreadableException>()),
      );
    });

    test('a readable legacy backup is still kept as the first one', () async {
      SharedPreferences.setMockInitialValues({
        'expenses': _legacy,
        'expenses_legacy_backup': 'first',
      });
      final storage = _storage(
        FakeRawStorage({_key: _stored(_legacy), _legacyKey: _stored('first')}),
      );
      await storage.backupLegacyData('second');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('expenses_legacy_backup'), 'first');
    });
  });

  group('raw export', () {
    test(
      'includes the damaged value exactly and marks it unreadable',
      () async {
        SharedPreferences.setMockInitialValues({
          'expenses_legacy_backup': _legacy,
        });
        final provider = ExpenseProvider(
          storage: _storage(
            FakeRawStorage({_key: _damaged, _legacyKey: _stored(_legacy)}),
          ),
          clock: () => DateTime.utc(2026, 10, 15, 12),
        );
        await provider.loadExpenses();

        final export = json.decode(await provider.exportRawData()) as Map;
        expect(export['format'], 'spendwise-raw-export');
        expect(export['formatVersion'], 1);
        expect(export['storage'], {
          'expenses': null,
          'expenses_legacy_backup': _legacy,
        });
        expect(export['unreadable'], {
          'expenses': {
            'browserStorageKey': _key,
            'reason': 'notDecodable',
            'exactValueIncluded': true,
            'browserStorageValue': _damaged,
          },
        });
        expect(export['unreadableNote'], isA<String>());
      },
    );

    test('valid data exports exactly the previous format', () async {
      SharedPreferences.setMockInitialValues({'expenses': _valid});
      final provider = ExpenseProvider(
        storage: _storage(FakeRawStorage({_key: _stored(_valid)})),
        clock: () => DateTime.utc(2026, 10, 15, 12),
      );
      await provider.loadExpenses();

      final export = json.decode(await provider.exportRawData()) as Map;
      expect(export.keys, [
        'format',
        'formatVersion',
        'exportedAt',
        'note',
        'storage',
      ]);
      expect(export['storage'], {
        'expenses': _valid,
        'expenses_legacy_backup': null,
      });
    });

    test('when the value cannot be retrieved, the export says so', () async {
      SharedPreferences.setMockInitialValues({});
      final raw = FakeRawStorage()..inaccessible = true;
      final provider = ExpenseProvider(storage: _storage(raw));
      await provider.loadExpenses();

      final export = json.decode(await provider.exportRawData()) as Map;
      final entry = (export['unreadable'] as Map)['expenses'] as Map;
      expect(entry['reason'], 'inaccessible');
      expect(entry['exactValueIncluded'], isFalse);
      expect(entry['browserStorageValue'], isNull);
    });
  });

  group('migration', () {
    test('an unreadable source is not migrated as empty', () async {
      SharedPreferences.setMockInitialValues({});
      final db = SpendWiseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final migration = JsonToDriftMigration(
        source: _storage(FakeRawStorage({_key: _damaged})),
        target: db,
        clock: () => DateTime.utc(2026, 10, 15, 9),
      );

      await expectLater(
        migration.status(),
        throwsA(isA<ExpenseStorageUnreadableException>()),
      );
      final result = await migration.migrate();
      expect(result.status, MigrationStatus.failed);
      for (final table in [
        'expenses',
        'migration_snapshots',
        'migration_runs',
      ]) {
        final c = await db
            .customSelect('SELECT COUNT(*) c FROM $table')
            .getSingle();
        expect(c.read<int>('c'), 0, reason: table);
      }
    });
  });

  testWidgets('the app explains the problem and offers the raw export', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final files = FakeFileTransfer();
    final raw = FakeRawStorage({_key: _damaged});
    await tester.pumpWidget(
      SpendWiseApp(
        storage: _storage(raw),
        platform: fakePlatform(files: files, rawStorage: raw),
        clock: () => DateTime(2026, 10, 15),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your saved expenses could not be read.'), findsOneWidget);
    expect(
      find.textContaining('has not changed or replaced it'),
      findsOneWidget,
    );
    expect(
      find.textContaining('cannot repair it automatically'),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Export raw data'));
    await tester.pumpAndSettle();
    final saved = json.decode(files.saved.single.text) as Map;
    expect(
      ((saved['unreadable'] as Map)['expenses'] as Map)['browserStorageValue'],
      _damaged,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Your saved expenses could not be read.'), findsOneWidget);
    expect(await tester.runAsync(_prefsKeys), isEmpty);
    expect(raw.values[_key], _damaged);
  });
}
