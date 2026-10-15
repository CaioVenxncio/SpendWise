import '../domain/calendar.dart';
import '../domain/money.dart';
import '../models/expense.dart';
import 'expense_validators.dart';

/// Categories offered for new expenses. Category management is M4.
const expenseCategories = ['General', 'Food', 'Transport', 'Entertainment'];

/// What the expense form shows, as entered.
class ExpenseFormValues {
  const ExpenseFormValues({
    required this.amountText,
    required this.description,
    required this.category,
    required this.date,
  });

  final String amountText;
  final String description;
  final String category;

  /// For a new expense the full date and time; when editing only its local
  /// calendar day is used.
  final DateTime date;
}

/// The starting point of the expense form and the rules for comparing the
/// user's input with it.
///
/// Editing rule: a field the user did not change keeps the stored value
/// exactly and is not re-validated, so a record that the form could not
/// create (imported negative, zero or very large amounts, long or empty
/// descriptions) can still have its other fields edited. A changed field
/// must pass the same validation as a new expense.
class ExpenseFormBaseline {
  /// A new expense dated [now].
  ExpenseFormBaseline.add(DateTime now)
    : original = null,
      amountText = '',
      description = '',
      category = expenseCategories.first,
      date = now;

  /// Editing [expense] as stored.
  ExpenseFormBaseline.edit(Expense expense)
    : original = expense,
      amountText = expense.amount.toDecimalString(),
      description = expense.description,
      category = expense.category,
      date = expense.date.toLocal();

  /// The record being edited; `null` when adding.
  final Expense? original;

  final String amountText;
  final String description;
  final String category;
  final DateTime date;

  bool get isEditing => original != null;

  /// Choices for the category field: the predefined ones, plus the
  /// record's own category if it is not one of them (e.g. imported), so it
  /// is shown and kept rather than replaced.
  List<String> get categories => [
    ...expenseCategories,
    if (!expenseCategories.contains(category)) category,
  ];

  /// Whether [text] denotes a different amount. Formatting-only changes
  /// (`12.5` for `12.50`, surrounding spaces) are not changes.
  bool amountChanged(String text) {
    final original = this.original;
    if (original == null) return text.trim().isNotEmpty;
    if (text.trim() == amountText) return false;
    return Money.tryParse(text) != original.amount;
  }

  /// Whether [text] is a different description, ignoring surrounding
  /// whitespace (which new descriptions never keep).
  bool descriptionChanged(String text) => text.trim() != description.trim();

  bool categoryChanged(String value) => value != category;

  /// Whether [value] falls on a different local calendar day.
  bool dayChanged(DateTime value) =>
      localCalendarDate(value) != localCalendarDate(date);

  /// Whether leaving the form would lose input.
  bool isDirty(ExpenseFormValues v) =>
      amountChanged(v.amountText) ||
      descriptionChanged(v.description) ||
      categoryChanged(v.category) ||
      dayChanged(v.date);

  String? validateAmountText(String? text) =>
      isEditing && !amountChanged(text ?? '') ? null : validateAmount(text);

  String? validateDescriptionText(String? text) =>
      isEditing && !descriptionChanged(text ?? '')
      ? null
      : validateDescription(text);

  /// The edited record: same ID; unchanged fields are taken from the
  /// original exactly, including its date text when the day is unchanged.
  /// Only valid input may be passed (see the validators above).
  Expense replacement(ExpenseFormValues v) {
    final original = this.original;
    if (original == null) throw StateError('Not editing an expense');
    return original.edited(
      amount: amountChanged(v.amountText)
          ? parseExpenseAmount(v.amountText)
          : null,
      description: descriptionChanged(v.description)
          ? v.description.trim()
          : null,
      category: categoryChanged(v.category) ? v.category : null,
      day: dayChanged(v.date) ? v.date : null,
    );
  }

  /// A new expense with [id] from valid input, as the add form always
  /// created it.
  Expense newExpense(String id, ExpenseFormValues v) => Expense(
    id: id,
    amount: parseExpenseAmount(v.amountText)!,
    description: v.description.trim(),
    category: v.category,
    date: v.date,
  );
}
