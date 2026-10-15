import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/drift/database.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/repositories/drift_expense_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

Expense _e(String id, int cents) => Expense(
  id: id,
  amount: Money.fromCents(cents),
  description: 'd',
  category: 'General',
  date: DateTime(2024, 3, 1),
);

void main() {
  group('schema v1', () {
    late SpendWiseDatabase db;
    setUp(() => db = SpendWiseDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('creates exactly the expected objects', () async {
      final rows = await db
          .customSelect(
            "SELECT type, name, sql FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
          )
          .get();
      expect(
        rows.map((r) => '${r.read<String>('type')} ${r.read<String>('name')}'),
        [
          'index expenses_occurred_at',
          'table expenses',
          'table migration_runs',
          'table migration_snapshots',
        ],
      );
      final table = rows[1].read<String>('sql');
      expect(
        table,
        contains('"seq" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT'),
      );
      expect(table, contains('"id" TEXT NOT NULL UNIQUE'));
      expect(table, contains('"amount_cents" INTEGER NOT NULL CHECK'));
      expect(table, contains('BETWEEN -9007199254740991 AND 9007199254740991'));
      expect(table, contains('"occurred_at" TEXT NOT NULL'));
    });

    test('records schema version 2', () async {
      final v = await db.customSelect('PRAGMA user_version').getSingle();
      expect(v.read<int>('user_version'), 2);
      expect(SpendWiseDatabase.currentSchemaVersion, 2);
    });

    test('migration snapshots have a unique fingerprint', () async {
      final sql = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = 'migration_snapshots'",
          )
          .getSingle();
      expect(
        sql.read<String>('sql'),
        contains('"fingerprint" TEXT NOT NULL UNIQUE'),
      );
      final runs = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = 'migration_runs'",
          )
          .getSingle();
      expect(
        runs.read<String>('sql'),
        contains('REFERENCES migration_snapshots'),
      );
    });

    test('UNIQUE rejects a duplicate ID even through raw SQL', () async {
      await db.customStatement(
        "INSERT INTO expenses (id, amount_cents, description, category, "
        "occurred_at) VALUES ('a', 1, 'd', 'c', '2024-01-01T00:00:00.000')",
      );
      await expectLater(
        db.customStatement(
          "INSERT INTO expenses (id, amount_cents, description, category, "
          "occurred_at) VALUES ('a', 2, 'd', 'c', '2024-01-01T00:00:00.000')",
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
    });

    test('CHECK rejects cents outside the Money range', () async {
      for (final cents in ['9007199254740992', '-9007199254740992']) {
        await expectLater(
          db.customStatement(
            "INSERT INTO expenses (id, amount_cents, description, category, "
            "occurred_at) VALUES ('x', $cents, 'd', 'c', '2024-01-01T00:00:00')",
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
      }
    });

    test('sequence numbers are never reused after deletes', () async {
      final repo = DriftExpenseRepository(db);
      await repo.load();
      await repo.add(_e('a', 1));
      await repo.add(_e('b', 1));
      await repo.delete('b');
      await repo.add(_e('c', 1));

      final seqs = await db
          .customSelect('SELECT id, seq FROM expenses ORDER BY seq')
          .get();
      expect(seqs.map((r) => '${r.read<String>('id')}:${r.read<int>('seq')}'), [
        'a:1',
        'c:3',
      ]);
    });

    test('a row the app cannot read fails load but not readRaw', () async {
      await db.customStatement(
        "INSERT INTO expenses (id, amount_cents, description, category, "
        "occurred_at) VALUES ('bad', 1, 'd', 'c', 'not-a-date')",
      );
      final repo = DriftExpenseRepository(db);

      await expectLater(repo.load(), throwsFormatException);
      final raw = await repo.readRaw();
      expect(raw.expenses, contains('not-a-date'));
      expect(raw.legacyBackup, isNull);
    });
  });

  group('database files', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('spendwise_db_'));
    tearDown(() => dir.deleteSync(recursive: true));

    File dbFile() => File('${dir.path}/spendwise.sqlite');

    test('data persists across connections', () async {
      final first = SpendWiseDatabase(NativeDatabase(dbFile()));
      final repo = DriftExpenseRepository(first);
      await repo.load();
      await repo.add(_e('kept', Money.maxCents));
      await first.close();

      final second = SpendWiseDatabase(NativeDatabase(dbFile()));
      addTearDown(second.close);
      final reread = (await DriftExpenseRepository(second).load()).expenses;
      expect(reread.single.amount.cents, Money.maxCents);
    });

    test('two connections to one file see each other\'s writes', () async {
      final a = SpendWiseDatabase(NativeDatabase(dbFile()));
      final b = SpendWiseDatabase(NativeDatabase(dbFile()));
      addTearDown(() async {
        await a.close();
        await b.close();
      });
      final repoA = DriftExpenseRepository(a);
      final repoB = DriftExpenseRepository(b);
      await repoA.load();
      await repoB.load();

      await repoA.add(_e('from-a', 1));
      final afterB = await repoB.add(_e('from-b', 2));

      expect(afterB.map((e) => e.id), ['from-a', 'from-b']);
    });

    test('a version 1 database is upgraded to 2, keeping its rows', () async {
      // Schema v1 exactly as shipped in Stage 2.
      final v1 = sqlite.sqlite3.open(dbFile().path);
      v1.execute(
        'CREATE TABLE IF NOT EXISTS "expenses" ("seq" INTEGER NOT NULL '
        'PRIMARY KEY AUTOINCREMENT, "id" TEXT NOT NULL UNIQUE, '
        '"amount_cents" INTEGER NOT NULL CHECK ("amount_cents" BETWEEN '
        '-9007199254740991 AND 9007199254740991), "description" TEXT NOT '
        'NULL, "category" TEXT NOT NULL, "occurred_at" TEXT NOT NULL)',
      );
      v1.execute('CREATE INDEX expenses_occurred_at ON expenses (occurred_at)');
      v1.execute(
        "INSERT INTO expenses (id, amount_cents, description, category, "
        "occurred_at) VALUES ('kept', 9007199254740991, 'd', 'c', "
        "'2024-01-01T00:00:00.000+02:00')",
      );
      v1.execute('PRAGMA user_version = 1');
      v1.close();

      final upgraded = SpendWiseDatabase(NativeDatabase(dbFile()));
      addTearDown(upgraded.close);
      final rows = (await DriftExpenseRepository(upgraded).load()).expenses;
      expect(rows.single.amount.cents, Money.maxCents);
      expect(rows.single.dateText, '2024-01-01T00:00:00.000+02:00');
      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.read<int>('user_version'), 2);
      expect(await upgraded.select(upgraded.migrationSnapshots).get(), isEmpty);
    });

    test('a database from a newer schema version is refused', () async {
      final created = SpendWiseDatabase(NativeDatabase(dbFile()));
      final repo = DriftExpenseRepository(created);
      await repo.load();
      await repo.add(_e('a', 1));
      await created.close();

      final raw = sqlite.sqlite3.open(dbFile().path);
      raw.execute('PRAGMA user_version = 3');
      raw.close();

      final reopened = SpendWiseDatabase(NativeDatabase(dbFile()));
      addTearDown(reopened.close);
      await expectLater(
        DriftExpenseRepository(reopened).load(),
        throwsA(isA<UnsupportedSchemaVersionException>()),
      );

      // The newer database is left untouched.
      final check = sqlite.sqlite3.open(dbFile().path);
      addTearDown(check.close);
      expect(check.select('PRAGMA user_version').single.values.single, 3);
      expect(check.select('SELECT id FROM expenses').single['id'], 'a');
    });
  });

  test('the Drift repository never asks SQL for sums', () {
    final source = File('lib/repositories/drift_expense_repository.dart')
        .readAsStringSync();
    expect(source.toLowerCase(), isNot(contains('sum(')));
    expect(source, isNot(contains('.sum()')));
  });

  test('web assets are pinned in the manifest', () {
    final manifest = File('web/web_assets.lock.json').readAsStringSync();
    expect(manifest, contains('"sqlite3"'));
    expect(manifest, contains('"driftWorker"'));
    expect(File('web/sqlite3.wasm').existsSync(), isTrue);
    expect(File('web/drift_worker.js').existsSync(), isTrue);
  });
}
