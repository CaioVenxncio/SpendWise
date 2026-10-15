import 'package:flutter/material.dart';

import '../presentation/app_theme.dart';

/// How serious a [NoticeBanner] is. Each level has its own icon and name,
/// so the meaning never depends on colour alone.
enum NoticeLevel {
  /// Something to know; nothing is at risk.
  info(Icons.info_outline, 'Information'),

  /// Edits are paused or data could be at risk if ignored.
  warning(Icons.warning_amber_rounded, 'Warning'),

  /// An action is unavailable because it would be unsafe.
  error(Icons.error_outline, 'Problem');

  const NoticeLevel(this.icon, this.semanticName);

  final IconData icon;

  /// Spoken before the text by screen readers.
  final String semanticName;
}

/// A full-width notice with an icon, a message and an optional action.
///
/// The message is a live region, so screen readers announce a notice that
/// appears while the user is on the screen (e.g. a change in another tab).
class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.text,
    this.level = NoticeLevel.info,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final NoticeLevel level;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (level) {
      NoticeLevel.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      NoticeLevel.warning => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      NoticeLevel.error => (scheme.errorContainer, scheme.onErrorContainer),
    };
    final textStyle = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: foreground);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.l,
          AppSpacing.m,
          AppSpacing.s,
          AppSpacing.m,
        ),
        child: Row(
          children: [
            // The level is spoken with the text instead (see below).
            ExcludeSemantics(child: Icon(level.icon, color: foreground)),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Semantics(
                liveRegion: true,
                label: '${level.semanticName}: $text',
                excludeSemantics: true,
                child: Text(text, style: textStyle),
              ),
            ),
            if (actionLabel != null) ...[
              const SizedBox(width: AppSpacing.s),
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(foregroundColor: foreground),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
