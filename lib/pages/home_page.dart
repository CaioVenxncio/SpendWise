import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_config.dart';
import '../app/backend.dart';
import '../app/tab_coordinator.dart';
import '../domain/money.dart';
import '../migration/json_to_drift_migration.dart';
import '../migration/migration_controller.dart';
import '../models/expense.dart';
import '../platform/platform_services.dart';
import '../presentation/app_theme.dart';
import '../presentation/breakpoints.dart';
import '../presentation/expense_order.dart';
import '../providers/expense_provider.dart';
import '../services/expense_storage.dart';
import '../widgets/brand.dart';
import '../widgets/data_actions.dart';
import '../widgets/delete_expense_dialog.dart';
import '../widgets/expense_detail.dart';
import '../widgets/expense_list.dart';
import '../widgets/migration_screen.dart';
import '../widgets/notice_banner.dart';
import '../widgets/state_views.dart';
import 'expense_detail_page.dart';
import 'expense_form_page.dart';

/// The expense workspace.
///
/// * Compact and medium widths (< 840): "Compact Hero", one column; a row
///   opens the expense in a full-screen detail page.
/// * Expanded and large widths (≥ 840): "Asymmetric Workspace", monthly
///   hero and selected-expense panel on the left (~40 %), activity on the
///   right (~60 %); a row selects the expense for the panel.
///
/// The selected expense is identified by its ID only (never by position)
/// and kept in this widget's state, so it survives resizing and reloads.
/// If it disappears, the panel says so instead of showing another one.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _selectedId;

  /// The selection was cleared because the expense was deleted here, so
  /// the panel says "Expense deleted" until something else is selected.
  bool _justDeleted = false;

  /// Focus nodes of the rows by expense ID, so focus can return to a row
  /// after Back or move to a neighbour after a delete. Rows whose ID is
  /// shared by several records get none.
  final _rowFocus = <String, FocusNode>{};
  final _addFocus = FocusNode(debugLabel: 'Add expense');

  @override
  void dispose() {
    for (final node in _rowFocus.values) {
      node.dispose();
    }
    _addFocus.dispose();
    super.dispose();
  }

  FocusNode _rowNode(String id) =>
      _rowFocus.putIfAbsent(id, () => FocusNode(debugLabel: 'Expense row'));

  /// Disposes the nodes of expenses that are gone, once their rows have
  /// been removed from the tree.
  void _pruneRowFocus(Set<String> ids) {
    if (_rowFocus.keys.every(ids.contains)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rowFocus.removeWhere((id, node) {
        if (ids.contains(id) || (node.context?.mounted ?? false)) return false;
        node.dispose();
        return true;
      });
    });
  }

  /// After the next frame, focuses the first of [nodes] that is still in
  /// the tree and can take focus; does nothing if none can.
  void _focusFirstAvailable(List<FocusNode?> nodes) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final node in nodes) {
        if (node != null &&
            (node.context?.mounted ?? false) &&
            node.canRequestFocus) {
          node.requestFocus();
          return;
        }
      }
    });
  }

  /// After [id] was deleted: focus the row that followed it in [before]
  /// (the list as shown before the delete), else the one before it, else
  /// Add expense.
  void _focusAfterDelete(List<Expense> before, String id) {
    final i = before.indexWhere((e) => e.id == id);
    _focusFirstAvailable([
      if (i >= 0 && i + 1 < before.length) _rowFocus[before[i + 1].id],
      if (i > 0) _rowFocus[before[i - 1].id],
      _addFocus,
    ]);
  }

  void _select(String id) => setState(() {
    _selectedId = id;
    _justDeleted = false;
  });

  void _clearAfterDelete() => setState(() {
    _selectedId = null;
    _justDeleted = true;
  });

  void _openAdd() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ExpenseFormPage.add()));

  void _edit(Expense expense) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => ExpenseFormPage.edit(expense)),
  );

  Future<void> _openDetail(String id) async {
    _select(id);
    final before = newestFirst(context.read<ExpenseProvider>().expenses);
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ExpenseDetailPage(expenseId: id)),
    );
    if (!mounted) return;
    if (deleted == true) {
      if (_selectedId == id) _clearAfterDelete();
      _focusAfterDelete(before, id);
    } else {
      // Back: return to the row that was opened, if it is still there.
      _focusFirstAvailable([_rowFocus[id]]);
    }
  }

  /// Returns whether [expense] was deleted. Focus moves only then; a
  /// cancelled or refused delete leaves it to the Delete button.
  Future<bool> _delete(Expense expense) async {
    final before = newestFirst(context.read<ExpenseProvider>().expenses);
    final deleted = await confirmAndDeleteExpense(context, expense);
    if (!deleted || !mounted) return deleted;
    if (_selectedId == expense.id) _clearAfterDelete();
    _focusAfterDelete(before, expense.id);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const SpendWiseWordmark(),
        actions: const [
          DataMenu(),
          SizedBox(width: AppSpacing.s),
        ],
      ),
      body: SafeArea(
        child: switch (provider.status) {
          ExpenseLoadStatus.notLoaded || ExpenseLoadStatus.loading =>
            const LoadingView(label: 'Loading expenses'),
          ExpenseLoadStatus.failed => _LoadErrorView(
            onRetry: provider.loadExpenses,
            unreadable: provider.loadError is ExpenseStorageUnreadableException,
          ),
          ExpenseLoadStatus.ready => LayoutBuilder(
            builder: (context, constraints) {
              final view = _ViewModel(context, provider, _selectedId);
              _pruneRowFocus({for (final e in view.ordered) e.id});
              return WindowSize.of(constraints.maxWidth).isWorkspace
                  ? _workspace(context, view, constraints)
                  : _compact(context, view);
            },
          ),
        },
      ),
    );
  }

  Widget _addButton(_ViewModel view, {required bool extended}) {
    final scheme = Theme.of(context).colorScheme;
    final ready = view.provider.isReady;
    // FloatingActionButton has no disabled look of its own; use the
    // Material 3 disabled colours so a paused app does not look ready.
    final background = ready ? null : scheme.onSurface.withValues(alpha: 0.12);
    final foreground = ready ? null : scheme.onSurface.withValues(alpha: 0.38);
    final onPressed = ready ? _openAdd : null;
    return extended
        // The visible label names the button; the tooltip is for pointer
        // users only, so the name is not read twice.
        ? Tooltip(
            message: 'Add expense',
            excludeFromSemantics: true,
            child: FloatingActionButton.extended(
              focusNode: _addFocus,
              heroTag: null,
              backgroundColor: background,
              foregroundColor: foreground,
              onPressed: onPressed,
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            ),
          )
        : FloatingActionButton(
            focusNode: _addFocus,
            heroTag: null,
            tooltip: 'Add expense',
            backgroundColor: background,
            foregroundColor: foreground,
            onPressed: onPressed,
            child: const Icon(Icons.add),
          );
  }

  Widget _row(_ViewModel view, Expense expense, {required bool workspace}) {
    final isDuplicate = view.provider.duplicateIds.contains(expense.id);
    return ExpenseTile(
      expense: expense,
      isDuplicate: isDuplicate,
      selected: expense.id == _selectedId && !isDuplicate,
      // Compact rows open a page; only the workspace has a selection.
      selectable: workspace,
      // A node belongs to one row; records sharing an ID cannot be opened.
      focusNode: isDuplicate ? null : _rowNode(expense.id),
      onSelect: !view.provider.isReady || isDuplicate
          ? null
          : workspace
          ? () => _select(expense.id)
          : () => _openDetail(expense.id),
    );
  }

  /// Compact Hero: summary + add, divider, activity.
  Widget _compact(BuildContext context, _ViewModel view) {
    final expenses = view.ordered;
    final header = <Widget>[
      for (final notice in view.notices) ...[
        notice,
        const SizedBox(height: AppSpacing.s),
      ],
      const SizedBox(height: AppSpacing.s),
      CompactMonthlySummary(
        total: view.total,
        now: view.now,
        addButton: _addButton(view, extended: false),
      ),
      const SizedBox(height: AppSpacing.l),
      const Divider(),
      const SizedBox(height: AppSpacing.l),
      ActivityHeader(count: expenses.length),
      const SizedBox(height: AppSpacing.s),
    ];

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: appContentMaxWidth),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.l,
            AppSpacing.s,
            AppSpacing.l,
            AppSpacing.xxl,
          ),
          itemCount: header.length + (expenses.isEmpty ? 1 : expenses.length),
          itemBuilder: (context, index) {
            if (index < header.length) return header[index];
            if (expenses.isEmpty) {
              return const _NoExpenses(
                hint: 'Add your first one with the + button.',
              );
            }
            return _row(
              view,
              expenses[index - header.length],
              workspace: false,
            );
          },
        ),
      ),
    );
  }

  /// Asymmetric Workspace: hero + selected expense | activity.
  Widget _workspace(
    BuildContext context,
    _ViewModel view,
    BoxConstraints constraints,
  ) {
    final colors = SpendWiseColors.of(context);
    final expenses = view.ordered;
    final selected = view.selected;
    final side = WindowSize.of(constraints.maxWidth) == WindowSize.expanded
        ? AppSpacing.l
        : AppSpacing.xl;
    final inner =
        (constraints.maxWidth.clamp(0, appWorkspaceMaxWidth) as double) -
        2 * side;
    // About 40 %, within readable bounds; the activity column takes the rest.
    final left = (inner * 0.4).clamp(320.0, 520.0);

    final detail = selected != null
        ? ExpenseDetailView(
            expense: selected,
            onEdit: view.editable(selected) ? () => _edit(selected) : null,
            onDelete: view.editable(selected) ? () => _delete(selected) : null,
          )
        : EmptySelection(
            reason: _selectedId != null
                ? EmptySelectionReason.missing
                : expenses.isEmpty
                ? EmptySelectionReason.noExpenses
                : _justDeleted
                ? EmptySelectionReason.deleted
                : EmptySelectionReason.noneSelected,
            onClear: () => setState(() => _selectedId = null),
          );

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: appWorkspaceMaxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(side, AppSpacing.l, side, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final notice in view.notices) ...[
                notice,
                const SizedBox(height: AppSpacing.s),
              ],
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  // Each column is one traversal group, so Tab follows the
                  // visual columns: the selected expense's actions on the
                  // left, then Add expense and the rows on the right. The
                  // order does not depend on the list's length or on which
                  // expense is selected.
                  children: [
                    SizedBox(
                      width: left,
                      child: FocusTraversalGroup(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              MonthlyHero(total: view.total, now: view.now),
                              const SizedBox(height: AppSpacing.l),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.surface,
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.large,
                                  ),
                                  border: Border.all(color: colors.divider),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(AppSpacing.xl),
                                  child: AnimatedSwitcher(
                                    // Keep the content start-aligned (the
                                    // default layout centres it).
                                    layoutBuilder: (current, previous) => Stack(
                                      alignment: AlignmentDirectional.topStart,
                                      children: [...previous, ?current],
                                    ),
                                    duration:
                                        MediaQuery.disableAnimationsOf(context)
                                        ? Duration.zero
                                        : const Duration(milliseconds: 150),
                                    child: KeyedSubtree(
                                      key: ValueKey(
                                        selected?.id ?? _selectedId,
                                      ),
                                      child: detail,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(
                      child: FocusTraversalGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ActivityHeader(
                              count: expenses.length,
                              trailing: _addButton(view, extended: true),
                            ),
                            const SizedBox(height: AppSpacing.m),
                            const Divider(),
                            Expanded(
                              child: expenses.isEmpty
                                  // In a list (unbounded height) so it sits
                                  // just under the header on tall screens.
                                  ? ListView(
                                      children: const [
                                        _NoExpenses(
                                          hint: 'Use Add expense to record your first one.',
                                        ),
                                      ],
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: AppSpacing.s,
                                      ),
                                      itemCount: expenses.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 2),
                                      itemBuilder: (context, i) => _row(
                                        view,
                                        expenses[i],
                                        workspace: true,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What both layouts show, derived once per build from the provider.
class _ViewModel {
  _ViewModel(BuildContext context, this.provider, String? selectedId)
    : ordered = newestFirst(provider.expenses),
      now = provider.now,
      notices = _notices(context, provider) {
    final matches = provider.expenses.where((e) => e.id == selectedId);
    selected = matches.length == 1 ? matches.single : null;
    try {
      total = provider.currentMonthTotal;
    } on MoneyOverflowException {
      total = null;
    }
  }

  final ExpenseProvider provider;
  final List<Expense> ordered;
  final DateTime now;
  final List<Widget> notices;
  late final Expense? selected;
  late final Money? total;

  bool editable(Expense e) =>
      provider.isReady && !provider.duplicateIds.contains(e.id);
}

class _NoExpenses extends StatelessWidget {
  const _NoExpenses({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
    child: EmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'No expenses',
      message: hint,
    ),
  );
}

/// Notices about storage, other tabs and conflicts, most urgent first.
List<Widget> _notices(BuildContext context, ExpenseProvider provider) {
  final backend = context.read<AppBackend>();
  final safety = backend.storageSafety;
  final migration = context.watch<MigrationController?>();
  final tabs = context.watch<TabCoordinator?>();
  final isJson = backend.config.backend == StorageBackend.json;

  return [
    if (provider.hasConflict)
      NoticeBanner(
        level: NoticeLevel.warning,
        text:
            'Your expenses were changed in another tab or window. '
            'Changes here are paused so nothing is overwritten.',
        actionLabel: 'Reload',
        onAction: provider.reload,
      ),
    if (safety == StorageSafety.temporary)
      const NoticeBanner(
        level: NoticeLevel.warning,
        text:
            'This browser only gave SpendWise temporary storage (for '
            'example in a private window). Everything here is lost when '
            'the tab closes. Export a backup.',
      ),
    if (safety == StorageSafety.singleTabOnly)
      const NoticeBanner(
        level: NoticeLevel.warning,
        text:
            'In this browser, storage is not coordinated between tabs. '
            'Keep SpendWise open in one tab only.',
      ),
    if (migration?.status?.status == MigrationStatus.sourceChanged)
      NoticeBanner(
        text:
            'Data in the previous storage changed after it was moved, '
            'for example in a tab with an older version. Nothing was '
            'added automatically.',
        actionLabel: 'Review',
        onAction: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const MigrationScreen()),
        ),
      ),
    if (isJson && (tabs?.migratedElsewhere ?? false))
      const NoticeBanner(
        level: NoticeLevel.warning,
        text:
            'Your expenses were moved to the new storage in another tab. '
            'Changes made here are not moved automatically. Close this '
            'tab and continue in the other one.',
      ),
    if (provider.duplicateIds.isNotEmpty)
      const NoticeBanner(
        text:
            'Some saved expenses share the same ID. They are shown '
            'unchanged but cannot be edited or deleted. Export a backup to '
            'keep a copy.',
      ),
  ];
}

class _LoadErrorView extends StatelessWidget {
  const _LoadErrorView({required this.onRetry, required this.unreadable});

  final VoidCallback onRetry;

  /// The stored data is present but damaged or inaccessible.
  final bool unreadable;

  @override
  Widget build(BuildContext context) {
    final canExport = context.read<PlatformServices>().files.isSupported;
    if (unreadable) {
      return ErrorView(
        title: 'Your saved expenses could not be read.',
        body:
            'The stored data is damaged, in an unexpected format, or could '
            'not be accessed. SpendWise has not changed or replaced it, and '
            'editing is disabled to protect it. '
            '${canExport ? 'Export the raw data and keep the file somewhere '
                      'private: it contains what was found in storage, as '
                      'found. ' : ''}'
            'SpendWise cannot repair it automatically.',
        actions: [
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
          if (canExport)
            OutlinedButton(
              onPressed: () => exportRawData(context),
              child: const Text('Export raw data'),
            ),
        ],
      );
    }
    return ErrorView(
      title: 'Could not load your saved expenses.',
      body:
          'Your stored data has not been changed. Editing is disabled '
          'until it loads successfully.',
      actions: [
        FilledButton(onPressed: onRetry, child: const Text('Retry')),
        if (canExport)
          OutlinedButton(
            onPressed: () => exportRawData(context),
            child: const Text('Export raw data'),
          ),
      ],
    );
  }
}
