import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/calendar.dart';

import '../support/date_texts.dart';

void main() {
  test('isoWithOffset denotes the same instant', () {
    final instant = DateTime.utc(2026, 10, 31, 23, 30);
    for (final offset in testOffsets) {
      final text = isoWithOffset(instant, offset);
      expect(
        DateTime.parse(text).isAtSameMomentAs(instant),
        isTrue,
        reason: text,
      );
    }
    expect(
      isoWithOffset(instant, const Duration(hours: -3)),
      '2026-10-31T20:30:00.000-03:00',
    );
  });

  group('localCalendarDate', () {
    test('text without an offset is already local and used as is', () {
      expect(
        localCalendarDate(DateTime.parse('2026-10-31T23:30:00.000')),
        DateTime(2026, 10, 31),
      );
      expect(
        localCalendarDate(DateTime.parse('2026-11-01T00:00:00')),
        DateTime(2026, 11, 1),
      );
    });

    for (final (label, local) in [
      ('late on the last day of a month', DateTime(2026, 10, 31, 23, 30)),
      ('just after midnight on the first', DateTime(2026, 11, 1, 0, 30)),
      ('last millisecond of the year', DateTime(2026, 12, 31, 23, 59, 59, 999)),
      ('first instant of the year', DateTime(2027, 1, 1)),
      ('leap day', DateTime(2028, 2, 29, 23, 59)),
    ]) {
      test('every text form of an instant $label gives its local day', () {
        final expected = DateTime(local.year, local.month, local.day);
        for (final text in dateTextVariants(local)) {
          expect(
            localCalendarDate(DateTime.parse(text)),
            expected,
            reason: text,
          );
        }
      });
    }

    test('a fixed instant lands on the day the device zone says', () {
      // 02:30 UTC on 1 November: still 31 October west of UTC−2:30.
      final instant = DateTime.parse('2026-10-31T23:30:00.000-03:00');
      final local = instant.toLocal();
      expect(
        localCalendarDate(instant),
        DateTime(local.year, local.month, local.day),
      );
    });
  });

  group('isInSameLocalMonth', () {
    test('compares local months, whatever the text form', () {
      final lastOfOctober = DateTime(2026, 10, 31, 23, 30);
      final firstOfNovember = DateTime(2026, 11, 1, 0, 30);
      final reference = DateTime(2026, 10, 15, 12);

      for (final text in dateTextVariants(lastOfOctober)) {
        expect(
          isInSameLocalMonth(DateTime.parse(text), reference),
          isTrue,
          reason: text,
        );
      }
      for (final text in dateTextVariants(firstOfNovember)) {
        expect(
          isInSameLocalMonth(DateTime.parse(text), reference),
          isFalse,
          reason: text,
        );
      }
    });

    test('the same month in another year is not the same month', () {
      expect(
        isInSameLocalMonth(DateTime(2025, 10, 15), DateTime(2026, 10, 15)),
        isFalse,
      );
    });

    test('a UTC reference is compared in local time too', () {
      final reference = DateTime(2027, 1, 1, 0, 30);
      expect(
        isInSameLocalMonth(DateTime(2027, 1, 20), reference.toUtc()),
        isTrue,
      );
    });

    test('matches the local day for every hour of a year (incl. any '
        'daylight-saving changes of this machine\'s zone)', () {
      var instant = DateTime.utc(2026, 1, 1);
      final end = DateTime.utc(2027, 1, 2);
      while (instant.isBefore(end)) {
        final day = localCalendarDate(instant);
        final reference = DateTime(day.year, day.month, 15);
        for (final text in dateTextVariants(instant)) {
          final parsed = DateTime.parse(text);
          expect(localCalendarDate(parsed), day, reason: text);
          expect(isInSameLocalMonth(parsed, reference), isTrue, reason: text);
        }
        instant = instant.add(const Duration(minutes: 30));
      }
    });
  });
}
