// M3.6 Stage 1: accessibility semantics of the primary workflows.
//
// These check the Flutter semantics tree, which Flutter Web turns into the
// browser's accessibility DOM once accessibility is enabled. They are not a
// screen-reader test. `testWidgets` builds the semantics tree by default;
// tests of the accessibility-off behaviour pass `semanticsEnabled: false`.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/pages/expense_detail_page.dart';
import 'package:spendwise/pages/expense_form_page.dart';
import 'package:spendwise/providers/expense_provider.dart';
import 'package:spendwise/services/expense_storage.dart';
import 'package:spendwise/widgets/brand.dart';
import 'package:spendwise/widgets/expense_detail.dart';
import 'package:spendwise/widgets/expense_list.dart';

import '../support/fake_expense_storage.dart';

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

final _seed = [
  _e('a', 1250, 'Lunch', date: '2026-10-03T12:30:00.000'),
  _e(
    'b',
    -500,
    'Refund',
    category: 'Transport',
    date: '2026-10-09T08:00:00.000',
  ),
  _e('c', Money.maxCents, 'Huge', category: 'Groceries'),
];

const _lunch = r'Lunch, $12.50, Food - Oct 3, 2026';
const _refund = r'Refund, -$5.00, Transport - Oct 9, 2026';
const _huge = r'Huge, $90,071,992,547,409.91, Groceries - Oct 3, 2026';

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
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

Finder _row(String description) => find.ancestor(
  of: find.text(description),
  matching: find.byType(ExpenseTile),
);

SemanticsNode _rowNode(WidgetTester tester, String description) =>
    tester.getSemantics(_row(description));

/// Activates [description]'s row the way assistive technology does: the
/// semantics tap action, not a pointer.
Future<void> _semanticTap(WidgetTester tester, String description) async {
  final node = _rowNode(tester, description);
  node.owner!.performAction(node.id, SemanticsAction.tap);
  await tester.pumpAndSettle();
}

List<SemanticsNode> _allNodes(WidgetTester tester) {
  final root = tester
      .binding
      .renderViews
      .single
      .owner!
      .semanticsOwner!
      .rootSemanticsNode!;
  final out = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    out.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return out;
}

Tristate _selectedOf(WidgetTester tester, String description) =>
    _rowNode(tester, description).getSemanticsData().flagsCollection.isSelected;

Widget? _focusedAncestor<T extends Widget>() => FocusManager
    .instance
    .primaryFocus
    ?.context
    ?.findAncestorWidgetOfExactType<T>();

