import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/expense.dart';

class ExpenseProvider with ChangeNotifier {
  List<Expense> _expenses = [];

  List<Expense> get expenses => List.unmodifiable(_expenses);

  double get currentMonthTotal {
    final now = DateTime.now();
    return _expenses
        .where((e) => e.date.month == now.month && e.date.year == now.year)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  Future<void> loadExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('expenses');
    if (data != null) {
      final list = json.decode(data) as List<dynamic>;
      _expenses = list.map((e) => Expense.fromMap(e)).toList();
      notifyListeners();
    }
  }

  Future<void> saveExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final data = json.encode(_expenses.map((e) => e.toMap()).toList());
    await prefs.setString('expenses', data);
  }

  Future<void> addExpense(Expense expense) async {
    _expenses.add(expense);
    await saveExpenses();
    notifyListeners();
  }

  Future<void> deleteExpense(String id) async {
    _expenses.removeWhere((e) => e.id == id);
    await saveExpenses();
    notifyListeners();
  }
}
