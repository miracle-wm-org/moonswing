// The wait that keeps `gtk_widget_destroy` off a window Flutter is still
// rendering into. The real thing aborts the process rather than throwing (glib
// clears a mutex the raster thread holds), so there is nothing to catch and no
// way to assert on it from a widget test — what is pinned here is the loop.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:graceful_shell/popup.dart';

void main() {
  testWidgets('waits for the view to detach, then one more frame',
      (WidgetTester tester) async {
    var attached = true;
    var destroys = 0;
    WindowTeardown(
      viewAttached: () => attached,
      destroy: () => destroys++,
    ).start();

    await tester.pump();
    await tester.pump();
    expect(destroys, 0, reason: 'the view is still mounted');

    attached = false;
    await tester.pump();
    expect(destroys, 0, reason: 'the raster thread gets one frame of grace');

    await tester.pump();
    expect(destroys, 1);
  });

  testWidgets('destroys once, and start() is not re-entrant',
      (WidgetTester tester) async {
    var destroys = 0;
    final teardown = WindowTeardown(
      viewAttached: () => false,
      destroy: () => destroys++,
    );
    teardown.start();
    teardown.start();

    await tester.pump();
    await tester.pump();
    expect(destroys, 1);
    expect(teardown.isDone, isTrue);

    // Nothing further is scheduled, so a compositor-initiated destroy arriving
    // now cannot be answered with a second one from here.
    await tester.pump();
    await tester.pump();
    expect(destroys, 1);
  });

  testWidgets('destroys anyway once maxFrames is reached',
      (WidgetTester tester) async {
    var destroys = 0;
    WindowTeardown(
      viewAttached: () => true,
      destroy: () => destroys++,
      maxFrames: 3,
    ).start();

    await tester.pump();
    await tester.pump();
    expect(destroys, 0);

    await tester.pump();
    expect(destroys, 1, reason: 'a leaked window per close is worse');
  });

  testWidgets('hides up front, before any destroy', (WidgetTester tester) async {
    final calls = <String>[];
    var attached = true;
    WindowTeardown(
      viewAttached: () => attached,
      destroy: () => calls.add('destroy'),
      hide: () => calls.add('hide'),
    ).start();

    expect(calls, ['hide'], reason: 'the close is visually instant');

    attached = false;
    await tester.pump();
    await tester.pump();
    expect(calls, ['hide', 'destroy']);
  });

  testWidgets('no hide callback means no unmap', (WidgetTester tester) async {
    var destroys = 0;
    WindowTeardown(
      viewAttached: () => false,
      destroy: () => destroys++,
    ).start();
    await tester.pump();
    await tester.pump();
    expect(destroys, 1);
  });

  testWidgets('viewIsAttached sees a view the framework renders into',
      (WidgetTester tester) async {
    // Only the positive half is assertable here: the test binding registers a
    // RenderView for its implicit view up front, where the shell's popup views
    // are added and removed with the `View` widget the WindowEntry builds. The
    // negative half is what the teardown waits for, and it needs real windows.
    await tester.pumpWidget(const SizedBox());
    expect(viewIsAttached(tester.view), isTrue);
  });
}
