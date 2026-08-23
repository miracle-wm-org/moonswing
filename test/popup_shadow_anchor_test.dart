// WindowPositionerAnchor is @internal to the SDK's experimental windowing API,
// which layer_shell re-exports; lib/popup.dart carries the same waiver.
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/popup.dart';
import 'package:layer_shell/layer_shell.dart';

/// A popup surface is grown by the shadow's reach so the shadow is not clipped
/// at the surface edge, which leaves the *card* sitting that far inside its own
/// window. [popupShadowAnchorOffset] is what puts the card back where an
/// unshadowed popup's window would have gone, and these pin the arithmetic per
/// anchor — there is no way to observe it without a compositor otherwise.
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
}
