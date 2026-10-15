import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/money.dart';
import '../models/expense.dart';
import '../repositories/expense_repository.dart';
import '../services/expense_storage.dart';

/// Backup file identifier.
const backupFormat = 'spendwise-backup';

/// Version of the backup layout written by this app.
const backupFormatVersion = 1;

/// Largest backup file that is read at all.
const maxBackupFileBytes = 5 * 1024 * 1024;

/// Most records accepted in one backup.
const maxBackupRecords = 50000;

/// Why a backup file was rejected. Messages never include file content.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => 'BackupFormatException: $message';
}

/// SHA-256 over the canonical encoding of [expenses].
String backupChecksum(List<Expense> expenses) =>
    'sha256:${sha256.convert(utf8.encode(encodeExpenses(expenses)))}';

/// Builds a backup file of [expenses].
///
/// The total is written as a decimal string so it is exact even beyond the
/// range of a JSON number.
String encodeBackup(List<Expense> expenses, {required DateTime exportedAt}) {
  final total = expenses.fold<BigInt>(
    BigInt.zero,
    (sum, e) => sum + BigInt.from(e.amount.cents),
  );
  return const JsonEncoder.withIndent('  ').convert({
    'format': backupFormat,
    'formatVersion': backupFormatVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'recordCount': expenses.length,
    'totalCents': total.toString(),
    'checksum': backupChecksum(expenses),
    'expenses': expenses.map((e) => e.toMap()).toList(),
  });
}

/// File name for a backup made at [time], e.g.
/// `spendwise-backup-2026-10-15.json`.
String backupFileName(DateTime time) => 'spendwise-backup-${_date(time)}.json';

String rawExportFileName(DateTime time) =>
    'spendwise-raw-data-${_date(time)}.json';

String preMigrationBackupFileName(DateTime time) =>
    'spendwise-pre-migration-backup-${_date(time)}.json';

String snapshotExportFileName(DateTime time) =>
    'spendwise-migration-snapshots-${_date(time)}.json';

