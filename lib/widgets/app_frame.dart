import 'package:flutter/material.dart';

import '../presentation/app_theme.dart';
import '../presentation/keyboard_focus.dart';
import 'state_views.dart';

/// The app's one [MaterialApp] configuration around [home].
///
/// Every startup phase (configuration error, opening SQLite, migration,
/// the expense app) shows its screen through this, so all of them share
/// the same light/dark theme, following the system setting. Exactly one
/// MaterialApp exists at a time; a phase change replaces it.
Widget spendWiseMaterialApp(Widget home) => MaterialApp(
  title: 'SpendWise',
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: ThemeMode.system,
  // Focus rings while the keyboard is in use (dialogs and pages included).
  builder: (context, child) => KeyboardFocusScope(child: child!),
  home: home,
);

/// A full-screen message with optional actions.
class ErrorPage extends StatelessWidget {
  const ErrorPage({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('SpendWise')),
    body: ErrorView(title: title, body: body, actions: actions),
  );
}
