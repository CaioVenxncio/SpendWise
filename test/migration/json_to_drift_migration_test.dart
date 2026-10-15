import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/backup/expense_backup.dart';
import 'package:spendwise/data/drift/database.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/migration/json_to_drift_migration.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/repositories/drift_expense_repository.dart';
import 'package:spendwise/repositories/expense_repository.dart';
import 'package:spendwise/repositories/json_expense_repository.dart';

import '../support/fake_expense_storage.dart';

/// One record as JSON text, with [amount] inserted verbatim.
String _rec(
  String id,
  String amountField, {
  String date = '2024-03-10T12:00:00.000',
}) =>
    '{"id":"$id",$amountField,"description":"desc $id","category":"Food",'
    '"date":"$date"}';

String _list(List<String> records) => '[${records.join(',')}]';

/// As written by the original app (decimal amounts).
final _legacy = _list([
  _rec('l1', '"amount":12.5'),
  _rec('l2', '"amount":0.1', date: '2024-03-11T08:00:00.000'),
  _rec('l3', '"amount":10'),
]);

/// As written by M1+ (integer cents).
final _m1 = _list([
  _rec('c1', '"amountCents":1250'),
  _rec('c2', '"amountCents":-5', date: '2023-12-31T23:59:59.000Z'),
]);

final _mixed = _list([
  _rec('l1', '"amount":19.99'),
  _rec('c1', '"amountCents":1', date: '2026-10-14T00:00:00.000+02:00'),
  _rec('l2', '"amount":0.2', date: '2024-02-29T08:00:00'),
]);

class _Env {
  _Env(String? data, {SpendWiseDatabase? db})
    : storage = FakeExpenseStorage(data: data),
      db = db ?? SpendWiseDatabase(NativeDatabase.memory());

  final FakeExpenseStorage storage;
  final SpendWiseDatabase db;

  JsonToDriftMigration migration() => JsonToDriftMigration(
    source: storage,
    target: db,
    clock: () => DateTime.utc(2026, 10, 15, 9),
  );

  Future<List<Expense>> rows() async =>
      (await DriftExpenseRepository(db).load()).expenses;

  Future<int> count(String table) async =>
      (await db.customSelect('SELECT COUNT(*) c FROM $table').getSingle())
          .read<int>('c');

  /// The JSON store must never be written by the migration.
  void expectSourceUntouched(String? original) {
    expect(storage.data, original);
    expect(storage.writeCount, 0);
    expect(storage.backupCount, 0);
  }

  Future<void> expectTargetEmpty() async {
    expect(await count('expenses'), 0);
    expect(await count('migration_snapshots'), 0);
    expect(await count('migration_runs'), 0);
  }
}

List<String> _ids(List<Expense> es) => es.map((e) => e.id).toList();

