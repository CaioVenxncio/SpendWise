import 'package:flutter/material.dart';

/// Spacing scale used across the app (logical pixels).
abstract final class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii. Restrained: full rounding only for compact actions.
abstract final class AppRadii {
  static const double small = 8;
  static const double medium = 12;
  static const double large = 16;
}

/// Widest the single-column layout grows (compact and medium widths).
const double appContentMaxWidth = 720;

/// Widest the two-column workspace grows on large monitors.
const double appWorkspaceMaxWidth = 1360;

/// Widest a form grows.
const double appFormMaxWidth = 560;

/// "Electric After Hours" colour tokens beyond the Material roles.
///
/// Read with `SpendWiseColors.of(context)`. Dark is the design reference;
/// light is derived from it with deep green in place of lime wherever
/// lime would be too faint (small text, icons on light surfaces).
@immutable
class SpendWiseColors extends ThemeExtension<SpendWiseColors> {
  const SpendWiseColors({
    required this.background,
    required this.surface,
    required this.surfaceSelected,
    required this.surfaceHover,
    required this.divider,
    required this.dividerStrong,
    required this.foreground,
    required this.foregroundSecondary,
    required this.foregroundMuted,
    required this.accent,
    required this.onAccent,
    required this.accentForeground,
    required this.focus,
  });

  /// Obsidian / off-white page background.
  final Color background;

  /// Graphite / pale panel surface.
  final Color surface;

  /// Selected row or elevated surface.
  final Color surfaceSelected;

  /// Hovered row.
  final Color surfaceHover;

  final Color divider;
  final Color dividerStrong;

  /// Main text.
  final Color foreground;

  /// Secondary text (descriptions' metadata).
  final Color foregroundSecondary;

  /// Muted labels (section markers). Still meets 4.5:1 on [surface].
  final Color foregroundMuted;

  /// Electric Lime: the signature accent for large surfaces and the
  /// primary action. Not for small text on light backgrounds.
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;

  /// Accent for small text, icons and the selection marker on
  /// [background]/[surface] (lime in dark, deep green in light).
  final Color accentForeground;

  /// Keyboard focus ring.
  final Color focus;

  static SpendWiseColors of(BuildContext context) =>
      Theme.of(context).extension<SpendWiseColors>()!;

  static const dark = SpendWiseColors(
    background: Color(0xFF0B1010),
    surface: Color(0xFF19211E),
    surfaceSelected: Color(0xFF26332C),
    surfaceHover: Color(0xFF2B3B30),
    divider: Color(0xFF29362F),
    dividerStrong: Color(0xFF344039),
    foreground: Color(0xFFF2F4EE),
    foregroundSecondary: Color(0xFFAAB8AE),
    foregroundMuted: Color(0xFF87998F),
    accent: Color(0xFFC8FF5F),
    onAccent: Color(0xFF0B1010),
    accentForeground: Color(0xFFC8FF5F),
    focus: Color(0xFFC8FF5F),
  );

  static const light = SpendWiseColors(
    background: Color(0xFFF4F6EF),
    surface: Color(0xFFE9EEE3),
    surfaceSelected: Color(0xFFDDE6D3),
    surfaceHover: Color(0xFFE2E9DA),
    divider: Color(0xFFD3DBCC),
    dividerStrong: Color(0xFFB9C4B2),
    foreground: Color(0xFF19211E),
    foregroundSecondary: Color(0xFF3F4D45),
    foregroundMuted: Color(0xFF55645B),
    accent: Color(0xFFC8FF5F),
    onAccent: Color(0xFF0B1010),
    accentForeground: Color(0xFF2E5410),
    focus: Color(0xFF2E5410),
  );

  @override
  SpendWiseColors copyWith() => this;

