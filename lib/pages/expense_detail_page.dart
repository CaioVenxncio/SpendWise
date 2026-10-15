import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../presentation/app_theme.dart';
import '../providers/expense_provider.dart';
import '../widgets/delete_expense_dialog.dart';
import '../widgets/expense_detail.dart';
import '../widgets/notice_banner.dart';
import 'expense_form_page.dart';

/// Full-screen details of one expense (compact and medium widths).
///
/// Looks the expense up by [expenseId] on every build, so it always shows
/// the record as currently loaded and never a stale copy. Pops with `true`
/// after the expense was deleted here.
class ExpenseDetailPage extends StatelessWidget {
  const ExpenseDetailPage({super.key, required this.expenseId});

  final String expenseId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    final matches = provider.expenses.where((e) => e.id == expenseId);
    final expense = matches.length == 1 ? matches.single : null;
    final editable =
        provider.isReady && !provider.duplicateIds.contains(expenseId);

    return Scaffold(
      appBar: AppBar(title: const Text('Expense')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: appFormMaxWidth),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.l),
              children: [
                if (provider.hasConflict) ...[
                  NoticeBanner(
                    level: NoticeLevel.warning,
                    text:
                        'Your expenses were changed in another tab or window. '
                        'Changes here are paused so nothing is overwritten.',
                    actionLabel: 'Reload',
                    onAction: provider.reload,
                  ),
                  const SizedBox(height: AppSpacing.l),
                ],
                if (expense == null)
                  EmptySelection(
                    reason: EmptySelectionReason.missing,
                    onClear: () => Navigator.of(context).pop(),
                    clearLabel: 'Back to expenses',
                  )
                else
                  ExpenseDetailView(
                    expense: expense,
                    showLabel: false,
                    onEdit: editable
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ExpenseFormPage.edit(expense),
                            ),
                          )
                        : null,
                    onDelete: editable
                        ? () async {
                            final navigator = Navigator.of(context);
                            final deleted = await confirmAndDeleteExpense(
                              context,
                              expense,
                            );
                            if (deleted) navigator.pop(true);
                            return deleted;
                          }
                        : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
