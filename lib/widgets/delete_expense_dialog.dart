import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../presentation/app_theme.dart';
import '../presentation/formatting.dart';
import '../providers/expense_provider.dart';
import '../repositories/expense_repository.dart';

/// Asks before deleting [expense]; `true` means delete.
class DeleteExpenseDialog extends StatelessWidget {
  const DeleteExpenseDialog({super.key, required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      // Names the dialog for screen readers (otherwise "Alert").
      semanticLabel: 'Delete expense',
      // Scrolls on short screens and with large text.
      scrollable: true,
      icon: Icon(Icons.delete_outline, color: scheme.error),
      title: const Text('Delete this expense?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            expense.description,
            // Shown in full; the dialog scrolls.
            style: text.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${formatMoney(expense.amount)} · ${expense.category} · '
            '${formatLongDate(expense.date)}',
            style: amountStyle(text.bodyMedium),
          ),
          const SizedBox(height: AppSpacing.l),
          const Text(
            'It is removed from this browser permanently. This cannot be '
            'undone, except by importing a backup that contains it.',
          ),
        ],
      ),
      actions: [
        TextButton(
          // Keyboard focus starts on the safe choice: Enter or Space right
          // after opening cancels. Escape also cancels.
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete expense'),
        ),
      ],
    );
  }
}

/// Asks for confirmation, then deletes [expense] only if the stored record
/// is still exactly that ([ExpenseProvider.deleteExpectedExpense]).
///
/// Returns `true` if it was deleted. Every refusal is explained in a snack
/// bar; conflicts and missing records also pause edits (*Reload* notice).
Future<bool> confirmAndDeleteExpense(
  BuildContext context,
  Expense expense,
) async {
  final provider = context.read<ExpenseProvider>();
  final messenger = ScaffoldMessenger.of(context);
  if (!provider.isReady) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => DeleteExpenseDialog(expense: expense),
  );
  if (confirmed != true) return false;

  void tell(String message) =>
      messenger.showSnackBar(SnackBar(content: Text(message)));
  try {
    await provider.deleteExpectedExpense(expense);
    tell('Expense deleted.');
    return true;
  } on ExpenseConflictException {
    tell('Expenses were changed in another tab. Reload to continue.');
  } on ExpenseNotFoundException {
    tell(
      'This expense was already deleted, for example in another tab. '
      'Reload to continue.',
    );
  } on DuplicateExpenseIdException {
    tell(
      'This expense shares its ID with another one and cannot be deleted '
      'safely.',
    );
  } catch (_) {
    tell('Could not delete expense. Try again.');
  }
  return false;
}
