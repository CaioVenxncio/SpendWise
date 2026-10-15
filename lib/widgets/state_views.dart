import 'package:flutter/material.dart';

import '../presentation/app_theme.dart';

/// A centred progress indicator with an accessible [label].
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(label: label, child: const CircularProgressIndicator()),
  );
}

/// Shown when there is nothing to list.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(
                icon,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A centred error message with optional actions. The title is a live
/// region so screen readers announce it when it appears.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: appFormMaxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.error_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: AppSpacing.m),
              Semantics(
                liveRegion: true,
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                body,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.s,
                  runSpacing: AppSpacing.s,
                  children: actions,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
