/// Display formatting for money and dates.
///
/// Deterministic and independent of the device locale. For display only:
/// nothing here is parsed back or stored.
library;

import '../domain/calendar.dart';
import '../domain/money.dart';

/// Currency symbol shown in front of amounts. Amounts carry no currency;
/// SpendWise has always shown them in dollars.
const currencySymbol = r'$';

/// [amount] with the currency symbol, thousands separated by `,` and
/// exactly two decimals: `$0.00`, `$1,234.56`, `-$1,234.56`.
///
/// Built from the exact cents ([Money.toDecimalString]); no floating point.
String formatMoney(Money amount) {
  final text = amount.toDecimalString();
  final negative = text.startsWith('-');
  final unsigned = negative ? text.substring(1) : text;
  final dot = unsigned.indexOf('.');
  final whole = unsigned.substring(0, dot);
  final fraction = unsigned.substring(dot);
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  return '${negative ? '-' : ''}$currencySymbol$grouped$fraction';
}

// Dates are shown in English (the product language). Every helper below
// formats the local calendar day of an instant (see [localCalendarDate]),
// the same day that monthly totals use. None of them is parsed back or
// stored: the record's `dateText` is never derived from these.

/// The local calendar date of [instant] as ISO `YYYY-MM-DD`, e.g.
/// `2026-10-15`. Machine-oriented; the UI uses [formatShortDate] and
/// [formatLongDate].
String formatExpenseDate(DateTime instant) {
  final day = localCalendarDate(instant);
  final year = day.year.abs().toString().padLeft(4, '0');
  return '${day.year < 0 ? '-' : ''}$year-${_two(day.month)}-${_two(day.day)}';
}

String _two(int n) => n.toString().padLeft(2, '0');

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Year as shown: four digits, with a sign before year 0 (as ISO).
String _year(int year) =>
    '${year < 0 ? '-' : ''}${year.abs().toString().padLeft(4, '0')}';

/// The local month of [instant], e.g. `October 2026` (monthly overview).
String formatMonthYear(DateTime instant) {
  final day = localCalendarDate(instant);
  return '${_months[day.month - 1]} ${_year(day.year)}';
}

/// Compact local date, e.g. `Oct 12, 2026` (expense rows). Month names are
/// abbreviated to three letters; no ordinal suffixes.
String formatShortDate(DateTime instant) {
  final day = localCalendarDate(instant);
  return '${_months[day.month - 1].substring(0, 3)} ${day.day}, '
      '${_year(day.year)}';
}

/// Full local date, e.g. `October 12, 2026` (details, form, dialogs).
String formatLongDate(DateTime instant) {
  final day = localCalendarDate(instant);
  return '${_months[day.month - 1]} ${day.day}, ${_year(day.year)}';
}
