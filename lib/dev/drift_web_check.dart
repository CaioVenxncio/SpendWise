// Development-only entry point for checking DriftExpenseRepository in a
// real browser. Not used by the app (lib/main.dart). Build with:
//   flutter build web -t lib/dev/drift_web_check.dart -o build/drift_check
// It uses its own database name and never touches the app's data.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../data/drift/connection.dart';
import '../data/drift/database.dart';
import '../domain/money.dart';
import '../models/expense.dart';
import '../repositories/drift_expense_repository.dart';
import '../repositories/expense_repository.dart';

const checkDatabaseName = 'spendwise_stage2_check';

final _state = <String, Object?>{};
final _text = ValueNotifier('starting');

void _publish() {
  final text = const JsonEncoder.withIndent('  ').convert(_state);
  web.window.setProperty('driftCheck'.toJS, text.toJS);
  _text.value = text;
}

Expense _fixture(String id, int cents, String dateText) => Expense(
  id: id,
  amount: Money.fromCents(cents),
  description: 'check $id',
  category: 'General',
  date: DateTime.parse(dateText),
  dateText: dateText,
);

final _fixtures = [
  _fixture('fx-max', Money.maxCents, '2026-10-14T22:07:12.656'),
  _fixture('fx-min', Money.minCents, '2024-02-29T23:59:59.999'),
  _fixture('fx-cent', 1, '2023-12-31T23:59:59.000Z'),
  _fixture('fx-offset', 1250, '2026-10-14T00:00:00.000+02:00'),
  _fixture('fx-short', 0, '2024-02-29T08:00:00'),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = SpendWiseDatabase(
    openSpendWiseConnection(
      name: checkDatabaseName,
      onWebResult: (r) {
        _state['implementation'] = r.implementation;
        _state['missingFeatures'] = r.missing;
        _publish();
      },
    ),
  );
  final repo = DriftExpenseRepository(db);

  try {
    final before = await repo.load();
    _state['rowsAtStartup'] = before.expenses.length;
    await repo.importExpenses(_fixtures);
    final all = (await repo.load()).expenses;
    final problems = <String>[];
    for (final f in _fixtures) {
      final match = all.where((e) => e.id == f.id).toList();
      if (match.length != 1) {
        problems.add('${f.id}: ${match.length} rows');
      } else if (json.encode(match.single.toMap()) != json.encode(f.toMap())) {
        problems.add('${f.id}: ${json.encode(match.single.toMap())}');
      }
    }
    _state['fixtureProblems'] = problems;

    // Rollback: a failing import must leave nothing behind.
    // Dev-only fault injection through the test hook.
    // ignore: invalid_use_of_visible_for_testing_member
    repo.beforeCommit = () => throw StateError('injected');
    try {
      await repo.importExpenses([
        _fixture('rollback-1', 1, '2026-01-01T00:00:00.000'),
        _fixture('rollback-2', 2, '2026-01-01T00:00:00.000'),
      ]);
    } catch (_) {}
    // ignore: invalid_use_of_visible_for_testing_member
    repo.beforeCommit = null;
    final afterRollback = (await repo.load()).expenses;
    _state['rollbackLeftRows'] = afterRollback
        .where((e) => e.id.startsWith('rollback'))
        .length;

    // Conflict: same ID, different content.
    try {
      await repo.importExpenses([
        _fixture('fx-cent', 2, '2023-12-31T23:59:59.000Z'),
      ]);
      _state['conflictDetected'] = false;
    } on ImportConflictException {
      _state['conflictDetected'] = true;
    }

    _state['ids'] = afterRollback.map((e) => e.id).toList();
  } catch (e) {
    _state['error'] = '$e';
  }
  _publish();

  web.window.setProperty(
    'driftCheckAdd'.toJS,
    ((JSString id) {
      Future<JSString> run() async {
        final list = await repo.add(
          _fixture(id.toDart, 725, DateTime.now().toIso8601String()),
        );
        return json.encode(list.map((e) => e.id).toList()).toJS;
      }

      return run().toJS;
    }).toJS,
  );
  web.window.setProperty(
    'driftCheckIds'.toJS,
    (() {
      Future<JSString> run() async {
        final list = (await repo.load()).expenses;
        final total = Money.sum(
          list.where((e) => !e.id.startsWith('fx-')).map((e) => e.amount),
        );
        return json.encode({
          'ids': list.map((e) => e.id).toList(),
          'nonFixtureTotal': total.toDecimalString(),
        }).toJS;
      }

      return run().toJS;
    }).toJS,
  );

  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Drift repository check (dev)')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ValueListenableBuilder<String>(
            valueListenable: _text,
            builder: (_, text, _) => SelectableText(text),
          ),
        ),
      ),
    ),
  );
}
