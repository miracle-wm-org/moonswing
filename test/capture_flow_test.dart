import 'package:flutter_test/flutter_test.dart';
import 'package:miracle/miracle.dart' show BaseNode;

import 'package:graceful_shell/capture/capture_flow.dart';
import 'package:graceful_shell/capture/capture_store.dart';
import 'package:graceful_shell/capture/selection_controller.dart';

/// A `GET_TREE` reply with one output and one workspace on it, focused or not.
BaseNode _tree({required bool focused, String connector = 'HDMI-1'}) =>
    BaseNode.fromJson({
      'type': 'root',
      'id': 1,
      'name': 'root',
      'rect': {'x': 0, 'y': 0, 'width': 1920, 'height': 1080},
      'nodes': [
        {
          'type': 'output',
          'id': 2,
          'name': connector,
          'rect': {'x': 0, 'y': 0, 'width': 1920, 'height': 1080},
          'active': true,
          'nodes': [
            {
              'type': 'workspace',
              'id': 3,
              'name': '1',
              'num': 1,
              'output': connector,
              'visible': true,
              'focused': focused,
              'rect': {'x': 0, 'y': 0, 'width': 1920, 'height': 1080},
              'nodes': <dynamic>[],
              'floating_nodes': <dynamic>[],
            },
          ],
        },
      ],
    });

/// Ask, wait for the surfaces to go, then capture.
void main() {
  const target =
      OutputCapture(connector: 'DP-1', outputSize: CaptureSize(1920, 1080));
  const noSettle = Duration.zero;

  ({CaptureStore store, List<CaptureNotice> notices}) buildStore() {
    final notices = <CaptureNotice>[];
    final store = CaptureStore.forTesting()
      ..notify = notices.add
      ..home = '/tmp/graceful-shell-test-home';
    store.connect = () => null;
    addTearDown(store.dispose);
    return (store: store, notices: notices);
  }

  test('nothing listening declines immediately and captures nothing', () async {
    // `RequestController`'s rule, and the one that keeps a headless run — or
    // this very test — from awaiting a window that will never appear.
    final controller = CaptureSelectionController.forTesting();
    addTearDown(controller.dispose);
    final (:store, :notices) = buildStore();

    await runCaptureFlow(
      CaptureKind.screenshot,
      SelectionMode.output,
      store: store,
      controller: controller,
      settle: noSettle,
    );

    expect(notices, isEmpty, reason: 'no shutter, so nothing to report');
    expect(store.error, isNull);
  });

  test('a cancelled selection does nothing at all', () async {
    final controller = CaptureSelectionController.forTesting();
    addTearDown(controller.dispose);
    controller.addListener(controller.cancel);
    final (:store, :notices) = buildStore();

    await runCaptureFlow(
      CaptureKind.screenshot,
      SelectionMode.area,
      store: store,
      controller: controller,
      settle: noSettle,
    );

    expect(notices, isEmpty);
  });

  test('an answered selection is handed to the shutter', () async {
    final controller = CaptureSelectionController.forTesting();
    addTearDown(controller.dispose);
    SelectionRequest? asked;
    controller.addListener(() {
      final pending = controller.pending;
      if (pending == null) return;
      asked = pending;
      controller.complete(target);
    });
    final (:store, :notices) = buildStore();

    await runCaptureFlow(
      CaptureKind.screenshot,
      SelectionMode.window,
      store: store,
      controller: controller,
      settle: noSettle,
    );

    expect(asked?.kind, CaptureKind.screenshot);
    expect(asked?.mode, SelectionMode.window);
    // There is no compositor behind a widget test, so the shutter fails — but
    // it *ran*, which is what this is pinning.
    expect(notices, hasLength(1));
    expect(notices.single.failed, isTrue);
  });

  test('a video selection starts a recording rather than a shutter', () async {
    final controller = CaptureSelectionController.forTesting();
    addTearDown(controller.dispose);
    controller.addListener(() {
      if (controller.pending != null) controller.complete(target);
    });
    final (:store, :notices) = buildStore();

    await runCaptureFlow(
      CaptureKind.video,
      SelectionMode.output,
      store: store,
      controller: controller,
      settle: noSettle,
    );

    expect(notices.single.summary, 'Recording failed');
    expect(store.recording, isFalse);
  });

  test('the settle is waited out before the shutter, not after the click',
      () async {
    // A layer-shell surface is not gone when its controller is destroyed, and
    // nothing in the stack reports when it is; the wait is what keeps the
    // dimmed selection surface out of the picture.
    final controller = CaptureSelectionController.forTesting();
    addTearDown(controller.dispose);
    controller.addListener(() {
      if (controller.pending != null) controller.complete(target);
    });
    final (:store, :notices) = buildStore();

    var settled = false;
    final flow = runCaptureFlow(
      CaptureKind.screenshot,
      SelectionMode.output,
      store: store,
      controller: controller,
      settle: const Duration(milliseconds: 40),
    ).then((_) => settled = true);

    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(notices, isEmpty, reason: 'still settling');
    expect(settled, isFalse);

    await flow;
    expect(notices, hasLength(1));
  });

  group('runScreenRecordingShortcut', () {
    /// A controller nothing may ask: it records that it was asked and backs
    /// out, so a test can tell "recorded without asking" from "put the picker
    /// up and then recorded".
    ({CaptureSelectionController controller, List<SelectionRequest> asked})
        watchfulController() {
      final asked = <SelectionRequest>[];
      final controller = CaptureSelectionController.forTesting();
      addTearDown(controller.dispose);
      controller.addListener(() {
        final pending = controller.pending;
        if (pending == null) return;
        asked.add(pending);
        controller.cancel();
      });
      return (controller: controller, asked: asked);
    }

    test('records the focused screen without asking which one', () async {
      final (:store, :notices) = buildStore();
      store.readTree = () async => _tree(focused: true);
      final (:controller, :asked) = watchfulController();

      await runScreenRecordingShortcut(
        store: store,
        controller: controller,
        settle: noSettle,
      );

      expect(asked, isEmpty, reason: 'the shortcut knows which screen it is');
      // There is no compositor behind a widget test, so the recording fails —
      // but it was *started*, which is what this is pinning.
      expect(notices.single.summary, 'Recording failed');
    });

    test('falls back to the picker when it cannot tell which screen', () async {
      final (:store, :notices) = buildStore();
      // Nothing focused, a tree that will not arrive, and a shell that is not
      // connected at all: three ways of not knowing, one answer.
      for (final source in <Future<BaseNode>? Function()>[
        () async => _tree(focused: false),
        () async => throw StateError('the socket went away'),
        () => null,
      ]) {
        store.readTree = source;
        final (:controller, :asked) = watchfulController();

        await runScreenRecordingShortcut(
          store: store,
          controller: controller,
          settle: noSettle,
        );

        expect(asked, hasLength(1));
        expect(asked.single.kind, CaptureKind.video);
        expect(asked.single.mode, SelectionMode.output);
      }
      // Every one of them was cancelled, and a cancelled selection captures
      // nothing at all.
      expect(notices, isEmpty);
    });

    test('nothing listening is not a recording of the wrong screen', () async {
      // `RequestController`'s first rule reaching this path: with no window to
      // put a picker in, the shortcut declines rather than picking a display.
      final (:store, :notices) = buildStore();
      store.readTree = () => null;
      final controller = CaptureSelectionController.forTesting();
      addTearDown(controller.dispose);

      await runScreenRecordingShortcut(
        store: store,
        controller: controller,
        settle: noSettle,
      );

      expect(notices, isEmpty);
      expect(store.recording, isFalse);
    });
  });
}
