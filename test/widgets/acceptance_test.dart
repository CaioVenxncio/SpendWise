// M3.5 acceptance review: regression tests for the findings.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/presentation/formatting.dart';
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
  DateTime? date,
}) => Expense(
  id: id,
  amount: Money.fromCents(cents),
  description: description,
  category: category,
  date: date ?? DateTime(2026, 10, 3, 12),
);

const _long =
    'A very long imported description that keeps going well beyond what '
    'fits on one line of a narrow phone screen';

void _size(WidgetTester tester, double width, {double height = 1400}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void _textScale(WidgetTester tester, double scale) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<FakeExpenseStorage> _pump(
  WidgetTester tester,
  List<Expense> seed,
) async {
  final storage = FakeExpenseStorage(data: encodeExpenses(seed));
  await tester.pumpWidget(SpendWiseApp(storage: storage, clock: () => _now));
  await tester.pumpAndSettle();
  return storage;
}

/// How much [finder]'s text is scaled on screen (1 = natural size).
double _scaleOf(WidgetTester tester, Finder finder) =>
    tester.getRect(finder).width /
    tester.renderObject<RenderBox>(finder).size.width;

void main() {
  group('monthly total presentation', () {
    for (final (label, cents, shown) in [
      ('zero', <int>[], r'$0.00'),
      ('ordinary', [1250, 300], r'$15.50'),
      ('negative', [-500, -125], r'-$6.25'),
      (
        'maximum individual amount',
        [Money.maxCents],
        r'$90,071,992,547,409.91',
      ),
      (
        'aggregate at the boundary',
        [Money.maxCents - 100, 100],
        r'$90,071,992,547,409.91',
      ),
      (
        'aggregate at the lower boundary',
        [Money.minCents + 1, -1],
        r'-$90,071,992,547,409.91',
      ),
    ]) {
      for (final width in [360.0, 1200.0]) {
        testWidgets('$label at ${width.toInt()} px: exact, every digit', (
          tester,
        ) async {
          _size(tester, width);
          await _pump(tester, [
            for (var i = 0; i < cents.length; i++) _e('e$i', cents[i], 'E$i'),
          ]);
          expect(tester.takeException(), isNull);
          expect(
            find.bySemanticsLabel('Total this month: $shown'),
            findsOneWidget,
          );
          final summary = width >= 840
              ? find.byType(MonthlyHero)
              : find.byType(CompactMonthlySummary);
          expect(
            find.descendant(of: summary, matching: find.text(shown)),
            findsOneWidget,
          );
        });
      }
    }

    testWidgets('an aggregate beyond the range fails closed and says why', (
      tester,
    ) async {
      _size(tester, 1200);
      await _pump(tester, [
        _e('a', Money.maxCents, 'Huge'),
        _e('b', 1, 'One cent'),
      ]);
      final hero = find.byType(MonthlyHero);
      expect(
        find.descendant(of: hero, matching: find.text('Total unavailable')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: hero,
          matching: find.textContaining(
            'more than SpendWise can total exactly',
          ),
        ),
        findsOneWidget,
      );
      // No figure is presented as the total.
      expect(
        find.descendant(of: hero, matching: find.textContaining(r'$')),
        findsNothing,
      );
      // Individual expenses are still exact.
      expect(inRow(find.text(r'$90,071,992,547,409.91')), findsOneWidget);
      expect(inRow(find.text(r'$0.01')), findsOneWidget);
    });

    test('a representable total is reported whatever the order (M1 sum, fixed '
        'in the M3.5 closure)', () {
      final max = Money.fromCents(Money.maxCents);
      expect(Money.sum([max, Money.fromCents(1), Money.fromCents(-1)]), max);
    });
  });

  group('M3.5 closure: order-independent monthly total', () {
    // MAX + 1 cent - 1 cent: the partial sum leaves the range in some orders.
    final orders = <List<int>>[
      [Money.maxCents, 1, -1],
      [1, Money.maxCents, -1],
      [-1, 1, Money.maxCents],
    ];
    for (final brightness in Brightness.values) {
      for (final width in [360.0, 1200.0]) {
        for (final (i, order) in orders.indexed) {
          testWidgets('${brightness.name} ${width.toInt()} px, order $i: the '
              'exact total is shown', (tester) async {
            tester.platformDispatcher.platformBrightnessTestValue = brightness;
            addTearDown(
              tester.platformDispatcher.clearPlatformBrightnessTestValue,
            );
            _size(tester, width);
            await _pump(tester, [
              for (var k = 0; k < order.length; k++)
                _e('e$i$k', order[k], 'E$k'),
            ]);
            const exact = r'$90,071,992,547,409.91';
            final summary = width >= 840
                ? find.byType(MonthlyHero)
                : find.byType(CompactMonthlySummary);
            expect(
              find.descendant(of: summary, matching: find.text(exact)),
              findsOneWidget,
            );
            expect(find.text('Total unavailable'), findsNothing);
            expect(
              find.bySemanticsLabel('Total this month: $exact'),
              findsOneWidget,
            );
            // Individual amounts stay exact.
            expect(inRow(find.text(exact)), findsOneWidget);
            expect(inRow(find.text(r'$0.01')), findsOneWidget);
            expect(inRow(find.text(r'-$0.01')), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('a genuinely out-of-range total still fails closed', (
      tester,
    ) async {
      _size(tester, 360);
      await _pump(tester, [
        _e('a', 1, 'One cent'),
        _e('b', Money.maxCents, 'Huge'),
        _e('c', -1, 'Minus'),
        _e('d', 1, 'Another cent'),
      ]);
      expect(find.text('Total unavailable'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CompactMonthlySummary),
          matching: find.textContaining(r'$'),
        ),
        findsNothing,
      );
    });
  });

  group('M3.5 closure: dates', () {
    testWidgets('English dates on every screen; the stored text is untouched', (
      tester,
    ) async {
      _size(tester, 1200);
      final expense = Expense(
        id: 'd1',
        amount: Money.fromCents(1250),
        description: 'Lunch',
        category: 'Food',
        date: DateTime.parse('2026-10-06T08:00:00.000+02:00'),
        dateText: '2026-10-06T08:00:00.000+02:00',
      );
      final storage = await _pump(tester, [expense]);
      final local = expense.date.toLocal();
      final short = formatShortDate(local);
      final long = formatLongDate(local);

      expect(inRow(find.text('Food - $short')), findsOneWidget);
      await openExpense(tester, 'Lunch');
      expect(
        find.descendant(
          of: find.byType(ExpenseDetailView),
          matching: find.text(long),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text(r'$12.50 · Food · ' + long), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Date: $long'), findsOneWidget);
      // Saving unchanged writes nothing; the stored text stays verbatim.
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();
      expect(storage.writeCount, 0);
      expect(storage.data, contains('"date":"2026-10-06T08:00:00.000+02:00"'));
      // No ISO date is shown anywhere.
      expect(find.textContaining(RegExp(r'\d{4}-\d{2}-\d{2}')), findsNothing);
    });

    for (final width in <double>[
      320, 360, 599, 600, 839, 840, 1199, 1200, 1440, //
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${width.toInt()} px at ${scale}x: row dates readable', (
          tester,
        ) async {
          _size(tester, width, height: 1600);
          _textScale(tester, scale);
          await _pump(tester, [
            _e(
              'a',
              1250,
              'Lunch',
              category: 'Entertainment',
              date: DateTime(2026, 9, 30),
            ),
            _e(
              'b',
              Money.maxCents,
              _long,
              category: 'Groceries',
              date: DateTime(2026, 12, 31),
            ),
          ]);
          expect(tester.takeException(), isNull);
          for (final meta in [
            'Entertainment - Sep 30, 2026',
            'Groceries - Dec 31, 2026',
          ]) {
            final paragraph = tester.renderObject<RenderParagraph>(
              inRow(find.text(meta)),
            );
            expect(paragraph.didExceedMaxLines, isFalse, reason: meta);
          }
        });
      }
    }
  });

  group('narrow rows', () {
    for (final width in <double>[320, 360, 599, 600, 840, 900, 1024]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('${width.toInt()} px at ${scale}x: long amounts get their '
            'own line at readable size; ordinary ones stay inline', (
          tester,
        ) async {
          _size(tester, width, height: 1600);
          _textScale(tester, scale);
          await _pump(tester, [
            _e('big', Money.maxCents, _long, category: 'Groceries'),
            _e('neg', -123456, 'Refund', category: 'Transport'),
            _e('small', 1250, 'Lunch', date: DateTime(2026, 10, 1)),
          ]);
          expect(tester.takeException(), isNull);

          final big = inRow(find.text(r'$90,071,992,547,409.91'));
          final bigDescription = inRow(find.text(_long));
          expect(big, findsOneWidget);
          // Stacked: below the description, not squeezed beside it.
          expect(
            tester.getRect(big).top,
            greaterThan(tester.getRect(bigDescription).top),
          );
          // Readable: at natural size whenever it fits the row width.
          final rowWidth = tester.getSize(find.byType(ExpenseTile).first).width;
          final natural = tester.renderObject<RenderBox>(big).size.width;
          if (natural <= rowWidth - 80) {
            expect(_scaleOf(tester, big), closeTo(1, 0.01));
          }

          final small = inRow(find.text(r'$12.50'));
          final lunch = inRow(find.text('Lunch'));
          if (scale == 1.0) {
            // Inline: on the description's line, at natural size.
            expect(
              tester.getRect(small).center.dy,
              closeTo(
                tester
                    .getRect(
                      find.ancestor(
                        of: lunch,
                        matching: find.byType(ExpenseTile),
                      ),
                    )
                    .center
                    .dy,
                12,
              ),
            );
          }
          expect(_scaleOf(tester, small), closeTo(1, 0.01));
          expect(inRow(find.text(r'-$1,234.56')), findsOneWidget);

          // Metadata is never cut: category and date both fully shown.
          for (final meta in [
            'Groceries - Oct 3, 2026',
            'Transport - Oct 3, 2026',
            'Food - Oct 1, 2026',
          ]) {
            final paragraph = tester.renderObject<RenderParagraph>(
              inRow(find.text(meta)),
            );
            expect(paragraph.didExceedMaxLines, isFalse, reason: meta);
          }
        });
      }
    }
  });

  group('840 px and nearby', () {
    for (final width in <double>[839, 840, 900, 1024, 1199, 1200]) {
      testWidgets('${width.toInt()} px at 2x text with extreme data: no '
          'overflow, details readable', (tester) async {
        _size(tester, width, height: 1600);
        _textScale(tester, 2);
        await _pump(tester, [
          _e('big', Money.maxCents, _long, category: 'Groceries'),
          _e('neg', -500, 'Refund'),
        ]);
        await openExpense(tester, _long);
        expect(tester.takeException(), isNull);
        if (width >= 840) {
          final detail = find.byType(ExpenseDetailView);
          expect(
            find.descendant(
              of: detail,
              matching: find.text(r'$90,071,992,547,409.91'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(of: detail, matching: find.text(_long)),
            findsOneWidget,
          );
        } else {
          expect(find.text('Expense'), findsOneWidget);
        }
      });
    }
  });

  group('dialogs and pages at 320 px', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('delete dialog at ${scale}x scrolls instead of overflowing', (
        tester,
      ) async {
        _size(tester, 320, height: 640);
        _textScale(tester, scale);
        await _pump(tester, [_e('big', Money.maxCents, _long)]);
        await openExpense(tester, _long);
        await tester.ensureVisible(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Delete this expense?'), findsOneWidget);
        expect(find.text('Delete expense'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
      });

      testWidgets('edit form at ${scale}x has no overflow', (tester) async {
        _size(tester, 320, height: 640);
        _textScale(tester, scale);
        await _pump(tester, [_e('big', Money.maxCents, _long)]);
        await openExpense(tester, _long);
        await tester.ensureVisible(find.text('Edit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('EDITING EXPENSE'), findsOneWidget);
      });
    }
  });

  testWidgets('the empty list message sits under the activity header', (
    tester,
  ) async {
    _size(tester, 1200, height: 1400);
    await _pump(tester, const []);
    final header = tester.getRect(find.text('02 / YOUR ACTIVITY'));
    final empty = tester.getRect(find.text('No expenses'));
    expect(empty.top - header.bottom, lessThan(200));
  });

  testWidgets('the delete dialog shows the full description', (tester) async {
    _size(tester, 320, height: 640);
    await _pump(tester, [_e('big', 100, _long)]);
    await openExpense(tester, _long);
    await tester.ensureVisible(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    final inDialog = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(_long),
    );
    expect(inDialog, findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(inDialog).didExceedMaxLines,
      isFalse,
    );
    expect(tester.widget<Text>(inDialog).maxLines, isNull);
  });

  group('empty-selection reasons (workspace)', () {
    testWidgets('no expenses / none selected / deleted / disappeared', (
      tester,
    ) async {
      _size(tester, 1200);
      final storage = await _pump(tester, const []);
      expect(find.text('Nothing to show yet'), findsOneWidget);

      storage.data = encodeExpenses([_e('a', 100, 'Tea'), _e('b', 200, 'Bus')]);
      tester
          .element(find.byType(MonthlyHero))
          .read<ExpenseProvider>()
          .markExternalChange();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reload'));
      await tester.pumpAndSettle();
      expect(find.text('No expense selected'), findsOneWidget);

      await deleteExpenseViaUi(tester, 'Tea');
      expect(find.text('Expense deleted'), findsOneWidget);

      await openExpense(tester, 'Bus');
      storage.data = encodeExpenses(const []);
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
    });
  });
}
