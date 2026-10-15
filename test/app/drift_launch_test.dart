import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/backup/expense_backup.dart';
import 'package:spendwise/app/app_config.dart';
import 'package:spendwise/app/backend.dart';
import 'package:spendwise/app/drift_launcher.dart';
import 'package:spendwise/data/drift/connection.dart';
import 'package:spendwise/data/drift/database.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/repositories/drift_expense_repository.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/migration/json_to_drift_migration.dart';
import 'package:spendwise/presentation/app_theme.dart';

import '../support/fake_expense_storage.dart';
import '../support/fake_platform_services.dart';
import '../support/ui_actions.dart';

const _testConfig = AppConfig(backend: StorageBackend.drift, namespace: 't1');

String _rec(String id, String amount, String description) =>
    '{"id":"$id",$amount,"description":"$description","category":"Food",'
    '"date":"2026-10-03T12:00:00.000"}';

final _legacy =
    '[${_rec('a', '"amount":12.5', 'Lunch')},'
    '${_rec('b', '"amount":0.1', 'Gum')}]';

/// One isolated environment: fake JSON source, fake files, and SQLite
/// files in a temporary directory.
class _Env {
  _Env({String? source}) : storage = FakeExpenseStorage(data: source);

  final FakeExpenseStorage storage;
  final files = FakeFileTransfer();
  final tabs = FakeTabChannel();
  final dir = Directory.systemTemp.createTempSync('spendwise_launch_');
  final openedNames = <String>[];
  WebStorageReport? report;
  Object? failOpen;
  void Function(MigrationStep)? onStep;

  File dbFile(String name) => File('${dir.path}/$name.sqlite');

  QueryExecutor executor(
    String name,
    void Function(WebStorageReport) onResult,
  ) {
    openedNames.add(name);
    if (report != null) onResult(report!);
    final error = failOpen;
    if (error != null) {
      return LazyDatabase(() async => throw error);
    }
    return NativeDatabase(dbFile(name));
  }

  Widget app({AppConfig? config = _testConfig}) => SpendWiseApp(
    config: config,
    storage: storage,
    platform: fakePlatform(files: files, tabs: tabs),
    clock: () => DateTime(2026, 10, 15),
    driftExecutor: executor,
    driftLauncher: buildDriftLauncher,
    backendLoader: () async {
      final backend = await AppBackend.openDrift(
        config: config!,
        platform: fakePlatform(files: files),
        jsonStorage: storage,
        openExecutor: executor,
      );
      backend.migration!.onStep = onStep;
      return backend;
    },
  );

  /// A second connection to the same database, like another tab.
  SpendWiseDatabase otherTab() =>
      SpendWiseDatabase(NativeDatabase(dbFile(_testConfig.databaseName)));

  void dispose() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// Lets real (non-fake-async) database work complete between frames.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _start(
  WidgetTester tester,
  _Env env, {
  AppConfig? config = _testConfig,
}) async {
  // Tall enough that the whole migration screen is built.
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(env.app(config: config));
  await _settle(tester);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await _settle(tester);
}

/// Steps 1 and 2: download the backup and confirm it was saved.
Future<void> _backUp(WidgetTester tester) async {
  await tester.ensureVisible(find.textContaining('Download'));
  await tester.tap(find.textContaining('Download'));
  await _settle(tester);
  await tester.ensureVisible(find.byType(CheckboxListTile));
  await tester.tap(find.byType(CheckboxListTile));
  await _settle(tester);
}

Future<void> _confirmMove(
  WidgetTester tester,
  String button, {
  bool backUp = true,
}) async {
  if (backUp) await _backUp(tester);
  await tester.ensureVisible(find.text(button));
  await tester.tap(find.text(button));
  await _settle(tester);
  await tester.tap(find.widgetWithText(FilledButton, 'Move'));
  await _settle(tester);
}

Future<int> _rows(_Env env) async {
  final db = env.otherTab();
  try {
    return (await db
            .customSelect('SELECT COUNT(*) c FROM expenses')
            .getSingle())
        .read<int>('c');
  } finally {
    await db.close();
  }
}

/// Workspace layout (this file's window is 1200 wide): select the row,
/// then Edit in the detail panel.
Future<void> _openForEdit(WidgetTester tester, String description) async {
  await tester.tap(inRow(find.text(description)));
  await _settle(tester);
  await tester.tap(find.text('Edit'));
  await _settle(tester);
}

