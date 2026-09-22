// The chrome around a desktop widget: the card it paints on, the selection rim,
// and the corner grips it is resized by.
//
// Separate from `desktop_grid.dart` for the reason `desktop_icon.dart` is: the
// grid owns pointers and persistence, these own pixels. The grid positions a
// [DesktopWidgetResizeGrip] at each corner and feeds it the drag.

import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/desktop/desktop_layout.dart';
import 'package:moonswing/desktop/widgets/desktop_widget.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

/// Which corner a resize is being dragged from.
enum DesktopWidgetCorner {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  bool get movesLeftEdge =>
      this == DesktopWidgetCorner.topLeft ||
      this == DesktopWidgetCorner.bottomLeft;

  bool get movesTopEdge =>
      this == DesktopWidgetCorner.topLeft ||
      this == DesktopWidgetCorner.topRight;

  Alignment get alignment => switch (this) {
        DesktopWidgetCorner.topLeft => Alignment.topLeft,
        DesktopWidgetCorner.topRight => Alignment.topRight,
        DesktopWidgetCorner.bottomLeft => Alignment.bottomLeft,
        DesktopWidgetCorner.bottomRight => Alignment.bottomRight,
      };

  /// The diagonal resize cursor for this corner. Two of the four run the other
  /// way, and getting it wrong is the sort of thing nobody reports but
  /// everybody feels.
  MouseCursor get cursor => switch (this) {
        DesktopWidgetCorner.topLeft ||
        DesktopWidgetCorner.bottomRight =>
          SystemMouseCursors.resizeUpLeftDownRight,
        DesktopWidgetCorner.topRight ||
        DesktopWidgetCorner.bottomLeft =>
          SystemMouseCursors.resizeUpRightDownLeft,
      };
}

/// The card a desktop widget is drawn on.
///
/// Renders through [PopupCard], so a widget inherits the theme's popup
/// background, rim, radius and shadow — one surface language for everything the
/// shell floats over the desktop.
class DesktopWidgetFrame extends StatelessWidget {
  const DesktopWidgetFrame({
    super.key,
    required this.item,
    required this.spec,
    required this.span,
    required this.size,
    this.selected = false,
    this.hovered = false,
  });

  final DesktopWidgetItem item;

  /// Null when the config names a type this build does not have.
  final DesktopWidgetSpec? spec;

  final GridSpan span;

  /// The pixel size of the card, handed to the widget's builder.
  final Size size;

  final bool selected;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    final spec = this.spec;

    // The rim is the whole selection chrome: a fill would fight the widget's
    // own content for contrast, which an icon tile does not have to worry about.
    final borderColor = selected
        ? theme.accent
        : hovered
            ? theme.accent.withValues(alpha: 0.5)
            : null;

    return AnimatedContainer(
      duration: ShellDurations.fast,
      foregroundDecoration: borderColor == null
          ? null
          : BoxDecoration(
              border: Border.all(color: borderColor, width: 2),
              borderRadius: popupCornerRadius(theme),
            ),
      child: PopupCard(
        padding: spec?.padding ?? const EdgeInsets.all(10),
        child: spec == null
            ? _UnknownWidget(type: item.type, theme: theme)
            : spec.builder(
                context,
                DesktopWidgetContext(item: item, size: size, span: span),
              ),
      ),
    );
  }
}

/// A widget type this build does not know.
///
/// Shown rather than dropped: the entry stays in the config, so a user who
/// downgraded still has something to right-click and remove, and an upgrade
/// brings the real widget straight back.
class _UnknownWidget extends StatelessWidget {
  const _UnknownWidget({required this.type, required this.theme});

  final String type;
  final ThemeConfig theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(
            FontAwesomeIcons.circleQuestion,
            size: 16,
            color: theme.muted,
          ),
          const SizedBox(height: 6),
          Text(
            'Unknown widget "$type"',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: theme.fontFamily,
              fontSize: ShellFontSizes.caption,
              color: theme.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// One corner grip.
///
/// Drawn only while the widget is hovered or being resized: a desktop widget
/// spends nearly all its life being *looked at*, and four permanent handles would
/// be four permanent pieces of chrome on the wallpaper.
class DesktopWidgetResizeGrip extends StatelessWidget {
  const DesktopWidgetResizeGrip({
    super.key,
    required this.corner,
    required this.color,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    this.size = 16,
  });

  final DesktopWidgetCorner corner;
  final Color color;

  final void Function(DragStartDetails details) onPanStart;
  final void Function(DragUpdateDetails details) onPanUpdate;
  final VoidCallback onPanEnd;

  final double size;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: corner.cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: onPanStart,
        onPanUpdate: onPanUpdate,
        onPanEnd: (_) => onPanEnd(),
        onPanCancel: onPanEnd,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Container(
              width: size * 0.55,
              height: size * 0.55,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
                border: Border.all(color: const Color(0x66000000)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The outline shown where a widget will land while it is being resized.
///
/// The resize is committed on release, so this is the only thing that says what
/// the release will do — the grid lines say which cells exist, and this says
/// which of them the widget is about to take.
class DesktopWidgetPreview extends StatelessWidget {
  const DesktopWidgetPreview({
    super.key,
    required this.rect,
    required this.color,
  });

  final Rect rect;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(ShellRadii.card),
          ),
        ),
      ),
    );
  }
}
