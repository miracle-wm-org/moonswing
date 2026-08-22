import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/scopes.dart';

/// One tab in an underline tab strip.
///
/// The overlay's top tabs, the system monitor's sub-tabs, the audio page's
/// tab bar and the panels editor each hand-rolled this exact treatment — the
/// 2px accent underline sitting on the header's bottom border (so the
/// selected tab reads as continuous with the content below it), and the
/// selected → hovered → rest foreground ladder. Sizes vary per strip; the
/// treatment must not.
class UnderlineTab extends StatelessWidget {
  const UnderlineTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.iconSize = 13,
    this.fontSize = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  final FaIconData? icon;
  final double iconSize;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  /// After the label — the panels editor puts its close button here.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return HoverRegion(
      builder: (context, hovered) {
        final Color foreground;
        if (selected) {
          foreground = theme.accent;
        } else if (hovered) {
          foreground = theme.popupForeground;
        } else {
          foreground = theme.popupForeground.withValues(alpha: 0.6);
        }
        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? theme.accent : const Color(0x00000000),
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  FaIcon(icon, size: iconSize, color: foreground),
                  SizedBox(width: iconSize > 12 ? 8 : 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontFamily: theme.fontFamily,
                    color: foreground,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        );
      },
    );
  }
}