  @override
  SpendWiseColors lerp(SpendWiseColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

/// SpendWise's Material 3 theme: "Electric After Hours", dark-first.
///
/// Material roles are filled from the tokens above so standard components
/// (fields, dialogs, menus, snack bars) match the custom ones.
abstract final class AppTheme {
  /// Electric Lime, the signature accent.
  static const Color seed = Color(0xFFC8FF5F);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ColorScheme _scheme(Brightness brightness) {
    final t = brightness == Brightness.dark
        ? SpendWiseColors.dark
        : SpendWiseColors.light;
    final dark = brightness == Brightness.dark;
    return ColorScheme(
      brightness: brightness,
      primary: t.accentForeground,
      onPrimary: dark ? t.onAccent : const Color(0xFFFFFFFF),
      primaryContainer: t.accent,
      onPrimaryContainer: t.onAccent,
      secondary: t.foregroundSecondary,
      onSecondary: t.background,
      // Information notices.
      secondaryContainer: dark
          ? const Color(0xFF223038)
          : const Color(0xFFDCE8EE),
      onSecondaryContainer: dark
          ? const Color(0xFFD6E7F0)
          : const Color(0xFF15262E),
      // Warning notices (amber; distinct from lime and from error).
      tertiary: dark ? const Color(0xFFF2C66D) : const Color(0xFF6B4E00),
      onTertiary: dark ? const Color(0xFF2A1F00) : const Color(0xFFFFFFFF),
      tertiaryContainer: dark
          ? const Color(0xFF3A3014)
          : const Color(0xFFFBE7B5),
      onTertiaryContainer: dark
          ? const Color(0xFFFCE3A6)
          : const Color(0xFF2A1F00),
      error: dark ? const Color(0xFFFFB4AB) : const Color(0xFFB3261E),
      onError: dark ? const Color(0xFF690005) : const Color(0xFFFFFFFF),
      errorContainer: dark ? const Color(0xFF4A1A16) : const Color(0xFFF9DEDC),
      onErrorContainer: dark
          ? const Color(0xFFFFDAD6)
          : const Color(0xFF410E0B),
      surface: t.background,
      onSurface: t.foreground,
      onSurfaceVariant: t.foregroundSecondary,
      surfaceDim: t.background,
      surfaceBright: t.surfaceHover,
      surfaceContainerLowest: t.background,
      surfaceContainerLow: t.surface,
      surfaceContainer: t.surface,
      surfaceContainerHigh: t.surfaceSelected,
      surfaceContainerHighest: t.surfaceHover,
      outline: t.dividerStrong,
      outlineVariant: t.divider,
      inverseSurface: t.foreground,
      onInverseSurface: t.background,
      inversePrimary: dark ? SpendWiseColors.light.accentForeground : t.accent,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      surfaceTint: Colors.transparent,
    );
  }

  static ThemeData _build(Brightness brightness) {
    final scheme = _scheme(brightness);
    final tokens = brightness == Brightness.dark
        ? SpendWiseColors.dark
        : SpendWiseColors.light;
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      // Comfortable targets on every platform, including desktop browsers.
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme;
    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.medium),
    );
    final focusBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.small),
      borderSide: BorderSide(color: tokens.focus, width: 2),
    );

    return base.copyWith(
      extensions: [tokens],
      scaffoldBackgroundColor: tokens.background,
      // Dropdown menus and other canvas popups sit on the panel surface,
      // so they stand out from the page.
      canvasColor: tokens.surface,
      focusColor: tokens.focus.withValues(alpha: 0.24),
      hoverColor: tokens.surfaceHover.withValues(alpha: 0.6),
      textTheme: text.copyWith(
        // Confident, tight display sizes for amounts and headings.
        displaySmall: text.displaySmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.background,
        foregroundColor: tokens.foreground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: tokens.divider)),
        titleTextStyle: text.titleLarge?.copyWith(
          color: tokens.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: tokens.surface,
        margin: EdgeInsets.zero,
        shape: rounded,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
        iconColor: tokens.foregroundSecondary,
        selectedColor: tokens.foreground,
        selectedTileColor: tokens.surfaceSelected,
        shape: rounded,
      ),
      dividerTheme: DividerThemeData(
        color: tokens.divider,
        space: 1,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          borderSide: BorderSide(color: tokens.dividerStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.small),
          borderSide: BorderSide(color: tokens.dividerStrong),
        ),
        focusedBorder: focusBorder,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          foregroundColor: tokens.foreground,
          side: BorderSide(color: tokens.dividerStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.small),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: tokens.accent,
        foregroundColor: tokens.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: tokens.surface,
        // Readable line length on desktop.
        constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.large),
          side: BorderSide(color: tokens.divider),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(color: tokens.surface),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Keyboard focus ring for buttons: 2 px in the focus colour, drawn 2 px
  /// outside the control, so it stays visible next to lime and red fills.
  static BorderSide focusRing(SpendWiseColors tokens) =>
      // strokeAlign 3: inner edge 2 px, outer edge 4 px outside the shape.
      BorderSide(color: tokens.focus, width: 2, strokeAlign: 3);

  /// [theme] with focus rings on the standard buttons, used while the
  /// keyboard is in use (see `KeyboardFocusScope`). Nothing else changes.
  static ThemeData withFocusRings(ThemeData theme) {
    final ring = focusRing(theme.extension<SpendWiseColors>()!);

    ButtonStyle ringed(ButtonStyle? style) {
      final side = style?.side;
      return (style ?? const ButtonStyle()).copyWith(
        side: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? ring
              : side?.resolve(states),
        ),
      );
    }

    final fabShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.large),
    );
    return theme.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: ringed(theme.filledButtonTheme.style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ringed(theme.outlinedButtonTheme.style),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ringed(theme.textButtonTheme.style),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ringed(theme.elevatedButtonTheme.style),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ringed(theme.iconButtonTheme.style),
      ),
      floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
        // The Material 3 FAB shape (regular and extended), plus the ring.
        shape: WidgetStateOutlinedBorder.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? fabShape.copyWith(side: ring)
              : fabShape,
        ),
      ),
    );
  }
}

/// Text style for money amounts: [style] with tabular (equal-width) figures.
TextStyle? amountStyle(TextStyle? style) =>
    style?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

/// Small uppercase editorial marker style, e.g. "02 / YOUR ACTIVITY".
TextStyle? sectionLabelStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelMedium?.copyWith(
      color: SpendWiseColors.of(context).foregroundMuted,
      letterSpacing: 1.4,
      fontWeight: FontWeight.w600,
    );
