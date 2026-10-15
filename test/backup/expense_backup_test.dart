import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/backup/expense_backup.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/repositories/expense_repository.dart';

Expense _e(String id, int cents, {String description = 'x'}) => Expense(
  id: id,
  amount: Money.fromCents(cents),
  description: description,
  category: 'General',
  date: DateTime(2024, 3, 1, 12, 30),
);

final _exportedAt = DateTime.utc(2026, 10, 15, 8, 30);

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

Map<String, dynamic> _json(List<Expense> expenses) =>
    json.decode(encodeBackup(expenses, exportedAt: _exportedAt))
        as Map<String, dynamic>;

Uint8List _encodeMap(Map<String, dynamic> map) => _bytes(json.encode(map));

Matcher _rejectedWith(String text) => throwsA(
  isA<BackupFormatException>().having(
    (e) => e.message,
    'message',
    contains(text),
  ),
);

void main() {
  group('encodeBackup', () {
    test(
      'writes format, version, count, exact total, checksum and records',
      () {
        final map = _json([_e('a', 1250), _e('b', 5)]);

        expect(map['format'], 'spendwise-backup');
        expect(map['formatVersion'], 1);
        expect(map['exportedAt'], '2026-10-15T08:30:00.000Z');
        expect(map['recordCount'], 2);
        expect(map['totalCents'], '1255');
        expect(map['checksum'], startsWith('sha256:'));
        expect((map['expenses'] as List).first, {
          'id': 'a',
          'amountCents': 1250,
          'description': 'x',
          'category': 'General',
          'date': '2024-03-01T12:30:00.000',
        });
      },
    );

    test('total beyond the Money range is still exact', () {
      final map = _json([_e('a', Money.maxCents), _e('b', Money.maxCents)]);
      expect(
        map['totalCents'],
        (BigInt.from(Money.maxCents) * BigInt.two).toString(),
      );
      expect(parseBackup(_encodeMap(map)).expenses, hasLength(2));
    });

    test('round-trips exactly through parseBackup', () {
      final expenses = [_e('a', 1), _e('b', -5), _e('c', Money.maxCents)];
      final parsed = parseBackup(
        _bytes(encodeBackup(expenses, exportedAt: _exportedAt)),
      );

      expect(
        parsed.expenses.map((e) => e.toMap()).toList(),
        expenses.map((e) => e.toMap()).toList(),
      );
      expect(parsed.exportedAt, _exportedAt);
      expect(parsed.identicalDuplicatesInFile, 0);
    });

    test('an empty backup is valid', () {
      expect(parseBackup(_encodeMap(_json([]))).expenses, isEmpty);
    });

    test('file names use the local date', () {
      expect(
        backupFileName(DateTime(2026, 1, 5, 23)),
        'spendwise-backup-2026-01-05.json',
      );
      expect(
        rawExportFileName(DateTime(2026, 1, 5)),
        'spendwise-raw-data-2026-01-05.json',
      );
    });
  });

  group('parseBackup rejects', () {
    test('files above the size limit before decoding', () {
      expect(
        () => parseBackup(Uint8List(maxBackupFileBytes + 1)),
        _rejectedWith('too large'),
      );
    });

    test('invalid UTF-8', () {
      expect(
        () => parseBackup(Uint8List.fromList([0xff, 0xfe, 0x00])),
        _rejectedWith('not valid JSON'),
      );
    });

    test('text that is not JSON', () {
      expect(
        () => parseBackup(_bytes('hello')),
        _rejectedWith('not valid JSON'),
      );
    });

    test('JSON that is not a SpendWise backup', () {
      expect(
        () => parseBackup(_bytes('[1,2,3]')),
        _rejectedWith('not a SpendWise backup'),
      );
      expect(
        () => parseBackup(_bytes('{"format":"other"}')),
        _rejectedWith('not a SpendWise backup'),
      );
    });

    test('a missing format version', () {
      final map = _json([_e('a', 1)])..remove('formatVersion');
      expect(
        () => parseBackup(_encodeMap(map)),
        _rejectedWith('format version'),
      );
    });

    test('a newer format version', () {
      final map = _json([_e('a', 1)])..['formatVersion'] = 2;
      expect(
        () => parseBackup(_encodeMap(map)),
        _rejectedWith('newer version'),
      );
    });

    test('an unknown older format version', () {
      final map = _json([_e('a', 1)])..['formatVersion'] = 0;
      expect(() => parseBackup(_encodeMap(map)), _rejectedWith('Unsupported'));
    });

    test('a record count that does not match', () {
      final map = _json([_e('a', 1)])..['recordCount'] = 2;
      expect(() => parseBackup(_encodeMap(map)), _rejectedWith('record count'));
    });

    test('a missing expenses list', () {
      final map = _json([_e('a', 1)])..remove('expenses');
      expect(() => parseBackup(_encodeMap(map)), _rejectedWith('incomplete'));
    });

    test('too many records', () {
      final records = List.filled(maxBackupRecords + 1, <String, dynamic>{});
      final map = _json([])
        ..['expenses'] = records
        ..['recordCount'] = records.length;
      expect(() => parseBackup(_encodeMap(map)), _rejectedWith('too many'));
    });

    test('a changed amount (checksum mismatch)', () {
      final map = _json([_e('a', 1250)]);
      ((map['expenses'] as List).first as Map)['amountCents'] = 1251;
      expect(() => parseBackup(_encodeMap(map)), _rejectedWith('checksum'));
    });

    test('a total that does not match the records', () {
      final map = _json([_e('a', 1250)])..['totalCents'] = '9999';
      expect(() => parseBackup(_encodeMap(map)), _rejectedWith('total'));
    });

    test('a numeric total (must be an exact string)', () {
      final map = _json([_e('a', 1250)])..['totalCents'] = 1250;
      expect(() => parseBackup(_encodeMap(map)), _rejectedWith('total'));
    });

    test('legacy floating-point amounts', () {
      final map = _json([_e('a', 1250)]);
      final record = (map['expenses'] as List).first as Map;
      record
        ..remove('amountCents')
        ..['amount'] = 12.5;
      expect(() => parseBackup(_encodeMap(map)), _rejectedWith('Record 1'));
    });

    test('an invalid record, naming its position only', () {
      final map = _json([_e('a', 1), _e('b', 2)]);
      ((map['expenses'] as List)[1] as Map)['date'] = 'not a date';
      expect(() => parseBackup(_encodeMap(map)), _rejectedWith('Record 2'));
    });

    test('different records sharing an ID', () {
      final bytes = _bytes(
        encodeBackup([_e('a', 1), _e('a', 2)], exportedAt: _exportedAt),
      );
      expect(() => parseBackup(bytes), _rejectedWith('same ID'));
    });

    test('error messages never contain record content', () {
      final map = _json([_e('a', 1, description: 'SECRET-PAYEE')]);
      ((map['expenses'] as List).first as Map)['amountCents'] = 'SECRET-AMOUNT';
      try {
        parseBackup(_encodeMap(map));
        fail('expected rejection');
      } on BackupFormatException catch (e) {
        expect(e.toString(), isNot(contains('SECRET')));
      }
    });
  });

  test('identical repeated records are collapsed and counted', () {
    final parsed = parseBackup(
      _bytes(
        encodeBackup([
          _e('a', 1),
          _e('a', 1),
          _e('b', 2),
        ], exportedAt: _exportedAt),
      ),
    );
    expect(parsed.expenses.map((e) => e.id), ['a', 'b']);
    expect(parsed.identicalDuplicatesInFile, 1);
  });

  group('previewImport', () {
    ParsedBackup backup(List<Expense> es) =>
        parseBackup(_bytes(encodeBackup(es, exportedAt: _exportedAt)));

    test('classifies new, already present and conflicting records', () {
      final preview = previewImport(
        backup([_e('new', 5), _e('same', 1), _e('changed', 2)]),
        [_e('same', 1), _e('changed', 999)],
      );

      expect(preview.newExpenses.map((e) => e.id), ['new']);
      expect(preview.alreadyPresent, 1);
      expect(preview.conflictingIds, ['changed']);
      expect(preview.canImport, isFalse);
    });

    test('can import when only new and identical records exist', () {
      final preview = previewImport(backup([_e('n', 5), _e('s', 1)]), [
        _e('s', 1),
      ]);
      expect(preview.canImport, isTrue);
      expect(preview.newTotal, Money.fromCents(5));
    });

    test('nothing to import when every record is present', () {
      final preview = previewImport(backup([_e('s', 1)]), [_e('s', 1)]);
      expect(preview.canImport, isFalse);
      expect(preview.conflictingIds, isEmpty);
    });

    test('an existing ID stored twice counts as a conflict', () {
      final preview = previewImport(backup([_e('d', 1)]), [
        _e('d', 1),
        _e('d', 1),
      ]);
      expect(preview.conflictingIds, ['d']);
    });

    test('a description-only difference is a conflict', () {
      final preview = previewImport(
        backup([_e('a', 1, description: 'Lunch')]),
        [_e('a', 1, description: 'Dinner')],
      );
      expect(preview.conflictingIds, ['a']);
    });

    test('newTotal is null instead of overflowing', () {
      final preview = previewImport(
        backup([_e('a', Money.maxCents), _e('b', Money.maxCents)]),
        [],
      );
      expect(preview.newTotal, isNull);
    });
  });

  group('encodeRawExport', () {
    test('wraps stored text exactly, even when invalid', () {
      const corrupt = '{"broken": [1, 2, "\u0000';
      final text = encodeRawExport(
        RawExpenseData(expenses: corrupt, legacyBackup: null),
        exportedAt: _exportedAt,
      );
      final map = json.decode(text) as Map<String, dynamic>;

      expect(map['format'], 'spendwise-raw-export');
      expect((map['storage'] as Map)['expenses'], corrupt);
      expect((map['storage'] as Map)['expenses_legacy_backup'], isNull);
    });

    test('includes the legacy backup', () {
      final map = json.decode(
        encodeRawExport(
          RawExpenseData(expenses: null, legacyBackup: '[old]'),
          exportedAt: _exportedAt,
        ),
      ) as Map<String, dynamic>;
      expect((map['storage'] as Map)['expenses_legacy_backup'], '[old]');
    });
  });
}
