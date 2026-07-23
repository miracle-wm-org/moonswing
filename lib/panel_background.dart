import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';

/// The static gradient drawn behind a panel's modules.
///
/// The gradient is "aligned" to the panel's own edge: the bright accent sits
/// against that edge and fades to dark across the panel.
///   top    -> left-aligned    bottom -> right-aligned
///   left   -> top-aligned     right  -> bottom-aligned
BoxDecoration panelBackgroundDecoration({
  String anchor = 'top',
  ThemeConfig theme = const ThemeConfig(),
}) {
  final dark = theme.workspaceBackground.withValues(alpha: 0xEE / 0xFF);
  final mid = theme.surfacePressed.withValues(alpha: 0xEE / 0xFF);
  final light = theme.accent.withValues(alpha: 0xEE / 0xFF);

  late final Alignment begin;
  late final Alignment end;
  switch (anchor) {
    case 'bottom':
      begin = Alignment.centerRight;
      end = Alignment.centerLeft;
      break;
    case 'left':
      begin = Alignment.topCenter;
      end = Alignment.bottomCenter;
      break;
    case 'right':
      begin = Alignment.bottomCenter;
      end = Alignment.topCenter;
      break;
    case 'top':
    default:
      begin = Alignment.centerLeft;
      end = Alignment.centerRight;
      break;
  }

  return BoxDecoration(
    gradient: LinearGradient(
      begin: begin,
      end: end,
      colors: [light, mid, dark],
      stops: const [0.0, 0.5, 1.0],
    ),
  );
}
