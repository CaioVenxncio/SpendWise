import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/app_config.dart';
import 'package:spendwise/app/backend.dart';
import 'package:spendwise/backup/expense_backup.dart';
import 'package:spendwise/data/drift/connection.dart';
import 'package:spendwise/migration/json_to_drift_migration.dart';
import 'package:spendwise/migration/migration_controller.dart';
import 'package:spendwise/platform/platform_services.dart';

import '../support/fake_expense_storage.dart';
import '../support/fake_platform_services.dart';

const _config = AppConfig(backend: StorageBackend.drift, namespace: 'unit');

String _rec(String id, String amount) =>
    '{"id":"$id",$amount,"description":"d$id","category":"c",'
    '"date":"2026-10-01T00:00:00.000"}';

class _FailingFiles extends FakeFileTransfer {
  @override
  Future<void> saveText(
    String fileName,
    String text, {
    String mimeType = 'application/json',
  }) async => throw StateError('download blocked');
}

Future<(MigrationController, AppBackend, FakeExpenseStorage)> _controller(
  String? source, {
  WebStorageReport? report,
}) async {
  final storage = FakeExpenseStorage(data: source);
  final backend = await AppBackend.openDrift(
    config: _config,
    platform: fakePlatform(),
    jsonStorage: storage,
    openExecutor: (name, onResult) {
      if (report != null) onResult(report);
      return NativeDatabase.memory();
    },
    clock: () => DateTime(2026, 10, 15),
  );
  final c = MigrationController(backend, clock: () => DateTime(2026, 10, 15));
  await c.refresh();
  return (c, backend, storage);
}

void main() {
  test('migration needs pending records, safe storage, and a confirmed '
      'backup of exactly this data', () async {
    final (c, backend, _) = await _controller(
      '[${_rec('a', '"amount":12.5')}]',
    );
    addTearDown(backend.dispose);
    final files = FakeFileTransfer();

    expect(c.hasPendingRecords, isTrue);
    expect(c.canMigrate, isFalse);

    c.setBackupConfirmed(true); // ignored: nothing offered yet
    expect(c.backupConfirmed, isFalse);

    expect(
      await c.savePreMigrationBackup(files),
      BackupSaveResult.handedToBrowser,
    );
    expect(c.backupOffered, isTrue);
    expect(c.canMigrate, isFalse); // offered is not confirmed

    c.setBackupConfirmed(true);
    expect(c.canMigrate, isTrue);

    final backup = parseBackup(
      Uint8List.fromList(utf8.encode(files.saved.single.text)),
    );
    expect(backup.expenses.single.amount.cents, 1250);
  });

  test('a failed download is not treated as a backup', () async {
    final (c, backend, _) = await _controller(
      '[${_rec('a', '"amountCents":1')}]',
    );
    addTearDown(backend.dispose);

    expect(
      await c.savePreMigrationBackup(_FailingFiles()),
      BackupSaveResult.failed,
    );
    expect(c.backupOffered, isFalse);
    c.setBackupConfirmed(true);
    expect(c.canMigrate, isFalse);
  });

  test('a changed source resets the confirmation on refresh', () async {
    final (c, backend, storage) = await _controller(
      '[${_rec('a', '"amountCents":1')}]',
    );
    addTearDown(backend.dispose);
    await c.savePreMigrationBackup(FakeFileTransfer());
    c.setBackupConfirmed(true);
    expect(c.canMigrate, isTrue);

    storage.data =
        '[${_rec('a', '"amountCents":1')},${_rec('b', '"amountCents":2')}]';
    await c.refresh();

    expect(c.backupOffered, isFalse);
    expect(c.backupConfirmed, isFalse);
    expect(c.canMigrate, isFalse);
  });

  test('blocked sources offer no backup and no migration', () async {
    final (c, backend, _) = await _controller(
      '[${_rec('a', '"amountCents":1')},${_rec('a', '"amountCents":2')}]',
    );
    addTearDown(backend.dispose);
    final files = FakeFileTransfer();

    expect(c.status!.blockReason, MigrationBlockReason.conflictingDuplicateIds);
    expect(await c.savePreMigrationBackup(files), BackupSaveResult.failed);
    expect(files.saved, isEmpty);
    expect(c.canMigrate, isFalse);
  });

  for (final mode in ['unsafeIndexedDb', 'inMemory', 'futureMode']) {
    test(
      '$mode storage refuses migration even with a confirmed backup',
      () async {
        final (c, backend, _) = await _controller(
          '[${_rec('a', '"amountCents":1')}]',
          report: (implementation: mode, missing: const []),
        );
        addTearDown(backend.dispose);
        await c.savePreMigrationBackup(FakeFileTransfer());
        c.setBackupConfirmed(true);

        expect(c.storageAllowsMigration, isFalse);
        expect(c.canMigrate, isFalse);
        expect(await c.migrate(), isNull);
      },
    );
  }

  test('a completed migration clears the confirmation', () async {
    final (c, backend, _) = await _controller(
      '[${_rec('a', '"amountCents":1')}]',
    );
    addTearDown(backend.dispose);
    await c.savePreMigrationBackup(FakeFileTransfer());
    c.setBackupConfirmed(true);

    final result = await c.migrate();

    expect(result!.status, MigrationStatus.completed);
    expect(c.backupConfirmed, isFalse);
    expect(c.canMigrate, isFalse);
  });

  test('default platform services carry a no-op tab channel', () {
    expect(fakePlatform().tabs, isA<NoTabChannel>());
  });
}
