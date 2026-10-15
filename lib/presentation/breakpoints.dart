/// Material 3 window size classes, by logical width.
enum WindowSize {
  /// Below 600: phones. Compact Hero, single column.
  compact,

  /// 600–839: small tablets, narrow windows. Centred single column.
  medium,

  /// 840–1199: Asymmetric Workspace (two columns).
  expanded,

  /// 1200 and above: Asymmetric Workspace, width capped.
  large;

  static WindowSize of(double width) {
    if (width < 600) return compact;
    if (width < 840) return medium;
    if (width < 1200) return expanded;
    return large;
  }

  /// Whether the two-column workspace with a detail panel is used.
  bool get isWorkspace => this == expanded || this == large;
}
