import 'dart:convert';

import '../domain/money.dart';

class Expense {
  final String id;
  final Money amount;
  final String description;
  final String category;
  final DateTime date;

  /// The date exactly as stored, written back unchanged so persisting an
  /// expense never rewrites its original ISO-8601 text.
  final String dateText;

  /// [dateText] defaults to `date.toIso8601String()`. When given, it must
  /// denote the same instant as [date].
  Expense({
    required this.id,
    required this.amount,
    required this.description,
    required this.category,
    required this.date,
    String? dateText,
  }) : dateText = dateText ?? date.toIso8601String(),
       assert(
         dateText == null || DateTime.parse(dateText).isAtSameMomentAs(date),
         'dateText must denote the same instant as date',
       );

  /// A copy with the given fields changed and the same [id].
  ///
  /// [day] is a calendar day; its time of day is ignored. If it is omitted
  /// or is the same local calendar day as [date], [dateText] is kept
  /// byte-for-byte (including any `Z` or offset). Otherwise the new date is
  /// that day at this expense's local time of day, written like new
  /// expenses: local time without an offset (`DateTime.toIso8601String`).
  Expense edited({
    Money? amount,
    String? description,
    String? category,
    DateTime? day,
  }) {
    final local = date.toLocal();
    final newDate =
        day == null ||
            (day.year == local.year &&
                day.month == local.month &&
                day.day == local.day)
        ? null
        : DateTime(
            day.year,
            day.month,
            day.day,
            local.hour,
            local.minute,
            local.second,
            local.millisecond,
            local.microsecond,
          );
    return Expense(
      id: id,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      category: category ?? this.category,
      date: newDate ?? date,
      dateText: newDate == null ? dateText : null,
    );
  }

  /// Key for the exact amount in cents, written by current versions.
  static const amountCentsKey = 'amountCents';

  /// Key for the floating-point amount written by versions before cents.
  static const legacyAmountKey = 'amount';

  /// Whether [map] stores its amount in the legacy floating-point format.
  static bool isLegacyMap(Map<String, dynamic> map) =>
      !map.containsKey(amountCentsKey) && map.containsKey(legacyAmountKey);

  /// Builds an [Expense] from a decoded JSON map.
  ///
  /// Reads the exact `amountCents` field, or converts a legacy `amount`
  /// field with [moneyFromLegacyAmount]. Throws a [FormatException] if a
  /// field is missing, has the wrong type, holds an invalid amount, or both
  /// amount fields are present, so callers can treat malformed stored data
  /// as an error instead of guessing.
  factory Expense.fromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final description = map['description'];
    final category = map['category'];
    final date = map['date'];

    if (id is! String ||
        description is! String ||
        category is! String ||
        date is! String) {
      throw FormatException('Invalid expense record', map);
    }

    return Expense(
      id: id,
      amount: _amountFromMap(map),
      description: description,
      category: category,
      date: DateTime.parse(date),
      dateText: date,
    );
  }

  static Money _amountFromMap(Map<String, dynamic> map) {
    final hasCents = map.containsKey(amountCentsKey);
    final hasLegacy = map.containsKey(legacyAmountKey);
    if (hasCents && hasLegacy) {
      throw FormatException('Expense has both amount fields', map);
    }
    if (hasLegacy) {
      final legacy = map[legacyAmountKey];
      if (legacy is! num) {
        throw FormatException('Invalid legacy expense amount', map);
      }
      return moneyFromLegacyAmount(legacy);
    }
    final cents = map[amountCentsKey];
    // JSON numbers like 1250.0 decode as doubles on the VM; accept them only
    // when integral and in range, so both platforms agree.
    if (cents is! num ||
        !cents.isFinite ||
        cents < Money.minCents ||
        cents > Money.maxCents ||
        cents != cents.truncate()) {
      throw FormatException('Invalid expense amount', map);
    }
    return Money.fromCents(cents.toInt());
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      amountCentsKey: amount.cents,
      'description': description,
      'category': category,
      'date': dateText,
    };
  }

  String toJson() => json.encode(toMap());

  factory Expense.fromJson(String source) {
    final decoded = json.decode(source);
    if (decoded is! Map<String, dynamic>) {
      throw FormatException('Expected a JSON object', source);
    }
    return Expense.fromMap(decoded);
  }
}
