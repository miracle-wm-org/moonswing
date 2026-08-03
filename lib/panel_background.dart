import 'package:flutter/widgets.dart';
import 'package:graceful_shell/config.dart';

/// The background drawn behind a panel's modules.
///
/// The bar's colour is [ThemeConfig.panelBackground] and its alpha is honoured
/// as written, so a translucent theme can see through the surface that sits
/// directly on the desktop. Before this the panel was painted from
/// `workspaceBackground` at a hardcoded 93%, which made it the one thing in the
/// shell no theme could open up.
///
/// With [ThemeConfig.panelGradient] the bar fades from `accent` through
/// `surfacePressed` to that colour, "aligned" to the panel's own edge — the
/// bright end sits against that edge:
///   top    -> left-aligned    bottom -> right-aligned
///   left   -> top-aligned     right  -> bottom-aligned
///
/// Every stop takes its alpha from `panelBackground`, not from its own colour.
/// The bar therefore has exactly one opacity: an author sets how see-through it
/// is in one place, and a stop cannot be more opaque than the rest of the bar
/// and read as a band across it.
///
/// [theme] is required on purpose: a defaulted palette here would silently
/// paint the built-in colours over whatever theme is actually active.
BoxDecoration panelBackgroundDecoration({
  String anchor = 'top',
  required ThemeConfig theme,
}) {
  if (!theme.panelGradient) {
    return BoxDecoration(color: theme.panelBackground);
  }

  final alpha = theme.panelBackground.a;
  final dark = theme.panelBackground;
  final mid = theme.surfacePressed.withValues(alpha: alpha);
  final light = theme.accent.withValues(alpha: alpha);

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
