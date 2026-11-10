import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonswing/modules/workspace_apps.dart';
import 'package:moonswing/modules/workspace_pod.dart';

import 'workspace_result.dart';

/// Pins the workspace row's pod: which dot it marks, the two options that
/// decide what each dot carries, and the render object that lays the dots out,
/// slides the selection between them and gives each one its whole slot to be
/// clicked in.
void main() {
  group('selectedWorkspaceIndex', () {
    test('marks the focused workspace when it is on this output', () {
      expect(
        selectedWorkspaceIndex([
          workspaceResult(num: 1, focused: false, visible: false),
          workspaceResult(num: 2, focused: true),
        ]),
        1,
      );
    });

    test('marks the one this output is showing when the focus is elsewhere',
        () {
      // `focused` is global: on the monitor without the focus, nothing on this
      // bar carries it, and the row must still say what the screen is on.
      expect(
        selectedWorkspaceIndex([
          workspaceResult(num: 1, focused: false, visible: false),
          workspaceResult(num: 2, focused: false, visible: true),
          workspaceResult(num: 3, focused: false, visible: false),
        ]),
        1,
      );
    });

    test('marks nothing when nothing is focused or shown', () {
      expect(
        selectedWorkspaceIndex([
          workspaceResult(num: 1, focused: false, visible: false),
        ]),
        isNull,
      );
      expect(selectedWorkspaceIndex(const []), isNull);
    });
  });

  group('WorkspacesConfig', () {
    test('shows labels and every workspace\'s apps by default', () {
      const config = WorkspacesConfig();
      expect(config.showLabels, isTrue);
      expect(config.selectedAppsOnly, isFalse);
      expect(WorkspacesConfig.fromMap(const {}).showLabels, isTrue);
      expect(WorkspacesConfig.fromMap(const {}).selectedAppsOnly, isFalse);
    });

    test('reads show_labels and selected_apps_only', () {
      final config = WorkspacesConfig.fromMap(const {
        'show_labels': false,
        'selected_apps_only': true,
      });
      expect(config.showLabels, isFalse);
      expect(config.selectedAppsOnly, isTrue);
    });

    test('a wrongly-typed value costs that key alone', () {
      final config = WorkspacesConfig.fromMap(const {
        'show_labels': 'no',
        'selected_apps_only': 3,
        'max_icons': 6,
      });
      expect(config.showLabels, isTrue);
      expect(config.selectedAppsOnly, isFalse);
      expect(config.maxIcons, 6);
    });
  });

  group('showsWorkspaceApps', () {
    test('every workspace shows its apps unless asked otherwise', () {
      const config = WorkspacesConfig();
      expect(showsWorkspaceApps(config, selected: true), isTrue);
      expect(showsWorkspaceApps(config, selected: false), isTrue);
    });

    test('selected_apps_only keeps them to the selected workspace', () {
      const config = WorkspacesConfig(selectedAppsOnly: true);
      expect(showsWorkspaceApps(config, selected: true), isTrue);
      expect(showsWorkspaceApps(config, selected: false), isFalse);
    });

    test('show_app_icons off shows none anywhere', () {
      const config =
          WorkspacesConfig(showAppIcons: false, selectedAppsOnly: true);
      expect(showsWorkspaceApps(config, selected: true), isFalse);
    });
  });

  test('the row signature moves with what a monitor is showing', () {
    // The selection follows `visible` on a monitor without the focus, so a
    // reply that changes only that must not be refused as nothing new.
    final before = workspaceRowSignature([
      workspaceResult(num: 1, focused: false, visible: true),
      workspaceResult(num: 2, focused: false, visible: false),
    ]);
    final after = workspaceRowSignature([
      workspaceResult(num: 1, focused: false, visible: false),
      workspaceResult(num: 2, focused: false, visible: true),
    ]);
    expect(after, isNot(before));
  });

  group('WorkspacePod', () {
    late AnimationController progress;

    setUp(() {
      progress = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 200),
        value: 1,
      );
    });

    tearDown(() => progress.dispose());

    Widget pod({
      required int? selected,
      Axis axis = Axis.horizontal,
      List<double> lengths = const [8, 8, 8],
      List<int>? taps,
      Color indicator = const Color(0xFFFF0000),
    }) =>
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: axis == Axis.horizontal ? 400 : 32,
              height: axis == Axis.horizontal ? 32 : 400,
              child: Align(
                alignment: Alignment.topLeft,
                child: WorkspacePod(
                  axis: axis,
                  selected: selected,
                  indicatorColor: indicator,
                  background: const Color(0xFF202020),
                  progress: progress,
                  curve: Curves.linear,
                  spacing: 4,
                  padding: 3,
                  children: [
                    for (final (i, length) in lengths.indexed)
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => taps?.add(i),
                        child: SizedBox(
                          width: axis == Axis.horizontal ? length : 8,
                          height: axis == Axis.horizontal ? 8 : length,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );

    RenderWorkspacePod renderPod(WidgetTester tester) =>
        tester.renderObject<RenderWorkspacePod>(find.byType(WorkspacePod));

    testWidgets('lays the dots out along the bar inside the pill',
        (tester) async {
      await tester.pumpWidget(pod(selected: 0, lengths: const [8, 20, 8]));
      final render = renderPod(tester);
      // 3 + 8 + 4 + 20 + 4 + 8 + 3 along; the bar's whole depth across.
      expect(render.size, const Size(50, 32));
      final dots = tester
          .renderObjectList<RenderBox>(find.byType(SizedBox))
          .where((box) => box.size.height == 8)
          .map((box) => box.localToGlobal(Offset.zero).dx)
          .toList();
      expect(dots, [3, 15, 39]);
    });

    testWidgets('runs down a side bar', (tester) async {
      await tester.pumpWidget(
          pod(selected: 0, axis: Axis.vertical, lengths: const [8, 8]));
      expect(renderPod(tester).size, const Size(32, 26));
    });

    testWidgets('slides the indicator from the old dot to the new one',
        (tester) async {
      await tester.pumpWidget(pod(selected: 0));
      final render = renderPod(tester);
      expect(render.debugIndicatorRect, const Rect.fromLTWH(3, 12, 8, 8));

      // The owner restarts the slide alongside the new selection.
      await tester.pumpWidget(pod(selected: 2));
      progress.forward(from: 0);
      await tester.pump();
      expect(render.debugIndicatorRect, const Rect.fromLTWH(3, 12, 8, 8));

      await tester.pump(const Duration(milliseconds: 100));
      // Halfway, on a linear curve: halfway between x 3 and x 27.
      expect(render.debugIndicatorRect!.left, closeTo(15, 0.01));

      await tester.pumpAndSettle();
      expect(render.debugIndicatorRect, const Rect.fromLTWH(27, 12, 8, 8));
      // And nothing keeps ticking once it has arrived.
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('a switch mid-slide carries on from where it is',
        (tester) async {
      await tester.pumpWidget(pod(selected: 0));
      final render = renderPod(tester);
      await tester.pumpWidget(pod(selected: 2));
      progress.forward(from: 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final midway = render.debugIndicatorRect!;

      await tester.pumpWidget(pod(selected: 1));
      progress.forward(from: 0);
      await tester.pump();
      // No jump back to dot 0 or ahead to dot 2.
      expect(render.debugIndicatorRect, midway);
      await tester.pumpAndSettle();
      expect(render.debugIndicatorRect, const Rect.fromLTWH(15, 12, 8, 8));
    });

    testWidgets('blends the colour when only the colour changes',
        (tester) async {
      await tester.pumpWidget(pod(selected: 1));
      final render = renderPod(tester);
      await tester.pumpWidget(
          pod(selected: 1, indicator: const Color(0xFF0000FF)));
      progress.forward(from: 0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final color = render.debugIndicatorColor!;
      expect(color.r, closeTo(0.5, 0.02));
      expect(color.b, closeTo(0.5, 0.02));
      await tester.pumpAndSettle();
      expect(render.debugIndicatorColor, const Color(0xFF0000FF));
    });

    testWidgets('draws no indicator with nothing selected', (tester) async {
      await tester.pumpWidget(pod(selected: null));
      expect(renderPod(tester).debugIndicatorRect, isNull);
    });

    testWidgets('a press anywhere in a dot\'s slot reaches that dot',
        (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(pod(selected: 0, taps: taps));
      // The pod's top-left corner, far outside the 8px dot it belongs to.
      await tester.tapAt(const Offset(0.5, 0.5));
      // The middle of the gap between dots 0 and 1, low in the bar, falls to 1.
      await tester.tapAt(const Offset(13.5, 30));
      // Past the last dot to the pod's far end.
      await tester.tapAt(const Offset(37.5, 1));
      expect(taps, [0, 1, 2]);
    });
  });
}
