import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/widgets/expense_list.dart';

/// [finder] inside an expense row (not the monthly summary or details).
Finder inRow(Finder finder) =>
    find.descendant(of: find.byType(ExpenseTile), matching: finder);

/// Selects the row showing [description]: opens the detail page at compact
/// and medium widths, or fills the detail panel in the workspace layout.
Future<void> openExpense(WidgetTester tester, String description) async {
  await tester.tap(inRow(find.text(description)));
  await tester.pumpAndSettle();
}

/// Opens [description] and its edit form.
Future<void> openEditForm(WidgetTester tester, String description) async {
  await openExpense(tester, description);
  await tester.tap(find.text('Edit'));
  await tester.pumpAndSettle();
}

/// Opens [description], presses Delete and confirms the dialog. At compact
/// widths a successful delete returns to the list; a refused one stays on
/// the detail page.
Future<void> deleteExpenseViaUi(WidgetTester tester, String description) async {
  await openExpense(tester, description);
  await tester.tap(find.text('Delete'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete expense'));
  await tester.pumpAndSettle();
}