void main() {
  group('A11Y-01 expense rows', () {
    for (final width in [360.0, 1200.0]) {
      testWidgets('${width.toInt()} px: one actionable, focusable node per '
          'row with the full label', (tester) async {
        _size(tester, width);
        await _pump(tester);

        for (final (description, label) in [
          ('Lunch', _lunch),
          ('Refund', _refund),
          ('Huge', _huge),
        ]) {
          expect(
            _rowNode(tester, description),
            isSemantics(
              label: label,
              isButton: true,
              hasTapAction: true,
              isFocusable: true,
            ),
            reason: description,
          );
          expect(
            _rowNode(tester, description).hintOverrides?.onTapHint,
            'show details',
          );
          // The row's own texts are not separate nodes (read once).
          expect(_rowNode(tester, description).childrenCount, 0);
        }
        // Each label appears exactly once in the tree.
        final labels = [for (final n in _allNodes(tester)) n.label];
        for (final label in [_lunch, _refund, _huge]) {
          expect(labels.where((l) => l.contains('Lunch, ')).length, 1);
          expect(labels.where((l) => l == label).length, 1, reason: label);
        }
      });
    }

    testWidgets('workspace: the semantics tap selects the right expense; '
        'nothing is written', (tester) async {
      _size(tester, 1200);
      final storage = await _pump(tester);

      await _semanticTap(tester, 'Refund');

      final detail = find.byType(ExpenseDetailView);
      expect(
        find.descendant(of: detail, matching: find.text('Refund')),
        findsOneWidget,
      );
      expect(_selectedOf(tester, 'Refund'), Tristate.isTrue);
      expect(_selectedOf(tester, 'Lunch'), Tristate.isFalse);
      expect(_selectedOf(tester, 'Huge'), Tristate.isFalse);
      // Still the home page; Edit and Delete are there.
      expect(find.byType(ExpenseDetailPage), findsNothing);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(storage.writeCount, 0);
    });

    testWidgets('compact: the semantics tap opens the details page; rows '
        'report no selected state', (tester) async {
      _size(tester, 360);
      final storage = await _pump(tester);

      for (final d in ['Lunch', 'Refund', 'Huge']) {
        expect(_selectedOf(tester, d), Tristate.none, reason: d);
      }
      await _semanticTap(tester, 'Lunch');

      expect(find.byType(ExpenseDetailPage), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      // Back on the list: still no selected state announced.
      expect(_selectedOf(tester, 'Lunch'), Tristate.none);
      expect(storage.writeCount, 0);
    });

    testWidgets('a row that cannot be opened is not a button', (tester) async {
      _size(tester, 1200);
      await _pump(
        tester,
        seed: [_e('d', 100, 'Twin A'), _e('d', 200, 'Twin B')],
      );
      final node = _rowNode(tester, 'Twin A');
      expect(
        node,
        isSemantics(
          isButton: false,
          hasTapAction: false,
          isFocusable: false,
          hasSelectedState: true,
          isSelected: false,
        ),
      );
      expect(node.label, endsWith(', shares its ID with another expense'));
    });

    for (final semantics in [true, false]) {
      testWidgets(
        'keyboard (accessibility ${semantics ? 'on' : 'off'}): '
        'Tab reaches a row, Enter selects it, then Edit and Delete',
        semanticsEnabled: semantics,
        (tester) async {
          _size(tester, 1200);
          final storage = await _pump(tester);

          Future<void> tabUntil(bool Function() reached) async {
            for (var i = 0; i < 20 && !reached(); i++) {
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await tester.pumpAndSettle();
            }
            expect(reached(), isTrue);
          }

          await tabUntil(
            () =>
                (_focusedAncestor<ExpenseTile>() as ExpenseTile?)
                    ?.expense
                    .description ==
                'Lunch',
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(tester.widget<ExpenseTile>(_row('Lunch')).selected, isTrue);
          if (semantics) expect(_selectedOf(tester, 'Lunch'), Tristate.isTrue);

          await tabUntil(() => _focusedAncestor<FilledButton>() != null);
          await tabUntil(() => _focusedAncestor<OutlinedButton>() != null);
          expect(storage.writeCount, 0);
        },
      );
    }
  });

  group('A11Y-04 selected state', () {
    testWidgets('follows the selection, an edit and a delete', (tester) async {
      _size(tester, 1200);
      final storage = await _pump(tester);

      for (final d in ['Lunch', 'Refund', 'Huge']) {
        expect(_selectedOf(tester, d), Tristate.isFalse, reason: d);
      }
      await _semanticTap(tester, 'Lunch');
      expect(_selectedOf(tester, 'Lunch'), Tristate.isTrue);
      await _semanticTap(tester, 'Refund');
      expect(_selectedOf(tester, 'Lunch'), Tristate.isFalse);
      expect(_selectedOf(tester, 'Refund'), Tristate.isTrue);

      // Edit: still selected, under its new description.
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Refund 2',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();
      expect(storage.writeCount, 1);
      expect(_selectedOf(tester, 'Refund 2'), Tristate.isTrue);
      expect(_selectedOf(tester, 'Lunch'), Tristate.isFalse);

      // Delete: no row stays selected.
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete expense'));
      await tester.pumpAndSettle();
      expect(find.text('Refund 2'), findsNothing);
      for (final d in ['Lunch', 'Huge']) {
        expect(_selectedOf(tester, d), Tristate.isFalse, reason: d);
      }
    });

    testWidgets('a reload that removes the selected expense leaves no row '
        'selected', (tester) async {
      _size(tester, 1200);
      final storage = await _pump(tester);
      await _semanticTap(tester, 'Lunch');

      // Same data reloaded: still the same expense, by ID.
      final provider = Provider.of<ExpenseProvider>(
        tester.element(find.byType(ExpenseTile).first),
        listen: false,
      );
      await provider.reload();
      await tester.pumpAndSettle();
      expect(_selectedOf(tester, 'Lunch'), Tristate.isTrue);

      // Removed elsewhere, then reloaded.
      storage.data = encodeExpenses([_seed[1], _seed[2]]);
      await provider.reload();
      await tester.pumpAndSettle();
      for (final d in ['Refund', 'Huge']) {
        expect(_selectedOf(tester, d), Tristate.isFalse, reason: d);
      }
      expect(
        find.text('The selected expense is no longer in your list.'),
        findsOneWidget,
      );
    });
  });

  group('A11Y-03 / A11Y-06 names and headings', () {
    for (final width in [360.0, 1200.0]) {
      testWidgets('${width.toInt()} px: Add expense has one name', (
        tester,
      ) async {
        _size(tester, width);
        await _pump(tester);
        final named = [
          for (final n in _allNodes(tester))
            if (n.label.contains('Add expense') ||
                n.tooltip.contains('Add expense'))
              n,
        ];
        expect(named, hasLength(1));
        final data = named.single.getSemanticsData();
        // Either the label or the tooltip names it, never both.
        expect([data.label, data.tooltip].where((s) => s.isNotEmpty), [
          'Add expense',
        ]);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        // The pointer tooltip is kept.
        expect(find.byTooltip('Add expense'), findsOneWidget);
      });

      testWidgets('${width.toInt()} px: one top-level heading; section '
          'markers read without numbering', (tester) async {
        _size(tester, width);
        await _pump(tester);
        final headings = {
          for (final n in _allNodes(tester))
            if (n.getSemanticsData().flagsCollection.isHeader)
              n.label: n.getSemanticsData().headingLevel,
        };
        expect(headings['SpendWise'], 1);
        expect(headings['Expenses, 3'], 2);
        expect(headings.values.where((l) => l == 1), hasLength(1));

        final labels = _allNodes(tester).map((n) => n.label).join('\n');
        expect(labels, isNot(contains('02 /')));
        expect(labels, isNot(contains('01 /')));
        expect(labels, isNot(contains('YOUR ACTIVITY')));
        expect(labels, isNot(contains('Expenses  ')));
        expect(labels, contains('Your activity'));
        // The visible markers are unchanged.
        expect(find.text('02 / YOUR ACTIVITY'), findsOneWidget);
      });
    }

    test('section marker spoken text', () {
      expect(SectionLabel.spokenText('02 / Your activity'), 'Your activity');
      expect(
        SectionLabel.spokenText('01 / Monthly overview'),
        'Monthly overview',
      );
      expect(SectionLabel.spokenText('Selected expense'), 'Selected expense');
    });

    testWidgets('the delete and discard dialogs are named by their purpose', (
      tester,
    ) async {
      _size(tester, 1200);
      final storage = await _pump(tester);

      bool named(String label) => _allNodes(tester).any(
        (n) =>
            n.label == label && n.getSemanticsData().flagsCollection.namesRoute,
      );

      await _semanticTap(tester, 'Lunch');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(named('Delete expense'), isTrue);
      expect(_allNodes(tester).any((n) => n.label == 'Alert'), isFalse);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Changed',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(named('Discard changes'), isTrue);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseFormPage), findsOneWidget);
      expect(storage.writeCount, 0);
    });
  });

  group('A11Y-05 validation', () {
    Finder field(String label) => find.descendant(
      of: find.widgetWithText(TextFormField, label),
      matching: find.byType(EditableText),
    );
    bool focused(WidgetTester tester, String label) =>
        tester.widget<EditableText>(field(label)).focusNode.hasPrimaryFocus;

    testWidgets('a failed submit focuses the first invalid field, which '
        'carries its message; nothing is written', (tester) async {
      _size(tester, 1200);
      final storage = await _pump(tester);
      await tester.tap(find.text('Add expense'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Add Expense'));
      await tester.pumpAndSettle();
      expect(focused(tester, 'Amount'), isTrue);
      expect(tester.getSemantics(field('Amount')).hint, 'Enter amount');
      expect(
        tester.getSemantics(field('Description')).hint,
        'Enter description',
      );
      // Each message is shown once.
      expect(find.text('Enter amount'), findsOneWidget);
      expect(find.text('Enter description'), findsOneWidget);

      await tester.enterText(field('Amount'), '12.345');
      await tester.tap(find.widgetWithText(FilledButton, 'Add Expense'));
      await tester.pumpAndSettle();
      expect(focused(tester, 'Amount'), isTrue);
      expect(
        tester.getSemantics(field('Amount')).hint,
        'Enter a number with up to 2 decimals, e.g. 12.50',
      );

      await tester.enterText(field('Amount'), '12.34');
      await tester.tap(find.widgetWithText(FilledButton, 'Add Expense'));
      await tester.pumpAndSettle();
      expect(focused(tester, 'Description'), isTrue);
      expect(focused(tester, 'Amount'), isFalse);
      expect(tester.getSemantics(field('Amount')).hint, isEmpty);

      expect(storage.writeCount, 0);
      expect(find.byType(ExpenseFormPage), findsOneWidget);
    });

    testWidgets('a valid submit is unchanged', (tester) async {
      _size(tester, 360);
      final storage = await _pump(tester, seed: []);
      await tester.tap(find.byTooltip('Add expense'));
      await tester.pumpAndSettle();
      await tester.enterText(field('Amount'), '7.50');
      await tester.enterText(field('Description'), 'Coffee');
      await tester.tap(find.widgetWithText(FilledButton, 'Add Expense'));
      await tester.pumpAndSettle();
      expect(find.byType(ExpenseFormPage), findsNothing);
      expect(storage.writeCount, 1);
      expect(storage.data, contains('"amountCents":750'));
    });
  });

  group('A11Y-02 on-demand accessibility', () {
    testWidgets(
      'the app does not turn accessibility on by itself',
      semanticsEnabled: false,
      (tester) async {
        for (final width in [360.0, 1200.0]) {
          _size(tester, width);
          await _pump(tester);
          expect(SemanticsBinding.instance.semanticsEnabled, isFalse);
          expect(tester.binding.rootPipelineOwner.semanticsOwner, isNull);
          // Pointer selection works as before.
          await tester.tap(find.text('Lunch'));
          await tester.pumpAndSettle();
          expect(SemanticsBinding.instance.semanticsEnabled, isFalse);
        }
      },
    );
  });
}
