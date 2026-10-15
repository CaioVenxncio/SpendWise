import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/presentation/app_theme.dart';
import 'package:spendwise/providers/expense_provider.dart';
import 'package:spendwise/services/expense_storage.dart';
import 'package:spendwise/widgets/expense_detail.dart';
import 'package:spendwise/widgets/expense_list.dart';

import '../support/fake_expense_storage.dart';
import '../support/ui_actions.dart';

final _now = DateTime(2026, 10, 15, 10);

Expense _e(
  String id,
  int cents,
  String description, {
  String category = 'Food',
  String date = '2026-10-03T12:30:00.000',
}) => Expense(
  id: id,
  amount: Money.fromCents(cents),
  description: description,
  category: category,
  date: DateTime.parse(date),
  dateText: date,
);

/// Stored in this order (oldest first in storage, not by date).
final _seed = [
  _e('a', 1250, 'Lunch', date: '2026-10-03T12:30:00.000'),
  _e(
    'b',
    -500,
    'Refund',
    category: 'Transport',
    date: '2026-10-09T08:00:00.000',
  ),
  _e(
    'c',
    Money.maxCents,
    'A very long imported description that keeps going well beyond what '
        'fits on one line of a narrow phone screen',
    category: 'Groceries',
    date: '2026-10-06T18:00:00.000+02:00',
  ),
];

