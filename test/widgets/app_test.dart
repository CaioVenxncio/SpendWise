import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/services/expense_storage.dart';
import 'package:spendwise/widgets/expense_list.dart';

import '../support/fake_expense_storage.dart';
import '../support/ui_actions.dart';

final _now = DateTime(2024, 3, 15, 10);

Future<void> _pumpApp(WidgetTester tester, FakeExpenseStorage storage) async {
  await tester.pumpWidget(SpendWiseApp(storage: storage, clock: () => _now));
  await tester.pumpAndSettle();
}

Future<void> _fillForm(
  WidgetTester tester, {
  required String amount,
  required String description,
}) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), amount);
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Description'),
    description,
  );
}

/// [finder] inside an expense row (not the monthly total card).
Finder _inRow(Finder finder) =>
    find.descendant(of: find.byType(ExpenseTile), matching: finder);

void main() {
  testWidgets('shows empty state and zero total', (tester) async {
    await _pumpApp(tester, FakeExpenseStorage());

    expect(find.text('No expenses'), findsOneWidget);
    expect(find.bySemanticsLabel('Total this month: \$0.00'), findsOneWidget);
  });

  testWidgets('lists stored expenses with amounts and monthly total', (
    tester,
  ) async {
    final storage = FakeExpenseStorage(
      data: encodeExpenses([
        Expense(
          id: '1',
          amount: Money.fromCents(1250),
          description: 'Lunch',
          category: 'Food',
          date: DateTime(2024, 3, 10),
        ),
        Expense(
          id: '2',
          amount: Money.fromCents(3000),
          description: 'Old trip',
          category: 'Transport',
          date: DateTime(2024, 1, 2),
        ),
      ]),
    );

    await _pumpApp(tester, storage);

    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Food - Mar 10, 2024'), findsOneWidget);
    expect(_inRow(find.text('\$12.50')), findsOneWidget);
    expect(_inRow(find.text('\$30.00')), findsOneWidget);
    expect(find.bySemanticsLabel('Total this month: \$12.50'), findsOneWidget);
  });

  testWidgets('shows grouped amounts and the local day of offset dates', (
    tester,
  ) async {
    // 23:30 local on 10 March, stored as UTC text: shown and counted on the
    // 10th in March whatever the machine's zone.
    final zText = DateTime(2024, 3, 10, 23, 30).toUtc().toIso8601String();
    final storage = FakeExpenseStorage(
      data: encodeExpenses([
        Expense(
          id: '1',
          amount: Money.fromCents(123456789),
          description: 'Big',
          category: 'Food',
          date: DateTime.parse(zText),
          dateText: zText,
        ),
      ]),
    );

    await _pumpApp(tester, storage);

    expect(find.text('Food - Mar 10, 2024'), findsOneWidget);
    expect(_inRow(find.text('\$1,234,567.89')), findsOneWidget);
    expect(
      find.bySemanticsLabel('Total this month: \$1,234,567.89'),
      findsOneWidget,
    );
    expect(storage.writeCount, 0);
  });

  testWidgets('adds an expense through the form', (tester) async {
    final storage = FakeExpenseStorage();
    await _pumpApp(tester, storage);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await _fillForm(tester, amount: '7,25', description: '  Coffee  ');
    await tester.tap(find.widgetWithText(FilledButton, 'Add Expense'));
    await tester.pumpAndSettle();

    expect(find.text('Coffee'), findsOneWidget);
    expect(find.text('\$7.25'), findsOneWidget);
    final stored = decodeExpenses(storage.data!).expenses.single;
    expect(stored.amount, Money.fromCents(725));
    expect(stored.description, 'Coffee');
    expect(stored.category, 'General');
  });

  testWidgets('form rejects invalid input and does not save', (tester) async {
    final storage = FakeExpenseStorage();
    await _pumpApp(tester, storage);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add Expense'));
    await tester.pump();

    expect(find.text('Enter amount'), findsOneWidget);
    expect(find.text('Enter description'), findsOneWidget);

    await _fillForm(tester, amount: '-3', description: 'Refund');
    await tester.tap(find.widgetWithText(FilledButton, 'Add Expense'));
    await tester.pump();

    expect(find.textContaining('up to 2 decimals'), findsOneWidget);
    expect(storage.writeCount, 0);
    expect(find.text('Add Expense'), findsWidgets);
  });

  testWidgets('shows an error and stays on the form when saving fails', (
    tester,
  ) async {
    final storage = FakeExpenseStorage()..failWrites = true;
    await _pumpApp(tester, storage);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await _fillForm(tester, amount: '5', description: 'Snack');
    await tester.tap(find.widgetWithText(FilledButton, 'Add Expense'));
    await tester.pumpAndSettle();

    expect(find.text('Could not save expense. Try again.'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Amount'), findsOneWidget);
    expect(storage.data, isNull);
  });

  testWidgets('deletes an expense', (tester) async {
    final storage = FakeExpenseStorage(
      data: encodeExpenses([
        Expense(
          id: '1',
          amount: Money.fromCents(300),
          description: 'Gum',
          category: 'Food',
          date: DateTime(2024, 3, 1),
        ),
      ]),
    );
    await _pumpApp(tester, storage);

    await deleteExpenseViaUi(tester, 'Gum');

    expect(find.text('Gum'), findsNothing);
    expect(find.text('No expenses'), findsOneWidget);
    expect(decodeExpenses(storage.data!).expenses, isEmpty);
  });

  testWidgets('corrupted data shows an error and disables adding', (
    tester,
  ) async {
    final storage = FakeExpenseStorage(data: '{corrupt');
    await _pumpApp(tester, storage);

    expect(find.text('Could not load your saved expenses.'), findsOneWidget);
    // No way to add while the data cannot be loaded.
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text('Add Expense'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Could not load your saved expenses.'), findsOneWidget);
    expect(storage.data, '{corrupt');
    expect(storage.writeCount, 0);
  });

  testWidgets('shows legacy data exactly and migrates it on first change', (
    tester,
  ) async {
    const legacy =
        '[{"id":"a","amount":0.1,"description":"Gum","category":"Food",'
        '"date":"2024-03-01T00:00:00.000"},'
        '{"id":"b","amount":0.2,"description":"Mint","category":"Food",'
        '"date":"2024-03-02T00:00:00.000"}]';
    final storage = FakeExpenseStorage(data: legacy);
    await _pumpApp(tester, storage);

    expect(find.text('\$0.10'), findsOneWidget);
    expect(find.text('\$0.20'), findsOneWidget);
    expect(find.bySemanticsLabel('Total this month: \$0.30'), findsOneWidget);
    expect(storage.data, legacy);

    await deleteExpenseViaUi(tester, 'Gum');

    expect(storage.legacyBackup, legacy);
    final stored = decodeExpenses(storage.data!);
    expect(stored.hasLegacyRecords, isFalse);
    expect(stored.expenses.single.amount, Money.fromCents(20));
    expect(find.bySemanticsLabel('Total this month: \$0.20'), findsOneWidget);
  });

  testWidgets('legacy amount with too many decimals blocks loading', (
    tester,
  ) async {
    const legacy =
        '[{"id":"a","amount":1.005,"description":"Gum","category":"Food",'
        '"date":"2024-03-01T00:00:00.000"}]';
    final storage = FakeExpenseStorage(data: legacy);
    await _pumpApp(tester, storage);

    expect(find.text('Could not load your saved expenses.'), findsOneWidget);
    expect(storage.data, legacy);
    expect(storage.writeCount, 0);
  });
}
