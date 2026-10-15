import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_config.dart';
import '../app/backend.dart';
import '../backup/expense_backup.dart';
import '../migration/migration_controller.dart';
import '../platform/platform_services.dart';
import '../presentation/formatting.dart';
import '../providers/expense_provider.dart';
import '../providers/storage_persistence.dart';
import '../repositories/expense_repository.dart';
import 'migration_screen.dart';

/// App-bar menu for backup export, import, and storage information.
class DataMenu extends StatelessWidget {
  const DataMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    final files = context.read<PlatformServices>().files;
    final migration = context.watch<MigrationController?>();

    return PopupMenuButton<_MenuAction>(
      tooltip: 'Data options',
      onSelected: (action) => switch (action) {
        _MenuAction.export => exportBackup(context),
        _MenuAction.import => importBackup(context),
        _MenuAction.storage => showStorageInfo(context),
        _MenuAction.migration => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const MigrationScreen()),
        ),
      },
      itemBuilder: (_) => [
        if (files.isSupported) ...[
          PopupMenuItem(
            value: _MenuAction.export,
            enabled: provider.status == ExpenseLoadStatus.ready,
            child: const Text('Export backup'),
          ),
          PopupMenuItem(
            value: _MenuAction.import,
            enabled: provider.isReady,
            child: const Text('Import backup'),
          ),
        ],
        const PopupMenuItem(
          value: _MenuAction.storage,
          child: Text('Storage information'),
        ),
        if (migration != null)
          const PopupMenuItem(
            value: _MenuAction.migration,
            child: Text('Storage migration'),
          ),
      ],
    );
  }
}

enum _MenuAction { export, import, storage, migration }

Future<void> exportBackup(BuildContext context) async {
  final provider = context.read<ExpenseProvider>();
  final files = context.read<PlatformServices>().files;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final text = provider.exportBackup();
    await files.saveText(backupFileName(DateTime.now()), text);
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Backup downloaded. It contains your financial data; '
          'keep it somewhere private.',
        ),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not create the backup.')),
    );
  }
}

Future<void> exportRawData(BuildContext context) async {
  final provider = context.read<ExpenseProvider>();
  final files = context.read<PlatformServices>().files;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final text = await provider.exportRawData();
    await files.saveText(rawExportFileName(DateTime.now()), text);
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Raw data downloaded unchanged. It contains your financial data; '
          'keep it somewhere private.',
        ),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not export the raw data.')),
    );
  }
}

Future<void> importBackup(BuildContext context) async {
  final provider = context.read<ExpenseProvider>();
  final files = context.read<PlatformServices>().files;
  final persistence = context.read<StoragePersistence>();
  final messenger = ScaffoldMessenger.of(context);

  void tell(String message) =>
      messenger.showSnackBar(SnackBar(content: Text(message)));

  final PickedFile? file;
  try {
    file = await files.pickFile(maxBytes: maxBackupFileBytes);
  } on FileTooLargeException {
    tell('The file is too large to be a SpendWise backup.');
    return;
  } catch (_) {
    tell('Could not open the file.');
    return;
  }
  if (file == null || !context.mounted) return;

  final ImportPreview preview;
  try {
    preview = provider.previewBackup(file.bytes);
  } on BackupFormatException catch (e) {
    tell('Cannot import: ${e.message} Nothing was changed.');
    return;
  } on ExpenseConflictException {
    tell('Expenses changed in another tab. Reload first.');
    return;
  } catch (_) {
    tell('Cannot import this file. Nothing was changed.');
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => ImportPreviewDialog(preview: preview),
  );
  if (confirmed != true) return;

  try {
    final outcome = await provider.importBackup(preview);
    tell(
      'Imported ${outcome.added} expense${outcome.added == 1 ? '' : 's'}'
      '${outcome.alreadyPresent > 0 ? ', skipped ${outcome.alreadyPresent} already present' : ''}.',
    );
    await persistence.requestAfterUserSave();
  } on ImportConflictException {
    tell('Import stopped: some records now differ. Nothing was changed.');
  } on ExpenseConflictException {
    tell(
      'Import stopped: expenses changed in another tab. Nothing was changed.',
    );
  } catch (_) {
    tell('Import failed. Nothing was changed.');
  }
}

