import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';
import 'package:miracle/miracle.dart';
import 'package:wayland/wayland.dart';

/// Provides [MiracleConnection] to the widget subtree.
class MiracleScope extends InheritedWidget {
  const MiracleScope({
    super.key,
    required this.connection,
    required super.child,
  });

  final MiracleConnection connection;

  static MiracleConnection of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MiracleScope>()!.connection;

  @override
  bool updateShouldNotify(MiracleScope old) => connection != old.connection;
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