String _date(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-'
    '${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

/// Wraps undecoded stored data in a JSON envelope. Works for any content,
/// including data the app cannot read.
String encodeRawExport(RawExpenseData raw, {required DateTime exportedAt}) =>
    const JsonEncoder.withIndent('  ').convert({
      'format': 'spendwise-raw-export',
      'formatVersion': 1,
      'exportedAt': exportedAt.toUtc().toIso8601String(),
      'note':
          'Unmodified stored data, for recovery. Values are the exact '
          'stored text and may not be valid.',
      'storage': {
        SharedPreferencesExpenseStorage.storageKey: raw.expenses,
        SharedPreferencesExpenseStorage.legacyBackupKey: raw.legacyBackup,
      },
      // Only when a value could not be read (its "storage" entry is null).
      if (raw.unreadable.isNotEmpty) ...{
        'unreadableNote':
            'SpendWise could not read the values listed under "unreadable" '
            'and changed nothing. "browserStorageValue" is the exact text '
            'found in browser storage under "browserStorageKey", in the '
            "storage layer's own encoding (not decoded). If "
            '"exactValueIncluded" is false, the value could not be '
            'retrieved and is not in this file.',
        'unreadable': {
          for (final MapEntry(:key, :value) in raw.unreadable.entries)
            key: {
              'browserStorageKey': value.platformKey,
              'reason': value.reason.name,
              'exactValueIncluded': value.exactValue != null,
              'browserStorageValue': value.exactValue,
            },
        },
      },
    });

/// A validated backup file.
class ParsedBackup {
  ParsedBackup({
    required this.expenses,
    required this.exportedAt,
    required this.identicalDuplicatesInFile,
  });

  /// Records in file order, with exact duplicates removed.
  final List<Expense> expenses;

  final DateTime? exportedAt;

  /// Records that repeated an earlier record exactly (same ID and content)
  /// and were therefore counted once.
  final int identicalDuplicatesInFile;
}

/// Validates [bytes] as a backup file without touching app data.
///
/// Throws [BackupFormatException] unless the file is a supported backup,
/// within the size and record limits, with a matching record count and
/// checksum, and every record valid. Records repeating an ID with different
/// content are rejected; exact repeats are collapsed and counted.
ParsedBackup parseBackup(Uint8List bytes) {
  if (bytes.length > maxBackupFileBytes) {
    throw const BackupFormatException('The file is too large.');
  }
  final Object? root;
  try {
    root = json.decode(utf8.decode(bytes));
  } on FormatException {
    throw const BackupFormatException('The file is not valid JSON text.');
  }
  if (root is! Map<String, dynamic> || root['format'] != backupFormat) {
    throw const BackupFormatException('The file is not a SpendWise backup.');
  }
  final version = root['formatVersion'];
  if (version is! int) {
    throw const BackupFormatException('The backup has no format version.');
  }
  if (version > backupFormatVersion) {
    throw const BackupFormatException(
      'The backup was made by a newer version of SpendWise.',
    );
  }
  if (version != backupFormatVersion) {
    throw const BackupFormatException('Unsupported backup format version.');
  }

  final records = root['expenses'];
  final count = root['recordCount'];
  if (records is! List || count is! int) {
    throw const BackupFormatException('The backup is incomplete.');
  }
  if (records.length > maxBackupRecords) {
    throw const BackupFormatException('The backup has too many records.');
  }
  if (records.length != count) {
    throw const BackupFormatException(
      'The record count does not match the records in the file.',
    );
  }

  final expenses = <Expense>[];
  for (var i = 0; i < records.length; i++) {
    final item = records[i];
    if (item is! Map<String, dynamic> ||
        !item.containsKey(Expense.amountCentsKey)) {
      throw BackupFormatException('Record ${i + 1} is invalid.');
    }
    try {
      expenses.add(Expense.fromMap(item));
    } on FormatException {
      throw BackupFormatException('Record ${i + 1} is invalid.');
    }
  }

  if (root['checksum'] != backupChecksum(expenses)) {
    throw const BackupFormatException(
      'The checksum does not match: the file was changed or damaged.',
    );
  }
  final total = root['totalCents'];
  final expectedTotal = expenses.fold<BigInt>(
    BigInt.zero,
    (sum, e) => sum + BigInt.from(e.amount.cents),
  );
  if (total is! String || BigInt.tryParse(total) != expectedTotal) {
    throw const BackupFormatException('The total does not match the records.');
  }

  final byId = <String, Expense>{};
  final unique = <Expense>[];
  var identical = 0;
  for (final e in expenses) {
    final earlier = byId[e.id];
    if (earlier == null) {
      byId[e.id] = e;
      unique.add(e);
    } else if (sameExpense(earlier, e)) {
      identical++;
    } else {
      throw const BackupFormatException(
        'The backup contains different records with the same ID.',
      );
    }
  }

  final exportedAt = root['exportedAt'];
  return ParsedBackup(
    expenses: unique,
    exportedAt: exportedAt is String ? DateTime.tryParse(exportedAt) : null,
    identicalDuplicatesInFile: identical,
  );
}

/// What importing a backup into the current expenses would do.
class ImportPreview {
  ImportPreview({
    required this.backup,
    required this.newExpenses,
    required this.alreadyPresent,
    required this.conflictingIds,
  });

  final ParsedBackup backup;

  /// Records that would be added.
  final List<Expense> newExpenses;

  /// Records identical to an existing expense; they would be skipped.
  final int alreadyPresent;

  /// IDs whose backup record differs from the existing expense. Any
  /// conflict blocks the whole import.
  final List<String> conflictingIds;

  bool get canImport => conflictingIds.isEmpty && newExpenses.isNotEmpty;

  /// Exact total of [newExpenses], or `null` if it exceeds [Money]'s range.
  Money? get newTotal {
    try {
      return Money.sum(newExpenses.map((e) => e.amount));
    } on MoneyOverflowException {
      return null;
    }
  }
}

/// Compares [backup] with [current] without changing anything.
ImportPreview previewImport(ParsedBackup backup, List<Expense> current) {
  final counts = <String, int>{};
  final byId = <String, Expense>{};
  for (final e in current) {
    counts[e.id] = (counts[e.id] ?? 0) + 1;
    byId.putIfAbsent(e.id, () => e);
  }
  final newExpenses = <Expense>[];
  final conflicts = <String>[];
  var alreadyPresent = 0;
  for (final e in backup.expenses) {
    final existing = byId[e.id];
    if (existing == null) {
      newExpenses.add(e);
    } else if (counts[e.id] == 1 && sameExpense(existing, e)) {
      alreadyPresent++;
    } else {
      conflicts.add(e.id);
    }
  }
  return ImportPreview(
    backup: backup,
    newExpenses: newExpenses,
    alreadyPresent: alreadyPresent,
    conflictingIds: conflicts,
  );
}
