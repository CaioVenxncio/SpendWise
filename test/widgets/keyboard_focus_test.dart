// M3.6 Stage 2: keyboard navigation and focus.
//
// Focus rings appear only while the keyboard is in use; Tab follows the
// visual columns; forms start on Amount; focus returns to a sensible,
// still-existing control after dialogs, Back and deletes.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/presentation/app_theme.dart';
import 'package:spendwise/services/expense_storage.dart';
import 'package:spendwise/widgets/expense_list.dart';

import '../support/fake_expense_storage.dart';

final _now = DateTime(2026, 10, 15, 10);

Expense _e(
  String id,
  int cents,
  String description, {
  String date = '2026-10-03T12:30:00.000',
}) => Expense(
  id: id,
  amount: Money.fromCents(cents),
  description: description,
  category: 'Food',
  date: DateTime.parse(date),
  dateText: date,
);

// Shown newest first: Refund, Lunch, Huge.
final _seed = [
  _e('a', 1250, 'Lunch', date: '2026-10-05T12:30:00.000'),
  _e('b', -500, 'Refund', date: '2026-10-09T08:00:00.000'),
  _e('c', Money.maxCents, 'Huge', date: '2026-10-01T09:00:00.000'),
];

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void _brightness(WidgetTester tester, Brightness brightness) {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

Future<FakeExpenseStorage> _pump(
  WidgetTester tester, {
  List<Expense>? seed,
}) async {
  final storage = FakeExpenseStorage(data: encodeExpenses(seed ?? _seed));
  await tester.pumpWidget(SpendWiseApp(storage: storage, clock: () => _now));
  await tester.pumpAndSettle();
  return storage;
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<void> _shiftTab(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pumpAndSettle();
}

String? _firstText(Element element) {
  String? found;
  void visit(Element e) {
    if (found != null) return;
    final widget = e.widget;
    if (widget is Text) {
      found = widget.data;
      return;
    }
    e.visitChildElements(visit);
  }

  visit(element);
  return found;
}

/// A readable name for whatever has keyboard focus.
String? _focused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final tile = context.findAncestorWidgetOfExactType<ExpenseTile>();
  if (tile != null) return 'row ${tile.expense.description}';
  if (context.findAncestorWidgetOfExactType<FloatingActionButton>() != null) {
    return 'Add expense';
  }
  if (context.findAncestorWidgetOfExactType<BackButton>() != null) {
    return 'Back';
  }
  final field = context.findAncestorWidgetOfExactType<TextField>();
  if (field != null) return 'field ${field.decoration?.labelText}';
  return _firstText(context as Element);
}

Future<void> _tabTo(WidgetTester tester, String target) async {
  for (var i = 0; i < 25 && _focused() != target; i++) {
    await _key(tester, LogicalKeyboardKey.tab);
  }
  expect(_focused(), target);
}

/// Row descriptions in on-screen order.
List<String> _rowsOnScreen(WidgetTester tester) {
  final tiles = find.byType(ExpenseTile).evaluate().toList()
    ..sort(
      (a, b) => tester
          .getTopLeft(find.byWidget(a.widget))
          .dy
          .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
    );
  return [for (final t in tiles) (t.widget as ExpenseTile).expense.description];
}

Finder _rowMaterial(String description) => find
    .descendant(
      of: find.ancestor(
        of: find.text(description),
        matching: find.byType(ExpenseTile),
      ),
      matching: find.byType(Material),
    )
    .first;

BorderSide _rowSide(WidgetTester tester, String description) =>
    (tester.widget<Material>(_rowMaterial(description)).shape!
            as RoundedRectangleBorder)
        .side;

BorderSide _buttonSide(WidgetTester tester, Finder button) {
  final shape = tester
      .widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first,
      )
      .shape;
  return (shape! as OutlinedBorder).side;
}

SpendWiseColors _tokens(Brightness b) =>
    b == Brightness.dark ? SpendWiseColors.dark : SpendWiseColors.light;