/// Shows what an import would do and asks for confirmation.
class ImportPreviewDialog extends StatelessWidget {
  const ImportPreviewDialog({super.key, required this.preview});

  final ImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final backup = preview.backup;
    final total = preview.newTotal;
    final exported = backup.exportedAt?.toLocal().toString().split('.')[0];
    final lines = <String>[
      if (exported != null) 'Backup created: $exported',
      'Records in file: ${backup.expenses.length + backup.identicalDuplicatesInFile}',
      'New expenses: ${preview.newExpenses.length}'
          '${total != null && preview.newExpenses.isNotEmpty ? ' (${formatMoney(total)})' : ''}',
      'Already present (skipped): ${preview.alreadyPresent}',
      if (backup.identicalDuplicatesInFile > 0)
        'Repeated records in file (counted once): '
            '${backup.identicalDuplicatesInFile}',
    ];
    final conflicts = preview.conflictingIds;

    return AlertDialog(
      semanticLabel: 'Import backup',
      title: const Text('Import backup'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines) Text(line),
            const SizedBox(height: 12),
            if (conflicts.isNotEmpty)
              Text(
                'Import blocked: ${conflicts.length} record'
                '${conflicts.length == 1 ? '' : 's'} in the backup '
                '${conflicts.length == 1 ? 'has' : 'have'} the same ID as an '
                'existing expense but different content. Existing expenses '
                'are never overwritten. Nothing will be changed.',
              )
            else if (preview.newExpenses.isEmpty)
              const Text('Nothing to import: all records are already present.')
            else
              const Text(
                'New expenses will be added. Existing expenses will not be '
                'changed.',
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(preview.canImport ? 'Cancel' : 'Close'),
        ),
        if (preview.canImport)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Import ${preview.newExpenses.length} '
              'expense${preview.newExpenses.length == 1 ? '' : 's'}',
            ),
          ),
      ],
    );
  }
}

Future<void> showStorageInfo(BuildContext context) async {
  final persistence = context.read<StoragePersistence>();
  await persistence.refresh();
  if (!context.mounted) return;
  final text = switch (persistence.status) {
    PersistenceStatus.persisted =>
      'Your browser reports this site\'s storage as persistent, so it should '
          'not clear it automatically when space runs low. It can still be '
          'removed, for example when site data is cleared.',
    PersistenceStatus.notPersisted =>
      'Your browser treats this site\'s storage as best-effort: it may clear '
          'it, for example when disk space runs low or under its privacy '
          'rules.',
    PersistenceStatus.unsupported ||
    null => 'This browser does not report whether storage is persistent.',
  };
  final backend = context.read<AppBackend>();
  final report = backend.storageReport;
  final where = backend.config.backend == StorageBackend.json
      ? 'Storage: browser local storage (JSON).'
      : 'Storage: SQLite database'
            '${report == null ? '' : ' (browser mode: ${report.implementation})'}. '
            '${describeStorageMode(report?.implementation)}';
  final safety = switch (backend.storageSafety) {
    StorageSafety.temporary =>
      '\n\nWarning: this storage is temporary. Everything is lost when the '
          'tab closes.',
    StorageSafety.singleTabOnly =>
      '\n\nWarning: storage is not coordinated between tabs here. Use one '
          'tab only.',
    StorageSafety.unknown =>
      '\n\nWarning: this browser storage mode is not recognised, so moving '
          'data into it is disabled.',
    StorageSafety.ok || StorageSafety.native => '',
  };
  final tabs = backend.config.backend == StorageBackend.json
      ? '\n\nTabs running this version coordinate their changes; a tab '
            'running an older version may not.'
      : '\n\nA tab still running an older version of SpendWise keeps using '
            'the previous storage. Changes made there are not moved '
            'automatically; SpendWise shows a notice when it detects them. '
            'Going back to the previous storage would not remove expenses '
            'deleted here.';
  final test = backend.config.usesRealData
      ? ''
      : '\n\nTest data set: ${backend.config.namespace}.';
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      semanticLabel: 'Storage information',
      title: const Text('Storage information'),
      content: SingleChildScrollView(
        child: Text(
          'Your expenses are stored only in this browser, on this device. '
          '$where $text$safety$tabs$test\n\nExport a backup regularly to '
          'keep a copy.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
