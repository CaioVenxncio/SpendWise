import 'package:flutter/material.dart';

import '../models/expense.dart';
import '../presentation/app_theme.dart';
import '../presentation/formatting.dart';
import '../presentation/keyboard_focus.dart';
import 'brand.dart';
import 'expense_list.dart';

/// Details of one expense with its Edit and Delete actions.
///
/// Shows the record exactly as currently loaded; the caller passes the
/// same object to the guarded update/delete, so a record changed
/// elsewhere is detected instead of overwritten.
class ExpenseDetailView extends StatefulWidget {
  const ExpenseDetailView({
    super.key,
    required this.expense,
    required this.onEdit,
    required this.onDelete,
    this.showLabel = true,
  });

  final Expense expense;

  /// `null` disables editing (paused edits).
  final VoidCallback? onEdit;

  /// Runs the confirmed, guarded delete and returns whether the expense
  /// was deleted; `null` disables it.
  final Future<bool> Function()? onDelete;

  /// Whether to show the "SELECTED EXPENSE" marker (desktop panel).
  final bool showLabel;

  @override
  State<ExpenseDetailView> createState() => _ExpenseDetailViewState();
}

class _ExpenseDetailViewState extends State<ExpenseDetailView> {
  bool _deleting = false;
  final _deleteFocus = FocusNode(debugLabel: 'Delete');

  @override
  void dispose() {
    _deleteFocus.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    var deleted = false;
    try {
      deleted = await widget.onDelete!();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
    // Cancelled or refused: focus returns to Delete (re-enabled by the
    // rebuild above), if it can still take it. After a delete the page
    // decides where focus goes.
    if (!deleted && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _deleteFocus.canRequestFocus) {
          _deleteFocus.requestFocus();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    final colors = SpendWiseColors.of(context);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ring = KeyboardFocusScope.isActive(context);

    Widget fact(String label, String value, IconData icon) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.foregroundMuted),
          const SizedBox(width: AppSpacing.m),
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: colors.foregroundMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: text.bodyLarge?.copyWith(color: colors.foreground),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showLabel) ...[
          const SectionLabel('Selected expense'),
          const SizedBox(height: AppSpacing.m),
        ],
        Semantics(
          header: true,
          child: Text(
            e.description,
            style: text.headlineSmall?.copyWith(color: colors.foreground),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        ExactAmount(
          formatMoney(e.amount),
          styles: [
            text.displaySmall?.copyWith(color: colors.foreground),
            text.headlineMedium?.copyWith(color: colors.foreground),
            text.headlineSmall?.copyWith(color: colors.foreground),
          ],
        ),
        const SizedBox(height: AppSpacing.l),
        Divider(color: colors.divider),
        fact('Category', e.category, categoryIcon(e.category)),
        fact('Date', formatLongDate(e.date), Icons.event_outlined),
        Divider(color: colors.divider),
        const SizedBox(height: AppSpacing.l),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.s,
          children: [
            FilledButton.icon(
              onPressed: widget.onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
            OutlinedButton.icon(
              focusNode: _deleteFocus,
              onPressed: widget.onDelete == null || _deleting ? null : _delete,
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error)
                  .copyWith(
                    // Disabled looks disabled (no error-coloured border).
                    // This replaces the theme's side, so it draws the
                    // keyboard focus ring itself.
                    side: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.focused) && ring
                          ? AppTheme.focusRing(colors)
                          : BorderSide(
                              color: states.contains(WidgetState.disabled)
                                  ? scheme.onSurface.withValues(alpha: 0.12)
                                  : scheme.error.withValues(alpha: 0.6),
                            ),
                    ),
                  ),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Why the detail panel has no expense to show.
enum EmptySelectionReason {
  /// There are no expenses at all.
  noExpenses,

  /// Expenses exist; none is selected yet.
  noneSelected,

  /// The selected expense was just deleted here.
  deleted,

  /// The selected expense is no longer stored (e.g. deleted in another tab
  /// and reloaded). Another record is never shown in its place.
  missing,
}

/// Shown in the detail panel (or detail page) when there is no expense to
/// show; the text says why.
class EmptySelection extends StatelessWidget {
  const EmptySelection({
    super.key,
    this.reason = EmptySelectionReason.noneSelected,
    this.onClear,
    this.clearLabel = 'Clear selection',
  });

  final EmptySelectionReason reason;

  /// Offered for [EmptySelectionReason.missing].
  final VoidCallback? onClear;

  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    final colors = SpendWiseColors.of(context);
    final text = Theme.of(context).textTheme;
    final (icon, title, body) = switch (reason) {
      EmptySelectionReason.noExpenses => (
        Icons.receipt_long_outlined,
        'Nothing to show yet',
        'Your expenses will appear here once you add one.',
      ),
      EmptySelectionReason.noneSelected => (
        Icons.touch_app_outlined,
        'No expense selected',
        'Select an expense in the list to see its details, edit or delete '
            'it.',
      ),
      EmptySelectionReason.deleted => (
        Icons.check_circle_outline,
        'Expense deleted',
        'Select another expense to see its details.',
      ),
      EmptySelectionReason.missing => (
        Icons.help_outline,
        'The selected expense is no longer in your list.',
        'It may have been deleted, for example in another tab.',
      ),
    };
    final announce =
        reason == EmptySelectionReason.missing ||
        reason == EmptySelectionReason.deleted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionLabel('Selected expense'),
        const SizedBox(height: AppSpacing.l),
        Icon(icon, color: colors.foregroundMuted),
        const SizedBox(height: AppSpacing.s),
        Semantics(
          liveRegion: announce,
          child: Text(
            title,
            style: text.titleMedium?.copyWith(color: colors.foreground),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          body,
          style: text.bodyMedium?.copyWith(color: colors.foregroundSecondary),
        ),
        if (reason == EmptySelectionReason.missing && onClear != null) ...[
          const SizedBox(height: AppSpacing.m),
          TextButton(onPressed: onClear, child: Text(clearLabel)),
        ],
      ],
    );
  }
}
