// Development-only page for checking the JSON → SQLite migration in a real
// browser. Not used by the app. Build with:
//   flutter build web -t lib/dev/migration_web_check.dart -o build/migration_check
//
// Uses ISOLATED test storage only: localStorage keys prefixed with
// `spendwise_check.` (never the app's `flutter.expenses`) and its own
// database name (`?db=` in the URL, default `spendwise_stage3_check`).
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../data/drift/connection.dart';
import '../data/drift/database.dart';
import '../migration/json_to_drift_migration.dart';
import '../platform/platform_services.dart';
import '../platform/platform_services_web.dart';
import '../repositories/drift_expense_repository.dart';
import '../services/expense_storage.dart';

const _prefix = 'spendwise_check.';

/// Test-only storage on prefixed localStorage keys.
class _CheckStorage implements ExpenseStorage {
  final CrossTabLock _lock = web.window.navigator.has('locks')
      ? WebLocksLock()
      : InProcessLock();

  @override
  String get sourceKey => '${_prefix}expenses';

  @override
  Set<String> get watchKeys => {
    '${_prefix}expenses',
    '${_prefix}expenses_legacy_backup',
  };

  @override
  LockKind get lockKind => _lock.kind;

  @override
  Future<T> exclusive<T>(Future<T> Function() action) =>
      _lock.run('${_prefix}expenses', action);

  @override
  Future<String?> read() async =>
      web.window.localStorage.getItem('${_prefix}expenses');

  @override
  Future<String?> readLegacyBackup() async =>
      web.window.localStorage.getItem('${_prefix}expenses_legacy_backup');

  @override
  Future<void> write(String data) =>
      throw UnsupportedError('The migration check never writes JSON');

  @override
  Future<void> backupLegacyData(String data) =>
      throw UnsupportedError('The migration check never writes JSON');

  @override
  Future<StoredExpenseText> readStoredText() async => StoredExpenseText(
    expenses: await read(),
    legacyBackup: await readLegacyBackup(),
  );
}

final _text = ValueNotifier('starting');
final _state = <String, Object?>{};

void _publish() {
  final text = const JsonEncoder.withIndent('  ').convert(_state);
  web.window.setProperty('migCheckState'.toJS, text.toJS);
  _text.value = text;
}

Map<String, Object?> _resultJson(MigrationResult r) => {
  'status': r.status.name,
  'blockReason': r.blockReason?.name,
  'fingerprint': r.fingerprint,
  'sourceRecords': r.sourceRecords,
  'newRecords': r.newRecords,
  'alreadyPresent': r.alreadyPresent,
  'duplicatesCollapsed': r.duplicatesCollapsed,
  'conflictingIds': r.conflictingIds,
  'totalCents': r.totalCents?.toString(),
};

void _expose(String name, Future<Object?> Function(List<String> args) f) {
  web.window.setProperty(
    name.toJS,
    (([JSString? a, JSString? b]) {
      final args = [if (a != null) a.toDart, if (b != null) b.toDart];
      return f(args).then((v) => json.encode(v).toJS).toJS;
    }).toJS,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final params = Uri.base.queryParameters;
  final dbName = params['db'] ?? 'spendwise_stage3_check';
  _state['database'] = dbName;
  final db = SpendWiseDatabase(
    openSpendWiseConnection(
      name: dbName,
      onWebResult: (r) {
        _state['implementation'] = r.implementation;
        _publish();
      },
    ),
  );
  final storage = _CheckStorage();
  _state['lock'] = storage.lockKind.name;
  JsonToDriftMigration migration() =>
      JsonToDriftMigration(source: storage, target: db);

  _expose('migSeed', (args) async {
    web.window.localStorage.setItem('${_prefix}expenses', args.first);
    return 'seeded';
  });
  _expose('migStatus', (_) async => _resultJson(await migration().status()));
  _expose(
    'migRun',
    (args) async => _resultJson(
      await migration().migrate(
        approvedChangedFingerprint: args.isEmpty ? null : args.first,
      ),
    ),
  );
  _expose('migRows', (_) async {
    final rows = (await DriftExpenseRepository(db).load()).expenses;
    return [for (final e in rows) e.toMap()];
  });
  _expose('migMeta', (_) async {
    final snaps = await migration().snapshots();
    final runs = await db.select(db.migrationRuns).get();
    return {
      'snapshots': [
        for (final s in snaps)
          {'fingerprint': s.fingerprint, 'rawLength': s.rawText?.length},
      ],
      'runs': runs.length,
    };
  });

  await db.customSelect('SELECT 1').get();
  _state['ready'] = true;
  _publish();

  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Migration check (dev, test data)')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ValueListenableBuilder<String>(
            valueListenable: _text,
            builder: (_, text, _) => SelectableText(text),
          ),
        ),
      ),
    ),
  );
}
