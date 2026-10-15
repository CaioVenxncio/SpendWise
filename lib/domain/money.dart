/// Exact monetary amounts in integer minor units (cents).
///
/// Pure Dart: no Flutter dependency.
library;

/// Thrown when a [Money] operation would leave the supported range.
class MoneyOverflowException implements Exception {
  MoneyOverflowException(this.message);

  final String message;

  @override
  String toString() => 'MoneyOverflowException: $message';
}

/// An exact amount of money stored as an integer number of cents.
///
/// All values lie within [minCents]..[maxCents]. The bounds are the largest
/// integers that JavaScript numbers represent exactly, so arithmetic gives
/// identical results on the Dart VM and on Flutter Web. Operations that would
/// leave the range throw [MoneyOverflowException] instead of losing precision.
///
/// Amounts are never converted to or from `double`.
class Money implements Comparable<Money> {
  const Money._(this.cents);

  /// Creates an amount from [cents]. Throws [RangeError] if out of range.
  factory Money.fromCents(int cents) {
    RangeError.checkValueInInterval(cents, minCents, maxCents, 'cents');
    return Money._(cents);
  }

  /// 2^53 - 1, the largest integer exactly representable in JavaScript.
  static const int maxCents = 9007199254740991;

  static const int minCents = -maxCents;

  static const Money zero = Money._(0);

  /// Largest whole-unit part whose cents value stays within [maxCents]
  /// (`maxCents ~/ 100`, written out so no division happens on the web).
  static const int _maxWholeUnits = 90071992547409;

  static final _decimalPattern = RegExp(r'^(\d+)(?:[.,](\d{1,2}))?$');

  /// The amount in cents.
  final int cents;

  /// Parses a non-negative decimal amount typed by a user, such as `12`,
  /// `12.5`, `12.50` or `12,50`, directly into cents.
  ///
  /// Accepts ASCII digits with an optional `.` or `,` decimal separator
  /// followed by one or two digits. Leading and trailing whitespace is
  /// ignored. Returns `null` for anything else, including signs, exponents,
  /// thousands separators, `NaN`, `Infinity`, more than two decimals, and
  /// values above [maxCents].
  static Money? tryParse(String input) {
    final match = _decimalPattern.firstMatch(input.trim());
    if (match == null) return null;
    return _fromParts(match.group(1)!, match.group(2), negative: false);
  }

  /// Like [tryParse], but throws a [FormatException] for invalid input.
  static Money parse(String input) =>
      tryParse(input) ??
      (throw FormatException('Invalid monetary amount', input));

  /// Builds an amount from decimal digit strings without using `double`.
  /// Returns `null` if the value is out of range.
  static Money? _fromParts(
    String wholeDigits,
    String? fractionDigits, {
    required bool negative,
  }) {
    // Longer strings cannot be in range; checking first keeps int.parse safe.
    final significant = wholeDigits.replaceFirst(RegExp('^0+(?=.)'), '');
    if (significant.length > _maxWholeUnits.toString().length) return null;
    final whole = int.parse(significant);
    if (whole > _maxWholeUnits) return null;
    final fraction = int.parse((fractionDigits ?? '').padRight(2, '0'));
    final cents = whole * 100 + fraction;
    if (cents > maxCents) return null;
    return Money._(negative && cents != 0 ? -cents : cents);
  }

  /// The exact sum of [amounts]; zero for none.
  ///
  /// Accumulates in [BigInt], so partial sums may leave the range: only the
  /// final total is checked, and the result does not depend on the order
  /// of [amounts]. Throws [MoneyOverflowException] if the exact total is
  /// outside [minCents]..[maxCents] (never clamped or rounded).
  static Money sum(Iterable<Money> amounts) {
    var total = BigInt.zero;
    for (final amount in amounts) {
      total += BigInt.from(amount.cents);
    }
    if (total > BigInt.from(maxCents) || total < BigInt.from(minCents)) {
      throw MoneyOverflowException('sum of $total cents is out of range');
    }
    return Money.fromCents(total.toInt());
  }

  bool get isZero => cents == 0;

  bool get isNegative => cents < 0;

  bool get isPositive => cents > 0;

  Money operator +(Money other) {
    final b = other.cents;
    // Compare before adding so the intermediate result never leaves the
    // exactly representable range on the web.
    if ((b > 0 && cents > maxCents - b) || (b < 0 && cents < minCents - b)) {
      throw MoneyOverflowException('$this + $other is out of range');
    }
    return Money._(cents + b);
  }

  /// Ranges are symmetric, so negation never overflows.
  /// Zero is returned as is: negating it on the web would produce `-0`.
  Money operator -() => cents == 0 ? this : Money._(-cents);

  Money operator -(Money other) => this + (-other);

  bool operator <(Money other) => cents < other.cents;

  bool operator <=(Money other) => cents <= other.cents;

  bool operator >(Money other) => cents > other.cents;

  bool operator >=(Money other) => cents >= other.cents;

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  /// Formats as a plain decimal with exactly two fraction digits, e.g.
  /// `12.50`, `0.05` or `-3.00`.
  String toDecimalString() {
    final absolute = cents.abs();
    final fraction = absolute % 100;
    // Subtract first so the division is exact on the web as well.
    final whole = (absolute - fraction) ~/ 100;
    final sign = cents < 0 ? '-' : '';
    return '$sign$whole.${fraction.toString().padLeft(2, '0')}';
  }

  @override
  String toString() => 'Money(${toDecimalString()})';
}

/// Converts a legacy floating-point amount (as stored before integer cents)
/// into [Money] without rounding.
///
/// Uses the shortest decimal representation of [value], which is the text
/// that was originally written to storage. Accepts it only if it is a plain
/// decimal with at most two fraction digits that fits in range. Throws a
/// [FormatException] for non-finite, out-of-range, exponent-notation, or
/// more precise values, rather than guessing.
Money moneyFromLegacyAmount(num value) {
  if (value is double && !value.isFinite) {
    throw FormatException('Legacy amount is not finite', value);
  }
  final match = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$')
      .firstMatch(value.toString());
  if (match == null) {
    throw FormatException(
      'Legacy amount has more than two decimal places or is out of range',
      value,
    );
  }
  final money = Money._fromParts(
    match.group(2)!,
    // VM doubles print a trailing ".0"; it carries no precision.
    match.group(3),
    negative: match.group(1) == '-',
  );
  if (money == null) {
    throw FormatException('Legacy amount is out of range', value);
  }
  return money;
}
