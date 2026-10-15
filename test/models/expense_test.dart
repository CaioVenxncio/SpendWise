import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/models/expense.dart';

Map<String, dynamic> _record(Map<String, dynamic> amountFields) => {
  'id': '1',
  ...amountFields,
  'description': 'Bus',
  'category': 'Transport',
  'date': '2023-01-01T00:00:00.000',
};

void main() {
  test('Expense serialization', () {
    final expense = Expense(
      id: '1',
      amount: Money.fromCents(1050),
      description: 'Lunch',
      category: 'Food',
      date: DateTime(2023, 1, 1),
    );

    final map = expense.toMap();
    final fromMap = Expense.fromMap(map);

    expect(fromMap.id, expense.id);
    expect(fromMap.amount, expense.amount);
    expect(fromMap.description, expense.description);
    expect(fromMap.category, expense.category);
    expect(fromMap.date, expense.date);
  });

  test('writes the amount as integer cents only', () {
    final expense = Expense(
      id: 'abc',
      amount: Money.fromCents(9999),
      description: 'Groceries',
      category: 'Food',
      date: DateTime(2024, 2, 29, 13, 45),
    );

    expect(
      expense.toJson(),
      '{"id":"abc","amountCents":9999,"description":"Groceries",'
      '"category":"Food","date":"2024-02-29T13:45:00.000"}',
    );
    expect(Expense.fromJson(expense.toJson()).toMap(), expense.toMap());
  });

  group('current format', () {
    test('accepts integral cents written as 1250.0', () {
      final expense = Expense.fromJson(
        jsonEncode(_record({}))
            .replaceFirst('"id":"1"', '"id":"1","amountCents":1250.0'),
      );
      expect(expense.amount, Money.fromCents(1250));
    });

    test('accepts zero and negative cents within range', () {
      expect(Expense.fromMap(_record({'amountCents': 0})).amount, Money.zero);
      expect(
        Expense.fromMap(_record({'amountCents': -5})).amount,
        Money.fromCents(-5),
      );
    });

    final invalid = <String, Object?>{
      'fractional cents': 12.5,
      'string cents': '1250',
      'null cents': null,
      'above range': Money.maxCents + 1,
      'below range': Money.minCents - 1,
      'huge double': 1e300,
    };
    invalid.forEach((name, value) {
      test('rejects $name', () {
        expect(
          () => Expense.fromMap(_record({'amountCents': value})),
          throwsFormatException,
        );
      });
    });
  });

  group('legacy format', () {
    test('converts double amounts exactly', () {
      final expense = Expense.fromMap(_record({'amount': 19.99}));
      expect(expense.amount, Money.fromCents(1999));
      expect(Expense.isLegacyMap(_record({'amount': 19.99})), isTrue);
    });

    test('converts integer amounts', () {
      expect(
        Expense.fromMap(_record({'amount': 10})).amount,
        Money.fromCents(1000),
      );
    });

    test('decodes records exactly as the original app wrote them', () {
      final expense = Expense.fromJson(
        '{"id":"a","amount":12.5,"description":"Lunch","category":"Food",'
        '"date":"2024-03-10T12:00:00.000"}',
      );
      expect(expense.amount, Money.fromCents(1250));
      expect(expense.date, DateTime(2024, 3, 10, 12));
    });

    test('rejects excessively precise amounts instead of rounding', () {
      expect(
        () => Expense.fromJson(
          '{"id":"a","amount":12.345,"description":"x","category":"y",'
          '"date":"2024-03-10T12:00:00.000"}',
        ),
        throwsFormatException,
      );
    });

    test('rejects non-numeric amounts', () {
      expect(
        () => Expense.fromMap(_record({'amount': '12.50'})),
        throwsFormatException,
      );
    });

    test('rejects records with both amount fields', () {
      expect(
        () => Expense.fromMap(_record({'amount': 12.5, 'amountCents': 1250})),
        throwsFormatException,
      );
    });

    test('a current record is not legacy', () {
      expect(Expense.isLegacyMap(_record({'amountCents': 1})), isFalse);
    });
  });

  group('fromMap rejects malformed records with FormatException', () {
    final valid = _record({'amountCents': 1000});

    for (final field in [
      'id',
      'amountCents',
      'description',
      'category',
      'date',
    ]) {
      test('missing $field', () {
        final map = Map<String, dynamic>.of(valid)..remove(field);
        expect(() => Expense.fromMap(map), throwsFormatException);
      });
    }

    test('unparseable date', () {
      final map = Map<String, dynamic>.of(valid)..['date'] = 'yesterday';
      expect(() => Expense.fromMap(map), throwsFormatException);
    });
  });

  test('fromJson rejects non-object JSON', () {
    expect(() => Expense.fromJson('[1, 2]'), throwsFormatException);
  });

  group('dateText', () {
    for (final text in [
      '2024-03-10T12:00:00.000',
      '2023-12-31T23:59:59.000Z',
      '2026-10-14T00:00:00.000+02:00',
      '2024-02-29T08:00:00',
      '2024-02-29T08:00:00.123456',
    ]) {
      test('"$text" is written back verbatim', () {
        final map = {
          'id': '1',
          'amountCents': 1,
          'description': 'x',
          'category': 'y',
          'date': text,
        };
        final expense = Expense.fromMap(map);
        expect(expense.dateText, text);
        expect(expense.toMap()['date'], text);
        expect(expense.date, DateTime.parse(text));
      });
    }

    test('defaults to the ISO form of date', () {
      final expense = Expense(
        id: '1',
        amount: Money.fromCents(1),
        description: 'x',
        category: 'y',
        date: DateTime(2024, 1, 2, 3, 4, 5),
      );
      expect(expense.dateText, '2024-01-02T03:04:05.000');
    });

    test('must denote the same instant as date', () {
      expect(
        () => Expense(
          id: '1',
          amount: Money.fromCents(1),
          description: 'x',
          category: 'y',
          date: DateTime(2024, 1, 2),
          dateText: '2025-01-01T00:00:00.000',
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('edited', () {
    Expense parsed(String text) => Expense.fromMap({
      'id': 'x1',
      'amountCents': 1250,
      'description': 'Lunch',
      'category': 'Food',
      'date': text,
    });

    test('keeps the ID and changes only the given fields', () {
      final original = parsed('2024-03-01T12:00:00.000');
      final copy = original.edited(
        amount: Money.fromCents(99),
        category: 'Transport',
      );

      expect(copy.id, 'x1');
      expect(copy.amount.cents, 99);
      expect(copy.description, 'Lunch');
      expect(copy.category, 'Transport');
      expect(copy.dateText, '2024-03-01T12:00:00.000');
    });

    test('no change gives an identical record', () {
      final original = parsed('2024-03-01T12:00:00.000');
      expect(original.edited().toJson(), original.toJson());
    });

    for (final text in [
      '2023-12-31T23:59:59.000Z',
      '2026-10-14T00:00:00.000+02:00',
      '2024-02-29T08:00:00',
      '2024-03-01T12:00:00.123456',
    ]) {
      test('the same local day keeps "$text" byte-for-byte', () {
        final original = parsed(text);
        final local = original.date.toLocal();

        final copy = original.edited(
          description: 'changed',
          day: DateTime(local.year, local.month, local.day, 23, 59),
        );

        expect(copy.dateText, text);
        expect(copy.date.isAtSameMomentAs(original.date), isTrue);
      });
    }

    test('a new day keeps the local time of day without an offset', () {
      final original = parsed('2024-03-01T08:15:30.250');

      final copy = original.edited(day: DateTime(2025, 1, 31));

      expect(copy.dateText, '2025-01-31T08:15:30.250');
      expect(copy.date, DateTime(2025, 1, 31, 8, 15, 30, 250));
      expect(copy.date.isUtc, isFalse);
    });

    test('a new day for an offset date uses its local time of day', () {
      final original = parsed('2026-10-14T00:00:00.000+02:00');
      final local = original.date.toLocal();
      final target = DateTime(2026, 11, 2);

      final copy = original.edited(day: target);

      final expected = DateTime(
        2026,
        11,
        2,
        local.hour,
        local.minute,
        local.second,
        local.millisecond,
        local.microsecond,
      );
      expect(copy.date, expected);
      expect(copy.dateText, expected.toIso8601String());
      expect(copy.dateText.endsWith('Z'), isFalse);
      expect(copy.dateText.contains('+'), isFalse);
    });

    test('the result round-trips through JSON', () {
      final copy = parsed('2023-12-31T23:59:59.000Z').edited(
        amount: Money.fromCents(Money.maxCents),
        day: DateTime(2024, 6, 1),
      );
      expect(Expense.fromJson(copy.toJson()).toJson(), copy.toJson());
    });
  });
}
