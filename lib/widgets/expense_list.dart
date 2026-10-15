import 'package:flutter/material.dart';

import '../domain/money.dart';
import '../models/expense.dart';
import '../presentation/app_theme.dart';
import '../presentation/formatting.dart';
import '../presentation/keyboard_focus.dart';
import 'brand.dart';

/// Text shown for the monthly total; `null` when the exact sum is outside
/// the range [Money] can represent (see [monthTotalUnavailableNote]).
String monthTotalText(Money? total) =>
    total == null ? 'Total unavailable' : formatMoney(total);

/// Shown with an unavailable total. The arithmetic fails closed: no
/// approximate or clamped figure is ever displayed as a total.
const monthTotalUnavailableNote =
    "This month's expenses add up to more than SpendWise can total exactly, "
    'so no total is shown. Every expense is still shown exactly.';

/// The phrase screen readers hear for the monthly total.
String monthTotalSemantics(Money? total) => total == null
    ? 'Total this month unavailable. $monthTotalUnavailableNote'
    : 'Total this month: ${formatMoney(total)}';

/// Natural one-line width of [text] in [style] with the ambient text
/// scaling.
double _naturalWidth(BuildContext context, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: amountStyle(style)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// An amount with every digit visible: uses the first of [styles] that
/// fits the available width on one line; only if even the last one does
/// not fit is it scaled down (never cut off or ellipsized).
class ExactAmount extends StatelessWidget {
  const ExactAmount(
    this.text, {
    super.key,
    required this.styles,
    this.alignment = AlignmentDirectional.centerStart,
  });

  final String text;

  /// Largest first.
  final List<TextStyle?> styles;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      var style = styles.last;
      for (final candidate in styles) {
        if (_naturalWidth(context, text, candidate) <= constraints.maxWidth) {
          style = candidate;
          break;
        }
      }
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Text(
          text,
          style: amountStyle(style),
          maxLines: 1,
          softWrap: false,
        ),
      );
    },
  );
}

/// Desktop monthly hero: the one expressive, Electric Lime surface.
class MonthlyHero extends StatelessWidget {
  const MonthlyHero({super.key, required this.total, required this.now});

