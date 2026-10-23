// The order a theme switch that moves the panels' reach is applied in. What it
// prevents is the engine drawing a resized bar from a frame of the old size —
// three Glassy bars stacked down the screen on the way to Forest — which no
// widget test can see; what is pinned here is that a resize and a restyle
// never land in one frame.

import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/panel_reach.dart';
import 'package:moonswing/theme/surface_material.dart';
import 'package:moonswing/theme/theme_config.dart';

const _plain = ThemeConfig();
const _overgrown = ThemeConfig(
  panelFoliage: FoliageStyle.ivy,
  panelOverhang: 64,
);
const _recoloured = ThemeConfig(panelBackground: Color(0xFF102030));

void main() {
  late ThemeConfig target;
  late List<int> commits;
  late bool reached;
  late PanelReachSequencer sequencer;

  setUp(() {
    target = _plain;
    commits = [];
    reached = false;
  });

  PanelReachSequencer build({
    ThemeConfig initial = _plain,
    int maxFrames = 30,
  }) => sequencer = PanelReachSequencer(
    initial: initial,
    target: () => target,
    commit: commits.add,
    reached: () => reached,
    maxFrames: maxFrames,
  );

  testWidgets('a growing reach resizes first and restyles once laid out', (
    WidgetTester tester,
  ) async {
    build();
    expect(_overgrown.panelReach, 64);

    target = _overgrown;
    sequencer.update();
    expect(commits, [64]);
    expect(
      sequencer.shown.value,
      _plain,
      reason: 'the frame at the new size draws what the one before it drew',
    );

    await tester.pump();
    await tester.pump();
    expect(
      sequencer.shown.value,
      _plain,
      reason: 'the views have not laid out at the new depth yet',
    );

    reached = true;
    await tester.pump();
    expect(sequencer.shown.value, _overgrown);
    expect(commits, [64]);
    sequencer.dispose();
  });

  testWidgets('a shrinking reach restyles first and resizes a frame later', (
    WidgetTester tester,
  ) async {
    target = _overgrown;
    build(initial: _overgrown);
    expect(sequencer.committed, 64);

    target = _plain;
    sequencer.update();
    expect(sequencer.shown.value, _plain);
    expect(
      commits,
      isEmpty,
      reason: 'the restyle has to be drawn before the surface shrinks',
    );

    await tester.pump();
    expect(commits, [0]);
    expect(sequencer.committed, 0);
    sequencer.dispose();
  });

  testWidgets('a change that keeps the reach restyles at once', (
    WidgetTester tester,
  ) async {
    build();
    target = _recoloured;
    sequencer.update();
    expect(sequencer.shown.value, _recoloured);
    expect(commits, isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
    sequencer.dispose();
  });

  testWidgets('restyles anyway once maxFrames pass with no resize', (
    WidgetTester tester,
  ) async {
    build(maxFrames: 3);
    target = _overgrown;
    sequencer.update();

    await tester.pump();
    await tester.pump();
    expect(sequencer.shown.value, _plain);
    await tester.pump();
    expect(sequencer.shown.value, _overgrown);
    sequencer.dispose();
  });

  testWidgets('a switch back mid-grow ends on the latest theme', (
    WidgetTester tester,
  ) async {
    build();
    target = _overgrown;
    sequencer.update();
    expect(commits, [64]);

    // Back to a theme with nothing to hang before the surface has grown.
    target = _plain;
    sequencer.update();
    expect(commits, [64], reason: 'folded into the round under way');

    reached = true;
    await tester.pump();
    expect(
      sequencer.shown.value,
      _plain,
      reason: 'the theme the store holds now, never the one left behind',
    );
    await tester.pump();
    expect(commits, [64, 0]);
    sequencer.dispose();
  });

  testWidgets('a switch back mid-shrink needs no shrink first', (
    WidgetTester tester,
  ) async {
    target = _overgrown;
    build(initial: _overgrown);

    target = _plain;
    sequencer.update();
    expect(sequencer.shown.value, _plain);

    target = _overgrown;
    sequencer.update();
    await tester.pump();
    expect(commits, isEmpty, reason: 'the surface already reaches far enough');
    expect(sequencer.shown.value, _overgrown);
    sequencer.dispose();
  });

  testWidgets('nothing is committed after dispose', (
    WidgetTester tester,
  ) async {
    target = _overgrown;
    build(initial: _overgrown);
    target = _plain;
    sequencer.update();
    sequencer.dispose();

    await tester.pump();
    expect(commits, isEmpty);
  });
}
