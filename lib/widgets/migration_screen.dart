import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/backend.dart';
import '../backup/expense_backup.dart';
import '../domain/money.dart';
import '../migration/json_to_drift_migration.dart';
import '../migration/migration_controller.dart';
import '../platform/platform_services.dart';
import '../presentation/app_theme.dart';
import '../presentation/formatting.dart';
import '../providers/expense_provider.dart';
import 'notice_banner.dart';

/// Lets the user review and run the JSON → SQLite migration.
///
/// Shown before the app when a migration is needed ([onContinue] set), or
/// from the menu to review a changed source.
class MigrationScreen extends StatelessWidget {
  const MigrationScreen({super.key, this.onContinue});

  /// Called when the user may continue to the app.
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<MigrationController>();
    final running = c.phase == MigrationPhase.running;

    return PopScope(
      canPop: !running,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Move expenses to new storage'),
          automaticallyImplyLeading: onContinue == null && !running,
        ),
        body: SafeArea(
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: _sidePadding(context),
              vertical: AppSpacing.l,
            ),
            children: [
              _StorageWarning(safety: c.storageSafety),
              Semantics(
                liveRegion: true,
                child: switch (c.phase) {
                  MigrationPhase.checking => const _Busy(
                    'Checking your saved expenses…',
                  ),
                  MigrationPhase.running => const _Busy(
                    'Moving your expenses. Keep this tab open; editing is '
                    'paused until this finishes.',
                  ),
                  MigrationPhase.error => const _Message(
                    title: 'Could not check your data',
                    body:
                        'Nothing was changed. Your original data is untouched. '
                        'Try again, or export the original data.',
                  ),
                  MigrationPhase.finished => _Outcome(c.outcome!),
                  MigrationPhase.ready => _Preview(c.status!),
                },
              ),
              if (c.storageSafety != StorageSafety.native)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Storage mode: ${describeStorageMode(c.storageImplementation)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (c.hasPendingRecords && c.storageAllowsMigration) ...[
                const SizedBox(height: 16),
                _OtherTabs(controller: c),
                const SizedBox(height: 12),
                _BackupSteps(controller: c),
              ],
              const SizedBox(height: 16),
              _Actions(controller: c, onContinue: onContinue),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps the text column at most [appFormMaxWidth] wide on large screens.
double _sidePadding(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  final extra = (width - appFormMaxWidth - 2 * AppSpacing.l) / 2;
  return AppSpacing.l + (extra > 0 ? extra : 0);
}

class _Busy extends StatelessWidget {
  const _Busy(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const CircularProgressIndicator(),
      const SizedBox(width: 16),
      Expanded(child: Text(text)),
    ],
  );
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(body),
    ],
  );
}

String _money(BigInt? cents) {
  if (cents == null) return '';
  if (cents.abs() > BigInt.from(Money.maxCents)) return '';
  return ' (${formatMoney(Money.fromCents(cents.toInt()))})';
}

List<String> _counts(MigrationResult r) => [
  'Records in saved data: ${r.sourceRecords}',
  'To move: ${r.newRecords}${_money(r.newTotalCents)}',
  if (r.alreadyPresent > 0)
    'Already in new storage (skipped): ${r.alreadyPresent}',
  if (r.duplicatesCollapsed > 0)
    'Exact repeats counted once: ${r.duplicatesCollapsed}',
  if (r.conflictingIds.isNotEmpty)
    'Conflicting records: ${r.conflictingIds.length}',
];

String _blockedText(MigrationBlockReason reason) => switch (reason) {
  MigrationBlockReason.invalidSource =>
    'Some saved data cannot be read exactly (for example an amount with '
        'more than two decimals, or damaged data). Nothing will be guessed or '
        'rounded, so nothing can be moved. Export the original data to keep '
        'a copy.',
  MigrationBlockReason.conflictingDuplicateIds =>
    'Some saved expenses share an ID but have different content. It is not '
        'clear which one is right, so nothing can be moved. Export the '
        'original data to keep a copy.',
  MigrationBlockReason.targetConflict =>
    'Some expenses already in the new storage have the same ID as saved '
        'expenses but different content. Nothing is overwritten, so nothing '
        'can be moved.',
};

class _Preview extends StatelessWidget {
  const _Preview(this.r);

  final MigrationResult r;

