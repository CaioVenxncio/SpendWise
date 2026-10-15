import 'package:spendwise/models/expense.dart';
import 'package:spendwise/domain/money.dart';

String _two(int n) => n.toString().padLeft(2, '0');

/// ISO-8601 text for [instant] written with a fixed UTC [offset], e.g.
/// `2026-10-31T20:30:00.000-03:00`, independent of the test machine's zone.
String isoWithOffset(DateTime instant, Duration offset) {
  final wall = instant.toUtc().add(offset);
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  return '${wall.year.toString().padLeft(4, '0')}-${_two(wall.month)}-'
      '${_two(wall.day)}T${_two(wall.hour)}:${_two(wall.minute)}:'
      '${_two(wall.second)}.${wall.millisecond.toString().padLeft(3, '0')}'
      '$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
}

/// Offsets used for date-text variants: the extremes and some common ones.
const testOffsets = [
  Duration(hours: 14),
  Duration(hours: 5, minutes: 30),
  Duration(hours: 1),
  Duration(hours: -3),
  Duration(hours: -12),
];

/// Every stored text form of the same [instant]: local without offset (as
/// SpendWise writes), UTC `Z`, and each of [testOffsets].
List<String> dateTextVariants(DateTime instant) => [
  instant.toLocal().toIso8601String(),
  instant.toUtc().toIso8601String(),
  for (final offset in testOffsets) isoWithOffset(instant, offset),
];

/// An expense whose stored date text is exactly [dateText].
Expense expenseAt(String id, int cents, String dateText) => Expense(
  id: id,
  amount: Money.fromCents(cents),
  description: 'Expense $id',
  category: 'General',
  date: DateTime.parse(dateText),
  dateText: dateText,
);
