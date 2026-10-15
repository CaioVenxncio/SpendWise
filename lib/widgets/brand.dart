import 'package:flutter/material.dart';

import '../presentation/app_theme.dart';

/// The typographic wordmark "spendwise." with an accent full stop.
class SpendWiseWordmark extends StatelessWidget {
  const SpendWiseWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = SpendWiseColors.of(context);
    final style = Theme.of(context).textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
      color: colors.foreground,
    );
    return Semantics(
      label: 'SpendWise',
      header: true,
      // The page's one top-level heading.
      headingLevel: 1,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          text: 'spendwise',
          children: [
            TextSpan(
              text: '.',
              style: TextStyle(color: colors.accentForeground),
            ),
          ],
        ),
        style: style,
      ),
    );
  }
}

/// A small editorial section marker such as "02 / YOUR ACTIVITY".
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color});

  final String text;

  /// Overrides the muted default, e.g. on the accent surface.
  final Color? color;

  /// What screen readers hear: the text as written, without the decorative
  /// "02 / " numbering or the visual upper case.
  static String spokenText(String text) =>
      text.replaceFirst(RegExp(r'^\d+\s*/\s*'), '');

  @override
  Widget build(BuildContext context) => Semantics(
    label: spokenText(text),
    excludeSemantics: true,
    child: Text(
      text.toUpperCase(),
      style: sectionLabelStyle(context)?.copyWith(color: color),
    ),
  );
}
