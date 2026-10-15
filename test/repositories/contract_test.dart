import 'package:drift/native.dart';
import 'package:spendwise/data/drift/database.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/repositories/drift_expense_repository.dart';
import 'package:spendwise/repositories/expense_repository.dart';
import 'package:spendwise/repositories/json_expense_repository.dart';
import 'package:spendwise/services/expense_storage.dart';

import '../support/fake_expense_storage.dart';
import 'repository_contract.dart';

class JsonHarness implements RepositoryHarness {
  final storage = FakeExpenseStorage();

  @override
  Future<ExpenseRepository> open({List<Expense> seed = const []}) async {
    storage.data = seed.isEmpty ? null : encodeExpenses(seed);
    return JsonExpenseRepository(storage);
  }

  @override
  ExpenseRepository secondInstance() => JsonExpenseRepository(storage);

  @override
  void failWrites(bool on) => storage.failWrites = on;

  @override
  Future<int> persistentWrites() async =>
      storage.writeCount + storage.backupCount;

  @override
  Future<void> dispose() async {}
}

class DriftHarness implements RepositoryHarness {
  final db = SpendWiseDatabase(NativeDatabase.memory());
  final _repos = <DriftExpenseRepository>[];
  bool _fail = false;

  DriftExpenseRepository _create() {
    final repo = DriftExpenseRepository(db)
      ..beforeCommit = () {
        if (_fail) throw StateError('injected failure');
      };
    _repos.add(repo);
    return repo;
  }

  @override
  Future<ExpenseRepository> open({List<Expense> seed = const []}) async {
    // Seed through a separate instance so the returned one is unloaded.
    if (seed.isNotEmpty) {
      final seeder = DriftExpenseRepository(db);
      await seeder.load();
      await seeder.importExpenses(seed);
    }
    return _create();
  }

  @override
  ExpenseRepository secondInstance() => _create();

  @override
  void failWrites(bool on) => _fail = on;

  @override
  Future<int> persistentWrites() async =>
      (await db.customSelect('SELECT total_changes() AS n').getSingle())
          .read<int>('n');

  @override
  Future<void> dispose() => db.close();
}

void main() {
  runRepositoryContract('JSON', JsonHarness.new);
  runRepositoryContract('Drift', DriftHarness.new);
}
