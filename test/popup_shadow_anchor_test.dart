// WindowPositionerAnchor is @internal to the SDK's experimental windowing API,
// which layer_shell re-exports; lib/popup.dart carries the same waiver.
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/popup.dart';
import 'package:moonswing/popup_surface.dart';
import 'package:layer_shell/layer_shell.dart';

/// A popup surface is grown by the shadow's reach so the shadow is not clipped at
/// the surface edge, which leaves the *card* sitting that far inside its own
/// window. [popupShadowAnchorOffset] puts it back where an unshadowed popup's
/// window would have gone, and these pin the arithmetic per anchor.
void main() {
  // Deliberately asymmetric on both axes, so a sign error cannot pass.
  const insets = EdgeInsets.only(left: 4, top: 10, right: 12, bottom: 22);

  test('no shadow is no correction', () {
    for (final anchor in WindowPositionerAnchor.values) {
      expect(popupShadowAnchorOffset(anchor, EdgeInsets.zero), Offset.zero,
          reason: '$anchor');
    }
  });

  group('the edge-centred anchors a bar popup uses', () {
    // popupAnchorsForBar returns these, and the centred axis takes *half* the
    // asymmetry: the compositor centres the window on the trigger, so a shadow
    // that leans one way would otherwise slide every bar popup sideways by half
    // its lean.
    test('top — the popup under a top bar', () {
      expect(popupShadowAnchorOffset(WindowPositionerAnchor.top, insets),
          const Offset(4, -10));
    });

    test('bottom — the popup above a bottom bar', () {
      expect(popupShadowAnchorOffset(WindowPositionerAnchor.bottom, insets),
          const Offset(4, 22));
    });

    test('left — the popup to the right of a left bar', () {
      expect(popupShadowAnchorOffset(WindowPositionerAnchor.left, insets),
          const Offset(-4, 6));
    });

    test('right — the popup to the left of a right bar', () {
      expect(popupShadowAnchorOffset(WindowPositionerAnchor.right, insets),
          const Offset(12, 6));
    });
  });

  group('the corner anchors a flyout uses', () {
    // The app directory's category submenu, which anchors topLeft/topRight and
    // flips across kPopupFlipX. Both axes are pinned, so neither is halved.
    test('topLeft', () {
      expect(popupShadowAnchorOffset(WindowPositionerAnchor.topLeft, insets),
          const Offset(-4, -10));
    });

    test('topRight', () {
      expect(popupShadowAnchorOffset(WindowPositionerAnchor.topRight, insets),
          const Offset(12, -10));
    });

    test('bottomLeft', () {
      expect(popupShadowAnchorOffset(WindowPositionerAnchor.bottomLeft, insets),
          const Offset(-4, 22));
    });

    test('bottomRight', () {
      expect(
          popupShadowAnchorOffset(WindowPositionerAnchor.bottomRight, insets),
          const Offset(12, 22));
    });
  });

  test('center halves both axes', () {
    expect(popupShadowAnchorOffset(WindowPositionerAnchor.center, insets),
        const Offset(4, 6));
  });

  group('the gap off the panel edge', () {
    // popupGapOffset is the second half of a bar popup's positioner offset: the
    // first cancels the margin the shadow added, this one is the distance the
    // theme asked for. It always pushes the popup *away* from the bar.
    test('pushes away from the anchored edge', () {
      expect(popupGapOffset('top', 8), const Offset(0, 8));
      expect(popupGapOffset('bottom', 8), const Offset(0, -8));
      expect(popupGapOffset('left', 8), const Offset(8, 0));
      expect(popupGapOffset('right', 8), const Offset(-8, 0));
    });

    test('a zero gap is no offset', () {
      for (final anchor in ['top', 'bottom', 'left', 'right', 'nonsense']) {
        expect(popupGapOffset(anchor, 0), Offset.zero, reason: anchor);
      }
    });

    test('an unknown anchor is treated as a top bar', () {
      expect(popupGapOffset('nonsense', 8), popupGapOffset('top', 8));
    });
  });

  group('the two terms compose to the gap exactly', () {
    // What openPopup actually sends. On the joined edge the shadow inset has
    // already been clamped to the gap, so the correction term contributes
    // `gap - min(reach, gap)` there and the sum is the gap — whatever the shadow's
    // reach. This is what puts an attached card flush against the bar.
    const shadow = ThemeConfig(
      popupShadowBlur: 16.0,
      popupShadowOffsetY: 6.0,
    );

    /// The displacement of the card's joined edge from the panel's, for a bar
    /// anchored at [anchor] under a theme with [gap].
    double joinedEdgeOffset(String anchor, double gap) {
      final theme = ThemeConfig(
        popupShadowBlur: shadow.popupShadowBlur,
        popupShadowOffsetY: shadow.popupShadowOffsetY,
        popupGap: gap,
      );
      final insets = popupShadowInsets(theme, attachEdge: anchor);
      final (_, childAnchor) = popupAnchorsForBar(anchor);
      final offset = popupShadowAnchorOffset(childAnchor, insets) +
          popupGapOffset(anchor, gap);
      // The offset places the *window*; the card sits `insets` inside it, so
      // the joined side's inset is added back to reach the card's own edge.
      // At a zero gap that inset is zero and the two coincide, which is the
      // flush case.
      return switch (anchor) {
        'bottom' => insets.bottom - offset.dy,
        'left' => offset.dx + insets.left,
        'right' => insets.right - offset.dx,
        _ => offset.dy + insets.top,
      };
    }

    for (final anchor in ['top', 'bottom', 'left', 'right']) {
      test('$anchor bar', () {
        // Attached: flush.
        expect(joinedEdgeOffset(anchor, 0), 0.0);
        // A gap under the shadow's reach: the shadow fills it and stops.
        expect(joinedEdgeOffset(anchor, 4), 4.0);
        // A gap past it: the shadow is untouched and the card is still exactly
        // `gap` off the bar.
        expect(joinedEdgeOffset(anchor, 40), 40.0);
      });
    }
  });
}