void main() {
  late _Env env;
  tearDown(() => env.db.close());

  group('source formats', () {
    test('original legacy JSON migrates exactly', () async {
      env = _Env(_legacy);

      final result = await env.migration().migrate();

      expect(result.status, MigrationStatus.completed);
      expect(result.newRecords, 3);
      expect(result.totalCents, BigInt.from(1250 + 10 + 1000));
      final rows = await env.rows();
      expect(_ids(rows), ['l1', 'l2', 'l3']);
      expect(rows.map((e) => e.amount.cents), [1250, 10, 1000]);
      expect(rows.map((e) => e.description), ['desc l1', 'desc l2', 'desc l3']);
      expect(rows.map((e) => e.category).toSet(), {'Food'});
      expect(rows[1].dateText, '2024-03-11T08:00:00.000');
      env.expectSourceUntouched(_legacy);
    });

    test('M1 JSON migrates exactly', () async {
      env = _Env(_m1);

      final result = await env.migration().migrate();

      expect(result.status, MigrationStatus.completed);
      final rows = await env.rows();
      expect(rows.map((e) => e.amount.cents), [1250, -5]);
      expect(rows[1].dateText, '2023-12-31T23:59:59.000Z');
    });

    test('mixed legacy and M1 records keep order and original dates', () async {
      env = _Env(_mixed);

      final result = await env.migration().migrate();

      expect(result.status, MigrationStatus.completed);
      final rows = await env.rows();
      expect(_ids(rows), ['l1', 'c1', 'l2']);
      expect(rows.map((e) => e.amount.cents), [1999, 1, 20]);
      expect(rows.map((e) => e.dateText), [
        '2024-03-10T12:00:00.000',
        '2026-10-14T00:00:00.000+02:00',
        '2024-02-29T08:00:00',
      ]);
      final run = await env.db.select(env.db.migrationRuns).getSingle();
      expect(run.hadLegacyRecords, isTrue);
      expect(run.totalCents, '2020');
    });

    test('exact monetary boundaries', () async {
      final raw = _list([
        _rec('max', '"amountCents":9007199254740991'),
        _rec('max2', '"amountCents":9007199254740991'),
        _rec('min', '"amountCents":-9007199254740991'),
        _rec('cent', '"amountCents":1'),
      ]);
      env = _Env(raw);

      final result = await env.migration().migrate();

      expect(result.status, MigrationStatus.completed);
      expect((await env.rows()).map((e) => e.amount.cents), [
        Money.maxCents,
        Money.maxCents,
        Money.minCents,
        1,
      ]);
      // Above Money's range, still exact.
      expect(result.totalCents, BigInt.from(Money.maxCents) + BigInt.one);
      final run = await env.db.select(env.db.migrationRuns).getSingle();
      expect(run.totalCents, '9007199254740992');
    });

    test('an absent source migrates as empty, once', () async {
      env = _Env(null);

      final first = await env.migration().migrate();
      final second = await env.migration().migrate();

      expect(first.status, MigrationStatus.completed);
      expect(first.fingerprint, absentSourceFingerprint);
      expect(second.status, MigrationStatus.alreadyMigrated);
      expect(await env.count('expenses'), 0);
      expect((await env.migration().snapshots()).single.rawText, isNull);
    });

    test('an empty list migrates as empty', () async {
      env = _Env('[]');
      final result = await env.migration().migrate();
      expect(result.status, MigrationStatus.completed);
      expect(result.newRecords, 0);
      expect(await env.count('migration_runs'), 1);
    });
  });

  group('invalid sources are blocked without writing', () {
    final cases = <String, String>{
      'corrupted JSON': '[{"id":"a",',
      'not a list': '{"id":"a"}',
      'legacy amount with 3 decimals': _list([_rec('a', '"amount":12.345')]),
      'legacy binary artifact': _list([
        _rec('a', '"amount":0.30000000000000004'),
      ]),
      'legacy exponent': _list([_rec('a', '"amount":1e21')]),
      'fractional cents': _list([_rec('a', '"amountCents":12.5')]),
      'cents out of range': _list([
        _rec('a', '"amountCents":9007199254740992'),
      ]),
      'both amount fields': _list([
        _rec('a', '"amount":1.5,"amountCents":150'),
      ]),
      'string amount': _list([_rec('a', '"amount":"12.50"')]),
      'invalid date': _list([_rec('a', '"amountCents":1', date: 'yesterday')]),
    };
    cases.forEach((name, raw) {
      test(name, () async {
        env = _Env(raw);

        final result = await env.migration().migrate();

        expect(result.status, MigrationStatus.blocked);
        expect(result.blockReason, MigrationBlockReason.invalidSource);
        await env.expectTargetEmpty();
        env.expectSourceUntouched(raw);
      });
    });

    test('messages never contain record content', () async {
      env = _Env(_list([_rec('SECRET-ID', '"amount":12.345')]));
      final result = await env.migration().migrate();
      expect('${result.message} $result', isNot(contains('SECRET')));
      expect('${result.message}', isNot(contains('12.345')));
    });
  });

  group('duplicate IDs in the source', () {
    test('identical duplicates are collapsed and counted', () async {
      final raw = _list([
        _rec('a', '"amountCents":1'),
        _rec('b', '"amountCents":2'),
        _rec('a', '"amountCents":1'),
        _rec('a', '"amountCents":1'),
      ]);
      env = _Env(raw);

      final result = await env.migration().migrate();

      expect(result.status, MigrationStatus.completed);
      expect(result.sourceRecords, 4);
      expect(result.duplicatesCollapsed, 2);
      expect(result.newRecords, 2);
      expect(_ids(await env.rows()), ['a', 'b']);
      final run = await env.db.select(env.db.migrationRuns).getSingle();
      expect(run.duplicatesCollapsed, 2);
    });

    test(
      'a legacy and an M1 record with the same value are identical',
      () async {
        env = _Env(
          _list([_rec('a', '"amount":12.5'), _rec('a', '"amountCents":1250')]),
        );
        final result = await env.migration().migrate();
        expect(result.status, MigrationStatus.completed);
        expect(result.duplicatesCollapsed, 1);
      },
    );

    test('conflicting duplicates block the migration', () async {
      final raw = _list([
        _rec('a', '"amountCents":1'),
        _rec('a', '"amountCents":2'),
      ]);
      env = _Env(raw);

      final result = await env.migration().migrate();

      expect(result.status, MigrationStatus.blocked);
      expect(result.blockReason, MigrationBlockReason.conflictingDuplicateIds);
      expect(result.conflictingIds, ['a']);
      await env.expectTargetEmpty();
      env.expectSourceUntouched(raw);
    });

    test('a date-text difference makes duplicates conflict', () async {
      env = _Env(
        _list([
          _rec('a', '"amountCents":1', date: '2024-01-01T00:00:00.000Z'),
          _rec('a', '"amountCents":1', date: '2024-01-01T00:00:00Z'),
        ]),
      );
      final result = await env.migration().migrate();
      expect(result.blockReason, MigrationBlockReason.conflictingDuplicateIds);
    });
  });

  group('snapshot and marker', () {
    test(
      'store the exact source text, fingerprint and legacy backup',
      () async {
        env = _Env(_legacy)..storage.legacyBackup = '[old legacy text]';

        final result = await env.migration().migrate();

        final snapshot = (await env.migration().snapshots()).single;
        expect(snapshot.rawText, _legacy);
        expect(snapshot.legacyBackupText, '[old legacy text]');
        expect(snapshot.fingerprint, sourceFingerprint(_legacy));
        expect(snapshot.fingerprint, result.fingerprint);
        expect(snapshot.fingerprint, startsWith('sha256:'));
        expect(snapshot.sourceKey, 'expenses');
        final run = await env.db.select(env.db.migrationRuns).getSingle();
        expect(run.algorithmVersion, migrationAlgorithmVersion);
        expect(run.sourceRecords, 3);
        expect(run.importedRecords, 3);
        expect(run.approvedChangedSource, isFalse);
        expect(run.completedAt, '2026-10-15T09:00:00.000Z');
      },
    );

    test('fingerprints follow exact text', () {
      expect(sourceFingerprint('[]'), sourceFingerprint('[]'));
      expect(sourceFingerprint('[]'), isNot(sourceFingerprint('[ ]')));
      expect(sourceFingerprint(null), absentSourceFingerprint);
    });
  });

  group('injected failures roll everything back', () {
    for (final step in MigrationStep.values) {
      test('failure at $step', () async {
        env = _Env(_mixed);
        final failing = env.migration()
          ..onStep = (s) {
            if (s == step) throw StateError('injected at $s');
          };

        final result = await failing.migrate();

        expect(result.status, MigrationStatus.failed);
        await env.expectTargetEmpty();
        env.expectSourceUntouched(_mixed);

        // A retry succeeds and is complete.
        final retry = await env.migration().migrate();
        expect(retry.status, MigrationStatus.completed);
        expect(_ids(await env.rows()), ['l1', 'c1', 'l2']);
        expect(await env.count('migration_runs'), 1);
      });
    }

    test('a read failure is never mistaken for an earlier migration', () async {
      env = _Env(null);
      await env.migration().migrate(); // records the absent source
      env.storage
        ..data = _legacy
        ..failReads = true;

      final result = await env.migration().migrate();

      expect(result.status, MigrationStatus.failed);
      expect(await env.count('migration_runs'), 1);
    });

    test('a failure reading the source writes nothing', () async {
      env = _Env(_legacy)..storage.failReads = true;
      final result = await env.migration().migrate();
      expect(result.status, MigrationStatus.failed);
      await env.expectTargetEmpty();
    });

    test('failures are logged without content', () async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logs.add('$m');
      addTearDown(() => debugPrint = original);

      env = _Env(_list([_rec('SECRET', '"amountCents":1')]));
      await (env.migration()..onStep = (_) => throw StateError('SECRET'))
          .migrate();

      expect(logs.join(), isNot(contains('SECRET')));
    });
  });

  group('repeated migration', () {
    test('running twice does not duplicate anything', () async {
      env = _Env(_legacy);

      final first = await env.migration().migrate();
      final second = await env.migration().migrate();

      expect(first.status, MigrationStatus.completed);
      expect(second.status, MigrationStatus.alreadyMigrated);
      expect(await env.count('expenses'), 3);
      expect(await env.count('migration_snapshots'), 1);
      expect(await env.count('migration_runs'), 1);
    });

    test('status reports progress without writing', () async {
      env = _Env(_legacy);

      final before = await env.migration().status();
      expect(before.status, MigrationStatus.notStarted);
      expect(before.newRecords, 3);
      await env.expectTargetEmpty();

      await env.migration().migrate();
      expect(
        (await env.migration().status()).status,
        MigrationStatus.alreadyMigrated,
      );
    });

    test('status reports blocked sources', () async {
      env = _Env('[{"broken"');
      final status = await env.migration().status();
      expect(status.status, MigrationStatus.blocked);
      expect(status.blockReason, MigrationBlockReason.invalidSource);
    });
  });

  group('existing target data', () {
    Future<void> seed(SpendWiseDatabase db, List<Expense> rows) async {
      final repo = DriftExpenseRepository(db);
      await repo.load();
      await repo.importExpenses(rows);
    }

    Expense e(String id, int cents, {String desc = 'x'}) => Expense(
      id: id,
      amount: Money.fromCents(cents),
      description: desc,
      category: 'Food',
      date: DateTime.parse('2024-03-10T12:00:00.000'),
      dateText: '2024-03-10T12:00:00.000',
    );

    test('unrelated rows are kept, migrated rows come after them', () async {
      env = _Env(_m1);
      await seed(env.db, [e('other', 7)]);

      final result = await env.migration().migrate();

      expect(result.status, MigrationStatus.completed);
      expect(_ids(await env.rows()), ['other', 'c1', 'c2']);
    });

    test('identical existing rows are skipped and counted', () async {
      env = _Env(
        _list([_rec('a', '"amountCents":5'), _rec('b', '"amountCents":6')]),
      );
      await seed(env.db, [e('a', 5, desc: 'desc a')]);

      final result = await env.migration().migrate();

      expect(result.status, MigrationStatus.completed);
      expect(result.alreadyPresent, 1);
      expect(result.newRecords, 1);
      expect(_ids(await env.rows()), ['a', 'b']);
    });

    test('a conflicting existing row blocks and changes nothing', () async {
      env = _Env(
        _list([_rec('a', '"amountCents":5'), _rec('b', '"amountCents":6')]),
      );
      await seed(env.db, [e('a', 999, desc: 'desc a')]);

      final result = await env.migration().migrate();

      expect(result.status, MigrationStatus.blocked);
      expect(result.blockReason, MigrationBlockReason.targetConflict);
      expect(result.conflictingIds, ['a']);
      final rows = await env.rows();
      expect(_ids(rows), ['a']);
      expect(rows.single.amount.cents, 999);
      expect(await env.count('migration_snapshots'), 0);
    });
  });

  group('source changes', () {
    test('a change during the migration rolls back', () async {
      env = _Env(_legacy);
      final m = env.migration()
        ..onStep = (s) {
          if (s == MigrationStep.rowsInserted) {
            env.storage.data = _m1; // e.g. an older tab without the lock
          }
        };

      final result = await m.migrate();

      expect(result.status, MigrationStatus.failed);
      await env.expectTargetEmpty();
    });

    test('a change after migration is detected, not imported', () async {
      env = _Env(_legacy);
      await env.migration().migrate();
      final changed = _list([
        _rec('l1', '"amount":12.5'),
        _rec('l2', '"amount":0.1', date: '2024-03-11T08:00:00.000'),
        _rec('l3', '"amount":10'),
        _rec('new', '"amountCents":300'),
      ]);
      env.storage.data = changed;

      final status = await env.migration().status();
      expect(status.status, MigrationStatus.sourceChanged);
      expect(status.newRecords, 1);
      expect(status.alreadyPresent, 3);
      expect(status.newTotalCents, BigInt.from(300));
      expect(status.totalCents, BigInt.from(1250 + 10 + 1000 + 300));

      final refused = await env.migration().migrate();
      expect(refused.status, MigrationStatus.sourceChanged);
      expect(await env.count('expenses'), 3);
      expect(await env.count('migration_runs'), 1);
    });

    test('an approved change imports only new records', () async {
      env = _Env(_legacy);
      await env.migration().migrate();
      env.storage.data = _list([
        _rec('l1', '"amount":12.5'),
        _rec('new', '"amountCents":300'),
      ]);
      final status = await env.migration().status();

      final result = await env.migration().migrate(
        approvedChangedFingerprint: status.fingerprint,
      );

      expect(result.status, MigrationStatus.completed);
      expect(result.newRecords, 1);
      expect(result.alreadyPresent, 1);
      // l2 and l3, removed from JSON, stay in SQLite: nothing is deleted.
      expect(_ids(await env.rows()), ['l1', 'l2', 'l3', 'new']);
      final runs = await env.db.select(env.db.migrationRuns).get();
      expect(runs.last.approvedChangedSource, isTrue);
      expect(await env.count('migration_snapshots'), 2);
    });

    test('approval must name the current fingerprint', () async {
      env = _Env(_legacy);
      await env.migration().migrate();
      env.storage.data = _m1;

      final result = await env.migration().migrate(
        approvedChangedFingerprint: sourceFingerprint(_mixed),
      );

      expect(result.status, MigrationStatus.sourceChanged);
      expect(await env.count('expenses'), 3);
    });

    test('an approved change that conflicts is blocked', () async {
      env = _Env(_legacy);
      await env.migration().migrate();
      env.storage.data = _list([_rec('l1', '"amount":99.99')]);
      final fp = (await env.migration().status()).fingerprint;

      final result = await env.migration().migrate(
        approvedChangedFingerprint: fp,
      );

      expect(result.status, MigrationStatus.blocked);
      expect(result.blockReason, MigrationBlockReason.targetConflict);
      expect((await env.rows()).first.amount.cents, 1250);
    });

    test(
      'a source corrupted after migration is a change, not a block',
      () async {
        env = _Env(_legacy);
        await env.migration().migrate();
        env.storage.data = '{corrupt';

        final status = await env.migration().status();

        expect(status.status, MigrationStatus.sourceChanged);
        expect(status.blockReason, MigrationBlockReason.invalidSource);
        expect(await env.count('expenses'), 3);
      },
    );

    test('reformatted but equal text is a change (retry vs change)', () async {
      env = _Env('[]');
      await env.migration().migrate();
      env.storage.data = '[ ]';
      expect(
        (await env.migration().migrate()).status,
        MigrationStatus.sourceChanged,
      );
    });
  });

  group('concurrent attempts', () {
    test('two attempts sharing the storage lock: one migrates', () async {
      env = _Env(_mixed);
      final results = await Future.wait([
        env.migration().migrate(),
        env.migration().migrate(),
      ]);

      expect(results.map((r) => r.status).toSet(), {
        MigrationStatus.completed,
        MigrationStatus.alreadyMigrated,
      });
      expect(await env.count('expenses'), 3);
      expect(await env.count('migration_runs'), 1);
    });

    test(
      'without a shared lock, SQLite constraints prevent duplicates',
      () async {
        final dir = Directory.systemTemp.createTempSync('spendwise_mig_');
        final file = File('${dir.path}/db.sqlite');
        // Two "tabs": separate locks and separate connections to one file.
        env = _Env(_mixed, db: SpendWiseDatabase(NativeDatabase(file)));
        final otherDb = SpendWiseDatabase(NativeDatabase(file));
        // Close both connections before deleting (Windows locks the file).
        addTearDown(() async {
          await otherDb.close();
          await env.db.close();
          dir.deleteSync(recursive: true);
        });
        final other = JsonToDriftMigration(
          source: FakeExpenseStorage(data: _mixed),
          target: otherDb,
        );
        // Make sure both connections are open before racing.
        await env.db.customSelect('SELECT 1').get();
        await otherDb.customSelect('SELECT 1').get();

        final results = await Future.wait([
          env.migration().migrate(),
          other.migrate(),
        ]);

        final statuses = results.map((r) => r.status).toList();
        // ignore: avoid_print
        print('race without shared lock: $statuses');
        expect(
          statuses.where((s) => s == MigrationStatus.completed),
          hasLength(1),
        );
        expect(
          statuses.where((s) => s != MigrationStatus.completed),
          everyElement(
            anyOf(MigrationStatus.alreadyMigrated, MigrationStatus.failed),
          ),
        );
        expect(await env.count('expenses'), 3);
        expect(await env.count('migration_runs'), 1);
        expect(await env.count('migration_snapshots'), 1);
      },
    );
  });

  test('large dataset (10,000 mixed records)', () async {
    final records = [
      for (var i = 0; i < 10000; i++)
        i.isEven
            ? _rec(
                'r$i',
                '"amount":${i ~/ 100}.${(i % 100).toString().padLeft(2, '0')}',
              )
            : _rec('r$i', '"amountCents":$i'),
    ];
    env = _Env(_list(records));

    final watch = Stopwatch()..start();
    final result = await env.migration().migrate();
    watch.stop();

    expect(result.status, MigrationStatus.completed);
    expect(result.newRecords, 10000);
    final rows = await env.rows();
    expect(rows.first.id, 'r0');
    expect(rows.last.id, 'r9999');
    final expected = List.generate(
      10000,
      (i) => i,
    ).fold<BigInt>(BigInt.zero, (s, i) => s + BigInt.from(i));
    expect(result.totalCents, expected);
    // ignore: avoid_print
    print('10,000 records migrated in ${watch.elapsedMilliseconds} ms');
  });

  test('40,000 records: above the SQLite bound-parameter limit', () async {
    env = _Env(
      _list([for (var i = 0; i < 40000; i++) _rec('p$i', '"amountCents":1')]),
    );

    final result = await env.migration().migrate();

    expect(result.status, MigrationStatus.completed);
    expect(await env.count('expenses'), 40000);
    expect(result.newTotalCents, BigInt.from(40000));
    expect(
      (await env.migration().migrate()).status,
      MigrationStatus.alreadyMigrated,
    );
  });

  group('recovery', () {
    test('the snapshot survives the source becoming unreadable', () async {
      env = _Env(_legacy);
      await env.migration().migrate();
      env.storage.data = '{corrupted';

      final snapshot = (await env.migration().snapshots()).single;

      expect(snapshot.rawText, _legacy);
      expect(sourceFingerprint(snapshot.rawText), snapshot.fingerprint);
      // Wrapped for export without decoding.
      final export = encodeRawExport(
        snapshot.toRawData(),
        exportedAt: DateTime.utc(2026),
      );
      expect(
        ((json.decode(export) as Map)['storage'] as Map)['expenses'],
        _legacy,
      );
    });

    test(
      'rollback to JSON: export from SQLite, confirmed import into JSON',
      () async {
        env = _Env(_legacy);
        await env.migration().migrate();

        // New activity after the migration, in SQLite only.
        final drift = DriftExpenseRepository(env.db);
        await drift.load();
        await drift.add(
          Expense(
            id: 'after',
            amount: Money.fromCents(725),
            description: 'after migration',
            category: 'Food',
            date: DateTime.parse('2026-10-15T10:00:00.000'),
            dateText: '2026-10-15T10:00:00.000',
          ),
        );
        await drift.delete('l3');

        // 1. Export a backup from SQLite.
        final backupFile = utf8.encode(
          encodeBackup(
            await drift.load().then((s) => s.expenses),
            exportedAt: DateTime.utc(2026, 10, 15),
          ),
        );

        // 2. Back on JSON (unchanged since migration): preview, then import.
        final json = JsonExpenseRepository(env.storage);
        await json.load();
        final preview = previewImport(
          parseBackup(backupFile),
          (await json.load()).expenses,
        );
        expect(preview.newExpenses.map((e) => e.id), ['after']);
        expect(preview.alreadyPresent, 2);
        expect(preview.conflictingIds, isEmpty);
        final outcome = await json.importExpenses(preview.newExpenses);

        // The post-migration record is back in JSON; nothing was overwritten.
        expect(_ids(outcome.expenses), ['l1', 'l2', 'l3', 'after']);
        // Documented limitation: a deletion made in SQLite (l3) is not
        // carried back, because import never deletes.
        expect(outcome.expenses.any((e) => e.id == 'l3'), isTrue);
        // The legacy original is preserved before JSON is rewritten.
        expect(env.storage.legacyBackup, _legacy);
      },
    );

    test('edits in SQLite after migration leave the migration state and '
        'the JSON source untouched', () async {
      env = _Env(_legacy);
      await env.migration().migrate();
      final snapshotBefore = (await env.migration().snapshots()).single;

      final drift = DriftExpenseRepository(env.db);
      final loaded = (await drift.load()).expenses;
      await drift.update(loaded[0], loaded[0].edited(description: 'edited'));
      await drift.deleteExpected(loaded[1]);

      expect(
        (await env.migration().status()).status,
        MigrationStatus.alreadyMigrated,
      );
      final snapshotAfter = (await env.migration().snapshots()).single;
      expect(snapshotAfter.fingerprint, snapshotBefore.fingerprint);
      expect(snapshotAfter.rawText, _legacy);
      env.expectSourceUntouched(_legacy);
    });

    // Known M2 blocker (see DEVELOPMENT_HANDOFF.md): the documented rollback
    // cannot carry an edit back to JSON, because import never replaces.
    test('rollback import is blocked by a record edited in SQLite', () async {
      env = _Env(_legacy);
      await env.migration().migrate();
      final drift = DriftExpenseRepository(env.db);
      final l1 = (await drift.load()).expenses.first;
      await drift.update(l1, l1.edited(amount: Money.fromCents(1300)));

      final backupFile = utf8.encode(
        encodeBackup(
          (await drift.load()).expenses,
          exportedAt: DateTime.utc(2026, 10, 15),
        ),
      );
      final json = JsonExpenseRepository(env.storage);
      final preview = previewImport(
        parseBackup(backupFile),
        (await json.load()).expenses,
      );

      expect(preview.conflictingIds, ['l1']);
      await expectLater(
        json.importExpenses(parseBackup(backupFile).expenses),
        throwsA(isA<ImportConflictException>()),
      );
      env.expectSourceUntouched(_legacy);
    });
  });
}
