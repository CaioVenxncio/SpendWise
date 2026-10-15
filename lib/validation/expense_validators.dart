import '../domain/money.dart';

/// Largest amount accepted for a single expense: 1,000,000,000.00.
final maxExpenseAmount = Money.fromCents(100000000000);

/// Longest description accepted for an expense.
const maxDescriptionLength = 200;

/// Parses a user-entered expense amount such as `12`, `12.5` or `12,50`.
///
/// Returns `null` unless the input is a valid decimal (see [Money.tryParse])
/// greater than zero and no larger than [maxExpenseAmount].
Money? parseExpenseAmount(String input) {
  final amount = Money.tryParse(input);
  if (amount == null || !amount.isPositive || amount > maxExpenseAmount) {
    return null;
  }
  return amount;
}

String? validateAmount(String? value) {
  if (value == null || value.trim().isEmpty) return 'Enter amount';
  final amount = Money.tryParse(value);
  if (amount == null) {
    return 'Enter a number with up to 2 decimals, e.g. 12.50';
  }
  if (!amount.isPositive || amount > maxExpenseAmount) {
    return 'Amount must be greater than 0 and at most 1,000,000,000';
  }
  return null;
}

String? validateDescription(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return 'Enter description';
  if (trimmed.length > maxDescriptionLength) {
    return 'Description must be at most $maxDescriptionLength characters';
  }
  return null;
}
