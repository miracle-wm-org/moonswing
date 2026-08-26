import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:graceful_shell/config.dart';
import 'package:graceful_shell/popup.dart';
import 'package:graceful_shell/popup_surface.dart';

/// A popup's `constraints` are handed to the Linux backend, which turns them
/// into the GTK window's min/max geometry hints — they cap the *surface*, and
/// never reach Flutter's layout (the sized-to-content view is registered with an
/// unbounded metrics range). With a shadow the surface is the card plus
/// [popupShadowInsets], so the hints have to describe that, not the card.
///
/// The regression these pin: handing the card's own constraints through clamped
/// the window back to the card's size, leaving the card rendered `insets.left`
/// inside a window too narrow to hold it — visibly off-centre from the button
/// that opened it, and clipped on the far side. It only showed on the popups
/// that pin a width or pass tight constraints, because a loose one whose content
/// sits under its maximum is never clamped.
void main() {
  // Asymmetric on both axes so a transposed or halved sum cannot pass.
  const insets = EdgeInsets.only(left: 4, top: 10, right: 12, bottom: 22);

  test('no shadow leaves the constraints exactly as the call site wrote them',
      () {
    const card = BoxConstraints(maxWidth: 320, maxHeight: 400);
    expect(popupWindowConstraints(card, EdgeInsets.zero), card);
  });

  test('the default theme really does produce a margin to account for', () {
    // Guards the premise: if the shipped palette had no shadow, every test
    // below would be exercising a case the shell never reaches.
    expect(popupShadowInsets(const ThemeConfig()), isNot(EdgeInsets.zero));
  });

  test('a pinned width widens the window rather than narrowing the card', () {
    // The app directory's list — minWidth == maxWidth is what used to clamp the
    // surface to the card and push the card sideways inside it.
    const card = BoxConstraints(minWidth: 300, maxWidth: 300, maxHeight: 1200);
    final window = popupWindowConstraints(card, insets);

    expect(window.minWidth, 316);
    expect(window.maxWidth, 316);
    expect(window.maxHeight, 1232);
  });

  test('tight constraints grow on both axes', () {
    // The system monitor's popup, the one case that pins both.
    const card = BoxConstraints.tightFor(width: 420, height: 440);
    final window = popupWindowConstraints(card, insets);

    expect(window.minWidth, 436);
    expect(window.maxWidth, 436);
    expect(window.minHeight, 472);
    expect(window.maxHeight, 472);
  });

  test('an infinite maximum stays infinite', () {
    // The backend maps an infinite max onto its own _kMaxWindowDimensions;
    // adding to infinity would be the same value, but returning it unchanged is
    // what says "unbounded" rather than "unbounded plus a shadow".
    final window = popupWindowConstraints(const BoxConstraints(), insets);

    expect(window.maxWidth, double.infinity);
    expect(window.maxHeight, double.infinity);
    expect(window.minWidth, 16);
    expect(window.minHeight, 32);
  });

  test('the window can hold the card the popup actually lays out', () {
    // The property the whole thing exists for, stated end to end: whatever size
    // the card settles at under the call site's constraints, the padded box
    // around it has to satisfy the hints the window was given — otherwise GTK
    // clamps it and the card is drawn outside its own surface.
    for (final card in const [
      BoxConstraints(maxWidth: 320, maxHeight: 400),
      BoxConstraints(minWidth: 300, maxWidth: 300, maxHeight: 1200),
      BoxConstraints(
        minWidth: 160,
        maxWidth: 320,
        minHeight: 24,
        maxHeight: 600,
      ),
      BoxConstraints.tightFor(width: 420, height: 440),
    ]) {
      final window = popupWindowConstraints(card, insets);
      final sizes = [card.smallest, card.constrain(const Size(280, 190))];
      for (final content in sizes) {
        final padded = Size(
          content.width + insets.horizontal,
          content.height + insets.vertical,
        );
        expect(window.isSatisfiedBy(padded), isTrue,
            reason: '$card at $content -> $padded does not fit $window');
      }
    }
  });

  test('an attached popup\'s clamped insets grow the window by exactly them',
      () {
    // The joined side's inset is clamped to the gap, which makes the insets
    // asymmetric but changes nothing about the rule: the surface is the card
    // plus whatever margin the Padding actually laid out.
    const clamped = EdgeInsets.only(left: 16, right: 16, top: 0, bottom: 22);
    const card = BoxConstraints(minWidth: 300, maxWidth: 300, maxHeight: 1200);
    final window = popupWindowConstraints(card, clamped);
    expect(window.minWidth, 332);
    expect(window.maxWidth, 332);
    expect(window.maxHeight, 1222);
    // And it is still not the zero-inset short circuit, which would hand the
    // card's own constraints back and let GTK clamp the resize.
    expect(clamped, isNot(EdgeInsets.zero));
  });

  test('insets clamped all the way to zero hand the card back unchanged', () {
    // Only reachable from a shadow with no reach at all, and then the card's
    // own constraints are exactly right.
    expect(popupWindowConstraints(
            const BoxConstraints(maxWidth: 320), EdgeInsets.zero),
        const BoxConstraints(maxWidth: 320));
  });
}
