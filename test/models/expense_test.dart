import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/models/expense.dart';

void main() {
  test('Expense serialization', () {
    final expense = Expense(
      id: '1',
      amount: 10.5,
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
}