void main() {
  group('KB-01 visible focus, keyboard only', () {
    for (final brightness in Brightness.values) {
      for (final width in [360.0, 1200.0]) {
        testWidgets('${brightness.name}, ${width.toInt()} px: rings while '
            'tabbing, none after a pointer press', (tester) async {
          _size(tester, width);
          _brightness(tester, brightness);
          await _pump(tester);
          final focus = _tokens(brightness).focus;

          await _tabTo(tester, 'Add expense');
          final add = find.byType(FloatingActionButton);
          expect(_buttonSide(tester, add).color, focus);
          expect(_buttonSide(tester, add).width, 2);
          // Drawn outside the button, with a gap.
          expect(_buttonSide(tester, add).strokeAlign, greaterThan(1));

          await _tabTo(tester, 'row Refund');
          expect(_rowSide(tester, 'Refund').color, focus);
          expect(_rowSide(tester, 'Refund').width, 2);
          expect(_rowSide(tester, 'Lunch'), BorderSide.none);
          expect(_buttonSide(tester, add).width, isNot(2));

          // A pointer press anywhere hides the rings; focus stays.
          await tester.tapAt(const Offset(4, 300));
          await tester.pumpAndSettle();
          expect(_focused(), 'row Refund');
          expect(_rowSide(tester, 'Refund'), BorderSide.none);

          // The next key press shows it again.
          await _key(tester, LogicalKeyboardKey.tab);
          await _shiftTab(tester);
          expect(_focused(), 'row Refund');
          expect(_rowSide(tester, 'Refund').color, focus);
        });
      }

      testWidgets('${brightness.name}: Edit and Delete show the ring', (
        tester,
      ) async {
        _size(tester, 1200);
        _brightness(tester, brightness);
        await _pump(tester);
        final focus = _tokens(brightness).focus;

        await _tabTo(tester, 'row Lunch');
        await _key(tester, LogicalKeyboardKey.enter);
        await _tabTo(tester, 'Edit');
        final edit = find.widgetWithText(FilledButton, 'Edit');
        expect(_buttonSide(tester, edit).color, focus);
        await _key(tester, LogicalKeyboardKey.tab);
        expect(_focused(), 'Delete');
        final delete = find.widgetWithText(OutlinedButton, 'Delete');
        expect(_buttonSide(tester, delete).color, focus);
        expect(_buttonSide(tester, edit).width, isNot(2));
      });
    }

    testWidgets('a mouse user sees no ring, even where focus was moved', (
      tester,
    ) async {
      _size(tester, 1200);
      await _pump(tester);
      await tester.tap(find.text('Lunch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      // The dialog puts focus on Cancel, without a ring for the mouse.
      expect(_focused(), 'Cancel');
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      expect(_buttonSide(tester, cancel).width, isNot(2));
    });
  });

  group('focused versus selected rows', () {
    testWidgets('the two states look different and combine', (tester) async {
      _size(tester, 1200);
      _brightness(tester, Brightness.dark);
      await _pump(tester);
      final tokens = SpendWiseColors.dark;
      Color? fill(String d) => tester.widget<Material>(_rowMaterial(d)).color;

      await _tabTo(tester, 'row Lunch');
      // Focused only: ring, no selected fill.
      expect(_rowSide(tester, 'Lunch').color, tokens.focus);
      expect(fill('Lunch'), isNot(tokens.surfaceSelected));

      await _key(tester, LogicalKeyboardKey.enter);
      // Focused and selected: both.
      expect(_rowSide(tester, 'Lunch').color, tokens.focus);
      expect(fill('Lunch'), tokens.surfaceSelected);

      await _key(tester, LogicalKeyboardKey.tab);
      expect(_focused(), 'row Huge');
      // Selected only: fill, no ring.
      expect(_rowSide(tester, 'Lunch'), BorderSide.none);
      expect(fill('Lunch'), tokens.surfaceSelected);
      expect(_rowSide(tester, 'Huge').color, tokens.focus);
      expect(fill('Huge'), isNot(tokens.surfaceSelected));
    });
  });

  group('KB-02 traversal order', () {
    testWidgets('workspace: the actions column, then Add expense and the '
        'rows, whichever row is selected', (tester) async {
      _size(tester, 1200);
      await _pump(tester);
      expect(_rowsOnScreen(tester), ['Refund', 'Lunch', 'Huge']);

      for (final selected in ['Refund', 'Lunch', 'Huge']) {
        await _tabTo(tester, 'row $selected');
        await _key(tester, LogicalKeyboardKey.enter);

        await _tabTo(tester, 'Edit');
        await _key(tester, LogicalKeyboardKey.tab);
        expect(_focused(), 'Delete');
        await _key(tester, LogicalKeyboardKey.tab);
        expect(_focused(), 'Add expense');
        final forward = <String?>[];
        for (var i = 0; i < 3; i++) {
          await _key(tester, LogicalKeyboardKey.tab);
          forward.add(_focused());
        }
        expect(forward, ['row Refund', 'row Lunch', 'row Huge']);

        // Shift+Tab walks the same order back.
        final back = <String?>[];
        for (var i = 0; i < 5; i++) {
          await _shiftTab(tester);
          back.add(_focused());
        }
        expect(back, [
          'row Lunch',
          'row Refund',
          'Add expense',
          'Delete',
          'Edit',
        ]);
      }
    });

    testWidgets('compact: Add expense, then the rows in list order', (
      tester,
    ) async {
      _size(tester, 360);
      await _pump(tester);
      await _tabTo(tester, 'Add expense');
      final order = <String?>[];
      for (var i = 0; i < 3; i++) {
        await _key(tester, LogicalKeyboardKey.tab);
        order.add(_focused());
      }
      expect(order, ['row Refund', 'row Lunch', 'row Huge']);
      await _shiftTab(tester);
      await _shiftTab(tester);
      await _shiftTab(tester);
      expect(_focused(), 'Add expense');
    });
  });

  group('KB-03 form initial focus', () {
    testWidgets('the add form starts on Amount', (tester) async {
      _size(tester, 1200);
      await _pump(tester);
      await _tabTo(tester, 'Add expense');
      await _key(tester, LogicalKeyboardKey.enter);
      expect(find.text('Add Expense'), findsWidgets);
      expect(_focused(), 'field Amount');
    });

    testWidgets(
      'the edit form starts on Amount; the value is neither selected nor '
      'changed',
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      (tester) async {
        _size(tester, 1200);
        final storage = await _pump(tester);
        await _tabTo(tester, 'row Lunch');
        await _key(tester, LogicalKeyboardKey.enter);
        await _tabTo(tester, 'Edit');
        await _key(tester, LogicalKeyboardKey.enter);

        expect(_focused(), 'field Amount');
        final amount = tester.widget<EditableText>(
          find.descendant(
            of: find.widgetWithText(TextFormField, 'Amount'),
            matching: find.byType(EditableText),
          ),
        );
        expect(amount.controller.text, '12.50');
        expect(amount.controller.selection.isCollapsed, isTrue);
        expect(amount.controller.selection.baseOffset, 5);

        // Unchanged: Escape leaves without asking or writing, and focus
        // returns to Edit.
        await _key(tester, LogicalKeyboardKey.escape);
        expect(find.text('Edit Expense'), findsNothing);
        expect(storage.writeCount, 0);
        expect(_focused(), 'Edit');
      },
    );

    testWidgets('Escape from the focused Amount field still asks before '
        'discarding input', (tester) async {
      _size(tester, 1200);
      final storage = await _pump(tester);
      await _tabTo(tester, 'Add expense');
      await _key(tester, LogicalKeyboardKey.enter);
      expect(_focused(), 'field Amount');
      await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '5');
      await tester.pumpAndSettle();

      await _key(tester, LogicalKeyboardKey.escape);
      expect(find.text('Discard this expense?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('5'), findsOneWidget);
      expect(storage.writeCount, 0);
    });

    testWidgets('an invalid submit still focuses the first invalid field', (
      tester,
    ) async {
      _size(tester, 1200);
      await _pump(tester);
      await _tabTo(tester, 'Add expense');
      await _key(tester, LogicalKeyboardKey.enter);
      await _tabTo(tester, 'Add Expense');
      await _key(tester, LogicalKeyboardKey.enter);
      expect(_focused(), 'field Amount');
    });
  });

  group('KB-04 focus restoration', () {
    for (final close in ['Cancel', 'Escape']) {
      testWidgets('workspace: closing the delete dialog with $close returns '
          'to Delete; nothing is written', (tester) async {
        _size(tester, 1200);
        final storage = await _pump(tester);
        await _tabTo(tester, 'row Lunch');
        await _key(tester, LogicalKeyboardKey.enter);
        await _tabTo(tester, 'Delete');
        await _key(tester, LogicalKeyboardKey.enter);

        expect(find.text('Delete this expense?'), findsOneWidget);
        // The dialog starts on the safe choice.
        expect(_focused(), 'Cancel');
        await _key(
          tester,
          close == 'Cancel'
              ? LogicalKeyboardKey.enter
              : LogicalKeyboardKey.escape,
        );

        expect(find.text('Delete this expense?'), findsNothing);
        expect(_focused(), 'Delete');
        expect(storage.writeCount, 0);
      });
    }

    for (final (deleted, expected) in [
      ('Refund', 'row Lunch'), // the next row
      ('Huge', 'row Lunch'), // the last row: the previous one
    ]) {
      testWidgets('workspace: after deleting $deleted, focus moves to '
          '$expected', (tester) async {
        _size(tester, 1200);
        final storage = await _pump(tester);
        await _tabTo(tester, 'row $deleted');
        await _key(tester, LogicalKeyboardKey.enter);
        await _tabTo(tester, 'Delete');
        await _key(tester, LogicalKeyboardKey.enter);
        await _key(tester, LogicalKeyboardKey.tab);
        expect(_focused(), 'Delete expense');
        await _key(tester, LogicalKeyboardKey.enter);

        expect(storage.writeCount, 1);
        expect(find.text('Expense deleted'), findsOneWidget);
        expect(_focused(), expected);
      });
    }

    testWidgets('workspace: deleting the only expense moves focus to Add '
        'expense', (tester) async {
      _size(tester, 1200);
      await _pump(tester, seed: [_seed.first]);
      await _tabTo(tester, 'row Lunch');
      await _key(tester, LogicalKeyboardKey.enter);
      await _tabTo(tester, 'Delete');
      await _key(tester, LogicalKeyboardKey.enter);
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(find.byType(ExpenseTile), findsNothing);
      expect(_focused(), 'Add expense');
    });

    testWidgets('workspace: a delete refused after a change elsewhere moves '
        'focus nowhere new', (tester) async {
      _size(tester, 1200);
      final storage = await _pump(tester);
      await _tabTo(tester, 'row Lunch');
      await _key(tester, LogicalKeyboardKey.enter);
      await _tabTo(tester, 'Delete');
      final newer = encodeExpenses([
        _e('a', 7777, 'Lunch', date: '2026-10-05T12:30:00.000'),
        ..._seed.skip(1),
      ]);
      storage.data = newer;
      await _key(tester, LogicalKeyboardKey.enter);
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.enter);

      expect(storage.data, newer);
      expect(find.text('Reload'), findsOneWidget);
      // Edits are paused, so Delete is disabled; focus does not jump to a
      // neighbouring row as if the expense were gone.
      expect(_focused(), isNot(startsWith('row ')));
      final node = FocusManager.instance.primaryFocus;
      expect(node == null || node.context!.mounted, isTrue);
    });

    testWidgets('compact: Back from the details returns to the row', (
      tester,
    ) async {
      _size(tester, 360);
      await _pump(tester);
      await _tabTo(tester, 'row Lunch');
      await _key(tester, LogicalKeyboardKey.enter);
      expect(find.text('Expense'), findsOneWidget);

      await _tabTo(tester, 'Back');
      await _key(tester, LogicalKeyboardKey.enter);
      expect(find.text('Expense'), findsNothing);
      expect(_focused(), 'row Lunch');
    });

    testWidgets('compact: after a delete on the details page, focus moves '
        'to the next row', (tester) async {
      _size(tester, 360);
      final storage = await _pump(tester);
      await _tabTo(tester, 'row Refund');
      await _key(tester, LogicalKeyboardKey.enter);
      await _tabTo(tester, 'Delete');
      await _key(tester, LogicalKeyboardKey.enter);
      expect(_focused(), 'Cancel');
      // Cancel first: focus stays on the page's Delete.
      await _key(tester, LogicalKeyboardKey.enter);
      expect(_focused(), 'Delete');

      await _key(tester, LogicalKeyboardKey.enter);
      await _key(tester, LogicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(storage.writeCount, 1);
      expect(find.text('Expense'), findsNothing);
      expect(_focused(), 'row Lunch');
    });
  });
}
