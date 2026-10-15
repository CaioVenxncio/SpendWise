import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/pages/expense_form_page.dart';
import 'package:spendwise/providers/expense_provider.dart';
import 'package:spendwise/services/expense_storage.dart';
import 'package:spendwise/widgets/expense_list.dart';

import '../support/fake_expense_storage.dart';
import '../support/ui_actions.dart';

final _now = DateTime(2026, 10, 15, 10);

Expense _e(
  String id,
  int cents,
  String description, {
  String category = 'Food',
  String dateText = '2026-10-03T12:30:00.000',
}) => Expense(
  id: id,
  amount: Money.fromCents(cents),
  description: description,
  category: category,
  date: DateTime.parse(dateText),
  dateText: dateText,
);

Future<void> _pump(WidgetTester tester, FakeExpenseStorage storage) async {
  await tester.pumpWidget(SpendWiseApp(storage: storage, clock: () => _now));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Finder _inRow(Finder finder) =>
    find.descendant(of: find.byType(ExpenseTile), matching: finder);

/// Row → detail page → Edit (the default 800×600 test window is the
/// single-column layout).
Future<void> _openEdit(WidgetTester tester, String description) async {
  await openEditForm(tester, description);
  expect(find.text('Edit Expense'), findsOneWidget);
}

/// From the detail page back to the list.
Future<void> _backToList(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
  await tester.pumpAndSettle();
}

/// Scrolls the form until [finder] is built and visible, then returns it.
Future<FilledButton> _visible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    100,
    // The form's vertical list (text fields scroll horizontally).
    scrollable: find
        .descendant(
          of: find.byType(ExpenseFormPage),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first,
  );
  return tester.widget<FilledButton>(finder);
}

String _amountText(WidgetTester tester) =>
    tester.widget<TextFormField>(_field('Amount')).controller!.text;

List<Expense> _stored(FakeExpenseStorage storage) =>
    decodeExpenses(storage.data!).expenses;