  @override
  Widget build(BuildContext context) {
    final reason = r.blockReason;
    if (reason != null) {
      return _Message(
        title: r.status == MigrationStatus.sourceChanged
            ? 'Saved data changed and cannot be added'
            : 'Your expenses cannot be moved',
        body: '${_blockedText(reason)}\n\n${_counts(r).join('\n')}',
      );
    }
    return switch (r.status) {
      MigrationStatus.alreadyMigrated => const _Message(
        title: 'Already moved',
        body:
            'Your saved expenses are already in the new storage. Nothing '
            'needs to be done.',
      ),
      MigrationStatus.sourceChanged => _Message(
        title: 'Saved data changed after the move',
        body:
            'The data in the previous storage changed after it was moved, '
            'for example in a tab running an older version of SpendWise. '
            'You can add the new records. Records that differ from ones '
            'already moved are never overwritten, and nothing is deleted.'
            '\n\n${_counts(r).join('\n')}',
      ),
      MigrationStatus.notStarted when r.sourceRecords == 0 => const _Message(
        title: 'Nothing to move',
        body: 'There are no saved expenses in the previous storage.',
      ),
      _ => _Message(
        title: 'Ready to move your expenses',
        body:
            'Your expenses will be copied to the new storage and checked. '
            'The original data stays where it is, unchanged, and a copy is '
            'kept with the new storage.\n\n${_counts(r).join('\n')}',
      ),
    };
  }
}

class _Outcome extends StatelessWidget {
  const _Outcome(this.r);

  final MigrationResult r;

  @override
  Widget build(BuildContext context) => switch (r.status) {
    MigrationStatus.completed => _Message(
      title: 'Expenses moved and verified',
      body:
          'Moved ${r.newRecords} expense${r.newRecords == 1 ? '' : 's'}'
          '${_money(r.newTotalCents)}. Count, order and amounts were checked '
          'before saving.'
          '${r.alreadyPresent > 0 ? '\nAlready present: ${r.alreadyPresent}.' : ''}'
          '${r.duplicatesCollapsed > 0 ? '\nExact repeats counted once: ${r.duplicatesCollapsed}.' : ''}'
          '\n\nThe original data was not changed. Note: if you ever go back '
          'to the previous storage, expenses you delete from now on would '
          'reappear there.',
    ),
    MigrationStatus.alreadyMigrated => const _Message(
      title: 'Already moved',
      body:
          'This data was already moved, for example in another tab. Nothing '
          'was added twice.',
    ),
    MigrationStatus.sourceChanged => const _Message(
      title: 'Saved data changed',
      body:
          'The saved data changed while you were reviewing it. Nothing was '
          'moved. Review it again.',
    ),
    MigrationStatus.blocked => _Message(
      title: 'Nothing was moved',
      body: _blockedText(r.blockReason!),
    ),
    _ => const _Message(
      title: 'Moving failed',
      body:
          'Nothing was changed: the move is all-or-nothing and was undone. '
          'Your original data is untouched. You can try again.',
    ),
  };
}

class _StorageWarning extends StatelessWidget {
  const _StorageWarning({required this.safety});

  final StorageSafety safety;

  @override
  Widget build(BuildContext context) {
    final text = switch (safety) {
      StorageSafety.temporary =>
        'This browser only offers temporary storage (for example in a '
            'private window). Anything saved here is lost when the tab '
            'closes, so moving is disabled.',
      StorageSafety.singleTabOnly =>
        'In this browser the new storage is not coordinated between tabs, '
            'so moving is disabled: another tab could interfere with it.',
      StorageSafety.unknown =>
        'This browser storage mode is not recognised, so moving is '
            'disabled.',
      StorageSafety.ok || StorageSafety.native => null,
    };
    if (text == null) return const SizedBox.shrink();
    return NoticeBanner(level: NoticeLevel.error, text: text);
  }
}

/// Warns about other open tabs. Only tabs of this version are visible.
class _OtherTabs extends StatelessWidget {
  const _OtherTabs({required this.controller});

  final MigrationController controller;

  @override
  Widget build(BuildContext context) {
    final others = controller.otherTabs;
    return NoticeBanner(
      level: others.isEmpty ? NoticeLevel.info : NoticeLevel.warning,
      text: others.isEmpty
          ? 'Close any other SpendWise tabs before moving. Tabs running '
                'an older version cannot be detected; if one is open, '
                'changes made there are noticed afterwards, never merged '
                'silently.'
          : 'SpendWise is open in ${others.length} other '
                'tab${others.length == 1 ? '' : 's'} '
                '(${others.map((t) => t.backend == 'json' ? 'previous storage' : 'new storage').toSet().join(', ')}). '
                'Close ${others.length == 1 ? 'it' : 'them'} before '
                'moving. Tabs running an older version cannot be '
                'detected.',
    );
  }
}

