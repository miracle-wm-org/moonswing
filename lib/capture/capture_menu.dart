// The menu both capture modules open from the bar.
//
// One card rather than one per module, because they are the same card: the same
// three ways of choosing what to capture, in the same order. The recorder adds a
// Stop row while it is running and the screenshot module never does, which is the
// whole of the difference — so the rows are the parameter and the card is shared.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:graceful_shell/hover_region.dart';
import 'package:graceful_shell/popup_surface.dart';
import 'package:graceful_shell/scopes.dart';
import 'package:graceful_shell/shell_text_root.dart';
import 'package:graceful_shell/theme/tokens.dart';

import 'selection_controller.dart';

/// The icon a selection mode is offered under.
FaIconData iconForMode(SelectionMode mode) => switch (mode) {
      SelectionMode.area => FontAwesomeIcons.cropSimple,
      SelectionMode.window => FontAwesomeIcons.windowMaximize,
      SelectionMode.output => FontAwesomeIcons.display,
    };

/// One row of [CaptureMenuCard].
class CaptureMenuAction {
  const CaptureMenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.emphasis = false,
  });

  /// One selection mode as a row. Both modules offer all three in
  /// `SelectionMode`'s own order — narrowest first, because that is the one
  /// being reached for most often and it leaves the two that need no aim at
  /// the bottom of the list.
  factory CaptureMenuAction.mode(SelectionMode mode, VoidCallback onTap) =>
      CaptureMenuAction(
        icon: iconForMode(mode),
        label: mode.label,
        onTap: onTap,
      );

  final FaIconData icon;
  final String label;
  final VoidCallback onTap;

  /// Drawn in the error colour — the recorder's Stop row, which is the one
  /// action here that ends something rather than starting it.
  final bool emphasis;
}

/// The card: a row per action, with an optional line under them.
class CaptureMenuCard extends StatelessWidget {
  const CaptureMenuCard({
    super.key,
    required this.actions,
    this.note,
    this.noteIsError = false,
  });

  final List<CaptureMenuAction> actions;

  /// A line under the rows — the elapsed recording, or why the last attempt
  /// failed. A failure is shown *here* as well as in its notification because
  /// the notification may have expired by the time the user comes back to the
  /// icon to find out what happened.
  final String? note;
  final bool noteIsError;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final note = this.note;
    return ShellTextRoot(
      style: TextStyle(
        color: theme.popupForeground,
        fontSize: ShellFontSizes.body,
      ),
      child: PopupCard(
        padding: const EdgeInsets.all(8),
        // The popup is sized to its content, and every row is a Row with an
        // Expanded label — so without this each would fill whatever maximum
        // the constraints allow and the card would simply be that wide.
        // `SystemPopupContent` states the same reasoning.
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, action) in actions.indexed) ...[
                if (index > 0) const SizedBox(height: 4),
                _CaptureMenuRow(action: action),
              ],
              if (note != null && note.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Text(
                    note,
                    style: TextStyle(
                      fontSize: ShellFontSizes.caption,
                      color: noteIsError ? kErrorColor : theme.muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptureMenuRow extends StatelessWidget {
  const _CaptureMenuRow({required this.action});

  final CaptureMenuAction action;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final color = action.emphasis ? kErrorColor : theme.popupForeground;
    return HoverRegion(
      onTap: action.onTap,
      builder: (context, hovered) => Container(
        decoration: BoxDecoration(
          color: hovered ? theme.surfaceHover : null,
          borderRadius: BorderRadius.circular(ShellRadii.control),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            FaIcon(action.icon, size: ShellFontSizes.label, color: color),
            const SizedBox(width: 10),
            Expanded(child: Text(action.label, style: TextStyle(color: color))),
          ],
        ),
      ),
    );
  }
}
