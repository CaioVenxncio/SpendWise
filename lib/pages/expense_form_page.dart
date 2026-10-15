import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/calendar.dart';
import '../models/expense.dart';
import '../presentation/app_theme.dart';
import '../presentation/formatting.dart';
import '../providers/expense_provider.dart';
import '../providers/storage_persistence.dart';
import '../repositories/expense_repository.dart';
import '../validation/expense_form_baseline.dart';
import '../widgets/brand.dart';
import '../widgets/notice_banner.dart';

/// One form for adding a new expense and editing a stored one.
///
/// Edits go through [ExpenseProvider.updateExpense] with the record as it
/// was opened, so a record changed or deleted elsewhere is never
/// overwritten. Input stays in the form until it is saved or the user
/// chooses to discard it.
class ExpenseFormPage extends StatefulWidget {
  /// A form for a new expense.
  const ExpenseFormPage.add({super.key}) : original = null;

  /// A form editing [expense], exactly as shown in the list.
  const ExpenseFormPage.edit(Expense expense, {super.key}) : original = expense;

  /// The record being edited; `null` when adding.
  final Expense? original;

  @override
  State<ExpenseFormPage> createState() => _ExpenseFormPageState();
}

/// Why the last save attempt did not go through, if it needs a notice.
enum _SaveProblem { stale, duplicate }

