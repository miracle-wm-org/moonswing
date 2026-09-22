import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:moonswing/config.dart';
import 'package:moonswing/hover_region.dart';
import 'package:moonswing/overlay/settings/controls.dart';
import 'package:moonswing/scopes.dart';
import 'package:moonswing/theme/tokens.dart';

import 'tap_target.dart';

/// The house rule, pinned: a control's hover box and its tap box are one rect.
///
/// Every one of these passes a *centre* tap today, because the glyph or the label
/// sits at the centre and is the only render object accepting a hit. The corners
/// are what a `GestureDetector` at `deferToChild` gave away.
Widget _host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: ThemeScope(
        theme: const ThemeConfig(),
        child: Center(child: child),
      ),
    );

void main() {
  testWidgets('SettingsIconButton fires from every corner of its box',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(SettingsIconButton(
      icon: FontAwesomeIcons.pause,
      size: 11,
      onTap: () => taps++,
    )));

    expect(
      tester.getSize(find.byType(SettingsIconButton)),
      const Size(ShellSizes.iconButton, ShellSizes.iconButton),
    );
    await tapEveryCorner(tester, find.byType(SettingsIconButton));
    expect(taps, 4);
  });

  testWidgets('a dense SettingsIconButton is still a box, not a glyph',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(SettingsIconButton(
      icon: FontAwesomeIcons.xmark,
      size: 11,
      box: ShellSizes.iconButtonDense,
      onTap: () => taps++,
    )));

    expect(
      tester.getSize(find.byType(SettingsIconButton)),
      const Size(ShellSizes.iconButtonDense, ShellSizes.iconButtonDense),
    );
    await tapEveryCorner(tester, find.byType(SettingsIconButton));
    expect(taps, 4);
  });

  testWidgets('wherever the cursor is a pointer, a click lands',
      (tester) async {
    // The invariant stated directly. The reported symptom was exactly this
    // pair coming apart: the cursor changed over the whole 26-square box and
    // the click only landed over the 11px glyph in the middle of it.
    var taps = 0;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);

    await tester.pumpWidget(_host(SettingsIconButton(
      icon: FontAwesomeIcons.play,
      size: 11,
      onTap: () => taps++,
    )));

    final corner = tester.getRect(find.byType(SettingsIconButton)).topLeft +
        const Offset(2, 2);
    await mouse.moveTo(corner);
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );

    await tester.tapAt(corner);
    await tester.pump();
    expect(taps, 1);
  });

  // One row per shared control. A control added to `controls.dart` later is one
  // line here; that is the point of the table.
  final cases = <String, Widget Function(VoidCallback)>{
    'SettingsIconButton': (tap) =>
        SettingsIconButton(icon: FontAwesomeIcons.stop, onTap: tap),
    // A stadium: `BoxDecoration.hitTest` refuses the four corner wedges, so
    // a rounded decoration alone is not enough here.
    'SettingsToggle': (tap) =>
        SettingsToggle(value: false, onChanged: (_) => tap()),
    'SettingsOptionButton': (tap) =>
        SettingsOptionButton(label: 'Pill', selected: false, onTap: tap),
    'SettingsActionButton': (tap) =>
        SettingsActionButton(label: 'Apply', onTap: tap),
    'SettingsRescanButton': (tap) => SettingsRescanButton(onTap: tap),
    'SettingsAddButton': (tap) => SettingsAddButton(label: 'Add', onTap: tap),
  };

  cases.forEach((name, build) {
    testWidgets('$name fires from every corner', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(build(() => taps++)));
      await tapEveryCorner(tester, find.byType(HoverRegion));
      expect(taps, 4, reason: '$name lost its corners');
    });
  });

  testWidgets('a disabled action button refuses the tap but keeps the box',
      (tester) async {
    var taps = 0;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);

    await tester.pumpWidget(_host(SizedBox(
      width: 120,
      child: SettingsActionButton(
        label: 'Apply',
        enabled: false,
        onTap: () => taps++,
      ),
    )));

    await mouse.moveTo(tester.getCenter(find.byType(SettingsActionButton)));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.basic,
    );

    await tapEveryCorner(tester, find.byType(SettingsActionButton));
    expect(taps, 0);
  });
}
