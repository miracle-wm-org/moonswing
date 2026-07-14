import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/miracle_manager.dart';
import 'package:wayland/wayland.dart';

/// Provides the shell's [MiracleManager] to the widget subtree.
///
/// The manager — not the connection — is scoped, because the connection can
/// come and go at runtime (Miracle may not be up when the shell starts, and a
/// user can retry from any bar). Consumers read `manager.connection` and listen
/// to the manager for changes; the scope itself is stable.
class MiracleScope extends InheritedWidget {
  const MiracleScope({
    super.key,
    required this.manager,
    required super.child,
  });

  final MiracleManager manager;

  static MiracleManager of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MiracleScope>()!.manager;

  @override
  bool updateShouldNotify(MiracleScope old) => manager != old.manager;
}

/// Provides bar information — specifically the side the bar is anchored to —
/// to the widget subtree.
class BarScope extends InheritedWidget {
  const BarScope({
    super.key,
    required this.anchor,
    required super.child,
  });

  /// The side of the screen this bar is anchored to.
  /// One of: `'top'`, `'bottom'`, `'left'`, `'right'`.
  final String anchor;

  static BarScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BarScope>()!;

  @override
  bool updateShouldNotify(BarScope old) => anchor != old.anchor;
}

/// Provides [WaylandOutput] for the display this bar is rendered on.
class DisplayScope extends InheritedWidget {
  const DisplayScope({
    super.key,
    required this.output,
    required super.child,
  });

  final WaylandOutput output;

  static WaylandOutput of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DisplayScope>()!.output;

  @override
  bool updateShouldNotify(DisplayScope old) => output.name != old.output.name;
}

/// Provides [ThemeConfig] to the widget subtree.
class ThemeScope extends InheritedWidget {
  const ThemeScope({
    super.key,
    required this.theme,
    required super.child,
  });

  final ThemeConfig theme;

  static ThemeConfig of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()!.theme;

  @override
  bool updateShouldNotify(ThemeScope old) => theme != old.theme;
}