/// Select the row, Delete in the detail panel, confirm.
Future<void> _deleteViaPanel(WidgetTester tester, String description) async {
  await tester.tap(inRow(find.text(description)));
  await _settle(tester);
  await tester.tap(find.text('Delete'));
  await _settle(tester);
  await tester.tap(find.text('Delete expense'));
  await _settle(tester);
}

void main() {
  late _Env env;
  // The "other tab" connections intentionally open a second database
  // object on the same file.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDown(() => env.dispose());

  testWidgets('default configuration uses JSON and never opens SQLite', (
    tester,
  ) async {
    env = _Env(source: _legacy);
    await tester.pumpWidget(
      SpendWiseApp(
        storage: env.storage,
        platform: fakePlatform(files: env.files),
        clock: () => DateTime(2026, 10, 15),
        driftExecutor: env.executor,
      ),
    );
    await _settle(tester);

    expect(find.text('Lunch'), findsOneWidget);
    expect(env.openedNames, isEmpty);
    expect(env.storage.writeCount, 0);
  });

  testWidgets('Drift on real data fails closed without opening anything', (
    tester,
  ) async {
    env = _Env(source: _legacy);
    await _start(
      tester,
      env,
      config: const AppConfig(backend: StorageBackend.drift),
    );

    expect(
      find.textContaining('cannot start with this configuration'),
      findsOneWidget,
    );
    expect(
      find.textContaining('No data was opened or changed'),
      findsOneWidget,
    );
    expect(env.openedNames, isEmpty);
    expect(env.storage.data, _legacy);
  });

  testWidgets('the database name is namespaced', (tester) async {
    env = _Env();
    await _start(tester, env);
    expect(env.openedNames, ['spendwise_ns_t1']);
    await _unmount(tester);
  });

  testWidgets('fresh installation opens the app directly', (tester) async {
    env = _Env();
    await _start(tester, env);

    expect(find.text('No expenses'), findsOneWidget);
    expect(find.textContaining('Ready to move'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('successful migration after explicit confirmation', (
    tester,
  ) async {
    env = _Env(source: _legacy);
    await _start(tester, env);

    expect(find.text('Ready to move your expenses'), findsOneWidget);
    expect(find.textContaining('Records in saved data: 2'), findsOneWidget);
    expect(find.textContaining(r'To move: 2 ($12.60)'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(await _rows(env), 0);

    // Move stays disabled until a backup is offered and confirmed.
    final move = find.widgetWithText(FilledButton, 'Move 2 expenses');
    expect(tester.widget<FilledButton>(move).onPressed, isNull);
    await _backUp(tester);
    expect(tester.widget<FilledButton>(move).onPressed, isNotNull);

    // Cancelling the confirmation does nothing.
    await tester.tap(find.text('Move 2 expenses'));
    await _settle(tester);
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(await _rows(env), 0);

    await _confirmMove(tester, 'Move 2 expenses', backUp: false);

    expect(find.text('Expenses moved and verified'), findsOneWidget);
    expect(
      find.textContaining('expenses you delete from now on would reappear'),
      findsOneWidget,
    );
    await tester.tap(find.text('Continue'));
    await _settle(tester);

    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Gum'), findsOneWidget);
    expect(find.bySemanticsLabel(r'Total this month: $12.60'), findsOneWidget);
    expect(await _rows(env), 2);
    expect(env.storage.data, _legacy);
    expect(env.storage.writeCount, 0);
    await _unmount(tester);

    // Reopening: already migrated, straight to the app.
    await _start(tester, env);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.textContaining('Ready to move'), findsNothing);
    expect(await _rows(env), 2);
    await _unmount(tester);
  });

  testWidgets('a source changed after migration shows a notice and needs '
      'explicit approval', (tester) async {
    env = _Env(source: _legacy);
    await _start(tester, env);
    await _confirmMove(tester, 'Move 2 expenses');
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    await _unmount(tester);

    // An older tab adds a record to the JSON source.
    env.storage.data =
        '[${_rec('a', '"amount":12.5', 'Lunch')},'
        '${_rec('b', '"amount":0.1', 'Gum')},'
        '${_rec('c', '"amountCents":300', 'Coffee')}]';
    await _start(tester, env);

    expect(find.textContaining('changed after it was moved'), findsOneWidget);
    expect(find.text('Coffee'), findsNothing);
    expect(await _rows(env), 2);

    await tester.tap(find.text('Review'));
    await _settle(tester);
    expect(find.text('Saved data changed after the move'), findsOneWidget);
    // Only the new record's amount, not the whole source total.
    expect(find.textContaining(r'To move: 1 ($3.00)'), findsOneWidget);
    await _confirmMove(tester, r'Add 1 new expense');

    expect(find.text('Expenses moved and verified'), findsOneWidget);
    expect(await _rows(env), 3);
    await tester.pageBack();
    await _settle(tester);
    // The list shows the added record without a restart.
    expect(find.text('Coffee'), findsOneWidget);
    expect(find.textContaining('changed after it was moved'), findsNothing);
    await _unmount(tester);
  });

  testWidgets('conflicting IDs block with an explanation and recovery export', (
    tester,
  ) async {
    final conflicting =
        '[${_rec('a', '"amountCents":1', 'One')},'
        '${_rec('a', '"amountCents":2', 'Two')}]';
    env = _Env(source: conflicting);
    await _start(tester, env);

    expect(find.text('Your expenses cannot be moved'), findsOneWidget);
    expect(
      find.textContaining('share an ID but have different content'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Continue'), findsNothing);

    await tester.tap(find.text('Export original data'));
    await _settle(tester);
    final saved = jsonDecode(env.files.saved.single.text) as Map;
    expect((saved['storage'] as Map)['expenses'], conflicting);
    expect(await _rows(env), 0);
    await _unmount(tester);
  });

  testWidgets('invalid source JSON blocks and is never guessed', (
    tester,
  ) async {
    env = _Env(source: '[${_rec('a', '"amount":12.345', 'Odd')}]');
    await _start(tester, env);

    expect(find.text('Your expenses cannot be moved'), findsOneWidget);
    expect(find.textContaining('cannot be read exactly'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(await _rows(env), 0);
    await _unmount(tester);
  });

  testWidgets('database initialization failure fails closed, then retries', (
    tester,
  ) async {
    env = _Env(source: _legacy)..failOpen = StateError('cannot open');
    await _start(tester, env);

    expect(find.text('Could not open the new storage'), findsOneWidget);
    expect(
      find.textContaining('did not open any other storage'),
      findsOneWidget,
    );
    expect(find.text('Lunch'), findsNothing);

    await tester.tap(find.text('Export original data'));
    await _settle(tester);
    expect(env.files.saved.single.text, contains('Lunch'));

    env.failOpen = null;
    await tester.tap(find.text('Try again'));
    await _settle(tester);
    expect(find.text('Ready to move your expenses'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('an interrupted migration rolls back and can be retried', (
    tester,
  ) async {
    env = _Env(source: _legacy)
      ..onStep = (s) {
        if (s == MigrationStep.rowsInserted) throw StateError('interrupted');
      };
    await _start(tester, env);
    await _confirmMove(tester, 'Move 2 expenses');

    expect(find.text('Moving failed'), findsOneWidget);
    expect(find.textContaining('was undone'), findsOneWidget);
    expect(await _rows(env), 0);
    await _unmount(tester);

    env.onStep = null;
    await _start(tester, env);
    await _confirmMove(tester, 'Move 2 expenses');
    expect(find.text('Expenses moved and verified'), findsOneWidget);
    expect(await _rows(env), 2);
    await _unmount(tester);
  });

  testWidgets('closing the app during a migration leaves all or nothing', (
    tester,
  ) async {
    env = _Env(source: _legacy);
    await _start(tester, env);
    await _backUp(tester);
    final gate = Completer<void>();
    env.storage.readGate = gate;

    await tester.tap(find.text('Move 2 expenses'));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await tester.pump();
    await tester.pump();

    // While running: progress shown, nothing else to press.
    expect(find.textContaining('Moving your expenses'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Check again'), findsNothing);

    // "Reload": the app goes away mid-migration.
    await _unmount(tester);
    gate.complete();
    env.storage.readGate = null;
    await _settle(tester);
    // The aborted attempt briefly polls for another tab's marker.
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);

    await _start(tester, env);
    final rows = await _rows(env);
    // ignore: avoid_print
    print('rows after interrupted migration: $rows');
    expect(rows == 0 || rows == 2, isTrue, reason: 'never partial: $rows');
    if (rows == 0) {
      expect(find.text('Ready to move your expenses'), findsOneWidget);
    } else {
      expect(find.text('Lunch'), findsOneWidget);
    }
    await _unmount(tester);
  });

  testWidgets('a second tab that migrated first: no double import', (
    tester,
  ) async {
    env = _Env(source: _legacy);
    await _start(tester, env);
    expect(find.text('Ready to move your expenses'), findsOneWidget);

    // The other tab migrates the same source.
    final other = env.otherTab();
    final result = await tester.runAsync(
      () => JsonToDriftMigration(source: env.storage, target: other).migrate(),
    );
    await tester.runAsync(other.close);
    expect(result!.status, MigrationStatus.completed);

    await _confirmMove(tester, 'Move 2 expenses');

    expect(find.text('Already moved'), findsOneWidget);
    expect(await _rows(env), 2);
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(find.text('Lunch'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('migration snapshots can be exported from the menu', (
    tester,
  ) async {
    env = _Env(source: _legacy);
    await _start(tester, env);
    await _confirmMove(tester, 'Move 2 expenses');
    await tester.tap(find.text('Continue'));
    await _settle(tester);

    await tester.tap(find.byTooltip('Data options'));
    await _settle(tester);
    await tester.tap(find.text('Storage migration'));
    await _settle(tester);
    await tester.tap(find.text('Export migration snapshots'));
    await _settle(tester);

    final saved = env.files.saved.last;
    expect(saved.name, startsWith('spendwise-migration-snapshots-'));
    final snapshots = (jsonDecode(saved.text) as Map)['snapshots'] as List;
    expect((snapshots.single as Map)['rawText'], _legacy);
    expect(
      (snapshots.single as Map)['fingerprint'],
      sourceFingerprint(_legacy),
    );
    await tester.pageBack();
    await _settle(tester);
    await _unmount(tester);
  });

  testWidgets('temporary browser storage disables migration with a warning', (
    tester,
  ) async {
    env = _Env(source: _legacy)
      ..report = (implementation: 'inMemory', missing: const ['indexedDb']);
    await _start(tester, env);

    expect(
      find.textContaining('only offers temporary storage'),
      findsOneWidget,
    );
    expect(find.text('Move 2 expenses'), findsNothing);
    expect(await _rows(env), 0);
    await _unmount(tester);
  });

  testWidgets('temporary storage is flagged inside the app', (tester) async {
    env = _Env()..report = (implementation: 'inMemory', missing: const []);
    await _start(tester, env);
    expect(
      find.textContaining('Everything here is lost when the tab closes'),
      findsOneWidget,
    );
    await _unmount(tester);
  });

  testWidgets('single-tab storage is flagged', (tester) async {
    env = _Env()
      ..report = (implementation: 'unsafeIndexedDb', missing: const []);
    await _start(tester, env);
    expect(
      find.textContaining('Keep SpendWise open in one tab only'),
      findsOneWidget,
    );
    await _unmount(tester);
  });

  testWidgets('storage information names the backend, mode and limits', (
    tester,
  ) async {
    env = _Env()..report = (implementation: 'opfsLocks', missing: const []);
    await _start(tester, env);

    await tester.tap(find.byTooltip('Data options'));
    await _settle(tester);
    await tester.tap(find.text('Storage information'));
    await _settle(tester);

    expect(
      find.textContaining('SQLite database (browser mode: opfsLocks)'),
      findsOneWidget,
    );
    expect(find.textContaining('older version of SpendWise'), findsOneWidget);
    expect(
      find.textContaining('would not remove expenses deleted here'),
      findsOneWidget,
    );
    expect(find.textContaining('Test data set: t1'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await _settle(tester);
    await _unmount(tester);
  });

  group('Stage 4B', () {
    testWidgets('a build without SQLite refuses the Drift configuration', (
      tester,
    ) async {
      env = _Env(source: _legacy);
      await tester.pumpWidget(
        SpendWiseApp(
          config: _testConfig,
          storage: env.storage,
          platform: fakePlatform(files: env.files),
          driftExecutor: env.executor,
        ),
      );
      await _settle(tester);

      expect(
        find.textContaining('does not include the SQLite backend'),
        findsOneWidget,
      );
      expect(env.openedNames, isEmpty);
    });

    testWidgets('the backup file is exact, importable and not proof of '
        'saving', (tester) async {
      env = _Env(source: _legacy);
      await _start(tester, env);

      final checkbox = find.byType(CheckboxListTile);
      // Confirming is impossible before a backup was offered.
      expect(tester.widget<CheckboxListTile>(checkbox).onChanged, isNull);

      await tester.tap(find.text('Download backup'));
      await _settle(tester);

      final file = env.files.saved.single;
      expect(file.name, 'spendwise-pre-migration-backup-2026-10-15.json');
      final parsed = parseBackup(Uint8List.fromList(utf8.encode(file.text)));
      expect(parsed.expenses.map((e) => e.amount.cents), [1250, 10]);
      expect(
        find.textContaining('cannot tell whether or where'),
        findsOneWidget,
      );
      expect(
        find.textContaining('personal financial information'),
        findsOneWidget,
      );

      // Offered, but not confirmed: still disabled.
      final move = find.widgetWithText(FilledButton, 'Move 2 expenses');
      expect(tester.widget<FilledButton>(move).onPressed, isNull);
      await tester.tap(checkbox);
      await _settle(tester);
      expect(tester.widget<FilledButton>(move).onPressed, isNotNull);

      // Unticking makes it unavailable again.
      await tester.tap(checkbox);
      await _settle(tester);
      expect(tester.widget<FilledButton>(move).onPressed, isNull);
      expect(await _rows(env), 0);
      expect(env.storage.data, _legacy);
      await _unmount(tester);
    });

    testWidgets('a source change after the backup requires a new one', (
      tester,
    ) async {
      env = _Env(source: _legacy);
      await _start(tester, env);
      await _backUp(tester);
      final move = find.widgetWithText(FilledButton, 'Move 2 expenses');
      expect(tester.widget<FilledButton>(move).onPressed, isNotNull);

      // Another tab (any version) writes the JSON data.
      env.storage.data = '[${_rec('a', '"amount":12.5', 'Lunch')}]';
      env.tabs.storageEvent('flutter.expenses');
      await _settle(tester);

      expect(find.text('Move 1 expense'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Move 1 expense'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Download backup'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('changing data between review and backup offers no file', (
      tester,
    ) async {
      env = _Env(source: _legacy);
      await _start(tester, env);
      env.storage.data = '[${_rec('a', '"amount":12.5', 'Lunch')}]';

      await tester.tap(find.text('Download backup'));
      await _settle(tester);

      expect(env.files.saved, isEmpty);
      expect(find.textContaining('Your saved data changed'), findsOneWidget);
      expect(find.text('Move 1 expense'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('other open tabs of this version are shown before moving', (
      tester,
    ) async {
      env = _Env(source: _legacy);
      await _start(tester, env);
      expect(
        find.textContaining(
          'Tabs running an older version cannot be '
          'detected',
        ),
        findsOneWidget,
      );

      env.tabs.receive({
        'protocol': 1,
        'type': 'hello',
        'tabId': 'other-1',
        'version': 'x',
        'backend': 'json',
        'namespace': 't1',
      });
      await _settle(tester);

      expect(
        find.textContaining('open in 1 other tab (previous storage)'),
        findsOneWidget,
      );
      // It answered the other tab.
      expect(env.tabs.postedTypes, contains('here'));
      await _unmount(tester);
    });

    testWidgets('a completed migration is announced to other tabs', (
      tester,
    ) async {
      env = _Env(source: _legacy);
      await _start(tester, env);
      await _confirmMove(tester, 'Move 2 expenses');
      expect(env.tabs.postedTypes, contains('migrated'));
      await _unmount(tester);
    });

    testWidgets('a migration in another tab refreshes the gate', (
      tester,
    ) async {
      env = _Env(source: _legacy);
      await _start(tester, env);

      final other = env.otherTab();
      await tester.runAsync(
        () =>
            JsonToDriftMigration(source: env.storage, target: other).migrate(),
      );
      await tester.runAsync(other.close);
      env.tabs.receive({
        'protocol': 1,
        'type': 'migrated',
        'tabId': 'other-1',
        'version': 'x',
        'backend': 'drift',
        'namespace': 't1',
      });
      await _settle(tester);

      expect(find.text('Already moved'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('a source change while the app is open shows the notice '
        'without reloading', (tester) async {
      env = _Env(source: _legacy);
      await _start(tester, env);
      await _confirmMove(tester, 'Move 2 expenses');
      await tester.tap(find.text('Continue'));
      await _settle(tester);
      expect(find.textContaining('changed after it was moved'), findsNothing);

      env.storage.data = '[${_rec('z', '"amountCents":1', 'Late')}]';
      env.tabs.storageEvent('flutter.expenses');
      await _settle(tester);

      expect(find.textContaining('changed after it was moved'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('unsafe IndexedDB disables moving', (tester) async {
      env = _Env(source: _legacy)
        ..report = (implementation: 'unsafeIndexedDb', missing: const []);
      await _start(tester, env);

      expect(find.textContaining('so moving is disabled'), findsOneWidget);
      expect(find.text('Move 2 expenses'), findsNothing);
      expect(find.text('Download backup'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('an unrecognised browser mode disables moving', (tester) async {
      env = _Env(source: _legacy)
        ..report = (implementation: 'futureMode', missing: const []);
      await _start(tester, env);

      expect(find.textContaining('not recognised'), findsWidgets);
      expect(find.text('Move 2 expenses'), findsNothing);
      await _unmount(tester);
    });

    for (final mode in ['opfsShared', 'opfsLocks', 'sharedIndexedDb']) {
      testWidgets('$mode allows moving and is described', (tester) async {
        env = _Env(source: _legacy)
          ..report = (implementation: mode, missing: const []);
        await _start(tester, env);

        expect(
          find.textContaining('Persistent and coordinated'),
          findsOneWidget,
        );
        expect(find.text('Move 2 expenses'), findsOneWidget);
        await _unmount(tester);
      });
    }
  });

  group('M3.3 theme', () {
    void dark(WidgetTester tester) {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    }

    ColorScheme schemeAt(WidgetTester tester, Finder finder) =>
        Theme.of(tester.element(finder)).colorScheme;

    testWidgets('migration screen, dialog and app share the dark theme', (
      tester,
    ) async {
      dark(tester);
      env = _Env(source: _legacy)
        ..report = (implementation: 'opfsLocks', missing: const []);
      await _start(tester, env);

      expect(find.byType(MaterialApp), findsOneWidget);
      final scheme = schemeAt(tester, find.text('Move 2 expenses'));
      expect(scheme.brightness, Brightness.dark);
      expect(scheme.primary, AppTheme.dark().colorScheme.primary);
      // Totals use the shared money format.
      expect(find.textContaining(r'To move: 2 ($12.60)'), findsOneWidget);
      // The other-tabs advice is a notice with a spoken level.
      expect(
        find.bySemanticsLabel(RegExp(r'^Information: Close any other')),
        findsOneWidget,
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));

      await _backUp(tester);
      await tester.ensureVisible(find.text('Move 2 expenses'));
      await tester.tap(find.text('Move 2 expenses'));
      await _settle(tester);
      expect(schemeAt(tester, find.byType(AlertDialog)), scheme);
      expect(find.textContaining(r'Move 2 expenses ($12.60)'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Move'));
      await _settle(tester);

      await tester.tap(find.text('Continue'));
      await _settle(tester);
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(schemeAt(tester, find.text('Lunch')), scheme);
      await _unmount(tester);
    });

    testWidgets('open failure screen is themed and keeps its recovery '
        'actions', (tester) async {
      dark(tester);
      env = _Env(source: _legacy)..failOpen = StateError('cannot open');
      await _start(tester, env);

      expect(find.text('Could not open the new storage'), findsOneWidget);
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(
        schemeAt(
          tester,
          find.text('Could not open the new storage'),
        ).brightness,
        Brightness.dark,
      );
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Export original data'),
        findsOneWidget,
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await _unmount(tester);
    });

    testWidgets('unsafe storage warning is an error notice', (tester) async {
      env = _Env(source: _legacy)
        ..report = (implementation: 'unsafeIndexedDb', missing: const []);
      await _start(tester, env);

      expect(
        find.bySemanticsLabel(RegExp(r'^Problem: In this browser the new')),
        findsOneWidget,
      );
      await _unmount(tester);
    });
  });

  group('M3.4 editing on SQLite', () {
    final lunch = Expense(
      id: 'a',
      amount: Money.fromCents(1250),
      description: 'Lunch',
      category: 'Food',
      date: DateTime.parse('2026-10-03T12:00:00.000+02:00'),
      dateText: '2026-10-03T12:00:00.000+02:00',
    );

    /// Fresh installation (no JSON source) whose database already holds
    /// [lunch]; returns the other tab's repository.
    Future<(SpendWiseDatabase, DriftExpenseRepository)> startWithLunch(
      WidgetTester tester,
    ) async {
      env = _Env();
      final db = env.otherTab();
      final other = DriftExpenseRepository(db);
      await tester.runAsync(() async {
        await other.load();
        await other.add(lunch);
      });
      await _start(tester, env);
      expect(inRow(find.text('Lunch')), findsOneWidget);
      return (db, other);
    }

    Future<List<Expense>> rowsIn(
      WidgetTester tester,
      DriftExpenseRepository repo,
    ) async => (await tester.runAsync(() => repo.load()))!.expenses;

    testWidgets('an edit saves through the guarded update and keeps the '
        'offset date text', (tester) async {
      final (db, other) = await startWithLunch(tester);

      await _openForEdit(tester, 'Lunch');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lunch'),
        'Team lunch',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await _settle(tester);

      expect(inRow(find.text('Team lunch')), findsOneWidget);
      final rows = await rowsIn(tester, other);
      expect(rows.single.description, 'Team lunch');
      expect(rows.single.dateText, '2026-10-03T12:00:00.000+02:00');
      await _unmount(tester);
      await tester.runAsync(db.close);
    });

    testWidgets('a record edited in another tab is not overwritten', (
      tester,
    ) async {
      final (db, other) = await startWithLunch(tester);
      await _openForEdit(tester, 'Lunch');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '99',
      );

      await tester.runAsync(
        () => other.update(lunch, lunch.edited(description: 'Other tab')),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await _settle(tester);

      expect(
        find.textContaining('may have been changed or deleted in another tab'),
        findsOneWidget,
      );
      final rows = await rowsIn(tester, other);
      expect(rows.single.description, 'Other tab');
      expect(rows.single.amount.cents, 1250);

      // The form has unsaved input: reloading asks first.
      await tester.tap(find.widgetWithText(TextButton, 'Reload'));
      await _settle(tester);
      expect(find.text('Discard changes and reload?'), findsOneWidget);
      await tester.tap(find.text('Discard and reload'));
      await _settle(tester);
      expect(inRow(find.text('Other tab')), findsOneWidget);
      await _unmount(tester);
      await tester.runAsync(db.close);
    });

    testWidgets('a record deleted in another tab is reported, not re-added', (
      tester,
    ) async {
      final (db, other) = await startWithLunch(tester);
      await _openForEdit(tester, 'Lunch');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '99',
      );

      await tester.runAsync(() => other.deleteExpected(lunch));
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await _settle(tester);

      expect(
        find.textContaining('may have been changed or deleted in another tab'),
        findsOneWidget,
      );
      expect(await rowsIn(tester, other), isEmpty);
      await _unmount(tester);
      await tester.runAsync(db.close);
    });

    testWidgets('the delete button never removes a row changed in another '
        'tab', (tester) async {
      final (db, other) = await startWithLunch(tester);

      final changed = lunch.edited(amount: Money.fromCents(5000));
      await tester.runAsync(() => other.update(lunch, changed));
      await _deleteViaPanel(tester, 'Lunch');

      expect(
        find.text('Expenses were changed in another tab. Reload to continue.'),
        findsOneWidget,
      );
      final rows = await rowsIn(tester, other);
      expect(rows.single.toJson(), changed.toJson());
      await _unmount(tester);
      await tester.runAsync(db.close);
    });

    testWidgets('a row already deleted elsewhere is reported', (tester) async {
      final (db, other) = await startWithLunch(tester);
      await tester.runAsync(() => other.deleteExpected(lunch));

      await _deleteViaPanel(tester, 'Lunch');

      expect(
        find.textContaining('This expense was already deleted'),
        findsOneWidget,
      );
      expect(find.text('Reload'), findsOneWidget);
      await _unmount(tester);
      await tester.runAsync(db.close);
    });
  });
}
