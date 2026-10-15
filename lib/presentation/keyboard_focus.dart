import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// Shows focus rings only while the keyboard is being used, like the
/// browser's `:focus-visible`.
///
/// Flutter's own [FocusManager.highlightMode] treats a mouse like a
/// keyboard, so it would also draw rings after a mouse click moved focus
/// (for example when a dialog closes). Here a key press turns rings on and
/// any pointer press turns them off.
///
/// While on, the theme below gets [AppTheme.withFocusRings], so standard
/// buttons draw their ring; custom controls ask [isActive].
class KeyboardFocusScope extends StatefulWidget {
  const KeyboardFocusScope({super.key, required this.child});

  final Widget child;

  /// Whether focus rings should be drawn. `false` without a scope.
  static bool isActive(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_KeyboardFocusActive>()
          ?.active ??
      false;

  @override
  State<KeyboardFocusScope> createState() => _KeyboardFocusScopeState();
}

class _KeyboardFocusScopeState extends State<KeyboardFocusScope> {
  bool _active = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    super.dispose();
  }

  /// Observes key presses; never handles them.
  bool _onKey(KeyEvent event) {
    // Modifiers alone (e.g. Ctrl for zooming) are not navigation.
    if (event is KeyDownEvent && !_modifiers.contains(event.logicalKey)) {
      _set(true);
    }
    return false;
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) _set(false);
  }

  void _set(bool active) {
    if (active != _active && mounted) setState(() => _active = active);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _KeyboardFocusActive(
      active: _active,
      // Always a Theme, so switching modes never rebuilds the app's state.
      child: Theme(
        data: _active ? AppTheme.withFocusRings(theme) : theme,
        child: widget.child,
      ),
    );
  }
}

final _modifiers = {
  LogicalKeyboardKey.shift,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.control,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.alt,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.meta,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
};

class _KeyboardFocusActive extends InheritedWidget {
  const _KeyboardFocusActive({required this.active, required super.child});

  final bool active;

  @override
  bool updateShouldNotify(_KeyboardFocusActive oldWidget) =>
      active != oldWidget.active;
}
