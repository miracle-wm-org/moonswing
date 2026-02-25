import 'package:flutter/widgets.dart';
import 'package:miracle/miracle.dart';

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

