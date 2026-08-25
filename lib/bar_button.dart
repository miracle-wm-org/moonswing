import 'package:flutter/widgets.dart';

import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/theme/tokens.dart';

/// The chrome around a bar module's clickable area.
///
/// Seven modules used to hand-roll these fifteen lines each, all with a
/// hard-coded `0x28FFFFFF` hover fill — which made bar-button hover the one
/// hover in the shell that ignored `theme.surfaceHover`. The fill now comes
/// from the theme, at the alpha the old constant had, so an opaque theme
/// colour still reads as a wash rather than a slab.
class BarButton extends StatelessWidget {
  const BarButton({
    super.key,
    this.active = false,
    this.onTapDown,
    this.onSecondaryTapDown,
    required this.child,
  });

  /// Keeps the fill on independent of the pointer — the module's popup is
  /// open, so the button should read as pressed.
  final bool active;

  final GestureTapDownCallback? onTapDown;
  final GestureTapDownCallback? onSecondaryTapDown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      // Tap-*down*, not tap: every popup toggle in the shell opens inside the
      // pointer-down that arms the coordinator's reopen guard.
      onTapDown: onTapDown,
      onSecondaryTapDown: onSecondaryTapDown,
      builder: (context, hovered) => Container(
        decoration: BoxDecoration(
          color: (hovered || active)
              ? theme.surfaceHover.withValues(alpha: 0.16)
              : null,
          borderRadius: BorderRadius.circular(ShellRadii.barButton),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: child,
      ),
    );
  }
}
