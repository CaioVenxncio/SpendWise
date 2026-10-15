import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/money.dart';

Money _c(int cents) => Money.fromCents(cents);

void main() {
  group('construction and range', () {
    test('accepts the full supported range', () {
      expect(_c(Money.maxCents).cents, 9007199254740991);
      expect(_c(Money.minCents).cents, -9007199254740991);
      expect(_c(0), Money.zero);
    });

    test('limits are exactly representable as JavaScript numbers', () {
      // 2^53 - 1: beyond it, Flutter Web loses integer precision.
      expect(Money.maxCents, pow(2, 53).toInt() - 1);
      expect(Money.minCents, -Money.maxCents);
    });

    test('rejects values outside the range', () {
      expect(() => _c(Money.maxCents + 1), throwsRangeError);
      expect(() => _c(Money.minCents - 1), throwsRangeError);
    });
  });

  group('arithmetic', () {
    test('adds and subtracts exactly where doubles would not', () {
      expect(Money.parse('0.10') + Money.parse('0.20'), Money.parse('0.30'));
      expect(Money.parse('1.10') - Money.parse('1.00'), _c(10));

      var total = Money.zero;
      for (var i = 0; i < 1000; i++) {
        total += Money.parse('0.01');
      }
      expect(total, Money.parse('10.00'));
    });

    test('supports negative results and negation', () {
      expect(_c(100) - _c(250), _c(-150));
      expect(-_c(150), _c(-150));
      expect(-(-_c(150)), _c(150));
    });

    test('negating zero gives zero', () {
      expect(-Money.zero, Money.zero);
      expect((-Money.zero).cents, 0);
      expect((-Money.zero).toDecimalString(), '0.00');
      expect((_c(5) - _c(5)).toDecimalString(), '0.00');
    });

    test('reaches the limits exactly', () {
      expect(_c(Money.maxCents - 1) + _c(1), _c(Money.maxCents));
      expect(_c(Money.minCents + 1) - _c(1), _c(Money.minCents));
      expect(_c(Money.maxCents) + _c(Money.minCents), Money.zero);
      expect(_c(Money.maxCents) - _c(Money.maxCents), Money.zero);
    });

    test('throws instead of overflowing', () {
      final max = _c(Money.maxCents);
      final min = _c(Money.minCents);
      expect(() => max + _c(1), throwsA(isA<MoneyOverflowException>()));
      expect(() => min - _c(1), throwsA(isA<MoneyOverflowException>()));
      expect(() => max - min, throwsA(isA<MoneyOverflowException>()));
      expect(() => min + min, throwsA(isA<MoneyOverflowException>()));
    });

    test('sum adds all amounts and detects overflow', () {
      expect(Money.sum([]), Money.zero);
      expect(Money.sum([_c(1), _c(2), _c(-4)]), _c(-1));
      expect(
        () => Money.sum([_c(Money.maxCents), _c(1)]),
        throwsA(isA<MoneyOverflowException>()),
      );
    });
  });

  group('comparison and equality', () {
    test('zero and sign checks', () {
      expect(Money.zero.isZero, isTrue);
      expect(_c(1).isPositive, isTrue);
      expect(_c(-1).isNegative, isTrue);
      expect(_c(1).isZero || _c(1).isNegative, isFalse);
    });

    test('comparison operators', () {
      expect(_c(1) < _c(2), isTrue);
      expect(_c(2) <= _c(2), isTrue);
      expect(_c(-1) > _c(-2), isTrue);
      expect(_c(3) >= _c(4), isFalse);
      final sorted = [_c(3), _c(-1), _c(2)]..sort();
      expect(sorted, [_c(-1), _c(2), _c(3)]);
    });

    test('value equality and hash codes', () {
      expect(_c(1250), Money.parse('12.50'));
      expect(_c(1250).hashCode, Money.parse('12,5').hashCode);
      expect(_c(1250), isNot(_c(1251)));
      expect({_c(1), _c(1), _c(2)}, hasLength(2));
    });
  });

  group('tryParse', () {
    const valid = {
      '12.50': 1250,
      '12,50': 1250,
      '12.5': 1250,
      '0.01': 1,
      '0': 0,
      '1000': 100000,
      '1000.00': 100000,
      '007.5': 750,
      ' 7 ': 700,
      '90071992547409.91': Money.maxCents,
    };
    valid.forEach((input, cents) {
      test('parses "$input" as $cents cents', () {
        expect(Money.tryParse(input), _c(cents));
      });
    });

    const invalid = [
      '',
      '   ',
      'NaN',
      'Infinity',
      '-Infinity',
      '1e3',
      '1E3',
      '-5',
      '+5',
      '1.234',
      '0.001',
      '1,000.00',
      '1.000,00',
      '1 000',
      '1_000',
      '12.',
      '.5',
      ',5',
      '12.5.0',
      'abc',
      '\$12',
      '١٢', // Arabic-Indic digits
      '90071992547409.92',
      '99999999999999999999999',
    ];
    for (final input in invalid) {
      test('rejects "$input"', () {
        expect(Money.tryParse(input), isNull);
        expect(() => Money.parse(input), throwsFormatException);
      });
    }
  });

  group('formatting', () {
    const cases = {
      1250: '12.50',
      5: '0.05',
      0: '0.00',
      100000: '1000.00',
      -300: '-3.00',
      -5: '-0.05',
      Money.maxCents: '90071992547409.91',
      Money.minCents: '-90071992547409.91',
    };
    cases.forEach((cents, text) {
      test('formats $cents cents as "$text"', () {
        expect(_c(cents).toDecimalString(), text);
      });
    });

    test('parse and format round-trip', () {
      for (final cents in [
        0,
        1,
        9,
        10,
        99,
        100,
        101,
        123456789,
        Money.maxCents,
      ]) {
        final money = _c(cents);
        expect(Money.parse(money.toDecimalString()), money);
      }
    });

    test('toString is descriptive', () {
      expect(_c(1250).toString(), 'Money(12.50)');
    });
  });

  group('moneyFromLegacyAmount', () {
    const valid = <(num, int)>[
      (12.5, 1250),
      (10, 1000),
      (10.0, 1000),
      (0.1, 10),
      (0.01, 1),
      (19.99, 1999),
      (1234567.89, 123456789),
      (0.0, 0),
      (-5.25, -525),
      (1000000000, 100000000000),
    ];
    for (final (value, cents) in valid) {
      test('converts ${value.runtimeType} $value exactly to $cents cents', () {
        expect(moneyFromLegacyAmount(value), _c(cents));
      });
    }

    test('negative zero converts to zero', () {
      expect(moneyFromLegacyAmount(-0.0), Money.zero);
    });

    final invalid = <String, num>{
      'NaN': double.nan,
      'Infinity': double.infinity,
      '-Infinity': double.negativeInfinity,
      'three decimals': 12.345,
      'binary rounding artifact': 0.1 + 0.2,
      'exponent notation (large)': 1e21,
      'exponent notation (small)': 1e-7,
      'out of range': 1e15,
    };
    invalid.forEach((name, value) {
      test('rejects $name ($value) without rounding', () {
        expect(() => moneyFromLegacyAmount(value), throwsFormatException);
      });
    });
  });

  group('sum: exact, order-independent, range-checked at the end', () {
    final max = Money.fromCents(Money.maxCents);
    final min = Money.fromCents(Money.minCents);
    final cent = Money.fromCents(1);
    final minusCent = Money.fromCents(-1);

    /// Every ordering of [items].
    List<List<T>> permutations<T>(List<T> items) {
      if (items.length <= 1) return [items];
      return [
        for (var i = 0; i < items.length; i++)
          for (final rest in permutations([
            ...items.sublist(0, i),
            ...items.sublist(i + 1),
          ]))
            [items[i], ...rest],
      ];
    }

    test('A: empty is exact zero', () {
      expect(Money.sum(const []), Money.zero);
      expect(Money.sum(const []).cents, 0);
    });

    test('B: one value is itself', () {
      expect(Money.sum([_c(1250)]), _c(1250));
      expect(Money.sum([max]), max);
      expect(Money.sum([min]), min);
    });

    test('C: ordinary positive values', () {
      expect(Money.sum([_c(1250), _c(300), _c(5)]), _c(1555));
    });

    test('D: negative values', () {
      expect(Money.sum([_c(-500), _c(-125), _c(25)]), _c(-600));
    });

    test('E: cancellation to zero', () {
      final zero = Money.sum([_c(123456), _c(-123456), max, min]);
      expect(zero, Money.zero);
      expect(zero.isZero, isTrue);
      expect(zero.toDecimalString(), '0.00');
    });

    test('F: [MAX, +1 cent, -1 cent] is MAX', () {
      expect(Money.sum([max, cent, minusCent]), max);
    });

    test('G: [MIN, -1 cent, +1 cent] is MIN', () {
      expect(Money.sum([min, minusCent, cent]), min);
    });

    test('H: every permutation gives the same exact result', () {
      final cases = <List<Money>>[
        [max, cent, minusCent],
        [min, minusCent, cent],
        [max, max, min, minusCent, _c(-1000)],
        [max, _c(5000), _c(-7000), _c(1999)],
        [min, min, max, max, cent],
        [_c(1250), _c(-300), _c(99), _c(1)],
      ];
      for (final values in cases) {
        final expected = values.fold<BigInt>(
          BigInt.zero,
          (t, m) => t + BigInt.from(m.cents),
        );
        for (final order in permutations(values)) {
          expect(
            Money.sum(order).cents,
            expected.toInt(),
            reason: order.map((m) => m.cents).join(', '),
          );
        }
      }
    });

    test('I: an exact total above MAX fails closed in every order', () {
      for (final order in permutations([max, cent, _c(-1), cent])) {
        expect(
          () => Money.sum(order),
          throwsA(isA<MoneyOverflowException>()),
          reason: order.map((m) => m.cents).join(', '),
        );
      }
      expect(
        () => Money.sum([max, max, min, cent]),
        throwsA(isA<MoneyOverflowException>()),
      );
    });

    test('J: an exact total below MIN fails closed in every order', () {
      for (final order in permutations([min, minusCent, cent, minusCent])) {
        expect(() => Money.sum(order), throwsA(isA<MoneyOverflowException>()));
      }
    });

    test('K: totals exactly at MAX and MIN succeed', () {
      expect(Money.sum([_c(Money.maxCents - 100), _c(100)]), max);
      expect(Money.sum([_c(Money.minCents + 100), _c(-100)]), min);
      expect(Money.sum([max, max, min]), max);
      expect(Money.sum([min, min, max]), min);
    });

    test('L: large mixed-sign collections are exact', () {
      final values = <Money>[];
      var expected = BigInt.zero;
      for (var i = 0; i < 2000; i++) {
        final m = i.isEven ? max : _c(Money.minCents + i);
        values.add(m);
        expected += BigInt.from(m.cents);
      }
      // 1000 × MAX + Σ(MIN + odd i) = Σ odd i = 1,000,000.
      expect(expected, BigInt.from(1000000));
      expect(Money.sum(values).cents, 1000000);
      expect(Money.sum(values.reversed).cents, 1000000);
    });

    test('the Money range itself is unchanged', () {
      expect(Money.maxCents, 9007199254740991);
      expect(Money.minCents, -9007199254740991);
      expect(() => Money.fromCents(Money.maxCents + 1), throwsRangeError);
      expect(() => max + cent, throwsA(isA<MoneyOverflowException>()));
    });
  });
}
