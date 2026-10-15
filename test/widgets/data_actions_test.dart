import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/backup/expense_backup.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/platform/platform_services.dart';
import 'package:spendwise/services/expense_storage.dart';
import 'package:spendwise/widgets/expense_list.dart';

import '../support/fake_expense_storage.dart';
import '../support/fake_platform_services.dart';
import '../support/ui_actions.dart';

Expense _e(String id, int cents, String description) => Expense(
  id: id,
  amount: Money.fromCents(cents),
  description: description,
  category: 'Food',
  date: DateTime(2024, 3, 1),
);

String _backup(List<Expense> es) =>
    encodeBackup(es, exportedAt: DateTime.utc(2026, 10, 1));

class _Harness {
  _Harness({String? data}) : storage = FakeExpenseStorage(data: data);

  final FakeExpenseStorage storage;
  final files = FakeFileTransfer();
  final persistence = FakePersistentStorage();

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      SpendWiseApp(
        storage: storage,
        clock: () => DateTime(2024, 3, 15),
        platform: fakePlatform(files: files, persistence: persistence),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _openMenu(WidgetTester tester, String item) async {
  await tester.tap(find.byTooltip('Data options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('exports a valid backup of all expenses', (tester) async {
    final h = _Harness(
      data: encodeExpenses([_e('a', 1250, 'Lunch'), _e('b', 300, 'Bus')]),
    );
    await h.pump(tester);

    await _openMenu(tester, 'Export backup');

    final saved = h.files.saved.single;
    expect(saved.name, startsWith('spendwise-backup-'));
    expect(saved.name, endsWith('.json'));
    final parsed = parseBackup(Uint8List.fromList(utf8.encode(saved.text)));
    expect(parsed.expenses.map((e) => e.id), ['a', 'b']);
    expect(find.textContaining('keep it somewhere private'), findsOneWidget);
  });

  testWidgets('imports new expenses after confirming the preview', (
    tester,
  ) async {
    final h = _Harness(data: encodeExpenses([_e('a', 1250, 'Lunch')]));
    await h.pump(tester);
    h.files.pickText(
      _backup([_e('a', 1250, 'Lunch'), _e('b', 300, 'Bus'), _e('c', 5, 'Gum')]),
    );

    await _openMenu(tester, 'Import backup');

    expect(find.text('New expenses: 2 (\$3.05)'), findsOneWidget);
    expect(find.text('Already present (skipped): 1'), findsOneWidget);
    expect(h.storage.writeCount, 0);

    await tester.tap(find.text('Import 2 expenses'));
    await tester.pumpAndSettle();

    expect(find.text('Bus'), findsOneWidget);
    expect(find.text('Gum'), findsOneWidget);
    expect(find.textContaining('Imported 2 expenses'), findsOneWidget);
    expect(decodeExpenses(h.storage.data!).expenses, hasLength(3));
    expect(h.persistence.requestCount, 1);
  });

  testWidgets('the import preview total uses the shared money format', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);
    h.files.pickText(
      _backup([_e('b', 123456, 'Laptop'), _e('c', -6, 'Refund')]),
    );

    await _openMenu(tester, 'Import backup');

    expect(find.text('New expenses: 2 (\$1,234.50)'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.storage.writeCount, 0);
  });

  testWidgets('cancelling the preview changes nothing', (tester) async {
    final h = _Harness(data: encodeExpenses([_e('a', 1250, 'Lunch')]));
    await h.pump(tester);
    final before = h.storage.data;
    h.files.pickText(_backup([_e('b', 300, 'Bus')]));

    await _openMenu(tester, 'Import backup');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Bus'), findsNothing);
    expect(h.storage.data, before);
    expect(h.storage.writeCount, 0);
  });

  testWidgets('conflicting records block the import', (tester) async {
    final h = _Harness(data: encodeExpenses([_e('a', 1250, 'Lunch')]));
    await h.pump(tester);
    final before = h.storage.data;
    h.files.pickText(
      _backup([_e('a', 9999, 'Changed lunch'), _e('b', 300, 'Bus')]),
    );

    await _openMenu(tester, 'Import backup');

    expect(find.textContaining('Import blocked'), findsOneWidget);
    expect(find.textContaining('Import 1 expense'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(h.storage.data, before);
    expect(find.text('Bus'), findsNothing);
  });

  testWidgets('an invalid file is rejected with a reason', (tester) async {
    final h = _Harness(data: encodeExpenses([_e('a', 1250, 'Lunch')]));
    await h.pump(tester);
    h.files.pickText('{"format":"something-else"}');

    await _openMenu(tester, 'Import backup');

    expect(find.textContaining('not a SpendWise backup'), findsOneWidget);
    expect(find.textContaining('Nothing was changed'), findsOneWidget);
    expect(h.storage.writeCount, 0);
  });

  testWidgets('an oversized file is refused before reading', (tester) async {
    final h = _Harness();
    await h.pump(tester);
    h.files
      ..pickText('{}')
      ..nextPickSize = maxBackupFileBytes + 1;

    await _openMenu(tester, 'Import backup');

    expect(find.textContaining('too large'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('cancelling the file picker does nothing', (tester) async {
    final h = _Harness();
    await h.pump(tester);

    await _openMenu(tester, 'Import backup');

    expect(h.files.pickCount, 1);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('load-error screen exports raw data unchanged', (tester) async {
    const corrupt = '[{"id":"a","amount":1.005,"description":"Gum"}]';
    final h = _Harness(data: corrupt)..storage.legacyBackup = '[old]';
    await h.pump(tester);

    expect(find.text('Could not load your saved expenses.'), findsOneWidget);
    await tester.tap(find.text('Export raw data'));
    await tester.pumpAndSettle();

    final saved = h.files.saved.single;
    expect(saved.name, startsWith('spendwise-raw-data-'));
    final storage = (json.decode(saved.text) as Map)['storage'] as Map;
    expect(storage['expenses'], corrupt);
    expect(storage['expenses_legacy_backup'], '[old]');
    expect(h.storage.data, corrupt);
    expect(h.storage.writeCount, 0);
  });

  testWidgets('a change from another tab pauses edits until reload', (
    tester,
  ) async {
    final h = _Harness(data: encodeExpenses([_e('a', 300, 'Gum')]));
    await h.pump(tester);
    final external = encodeExpenses([
      _e('a', 300, 'Gum'),
      _e('t', 700, 'Taxi'),
    ]);
    h.storage.data = external;

    // The confirmed delete is refused (stale data); back to the list.
    await deleteExpenseViaUi(tester, 'Gum');
    expect(find.textContaining('changed in another tab'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.textContaining('changed in another tab'), findsWidgets);
    expect(
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNull,
    );
    expect(h.storage.data, external);

    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();

    expect(find.text('Taxi'), findsOneWidget);
    expect(find.text('Gum'), findsOneWidget);
    expect(find.textContaining('Changes here are paused'), findsNothing);
  });

  testWidgets('expenses sharing an ID are shown but cannot be deleted', (
    tester,
  ) async {
    final h = _Harness(
      data: encodeExpenses([
        _e('dup', 100, 'First'),
        _e('dup', 200, 'Second'),
        _e('ok', 300, 'Single'),
      ]),
    );
    await h.pump(tester);

    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.textContaining('share the same ID'), findsOneWidget);
    ExpenseTile row(String description) => tester.widget<ExpenseTile>(
      find.ancestor(
        of: find.text(description),
        matching: find.byType(ExpenseTile),
      ),
    );
    // Rows sharing an ID cannot be opened, so neither edited nor deleted.
    expect(row('First').onSelect, isNull);
    expect(row('Second').onSelect, isNull);
    expect(row('First').isDuplicate, isTrue);
    expect(row('Single').onSelect, isNotNull);
  });

  testWidgets('persistence is requested after adding, not on load', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);
    expect(h.persistence.requestCount, 0);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '4');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'Tea',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add Expense'));
    await tester.pumpAndSettle();

    expect(find.text('Tea'), findsOneWidget);
    expect(h.persistence.requestCount, 1);
  });

  testWidgets('storage information never promises permanence', (tester) async {
    final h = _Harness();
    h.persistence.current = PersistenceStatus.notPersisted;
    await h.pump(tester);

    await _openMenu(tester, 'Storage information');

    expect(find.textContaining('may clear it'), findsOneWidget);
    expect(find.textContaining('Export a backup regularly'), findsOneWidget);
    expect(find.textContaining('guarantee'), findsNothing);
  });

  testWidgets('persistent storage is described with its limits', (
    tester,
  ) async {
    final h = _Harness();
    h.persistence.current = PersistenceStatus.persisted;
    await h.pump(tester);

    await _openMenu(tester, 'Storage information');

    expect(find.textContaining('can still be removed'), findsOneWidget);
  });
}