void main() {
  group('opening an expense', () {
    testWidgets('selecting a row opens it with its stored values', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeExpenseStorage(data: encodeExpenses([_e('a', 1250, 'Lunch')])),
      );

      await _openEdit(tester, 'Lunch');

      expect(_amountText(tester), '12.50');
      expect(find.widgetWithText(TextFormField, 'Lunch'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Date: October 3, 2026'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save changes'), findsOneWidget);
    });

    testWidgets('rows can be opened with the keyboard', (tester) async {
      await _pump(
        tester,
        FakeExpenseStorage(data: encodeExpenses([_e('a', 1250, 'Lunch')])),
      );
      Focus.of(tester.element(_inRow(find.text('Lunch')))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Expense'), findsOneWidget);
      Focus.of(tester.element(find.text('Edit'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Edit Expense'), findsOneWidget);
    });

    testWidgets('an unknown imported category is shown and kept', (
      tester,
    ) async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([_e('a', 999, 'Shop', category: 'Groceries')]),
      );
      await _pump(tester, storage);

      await _openEdit(tester, 'Shop');
      expect(tester.takeException(), isNull);
      expect(find.text('Groceries'), findsOneWidget);

      await tester.enterText(_field('Description'), 'Weekly shop');
      await _save(tester);

      final saved = _stored(storage).single;
      expect(saved.category, 'Groceries');
      expect(saved.description, 'Weekly shop');
    });

    testWidgets('a date before 2000 opens and the picker accepts it', (
      tester,
    ) async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([
          _e('a', 100, 'Old', dateText: '1995-06-01T09:00:00.000'),
        ]),
      );
      await _pump(tester, storage);
      await _openEdit(tester, 'Old');

      expect(find.text('Date: June 1, 1995'), findsOneWidget);
      await tester.tap(find.byTooltip('Pick date'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(DatePickerDialog),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Date: June 1, 1995'), findsOneWidget);
    });

    testWidgets('a future-dated import opens without a picker error', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeExpenseStorage(
          data: encodeExpenses([
            _e('a', 100, 'Later', dateText: '2030-01-01T09:00:00.000'),
          ]),
        ),
      );
      await _openEdit(tester, 'Later');
      await tester.tap(find.byTooltip('Pick date'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });
  });

  group('saving an edit', () {
    testWidgets('a new amount updates the list and the monthly total', (
      tester,
    ) async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([_e('a', 1250, 'Lunch'), _e('b', 300, 'Bus')]),
      );
      await _pump(tester, storage);
      expect(
        find.bySemanticsLabel(r'Total this month: $15.50'),
        findsOneWidget,
      );

      await _openEdit(tester, 'Lunch');
      await tester.enterText(_field('Amount'), '1234.56');
      await _save(tester);

      expect(find.text('Edit Expense'), findsNothing);
      // The detail page shows the saved record, then the list does.
      expect(find.text(r'$1,234.56'), findsOneWidget);
      await _backToList(tester);
      expect(_inRow(find.text(r'$1,234.56')), findsOneWidget);
      expect(
        find.bySemanticsLabel(r'Total this month: $1,237.56'),
        findsOneWidget,
      );
      final saved = _stored(storage);
      expect(saved.map((e) => e.id), ['a', 'b']);
      expect(saved.first.amount.cents, 123456);
      expect(saved.first.dateText, '2026-10-03T12:30:00.000');
      expect(saved.last.toJson(), _e('b', 300, 'Bus').toJson());
    });

    testWidgets('description, category and date can all be changed', (
      tester,
    ) async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([_e('a', 1250, 'Lunch')]),
      );
      await _pump(tester, storage);
      await _openEdit(tester, 'Lunch');

      await tester.enterText(_field('Description'), 'Dinner');
      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entertainment').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Pick date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('7'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Date: October 7, 2026'), findsOneWidget);
      await _save(tester);

      final saved = _stored(storage).single;
      expect(saved.id, 'a');
      expect(saved.description, 'Dinner');
      expect(saved.category, 'Entertainment');
      expect(saved.amount.cents, 1250);
      // New day, original local time of day, local convention.
      expect(saved.dateText, '2026-10-07T12:30:00.000');
      await _backToList(tester);
      expect(find.text('Entertainment - Oct 7, 2026'), findsOneWidget);
    });

    testWidgets('saving without changes writes nothing and closes', (
      tester,
    ) async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([_e('a', 1250, 'Lunch')]),
      );
      await _pump(tester, storage);
      await _openEdit(tester, 'Lunch');

      await tester.enterText(_field('Amount'), '12.5');
      await _save(tester);

      expect(find.text('Edit Expense'), findsNothing);
      expect(storage.writeCount, 0);
      expect(storage.backupCount, 0);
    });

    for (final text in [
      '2023-12-31T23:59:59.000Z',
      '2026-10-14T00:00:00.000+02:00',
      '2026-10-02T18:00:00.000-11:00',
    ]) {
      testWidgets('date text "$text" is kept byte-for-byte', (tester) async {
        final storage = FakeExpenseStorage(
          data: encodeExpenses([_e('a', 1250, 'Lunch', dateText: text)]),
        );
        await _pump(tester, storage);
        await _openEdit(tester, 'Lunch');

        await tester.enterText(_field('Description'), 'Changed');
        await _save(tester);

        expect(_stored(storage).single.dateText, text);
        expect(storage.data, contains('"date":"$text"'));
      });
    }

    for (final cents in [0, -500, Money.maxCents]) {
      testWidgets('an unchanged amount of $cents cents is kept exactly', (
        tester,
      ) async {
        final storage = FakeExpenseStorage(
          data: encodeExpenses([_e('a', cents, 'Imported')]),
        );
        await _pump(tester, storage);
        await _openEdit(tester, 'Imported');

        await tester.enterText(_field('Description'), 'Renamed');
        await _save(tester);

        final saved = _stored(storage).single;
        expect(saved.amount.cents, cents);
        expect(saved.description, 'Renamed');
      });
    }

    testWidgets('a changed amount must be valid; nothing is saved', (
      tester,
    ) async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([_e('a', 1250, 'Lunch')]),
      );
      await _pump(tester, storage);
      await _openEdit(tester, 'Lunch');

      for (final (text, message) in [
        ('', 'Enter amount'),
        ('1.234', 'Enter a number with up to 2 decimals, e.g. 12.50'),
        ('0', 'Amount must be greater than 0 and at most 1,000,000,000'),
        (
          '1000000000.01',
          'Amount must be greater than 0 and at most 1,000,000,000',
        ),
      ]) {
        await tester.enterText(_field('Amount'), text);
        await _save(tester);
        expect(find.text(message), findsOneWidget, reason: text);
        expect(find.text('Edit Expense'), findsOneWidget);
      }
      expect(storage.writeCount, 0);
    });

    testWidgets('repeated save clicks write once', (tester) async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([_e('a', 1250, 'Lunch')]),
      );
      await _pump(tester, storage);
      await _openEdit(tester, 'Lunch');
      await tester.enterText(_field('Amount'), '20');

      storage.readGate = Completer<void>();
      final save = find.widgetWithText(FilledButton, 'Save changes');
      await tester.tap(save);
      await tester.pump();
      await tester.tap(save, warnIfMissed: false);
      await tester.pump();
      storage.readGate!.complete();
      storage.readGate = null;
      await tester.pumpAndSettle();

      expect(storage.writeCount, 1);
      expect(_stored(storage).single.amount.cents, 2000);
    });

    testWidgets('a storage failure keeps the input and allows a retry', (
      tester,
    ) async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([_e('a', 1250, 'Lunch')]),
      );
      await _pump(tester, storage);
      await _openEdit(tester, 'Lunch');
      await tester.enterText(_field('Amount'), '20');
      await tester.enterText(_field('Description'), 'Typed');

      storage.failWrites = true;
      await _save(tester);

      expect(find.text('Could not save expense. Try again.'), findsOneWidget);
      expect(find.text('Edit Expense'), findsOneWidget);
      expect(_amountText(tester), '20');
      expect(find.widgetWithText(TextFormField, 'Typed'), findsOneWidget);
      expect(_stored(storage).single.amount.cents, 1250);

      storage.failWrites = false;
      await _save(tester);
      expect(_stored(storage).single.amount.cents, 2000);
      expect(_stored(storage).single.description, 'Typed');
    });
  });

  group('another tab', () {
    testWidgets('a stale edit is refused; input kept; reload shows the newer '
        'data', (tester) async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([_e('a', 1250, 'Lunch')]),
      );
      await _pump(tester, storage);
      await _openEdit(tester, 'Lunch');
      await tester.enterText(_field('Amount'), '99');

      final newer = encodeExpenses([_e('a', 777, 'Lunch from other tab')]);
      storage.data = newer;
      await _save(tester);

      expect(
        find.textContaining('may have been changed or deleted in another tab'),
        findsOneWidget,
      );
      expect(_amountText(tester), '99');
      expect(storage.data, newer);
      expect(
        (await _visible(
          tester,
          find.widgetWithText(FilledButton, 'Save changes'),
        )).onPressed,
        isNull,
      );

      // Reloading would lose the typed input: asked first.
      await tester.tap(find.widgetWithText(TextButton, 'Reload'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes and reload?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Expense'), findsOneWidget);
      expect(_amountText(tester), '99');
      expect(storage.data, newer);

      await tester.tap(find.widgetWithText(TextButton, 'Reload'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard and reload'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Expense'), findsNothing);
      expect(find.text('Lunch from other tab'), findsOneWidget);
      expect(storage.data, newer);
    });

    testWidgets('reload on an unchanged paused form needs no confirmation', (
      tester,
    ) async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([_e('a', 1250, 'Lunch')]),
      );
      await _pump(tester, storage);
      await _openEdit(tester, 'Lunch');
      tester
          .element(find.byType(ExpenseFormPage))
          .read<ExpenseProvider>()
          .markExternalChange();
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Reload'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Edit Expense'), findsNothing);
    });

    testWidgets('Cancel on a dirty form asks before leaving', (tester) async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([_e('a', 1250, 'Lunch')]),
      );
      await _pump(tester, storage);
      await _openEdit(tester, 'Lunch');
      await tester.enterText(_field('Description'), 'Typed');
      await tester.pump();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Typed'), findsOneWidget);
      expect(storage.writeCount, 0);
    });

    testWidgets('a pause while the form is open disables saving', (
      tester,
    ) async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([_e('a', 1250, 'Lunch')]),
      );
      await _pump(tester, storage);
      await _openEdit(tester, 'Lunch');
      await tester.enterText(_field('Description'), 'Typed');

      tester
          .element(find.byType(ExpenseFormPage))
          .read<ExpenseProvider>()
          .markExternalChange();
      await tester.pumpAndSettle();

      expect(find.textContaining('saving is paused'), findsOneWidget);
      expect(
        (await _visible(
          tester,
          find.widgetWithText(FilledButton, 'Save changes'),
        )).onPressed,
        isNull,
      );
      expect(find.widgetWithText(TextFormField, 'Typed'), findsOneWidget);
      expect(storage.writeCount, 0);
    });

    testWidgets('a stale row is not deleted', (tester) async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([_e('a', 1250, 'Lunch')]),
      );
      await _pump(tester, storage);
      final newer = encodeExpenses([_e('a', 777, 'Lunch')]);
      storage.data = newer;

      await deleteExpenseViaUi(tester, 'Lunch');

      expect(storage.data, newer);
      expect(find.text('Reload'), findsOneWidget);
      expect(
        find.text('Expenses were changed in another tab. Reload to continue.'),
        findsOneWidget,
      );
    });

    testWidgets('while edits are paused rows cannot be edited or deleted', (
      tester,
    ) async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([_e('a', 1250, 'Lunch'), _e('b', 300, 'Bus')]),
      );
      await _pump(tester, storage);
      storage.data = encodeExpenses([_e('x', 1, 'Other')]);
      await deleteExpenseViaUi(tester, 'Lunch');

      // On the detail page: edit and delete are disabled now.
      ButtonStyleButton button(String label) =>
          tester.widget<ButtonStyleButton>(
            find.ancestor(
              of: find.text(label),
              matching: find.bySubtype<ButtonStyleButton>(),
            ),
          );
      expect(button('Edit').onPressed, isNull);
      expect(button('Delete').onPressed, isNull);

      await _backToList(tester);
      for (final tile in tester.widgetList<ExpenseTile>(
        find.byType(ExpenseTile),
      )) {
        expect(tile.onSelect, isNull);
      }
      await tester.tap(_inRow(find.text('Bus')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Edit Expense'), findsNothing);
    });
  });

  testWidgets('rows sharing an ID can be neither edited nor deleted', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeExpenseStorage(
        data: encodeExpenses([
          _e('d', 1, 'Dup'),
          _e('d', 1, 'Dup'),
          _e('s', 2, 'Single'),
        ]),
      ),
    );
    final tiles = {
      for (final t in tester.widgetList<ExpenseTile>(find.byType(ExpenseTile)))
        '${t.expense.description}#${t.hashCode}': t,
    }.values.toList();
    expect(tiles.where((t) => t.expense.id == 'd'), hasLength(2));
    for (final t in tiles) {
      expect(t.onSelect == null, t.expense.id == 'd');
    }
  });

  group('unsaved changes', () {
    Future<FakeExpenseStorage> openDirty(WidgetTester tester) async {
      final storage = FakeExpenseStorage(
        data: encodeExpenses([_e('a', 1250, 'Lunch')]),
      );
      await _pump(tester, storage);
      await _openEdit(tester, 'Lunch');
      await tester.enterText(_field('Description'), 'Unsaved');
      await tester.pump();
      return storage;
    }

    testWidgets('back asks; keep editing stays with the input', (tester) async {
      await openDirty(tester);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Expense'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Unsaved'), findsOneWidget);
    });

    testWidgets('discard leaves without saving', (tester) async {
      final storage = await openDirty(tester);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Expense'), findsNothing);
      expect(find.text('Lunch'), findsOneWidget);
      expect(storage.writeCount, 0);
    });

    testWidgets('Escape asks too, and only one dialog appears', (tester) async {
      await openDirty(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);

      // Escape again closes that dialog (= keep editing); no second dialog
      // is stacked and the input is still there.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Edit Expense'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Unsaved'), findsOneWidget);

      // Two back requests in the same frame still show exactly one dialog.
      final first = tester.binding.handlePopRoute();
      final second = tester.binding.handlePopRoute();
      await Future.wait([first, second]);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog).evaluate().length, lessThanOrEqualTo(1));
      expect(find.text('Edit Expense'), findsOneWidget);
    });

    testWidgets('system back asks before leaving', (tester) async {
      await openDirty(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
    });

    testWidgets('a formatting-only change leaves without asking', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeExpenseStorage(data: encodeExpenses([_e('a', 1250, 'Lunch')])),
      );
      await _openEdit(tester, 'Lunch');
      await tester.enterText(_field('Amount'), ' 12,5 ');
      await tester.enterText(_field('Description'), ' Lunch ');
      await tester.pump();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Edit Expense'), findsNothing);
    });

    testWidgets('an unchanged form leaves without asking', (tester) async {
      await _pump(
        tester,
        FakeExpenseStorage(data: encodeExpenses([_e('a', 1250, 'Lunch')])),
      );
      await _openEdit(tester, 'Lunch');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Edit Expense'), findsNothing);
    });

    testWidgets('the add form asks before discarding input', (tester) async {
      final storage = FakeExpenseStorage();
      await _pump(tester, storage);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      await tester.enterText(_field('Amount'), '5');
      await tester.pump();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard this expense?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(find.text('No expenses'), findsOneWidget);
      expect(storage.writeCount, 0);
    });
  });
}