  /// `null` when the exact sum is outside the supported range.
  final Money? total;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final colors = SpendWiseColors.of(context);
    final text = Theme.of(context).textTheme;
    final ink = colors.onAccent;
    return Semantics(
      container: true,
      label: monthTotalSemantics(total),
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: colors.accent,
          borderRadius: BorderRadius.circular(AppRadii.large),
        ),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wraps onto two lines when narrow or with large text.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: AppSpacing.m,
              runSpacing: AppSpacing.xs,
              children: [
                SectionLabel(
                  '01 / Monthly overview',
                  color: ink.withValues(alpha: 0.72),
                ),
                Text(
                  formatMonthYear(now),
                  style: text.labelLarge?.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            ExactAmount(
              monthTotalText(total),
              styles: [
                text.displaySmall?.copyWith(color: ink),
                text.headlineMedium?.copyWith(color: ink),
                text.headlineSmall?.copyWith(color: ink),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Total spent this month',
              style: text.titleSmall?.copyWith(color: ink),
            ),
            if (total == null) ...[
              const SizedBox(height: AppSpacing.s),
              Text(
                monthTotalUnavailableNote,
                style: text.bodySmall?.copyWith(color: ink),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact (mobile/medium) summary: typographic, on the dark surface,
/// with lime concentrated in the [addButton].
class CompactMonthlySummary extends StatelessWidget {
  const CompactMonthlySummary({
    super.key,
    required this.total,
    required this.now,
    required this.addButton,
  });

  final Money? total;
  final DateTime now;
  final Widget addButton;

  @override
  Widget build(BuildContext context) {
    final colors = SpendWiseColors.of(context);
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Semantics(
            container: true,
            label: monthTotalSemantics(total),
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total spent · ${formatMonthYear(now)}',
                  style: text.labelLarge?.copyWith(
                    color: colors.foregroundSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                ExactAmount(
                  monthTotalText(total),
                  styles: [
                    text.headlineMedium?.copyWith(color: colors.foreground),
                    text.headlineSmall?.copyWith(color: colors.foreground),
                    text.titleLarge?.copyWith(color: colors.foreground),
                  ],
                ),
                if (total == null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    monthTotalUnavailableNote,
                    style: text.bodySmall?.copyWith(
                      color: colors.foregroundSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.l),
        addButton,
      ],
    );
  }
}

/// "02 / YOUR ACTIVITY" and the "Expenses" heading, with an optional
/// trailing action.
class ActivityHeader extends StatelessWidget {
  const ActivityHeader({super.key, this.trailing, this.count});

  final Widget? trailing;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = SpendWiseColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('02 / Your activity'),
              const SizedBox(height: AppSpacing.xs),
              // Read as "Expenses, 3": the visual gap is not spoken.
              Semantics(
                // Its own node, not merged with the marker above.
                container: true,
                header: true,
                headingLevel: 2,
                label: count == null ? 'Expenses' : 'Expenses, $count',
                excludeSemantics: true,
                child: Text.rich(
                  TextSpan(
                    text: 'Expenses',
                    children: [
                      if (count != null)
                        TextSpan(
                          text: '  $count',
                          style: text.titleMedium?.copyWith(
                            color: colors.foregroundMuted,
                          ),
                        ),
                    ],
                  ),
                  style: text.headlineSmall?.copyWith(color: colors.foreground),
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Icon shown for a category. Unknown categories (e.g. from an import) get
/// a neutral icon; the category name is always shown as text too.
IconData categoryIcon(String category) => switch (category) {
  'Food' => Icons.restaurant_outlined,
  'Transport' => Icons.directions_bus_outlined,
  'Entertainment' => Icons.movie_outlined,
  'General' => Icons.receipt_long_outlined,
  _ => Icons.label_outline,
};

/// One expense in the activity list: category icon, description,
/// "category - date" and the exact amount. Selecting it shows its details.
///
/// Selected: raised surface and accent bar on the left. Keyboard focus: a
/// ring in the focus colour all around (only while the keyboard is in use),
/// so the two states never look alike.
class ExpenseTile extends StatefulWidget {
  const ExpenseTile({
    super.key,
    required this.expense,
    required this.isDuplicate,
    required this.selected,
    required this.onSelect,
    this.selectable = true,
    this.focusNode,
  });

  final Expense expense;

  /// Whether another stored record shares this ID; such rows cannot be
  /// opened (edit and delete are refused for them).
  final bool isDuplicate;

  /// Whether this row is the selected expense (desktop detail panel).
  final bool selected;

  /// Whether the row reports a selected state to assistive technology.
  /// Only where selecting is what the row does (desktop panel); a row that
  /// opens a separate page has no selected state to report.
  final bool selectable;

  /// `null` when the row cannot be opened.
  final VoidCallback? onSelect;

  /// Lets the page move focus back to this row (after Back or a delete).
  final FocusNode? focusNode;

  @override
  State<ExpenseTile> createState() => _ExpenseTileState();
}

class _ExpenseTileState extends State<ExpenseTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final expense = widget.expense;
    final isDuplicate = widget.isDuplicate;
    final selected = widget.selected;
    final selectable = widget.selectable;
    final onSelect = widget.onSelect;
    final colors = SpendWiseColors.of(context);
    final text = Theme.of(context).textTheme;
    final ring = _focused && KeyboardFocusScope.isActive(context);
    final amount = formatMoney(expense.amount);
    final meta = '${expense.category} - ${formatShortDate(expense.date)}';

    // One node per row: this label, plus the tap action and focusability
    // of the InkWell below (they merge into it). Only the row's own text is
    // excluded, so its parts are not read twice.
    return Semantics(
      container: true,
      selected: selectable ? selected : null,
      button: onSelect != null,
      onTapHint: onSelect == null ? null : 'show details',
      label:
          '${expense.description}, $amount, $meta'
          '${isDuplicate ? ', shares its ID with another expense' : ''}',
      child: Material(
        color: selected ? colors.surfaceSelected : Colors.transparent,
        // Drawn inside the row: neighbouring rows and the list's edges
        // never cover it.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          side: ring
              ? BorderSide(color: colors.focus, width: 2)
              : BorderSide.none,
        ),
        child: InkWell(
          focusNode: widget.focusNode,
          onFocusChange: (focused) => setState(() => _focused = focused),
          onTap: onSelect,
          borderRadius: BorderRadius.circular(AppRadii.small),
          hoverColor: colors.surfaceHover,
          focusColor: colors.focus.withValues(alpha: 0.18),
          child: ExcludeSemantics(
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: selected
                        ? colors.accentForeground
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.m,
                vertical: AppSpacing.s,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final amountStyleBase = text.titleMedium?.copyWith(
                    color: colors.foreground,
                  );
                  // Room right of the icon (40) and its gap.
                  final content = constraints.maxWidth - 40 - AppSpacing.m;
                  // Ordinary amounts sit beside the description (which keeps
                  // at least ~112 px); a long one gets its own full-width line
                  // instead of being shrunk.
                  final inline =
                      _naturalWidth(context, amount, amountStyleBase) <=
                      content - 112;
                  final details = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        expense.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyLarge?.copyWith(
                          color: colors.foreground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Short, and never cut: wraps if needed so the date
                      // stays visible.
                      Text(
                        meta,
                        style: text.bodySmall?.copyWith(
                          color: colors.foregroundSecondary,
                        ),
                      ),
                    ],
                  );
                  final amountText = ExactAmount(
                    amount,
                    styles: [amountStyleBase],
                    alignment: AlignmentDirectional.centerEnd,
                  );
                  return Row(
                    crossAxisAlignment: inline
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: colors.surface,
                          border: Border.all(color: colors.divider),
                          borderRadius: BorderRadius.circular(AppRadii.small),
                        ),
                        child: Icon(
                          categoryIcon(expense.category),
                          size: 20,
                          color: selected
                              ? colors.accentForeground
                              : colors.foregroundSecondary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.m),
                      if (inline) ...[
                        Expanded(child: details),
                        const SizedBox(width: AppSpacing.m),
                        amountText,
                      ] else
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              details,
                              const SizedBox(height: AppSpacing.xs),
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: amountText,
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