class _ExpenseFormPageState extends State<ExpenseFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final ExpenseFormBaseline _baseline;
  late final TextEditingController _amount;
  late final TextEditingController _description;
  final _amountField = GlobalKey<FormFieldState<String>>();
  final _descriptionField = GlobalKey<FormFieldState<String>>();
  final _amountFocus = FocusNode();
  final _descriptionFocus = FocusNode();
  late String _category;
  late DateTime _date;
  bool _saving = false;
  bool _confirmingDiscard = false;
  _SaveProblem? _problem;

  bool get _editing => _baseline.isEditing;

  ExpenseFormValues get _values => ExpenseFormValues(
    amountText: _amount.text,
    description: _description.text,
    category: _category,
    date: _date,
  );

  bool get _dirty => _baseline.isDirty(_values);

  @override
  void initState() {
    super.initState();
    final original = widget.original;
    _baseline = original == null
        ? ExpenseFormBaseline.add(DateTime.now())
        : ExpenseFormBaseline.edit(original);
    _amount = TextEditingController(text: _baseline.amountText)
      ..addListener(_onChanged);
    _description = TextEditingController(text: _baseline.description)
      ..addListener(_onChanged);
    _category = _baseline.category;
    _date = _baseline.date;
  }

  /// Rebuilds so [PopScope] knows whether leaving would lose input.
  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _amountFocus.dispose();
    _descriptionFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = localCalendarDate(DateTime.now());
    final shown = localCalendarDate(_date);
    // Wide enough for any stored date (imports may predate 2000 or lie in
    // the future), so the picker never rejects the record's own date.
    final first = DateTime(2000);
    final date = await showDatePicker(
      context: context,
      initialDate: shown,
      firstDate: shown.isBefore(first) ? shown : first,
      lastDate: shown.isAfter(today) ? shown : today,
    );
    if (!mounted || date == null) return;
    setState(() => _date = date);
  }

  Future<void> _submit() async {
    if (_saving) return;
    final provider = context.read<ExpenseProvider>();
    if (!provider.isReady) return;
    if (!_formKey.currentState!.validate()) {
      _focusFirstError();
      return;
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final persistence = context.read<StoragePersistence>();
    final values = _values;

    if (_editing && !_baseline.isDirty(values)) {
      // Nothing changed: leave without writing.
      navigator.pop();
      return;
    }

    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      if (_editing) {
        await provider.updateExpense(
          _baseline.original!,
          _baseline.replacement(values),
        );
      } else {
        await provider.addExpense(
          _baseline.newExpense(const Uuid().v4(), values),
        );
      }
    } on ExpenseConflictException {
      _failed(_SaveProblem.stale);
      return;
    } on ExpenseNotFoundException {
      _failed(_SaveProblem.stale);
      return;
    } on DuplicateExpenseIdException {
      _failed(_SaveProblem.duplicate);
      return;
    } catch (_) {
      _failed(null);
      messenger.showSnackBar(
        // Wording kept from the add form; the input stays in the form.
        const SnackBar(content: Text('Could not save expense. Try again.')),
      );
      return;
    }
    unawaited(persistence.requestAfterUserSave());
    if (!mounted) return;
    // Navigator.pop ignores PopScope: the input was saved.
    navigator.pop();
  }

  /// Moves focus to the first field with an error, so keyboard and screen
  /// reader users land on it; its message is part of the field's
  /// accessible description.
  void _focusFirstError() {
    for (final (field, focus) in [
      (_amountField, _amountFocus),
      (_descriptionField, _descriptionFocus),
    ]) {
      if (field.currentState?.hasError ?? false) {
        focus.requestFocus();
        return;
      }
    }
  }

  void _failed(_SaveProblem? problem) {
    if (!mounted) return;
    setState(() {
      _saving = false;
      _problem = problem;
    });
  }

  /// Asked when leaving with unsaved input. `true` means discard.
  Future<void> _confirmDiscard() async {
    if (_confirmingDiscard || _saving) return;
    _confirmingDiscard = true;
    final navigator = Navigator.of(context);
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        semanticLabel: _editing ? 'Discard changes' : 'Discard this expense',
        title: Text(_editing ? 'Discard changes?' : 'Discard this expense?'),
        content: Text(
          _editing
              ? 'Your changes to this expense have not been saved.'
              : 'This expense has not been saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    _confirmingDiscard = false;
    if (discard == true && mounted) navigator.pop();
  }

  /// Leaves the paused state by reloading stored data and closing the form.
  /// If that would lose input, asks first; staying keeps the input.
  Future<void> _reloadAndClose() async {
    if (_confirmingDiscard || _saving) return;
    final navigator = Navigator.of(context);
    final provider = context.read<ExpenseProvider>();
    if (_dirty) {
      _confirmingDiscard = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          semanticLabel: 'Discard changes and reload',
          title: const Text('Discard changes and reload?'),
          content: Text(
            'Reloading shows the latest saved data. '
            '${_editing ? 'Your unsaved changes to this expense' : 'This unsaved expense'} '
            'will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Discard and reload'),
            ),
          ],
        ),
      );
      _confirmingDiscard = false;
      if (discard != true || !mounted) return;
    }
    await provider.reload();
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    final paused = !provider.isReady;
    const gap = SizedBox(height: AppSpacing.l);

    final notice = switch (_problem) {
      _SaveProblem.duplicate => const NoticeBanner(
        level: NoticeLevel.error,
        text:
            'This expense shares its ID with another saved expense, so it '
            'cannot be changed safely. Nothing was saved.',
      ),
      _SaveProblem.stale => NoticeBanner(
        level: NoticeLevel.warning,
        text:
            'This expense may have been changed or deleted in another tab. '
            'Nothing was saved, so the newer data is kept. Your input is '
            'still here; reload to see the latest data.',
        actionLabel: 'Reload',
        onAction: _reloadAndClose,
      ),
      null when paused => NoticeBanner(
        level: NoticeLevel.warning,
        text:
            'Expenses were changed in another tab or window, so saving is '
            'paused. Your input is still here; reload to see the latest '
            'data.',
        actionLabel: 'Reload',
        onAction: _reloadAndClose,
      ),
      null => null,
    };

    return PopScope(
      canPop: !_saving && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      // Escape leaves like the back button (asking first if input would be
      // lost). Key events from every field and button of the page reach
      // this handler; the Amount field has focus from the start.
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).maybePop();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: Text(_editing ? 'Edit Expense' : 'Add Expense'),
            ),
            body: SafeArea(
              child: Form(
                key: _formKey,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: appFormMaxWidth,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.l),
                      children: [
                        SectionLabel(
                          _editing ? 'Editing expense' : 'New expense',
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _editing
                              ? 'Only the fields you change are updated. '
                                    'Nothing is saved until you choose Save '
                                    'changes.'
                              : 'Amounts are stored exactly, to the cent.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: SpendWiseColors.of(context)
                                    .foregroundSecondary,
                              ),
                        ),
                        gap,
                        if (notice != null) ...[notice, gap],
                        TextFormField(
                          key: _amountField,
                          focusNode: _amountFocus,
                          // The form starts here, for keyboard and screen
                          // reader users alike. The cursor goes to the end;
                          // an existing amount is neither selected nor
                          // changed (browsers would select it all).
                          autofocus: true,
                          selectAllOnFocus: false,
                          controller: _amount,
                          // The amount leads the form, in tabular figures.
                          style: amountStyle(
                            Theme.of(context).textTheme.headlineSmall,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                            prefixText: currencySymbol,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: _baseline.validateAmountText,
                        ),
                        gap,
                        TextFormField(
                          key: _descriptionField,
                          focusNode: _descriptionFocus,
                          controller: _description,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                          ),
                          validator: _baseline.validateDescriptionText,
                        ),
                        gap,
                        DropdownButtonFormField<String>(
                          initialValue: _category,
                          items: [
                            for (final c in _baseline.categories)
                              DropdownMenuItem(value: c, child: Text(c)),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _category = value);
                            }
                          },
                          decoration: const InputDecoration(
                            labelText: 'Category',
                          ),
                        ),
                        gap,
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event_outlined),
                          title: Text('Date: ${formatLongDate(_date)}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.calendar_today),
                            tooltip: 'Pick date',
                            onPressed: _saving ? null : _pickDate,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        FilledButton(
                          onPressed: _saving || paused ? null : _submit,
                          child: Text(
                            _editing ? 'Save changes' : 'Add Expense',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s),
                        // Leaves like Back: asks first if input would be lost.
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).maybePop(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