/// Step 1 and 2: backup file, then the user's confirmation.
class _BackupSteps extends StatelessWidget {
  const _BackupSteps({required this.controller});

  final MigrationController controller;

  Future<void> _download(BuildContext context) async {
    final files = context.read<PlatformServices>().files;
    final messenger = ScaffoldMessenger.of(context);
    final result = await controller.savePreMigrationBackup(files);
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (result) {
          BackupSaveResult.handedToBrowser =>
            'Backup file created. Check that your browser saved it.',
          BackupSaveResult.sourceChanged =>
            'Your saved data changed. It was checked again; review it and '
                'create a new backup.',
          BackupSaveResult.failed => 'Could not create the backup file.',
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final name = c.backupFileName;
    final canDownload =
        context.read<PlatformServices>().files.isSupported &&
        c.phase == MigrationPhase.ready;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step 1: save a backup',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        const Text(
          'The backup is a file with all your expenses in it. It contains '
          'personal financial information: keep it private, and do not '
          'share or upload it. You can import it again if anything goes '
          'wrong.',
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: canDownload ? () => _download(context) : null,
          icon: const Icon(Icons.download),
          label: Text(name == null ? 'Download backup' : 'Download again'),
        ),
        if (name != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Offered as "$name". SpendWise cannot tell whether or where '
              'your browser stored it.',
            ),
          ),
        const SizedBox(height: 12),
        Text('Step 2: confirm', style: Theme.of(context).textTheme.titleSmall),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: c.backupConfirmed,
          onChanged: name == null
              ? null
              : (v) => c.setBackupConfirmed(v ?? false),
          title: const Text(
            'I have saved the backup file and know where to find it.',
          ),
        ),
        Text('Step 3: move', style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.controller, required this.onContinue});

  final MigrationController controller;
  final VoidCallback? onContinue;

  Future<void> _confirmAndMigrate(BuildContext context) async {
    final s = controller.status!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move expenses?'),
        content: Text(
          'Move ${s.newRecords} expense${s.newRecords == 1 ? '' : 's'}'
          '${_money(s.newTotalCents)} to the new storage. The original data is '
          'kept unchanged. You can still cancel now.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Move'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // Looked up before awaiting; absent before the app is shown.
    final expenses = Provider.of<ExpenseProvider?>(context, listen: false);
    final result = await controller.migrate();
    if (result?.status == MigrationStatus.completed) {
      // The open expense list must show the rows just added.
      await expenses?.reload();
    }
  }

  Future<void> _export(
    BuildContext context,
    Future<String> Function() build,
    String name,
  ) async {
    final files = context.read<PlatformServices>().files;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await files.saveText(name, await build());
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Exported. The file contains your financial data; keep it '
            'somewhere private.',
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not export the data.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final busy =
        c.phase == MigrationPhase.running || c.phase == MigrationPhase.checking;
    final canExport = context.read<PlatformServices>().files.isSupported;
    final now = DateTime.now();
    final s = c.status;
    final pending = c.hasPendingRecords;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (pending && c.storageAllowsMigration)
          FilledButton(
            // Disabled until a backup of exactly this data is confirmed.
            onPressed: c.canMigrate ? () => _confirmAndMigrate(context) : null,
            child: Text(
              s!.status == MigrationStatus.sourceChanged
                  ? 'Add ${s.newRecords} new expense${s.newRecords == 1 ? '' : 's'}'
                  : 'Move ${s.newRecords} expense${s.newRecords == 1 ? '' : 's'}',
            ),
          ),
        if (onContinue != null && c.mayOpenApp && !busy)
          FilledButton(onPressed: onContinue, child: const Text('Continue')),
        if (!busy)
          OutlinedButton(
            onPressed: c.refresh,
            child: const Text('Check again'),
          ),
        if (canExport)
          OutlinedButton(
            onPressed: busy
                ? null
                : () => _export(
                    context,
                    c.exportJsonSource,
                    rawExportFileName(now),
                  ),
            child: const Text('Export original data'),
          ),
        if (canExport && c.snapshotCount > 0)
          OutlinedButton(
            onPressed: busy
                ? null
                : () => _export(
                    context,
                    c.exportSnapshots,
                    snapshotExportFileName(now),
                  ),
            child: const Text('Export migration snapshots'),
          ),
      ],
    );
  }
}
