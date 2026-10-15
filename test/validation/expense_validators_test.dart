import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/validation/expense_validators.dart';

void main() {
  group('parseExpenseAmount', () {
    test('accepts positive amounts with up to two decimals', () {
      expect(parseExpenseAmount('12'), Money.fromCents(1200));
      expect(parseExpenseAmount('12.5'), Money.fromCents(1250));
      expect(parseExpenseAmount('12,50'), Money.fromCents(1250));
      expect(parseExpenseAmount(' 0.01 '), Money.fromCents(1));
    });

    test('accepts the maximum expense amount', () {
      expect(parseExpenseAmount('1000000000'), maxExpenseAmount);
      expect(parseExpenseAmount('1000000000.00'), maxExpenseAmount);
    });

    for (final input in [
      '',
      '0',
      '0.00',
      '-5',
      '+5',
      '1.234',
      '1e3',
      'NaN',
      'Infinity',
      '1,000.00',
      '12.',
      '.5',
      'abc',
      '1000000000.01',
    ]) {
      test('rejects "$input"', () => expect(parseExpenseAmount(input), isNull));
    }
  });

  group('validateAmount', () {
    test('returns null for valid input', () {
      expect(validateAmount('12.50'), isNull);
      expect(validateAmount('12,50'), isNull);
    });

    test('requires a value', () {
      expect(validateAmount(null), 'Enter amount');
      expect(validateAmount('  '), 'Enter amount');
    });

    test('explains format errors', () {
      for (final input in ['12.345', '-3', '1e3', '1,000.00']) {
        expect(validateAmount(input), contains('up to 2 decimals'));
      }
    });

    test('explains range errors', () {
      expect(validateAmount('0'), contains('greater than 0'));
      expect(validateAmount('1000000000.01'), contains('at most'));
    });
  });

  group('validateDescription', () {
    test('returns null for valid input', () {
      expect(validateDescription('Lunch'), isNull);
    });

    test('rejects empty or whitespace-only input', () {
      expect(validateDescription(null), 'Enter description');
      expect(validateDescription('   '), 'Enter description');
    });

    test('rejects overly long input', () {
      expect(validateDescription('a' * (maxDescriptionLength + 1)), isNotNull);
      expect(validateDescription('a' * maxDescriptionLength), isNull);
    });
  });
}
