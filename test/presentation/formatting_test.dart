import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/calendar.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/presentation/formatting.dart';

import '../support/date_texts.dart';

void main() {
  group('formatMoney', () {
    for (final (cents, text) in [
      (0, r'$0.00'),
      (1, r'$0.01'),
      (-1, r'-$0.01'),
      (99, r'$0.99'),
      (100, r'$1.00'),
      (1250, r'$12.50'),
      (-500, r'-$5.00'),
      (99999, r'$999.99'),
      (100000, r'$1,000.00'),
      (123456, r'$1,234.56'),
      (-123456, r'-$1,234.56'),
      (99999999, r'$999,999.99'),
      (100000000, r'$1,000,000.00'),
      (123456789, r'$1,234,567.89'),
      (100000000000, r'$1,000,000,000.00'),
      (Money.maxCents, r'$90,071,992,547,409.91'),
      (Money.minCents, r'-$90,071,992,547,409.91'),
    ]) {
      test('$cents cents is $text', () {
        expect(formatMoney(Money.fromCents(cents)), text);
      });
    }

    test('groups every value exactly like its decimal string', () {
      // Digits and sign must be unchanged; only separators and symbol added.
      for (var cents = -2000000; cents <= 2000000; cents += 997) {
        final money = Money.fromCents(cents);
        final stripped = formatMoney(money)
            .replaceAll(',', '')
            .replaceFirst(currencySymbol, '');
        expect(stripped, money.toDecimalString());
      }
    });
  });

  group('formatExpenseDate', () {
    test('is the local calendar date as YYYY-MM-DD', () {
      expect(formatExpenseDate(DateTime(2026, 10, 5, 23, 59)), '2026-10-05');
      expect(formatExpenseDate(DateTime(2026, 1, 1)), '2026-01-01');
      expect(formatExpenseDate(DateTime(999, 3, 4)), '0999-03-04');
    });

    test('every text form of an instant shows the same local day', () {
      for (final local in [
        DateTime(2026, 10, 31, 23, 30),
        DateTime(2026, 11, 1, 0, 30),
        DateTime(2026, 12, 31, 23, 59, 59, 999),
        DateTime(2027, 1, 1),
      ]) {
        final expected = formatExpenseDate(local);
        for (final text in dateTextVariants(local)) {
          expect(
            formatExpenseDate(DateTime.parse(text)),
            expected,
            reason: text,
          );
        }
      }
    });

    test('shows the month that monthly totals use', () {
      var instant = DateTime.utc(2026, 1, 1);
      while (instant.year < 2027) {
        final shown = formatExpenseDate(instant);
        final day = localCalendarDate(instant);
        expect(
          shown,
          startsWith('${day.year}-${day.month.toString().padLeft(2, '0')}-'),
        );
        expect(
          isInSameLocalMonth(instant, DateTime(day.year, day.month, 28)),
          isTrue,
        );
        instant = instant.add(const Duration(hours: 7));
      }
    });
  });

  group('English display dates', () {
    for (final (date, short, long) in [
      (DateTime(2026, 1, 1), 'Jan 1, 2026', 'January 1, 2026'),
      (DateTime(2026, 12, 31, 23, 59), 'Dec 31, 2026', 'December 31, 2026'),
      (DateTime(2026, 10, 3), 'Oct 3, 2026', 'October 3, 2026'),
      (DateTime(2026, 10, 12), 'Oct 12, 2026', 'October 12, 2026'),
      (DateTime(2028, 2, 29), 'Feb 29, 2028', 'February 29, 2028'),
      (DateTime(1995, 6, 1), 'Jun 1, 1995', 'June 1, 1995'),
      (DateTime(2030, 9, 9), 'Sep 9, 2030', 'September 9, 2030'),
      (DateTime(999, 5, 2), 'May 2, 0999', 'May 2, 0999'),
    ]) {
      test('$date', () {
        expect(formatShortDate(date), short);
        expect(formatLongDate(date), long);
      });
    }

    test('every month has its English name and a 3-letter abbreviation', () {
      expect(
        [for (var m = 1; m <= 12; m++) formatShortDate(DateTime(2026, m, 5))],
        [
          'Jan 5, 2026',
          'Feb 5, 2026',
          'Mar 5, 2026',
          'Apr 5, 2026',
          'May 5, 2026',
          'Jun 5, 2026',
          'Jul 5, 2026',
          'Aug 5, 2026',
          'Sep 5, 2026',
          'Oct 5, 2026',
          'Nov 5, 2026',
          'Dec 5, 2026',
        ],
      );
      expect(formatMonthYear(DateTime(2026, 10, 15)), 'October 2026');
    });

    test('same local day as ISO and the monthly total, for every text form '
        'near midnight', () {
      for (final local in [
        DateTime(2026, 10, 31, 23, 30),
        DateTime(2026, 11, 1, 0, 30),
        DateTime(2026, 12, 31, 23, 59, 59, 999),
        DateTime(2027, 1, 1),
      ]) {
        final day = localCalendarDate(local);
        for (final text in dateTextVariants(local)) {
          final parsed = DateTime.parse(text);
          expect(formatLongDate(parsed), formatLongDate(day), reason: text);
          expect(formatShortDate(parsed), formatShortDate(day), reason: text);
          expect(
            formatExpenseDate(parsed),
            formatExpenseDate(day),
            reason: text,
          );
        }
      }
    });
  });
}
