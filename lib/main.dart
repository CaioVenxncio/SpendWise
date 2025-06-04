import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'pages/add_expense_page.dart';
import 'providers/expense_provider.dart';

void main() => runApp(const SpendWiseApp());

class SpendWiseApp extends StatelessWidget {
  const SpendWiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ExpenseProvider()..loadExpenses(),
      child: MaterialApp(
        title: 'SpendWise',
        theme: ThemeData(primarySwatch: Colors.blue),
        home: const HomePage(),
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ExpenseProvider>(context);
    final expenses = provider.expenses;

    return Scaffold(
      appBar: AppBar(title: const Text('SpendWise')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Total this month: \$${provider.currentMonthTotal.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: expenses.isEmpty
                ? const Center(child: Text('No expenses'))
                : ListView.builder(
                    itemCount: expenses.length,
                    itemBuilder: (context, index) {
                      final expense = expenses[index];
                      return ListTile(
                        title: Text(expense.description),
                        subtitle: Text(
                          '${expense.category} - ${expense.date.toLocal().toString().split(' ')[0]}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('\\$${expense.amount.toStringAsFixed(2)}'),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () => provider.deleteExpense(expense.id),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => AddExpensePage()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