void _size(WidgetTester tester, double width, {double height = 900}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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

List<String> _shownOrder(WidgetTester tester) => [
  for (final t in tester.widgetList<ExpenseTile>(find.byType(ExpenseTile)))
    t.expense.id,
];

ExpenseTile _tile(WidgetTester tester, String description) =>
    tester.widget<ExpenseTile>(
      find.ancestor(
        of: find.text(description),
        matching: find.byType(ExpenseTile),
      ),
    );

void main() {
  group('responsive layouts', () {
    for (final width in <double>[
      320,
      360,
      599,
      600,
      839,
      840,
      1199,
      1200,
      1440,
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${width.toInt()} px at ${scale}x text: right layout, no '
            'overflow', (tester) async {
          _size(tester, width, height: scale > 1 ? 1400 : 900);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await _pump(tester);

          expect(tester.takeException(), isNull);
          final workspace = width >= 840;
          expect(
            find.byType(MonthlyHero),
            workspace ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(CompactMonthlySummary),
            workspace ? findsNothing : findsOneWidget,
          );
          expect(
            find.byType(EmptySelection),
            workspace ? findsOneWidget : findsNothing,
          );
          // The add action is always visible and labelled.
          expect(find.byTooltip('Add expense'), findsOneWidget);
          // Every amount is shown in full (scaled, never cut).
          expect(find.text(r'$90,071,992,547,409.91'), findsOneWidget);
          expect(find.text(r'-$5.00'), findsOneWidget);
        });
      }
    }

    testWidgets('workspace columns are about 40 / 60', (tester) async {
      _size(tester, 1200);
      await _pump(tester);

      final hero = tester.getRect(find.byType(MonthlyHero));
      final list = tester.getRect(find.byType(ExpenseTile).first);
      final fraction = hero.width / (hero.width + list.width);
      expect(fraction, inInclusiveRange(0.35, 0.45));
      expect(hero.right, lessThan(list.left));
      // The panel content starts at the panel padding, not centred.
      final label = tester.getRect(find.text('SELECTED EXPENSE'));
      expect(label.left - hero.left, inInclusiveRange(20, 30));
    });

    testWidgets('very wide windows keep a maximum workspace width', (
      tester,
    ) async {
      _size(tester, 2400);
      await _pump(tester);
      final hero = tester.getRect(find.byType(MonthlyHero));
      final list = tester.getRect(find.byType(ExpenseTile).first);
      expect(list.right - hero.left, lessThanOrEqualTo(appWorkspaceMaxWidth));
      expect(hero.left, greaterThan(400));
    });

    testWidgets('medium widths centre a single column', (tester) async {
      _size(tester, 800);
      await _pump(tester);
      final row = tester.getRect(find.byType(ExpenseTile).first);
      expect(row.width, lessThanOrEqualTo(appContentMaxWidth));
      expect((row.left - (800 - row.right)).abs(), lessThan(2));
    });
  });

  group('design', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: hero is the lime surface, the compact '
          'summary is typographic', (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        _size(tester, 1200);
        await _pump(tester);

        final tokens = brightness == Brightness.dark
            ? SpendWiseColors.dark
            : SpendWiseColors.light;
        final hero = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(MonthlyHero),
                matching: find.byType(Container),
              )
              .first,
        );
        expect((hero.decoration! as BoxDecoration).color, tokens.accent);
        expect(find.text('Total spent this month'), findsOneWidget);
        expect(find.text('October 2026'), findsOneWidget);
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        _size(tester, 360);
        await tester.pumpAndSettle();
        expect(find.byType(MonthlyHero), findsNothing);
        final fab = tester.widget<FloatingActionButton>(
          find.byType(FloatingActionButton),
        );
        expect(
          fab.backgroundColor ??
              Theme.of(tester.element(find.byType(FloatingActionButton)))
                  .floatingActionButtonTheme
                  .backgroundColor,
          tokens.accent,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      });
    }

    test('dropdown menus use the panel surface, not the page colour', () {
      for (final (theme, tokens) in [
        (AppTheme.dark(), SpendWiseColors.dark),
        (AppTheme.light(), SpendWiseColors.light),
      ]) {
        expect(theme.canvasColor, tokens.surface);
        expect(theme.canvasColor, isNot(tokens.background));
      }
    });

    testWidgets('a disabled Delete has no error-coloured border', (
      tester,
    ) async {
      _size(tester, 1200);
      final storage = await _pump(tester);
      await openExpense(tester, 'Lunch');
      storage.data = encodeExpenses([_seed[1]]);
      tester
          .element(find.byType(MonthlyHero))
          .read<ExpenseProvider>()
          .markExternalChange();
      await tester.pumpAndSettle();

      final button = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Delete'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(button.onPressed, isNull);
      final scheme = Theme.of(tester.element(find.text('Delete'))).colorScheme;
      final side = button.style!.side!.resolve({WidgetState.disabled})!;
      expect(side.color, scheme.onSurface.withValues(alpha: 0.12));
    });

    testWidgets('monthly total is exact and labelled', (tester) async {
      _size(tester, 1200);
      await _pump(
        tester,
        seed: [
          _e('a', 123456, 'Laptop'),
          _e('b', -500, 'Refund'),
          _e('c', 999, 'Old', date: '2026-09-30T12:00:00.000'),
        ],
      );
      expect(
        find.bySemanticsLabel(r'Total this month: $1,229.56'),
        findsOneWidget,
      );
      expect(find.text(r'$1,229.56'), findsOneWidget);
    });

    testWidgets('wordmark and section markers are shown', (tester) async {
      _size(tester, 1200);
      await _pump(tester);
      expect(find.bySemanticsLabel('SpendWise'), findsOneWidget);
      expect(find.text('01 / MONTHLY OVERVIEW'), findsOneWidget);
      expect(find.text('02 / YOUR ACTIVITY'), findsOneWidget);
      expect(find.text('SELECTED EXPENSE'), findsOneWidget);
    });
  });

  group('ordering', () {
    testWidgets('newest first on screen; storage order unchanged', (
      tester,
    ) async {
      _size(tester, 1200);
      final storage = await _pump(tester);
      final before = storage.data;
      // Dates: b 10-09, c 10-06 (+02:00), a 10-03.
      expect(_shownOrder(tester), ['b', 'c', 'a']);
      expect(storage.data, before);
      expect(storage.writeCount, 0);
    });

    testWidgets('an edit that moves a date re-sorts but keeps selection', (
      tester,
    ) async {
      _size(tester, 1200);
      final storage = await _pump(tester);
      await openEditForm(tester, 'Lunch');
      await tester.tap(find.byTooltip('Pick date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(_shownOrder(tester), ['a', 'b', 'c']);
      expect(_tile(tester, 'Lunch').selected, isTrue);
      expect(decodeExpenses(storage.data!).expenses.map((e) => e.id), [
        'a',
        'b',
        'c',
      ]);
    });
  });

  group('selection (workspace)', () {
    testWidgets('selecting a row fills the detail panel', (tester) async {
      _size(tester, 1200);
      await _pump(tester);
      expect(find.text('No expense selected'), findsOneWidget);

      await openExpense(tester, 'Lunch');

      expect(_tile(tester, 'Lunch').selected, isTrue);
      expect(_tile(tester, 'Refund').selected, isFalse);
      final detail = find.byType(ExpenseDetailView);
      expect(
        find.descendant(of: detail, matching: find.text('Lunch')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: detail, matching: find.text(r'$12.50')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: detail, matching: find.text('October 3, 2026')),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byType(ExpenseTile).at(2)),
        isSemantics(isSelected: true, hasSelectedState: true),
      );
      // Still on the home page (no navigation).
      expect(find.byType(MonthlyHero), findsOneWidget);
    });

    testWidgets('selection survives resizing in both directions', (
      tester,
    ) async {
      _size(tester, 1200);
      await _pump(tester);
      await openExpense(tester, 'Refund');

      _size(tester, 700);
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseDetailView), findsNothing);
      expect(_tile(tester, 'Refund').selected, isTrue);

      _size(tester, 1440);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(ExpenseDetailView),
          matching: find.text('Refund'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an edit updates the selected details', (tester) async {
      _size(tester, 1200);
      await _pump(tester);
      await openEditForm(tester, 'Lunch');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Lunch'),
        'Team lunch',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(ExpenseDetailView),
          matching: find.text('Team lunch'),
        ),
        findsOneWidget,
      );
      expect(_tile(tester, 'Team lunch').selected, isTrue);
    });

    testWidgets('deleting the selected expense clears the selection', (
      tester,
    ) async {
      _size(tester, 1200);
      final storage = await _pump(tester);
      await deleteExpenseViaUi(tester, 'Lunch');

      expect(find.text('Lunch'), findsNothing);
      expect(find.text('Expense deleted'), findsOneWidget);
      // Selecting another expense replaces the message.
      await openExpense(tester, 'Refund');
      expect(find.text('Expense deleted'), findsNothing);
      expect(decodeExpenses(storage.data!).expenses.map((e) => e.id), [
        'b',
        'c',
      ]);
    });

    testWidgets('a selected expense removed elsewhere is reported, never '
        'replaced by another', (tester) async {
      _size(tester, 1200);
      final storage = await _pump(tester);
      await openExpense(tester, 'Lunch');

      storage.data = encodeExpenses([_seed[1], _seed[2]]);
      tester
          .element(find.byType(MonthlyHero))
          .read<ExpenseProvider>()
          .markExternalChange();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reload'));
      await tester.pumpAndSettle();

      expect(
        find.text('The selected expense is no longer in your list.'),
        findsOneWidget,
      );
      expect(find.byType(ExpenseDetailView), findsNothing);
      for (final t in tester.widgetList<ExpenseTile>(
        find.byType(ExpenseTile),
      )) {
        expect(t.selected, isFalse);
      }
      await tester.tap(find.text('Clear selection'));
      await tester.pumpAndSettle();
      expect(find.text('No expense selected'), findsOneWidget);
    });

    testWidgets('an empty list shows the empty states', (tester) async {
      _size(tester, 1200);
      await _pump(tester, seed: const []);
      expect(find.text('No expenses'), findsOneWidget);
      expect(find.text('Nothing to show yet'), findsOneWidget);
      expect(
        find.text('Use Add expense to record your first one.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(r'Total this month: $0.00'), findsOneWidget);
    });
  });

  group('compact detail page', () {
    testWidgets('a row opens the details; back returns to the list', (
      tester,
    ) async {
      _size(tester, 360);
      await _pump(tester);
      await openExpense(tester, 'Refund');

      expect(find.text('Expense'), findsOneWidget);
      expect(find.text(r'-$5.00'), findsOneWidget);
      expect(find.text('Transport'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(CompactMonthlySummary), findsOneWidget);
      expect(_tile(tester, 'Refund').selected, isTrue);
    });

    testWidgets('a record deleted elsewhere shows "no longer in your list"', (
      tester,
    ) async {
      _size(tester, 360);
      final storage = await _pump(tester);
      await openExpense(tester, 'Lunch');

      storage.data = encodeExpenses([_seed[1]]);
      tester
          .element(find.byType(ExpenseDetailView))
          .read<ExpenseProvider>()
          .markExternalChange();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reload'));
      await tester.pumpAndSettle();

      expect(
        find.text('The selected expense is no longer in your list.'),
        findsOneWidget,
      );
      expect(find.text('Refund'), findsNothing);
    });
  });

  group('delete confirmation', () {
    testWidgets('shows what will be deleted; cancel writes nothing', (
      tester,
    ) async {
      _size(tester, 1200);
      final storage = await _pump(tester);
      await openExpense(tester, 'Lunch');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      expect(find.text('Delete this expense?'), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('Lunch')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(r'$12.50 · Food · October 3, 2026'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('cannot be undone'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(storage.writeCount, 0);
      expect(_tile(tester, 'Lunch').selected, isTrue);
    });

    testWidgets('confirm deletes exactly that record once', (tester) async {
      _size(tester, 1200);
      final storage = await _pump(tester);
      await openExpense(tester, 'Lunch');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      storage.readGate = Completer<void>();
      await tester.tap(find.text('Delete expense'));
      // Let the dialog finish closing; the write is still pending.
      await tester.pumpAndSettle();
      expect(find.text('Delete this expense?'), findsNothing);
      // While the write is pending the Delete button is disabled.
      final delete = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Delete'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(delete.onPressed, isNull);
      expect(find.byType(AlertDialog), findsNothing, reason: 'before tap');
      await tester.tap(find.text('Delete'), warnIfMissed: false);
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);

      storage.readGate!.complete();
      storage.readGate = null;
      await tester.pumpAndSettle();
      expect(storage.writeCount, 1);
      expect(decodeExpenses(storage.data!).expenses.map((e) => e.id), [
        'b',
        'c',
      ]);
      expect(find.text('Expense deleted.'), findsOneWidget);
    });

    testWidgets('a record changed in another tab is not deleted', (
      tester,
    ) async {
      _size(tester, 1200);
      final storage = await _pump(tester);
      final newer = encodeExpenses([_e('a', 7777, 'Lunch'), ..._seed.skip(1)]);
      storage.data = newer;

      await deleteExpenseViaUi(tester, 'Lunch');

      expect(storage.data, newer);
      expect(find.text('Reload'), findsOneWidget);
      expect(
        find.text('Expenses were changed in another tab. Reload to continue.'),
        findsOneWidget,
      );
      expect(_tile(tester, 'Lunch').selected, isTrue);
    });
  });
}
