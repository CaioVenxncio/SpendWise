import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/app/app_config.dart';
import 'package:spendwise/domain/money.dart';
import 'package:spendwise/main.dart';
import 'package:spendwise/models/expense.dart';
import 'package:spendwise/presentation/app_theme.dart';
import 'package:spendwise/services/expense_storage.dart';
import 'package:spendwise/widgets/expense_list.dart';
import 'package:spendwise/widgets/notice_banner.dart';
import 'package:spendwise/widgets/state_views.dart';

import '../support/fake_expense_storage.dart';
import '../support/ui_actions.dart';

Expense _e(String id, int cents, String description) => Expense(
  id: id,
  amount: Money.fromCents(cents),
  description: description,
  category: 'Food',
  date: DateTime(2024, 3, 10),
);

double _luminance(Color c) => c.computeLuminance();

double _contrast(Color a, Color b) {
  final hi = math.max(_luminance(a), _luminance(b));
  final lo = math.min(_luminance(a), _luminance(b));
  return (hi + 0.05) / (lo + 0.05);
}

void _setBrightness(WidgetTester tester, Brightness brightness) {
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

Future<void> _pump(
  WidgetTester tester,
  FakeExpenseStorage storage, {
  AppConfig? config,
}) async {
  await tester.pumpWidget(
    SpendWiseApp(
      storage: storage,
      config: config,
      clock: () => DateTime(2024, 3, 15),
    ),
  );
  await tester.pumpAndSettle();
}

ThemeData _themeOf(WidgetTester tester, Finder inside) =>
    Theme.of(tester.element(inside));

void main() {
  group('AppTheme', () {
    for (final (name, theme) in [
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      test('$name: Material 3 from the seed colour', () {
        expect(theme.useMaterial3, isTrue);
        expect(
          theme.colorScheme.brightness,
          name == 'light' ? Brightness.light : Brightness.dark,
        );
        final tokens = theme.extension<SpendWiseColors>()!;
        expect(
          tokens,
          name == 'light' ? SpendWiseColors.light : SpendWiseColors.dark,
        );
        // Electric Lime is the accent; small-text accent is lime in dark
        // and deep green in light.
        expect(tokens.accent, const Color(0xFFC8FF5F));
        expect(theme.colorScheme.primary, tokens.accentForeground);
        expect(theme.colorScheme.primaryContainer, tokens.accent);
        expect(theme.scaffoldBackgroundColor, tokens.background);
        expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      });

      test('$name: text colours meet WCAG AA (4.5:1) on their surfaces', () {
        final s = theme.colorScheme;
        final pairs = {
          'onSurface/surface': (s.onSurface, s.surface),
          'onSurfaceVariant/surface': (s.onSurfaceVariant, s.surface),
          'onSurface/surfaceContainerLow': (s.onSurface, s.surfaceContainerLow),
          'onSurfaceVariant/surfaceContainerLow': (
            s.onSurfaceVariant,
            s.surfaceContainerLow,
          ),
          'onPrimary/primary': (s.onPrimary, s.primary),
          'onPrimaryContainer/primaryContainer': (
            s.onPrimaryContainer,
            s.primaryContainer,
          ),
          'onSecondaryContainer/secondaryContainer': (
            s.onSecondaryContainer,
            s.secondaryContainer,
          ),
          'onTertiaryContainer/tertiaryContainer': (
            s.onTertiaryContainer,
            s.tertiaryContainer,
          ),
          'onErrorContainer/errorContainer': (
            s.onErrorContainer,
            s.errorContainer,
          ),
          'primary/surface (text buttons)': (s.primary, s.surface),
          'error/surface': (s.error, s.surface),
        };
        pairs.forEach((label, pair) {
          expect(
            _contrast(pair.$1, pair.$2),
            greaterThanOrEqualTo(4.5),
            reason: label,
          );
        });
      });
    }

    test('dialogs keep a readable width on desktop', () {
      expect(AppTheme.light().dialogTheme.constraints?.maxWidth, 560);
    });

    test('amounts use tabular figures', () {
      expect(
        amountStyle(const TextStyle())!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });
  });

  group('JSON app follows the system brightness', () {
    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: one MaterialApp, themed screens', (
        tester,
      ) async {
        _setBrightness(tester, brightness);
        await _pump(
          tester,
          FakeExpenseStorage(data: encodeExpenses([_e('1', 1250, 'Lunch')])),
        );

        expect(find.byType(MaterialApp), findsOneWidget);
        final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(app.themeMode, ThemeMode.system);
        final theme = _themeOf(tester, find.text('Lunch'));
        expect(theme.colorScheme.brightness, brightness);
        expect(
          theme.colorScheme.primary,
          (brightness == Brightness.light ? AppTheme.light() : AppTheme.dark())
              .colorScheme
              .primary,
        );

        // The add page and the data dialogs use the same theme.
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        expect(
          _themeOf(tester, find.text('Add Expense').first).colorScheme,
          theme.colorScheme,
        );
        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Data options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Storage information'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          _themeOf(tester, find.byType(AlertDialog)).colorScheme,
          theme.colorScheme,
        );
      });

      testWidgets('${brightness.name}: configuration error screen', (
        tester,
      ) async {
        _setBrightness(tester, brightness);
        await _pump(
          tester,
          FakeExpenseStorage(),
          config: const AppConfig(backend: StorageBackend.drift),
        );

        expect(
          find.text('SpendWise cannot start with this configuration'),
          findsOneWidget,
        );
        expect(find.byType(MaterialApp), findsOneWidget);
        expect(
          _themeOf(
            tester,
            find.text('SpendWise cannot start with this configuration'),
          ).colorScheme.brightness,
          brightness,
        );
      });

      testWidgets('${brightness.name}: load error stays readable and offers '
          'recovery', (tester) async {
        _setBrightness(tester, brightness);
        await _pump(tester, FakeExpenseStorage(data: '{not json'));

        expect(
          find.text('Could not load your saved expenses.'),
          findsOneWidget,
        );
        expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
        // No add action while nothing could be loaded.
        expect(find.byType(FloatingActionButton), findsNothing);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });

      testWidgets('${brightness.name}: home screen meets contrast and '
          'tap-target guidelines', (tester) async {
        _setBrightness(tester, brightness);
        final storage = FakeExpenseStorage(
          data: encodeExpenses([
            _e('1', 1250, 'Lunch'),
            _e('d', 1, 'Dup'),
            _e('d', 1, 'Dup'),
          ]),
        );
        await _pump(tester, storage);
        storage.data = encodeExpenses([_e('x', 5, 'Other tab')]);
        await deleteExpenseViaUi(tester, 'Lunch');
        await tester.pageBack();
        await tester.pumpAndSettle();

        // Conflict and duplicate-ID notices are both shown.
        expect(find.text('Reload'), findsOneWidget);
        // The add button is disabled and looks disabled.
        final fab = tester.widget<FloatingActionButton>(
          find.byType(FloatingActionButton),
        );
        final scheme = _themeOf(
          tester,
          find.byType(FloatingActionButton),
        ).colorScheme;
        expect(fab.onPressed, isNull);
        expect(fab.backgroundColor, scheme.onSurface.withValues(alpha: 0.12));
        expect(fab.foregroundColor, scheme.onSurface.withValues(alpha: 0.38));
        expect(find.textContaining('share the same ID'), findsOneWidget);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });
    }
  });

  testWidgets('Tab moves keyboard focus through the home controls', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeExpenseStorage(data: encodeExpenses([_e('1', 1250, 'Lunch')])),
    );
    final focused = <String>{};
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final context = FocusManager.instance.primaryFocus?.context;
      if (context == null) continue;
      final tooltip = context.findAncestorWidgetOfExactType<Tooltip>();
      if (tooltip?.message != null) focused.add(tooltip!.message!);
      final row = context.findAncestorWidgetOfExactType<ExpenseTile>();
      if (row != null) focused.add('row ${row.expense.description}');
    }
    expect(
      focused,
      containsAll(<String>['Data options', 'Add expense', 'row Lunch']),
    );
  });

  group('home states', () {
    testWidgets('loading shows a labelled progress indicator', (tester) async {
      final storage = FakeExpenseStorage(data: '[]')
        ..readGate = Completer<void>();
      await tester.pumpWidget(SpendWiseApp(storage: storage));
      await tester.pump();

      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.bySemanticsLabel('Loading expenses'), findsOneWidget);
      storage.readGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(LoadingView), findsNothing);
    });

    testWidgets('empty state explains how to start', (tester) async {
      await _pump(tester, FakeExpenseStorage());
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No expenses'), findsOneWidget);
      expect(
        find.text('Add your first one with the + button.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(r'Total this month: $0.00'), findsOneWidget);
    });

    testWidgets('rows show formatted amount, category and date', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeExpenseStorage(data: encodeExpenses([_e('1', -123456, 'Refund')])),
      );
      final row = find.byType(ExpenseTile);
      expect(
        find.descendant(of: row, matching: find.text(r'-$1,234.56')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('Food - Mar 10, 2024')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(r'Total this month: -$1,234.56'),
        findsOneWidget,
      );
    });

    testWidgets('an overflowing total is described, not wrapped', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeExpenseStorage(
          data: encodeExpenses([
            _e('1', Money.maxCents, 'a'),
            _e('2', Money.maxCents, 'b'),
          ]),
        ),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Total this month unavailable\.')),
        findsOneWidget,
      );
      // Fails closed: no clamped or approximate total is shown.
      expect(find.text('Total unavailable'), findsOneWidget);
      expect(
        find.textContaining('add up to more than SpendWise can total'),
        findsOneWidget,
      );
    });
  });

  group('NoticeBanner', () {
    Future<void> pumpBanner(WidgetTester tester, Widget banner) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: banner),
          ),
        );

    for (final level in NoticeLevel.values) {
      testWidgets('${level.name}: icon, spoken level and live region', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pumpBanner(
          tester,
          NoticeBanner(level: level, text: 'Something happened.'),
        );

        expect(find.byIcon(level.icon), findsOneWidget);
        expect(
          tester.getSemantics(
            find.bySemanticsLabel('${level.semanticName}: Something happened.'),
          ),
          isSemantics(isLiveRegion: true),
        );
        handle.dispose();
      });
    }

    test('every level has its own icon and spoken name', () {
      expect(NoticeLevel.values.map((l) => l.icon).toSet(), hasLength(3));
      expect(
        NoticeLevel.values.map((l) => l.semanticName).toSet(),
        hasLength(3),
      );
    });

    testWidgets('the action button calls back', (tester) async {
      var taps = 0;
      await pumpBanner(
        tester,
        NoticeBanner(
          level: NoticeLevel.warning,
          text: 'Paused.',
          actionLabel: 'Reload',
          onAction: () => taps++,
        ),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Reload'));
      expect(taps, 1);
    });

    testWidgets('without an action there is no button', (tester) async {
      await pumpBanner(tester, const NoticeBanner(text: 'Info.'));
      expect(find.byType(TextButton), findsNothing);
    });
  });

  testWidgets('ErrorView announces its title', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: ErrorView(title: 'Broken', body: 'Nothing changed.'),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.text('Broken')),
      isSemantics(label: 'Broken', isLiveRegion: true),
    );
    // The body is not a live region (proves the matcher discriminates).
    expect(
      tester.getSemantics(find.text('Nothing changed.')),
      isNot(isSemantics(isLiveRegion: true)),
    );
    handle.dispose();
  });
}
