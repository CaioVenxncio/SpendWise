import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/validation/expense_form_baseline.dart';

Expense _stored({
  int cents = 1250,
  String description = 'Lunch',
  String category = 'Food',
  String dateText = '2026-10-03T12:30:00.000',
}) => Expense(
  id: 'id-1',
  amount: Money.fromCents(cents),
  description: description,
  category: category,
  date: DateTime.parse(dateText),
  dateText: dateText,
);

ExpenseFormValues _values(
  ExpenseFormBaseline b, {
  String? amount,
  String? description,
  String? category,
  DateTime? date,
}) => ExpenseFormValues(
  amountText: amount ?? b.amountText,
  description: description ?? b.description,
  category: category ?? b.category,
  date: date ?? b.date,
);

void main() {
  group('edit baseline', () {
    test('starts from the stored values', () {
      final b = ExpenseFormBaseline.edit(_stored());
      expect(b.isEditing, isTrue);
      expect(b.amountText, '12.50');
      expect(b.description, 'Lunch');
      expect(b.category, 'Food');
      expect(b.isDirty(_values(b)), isFalse);
    });

    test('formatting-only amount changes are not changes', () {
      final b = ExpenseFormBaseline.edit(_stored());
      for (final text in ['12.50', '12.5', ' 12.50 ', '12,50', '12,5']) {
        expect(b.amountChanged(text), isFalse, reason: text);
        expect(b.isDirty(_values(b, amount: text)), isFalse, reason: text);
      }
      expect(b.amountChanged('12.51'), isTrue);
      expect(b.amountChanged(''), isTrue);
      expect(b.amountChanged('abc'), isTrue);
    });

    test('surrounding whitespace in the description is not a change', () {
      final b = ExpenseFormBaseline.edit(_stored());
      expect(b.descriptionChanged('  Lunch '), isFalse);
      expect(b.descriptionChanged('lunch'), isTrue);
    });

    test('a time-only difference on the same local day is not a change', () {
      final b = ExpenseFormBaseline.edit(_stored());
      expect(b.dayChanged(DateTime(2026, 10, 3)), isFalse);
      expect(b.dayChanged(DateTime(2026, 10, 3, 23, 59)), isFalse);
      expect(b.dayChanged(DateTime(2026, 10, 4)), isTrue);
    });

    test('an unknown category is offered and kept', () {
      final b = ExpenseFormBaseline.edit(_stored(category: 'Groceries'));
      expect(b.categories, [...expenseCategories, 'Groceries']);
      final replacement = b.replacement(_values(b, description: 'Weekly shop'));
      expect(replacement.category, 'Groceries');
    });

    test('a known category is not listed twice', () {
      final b = ExpenseFormBaseline.edit(_stored(category: 'Food'));
      expect(b.categories, expenseCategories);
    });

    for (final cents in [0, -500, Money.maxCents, Money.minCents]) {
      test('unchanged amount $cents is kept exactly and not re-validated', () {
        final b = ExpenseFormBaseline.edit(_stored(cents: cents));
        expect(b.validateAmountText(b.amountText), isNull);
        final replacement = b.replacement(_values(b, description: 'x'));
        expect(replacement.amount.cents, cents);
      });
    }

    test('a changed amount must pass the new-expense rules', () {
      final b = ExpenseFormBaseline.edit(_stored(cents: -500));
      expect(b.validateAmountText('-1'), isNotNull);
      expect(b.validateAmountText('0'), isNotNull);
      expect(b.validateAmountText('1000000000.01'), isNotNull);
      expect(b.validateAmountText('1.234'), isNotNull);
      expect(b.validateAmountText(''), isNotNull);
      expect(b.validateAmountText('1000000000'), isNull);
      expect(
        b.replacement(_values(b, amount: '1000000000')).amount.cents,
        100000000000,
      );
    });

    test('an unchanged imported description is not re-validated', () {
      final long = 'x' * 300;
      final b = ExpenseFormBaseline.edit(_stored(description: long));
      expect(b.validateDescriptionText(long), isNull);
      expect(b.replacement(_values(b, amount: '1')).description, long);
      expect(b.validateDescriptionText('${long}y'), isNotNull);
    });

    test('an untouched imported description keeps its whitespace', () {
      final b = ExpenseFormBaseline.edit(_stored(description: ' padded '));
      expect(b.replacement(_values(b, amount: '1')).description, ' padded ');
    });

    for (final text in [
      '2023-12-31T23:59:59.000Z',
      '2026-10-14T00:00:00.000+02:00',
      '2024-02-29T08:00:00',
      '1995-06-01T09:00:00.000',
    ]) {
      test('date text "$text" survives an edit of other fields', () {
        final b = ExpenseFormBaseline.edit(_stored(dateText: text));
        final r = b.replacement(
          _values(b, amount: '99', description: 'Changed', category: 'General'),
        );
        expect(r.id, 'id-1');
        expect(r.dateText, text);
        expect(r.amount.cents, 9900);
        expect(r.description, 'Changed');
        expect(r.category, 'General');
      });
    }

    test('a new day keeps the local time of day', () {
      final b = ExpenseFormBaseline.edit(_stored());
      final r = b.replacement(_values(b, date: DateTime(2026, 9, 30)));
      expect(r.dateText, '2026-09-30T12:30:00.000');
    });

    test('no change gives the identical record', () {
      final original = _stored(dateText: '2026-10-14T00:00:00.000+02:00');
      final b = ExpenseFormBaseline.edit(original);
      expect(b.replacement(_values(b)).toJson(), original.toJson());
    });
  });

  group('add baseline', () {
    final now = DateTime(2026, 10, 15, 9, 41);

    test('is clean until something is entered', () {
      final b = ExpenseFormBaseline.add(now);
      expect(b.isEditing, isFalse);
      expect(b.category, 'General');
      expect(b.isDirty(_values(b)), isFalse);
      expect(b.isDirty(_values(b, amount: ' ')), isFalse);
      expect(b.isDirty(_values(b, amount: '1')), isTrue);
      expect(b.isDirty(_values(b, description: 'x')), isTrue);
      expect(b.isDirty(_values(b, category: 'Food')), isTrue);
      expect(b.isDirty(_values(b, date: DateTime(2026, 10, 1))), isTrue);
    });

    test('always validates', () {
      final b = ExpenseFormBaseline.add(now);
      expect(b.validateAmountText(''), isNotNull);
      expect(b.validateDescriptionText(''), isNotNull);
    });

    test('creates the expense as before', () {
      final b = ExpenseFormBaseline.add(now);
      final e = b.newExpense(
        'new',
        _values(b, amount: '12,50', description: ' Bus '),
      );
      expect(e.id, 'new');
      expect(e.amount.cents, 1250);
      expect(e.description, 'Bus');
      expect(e.date, now);
      expect(() => b.replacement(_values(b)), throwsStateError);
    });
  });
}
